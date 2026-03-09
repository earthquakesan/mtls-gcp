#!/bin/bash

# Configuration
PROJECT_ID=$(gcloud config get-value project)
REGION=${REGION:-europe-west3}
ZONE=${ZONE:-europe-west3-a}
# Configurable zones: europe-west3-a,europe-west3-b,europe-west3-c
# If empty, GKE Autopilot will use all available zones in the region.
ZONES=${ZONES:-""}

VPC_NAME="mtls-demo-vpc"
SUBNET_NAME="mtls-lb-subnet"
SUBNET_RANGE="10.0.0.0/24"
PROXY_SUBNET_NAME="proxy-only-subnet"
PROXY_SUBNET_RANGE="10.129.0.0/23"

CLUSTER_NAME="mtls-gke-cluster"
LB_NAME="mtls-internal-l7-lb"
IP_NAME="mtls-lb-static-ip"
LB_IP="10.0.0.10"
HEALTH_CHECK_NAME="mtls-hc"
BACKEND_SERVICE_NAME="mtls-backend"
URL_MAP_NAME="mtls-url-map"
TARGET_HTTPS_PROXY_NAME="mtls-target-proxy"
FORWARDING_RULE_NAME="mtls-forwarding-rule"

TRUST_CONFIG_NAME="mtls-trust-config"
SERVER_TLS_POLICY_NAME="mtls-server-tls-policy"
SERVER_CERT_NAME="mtls-server-cert"

VM_NAME="mtls-test-client"

echo "Using Project ID: $PROJECT_ID"
echo "Region: $REGION"

# 1. Enable APIs
echo "Enabling necessary APIs..."
gcloud services enable \
    compute.googleapis.com \
    container.googleapis.com \
    networkservices.googleapis.com \
    certificatemanager.googleapis.com \
    networksecurity.googleapis.com

# 2. Create VPC and Subnets
echo "Creating VPC and Subnets..."
if ! gcloud compute networks describe $VPC_NAME --quiet > /dev/null 2>&1; then
    gcloud compute networks create $VPC_NAME --subnet-mode=custom
fi

if ! gcloud compute networks subnets describe $SUBNET_NAME --region=$REGION --quiet > /dev/null 2>&1; then
    gcloud compute networks subnets create $SUBNET_NAME \
        --network=$VPC_NAME \
        --range=$SUBNET_RANGE \
        --region=$REGION
fi

# Proxy-only subnet for Regional Internal HTTP(S) LB
if ! gcloud compute networks subnets describe $PROXY_SUBNET_NAME --region=$REGION --quiet > /dev/null 2>&1; then
    gcloud compute networks subnets create $PROXY_SUBNET_NAME \
        --purpose=REGIONAL_MANAGED_PROXY \
        --role=ACTIVE \
        --network=$VPC_NAME \
        --range=$PROXY_SUBNET_RANGE \
        --region=$REGION
fi

# 3. Create Firewall Rules
echo "Creating Firewall rules..."
# Allow SSH via IAP
if ! gcloud compute firewall-rules describe allow-ssh-iap --quiet > /dev/null 2>&1; then
    gcloud compute firewall-rules create allow-ssh-iap \
        --network=$VPC_NAME \
        --allow=tcp:22 \
        --source-ranges=35.235.240.0/20 \
        --description="Allow SSH from IAP"
fi

# Allow Health Checks
if ! gcloud compute firewall-rules describe allow-lb-health-check --quiet > /dev/null 2>&1; then
    gcloud compute firewall-rules create allow-lb-health-check \
        --network=$VPC_NAME \
        --action=allow \
        --direction=ingress \
        --source-ranges=130.211.0.0/22,35.191.0.0/16 \
        --rules=tcp:80,tcp:443 \
        --description="Allow Health Checks from GCP"
fi

# Allow Proxy-only Subnet
if ! gcloud compute firewall-rules describe allow-proxy-only-subnet --quiet > /dev/null 2>&1; then
    gcloud compute firewall-rules create allow-proxy-only-subnet \
        --network=$VPC_NAME \
        --action=allow \
        --direction=ingress \
        --source-ranges=$PROXY_SUBNET_RANGE \
        --rules=tcp:80,tcp:443,tcp:8080 \
        --description="Allow traffic from proxy-only subnet"
fi

# 4. Create Regional GKE Autopilot Cluster
echo "Creating GKE Autopilot cluster..."
if ! gcloud container clusters describe $CLUSTER_NAME --region=$REGION --quiet > /dev/null 2>&1; then
    gcloud container clusters create-auto $CLUSTER_NAME \
        --region=$REGION \
        --network=$VPC_NAME \
        --subnetwork=$SUBNET_NAME \
        ${ZONES:+--node-locations=$ZONES} \
        --async
else
    echo "Cluster $CLUSTER_NAME already exists."
fi

# 5. Reserve Static Internal IP
echo "Reserving static internal IP..."
if ! gcloud compute addresses describe $IP_NAME --region=$REGION --quiet > /dev/null 2>&1; then
    gcloud compute addresses create $IP_NAME \
        --region=$REGION \
        --subnet=$SUBNET_NAME \
        --purpose=GCE_ENDPOINT \
        --addresses=$LB_IP
else
    echo "Static IP $IP_NAME already exists."
fi

# 6. Create Health Check & Backend Service
echo "Configuring Load Balancer base..."
if ! gcloud compute health-checks describe $HEALTH_CHECK_NAME --region=$REGION --quiet > /dev/null 2>&1; then
    gcloud compute health-checks create http $HEALTH_CHECK_NAME \
        --region=$REGION \
        --use-serving-port \
        --request-path=/healthz
else
    echo "Updating health check $HEALTH_CHECK_NAME to use /healthz..."
    gcloud compute health-checks update http $HEALTH_CHECK_NAME \
        --region=$REGION \
        --request-path=/healthz
fi

if ! gcloud compute backend-services describe $BACKEND_SERVICE_NAME --region=$REGION --quiet > /dev/null 2>&1; then
    gcloud compute backend-services create $BACKEND_SERVICE_NAME \
        --load-balancing-scheme=INTERNAL_MANAGED \
        --protocol=HTTP \
        --health-checks=$HEALTH_CHECK_NAME \
        --health-checks-region=$REGION \
        --region=$REGION \
        --custom-request-header='X-Client-Cert-Fingerprint:{client_cert_sha256_fingerprint}'
else
    echo "Backend service $BACKEND_SERVICE_NAME already exists. Updating custom headers..."
    gcloud compute backend-services update $BACKEND_SERVICE_NAME \
        --region=$REGION \
        --custom-request-header='X-Client-Cert-Fingerprint:{client_cert_sha256_fingerprint}'
fi

# Note: NEGs will be attached later in K8s config.

# 7. Setup mTLS Configuration
echo "Setting up mTLS configuration (requires root-ca.pem for TrustConfig)..."
if [ -f "certs/root-ca.pem" ]; then
    # Setup Trust Config
    if ! gcloud certificate-manager trust-configs describe $TRUST_CONFIG_NAME --location=$REGION --quiet > /dev/null 2>&1; then
        echo "Creating Trust Config..."
        gcloud certificate-manager trust-configs create $TRUST_CONFIG_NAME \
            --trust-store=trust-anchors=certs/root-ca.pem \
            --location=$REGION --quiet
    else
        echo "Updating Trust Config..."
        gcloud certificate-manager trust-configs update $TRUST_CONFIG_NAME \
            --trust-store=trust-anchors=certs/root-ca.pem \
            --location=$REGION --quiet
    fi
   
    # Create Server TLS Policy
    if ! gcloud network-security server-tls-policies describe $SERVER_TLS_POLICY_NAME --location=$REGION --quiet > /dev/null 2>&1; then
        echo "Importing Server TLS Policy..."
        cat > server-tls-policy.yaml <<EOF
description: "mTLS policy for internal L7 LB"
mtlsPolicy:
  clientValidationMode: REJECT_INVALID
  clientValidationTrustConfig: projects/$PROJECT_ID/locations/$REGION/trustConfigs/$TRUST_CONFIG_NAME
EOF
        gcloud network-security server-tls-policies import $SERVER_TLS_POLICY_NAME \
            --source=server-tls-policy.yaml \
            --location=$REGION --quiet
        rm server-tls-policy.yaml
    else
        echo "Server TLS Policy $SERVER_TLS_POLICY_NAME already exists. (Updating policies is usually done via import)"
        cat > server-tls-policy.yaml <<EOF
description: "mTLS policy for internal L7 LB"
mtlsPolicy:
  clientValidationMode: REJECT_INVALID
  clientValidationTrustConfig: projects/$PROJECT_ID/locations/$REGION/trustConfigs/$TRUST_CONFIG_NAME
EOF
        gcloud network-security server-tls-policies import $SERVER_TLS_POLICY_NAME \
            --source=server-tls-policy.yaml \
            --location=$REGION --quiet
        rm server-tls-policy.yaml
    fi
else
    echo "WARNING: certs/root-ca.pem not found. skipping TrustConfig and ServerTlsPolicy creation."
fi

# 8. URL Map & Target HTTPS Proxy
echo "Creating URL Map and Target HTTPS Proxy..."
if ! gcloud compute url-maps describe $URL_MAP_NAME --region=$REGION --quiet > /dev/null 2>&1; then
    gcloud compute url-maps create $URL_MAP_NAME \
        --default-service=$BACKEND_SERVICE_NAME \
        --region=$REGION
fi

# Target HTTPS Proxy
if ! gcloud compute target-https-proxies describe $TARGET_HTTPS_PROXY_NAME --region=$REGION --quiet > /dev/null 2>&1; then
    gcloud compute target-https-proxies create $TARGET_HTTPS_PROXY_NAME \
        --url-map=$URL_MAP_NAME \
        --region=$REGION \
        --certificate-manager-certificates=$SERVER_CERT_NAME \
        --server-tls-policy=$SERVER_TLS_POLICY_NAME
fi

# 9. Create Forwarding Rule
echo "Creating Forwarding Rule..."
if ! gcloud compute forwarding-rules describe $FORWARDING_RULE_NAME --region=$REGION --quiet > /dev/null 2>&1; then
    gcloud compute forwarding-rules create $FORWARDING_RULE_NAME \
        --load-balancing-scheme=INTERNAL_MANAGED \
        --network=$VPC_NAME \
        --subnet=$SUBNET_NAME \
        --address=$IP_NAME \
        --ports=443 \
        --target-https-proxy=$TARGET_HTTPS_PROXY_NAME \
        --target-https-proxy-region=$REGION \
        --region=$REGION
fi

# 10. Provision Test VM
echo "Provisioning Test VM..."
if ! gcloud compute instances describe $VM_NAME --zone=$ZONE --quiet > /dev/null 2>&1; then
    gcloud compute instances create $VM_NAME \
        --zone=$ZONE \
        --network=$VPC_NAME \
        --subnet=$SUBNET_NAME \
        --machine-type=e2-micro \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --metadata=startup-script="apt-get update && apt-get install -y curl"
else
    echo "VM $VM_NAME already exists."
fi

echo "Infrastructure provisioning complete (or already exists)."
echo "You can test mTLS from the VM using:"
echo "gcloud compute ssh $VM_NAME --zone=$ZONE --tunnel-through-iap"
echo "curl -v --cacert ~/certs/root-ca.pem --cert ~/certs/client1.pem --key ~/certs/client1.key https://$LB_IP"
