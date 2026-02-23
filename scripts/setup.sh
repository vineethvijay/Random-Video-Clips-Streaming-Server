#!/bin/bash
# Setup script for Random Video Clips Streaming Server

set -e

echo "Setting up Random Video Clips Streaming Server..."

# Check if .env exists
if [ ! -f .env ]; then
    echo "Creating .env from .env.example..."
    cp .env.example .env
    echo "Please edit .env and set VIDEO_FOLDER to your video directory path"
    exit 1
fi

# Create data directory
mkdir -p data

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed"
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "Error: Docker Compose is not installed"
    exit 1
fi

echo "Setup complete!"
echo ""
echo "Next steps:"
echo "1. Edit .env and set VIDEO_FOLDER to your video directory"
echo "2. Run: docker-compose up -d"
echo "3. Access stream at: http://localhost:8080/playlist.m3u8"
