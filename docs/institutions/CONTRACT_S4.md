# Institutions S4: messaging + must-acknowledge, the API contract

Backend branch `feature/institutions-s4` (D-975 – D-978, migration 0088). Staff prefix
`/api/v1/org/orgs/{org_id}/messages`, member prefix `/api/v1/me`. Errors are
`{"detail": {"code", "message", "message_en", …}}`. Times are naive UTC ISO strings (an aware `expires_at` is
converted). Kill switches: `org.messages` (everything), `org.messages.must_ack` (the must-acknowledge delivery and the
screen).

Normal messages are one-way notices. A reply goes to NextBrain Messages (the existing org chat: `reply.kind ==
"chat"` → start a conversation with `peer_id` in `org_id`) or, for a message about a complaint / request, to that
item's thread (`reply.kind == "item"`; the message is also written into the complaint's thread). The chat is unchanged.

## Who may send

- Any live non-student member of the organization (or of an ancestor): `normal` and `push`, to any student of the
  organization tree. Otherwise 403 `not_org_staff` (students, outsiders, another organization's staff).
- `must_ack`: the org admin, the dean, the vice deans (org-wide role), department heads. Others 403 `ack_not_allowed`.
  A head only to the students of the departments they head (their audience) plus the submitters of complaints /
  requests those departments hold: 403 `ack_out_of_audience`.
- About a complaint / request (`to.complaint_id` | `to.work_item_id`): only the team of the department that holds it
  (head included), 403 `not_dept_team`; the recipient is its submitter only.

## Staff routes

`GET /options`

```json
{"can_send": true, "can_must_ack": true, "must_ack_scope": "all" | "departments" | null,
 "head_dept_ids": [3], "my_dept_ids": [3, 5], "ack_limit": 3, "ack_used_today": 1, "ack_max_days": 7,
 "max_recipients": 5000}
```

`POST ""` → 201

```json
{"delivery": "normal" | "push" | "must_ack", "title": "≤160", "body": "≤4000",
 "reason": "3..500, must_ack only", "expires_at": "2026-11-20T10:00:00 (must_ack: required, ≤ 7 days)",
 "to": {"user_ids": [1, 2], "dept_id": 3, "course_id": 9}  |  {"complaint_id": 4}  |  {"work_item_id": 7},
 "dry_run": false}
```

- `to` fields combine (union); a linked item stands alone (422 `bad_audience`). Answer
  `{"id", "recipients", "queued", "delivery"}`; `queued` = recipients who already had a must_ack waiting (theirs is
  shown later). `dry_run: true` answers `{"dry_run": true, "recipients", "queued"}`, sends nothing, never counts
  toward the daily limit (use it for the composer's "N recipients" line).
- A department's audience: none when its audience leaves students out (422 `no_recipients` if nothing else), a
  scientific department's program students + its courses' active students, every student for a service department
  open to students. `course_id`: the course's active students (404 `course_not_found` outside the org).
- 422: `not_org_student` (`user_ids` of the refused, also another organization's students), `bad_audience`,
  `no_recipients`, `too_many_recipients` (`max`), `message_empty`, `bad_expiry` (past), `ack_reason_required`,
  `ack_expiry_required`, `ack_expiry_too_far` (`max_days: 7`). 404 `dept_not_found`, `item_not_found`.
- 429 `ack_rate_limit` `{limit: 3, retry_after: seconds}`: 3 must_ack per sender in any 24 hours.
- 403 `feature_disabled` when a switch is off.

`GET ""` → `{"total", "items": [message + "stats"]}`, newest first, `limit` (≤200) / `offset`.
Without a filter: the messages I sent in this organization. `?complaint_id=` / `?work_item_id=`: that item's messages,
for its department's team only (404 `message_not_found` otherwise).

`GET /{mid}` → message + stats + recipients. Visible to the sender, the org admin (unlinked messages), the holding
department's team (linked ones); otherwise 404 `message_not_found`.

```json
{"id": 12, "org_id": 1, "delivery": "must_ack", "title": "…", "body": "…", "reason": "…",
 "sender": {"id": 4, "name": "…", "avatar": null}, "dept": {"id": 3, "name_ar": "…", "name_en": null} | null,
 "audience": {"user_ids": [1, 2]}, "complaint_id": null, "work_item_id": null,
 "expires_at": "…", "expired": false, "created_at": "…",
 "stats": {"recipients": 2, "read": 1, "acknowledged": 1, "pending": 1},
 "recipients": {"total": 2, "items": [{"user": {"id": 1, "name": "…", "avatar": null}, "read_at": "…", "acked_at": "…"}]}}
```

`?status=acknowledged|pending|unread`, `limit` (≤500) / `offset`; acknowledged first, by time. An anonymous
complaint's submitter is `{"id": null, "name": null, "anonymous": true}`. `pending` is 0 for non-must_ack messages.

## Member routes

`GET /me/must-ack` → `{"item": member message | null, "queued": 2}`: the ONE must-acknowledge message to show now,
the oldest first, of organizations you are still a live member of, unexpired. `item: null` when there is none, the
switch is off or organizations are off. **The app does not show it while a live exam or a live room is open**; it reads
this again when it leaves them, at start-up / resume, and on the `org_must_ack` event.

`GET /me/org-messages?org_id=&limit=&offset=` → `{"total", "unread", "items": [member message]}` newest first;
expired ones are left out.

`GET /me/org-messages/{mid}` → member message (marks it read). `POST …/{mid}/read` → `{"id", "read_at"}`.
404 `message_not_found` (not yours, ended membership), 410 `message_expired`.

`POST /me/org-messages/{mid}/acknowledge` → `{"id", "acked_at", "next": {"item", "queued"}}`. Idempotent (the first
time is kept). 422 `not_must_ack`, 410 `message_expired`, 404 `message_not_found`.

Member message = the message JSON (without `audience`) plus:

```json
{"org": {"id": 1, "name_ar": "…", "name_en": null, "logo_url": null},
 "read_at": null, "acked_at": null, "needs_ack": true,
 "reply": {"kind": "chat", "peer_id": 4, "org_id": 1} | {"kind": "item", "complaint_id": 4, "work_item_id": null} | null}
```

## Events and notifications

- `org_message` `{org_id, message_id, delivery}` → the recipients (stream only): reload the messages list.
- `org_must_ack` `{org_id, message_id, delivery}` → the recipients (stream + silent push): read `GET /me/must-ack`.
- `org_message_ack` `{org_id, message_id, acknowledged, pending}` → the sender (stream only): re-read the detail.
- Notifications: `related_type: "org_message"`, `related_id` = the message id (normal: in-app row only; push and
  must_ack: row + push, push data `module: "org_message"`, `delivery`, `org_id`). A tap opens the message.

## Audit

`message.normal` / `message.push` / `message.must_ack` (count, reason, expiry, link) and `message.ack` (time) in the
organization's audit log.
