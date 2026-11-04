#!/usr/bin/env bash
# Builds the landing site (landing/) into landing/dist, atomically.
#   - node on PATH      -> npm ci && npm run build locally
#   - no node / LANDING_BUILD_DOCKER=1 -> the same inside a pinned node image (the server has Docker only)
# The previous build stays in landing/dist-prev for rollback. LANDING_API_ORIGIN (optional) bakes the
# public stats and options in at build time; a failure to fetch them never fails the build.
# PUBLIC_LANDING_API_BASE (optional, e.g. https://nextbrain.site) is the origin the page's own requests go to when it is
# served from another host (Firebase Hosting, scripts/build_firebase_hosting.sh); empty = the same origin.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANDING="$ROOT/landing"
NODE_IMAGE="${LANDING_NODE_IMAGE:-node:24.11.1-alpine}"   # keep in step with landing/.nvmrc

cd "$LANDING"
rm -rf dist-new

if [ "${LANDING_BUILD_DOCKER:-0}" = "1" ] || ! command -v node >/dev/null 2>&1; then
  command -v docker >/dev/null 2>&1 || { echo "need node or docker on PATH" >&2; exit 1; }
  echo "building in $NODE_IMAGE"
  docker run --rm \
    -v "$LANDING:/w" -w /w \
    -e LANDING_API_ORIGIN="${LANDING_API_ORIGIN:-}"     -e PUBLIC_LANDING_API_BASE="${PUBLIC_LANDING_API_BASE:-}" \
    "$NODE_IMAGE" sh -c 'npm ci --no-audit --no-fund && npm run build -- --outDir dist-new'
  # Docker on a server runs as root; hand the output back to whoever runs this script.
  if [ "$(id -u)" != "0" ]; then
    docker run --rm -v "$LANDING:/w" -w /w "$NODE_IMAGE" chown -R "$(id -u):$(id -g)" dist-new node_modules .astro 2>/dev/null || true
  fi
else
  npm ci --no-audit --no-fund
  npm run build -- --outDir dist-new
fi

[ -f dist-new/ar/index.html ] && [ -f dist-new/en/index.html ] && [ -f dist-new/index.html ] \
  || { echo "build output incomplete" >&2; exit 1; }

# Atomic-ish swap: dist -> dist-prev, dist-new -> dist.
rm -rf dist-prev
[ -d dist ] && mv dist dist-prev
mv dist-new dist

echo "landing/dist: $(find dist -type f | wc -l) files, $(du -sh dist | cut -f1)"
