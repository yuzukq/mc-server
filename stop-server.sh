#!/bin/bash
# Minecraft Server Shutdown Script with R2 Sync
# This script stops the server and uploads world data to R2

echo "========================================"
echo "Minecraft Server Shutdown (with R2 Sync)"
echo "========================================"
echo

cd "$(dirname "$0")"

echo "Stopping server..."
docker compose -f server001/compose.yml down

echo
echo "Uploading world data to R2 and releasing lock..."
docker compose -f server001/compose.yml run --rm sync-shutdown

if [ $? -eq 0 ]; then
    echo
    echo "========================================"
    echo "Server stopped successfully!"
    echo "World data uploaded to R2"
    echo "========================================"
    echo
else
    echo
    echo "[ERROR] Failed to sync data"
    echo "Please check the error messages above"
    echo
    exit 1
fi
