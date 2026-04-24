#!/bin/bash
set -e

IP_ADDRESS=$(ifconfig | grep -E "inet\s" | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1)
if [ -z "$IP_ADDRESS" ]; then
  echo "Error: Could not detect IP address"
  exit 1
fi
echo "Detected IP address: $IP_ADDRESS"
if grep -q "DEV_IP=" .env; then
  sed -i '' "s/DEV_IP=.*/DEV_IP=$IP_ADDRESS/" .env
else
  echo "DEV_IP=$IP_ADDRESS" >> .env
fi

echo "Starting docker compose..."
docker compose up "$@"
