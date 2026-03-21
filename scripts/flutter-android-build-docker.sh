#!/usr/bin/env bash
set -euo pipefail

# Build Flutter Android artifact in Docker.
# Usage:
#   scripts/flutter-android-build-docker.sh [apk|aab] [API_BASE_URL] [HLS_URL]

DEFAULT_HOST="localhost"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/frontend-flutter"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

TARGET="${1:-apk}"
API_BASE_URL="${2:-http://$DEFAULT_HOST:8081}"
HLS_URL="${3:-http://$DEFAULT_HOST:8082/hls/stream.m3u8}"
ENABLE_LIVE_STREAM="${ENABLE_LIVE_STREAM:-false}"

YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

printf "${RED}==============================================${NC}\n"
printf "${YELLOW}WARNING: default host is set to %s${NC}\n" "$DEFAULT_HOST"
printf "${YELLOW}Change DEFAULT_HOST if your backend runs elsewhere.${NC}\n"
printf "${RED}==============================================${NC}\n\n"

if [[ "$TARGET" != "apk" && "$TARGET" != "aab" ]]; then
  echo "Invalid target '$TARGET'. Use 'apk' or 'aab'."
  exit 1
fi

if [[ "$TARGET" == "apk" ]]; then
  BUILD_CMD="flutter build apk --release"
  ARTIFACT_IN_CONTAINER="build/app/outputs/flutter-apk/app-release.apk"
  ARTIFACT_NAME="random-video-streamer-release.apk"
else
  BUILD_CMD="flutter build appbundle --release"
  ARTIFACT_IN_CONTAINER="build/app/outputs/bundle/release/app-release.aab"
  ARTIFACT_NAME="random-video-streamer-release.aab"
fi

echo "Building Flutter Android ($TARGET) in Docker..."
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
    flutter create --platforms=android,web . &&
    flutter pub get &&
    $BUILD_CMD \
      --dart-define=API_BASE_URL=$API_BASE_URL \
      --dart-define=HLS_URL=$HLS_URL \
      --dart-define=ENABLE_LIVE_STREAM=$ENABLE_LIVE_STREAM &&
    mkdir -p dist/android &&
    cp $ARTIFACT_IN_CONTAINER dist/android/$ARTIFACT_NAME &&
    chown -R $HOST_UID:$HOST_GID /app/build /app/dist /app/.dart_tool /app/.flutter-plugins* 2>/dev/null || true
  "

echo "Android build complete: frontend-flutter/dist/android/$ARTIFACT_NAME"
