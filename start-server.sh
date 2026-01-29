#!/bin/bash
# Minecraft Server Startup Script with R2 Sync
# This script starts the Minecraft server with automatic world sync

echo "========================================"
echo "Minecraft Server Startup (with R2 Sync)"
echo "========================================"
echo

cd "$(dirname "$0")"

# Check if .env file exists
if [ ! -f .env ]; then
    echo "[ERROR] .env file not found!"
    echo "Please copy .env.example to .env and configure your R2 credentials."
    echo
    exit 1
fi

echo "Starting server..."
echo

docker compose up -d

if [ $? -eq 0 ]; then
    echo
    echo "========================================"
    echo "Server started successfully!"
    echo "========================================"
    echo
    echo "To view logs: docker logs -f mc_server"
    echo "To stop server: ./stop-server.sh"
    echo
else
    echo
    echo "[ERROR] Failed to start server"
    echo "Check the error messages above"
    echo
    exit 1
fi
