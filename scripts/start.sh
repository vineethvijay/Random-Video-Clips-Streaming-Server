#!/bin/bash
# Start script for Random Video Clips Streaming Server

set -e

# Run from repo root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Check if .env exists
if [ ! -f .env ]; then
    echo "Error: .env file not found. Run setup.sh first."
    exit 1
fi

# Load environment variables
set -a
source .env
set +a

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

# Docker Compose command
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
else
    echo "Error: Docker Compose not found"
    exit 1
fi

# Colors (optional; strip if not a tty)
if [ -t 1 ]; then
    C="\033[0;36m"   # cyan
    G="\033[0;32m"   # green
    Y="\033[0;33m"   # yellow
    B="\033[1m"      # bold
    R="\033[0m"      # reset
else
    C= G= Y= B= R=
fi

# Ask what to do
echo ""
echo -e "${C}${B}🎬 Random Video Clips Streaming Server${R}"
echo -e "${C}─────────────────────────────────────────${R}"
echo ""
echo -e "  ${G}1)${R} 🔨  Rebuild and up    ${Y}(docker compose up -d --build)${R}"
echo -e "  ${G}2)${R} 🔄  Stop and up       ${Y}(docker compose down && docker compose up -d)${R}"
echo -e "  ${G}3)${R} ▶️   Simple up         ${Y}(docker compose up -d)${R}"
echo ""
read -p "$(echo -e ${Y}Choose [1-3] \(default 3\): ${R})" choice
choice="${choice:-3}"

case "$choice" in
    1)
        echo -e "\n${G}🔨 Rebuilding and starting...${R}\n"
        $COMPOSE_CMD up -d --build
        ;;
    2)
        echo -e "\n${G}🔄 Stopping, then starting...${R}\n"
        $COMPOSE_CMD down
        $COMPOSE_CMD up -d
        ;;
    3)
        echo -e "\n${G}▶️  Starting...${R}\n"
        $COMPOSE_CMD up -d
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

# Wait a moment for containers to start
sleep 2

# Check if containers are running
CONTAINER_STATUS=$($COMPOSE_CMD ps --format json 2>/dev/null | grep -o '"State":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")

if [ "$CONTAINER_STATUS" != "running" ]; then
    echo -e "${Y}⚠️  Warning: Container status is '$CONTAINER_STATUS'${R}"
    echo "Checking logs for errors..."
    $COMPOSE_CMD logs --tail=20
    echo ""
    echo "Container may have crashed. Check logs above."
    exit 1
else
    echo -e "\n${G}✅ Containers are running${R}"
    sleep 2
    if curl -s -f "http://localhost:${PORT:-8081}/api/status" > /dev/null 2>&1; then
        echo -e "${G}✅ API is responding — server is operational${R}"
    else
        echo -e "${Y}⚠️  API not responding yet (may need a few more seconds)${R}"
        echo "   Dashboard: http://localhost:${PORT:-8081}/"
        echo "   On macOS/Docker Desktop, use your Mac IP for TV: http://\$(ipconfig getifaddr en0 2>/dev/null || echo 'YOUR-IP'):${PORT:-8081}/iptv.m3u"
    fi
fi

echo ""
echo -e "${C}📋 Useful commands (copy as needed):${R}"
echo "  $COMPOSE_CMD logs -f"
echo "  $COMPOSE_CMD ps"
echo "  $COMPOSE_CMD down"
echo "  Dashboard:  http://localhost:${PORT:-8081}/"
echo "  HLS stream: http://localhost:${HLS_PORT:-8082}/hls/stream.m3u8"
