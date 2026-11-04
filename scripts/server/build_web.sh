#!/usr/bin/env bash
# Proposed replacement for the server's web build script (the owner's build_web.sh, run on the server through srv.py):
# the same steps as before, plus scripts/web/postbuild.dart, so the build folder carries a content-hashed main script
# (cacheable `immutable`) and .gz / .br copies for nginx `gzip_static` / `brotli_static`.
#
#   scripts/server/build_web.sh [--self-host-canvaskit]
#
# Needs the nginx config of back/deploy/nginx/nextbrain.conf.example to get the full effect (HTTP/2, the cache headers).
# `brotli` (apt install brotli) is optional: without it only .gz files are written.
set -euo pipefail
export PATH="$PATH:$HOME/flutter/bin:$HOME/flutter/bin/cache/dart-sdk/bin"
cd "${NB_FRONT_DIR:-/root/nextbrain/front}"
git checkout --theirs . || true
git pull origin organizations
git checkout --theirs . || true
git log --oneline -1
flutter pub get
# D-165: once nginx serves the landing at the root (deploy_landing.sh wrote its block), the app lives under /app/
BASE=/
grep -q "nb-landing:begin" /etc/nginx/sites-available/nextbrain && BASE=/app/
echo "base href: $BASE"
flutter build web --release --base-href "$BASE" \
  --dart-define=API_BASE_URL=https://nextbrain.site/api \
  --dart-define=LIVEKIT_URL=wss://nextbrain.site/livekit
dart run scripts/web/postbuild.dart build/web --brotli-quality="${NB_BROTLI_QUALITY:-11}" "$@"
chmod -R o+rX build/web
ls -la build/web | head -5; date
curl -s https://nextbrain.site/ --resolve nextbrain.site:443:127.0.0.1 -o /dev/null -w "site: %{http_code}\n"
