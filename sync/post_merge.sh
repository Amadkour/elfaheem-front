#!/usr/bin/env bash
# sync/post_merge.sh — re-apply the Alfaheem identity and regenerate the brand images (idempotent).
# Called by sync/sync.sh after a merge; safe to run on its own at any time.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
PY="${PY:-py -3.12}"
export PYTHONUTF8=1

$PY sync/apply_identity.py
$PY sync/gen_brand_assets.py
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
rm -f web/icons/favicon.png   # written by flutter_launcher_icons; the app uses web/favicon.png (keep-list)
# flutter_native_splash rewrites web/index.html: put the identity back on top of it.
$PY sync/apply_identity.py
$PY sync/check_identity.py
