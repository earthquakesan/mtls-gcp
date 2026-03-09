#!/bin/bash

# Configuration
PROJECT_ID=$(gcloud config get-value project)
REGION=${REGION:-europe-west3}
SERVER_CERT_NAME="mtls-server-cert"
TRUST_CONFIG_NAME="mtls-trust-config"

# Directory for certificates
CERT_DIR="./certs"
mkdir -p $CERT_DIR

echo "Generating certificates in $CERT_DIR..."

# 1. Generate Root CA
echo "Step 1: Generating Root CA..."
openssl genrsa -out $CERT_DIR/root-ca.key 4096

# Create Root CA config for extensions
cat > $CERT_DIR/root-ca.ext <<EOF
[ v3_ca ]
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer
basicConstraints=critical,CA:TRUE
keyUsage=critical,digitalSignature,cRLSign,keyCertSign
EOF

openssl req -x509 -new -nodes -key $CERT_DIR/root-ca.key -sha256 -days 3650 \
    -out $CERT_DIR/root-ca.pem \
    -subj "/C=DE/ST=Berlin/L=Berlin/O=Demo Root CA Inc/CN=mtls-demo-root-ca" \
    -config <(cat /etc/ssl/openssl.cnf <(echo "[req]"; echo "distinguished_name=dn"; echo "[dn]"; echo "[v3_ca]"; cat $CERT_DIR/root-ca.ext)) \
    -extensions v3_ca

# Copy root-ca.pem to infra directory so provision.sh can find it
cp $CERT_DIR/root-ca.pem ./infra/root-ca.pem

# 2. Generate 3 Client Certificates
echo "Step 2: Generating 3 Client Certificates..."

# Create Client Extension config
cat > $CERT_DIR/client.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
subjectKeyIdentifier = hash
EOF

# Initialize Fingerprints.md
echo "# Client Certificate Fingerprints" > Fingerprints.md
echo "| Client | CN | Fingerprint (SHA256) |" >> Fingerprints.md
echo "| :--- | :--- | :--- |" >> Fingerprints.md

# Client 1: Alice Smith
openssl genrsa -out $CERT_DIR/client1.key 2048
openssl req -new -key $CERT_DIR/client1.key -out $CERT_DIR/client1.csr \
    -subj "/C=DE/ST=Berlin/L=Berlin/O=User Group A/CN=alice.smith@example.com"
openssl x509 -req -in $CERT_DIR/client1.csr -CA $CERT_DIR/root-ca.pem -CAkey $CERT_DIR/root-ca.key \
    -CAcreateserial -out $CERT_DIR/client1.pem -days 365 -sha256 -extfile $CERT_DIR/client.ext
# Add to Fingerprints.md
FP1=$(openssl x509 -noout -fingerprint -sha256 -in $CERT_DIR/client1.pem | cut -d'=' -f2)
echo "| Client 1 | alice.smith@example.com | $FP1 |" >> Fingerprints.md

# Client 2: Bob Jones
openssl genrsa -out $CERT_DIR/client2.key 2048
openssl req -new -key $CERT_DIR/client2.key -out $CERT_DIR/client2.csr \
    -subj "/C=DE/ST=Bavaria/L=Munich/O=User Group B/CN=bob.jones@example.com"
openssl x509 -req -in $CERT_DIR/client2.csr -CA $CERT_DIR/root-ca.pem -CAkey $CERT_DIR/root-ca.key \
    -CAcreateserial -out $CERT_DIR/client2.pem -days 365 -sha256 -extfile $CERT_DIR/client.ext
# Add to Fingerprints.md
FP2=$(openssl x509 -noout -fingerprint -sha256 -in $CERT_DIR/client2.pem | cut -d'=' -f2)
echo "| Client 2 | bob.jones@example.com | $FP2 |" >> Fingerprints.md

# Client 3: Charlie Brown
openssl genrsa -out $CERT_DIR/client3.key 2048
openssl req -new -key $CERT_DIR/client3.key -out $CERT_DIR/client3.csr \
    -subj "/C=DE/ST=Hamburg/L=Hamburg/O=User Group C/CN=charlie.brown@example.com"
openssl x509 -req -in $CERT_DIR/client3.csr -CA $CERT_DIR/root-ca.pem -CAkey $CERT_DIR/root-ca.key \
    -CAcreateserial -out $CERT_DIR/client3.pem -days 365 -sha256 -extfile $CERT_DIR/client.ext
# Add to Fingerprints.md
FP3=$(openssl x509 -noout -fingerprint -sha256 -in $CERT_DIR/client3.pem | cut -d'=' -f2)
echo "| Client 3 | charlie.brown@example.com | $FP3 |" >> Fingerprints.md

# 3. Generate Server Certificate for the Load Balancer
echo "Step 3: Generating Server Certificate..."
openssl genrsa -out $CERT_DIR/server.key 2048
openssl req -new -key $CERT_DIR/server.key -out $CERT_DIR/server.csr \
    -subj "/C=DE/ST=Berlin/L=Berlin/O=Demo Infrastructure/CN=mtls-lb.example.com"

# Create a SAN (Subject Alternative Name) config for the server
cat > $CERT_DIR/server.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = mtls-lb.example.com
IP.1 = 10.0.0.10
EOF

openssl x509 -req -in $CERT_DIR/server.csr -CA $CERT_DIR/root-ca.pem -CAkey $CERT_DIR/root-ca.key \
    -CAcreateserial -out $CERT_DIR/server.pem -days 365 -sha256 -extfile $CERT_DIR/server.ext

# 4. Upload Server Certificate to GCP Certificate Manager
echo "Step 4: Uploading Server Certificate to GCP..."
if ! gcloud certificate-manager certificates describe $SERVER_CERT_NAME --location=$REGION --quiet > /dev/null 2>&1; then
    gcloud certificate-manager certificates create $SERVER_CERT_NAME \
        --certificate-file=$CERT_DIR/server.pem \
        --private-key-file=$CERT_DIR/server.key \
        --location=$REGION
else
    echo "Updating Certificate $SERVER_CERT_NAME in GCP..."
    gcloud certificate-manager certificates update $SERVER_CERT_NAME \
        --certificate-file=$CERT_DIR/server.pem \
        --private-key-file=$CERT_DIR/server.key \
        --location=$REGION
fi

echo "--------------------------------------------------"
echo "Certificates generated in $CERT_DIR"
echo "Root CA: root-ca.pem (Copied to ./infra/root-ca.pem)"
echo "Client 1: alice.smith@example.com"
echo "Client 2: bob.jones@example.com"
echo "Client 3: charlie.brown@example.com"
echo "Server Cert: mtls-lb.example.com (Uploaded to GCP as $SERVER_CERT_NAME)"
echo "--------------------------------------------------"
