#!/bin/bash

# Configuration
LB_IP="10.0.0.10"
CERT_DIR="./certs"
INTERVAL=10

echo "Starting mTLS test loop against https://$LB_IP (Interval: ${INTERVAL}s)"
echo "Press [CTRL+C] to stop."
echo "--------------------------------------------------"

while true; do
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Run curl command
    # -s: Silent mode
    # -o /dev/null: Discard output body
    # -w: Print HTTP status code
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
        --cacert $CERT_DIR/root-ca.pem \
        --cert $CERT_DIR/client1.pem \
        --key $CERT_DIR/client1.key \
        https://$LB_IP 2>&1)
    
    CURL_EXIT_CODE=$?

    if [ $CURL_EXIT_CODE -eq 0 ]; then
        echo "[$TIMESTAMP] Status: $RESPONSE - Success"
    else
        echo "[$TIMESTAMP] Error: Curl exit code $CURL_EXIT_CODE (Handshake failure or reset likely)"
    fi

    sleep $INTERVAL
done
