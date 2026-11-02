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

## As built (backend, `feature/app-releases`) — additions to the contract above
Routes: `routers/app_releases_router.py`; logic `services/app_release_service.py`; files `services/app_release_files.py`;
tables `app_releases`, `app_release_logs`, `app_builder_state` (migration 0040); server setup `docs/app_releases_server.md`;
build agent `tools/builder/`. Every error body is `{"detail": {"code", "message" (ar), "message_en", …}}`.
- **Release object** (list items, `GET /{id}`, every action's answer): `id, platform, version, build_number, notes_ar,
  notes_en, policy, min_supported, branch, commit_sha, gate, source, store_url, auto_publish, status, progress, error,
  attempt, current, buildable, artifacts [{name, size, sha256}], created_by, published_by, created_at, updated_at,
  started_at, finished_at, live_at, actions {cancel, retry, publish, rollback}` (what the buttons may do now). `GET /{id}`
  and the actions add `log [{seq, line}]` (last 500), `log_count`, `download_url`, `meta {agent_version, min_os,
  min_build, effective_min_supported}`. `current` = the release its platform serves now (one per platform); a release
  that was live and was replaced stays `live` with `current: false`.
- `GET /` → `{items, total, page, page_size, live {platform: version|null}, next_build_number {platform: n}}` (the form's
  defaults). Paging `page` (1…), `page_size` (≤ 100).
- `POST /` errors: 422 `platform_invalid` / `version_invalid` (x.y.z) / `policy_invalid` / `gate_invalid` /
  `source_invalid` (google_play = android only, app_store = ios / macos only) / `store_url_invalid` (https only) /
  `store_url_required` (google_play, app_store, custom) / `min_supported_invalid` / `build_number_invalid`; 400
  `branch_invalid`; 403 `reauth_failed` (missing or wrong password; failures count against the login throttle, 429
  `too_many_attempts`); 409 `version_exists`, `build_running`, `version_not_greater {live}`, `build_number_not_greater
  {next_build_number}`; 503 `releases_not_configured` (web / android / linux while the server has no releases folder).
  `branch_not_found` is the BUILD's error (the agent cannot fetch it): the release goes `failed` with
  `error: "branch_not_found"`.
- ios / windows / macos are recorded only: created `ready` (progress 100), and live at once when `auto_publish`.
- `POST /{id}/cancel` (queued / building / testing; else 409 `not_cancelable`), `POST /{id}/retry` (failed / canceled
  of a buildable platform; `attempt` + 1, artifacts cleared; 409 `not_retryable`, `build_running`), `POST /{id}/publish`
  {password} (ready only, 409 `not_publishable`; a Google Play release is published by hand after the Play upload —
  auto publish never runs for it), `POST /{id}/rollback` {password} (the current live release only, 409 `not_live`,
  `rollback_unavailable` when there is no earlier live release or its files are gone). 503 `releases_not_configured`.
- `GET /{id}/log?after=<seq>&limit=` → `{lines [{seq, line}], log_count, status, progress}`.
- `POST /builder/token` {password} → `{token}` (shown ONCE; the old token stops working). `GET /builder/status` →
  `{online (seen ≤ 120 s ago), last_seen, version, busy_job {id, platform, version, status, progress} | null, token_set,
  token_rotated_at, configured}`.
- Builder calls carry `X-Job-Attempt: <attempt>` (from the claim); a call about a job that is no longer running →
  409 `job_not_active {cancel: true}`. Claim → `{id, attempt, platform, version, build_number, branch, gate, source,
  policy, notes_ar, notes_en, artifacts [required names], max_upload_bytes}`. Artifact names: web `web.tar.gz`; android
  `app-arm64-v8a.apk`, `app-armeabi-v7a.apk`, `app-universal.apk`, `app.aab`; linux `linux-x64.deb`,
  `linux-x64.tar.gz` (else 400 `artifact_name_invalid`); header `X-Artifact-Sha256` (400 `artifact_sha_required` /
  `artifact_sha_mismatch`), 413 `artifact_too_large`. Finish `{ok, error?, meta?}`: ok without the required artifacts
  → `failed` (`artifacts_missing: …`).
- SSE: `app_release_updated {id, platform, status, progress, current}` to every super admin (stream only);
  `app_release_live {platform, version, build_number, policy, must}` to EVERY open stream when a web build goes live
  (also after a rollback), not replayed.
- Version check (additive): `download_url`, `source`, `notes {ar, en}`, `policy`, `build_number` of the current release.
  linux / windows / macos are answered from their release. The policy is carried by `min_supported` on the
  app_versions row the release writes (`must` → this version; never lower than an earlier forced minimum), so a client
  ON the latest version is never told to update.
