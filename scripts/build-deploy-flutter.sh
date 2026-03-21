#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# Unified Flutter Build Manager
# Replaces scattered build scripts with a single configurable engine.
# ==========================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/frontend-flutter"
CONFIG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/flutter_config.env"

# --- Default Arguments ---
ENV_TARGET=""
BUILD_TARGET=""
BUILD_ENGINE=""
SERVE=false
DEPLOY=false

# --- Parse args or prompt ---
if [[ $# -eq 0 ]]; then
  echo ""
  echo -e "\033[1;36m🎬 Flutter Client Builder\033[0m"
  echo "──────────────────────────────"
  echo -e "  \033[0;32m1)\033[0m Build Web  (Local Env) & Serve"
  echo -e "  \033[0;32m2)\033[0m Build APK  (Proxmox Env)"
  echo -e "  \033[0;32m3)\033[0m Build Web  (Proxmox Env) & Deploy to Proxmox"
  echo ""
  read -p "Select option [1-3] (default 1): " OPT
  OPT=${OPT:-1}
  
  case $OPT in
    1) ENV_TARGET="local"; BUILD_TARGET="web"; SERVE=true ;;
    2) ENV_TARGET="proxmox"; BUILD_TARGET="apk" ;;
    3) ENV_TARGET="proxmox"; BUILD_TARGET="web"; DEPLOY=true ;;
    *) echo "Invalid option"; exit 1 ;;
  esac
  
  echo ""
  read -t 5 -p "Use Docker for building? (y/n, default n): " USE_DOCKER || true
  USE_DOCKER=${USE_DOCKER:-n}
  if [[ "$USE_DOCKER" == "y" || "$USE_DOCKER" == "Y" ]]; then
    BUILD_ENGINE="docker"
  else
    BUILD_ENGINE="local"
  fi
  echo ""
else
  while [[ $# -gt 0 ]]; do
    case $1 in
      --env) ENV_TARGET="$2"; shift 2 ;;
      --target) BUILD_TARGET="$2"; shift 2 ;;
      --engine) BUILD_ENGINE="$2"; shift 2 ;;
      --serve) SERVE=true; shift 1 ;;
      --deploy) DEPLOY=true; shift 1 ;;
      *) echo "Unknown parameter $1"; exit 1 ;;
    esac
  done
  
  ENV_TARGET=${ENV_TARGET:-local}
  BUILD_TARGET=${BUILD_TARGET:-web}
  BUILD_ENGINE=${BUILD_ENGINE:-docker}
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "❌ Error: $CONFIG_FILE not found. Please create it at the repo root."
  exit 1
fi
source "$CONFIG_FILE"

# --- Extract variables based on ENV_TARGET ---
ENV_UPPER=$(echo "$ENV_TARGET" | tr '[:lower:]' '[:upper:]')

API_BASE_URL=$(eval echo \$${ENV_UPPER}_API_BASE_URL)
HLS_URL=$(eval echo \$${ENV_UPPER}_HLS_URL)
ENABLE_LIVE_STREAM=$(eval echo \$${ENV_UPPER}_ENABLE_LIVE_STREAM)
REFRESH_SECONDS=$(eval echo \$${ENV_UPPER}_REFRESH_SECONDS)

# Apply fallbacks
REFRESH_SECONDS=${REFRESH_SECONDS:-5}
ENABLE_LIVE_STREAM=${ENABLE_LIVE_STREAM:-false}

if [[ -z "$API_BASE_URL" || -z "$HLS_URL" ]]; then
  echo "❌ Error: ${ENV_UPPER}_API_BASE_URL and ${ENV_UPPER}_HLS_URL must be set in $CONFIG_FILE"
  exit 1
fi

DART_DEFINES="--dart-define=API_BASE_URL=$API_BASE_URL --dart-define=HLS_URL=$HLS_URL --dart-define=ENABLE_LIVE_STREAM=$ENABLE_LIVE_STREAM --dart-define=REFRESH_SECONDS=$REFRESH_SECONDS"

echo "=========================================================="
echo "🛠️  Building: Target=$BUILD_TARGET | Env=$ENV_TARGET | Engine=$BUILD_ENGINE"
echo "🌐 API: $API_BASE_URL | LiveStream: $ENABLE_LIVE_STREAM"
echo "=========================================================="

if [[ "$SERVE" == true || "$DEPLOY" == true ]]; then
  echo ""
  echo "=> Checking backend connectivity..."
  if ! curl -s -f --max-time 3 "$API_BASE_URL/api/status" > /dev/null; then
    echo -e "\033[1;31m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo -e "\033[1;31m❌ WARNING: Backend is NOT reachable at $API_BASE_URL\033[0m"
    echo -e "\033[1;31m   The Flutter app may fail to load chunks or live streams.\033[0m"
    echo -e "\033[1;31m   Ensure 'docker-compose up' is running for this environment.\033[0m"
    echo -e "\033[1;31m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    echo ""
    sleep 3
  else
    echo -e "\033[0;32m✅ Backend is online!\033[0m"
    echo ""
  fi
fi

if [[ "$BUILD_TARGET" == "web" ]]; then
  FLUTTER_CMD="flutter build web --release $DART_DEFINES"
elif [[ "$BUILD_TARGET" == "apk" ]]; then
  FLUTTER_CMD="flutter build apk --release $DART_DEFINES"
elif [[ "$BUILD_TARGET" == "aab" ]]; then
  FLUTTER_CMD="flutter build appbundle --release $DART_DEFINES"
else
  echo "❌ Invalid target: $BUILD_TARGET"
  exit 1
fi

# --- Run Build Engine ---
if [[ "$BUILD_ENGINE" == "local" ]]; then
  echo "=> Executing local flutter binary..."
  cd "$APP_DIR"
  
  if [[ ! -d "android" || ! -d "web" ]]; then
    flutter create --platforms=android,web .
  fi
  flutter pub get
  eval "$FLUTTER_CMD"
  
  if [[ "$BUILD_TARGET" == "apk" || "$BUILD_TARGET" == "aab" ]]; then
    mkdir -p dist/android
    cp build/app/outputs/flutter-apk/app-release.apk dist/android/random-video-streamer-release.apk 2>/dev/null || true
    cp build/app/outputs/bundle/release/app-release.aab dist/android/random-video-streamer-release.aab 2>/dev/null || true
  fi

elif [[ "$BUILD_ENGINE" == "docker" ]]; then
  echo "=> Executing dockerized flutter image..."
  HOST_UID="$(id -u)"
  HOST_GID="$(id -g)"
  
  if [[ "$BUILD_TARGET" == "apk" || "$BUILD_TARGET" == "aab" ]]; then
    COPY_CMD="mkdir -p dist/android && cp build/app/outputs/flutter-apk/app-release.apk dist/android/random-video-streamer-release.apk 2>/dev/null || cp build/app/outputs/bundle/release/app-release.aab dist/android/random-video-streamer-release.aab 2>/dev/null || true"
  else
    COPY_CMD="true"
  fi
  
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
      $FLUTTER_CMD &&
      $COPY_CMD &&
      chown -R $HOST_UID:$HOST_GID /app/build /app/dist /app/.dart_tool /app/.flutter-plugins* 2>/dev/null || true
    "
else
  echo "❌ Invalid engine: $BUILD_ENGINE"
  exit 1
fi

echo "✅ Build completed for $BUILD_TARGET ($ENV_TARGET)!"

# ----------------------------------------------------------
# Post-Build Steps (Serve & Deploy)
# ----------------------------------------------------------

if [[ "$SERVE" == true && "$BUILD_TARGET" == "web" ]]; then
  PREVIEW_PORT=$(eval echo \$${ENV_UPPER}_PREVIEW_PORT)
  PREVIEW_PORT=${PREVIEW_PORT:-8090}
  
  echo ""
  echo "🌐 Starting Local Server on http://localhost:$PREVIEW_PORT"
  echo "   (Press Ctrl+C to stop)"
  
  if [[ "$BUILD_ENGINE" == "docker" ]]; then
    docker run --rm -it -p "$PREVIEW_PORT:80" -v "$APP_DIR/build/web:/usr/share/nginx/html:ro" nginx:alpine
  else
    cd "$APP_DIR/build/web"
    python3 -m http.server "$PREVIEW_PORT" --bind 0.0.0.0
  fi
fi

if [[ "$DEPLOY" == true && "$BUILD_TARGET" == "web" ]]; then
  SSH_HOST=$(eval echo \$${ENV_UPPER}_SSH_HOST)
  REMOTE_WEB_DIR=$(eval echo \$${ENV_UPPER}_REMOTE_WEB_DIR)
  UI_CONTAINER=$(eval echo \$${ENV_UPPER}_UI_CONTAINER)
  UI_PORT=$(eval echo \$${ENV_UPPER}_UI_PORT)
  
  if [[ -z "$SSH_HOST" || -z "$REMOTE_WEB_DIR" ]]; then
    echo "❌ Error: Must specify ${ENV_UPPER}_SSH_HOST and ${ENV_UPPER}_REMOTE_WEB_DIR in config for deployment."
    exit 1
  fi
  
  echo ""
  echo "🚀 Deploying to $SSH_HOST..."
  ssh "$SSH_HOST" "mkdir -p \"$REMOTE_WEB_DIR\""
  rsync -avz --delete "$APP_DIR/build/web/" "$SSH_HOST:$REMOTE_WEB_DIR/"
  
  if [[ -n "$UI_CONTAINER" && -n "$UI_PORT" ]]; then
    echo "🔄 Restarting Nginx container ($UI_CONTAINER)..."
    ssh "$SSH_HOST" "docker rm -f \"$UI_CONTAINER\" >/dev/null 2>&1 || true; docker run -d --name \"$UI_CONTAINER\" --restart unless-stopped -p \"$UI_PORT:80\" -v \"$REMOTE_WEB_DIR:/usr/share/nginx/html:ro\" nginx:alpine >/dev/null"
  fi
  echo "🎉 Deployment Success! UI live at http://${SSH_HOST##*@}:$UI_PORT"
fi
