#!/usr/bin/env bash
# The server's web deploy (run on the server, e.g. through the owner's srv.py): pull $NB_BRANCH (default organizations;
# the release pipeline passes production), build the web app
# NEXT TO the live folder, post-process it (scripts/web/postbuild.dart, D-171: a content-hashed main script and .gz /
# .br copies for nginx gzip_static / brotli_static), swap it in, smoke test the live site, and roll back to the
# previous build when a check fails. The live folder is never half-written: a failed build or postbuild leaves it alone.
#
#   scripts/server/build_web.sh [--self-host-canvaskit]
#
# Needs the nginx rules of back/deploy/nginx/nextbrain.conf.example for the full effect (HTTP/2, the cache headers).
# `brotli` (apt install brotli) is optional: without it only .gz files are written.
# Exit codes: 0 deployed, 1 nothing changed (a step before the swap failed), 2 rolled back after the swap.
set -uo pipefail
export PATH="$PATH:$HOME/flutter/bin:$HOME/flutter/bin/cache/dart-sdk/bin"
FRONT="${NB_FRONT_DIR:-/root/elfaheem/front}"
TS=$(date +%Y%m%d-%H%M%S)
die() { echo "!! $*"; exit 1; }

cd "$FRONT" || die "no $FRONT"
LIVE=$(readlink -f /root/elfaheem/app_releases/web/current)
echo "live web: $LIVE"
[ "$LIVE" = "$FRONT/build/web" ] || die "app_releases/web/current -> $LIVE, not $FRONT/build/web: publish a web release instead"

git checkout --theirs . || true
BRANCH="${NB_BRANCH:-organizations}"
case "$BRANCH" in ""|*[!A-Za-z0-9._/-]*) die "bad NB_BRANCH: $BRANCH" ;; esac
git pull origin "$BRANCH" || die "git pull failed"
git checkout --theirs . || true
git log --oneline -1
flutter pub get > /tmp/nb-pubget.log 2>&1 || { tail -20 /tmp/nb-pubget.log; die "pub get failed"; }

# D-270: once nginx serves the landing at the root (deploy_landing.sh wrote its block), the app lives under /app/
BASE=/
grep -q "nb-landing:begin" /etc/nginx/sites-available/nextbrain && BASE=/app/
echo "base href: $BASE"
rm -rf build/web-next
flutter build web --release --base-href "$BASE" -o build/web-next \
  --dart-define=API_BASE_URL=https://alfheemacademy.com/api \
  --dart-define=LIVEKIT_URL=wss://alfheemacademy.com/livekit > /tmp/nb-webbuild.log 2>&1 \
  || { tail -30 /tmp/nb-webbuild.log; die "web build failed; live site untouched"; }
dart run scripts/web/postbuild.dart build/web-next --brotli-quality="${NB_BROTLI_QUALITY:-11}" "$@" > /tmp/nb-postbuild.log 2>&1 \
  || { tail -30 /tmp/nb-postbuild.log; die "postbuild failed; live site untouched"; }
tail -2 /tmp/nb-postbuild.log
MAIN=$(ls build/web-next | grep -E '^main\.dart\.[0-9a-f]{8}\.js$' | head -1)
[ -n "$MAIN" ] || die "no hashed main script in build/web-next; live site untouched"
grep -q "$MAIN" build/web-next/flutter_bootstrap.js || die "flutter_bootstrap.js does not load $MAIN; live site untouched"
chmod -R o+rX build/web-next
echo "new main: $MAIN"

# swap: build/web -> build/web-prev-<time>, build/web-next -> build/web (app_releases/web/current points at build/web)
mv build/web "build/web-prev-$TS" || die "could not move the live build aside"
mv build/web-next build/web || { mv "build/web-prev-$TS" build/web; die "swap failed; restored"; }
echo "swapped (previous build kept in build/web-prev-$TS)"

rollback() {
  echo "!! smoke test failed: $* -> rolling back"
  rm -rf build/web-failed
  if mv build/web build/web-failed && mv "build/web-prev-$TS" build/web; then
    echo "!! rolled back to the previous build (the failed one is in build/web-failed)"
  else
    echo "!! ROLLBACK INCOMPLETE: restore build/web from build/web-prev-$TS by hand"
  fi
  exit 2
}
R="--resolve alfheemacademy.com:443:127.0.0.1"
code() { curl -s $R -o /dev/null -w "%{http_code}" "$1"; }
U="https://alfheemacademy.com${BASE}"
HASH=$(echo "$MAIN" | cut -d. -f3)
c=$(code "$U"); echo "index: $c"; [ "$c" = 200 ] || rollback "index $c"
curl -s $R "$U" | grep -q flutter_bootstrap.js || rollback "index has no flutter_bootstrap.js"
c=$(code "${U}flutter_bootstrap.js"); echo "bootstrap: $c"; [ "$c" = 200 ] || rollback "bootstrap $c"
curl -s $R "${U}flutter_bootstrap.js" | grep -q "$MAIN" || rollback "the served bootstrap does not load $MAIN"
c=$(code "${U}$MAIN"); echo "main: $c"; [ "$c" = 200 ] || rollback "main $c"
# the first deferred part that exists (dart2js does not always emit _1)
PART=$(ls build/web | grep -E "^main\.dart\.$HASH\.js_[0-9]+\.part\.js$" | sort -t_ -k2 -n | head -1)
[ -n "$PART" ] || rollback "no deferred part in build/web"
c=$(code "${U}$PART"); echo "part $PART: $c"; [ "$c" = 200 ] || rollback "part $c"
c=$(code "${U}assets/assets/tz/latest.tzf"); echo "tz data: $c"; [ "$c" = 200 ] || rollback "tz $c"
c=$(code "${U}calendar"); echo "deep link /calendar: $c"; [ "$c" = 200 ] || rollback "deep link $c"
c=$(code "https://alfheemacademy.com/api/api/v1/theme/web"); echo "api theme: $c"; [ "$c" = 200 ] || rollback "api theme $c"
# keep the two newest previous builds
ls -d build/web-prev-* 2>/dev/null | sort | head -n -2 | xargs -r rm -rf
echo "OK deployed $(git log --oneline -1)"
