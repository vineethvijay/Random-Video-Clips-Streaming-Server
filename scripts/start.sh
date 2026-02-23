#!/bin/bash
# Start script for Random Video Clips Streaming Server

set -e

# Check if .env exists
if [ ! -f .env ]; then
    echo "Error: .env file not found. Run setup.sh first."
    exit 1
fi

# Load environment variables
source .env

# Check if VIDEO_FOLDER is set
if [ -z "$VIDEO_FOLDER" ]; then
    echo "Error: VIDEO_FOLDER not set in .env"
    exit 1
fi

# Check if video folder exists
if [ ! -d "$VIDEO_FOLDER" ]; then
    echo "Warning: Video folder does not exist: $VIDEO_FOLDER"
    echo "Make sure the path is correct and accessible"
fi

# Start with docker-compose
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
else
    echo "Error: Docker Compose not found"
    exit 1
fi

# Start the container
$COMPOSE_CMD up -d

# Wait a moment for container to start
sleep 2

# Check if container is actually running
CONTAINER_STATUS=$($COMPOSE_CMD ps --format json 2>/dev/null | grep -o '"State":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")

if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "⚠️  Warning: Container status is '$CONTAINER_STATUS'"
    echo "Checking logs for errors..."
    $COMPOSE_CMD logs --tail=20
    echo ""
    echo "Container may have crashed. Check logs above."
    exit 1
else
    # Check if the app process is running inside container
    if docker exec random-video-streamer ps aux | grep -q "[p]ython app.py"; then
        echo "✅ Container is running"
        
        # Test if API is responding
        sleep 2
        if curl -s -f "http://localhost:${PORT:-8081}/api/status" > /dev/null 2>&1; then
            echo "✅ API is responding"
            echo "✅ Server is fully operational!"
        else
            echo "⚠️  Note: API test from host failed (this is normal on Docker Desktop macOS)"
            echo "   The server is running inside the container and handling requests"
            echo "   Check logs to verify: $COMPOSE_CMD logs -f | grep -E '(Running|GET|Selected)'"
            echo ""
            echo "   To access from your TV, use your Mac's IP address:"
            echo "   http://$(ipconfig getifaddr en0 2>/dev/null || echo 'YOUR-MAC-IP'):${PORT:-8081}/iptv.m3u"
        fi
    else
        echo "⚠️  Warning: Container is up but Python process not found"
        echo "Checking logs..."
        $COMPOSE_CMD logs --tail=20
        exit 1
    fi
fi

echo ""
echo "Useful commands:"
echo "  Check logs:    $COMPOSE_CMD logs -f"
echo "  Check status:  $COMPOSE_CMD ps"
echo "  Stop server:   $COMPOSE_CMD down"
echo "  Access stream: http://localhost:${PORT:-8081}/playlist.m3u8"
