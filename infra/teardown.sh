#!/bin/bash

# Configuration
PROJECT_ID=$(gcloud config get-value project)
REGION=${REGION:-europe-west3}
ZONE=${ZONE:-europe-west3-a}

VPC_NAME="mtls-demo-vpc"
SUBNET_NAME="mtls-lb-subnet"
PROXY_SUBNET_NAME="proxy-only-subnet"

CLUSTER_NAME="mtls-gke-cluster"
LB_NAME="mtls-internal-l7-lb"
IP_NAME="mtls-lb-static-ip"
HEALTH_CHECK_NAME="mtls-hc"
BACKEND_SERVICE_NAME="mtls-backend"
URL_MAP_NAME="mtls-url-map"
TARGET_HTTPS_PROXY_NAME="mtls-target-proxy"
FORWARDING_RULE_NAME="mtls-forwarding-rule"

TRUST_CONFIG_NAME="mtls-trust-config"
SERVER_TLS_POLICY_NAME="mtls-server-tls-policy"

VM_NAME="mtls-test-client"

echo "Starting teardown of infrastructure in project: $PROJECT_ID, region: $REGION"

# 1. Delete Forwarding Rule (Depends on Target Proxy)
echo "Deleting Forwarding Rule..."
gcloud compute forwarding-rules delete $FORWARDING_RULE_NAME --region=$REGION --quiet || true

# 2. Delete Target HTTPS Proxy (Depends on URL Map, Server TLS Policy, and Server Certificate)
echo "Deleting Target HTTPS Proxy..."
gcloud compute target-https-proxies delete $TARGET_HTTPS_PROXY_NAME --region=$REGION --quiet || true

# 3. Delete URL Map (Depends on Backend Service)
echo "Deleting URL Map..."
gcloud compute url-maps delete $URL_MAP_NAME --region=$REGION --quiet || true

# 4. Delete Server TLS Policy (Depends on Trust Config)
echo "Deleting Server TLS Policy..."
gcloud network-security server-tls-policies delete $SERVER_TLS_POLICY_NAME --location=$REGION --quiet || true

# 5. Delete Trust Config
echo "Deleting Trust Config..."
gcloud certificate-manager trust-configs delete $TRUST_CONFIG_NAME --location=$REGION --quiet || true

# 6. Delete Backend Service (Depends on Health Check)
echo "Deleting Backend Service..."
gcloud compute backend-services delete $BACKEND_SERVICE_NAME --region=$REGION --quiet || true

# 7. Delete Health Check
echo "Deleting Health Check..."
gcloud compute health-checks delete $HEALTH_CHECK_NAME --region=$REGION --quiet || true

# 8. Delete Static IP
echo "Deleting Static IP..."
gcloud compute addresses delete $IP_NAME --region=$REGION --quiet || true

# 9. Delete Test VM
echo "Deleting Test VM..."
gcloud compute instances delete $VM_NAME --zone=$ZONE --quiet || true

# 10. Delete GKE Cluster
echo "Deleting GKE Cluster (this may take a while)..."
gcloud container clusters delete $CLUSTER_NAME --region=$REGION --quiet --async

# 11. Delete Server Certificate
echo "Deleting Server Certificate..."
gcloud certificate-manager certificates delete mtls-server-cert --location=$REGION --quiet || true

# 12. Delete Firewall Rules
echo "Deleting Firewall Rules..."
gcloud compute firewall-rules delete allow-ssh-iap --quiet || true

# 13. Delete Subnets and VPC
echo "Deleting Subnets..."
gcloud compute networks subnets delete $PROXY_SUBNET_NAME --region=$REGION --quiet || true
gcloud compute networks subnets delete $SUBNET_NAME --region=$REGION --quiet || true

echo "Deleting VPC..."
gcloud compute networks delete $VPC_NAME --quiet || true

echo "Teardown initiated. Note that the GKE cluster deletion is running asynchronously."
