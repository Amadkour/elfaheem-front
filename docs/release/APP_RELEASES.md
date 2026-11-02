# App releases from the Super Admin dashboard (D-143) — shared contract

The super admin creates a version; a SEPARATE BUILD SERVER builds it from the chosen branch and publishes it.
Production never runs builds and never holds the Android signing key.

## Flow
1. Super admin → Dashboard → App versions → New version: platform, version (x.y.z), build number (default: last + 1),
   notes (ar + en), update policy (optional / recommended / must update) + minimum supported version, branch
   (default `production`, free text validated against `^[A-Za-z0-9._/-]{1,100}$` and must exist on origin),
   gate (`test_first` = analyzer + test suites must pass, or `direct`), download source, store URL when needed,
   "publish automatically when the build succeeds" (default on). Confirm with the account password (re-auth).
2. The server stores the release (status `queued`) and an audit entry; an SSE event `app_release_updated` is sent on
   every status / progress change.
3. The build agent (on the build server) polls `POST /api/v1/builder/claim` with its own token (scope: builder only),
   checks out the branch at a pinned commit, stamps `--build-name=<version> --build-number=<n>`, runs the gate when
   `test_first`, builds, uploads artifacts, reports log lines and progress, then `POST …/builder/jobs/{id}/finish`.
4. Publishing (automatic or the "Make live" button) makes it live: web → the uploaded build replaces the served site
   atomically (previous one kept for rollback); android/linux files → releases folder + releases.json (D-137);
   the AppVersion row becomes active with the update policy, so the app's version check sees it at once.

## Platforms
- `web` — flutter build web --release. "Must update" = open tabs are told to reload (SSE `app_release_live`).
- `android` — signed APKs (arm64-v8a, armeabi-v7a, universal) for the website, and an AAB when the source is Google Play.
- `linux` — scripts/release/build_linux.sh packaging (.deb + .tar.gz).
- `ios` — NO native build (Apple allows App Store installs only): the iOS entry is the PWA. Creating an iOS version
  records notes + policy and the PWA (the web build) is what iPhone users install; source `app_store` + URL is allowed
  for a future native app, recorded only.
- `windows`, `macos` — not buildable on Linux: record only (source = website file URL or store URL).

## Download source (per release)
`website` (our releases page / direct files, the default), `google_play`, `app_store`, `custom` (any https URL).
The app's update dialog opens: website → the releases page / file for this platform; store → the store URL.
Automatic upload to Google Play is phase 2 (needs a Play Console service account JSON); in phase 1 a Google Play
release builds the AAB, which the super admin downloads from the release page and uploads to the Play Console;
it is marked live by hand.

## Statuses
`queued → building → testing (test_first) → uploading → ready → live` | `failed` | `canceled` | `rolled_back`.
Cancel works until `uploading`. Retry creates a new job for the same release. Rollback (web / website files): make the
previous live release of that platform live again.

## API (core, all super-admin only, /api/v1/admin/app-releases)
- `GET /` (filter platform, status, paged) · `GET /{id}` (incl. last 500 log lines, artifacts, commit)
- `POST /` {platform, version, build_number?, notes_ar, notes_en, policy: optional|recommended|must, min_supported?,
  branch?, gate: test_first|direct, source: website|google_play|app_store|custom, store_url?, auto_publish, password}
  → 201 (409 version_exists, 400 branch_invalid / branch_not_found, 403 reauth_failed, 409 build_running for that platform)
- `POST /{id}/cancel` · `POST /{id}/retry` · `POST /{id}/publish` {password} · `POST /{id}/rollback` {password}
- `GET /{id}/log?after=<line>` · `GET /{id}/artifacts/{name}` (download, e.g. the AAB)
- `GET /builder/status` → {online, last_seen, version, busy_job}
Builder (token auth `Authorization: Builder <token>`, token hash in settings, rotate from the dashboard):
- `POST /api/v1/builder/claim` → job or 204 · `POST /api/v1/builder/jobs/{id}/log` {lines[], progress, status}
- `PUT /api/v1/builder/jobs/{id}/artifacts/{name}` (stream upload, size cap, sha256 header) · `POST …/finish` {ok, error}
Existing: `GET /app/version-check` keeps working; it now also returns `download_url` / `source` / `notes` of the live
release.
