#!/usr/bin/env bash
set -euo pipefail

# Build Flutter web app in Docker (no local Flutter SDK required).
# Usage:
#   scripts/flutter-web-build-docker.sh [API_BASE_URL] [HLS_URL] [serve]

DEFAULT_HOST="localhost"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/flutter_client"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

API_BASE_URL="${1:-http://$DEFAULT_HOST:8081}"
HLS_URL="${2:-http://$DEFAULT_HOST:8082/hls/stream.m3u8}"
SERVE_AFTER_BUILD="${3:-}"
PREVIEW_PORT="${PREVIEW_PORT:-8090}"
PREVIEW_BIND_IP="${PREVIEW_BIND_IP:-0.0.0.0}"
ENABLE_LIVE_STREAM="${ENABLE_LIVE_STREAM:-false}"

YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

printf "${RED}==============================================${NC}\n"
printf "${YELLOW}WARNING: default host is set to %s${NC}\n" "$DEFAULT_HOST"
printf "${YELLOW}Change DEFAULT_HOST if your backend runs elsewhere.${NC}\n"
printf "${RED}==============================================${NC}\n\n"

echo "Building Flutter web in Docker..."
echo "API_BASE_URL=$API_BASE_URL"
echo "HLS_URL=$HLS_URL"
echo "ENABLE_LIVE_STREAM=$ENABLE_LIVE_STREAM"

docker run --rm \
  -v "$APP_DIR:/app" \
  -w /app \
  ghcr.io/cirruslabs/flutter:stable \
  sh -lc "
    export HOME=/tmp &&
    git config --global --add safe.directory /sdks/flutter &&
    flutter config --enable-web &&
    flutter create --platforms=android,web . &&
    flutter pub get &&
    flutter build web --release \
      --dart-define=API_BASE_URL=$API_BASE_URL \
      --dart-define=HLS_URL=$HLS_URL \
      --dart-define=ENABLE_LIVE_STREAM=$ENABLE_LIVE_STREAM &&
    chown -R $HOST_UID:$HOST_GID /app/build /app/.dart_tool /app/.flutter-plugins* 2>/dev/null || true
  "

echo "Web build complete: flutter_client/build/web"

if [[ "$SERVE_AFTER_BUILD" == "serve" ]]; then
  echo "Starting preview server..."
  echo "Local URL: http://localhost:$PREVIEW_PORT"
  echo "Loopback:  http://127.0.0.1:$PREVIEW_PORT"
  echo "Press Ctrl+C to stop preview server."
  docker run --rm \
    -p "$PREVIEW_BIND_IP:$PREVIEW_PORT:80" \
    -v "$APP_DIR/build/web:/usr/share/nginx/html:ro" \
    nginx:alpine
fi
