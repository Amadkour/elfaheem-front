#!/usr/bin/env bash
# Uploads a website-channel build's files to our server (D-144, docs/release/APP_RELEASES_CODEMAGIC.md "Release
# lifecycle" 5): the last step of the Codemagic workflows android-website, web-website, linux-website and
# windows-website (codemagic.yaml).
#
#   scripts/release/upload_artifacts.sh <dir>
#
# Every regular file directly in <dir> (no sub-folders, no dot files) goes up as
#   PUT  $NB_API_URL/api/v1/app-releases/upload/$NB_RELEASE_ID/<name>
#        Authorization: Upload $NB_UPLOAD_TOKEN · X-Sha256: <hex> · the file as the body (streamed, not read into memory)
# then the release is closed with
#   POST $NB_API_URL/api/v1/app-releases/upload/$NB_RELEASE_ID/done   {"files": [{name, size, sha256}]}
#
# Environment (set by the server when it starts the Codemagic build): NB_API_URL (e.g. https://nextbrain.site/api, the
# same base the app uses), NB_RELEASE_ID, NB_UPLOAD_TOKEN (per release and attempt, expires after 6 h).
# A 5xx / network failure is retried 5 times with a growing pause; a 4xx stops at once (a wrong token, a name the
# server refuses, a file too large, a release that is no longer building). The token is never printed: it reaches curl
# through a header file readable by this user only, never on the command line.
set -euo pipefail

dir="${1:-}"
[ -n "$dir" ] && [ -d "$dir" ] || { echo "usage: $0 <dir> (a folder holding the files to upload)" >&2; exit 2; }
: "${NB_API_URL:?NB_API_URL is not set (the server passes it with the build)}"
: "${NB_RELEASE_ID:?NB_RELEASE_ID is not set}"
if [ -z "${NB_UPLOAD_TOKEN:-}" ]; then
  echo "NB_UPLOAD_TOKEN is not set: a website-channel build must be started by the server (App versions → New version)" >&2
  exit 2
fi
case "$NB_RELEASE_ID" in *[!0-9]*) echo "NB_RELEASE_ID must be a number" >&2; exit 2 ;; esac

base="${NB_API_URL%/}/api/v1/app-releases/upload/${NB_RELEASE_ID}"
tries="${NB_UPLOAD_TRIES:-5}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
headers="$work/headers"
( umask 077; printf 'Authorization: Upload %s\n' "$NB_UPLOAD_TOKEN" > "$headers" )

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# send <label> <curl args…>: retries 5xx / network errors, stops on 4xx; prints the server's answer on failure
send() {
  local label="$1"; shift
  local attempt=1 code pause
  while :; do
    code="$(curl -sS -o "$work/body" -w '%{http_code}' -H @"$headers" "$@" || echo 000)"
    case "$code" in
      2??) return 0 ;;
      4??)
        echo "✗ $label: HTTP $code" >&2
        head -c 2000 "$work/body" >&2 || true
        echo >&2
        return 1 ;;
    esac
    if [ "$attempt" -ge "$tries" ]; then
      echo "✗ $label: HTTP $code after $attempt tries" >&2
      head -c 2000 "$work/body" >&2 || true
      echo >&2
      return 1
    fi
    pause=$((attempt * attempt * 5))
    echo "  $label: HTTP $code, trying again in ${pause}s (${attempt}/${tries})"
    sleep "$pause"
    attempt=$((attempt + 1))
  done
}

files=()
while IFS= read -r -d '' f; do files+=("$f"); done < <(find "$dir" -maxdepth 1 -type f ! -name '.*' -print0 | sort -z)
[ "${#files[@]}" -gt 0 ] || { echo "nothing to upload in $dir" >&2; exit 1; }

manifest="["
for f in "${files[@]}"; do
  name="$(basename "$f")"
  if ! [[ "$name" =~ ^[A-Za-z0-9._-]{1,120}$ ]]; then
    echo "✗ $name: the server accepts letters, digits, '.', '_' and '-' only (1–120 characters)" >&2
    exit 1
  fi
  size="$(wc -c < "$f" | tr -d ' ')"
  sum="$(sha256_of "$f")"
  echo "→ $name ($size bytes, sha256 $sum)"
  send "$name" -X PUT -H "X-Sha256: $sum" -H 'Content-Type: application/octet-stream' -T "$f" "$base/$name"
  echo "  ✓ uploaded"
  [ "$manifest" = "[" ] || manifest="$manifest,"
  manifest="$manifest{\"name\":\"$name\",\"size\":$size,\"sha256\":\"$sum\"}"
done
manifest="$manifest]"

echo "→ done (${#files[@]} files)"
send done -X POST -H 'Content-Type: application/json' --data "{\"files\":$manifest}" "$base/done"
echo "✓ release $NB_RELEASE_ID: ${#files[@]} files uploaded"
