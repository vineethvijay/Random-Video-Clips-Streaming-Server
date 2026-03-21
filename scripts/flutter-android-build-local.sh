#!/usr/bin/env bash
set -euo pipefail

# Build Flutter Android artifact locally (uses local Flutter SDK).
# Usage:
#   scripts/flutter-android-build-local.sh [apk|aab] [API_BASE_URL] [HLS_URL]

DEFAULT_HOST="localhost"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/flutter_client"
FLUTTER_BIN="${FLUTTER_BIN:-/Users/vineeth/flutter/flutter/bin}"

if [[ -x "$FLUTTER_BIN/flutter" ]]; then
  export PATH="$FLUTTER_BIN:$PATH"
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found. Set FLUTTER_BIN or add flutter to PATH."
  echo "Current FLUTTER_BIN: $FLUTTER_BIN"
  exit 1
fi

TARGET="${1:-apk}"
API_BASE_URL="${2:-http://$DEFAULT_HOST:8081}"
HLS_URL="${3:-http://$DEFAULT_HOST:8082/hls/stream.m3u8}"
ENABLE_LIVE_STREAM="${ENABLE_LIVE_STREAM:-false}"

if [[ "$TARGET" != "apk" && "$TARGET" != "aab" ]]; then
  echo "Invalid target '$TARGET'. Use 'apk' or 'aab'."
  exit 1
fi

if [[ "$TARGET" == "apk" ]]; then
  BUILD_CMD=(flutter build apk --release)
  SOURCE_ARTIFACT="build/app/outputs/flutter-apk/app-release.apk"
  TARGET_ARTIFACT="dist/android/random-video-streamer-release.apk"
else
  BUILD_CMD=(flutter build appbundle --release)
  SOURCE_ARTIFACT="build/app/outputs/bundle/release/app-release.aab"
  TARGET_ARTIFACT="dist/android/random-video-streamer-release.aab"
fi

YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

printf "${RED}==============================================${NC}\n"
printf "${YELLOW}WARNING: default host is set to %s${NC}\n" "$DEFAULT_HOST"
printf "${YELLOW}Change DEFAULT_HOST if your backend runs elsewhere.${NC}\n"
printf "${RED}==============================================${NC}\n\n"

echo "Building Flutter Android ($TARGET) locally..."
echo "Flutter binary: $(command -v flutter)"
echo "API_BASE_URL=$API_BASE_URL"
echo "HLS_URL=$HLS_URL"
echo "ENABLE_LIVE_STREAM=$ENABLE_LIVE_STREAM"

cd "$APP_DIR"

if [[ ! -d "android" || ! -d "web" ]]; then
  echo "Flutter platforms missing. Bootstrapping android/web..."
  flutter create --platforms=android,web .
fi

flutter pub get
"${BUILD_CMD[@]}" \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=HLS_URL="$HLS_URL" \
  --dart-define=ENABLE_LIVE_STREAM="$ENABLE_LIVE_STREAM"

mkdir -p "$(dirname "$TARGET_ARTIFACT")"
cp "$SOURCE_ARTIFACT" "$TARGET_ARTIFACT"

echo "Android build complete: flutter_client/$TARGET_ARTIFACT"
