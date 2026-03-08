#!/bin/bash

# Configuration
PROJECT_ID=$(gcloud config get-value project)
REGION=${REGION:-europe-west3}
BACKEND_SERVICE_NAME="mtls-backend"
NEG_NAME="nginx-neg"

# Zones to check for NEGs
ZONES=("europe-west3-a" "europe-west3-b" "europe-west3-c")

echo "Configuring Backend Service '$BACKEND_SERVICE_NAME' to point to NEG '$NEG_NAME'..."

for ZONE in "${ZONES[@]}"; do
    echo "Checking for NEG '$NEG_NAME' in zone '$ZONE'..."
    
    # Check if NEG exists in this zone
    if gcloud compute network-endpoint-groups describe $NEG_NAME --zone=$ZONE --quiet > /dev/null 2>&1; then
        echo "NEG found in $ZONE. Attaching to backend service..."
        
        # Check if already attached to avoid errors
        if ! gcloud compute backend-services describe $BACKEND_SERVICE_NAME --region=$REGION --format="value(backends[].group)" | grep -q "$ZONE/networkEndpointGroups/$NEG_NAME"; then
            gcloud compute backend-services add-backend $BACKEND_SERVICE_NAME \
                --network-endpoint-group=$NEG_NAME \
                --network-endpoint-group-zone=$ZONE \
                --balancing-mode=RATE \
                --max-rate-per-endpoint=5 \
                --region=$REGION \
                --quiet
            echo "Successfully attached NEG in $ZONE."
        else
            echo "NEG in $ZONE is already attached."
        fi
    else
        echo "NEG not found in $ZONE (this is normal if no pods are running there yet)."
    fi
done

echo "Backend configuration complete."
