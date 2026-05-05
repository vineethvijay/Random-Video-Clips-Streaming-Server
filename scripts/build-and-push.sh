#!/bin/bash
set -e

# Build and push container images to the local K8s registry.
# Only rebuilds images whose source files have changed (based on git diff).
#
# Usage: ./scripts/build-and-push.sh [registry]
#   registry: defaults to 192.168.0.245:5000
#
# Env vars:
#   TAG       - image tag (default: latest)
#   FORCE     - set to 1 to rebuild all images regardless of changes
#   ONLY      - comma-separated list of images to build: api,generator,nginx

REGISTRY="${1:-192.168.0.245:5000}"
PREFIX="random-streamer"
TAG="${TAG:-latest}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# ── Detect which images need rebuilding ──
needs_build() {
  local image="$1"
  [[ "${FORCE:-0}" == "1" ]] && return 0
  if [[ -n "${ONLY:-}" ]]; then
    echo ",$ONLY," | grep -q ",$image," && return 0 || return 1
  fi
  # Compare working tree against last pushed image (use git status + diff)
  local changed
  changed=$(git diff --name-only HEAD 2>/dev/null; git diff --name-only --cached 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)
  case "$image" in
    api)       echo "$changed" | grep -qE '^backend/(app\.py|clip_pusher|gunicorn|requirements\.txt|Dockerfile[^.]|scripts/|.*\.py)' ;;
    generator) echo "$changed" | grep -qE '^backend/(generate_chunk\.sh|Dockerfile\.generator|scripts/)' ;;
    nginx)     echo "$changed" | grep -qE '^(Dockerfile\.nginx|nginx\.conf)' ;;
  esac
}

build_and_push() {
  local name="$1" dockerfile="$2" context="$3"
  local full="${REGISTRY}/${PREFIX}-${name}:${TAG}"
  echo "--- Building ${PREFIX}-${name} ---"
  docker build -t "$full" -f "$dockerfile" "$context"
  echo "--- Pushing ${PREFIX}-${name} ---"
  docker push "$full"
  echo ""
  BUILT+=("$full")
}

BUILT=()

if needs_build api; then
  build_and_push api backend/Dockerfile backend/
else
  echo "--- Skipping ${PREFIX}-api (no changes) ---"
fi

if needs_build generator; then
  build_and_push generator backend/Dockerfile.generator backend/
else
  echo "--- Skipping ${PREFIX}-generator (no changes) ---"
fi

if needs_build nginx; then
  build_and_push nginx Dockerfile.nginx .
else
  echo "--- Skipping ${PREFIX}-nginx (no changes) ---"
fi

echo ""
if [[ ${#BUILT[@]} -gt 0 ]]; then
  echo "==> Built and pushed:"
  printf '    %s\n' "${BUILT[@]}"
  echo ""
  echo "To trigger a rollout in K8s:"
  for img in "${BUILT[@]}"; do
    case "$img" in
      *-api:*)       echo "    kubectl rollout restart deployment/random-streamer-api" ;;
      *-generator:*) echo "    kubectl rollout restart deployment/random-streamer-generator" ;;
      *-nginx:*)     echo "    kubectl rollout restart deployment/random-streamer-nginx" ;;
    esac
  done
else
  echo "==> Nothing to build — no changes detected."
  echo "    Use FORCE=1 to rebuild all, or ONLY=api,generator,nginx to pick specific images."
fi
