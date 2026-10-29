# Native recorders: upload token, `epoch`, 409 handling

Status: the Dart and web sides are done (2026-10-29); the Kotlin / Swift items below are **not** applied (those
files belong to the Android and iOS review work). Server contract: `../back/FLUTTER_API_CHANGES.md`, "Live
hardening, batch 2" → "Device recording upload token" and "Recording chunks (R1 / R4)".

## What the Dart side already does

- `ClientRecorder.start()` (`lib/features/teacher/sessions/live/widgets/room_recorder.dart`) asks once per start for
  the upload token (`POST /api/v1/live-sessions/{id}/recording-upload-token`, a meeting recording
  `POST /api/v1/live/recordings/{rid}/upload-token`; pure rule in `widgets/record/recording_upload_token.dart`) and
  passes `Bearer <upload token>` as the existing `authToken` start argument. An older server (bare 404 / 405) or any
  other failure falls back to `Bearer <access token>`, as before.
- No native change is needed for the token: Android `ScreenCaptureService.uploadChunk` sends
  `setRequestProperty("Authorization", authToken)` and iOS `AppDelegate` sends
  `request.setValue(authToken, forHTTPHeaderField: "Authorization")` verbatim, and the server accepts
  `Authorization: Bearer <upload token>` on both chunk routes.
- `startMicRecording` now also carries **`epoch`** (string, the start time in ms, a new one per recorder start)
  next to `sessionId`, `uploadUrl`, `authToken`, `chunkSeconds`, `chunkIndex`. The native sides ignore it today.

## What the native sides must add

1. **`epoch` form field** — read `args["epoch"]` in `startMicRecording` (Android: `MainActivity` → an intent extra
   for `ScreenCaptureService`, e.g. `EXTRA_EPOCH = "epoch"`; iOS: `AppDelegate`'s `startMicRecording` case) and add
   `epoch=<value>` to every chunk's multipart form, beside `chunk_index` / `is_final`:
   - Android: `uploadChunk` → `field("epoch", epoch)` when non-empty.
   - iOS: the chunk upload (`addField("chunk_index", …)` in `uploadChunkAsync`) and the finalize ping
     (`uploadFinalizePingAsync`) → `addField("epoch", epoch)` when non-empty; a kept chunk (I11 sidecar) must keep
     the epoch it was recorded with (store it in `UploadTarget` / the sidecar next to `url` / `token`).
   Without it the server still detects a restart (same index, different bytes) and keeps earlier footage; with it
   assembly orders by (epoch, index) exactly.
2. **409 `recording_assembled`** (body `{"detail": {"code": "recording_assembled", …}}`) — the run's recording is
   assembled: stop uploading for this run (drop the queue, delete kept chunks of that run, report the recorder as
   done), do not retry. Today Android retries every non-2xx 3 times then gives up on that chunk; iOS treats a 4xx as
   permanent per chunk but keeps going with the next.
3. **409 `recording_assembling`** — being assembled right now: keep the chunk file (I11 keep path on iOS) rather than
   delete it; an empty finalize ping is still accepted.
4. **401 `upload_token_expired` / `upload_token_invalid` / `upload_token_revoked`, 403 `upload_token_scope`** — the
   token can no longer upload to this run (the run ended after its 3-minute grace, a newer run started, or the
   meeting recording left `recording`): permanent, do not retry. iOS `retryPendingChunks` retries kept chunks with
   the token captured in their sidecar; one from an ended run answers `upload_token_revoked` → drop it.
5. Optional: Android could treat 4xx (other than 408 / 429) as permanent like iOS (no 3 retries with back-off).

Classification shared with the Dart / web side: `recordingChunkVerdict(status, code)` in
`widgets/record/recording_upload_token.dart` (uploaded · assembled · keep · drop · retry).
