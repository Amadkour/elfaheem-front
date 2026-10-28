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

---

# Part 2 (2026-10-28): quick meetings · student live plan · points · direct guest link · room info

Same conventions as above: errors are `{"detail": {"code", "message", …}}`, times naive UTC ISO, new app strings
inline `t(ar, en)`. Schema: ONE new Alembic revision `0020_points_live_plan` (+ the models, so the e2e scripts get
them from `create_all`).

## 7. Quick meeting ("Meet now")

```
POST /api/v1/me/calendar/meetings/quick   {title?: str ≤200, minutes?: int 15..240 = 60, org_id?: int}
→ 201 the meeting detail (same shape as POST …/meetings): mode online, private (no audience), starts now,
       ends now + minutes, room_name set. No title → the date title below.
```

**Optional title for online meetings (added 2026-10-28).** `POST …/meetings` and `/meetings/quick`: when
`mode = online`, `title` may be omitted, null, empty or blank; the server then stores the meeting's start as its
title, `YYYY-MM-DD HH:mm` in the organization's timezone when `org_id` is set, else the platform timezone (the same
timezone the app's `AppTime` shows). A `PATCH` that sends an empty title for an online meeting does the same.
Offline meetings keep the title required (422 as today). App: the meeting form's title field is optional while
Online is selected (hint "Optional, the date is used"), and the quick meeting sends no title.
Any signed-in user (students too: it is online + private by construction). Feature key `live.quick_meeting`.
App: a "Meet now" button next to "New meeting" on the calendar (and on the student / teacher "My schedule"
upcoming-meetings card when present) → create → `PreJoinPage(JoinArgs(..., autoJoin: true))`, which presses Join
by itself as soon as the devices are ready (no tap) → the room. The owner is the host (lobby, link, record).

## 8. Students and the live-meeting plan

A **student** = a user whose role is not in `subscription_service.STAFF_VALUES`.

* **Online + private only.** A student's `POST …/meetings` and `PATCH …/meetings/{id}` must keep `mode = online`
  and an EMPTY audience (the app's "Only me"; people come through the share link) → else 422
  `student_meeting_online_private`. `meeting_detail` gains `owner_is_student: bool`.
* **Free time.** A student-owned meeting whose owner has no active plan is free for `live_meeting_free_minutes`
  (app setting, default 15) of LIVE time per meeting, counted from the room's first successful join (new column
  `cal_meetings.live_started_at`, set once). After that:
  - `POST …/meetings/{id}/join` → owner: 402 `live_plan_required` {price_points, days, balance}; anyone else:
    403 `meeting_time_limit`. The public / link guest joins of that meeting → 403 `meeting_time_limit`.
  - a scheduler tick every 60 s (`_live_plan_tick`) deletes the LiveKit room of every live, over-limit,
    unplanned student meeting (ends it for everyone) once, and notifies the owner (type `live_plan_required`,
    deep link `live_plan`).
  - Every successful meeting join payload (200 owner / member / admitted guest) carries
    `time_limit: {ends_at: iso, free_minutes: int} | null` (null = unlimited). `meeting_detail` carries the same
    `time_limit` plus `owner_plan_active: bool` (meaningful for the owner; false for others).
  - The limit is computed on every check: subscribing mid-meeting lifts it at once; the same meeting can be
    rejoined after subscribing.
* **The plan:** `live_meeting_price_points` (default 30) points for `live_meeting_plan_days` (default 30) days.

```
GET  /api/v1/me/live-plan            → {active, ends_at|null, price_points, days, free_minutes, balance, needed}
POST /api/v1/me/live-plan/subscribe  → 200 same shape (debits the price; starts now, or extends an active ends_at)
                                       402 points_insufficient {balance, price_points}
```
Staff never need it: `needed: false`, `active: true`, `ends_at: null`; their subscribe → 409 `plan_not_needed`.

## 9. Points wallet

Tables: `user_points` (user_id PK, balance int ≥ 0, updated_at), `points_ledger` (id, user_id, delta,
balance_after, kind grant|deduct|topup|spend|refund, ref_type, ref_id, note, by_user_id, created_at),
`points_topups` (id, user_id, points, amount, currency, method bank_transfer|instapay, receipt_key, status
pending|approved|rejected, note, decided_by, decided_at, created_at), `service_subscriptions` (id, user_id,
service 'live_meeting', starts_at, ends_at, points, ledger_id, created_at). A debit is ONE conditional UPDATE
(`… WHERE balance >= :p`), never read-then-write; an approve is a compare-and-set on `status = 'pending'`.
App settings (AppSettingsService DEFAULTS, edited by the super admin): `live_meeting_free_minutes` 15,
`live_meeting_price_points` 30, `live_meeting_plan_days` 30, `points_price` 1.0 (money per point),
`points_currency` "SAR", `points_topup_min` 10.

```
GET  /api/v1/me/points                 → {balance, price_per_point, currency, topup_min, methods: [...],
                                          history: [ledger rows, newest first, ≤50], topups: [mine, ≤20]}
POST /api/v1/me/points/topups          multipart: points (int ≥ topup_min), method, receipt (image / pdf ≤ 10 MB)
                                       → 201 {id, points, amount, currency, method, status, created_at}
Admin (admin / super-admin / developer):
GET  /api/v1/admin/points/users?q=&page=      → {items: [{user {id,name,email,phone,role}, balance}], total}
POST /api/v1/admin/points/grant               {user_id, points (≠0; negative = deduct), note} → {user_id, balance}
                                               422 points_negative_balance when a deduct would go below 0
GET  /api/v1/admin/points/users/{uid}/history → {items: ledger rows}
GET  /api/v1/admin/points/topups?status=pending|approved|rejected → {items: [topup + user]}
POST /api/v1/admin/points/topups/{id}/approve · …/reject   {note?} → topup  (409 topup_decided)
GET  /api/v1/admin/points/topups/{id}/receipt → the file
GET  /api/v1/admin/points/settings · PUT {the six settings} → the settings
```
Notifications: top-up approved / rejected (type `points_topup`, deep link `points`), plan bought (`live_plan`).
Feature keys: `profile.points` (the wallet and the live plan), `admin.points` (the admin page).

## 10. Direct guest link (the waiting icon)

`live_room_settings.link_direct` (bool, default false, for BOTH kinds: a session's settings row holds it too).

```
PUT /api/v1/live/{kind}/{id}/link   gains  direct?: bool   (omitted = unchanged)
the link payload (GET / PUT …/link) gains  direct: bool
GET /api/v1/public/live/{token}     gains  auto_join: bool  (= the link is direct)
```
A guest entering through a DIRECT link is admitted at once (as if `guest_admission = auto`); the PIN, block,
guest limit and the meeting time limit still apply. A signed-in non-member through it too. Members keep the
member door. App: the room's waiting (lobby) button opens `LobbySheet`, whose top card is **"Quick guest link"**:
one tap creates the link if missing (`PUT …/link {direct: true, can_publish: true}`) or turns an existing one
direct, then Copy / Share / QR; a switch turns direct entry off again. The guest page (`/live/<token>`) with
`auto_join`: signed in → joins with the account at once; a remembered guest name → joins at once; otherwise only
the name field (autofocus) → Join; the pre-join step then presses Join by itself (`JoinArgs.autoJoin`).

## 11. Room: record button, info, time limit

* **Record** (the meeting creator, `canRecord`): a labelled red "Record" / "Stop" action in the control bar's
  primary group (not hidden in More), and the top chip larger with a pulsing dot while recording.
* **Info** (everyone): an (i) chip at the top beside Minimize → `MeetingInfoSheet` (plain values): title, kind,
  host, scheduled time, live time elapsed, participants count, your role, the share link with Copy (host), the
  admission rules (host), the recording state, the free time left.
* **Time limit:** `LiveResponseModel.freeEndsAt` (from `time_limit.ends_at`) → `RoomPage.freeEndsAt`: a countdown
  pill for everyone; the owner, from 3 minutes left, gets "Upgrade" → `showLivePlanSheet(context)` in
  `lib/features/shared/points/live_plan_sheet.dart` (signature `Future<bool> showLivePlanSheet(BuildContext
  context)`, true = subscribed); after subscribing the pill disappears. When the server ends the room for the
  limit, the owner sees "Free time ended" with Subscribe.

### Deviations recorded by the backend (Part 2, 2026-10-28)

- The revision is `0021_points_live_plan` (Revises `0020`): `0020` was already the theme-contrast fix.
- One extra column, `cal_meetings.live_limit_ended_at`: the scheduler's `_live_plan_tick` claims each over-limit
  meeting with a compare-and-set on it, so a room is ended and its owner notified ONCE across workers.
- `PUT /live/{kind}/{id}/link` did not exist before (only POST): it is new, every field optional and omitted =
  unchanged (`can_publish`, `max_guests` with null = unlimited, `pin`, `clear_pin`, `rotate`, `direct`), and it
  creates a missing link. `POST …/link` takes `direct` too. Deleting the link resets `direct` to false. The old
  `/live-sessions/{id}/guest-link` payload does not carry `direct`.
- Extra fields: `meeting_detail.live_started_at`; top-up items `note`, `has_receipt`, `decided_at` (+ `user` in
  the admin list); the users list `page`, `size`; the history route `balance`; `topup_decided` carries
  `topup_status`. Extra codes: 422 `title_required` (offline meeting without a title), `points_zero`,
  `points_below_min {topup_min}`, `bad_method`, `receipt_invalid`, `bad_setting`; 404 `user_not_found`,
  `topup_not_found`, `receipt_missing`; 403 `admin_required`; 502 `receipt_upload_failed`.
- A guest whose lobby request was admitted but who polls after the free time ran out gets 403
  `meeting_time_limit` (not `expired`); a member's admitted poll likewise.
- Receipts always go to the PRIVATE bucket (`services/private_storage.py`), whatever `PRIVATE_SENSITIVE_UPLOADS`
  says; `GET …/topups/{id}/receipt` streams the bytes with the file's own content type.
- `/api/v1/me/points*` and `/api/v1/me/live-plan*` are open past the subscription paywall (and the device guard's
  list), like `/subscriptions`: the wallet is the user's own money.
- Push data: `live_plan_required` → `{type: live_plan, meeting_id, id}` (`related_type: meeting`), plan bought
  `live_plan` → `{type: live_plan, id}`, `points_topup` → `{type: points, id, status}`.

---

# Part 3 (2026-10-28): card top-ups · daily free cap · plan reminders and auto-renew · public API base · live time · stuck uploads

## 12. Public API base for every callback

Production nginx strips one `/api` (`location /api/ → :8000/`), so the API root's public URL is
`https://nextbrain.site/api` while `APP_URL` is `https://nextbrain.site`. New setting `PUBLIC_API_BASE_URL` (the
public URL of the API ROOT; empty = `APP_URL`) and ONE helper `config.public_api_url(path)` (path starts with
`/api/v1/…`). Every URL handed to an outside party that must reach the API uses it: Moyasar / Paymob callback and
webhook URLs (`routers/checkout.py`, `routers/webhooks.py`, `payment_providers/*`, the org creation fee), the cloud
OAuth redirect (`CLOUD_OAUTH_BASE_URL` still wins when set, then `PUBLIC_API_BASE_URL`, then `APP_URL`). Links meant
for the WEB APP (`FLUTTER_APP_URL`, `PUBLIC_WEB_URL`, login links) are not touched.

## 13. Buy points by card

```
POST /api/v1/me/points/checkout     {points: int ≥ topup_min, provider?: "moyasar"|"paymob"}
→ 201 {topup_id, provider, amount, currency, …whatever the app needs to open the provider's payment page,
       exactly like the course checkout returns it}
GET  /api/v1/me/points/topups/{id}  → the top-up (the app polls it after the payment page closes)
```
A card top-up is a `points_topups` row with `method = "card"`, `provider`, `payment_id`, status `pending`. The
provider's callback / webhook is verified server-side (fetch the payment from the provider, check amount and
currency, the same way course payments are verified) and credits the points ONCE (compare-and-set on
`status = pending`; a repeated callback is a no-op). Failed / cancelled → `rejected` with the provider's reason.
Notification on success (`points_topup`, deep link `points`). Settings: `points_card_enabled` (default true) — the
`methods` list of `GET /me/points` includes `card` only when it is on and a provider is configured. Admin
"Top-ups" lists card rows too (read-only: they were decided by the provider).

## 14. Daily free-time cap for students

Setting `live_meeting_free_minutes_daily` (default 30; 0 = no daily cap). When a student's unplanned meeting goes
live (its first join stamps `live_started_at`), it gets `free_window_minutes = min(live_meeting_free_minutes,
daily_left)` (new column `cal_meetings.free_window_minutes`, set once), where `daily_left` = the daily cap minus the
`free_window_minutes` of the owner's meetings that went live TODAY (platform timezone day). `daily_left = 0` → the
owner's first join gets 402 `live_plan_required` with `reason: "daily_limit"`; others 403 `meeting_time_limit`.
The meeting's limit is `live_started_at + free_window_minutes`. `time_limit` gains `daily_minutes` and `daily_left`;
`GET /me/live-plan` gains `daily_free_minutes` and `daily_free_left`.

## 15. Plan reminders and auto-renew

`PUT /api/v1/me/live-plan {auto_renew: bool}` → the plan payload, which gains `auto_renew`, `days_left`.
Stored per user (`user_points.live_auto_renew`, default false). An hourly tick:
* a plan ending within 3 days, not yet reminded → notification `live_plan_expiring` (deep link `live_plan`), stamped
  (`service_subscriptions.reminded_at`) so it is sent once;
* a plan that has ended (no newer plan) with auto-renew on → ONE conditional debit + a new 30-day plan starting at
  the old `ends_at` (ledger kind `spend`, note `auto_renew`), notification `live_plan_renewed`; not enough points →
  notification `live_plan_renew_failed` once (stamp `renew_failed_at`), auto-renew stays on for a later top-up.

## 16. The meeting's real live time

Every meeting join payload (owner / member / admitted guest) and `meeting_detail` carry `live_started_at` (the
room's first join); a course session's join payloads carry the online session's start time under the same key.
App: `LiveResponseModel.liveStartedAt` → `RoomPage.liveStartedAt` → the info sheet's "Live for" counts from it
(falls back to the person's own time in the room when absent).

## 17. Recovering stuck recording uploads

A meeting recording left in `uploading` (or `assembling`) longer than 30 minutes (by its claim / `updated_at`) means
the worker died. The existing retry tick takes it back with the same compare-and-set as a retry: it is treated as a
transient failure (attempt counted, `last_error` "worker_lost"), so it either uploads again or, after the last
attempt, fails with the usual notification. Never two workers on one row.


### Deviations recorded by the backend (Part 3, 2026-10-28)

- Revision `0023_points_card_renew` (Revises `0022`; `0024` users.ui_prefs now sits on top of it). Besides the
  columns named above it adds `points_topups.checkout_token` (unique; our token in the callback URL and the gateway's
  merchant order id) and `points_topups.meta` (JSON: the Paymob signed order id, the Moyasar id, the sanitized gateway
  object), a unique index on `(provider, payment_id)` (one gateway transaction pays one top-up), and
  `live_recordings.updated_at` (bumped on every write; the §17 clock).
- §13 browser return: `GET /api/v1/payments/callback/points/{provider}?token=…` (an HTML page, under the already-open
  `/api/v1/payments/callback` prefix) with the course checkout's handshake: it redirects after 2.5 s to
  `FLUTTER_APP_URL/#/payment/callback?status=paid|initiated|failed&topup_id=…[&message=…]` and posts
  `{paymentStatus, moyasarStatus, topupId}` to `window.parent`; the app may simply poll `GET /me/points/topups/{id}` as planned. Plus `POST
  /api/v1/payments/callback/points/moyasar/attach {token, id}` (the Moyasar page reports its payment id; stored only,
  then `GET /me/points/topups/{id}` asks Moyasar with the secret key at most once a minute after the first minute).
- §13 checkout response, exactly like the course checkout plus the top-up: `{status: "checkout", already_paid: false,
  topup_id, provider, points, amount, currency, checkout_url, session_token, amount_minor, is_sandbox, topup}`.
  Codes: 409 `card_unavailable {providers}` (switch off, card method closed in Admin → Payment methods, or no
  configured provider charging in `points_currency`), 422 `bad_provider`, 422 `points_below_min`, 502 `gateway_error`.
  `GET /me/points` also returns `card_providers` (default provider first). Top-up items gain `provider`, `payment_id`,
  `failure_reason`; a rejected card row carries the provider's reason in `note` too (what the app shows).
  `failure_reason` is `declined: <provider message>`, `amount_mismatch expected=… actual=…`,
  `currency_mismatch …` or `transaction_reused`. Admin approve / reject of a card row → 409 `topup_by_card
  {topup_status}`. A later VERIFIED success repairs a `declined` row (the money moved); a mismatch never.
- §14 the 402 `live_plan_required` and the 403 `meeting_time_limit` always carry `reason`: `daily_limit` or
  `meeting_limit` (the per-meeting window); the 402 also `daily_minutes` and `daily_left`. With no cap
  (`daily_minutes: 0`) `time_limit.daily_left` and the plan's `daily_free_left` are null; for staff
  `daily_free_left` is null. A meeting that went live while its owner had a plan has no fixed window: if the plan
  lapses it gets the per-meeting minutes and does not count against the day. Two of one student's meetings going live
  in the same instant can together exceed the day's cap by one window (not serialized).
- §15 `PUT /me/live-plan` by staff → 409 `plan_not_needed`. `days_left` = whole days left (floor), 0 without a plan,
  null for staff. Auto-renew: a renewal within 2 h of the old end starts at the old end; a later one (e.g. after a
  top-up following `live_plan_renew_failed`) starts NOW, so the student never pays for days already lost. Plans
  that ended more than 7 days ago are not renewed by the tick any more. The debit holds the wallet row and the
  "no newer plan" check runs after it, so a manual purchase at the same moment wins and nothing is charged twice.
  The tick is `_live_plan_renew_tick` (hourly).
- §16 also in the admitted guest / member lobby poll payloads (they are join payloads).
- §17 an upload that was in progress already counted its attempt; a lost assembly counts one. A stuck `assembling`
  row with its chunks still on disk is re-assembled (not only re-uploaded). The recovery uses the real clock (not the
  tick's `now` used for due retries).
- Notification taps: `GET /api/v1/notifications/{id}/target` answers `{module: "live_plan"}` for the types `live_plan`,
  `live_plan_required` (although its related_type is `meeting`), `live_plan_expiring`, `live_plan_renewed`,
  `live_plan_renew_failed`, and `{module: "points"}` for `points_topup` (`target_id` = the related id).
