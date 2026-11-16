# Institutions S2: councils, the API contract

Backend branch `feature/institutions-s2` (D-965 – D-970, migration 0086). Staff prefix
`/api/v1/org/orgs/{org_id}/governance`, member prefix `/api/v1/org/public/governance`. Errors are
`{"detail": {"code", "message", "message_en"?, …}}`. Times are naive UTC ISO strings.

## Roster: members, weights, secretary (D-965, D-969)

`GET /councils/{cid}/members` (anyone who can view the council)

```json
{"council_id": 1, "total_weight": 5, "cap_pct": 40, "secretary_user_id": 4, "chair_user_id": 3,
 "items": [{"user_id": 3, "user": {"id": 3, "name": "…", …}, "weight": 1, "is_head": true, "is_chair": true,
            "is_secretary": false, "title": null}],
 "can": {"roster": true}}
```

`PUT /councils/{cid}/members` body `{"members"?: [{"user_id": 5, "weight": 1..3}], "secretary_user_id"?: 4 | null}`

- `members` left out: the team is unchanged (weights still checked). Given: it REPLACES the council's team; the head
  is always kept (with their stored weight when not listed). New members must be staff members of the org
  (422 `not_staff_member` + `user_id`).
- `secretary_user_id` left out: unchanged; `null` clears; must be on the final team (422 `council_settings_invalid`,
  `field: "secretary_user_id"`).
- Weights: 1..3 (422 from validation). Once any weight is not 1, no member may exceed 40 % of the total: 422
  `weight_cap` `{user_id, cap_pct: 40}`. Equal weights are never capped.
- Who: org admin for the faculty council; for a department council also the head of its scientific department or of
  the council entity. The secretary cannot (403 `org_forbidden`, `action: "roster"`).
- Answer: the GET shape.

## Council JSON (additions)

`GET /councils`, `GET /councils/{cid}`, `PUT /councils/{cid}/settings` answers gain:

```json
{"secretary": {"id": 4, "name": "…"} | null, "total_weight": 5,
 "meeting": {"mode": "online" | "in_person" | null, "location": "…" | null, "link": "https://…" | null},
 "settings": {…, "secretary_user_id": 4, "meeting_mode": …, "meeting_location": …, "meeting_link": …},
 "can": {"manage": true, "roster": false, "vote": true}}
```

`can.manage` is now also true for the secretary.

## Settings: meeting setup (D-966)

`PUT /councils/{cid}/settings` accepts three OPTIONAL fields: `meeting_mode` (`online` | `in_person` | null),
`meeting_location` (≤ 255), `meeting_link` (https only, ≤ 500; 422 `council_settings_invalid` `field:
"meeting_link"`). Unlike the other fields, one left out keeps its stored value. Changing the setup re-syncs the
calendar meetings of the open sessions. Changing `chair_user_id` needs the roster right (403 `org_forbidden`, `action:
"roster"`): send the stored chair back unchanged.

## Sessions (D-966, D-968)

- `POST /councils/{cid}/sessions` and `PATCH /sessions/{sid}` accept `review_deadline` (datetime | null). At opening,
  a deadline still ahead becomes `voting_closes_at`, else opening + `voting_deadline_hours`. A PATCH while voting moves
  `voting_closes_at` too.
- Session JSON gains:

```json
{"review_deadline": "2026-11-25T10:00:00" | null, "manual_reminded_at": "…" | null,
 "meeting": {"mode": "online", "location": null, "link": null, "cal_meeting_id": 12 | null, "room": true},
 "can": {…, "remind": true, "write_item": true, "declare_conflict": true}}
```

`meeting.cal_meeting_id` is the `/me/calendar` meeting (owner = the chair, the council team invited, 2 h long);
`room: true` = it uses the platform's meeting room (online without a link of its own).

## Write an item (D-967)

`POST /sessions/{sid}/agenda/write` (manager: chair, secretary, admin, …) body
`{"title": "…" (1..255), "body"?: "…", "template_key"?: "[a-z0-9_]{1,40}"}` → 201 with the full session JSON.
Session must be draft / published / voting (409 `session_state`). 422 `title_required`, `template_key_invalid`. The
row's `council_written` is true; its writer still votes on it.

## Remind non-voters (D-968)

`POST /sessions/{sid}/remind` (manager), no body → `{"reminded": 3, "manual_reminded_at": "…", "next_allowed_at":
"…"}`. Only while the session is `voting` (also after `voting_closes_at` until it is closed; else 409
`session_state`). At most once an hour per session: 429 `remind_too_soon` `{retry_after: <seconds>, last_at}`.
Nobody pending → `reminded: 0`, the hour is not used. Push title «تذكير بالتصويت — <council>», `related_type:
org_council_session`, `related_id: <sid>`.

Automatic (server tick): 48 h, 24 h and 2 h before `voting_closes_at`, to non-voters only, once per member and step.
The 24 h step is the existing «يُغلق التصويت خلال 24 ساعة» notice (every member, unchanged).

## Conflict of interest (D-969)

`POST /agenda/{aid}/conflict` (staff) and `POST {member prefix}/agenda/{aid}/conflict` (member app), body
`{"note"?: "…"}` → the agenda row JSON. Members only (403 `not_a_voter`); refused once the row is decided (409
`voting_closed`). Idempotent. A vote already cast is withdrawn; voting afterwards → 403 `conflict_declared`.

## Agenda row JSON (additions)

Every agenda row (in session JSON, vote replies, `GET /agenda/{aid}/results`):

```json
{"decision_no": "1/2/2026" | null, "template_key": "exam_committees" | null,
 "result": "approved_full" | "approved_partial" | "rejected" | "no_quorum" | "pending",
 "coi_count": 1, "my_coi": false, "council_written": false,
 "voters": [{"user_id": 4, "name": "…", "user": {…}, "vote": "approve", "weight": 2, "note": "…", "at": "…"}] | null,
 "non_responders": [{"user_id": 6, "name": "…", "user": {…}, "weight": 1}] | null,
 "weights": {"approve_w": 3, "reject_w": 1, "abstain_w": 0, "eligible_w": 4, "voted_w": 4, "needed_w": 2} | null}
```

`voters` / `non_responders` / `weights` follow the existing `votes` visibility: managers (live while voting, `needed_w`
null then) and everyone after the close; null otherwise. A member with a declared conflict is in neither list.
`approve_count` / `reject_count` / `abstain_count` stay COUNTS; `approve_pct` is now by weight.

`GET /agenda/{aid}/results` (anyone who can view the council) → that row.

## Tally (D-969)

quorum: `voted_w ≥ needed_w = max(1, ceil(eligible_w × quorum_pct / 100))`. approved when `approve_w > reject_w` and
(no `majority_pct`, or `approve_pct ≥ majority_pct`); `approve_pct = approve_w / (approve_w + reject_w [+ abstain_w
when abstain_counts] [+ silent weight when no_vote_rule = abstain]) × 100`. Equal weights → `tie_rule`. Full = every
cast vote approves. Eligible = the team minus the item's submitter minus declared conflicts. All weights 1 = the old
results exactly.

## Decision numbers and minutes (D-970)

At the close, each row decided approved or rejected gets `decision_no = session_no/item_no/year` (the session's rank
among the council's closed sessions of the year, the row's agenda position, the year). `GET /sessions/{sid}/minutes`:
`minutes.items[]` gain `decision_no`, `result`, `template_key`, `weights`, `coi_count`; `text_ar` / `text_en` print
«قرار رقم 1/2/2026» / "Decision no. 1/2/2026" after the item title.

## Kill switch

None new: everything sits under `org.governance`.
