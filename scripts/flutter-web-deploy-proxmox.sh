#!/usr/bin/env bash
set -euo pipefail

# One-command Flutter web deploy to Proxmox:
# 1) Build locally
# 2) Rsync build output to server
# 3) Restart nginx container serving static UI
#
# Usage:
#   scripts/flutter-web-deploy-proxmox.sh [API_BASE_URL] [HLS_URL]
#
# Optional env vars:
#   DEPLOY_HOST      (default from deploy/config or deploy/config.example)
#   DEPLOY_PATH      (default from deploy/config or deploy/config.example)
#   REMOTE_WEB_DIR   (default: $DEPLOY_PATH/flutter_web)
#   UI_CONTAINER     (default: flutter-ui)
#   UI_PORT          (default: 8090)
#   ENABLE_LIVE_STREAM (passed through to local build script)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$ROOT_DIR/deploy/config"
if [[ ! -f "$CONFIG_FILE" ]]; then
  CONFIG_FILE="$ROOT_DIR/deploy/config.example"
fi

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

DEPLOY_HOST="${DEPLOY_HOST:-}"
DEPLOY_PATH="${DEPLOY_PATH:-}"

if [[ -z "$DEPLOY_HOST" || -z "$DEPLOY_PATH" ]]; then
  echo "DEPLOY_HOST and DEPLOY_PATH are required."
  echo "Set them in deploy/config (preferred) or export env vars."
  exit 1
fi

API_BASE_URL="${1:-http://localhost:8081}"
HLS_URL="${2:-http://localhost:8082/hls/stream.m3u8}"
REMOTE_WEB_DIR="${REMOTE_WEB_DIR:-${DEPLOY_PATH%/}/flutter_web}"
UI_CONTAINER="${UI_CONTAINER:-flutter-ui}"
UI_PORT="${UI_PORT:-8090}"

echo "==> Step 1/3: Build Flutter web locally"
"$ROOT_DIR/scripts/flutter-web-build-local.sh" "$API_BASE_URL" "$HLS_URL"

echo "==> Step 2/3: Sync build/web to Proxmox"
ssh "$DEPLOY_HOST" "mkdir -p \"$REMOTE_WEB_DIR\""
rsync -avz --delete \
  "$ROOT_DIR/flutter_client/build/web/" \
  "$DEPLOY_HOST:$REMOTE_WEB_DIR/"

echo "==> Step 3/3: Restart nginx UI container on Proxmox"
ssh "$DEPLOY_HOST" "\
docker rm -f \"$UI_CONTAINER\" >/dev/null 2>&1 || true; \
docker run -d --name \"$UI_CONTAINER\" --restart unless-stopped \
  -p \"$UI_PORT:80\" \
  -v \"$REMOTE_WEB_DIR:/usr/share/nginx/html:ro\" \
  nginx:alpine >/dev/null"

echo "Done."
echo "UI URL: http://${DEPLOY_HOST##*@}:$UI_PORT"
