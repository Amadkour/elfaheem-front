#!/usr/bin/env bash
# Builds build/hosting for Firebase Hosting (firebase.json "public"), the same layout nginx serves (D-270):
#   /            the landing site (landing/dist), its requests to the API at PUBLIC_LANDING_API_BASE
#   /app/        the Flutter web app (--base-href /app/, post-processed by scripts/web/postbuild.dart, D-171)
#   /.well-known App Links / Universal Links, from the app's build (the verifiers do not follow redirects)
#   /flutter_service_worker.js, /firebase-messaging-sw.js  the app's copies, for browsers that registered them at /
#   /404.html    sends an old root URL (/login, /notifications, ...) on to the same path under /app/
#
#   scripts/build_firebase_hosting.sh && firebase deploy --only hosting
#
# Firebase Hosting answers redirects BEFORE static files, so the root cannot redirect "everything else" the way nginx's
# @nb_app does: share links get real 302s in firebase.json, every other old app URL goes through 404.html.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PUBLIC_LANDING_API_BASE="${PUBLIC_LANDING_API_BASE:-https://alfheemacademy.com}"
API_BASE_URL="${API_BASE_URL:-https://alfheemacademy.com/api}"
LIVEKIT_URL="${LIVEKIT_URL:-wss://alfheemacademy.com/livekit}"

bash scripts/build_landing.sh

# MSYS_NO_PATHCONV: Git Bash on Windows would rewrite /app/ into a C:/Program Files/Git path
MSYS_NO_PATHCONV=1 flutter build web --release --base-href /app/ \
  --dart-define=API_BASE_URL="$API_BASE_URL" --dart-define=LIVEKIT_URL="$LIVEKIT_URL"
dart run scripts/web/postbuild.dart build/web

grep -q '<base href="/app/">' build/web/index.html || { echo "build/web is not built for /app/" >&2; exit 1; }

rm -rf build/hosting
mkdir -p build/hosting
cp -a landing/dist/. build/hosting/
cp -a build/web build/hosting/app
rm -f build/hosting/app/.last_build_id
[ -d build/web/.well-known ] && cp -a build/web/.well-known build/hosting/.well-known
for f in flutter_service_worker.js firebase-messaging-sw.js; do
  [ -f "build/web/$f" ] && cp "build/web/$f" "build/hosting/$f"
done

cat > build/hosting/404.html <<'HTML'
<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Alfaheem</title>
<script>
  // an old web-app URL from before the app moved to /app/ (D-270): the same path, query and hash under /app/
  (function () {
    var p = location.pathname;
    if (p.indexOf('/app/') !== 0 && p !== '/app') location.replace('/app' + p + location.search + location.hash);
  })();
</script>
</head>
<body>
<p><a href="/app/">Alfaheem</a></p>
</body>
</html>
HTML

echo "build/hosting: $(find build/hosting -type f | wc -l) files, $(du -sh build/hosting | cut -f1)"
