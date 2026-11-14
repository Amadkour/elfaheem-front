#!/usr/bin/env bash
# Release builds with obfuscated Dart code (brief §11, D-026). Symbols go to build/debug-info/<version>/ (git-ignored):
# keep them with the release — they are the only way to read a stack trace from that build
# (`flutter symbolize -i trace.txt -d build/debug-info/<version>/app.android-arm64.symbols`).
#
#   scripts/build_release.sh apk | appbundle | ipa | web
#
# Android signing: android/key.properties or ANDROID_KEYSTORE_PATH / _PASSWORD / ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD;
# without them this script refuses the apk / appbundle (S13: a release is never signed with the debug key), and so does
# gradle (android/app/build.gradle.kts).
set -euo pipefail
target="${1:-appbundle}"
version="$(grep -E '^version:' pubspec.yaml | awk '{print $2}')"
symbols="build/debug-info/${version}"
mkdir -p "$symbols"
android_keystore() {
  # the same lookup as gradle: key.properties' storeFile (relative to android/app), else ANDROID_KEYSTORE_PATH
  local store=""
  if [[ -f android/key.properties ]]; then
    store="$(grep -E '^[[:space:]]*storeFile[[:space:]]*=' android/key.properties | head -n1 | cut -d= -f2- | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$store" && "$store" != /* && ! "$store" =~ ^[A-Za-z]: ]] && store="android/app/$store"
  fi
  [[ -z "$store" ]] && store="${ANDROID_KEYSTORE_PATH:-}"
  printf '%s' "$store"
}
case "$target" in
  apk|appbundle)
    store="$(android_keystore)"
    if [[ -z "$store" ]]; then
      echo "refusing: no release keystore (android/key.properties or ANDROID_KEYSTORE_PATH) — a release must never be signed with the debug key" >&2
      exit 3
    fi
    if [[ ! -f "$store" ]]; then
      echo "refusing: the release keystore '$store' does not exist" >&2
      exit 3
    fi
    flutter build "$target" --release --obfuscate --split-debug-info="$symbols"
    ;;
  ipa)
    flutter build "$target" --release --obfuscate --split-debug-info="$symbols"
    ;;
  web)
    # web code is minified by dart2js; --obfuscate does not apply to web builds
    # served at https://alfheemacademy.com/app/ (the landing site owns the root, D-270)
    MSYS_NO_PATHCONV=1 flutter build web --release --base-href /app/  # MSYS: Git Bash on Windows would rewrite /app/ into a C:/Program Files/Git path
    # content-hashed main script, precompressed .gz / .br, font-manifest prune (scripts/web/postbuild.dart; add --self-host-canvaskit to serve CanvasKit from the build)
    dart run scripts/web/postbuild.dart build/web
    ;;
  *) echo "usage: $0 apk|appbundle|ipa|web" >&2; exit 2 ;;
esac
echo "built $target $version — symbols in $symbols"
