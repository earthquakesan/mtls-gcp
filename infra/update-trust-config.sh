#!/bin/bash

# Configuration
PROJECT_ID=$(gcloud config get-value project)
REGION=${REGION:-europe-west3}
TRUST_CONFIG_NAME="mtls-trust-config"
ROOT_CA_PATH="certs/root-ca.pem"

if [ ! -f "$ROOT_CA_PATH" ]; then
    echo "ERROR: Root CA file not found at $ROOT_CA_PATH"
    exit 1
fi

echo "Updating Trust Config '$TRUST_CONFIG_NAME' in $REGION with new Root CA..."

# Update the trust-store with the new PEM file
gcloud certificate-manager trust-configs update $TRUST_CONFIG_NAME \
    --location=$REGION \
    --trust-store=trust-anchors=$ROOT_CA_PATH \
    --quiet

echo "Trust Config update operation submitted."
echo "Waiting for Trust Config to return to ACTIVE state..."

while [[ $(gcloud certificate-manager trust-configs describe $TRUST_CONFIG_NAME --location=$REGION --format="value(state)" 2>/dev/null) != "ACTIVE" ]]; do
    echo "Trust Config is still updating... (Current state: $(gcloud certificate-manager trust-configs describe $TRUST_CONFIG_NAME --location=$REGION --format="value(state)" 2>/dev/null))"
    sleep 5
done

echo "Update complete. Trust Config is now ACTIVE."
echo "Note: It may take up to 10-15 minutes for the change to propagate to all Load Balancer proxies."
