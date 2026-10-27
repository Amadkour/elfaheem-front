# Live rooms: share links, admission lobby, meeting recordings to cloud drives

Contract between the app (`lib/features/shared/live/`, the live room in
`lib/features/teacher/sessions/live/`) and the backend (`../back/routers/live_room_router.py`,
`../back/services/live_room_service.py`, `../back/routers/live_recording_router.py`,
`../back/services/live_recording_service.py`, `../back/services/cloud_drive_service.py`).
Written 2026-10-27. Every agent working on this feature follows it; a deviation is recorded here.

## 1. Room identity

A **live room** is either a course live session or a calendar meeting:

| `kind`    | `id`              | host                                   | LiveKit room                     |
|-----------|-------------------|----------------------------------------|----------------------------------|
| `session` | `sessions.id`     | the course teacher (`assert_session_teacher`) | `OnlineSession.room_name`  |
| `meeting` | `cal_meetings.id` | `CalMeeting.owner_id`                  | `CalMeeting.room_name`           |

The app already identifies a meeting room with `JoinArgs.sessionId = -meetingId` (see
`calendar_meeting.dart`). New app code carries an explicit `LiveRoomRef(kind, id)`; `RoomPage` /
`JoinArgs` gain `roomRef` (default `LiveRoomRef.session(sessionId)`).

Every new route lives under `/api/v1/live/…`. `{kind}` is `session` or `meeting`; a wrong kind or
a room the caller may not host answers 404 / 403 with the usual `detail.code`.

## 2. Policy (host only)

```
GET  /api/v1/live/{kind}/{id}/policy
PUT  /api/v1/live/{kind}/{id}/policy        {admission?, guest_admission?}
```

Response (both):

```json
{
  "kind": "meeting", "id": 12,
  "admission": "open" | "approve",          // members (enrolled students / invitees). default open
  "guest_admission": "approve" | "auto",    // visitors from the share link. default approve
  "waiting": 2,                              // requests now waiting
  "link": { "url": "https://…/live/<token>", "token": "…", "can_publish": false,
            "max_guests": null, "has_pin": false, "created_at": "…" } | null
}
```

Switching `admission` to `open` admits every waiting member request; switching
`guest_admission` to `auto` admits every waiting guest request. The host is never asked.
Storage: table `live_room_settings (kind, ref_id, admission, guest_admission, link_token,
link_can_publish, link_max, link_pin_hash, link_created_at, updated_at)` in
`../back/data/live_room_models.py`, created by `ensure_live_room_tables` (called from
`ensure_org_tables`, no Alembic). For `kind = session` the link columns stay on
`SessionModel` (`guest_link_token` …) and the existing `…/guest-link` routes keep working;
`live_room_settings` holds only the admission fields for sessions.

## 3. Share link

```
POST   /api/v1/live/{kind}/{id}/link      {can_publish, max_guests, pin}   → policy.link
GET    /api/v1/live/{kind}/{id}/link
DELETE /api/v1/live/{kind}/{id}/link      204
```

The URL is `https://<web base>/live/<token>` (same as today's guest link, `guest_link_url`).
The app's route `/live/<token>` opens `GuestLivePage`, which now serves both kinds.

```
GET  /api/v1/public/live/{token}
```
adds to today's payload: `kind`, `title`, `host_name`, `starts_at` (meeting) and
`guest_admission` (`approve` | `auto`), `signed_in_join: true`.

```
POST /api/v1/public/live/{token}/join      {name, pin?, consent: true}
```
Answers either **200** `{status: "admitted", …today's join payload (url, token, room, identity,
can_publish, ttl_seconds…)}` or **202** `{status: "waiting", request_id, secret, poll_after: 3}`.
The guest then polls

```
GET  /api/v1/public/live/requests/{request_id}?secret=…
```
→ `{status: "waiting" | "admitted" | "rejected" | "expired", …join payload when admitted}`.
A waiting request expires after 10 minutes; `rejected` carries no reason.

A **signed-in** person who opens the link calls

```
POST /api/v1/live/links/{token}/join       (authenticated)
```
If they belong to the room (host, enrolled student, invitee) this is the ordinary member join
(the member admission rule applies). Otherwise they join as a named guest under the guest
rule, with `name` = their account name and `user_id` kept on the request. Same two answers.

## 4. Admission (lobby)

Member joins — `GET /api/v1/live-sessions/{id}/join` and `POST /api/v1/meetings/{id}/join` —
keep their payload, but when `admission = approve` and the caller is not the host they answer
**202** `{status: "waiting", request_id, poll_after: 3}`; the client polls

```
GET  /api/v1/live/requests/{request_id}      (authenticated, own request only)
```
with the same `status` answers as the public poll. The host is always admitted at once.

Host side:

```
GET  /api/v1/live/{kind}/{id}/lobby
     → { "waiting": [ {request_id, kind: "member"|"guest", name, user_id?, image_url?, requested_at} ],
         "admission": "...", "guest_admission": "...", "admitted_recent": [ … last 20 … ] }
POST /api/v1/live/{kind}/{id}/lobby/{request_id}/admit
POST /api/v1/live/{kind}/{id}/lobby/{request_id}/reject
POST /api/v1/live/{kind}/{id}/lobby/admit-all
```

Admitting mints the LiveKit token at that moment (guest: `make_guest_token`, and the
`LiveGuestJoin` row is written then, not at request time). Table `live_join_requests (id, kind,
ref_id, request_kind member|guest, user_id, name, identity, secret_hash, ip, status, created_at,
decided_at, decided_by)`.

Alerting the host: every new request sends a silent push `push_live(host, "live_join_request",
{kind, id, request_id, name})` (the host's room polls the lobby every 15 s — 4 s while the lobby sheet is
open, not at all in the background — and refreshes at once on that push, with one follow-up poll 4 s later,
and when the app returns to the foreground). If the host is not in the LiveKit room (no participant with
the host identity) a normal notification `notify_user(host, type="live_join_request",
related_type=kind, related_id=id, push_data={type: "live_lobby", kind, id})` is also sent, at
most one per room per 60 s. The app's `AppNavigator` deep link `live_lobby` opens the
session / meeting with the lobby sheet.

## 5. Meeting recordings → Google Drive / OneDrive

Course sessions keep today's recording flow (`record_enabled`, `…/recording-chunk`, session
materials). The flow below is for rooms that are **not** course sessions (`kind = meeting`);
`POST …/recordings` on a session answers 409 `course_session_recording`.

Connected drives (per user):

```
GET    /api/v1/me/cloud
       → { "providers": [ {provider: "google_drive"|"onedrive", available: bool, connected: bool,
                           email?, connected_at?} ] }
POST   /api/v1/me/cloud/{provider}/connect      → { "auth_url": "https://…" }
GET    /api/v1/cloud/oauth/{provider}/callback?code=&state=   (browser redirect; tiny HTML page)
DELETE /api/v1/me/cloud/{provider}              204
```
`available` is false until the server has `GOOGLE_DRIVE_CLIENT_ID/SECRET` or
`ONEDRIVE_CLIENT_ID/SECRET` (`config.py`). Tokens are stored encrypted (Fernet,
`CLOUD_TOKEN_KEY`, falls back to a key derived from `SECRET_KEY`) in `user_cloud_accounts`.
Scopes: Google `https://www.googleapis.com/auth/drive.file`; Microsoft `Files.ReadWrite
offline_access`. The app opens `auth_url` in the browser and polls `GET /me/cloud` until
`connected`.

Recording a meeting (host only):

```
POST /api/v1/live/{kind}/{id}/recordings
     {quality: "1080p"|"720p"|"480p"|"audio", destination: "google_drive"|"onedrive"}
     → 201 { recording_id, status: "recording", chunk_path: "/api/v1/live/recordings/{rid}/chunk" }
     409 cloud_not_connected  · 409 course_session_recording · 409 recording_active
POST /api/v1/live/recordings/{rid}/chunk        multipart: chunk, chunk_index, is_final   (same semantics as routers/recorder.py)
POST /api/v1/live/recordings/{rid}/stop         is_final without a chunk
GET  /api/v1/live/recordings/{rid}
     → { recording_id, kind, id, status: "recording"|"assembling"|"uploading"|"done"|"failed",
         quality, destination, size, duration_seconds, remote_url?, error?, created_at, finished_at? }
POST /api/v1/live/recordings/{rid}/retry        failed → uploading again (file kept on failure)
GET  /api/v1/live/{kind}/{id}/recordings        host: all; attendees: done ones
```

After the final chunk the server assembles ONE mp4 (or m4a for `audio`) at the chosen quality
with the ffmpeg helpers of `services/local_recorder.py` into `CLIENT_RECORDING_DIR/meetings/`,
uploads it to the owner's drive (Google: resumable upload to folder "NextBrain recordings";
OneDrive: Graph upload session to `/NextBrain recordings/`), names it
`<meeting title> – <date>.mp4`, stores `remote_file_id` / `remote_url`, deletes the local file,
and sends `notify_user(owner, type="live_recording_ready", related_type="meeting",
related_id=id, push_data={type: "calendar", id})`. On failure: status `failed`, the file is
kept, `live_recording_failed` notification. `meeting_detail` (calendar) adds
`"recording": <latest recording summary> | null` and `"can_record": is_owner && mode == online`.

Table `live_recordings (id, kind, ref_id, owner_id, quality, destination, status, local_path,
size, duration_seconds, remote_file_id, remote_url, error, created_at, finished_at)` in
`../back/data/live_recording_models.py`.

## 6. App flow summary

- **Host, before / in the room:** the share sheet (link, PIN, can-publish, max guests, copy /
  share) and the lobby sheet (waiting list with Admit / Reject / Admit all, the two switches:
  "Everyone needs my approval" / "Guests join automatically"). A lobby button with the waiting
  count sits in the control bar; a new request shows an in-room banner with a sound.
- **Joiner:** after Join, a "Waiting for the host…" screen (polling, cancel) replaces the
  pre-join page until admitted; rejected / expired show a friendly end screen.
- **Meeting recording:** the Record button of a meeting room opens a setup sheet first:
  destination (connect if needed), quality, Start. The chunks go to `chunk_path`. The meeting
  detail shows the recording status and, when done, the drive link.
- **Settings → Connected drives** (`profile.cloud_drives` feature key): connect / disconnect.
- New inline strings use `t(ar, en)` from `admin_common.dart` (no `translation.json` edits).
- Kill-switch keys: `live.lobby`, `live.share_link`, `live.meeting_recording`,
  `profile.cloud_drives` (add to `../back/services/feature_catalog.py`); guide entries in
  `../back/data/app_features_guide.json`.

### Deviations recorded by the backend (section 5, 2026-10-27)

- Microsoft scope is `Files.ReadWrite offline_access User.Read` — `User.Read` only reads the account's e-mail for
  `GET /me/cloud` (the `email` field); Google stays `drive.file` (its e-mail comes from `drive/v3/about`).
- `GET /me/cloud` providers also carry `label`; the recording summary adds `destination_label`, `file_name`,
  `chunks`, `remote_file_id`; `POST …/recordings` also returns `file_name`. Extra 409s: `not_online` (the meeting is
  offline or cancelled), `not_recording` (a chunk after stop), `not_failed` / `recording_file_missing` (retry).
- The chunk directory and the assembled file live under `CLIENT_RECORDINGS_TMP/meetings/<rid>/` (the setting that
  exists; the spec's `CLIENT_RECORDING_DIR` is that one). Without ffmpeg on the host the chunks are concatenated
  as uploaded (test environments); with it the file is re-encoded at the chosen quality.
- The OAuth redirect base is `APP_URL` (the public backend URL already used by the payment callbacks).

### Deviations recorded by the backend (section 2, grandfathering, 2026-10-27)

- A course session whose `guest_link_token` existed before the lobby release (no `live_room_settings` row when its
  policy is first read or written) gets `guest_admission = auto`, not the `approve` default — its visitors walked
  straight in and still do. The policy answer then carries `legacy_auto: true` (absent otherwise); an explicit
  `PUT {guest_admission}` clears it. Rule in `live_room_service.new_settings`; migration `0018` writes the rows up
  front; new links and meetings default to `approve`. `/public/live/{token}` only reflects the value.

### Deviations recorded by the backend (section 5, hands-off retry, 2026-10-27)

- A failed drive upload is retried by the server itself when the error is transient (network / timeout, 5xx,
  408 / 425 / 429, a token-refresh hiccup): `live_recordings.next_retry_at` is set 2 min, then 10 min, then
  60 min after each failure (3 automatic attempts, `attempts` counts every try), the scheduler's
  `_live_recording_retry_tick` (every 60 s) claims each due row with a compare-and-set UPDATE on
  (status, next_retry_at) → `uploading` and uploads again, and the `live_recording_failed` notification is sent
  once, only when the last automatic attempt fails too. A permanent error (401 / 403 after the refresh = the
  drive is disconnected, quota exceeded, the grant revoked, the file gone, any other 4xx — a deleted Google
  folder is recreated once before a 404 counts) is never retried automatically and notifies at once.
- The recording summary adds `attempts`, `next_retry_at`, `last_error_at` and `retry_mode: "auto" | "manual" |
  null` (`auto`: a retry is scheduled, `manual`: only the owner's Retry is left, null: not failed or nothing to
  retry); `finished_at` stays null while a retry is pending. `POST …/retry` keeps working on any failed row,
  resets `attempts` and the backoff, and answers 409 `not_failed` (`recording_status: uploading`) when the tick
  claimed the row first. Columns `attempts` · `next_retry_at` · `last_error_at` come with migration 0019.
