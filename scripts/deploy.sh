#!/bin/bash
# Deploy script - Copy project to remote server via SSH
# Usage: ./deploy.sh [user@host] [remote_path]
# Example: ./deploy.sh root@192.168.0.8 /opt/random-video-streamer

set -e

REMOTE_HOST="${1:-root@192.168.0.8}"
REMOTE_PATH="${2:-/opt/random-video-streamer}"

echo "Deploying Random Video Clips Streaming Server to $REMOTE_HOST"
echo "Remote path: $REMOTE_PATH"
echo ""

# Check if rsync is available (preferred) or use scp
if command -v rsync &> /dev/null; then
    echo "Using rsync..."
    rsync -avz --progress \
        --exclude '.git' \
        --exclude '__pycache__' \
        --exclude '*.pyc' \
        --exclude '.env' \
        --exclude 'data/' \
        --exclude '.DS_Store' \
        --exclude '*.log' \
        --exclude 'node_modules' \
        --exclude '.venv' \
        --exclude 'venv' \
        --exclude 'env' \
        ./ "$REMOTE_HOST:$REMOTE_PATH/"
else
    echo "Using scp (rsync not found)..."
    echo "Creating temporary archive..."
    tar -czf /tmp/random-video-streamer.tar.gz \
        --exclude='.git' \
        --exclude='__pycache__' \
        --exclude='*.pyc' \
        --exclude='.env' \
        --exclude='data' \
        --exclude='.DS_Store' \
        --exclude='*.log' \
        --exclude='node_modules' \
        --exclude='.venv' \
        --exclude='venv' \
        --exclude='env' \
        .
    
    echo "Copying archive to remote server..."
    scp /tmp/random-video-streamer.tar.gz "$REMOTE_HOST:/tmp/"
    
    echo "Extracting on remote server..."
    ssh "$REMOTE_HOST" "mkdir -p $REMOTE_PATH && cd $REMOTE_PATH && tar -xzf /tmp/random-video-streamer.tar.gz && rm /tmp/random-video-streamer.tar.gz"
    
    rm /tmp/random-video-streamer.tar.gz
fi

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Next steps on remote server:"
echo "  1. SSH to server: ssh $REMOTE_HOST"
echo "  2. Navigate to: cd $REMOTE_PATH"
echo "  3. Create .env file: cp .env.example .env"
echo "  4. Edit .env and set VIDEO_FOLDER"
echo "  5. Start: docker compose up -d"
