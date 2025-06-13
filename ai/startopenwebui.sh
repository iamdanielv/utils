#!/bin/bash

# Start OpenWebUI using docker compose in detached mode

clear

echo -e "\n\033[1;34mStarting OpenWebUI...\033[0m"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "\n\033[1;35m❌ Error: Docker is not installed. Please install Docker first.\033[0m\n"
    exit 1
fi

if ! docker compose up -d; then
    echo -e "\n\033[1;35m❌ Error: Failed to start containers\033[0m\n"
    exit 1
fi

echo -e "\n\033[1;32m✅ OpenWebUI started successfully!\033[0m"
echo -e "\n🌐 Access at: http://localhost:8080"

exit 0
