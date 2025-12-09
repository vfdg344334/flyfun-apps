#!/bin/bash
# Build script for Docker images
# Ensures base image is built first before dependent images

set -e

echo "Building base image..."
docker-compose build base

echo "Building web-server and mcp-server..."
docker-compose build web-server mcp-server

echo "All images built successfully!"

