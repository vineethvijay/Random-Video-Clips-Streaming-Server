#!/usr/bin/env bash
set -euo pipefail

# Build Flutter web app locally (uses local Flutter SDK).
# Usage:
#   scripts/flutter-web-build-local.sh [API_BASE_URL] [HLS_URL] [serve]

DEFAULT_HOST="localhost"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/flutter_client"

API_BASE_URL="${1:-http://$DEFAULT_HOST:8081}"
HLS_URL="${2:-http://$DEFAULT_HOST:8082/hls/stream.m3u8}"
SERVE_AFTER_BUILD="${3:-}"
ENABLE_LIVE_STREAM="${ENABLE_LIVE_STREAM:-false}"
PREVIEW_PORT="${PREVIEW_PORT:-8090}"
PREVIEW_HOST="${PREVIEW_HOST:-127.0.0.1}"

YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

printf "${RED}==============================================${NC}\n"
printf "${YELLOW}WARNING: default host is set to %s${NC}\n" "$DEFAULT_HOST"
printf "${YELLOW}Change DEFAULT_HOST if your backend runs elsewhere.${NC}\n"
printf "${RED}==============================================${NC}\n\n"

echo "Building Flutter web locally..."
echo "API_BASE_URL=$API_BASE_URL"
echo "HLS_URL=$HLS_URL"
echo "ENABLE_LIVE_STREAM=$ENABLE_LIVE_STREAM"

cd "$APP_DIR"

if [[ ! -d "android" || ! -d "web" ]]; then
  echo "Flutter platforms missing. Bootstrapping android/web..."
  flutter create --platforms=android,web .
fi

flutter pub get
flutter build web --release \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=HLS_URL="$HLS_URL" \
  --dart-define=ENABLE_LIVE_STREAM="$ENABLE_LIVE_STREAM"

echo "Web build complete: flutter_client/build/web"

if [[ "$SERVE_AFTER_BUILD" == "serve" ]]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required for local preview server."
    exit 1
  fi

  echo "Starting local preview server..."
  echo "Open: http://localhost:$PREVIEW_PORT"
  echo "Bind: $PREVIEW_HOST:$PREVIEW_PORT"
  echo "Press Ctrl+C to stop preview server."
  cd "$APP_DIR/build/web"
  python3 -m http.server "$PREVIEW_PORT" --bind "$PREVIEW_HOST"
fi
