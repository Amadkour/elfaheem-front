# Phase 5 — Appointments, messages, student hub: brief and contract

Read `PLAN.md` §3.2 (threads, messages, attachments, availability, appointments, feedback, templates, notice log),
§3.6, §3.8, §3.10 and `PHASE2.md` (common rules unchanged: own worktree only, `git commit --only`, never push or merge,
`-j 2`, the Python venv, Arabic + English, no placeholders, lead-owned files, report ≤ 15 lines). `PHASE3.md` "Shared
rules" and `PHASE4.md` "Who sees what" apply (roles, list envelope `{items,total,page,size,pages}`, error shape, audit
+ notices through the advising notify helpers, every route: kill switch → eligibility → enabled, then the role; an
advisor asking for a student they don't advise → 404 `advising_not_found`). Brief requirements covered: §2.3
complaints and messages (reply, status, escalate, attachments), §2.3 appointments (availability, office hours, book,
reschedule, cancel, in-person · video · phone · chat, reminders, no-show, meeting notes, time zones, conflicts, .ics),
defaults #6 (thread priority + SLA escalation), #15 (templates), #16 (anonymous survey), #18 (student hub),
#23 (offline drafts for messages too).

## Decisions (made here, state them in the report if you deviate)
- **Times**: stored naive UTC; availability rules are LOCAL wall-clock times in the org timezone (the org's
  `AppTime` zone on the server: the helper the calendar already uses). Slots are computed on read; a day where DST
  shifts still yields correct UTC instants. The app shows every time through `AppTime`.
- **Video**: the availability rule may carry an `https://` link (validated, else 422 `advising_bad_link`); when it has
  none, a video appointment uses the platform's own online meeting (the mirrored `CalMeeting` is `mode=online`, so the
  existing Join flow works). Phone shows the advisor's contact note; chat opens the student's thread.
- **Calendar mirror**: every booked appointment creates ONE `CalMeeting` (owner = advisor, invited student,
  `source_type="advising"`, `source_id` = appointment id, visibility `invited`), so it shows in `/me/calendar` for
  both; cancel / reschedule / complete keep it in sync (cancel → `status=cancelled`). `source_type` column is
  String(20): `"advising"` fits.
- **Conflicts**: a slot is free only when the advisor has no active appointment there AND `calendar_service.busy()`
  says the advisor is free; booking re-checks inside the transaction. Unique active (advisor_user_id, starts_at)
  partial index = two students can never take one slot (the loser gets 409 `advising_slot_taken`). The student must
  also be free (`busy()` → 409 `advising_student_busy`, no force for students; an advisor may pass `force: true`).
- **Booking rules (per policy scope, new settings keys with defaults)**: `booking_min_notice_hours` 2,
  `booking_horizon_days` 30, `cancel_min_notice_hours` 2 (later → the advisor is told; the student can still cancel
  but it counts as late), `max_active_bookings` 2 per student, `no_show_after_minutes` 15 (the advisor may mark
  no-show only after start + this), `sla_hours` per priority reused from Phase 4 for threads,
  `survey_enabled` true. Settings PUT already replaces the whole object: add the keys to its schema with these defaults.
- **Reminders**: 24 h and 1 h before (student + advisor), through the notice log (dedupe key per appointment +
  kind), from the existing 10-minute advising job; retry-safe.
- **Survey (#16)**: completing an appointment issues ONE single-use token (stored hashed) and notifies the student
  with a deep link. The answer row stores org, advisor, term, rating 1–5, optional comment (≤ 1000) and NO student or
  appointment id; the token row is only marked used. Results for the director: count, average, distribution — only
  when n ≥ 5 for the chosen advisor/term, else `{"count": n, "hidden": true}`. Comments shown only with n ≥ 5 too,
  newest first, never with dates finer than the month.
- **Threads**: kinds `message` (either side starts it) and `complaint` (student only). A complaint has `about`:
  `advisor` (about their own advisor: visible to manage ONLY, never to the advisor) or `other` (to the primary advisor,
  like a message). Priority low · normal · high · urgent; `sla_due_at` = created + `sla_hours[priority]` while the
  student's last message is unanswered; overdue → notify the advisor, then manage (escalated_at, once per round).
  Statuses: open · answered (advisor replied last) · closed · escalated. Escalate (advisor or manage) = governance
  complaint work item (`items.create_item(type="complaint")`) owned by the Advising department (fall back to the
  org without dept when none), linked in `adv_case_links` (kind `complaint_escalation`); the thread shows its
  work item id and status. Urgent → advisor + directors notified at once.
- **Attachments**: up to 5 per message, governance `attachments.sniff` + size cap + `put_bytes`, private store,
  served through `GET .../attachments/{id}` → `{"url"}` presigned 10 minutes; only people who can read the thread.
- **Templates (#15)**: kinds `meeting_note · outreach · support_request · message`; system templates seeded per org
  on first read (Arabic + English bodies, placeholders `{student_name} {advisor_name} {date} {time} {org_name}`);
  manage can add / edit / deactivate, system ones can be edited (body) but not deleted (409
  `advising_template_system`). The app fills placeholders on the client before editing; the server never executes them.
- **Rate limits** (`throttle.py`, every call counts): messages 30 / 10 min per user, bookings 10 / hour per user,
  thread creation 5 / hour per student → 429 `advising_rate_limited` with `retry_after_minutes`.
- **Offline drafts (#23)**: the app's `adv_draft_store` keeps unsent messages too; `POST .../messages` takes
  `client_id` (idempotent per thread; reused for another thread → 409 `advising_client_id_conflict`).

## API (base `/api/v1/org/orgs/{org_id}/advising`)

### Availability (advisor edits own; manage edits any advisor)
- `GET /advisors/{uid}/availability` → `{"rules":[{"id","weekday":0-6 (Mon=0),"start":"HH:MM","end":"HH:MM",
  "slot_minutes":15|20|30|45|60,"modes":["in_person","video","phone","chat"],"location":str|null,
  "video_link":str|null,"valid_from":"YYYY-MM-DD"|null,"valid_to":...}],"off":[{"id","from":"YYYY-MM-DD",
  "to":"YYYY-MM-DD","reason":str|null}],"timezone":"Africa/Cairo"}`
- `PUT /advisors/{uid}/availability` body `{"rules":[...]}` (whole list, ids optional) → same shape; overlapping
  rules on one weekday → 422 `advising_rules_overlap`; end ≤ start → 422 `advising_bad_time`.
- `POST /advisors/{uid}/off` `{"from","to","reason"}` → the row; `DELETE /advisors/{uid}/off/{id}`. Days off that
  cover booked appointments do NOT cancel them; the reply carries `"affected": [appointment ids]` so the app offers to
  cancel them with a reason.
- `GET /advisors/{uid}/slots?from=YYYY-MM-DD&to=YYYY-MM-DD&mode=` (≤ 31 days; students only for their own advisors)
  → `{"slots":[{"starts_at","ends_at","modes":[...],"location"}],"timezone"}` (UTC instants).
- Office hours (for the hub / welcome text): `GET /advisors/{uid}/office-hours` → `{"rules":[{"weekday","start","end",
  "modes","location"}],"timezone","next_free": iso|null}` (no links, no off-reasons).

### Appointments
- `GET /appointments?member_id=&advisor_user_id=&status=&from=&to=&page=&size=` (student: own; advisor: own
  advisees / own appointments; manage: all) → items `{"id","member_id","student_name","advisor_user_id",
  "advisor_name","starts_at","ends_at","mode","location":str|null,"video_link":str|null,"meeting_id":int|null,
  "status":"booked|cancelled|completed|no_show","reason":str|null,"cancel_reason":str|null,"cancelled_by":
  "student|advisor|system"|null,"late_cancel":bool,"note_id":int|null,"booked_by":"student|advisor",
  "created_at","can":{"cancel","reschedule","complete","no_show","note"}}`
- `POST /appointments` `{"member_id": int|null (student: omitted = self), "advisor_user_id", "starts_at", "mode",
  "reason": str ≤ 500|null, "force": bool (advisor only)}` → the item. Errors: 409 `advising_slot_taken`,
  `advising_student_busy` (+ `conflicts`), 422 `advising_bad_slot` (not a free slot / outside notice or horizon),
  409 `advising_booking_limit`, 403 `advising_not_your_advisor`.
- `POST /appointments/{id}/reschedule` `{"starts_at","mode"}` → the item (same checks; same row, CalMeeting moved).
- `POST /appointments/{id}/cancel` `{"reason"}` (required for the advisor) → the item.
- `POST /appointments/{id}/status` `{"status":"completed"|"no_show"}` (advisor / manage, only after start; no_show
  only after `no_show_after_minutes`; 409 `advising_too_early`) → the item. Completed → survey token + notice;
  no_show → the student is told, counted in stats.
- Meeting notes: the Phase 4 `POST /students/{mid}/notes` gains `appointment_id` and `template_id`; an appointment's
  note sets `note_id`. Contact mode follows the appointment's mode.
- `GET /appointments/{id}/ics` → `text/calendar` (RFC 5545: UID `adv-<id>@nextbrain`, DTSTART/DTEND in UTC `Z`,
  SUMMARY, LOCATION or the video link, STATUS CONFIRMED/CANCELLED, SEQUENCE grows on reschedule; text escaped per
  the RFC). Same visibility as the item.

### Threads
- `GET /threads?member_id=&kind=&status=&q=&page=&size=` → items `{"id","member_id","student_name","kind",
  "about":"advisor|other"|null,"subject","status","priority","sla_due_at":iso|null,"overdue":bool,
  "last_message_at","last_message_preview" (≤ 140 chars),"unread":int,"work_item_id":int|null,
  "escalated_at":iso|null}`; `unread_total` in the envelope.
- `POST /threads` `{"member_id" (advisor; student omitted = self),"kind","about","subject" ≤ 200,"body" ≤ 5000,
  "priority","attachment_ids":[...],"client_id"}` → the thread with its first message.
- `GET /threads/{id}?before=<opaque>&limit=30` → `{"thread":{...},"messages":[{"id","sender_id","sender_name",
  "mine":bool,"body","attachments":[{"id","name","mime","size"}],"created_at","client_id"}],"next":str|null}`
  (newest last within the page; reading marks it read).
- `POST /threads/{id}/messages` `{"body","attachment_ids","client_id"}` → the message; closed thread → 409
  `advising_thread_closed` (the student may reopen by `status`).
- `POST /threads/{id}/status` `{"status":"open"|"closed","note"}` (student: close / reopen own; advisor: close / reopen).
- `POST /threads/{id}/escalate` `{"note"}` (advisor / manage) → the thread with `work_item_id`; twice → 409
  `advising_already_escalated`.
- `POST /attachments` multipart `file` (+ `thread_id` optional) → `{"id","name","mime","size"}`; bad type → 422
  `advising_bad_file`, too big → 413 `advising_file_too_large`. `GET /attachments/{id}` → `{"url"}`.

### Templates
- `GET /templates?kind=` → items `{"id","kind","name","body_ar","body_en","system","active"}`;
  `POST /templates`, `PUT /templates/{id}`, `DELETE /templates/{id}` (manage).

### Survey
- `GET /survey/{token}` (the student, signed in) → `{"advisor_name","date","answered":bool}`; invalid / used token →
  404 `advising_survey_gone`. `POST /survey/{token}` `{"rating":1-5,"comment"}` → `{"ok":true}`.
- `GET /feedback?advisor_user_id=&term_id=` (manage; an advisor only their own) → `{"count","average","distribution":
  {"1".."5"},"comments":[{"text","month":"YYYY-MM"}],"hidden":bool}`.

### Student hub (the student, own membership only)
- `GET /me` → `{"advisors":[{"user_id","name","type":"primary|co|support","office","contact_note","bio","avatar",
  "office_hours":{...as above},"next_free"}],"upcoming":[appointment items],"past":[last 5],"threads":{"unread",
  "open"},"notes":[student-visible notes, newest 20: {"id","author_name","body","created_at"}],"surveys":[{"token",
  "advisor_name","date"}],"can_book":bool,"booking_rules":{"min_notice_hours","horizon_days",
  "cancel_min_notice_hours"}}`. No flags, risk, internal or sensitive notes ever. Plan / requests come in Phase 7.
- `/status` `me` adds `threads_unread`, `appointments_today`, `surveys_pending`; `/mine?members=1` `advising` adds
  `hub: true` for a student with an active advisor.

### 360 additions
- `GET /students/{mid}/profile` gains `"meetings":{"upcoming":[...],"past":[...],"no_shows":int}` and
  `"threads":{"open","unread"}`; the timeline gains kinds `appointment_booked · appointment_cancelled ·
  appointment_completed · appointment_no_show · thread_opened · thread_escalated`.

### Notices and pushes
New notices (Arabic + English, notice log dedupe): booking (advisor), cancel / reschedule (the other side),
reminders 24 h / 1 h, no-show (student), survey, new message (the other side; collapse to one notice per thread per
10 minutes), thread overdue, escalation. Push data: `kind` + `org_id` + `appointment_id` | `thread_id` | `token`.
Deep links (app): `org_adv_appointment`, `org_adv_thread`, `org_adv_survey`.

### Migration
`0054_advising_appointments` (down `0053`): `adv_availability`, `adv_availability_off`, `adv_appointments` (+ partial
unique), `adv_threads`, `adv_messages`, `adv_message_reads`, `adv_attachments`, `adv_templates`, `adv_feedback`,
`adv_feedback_tokens`, notes gain `appointment_id` / `template_id` if not present; RLS on every table like 0050;
indexes org_id-first. Recheck the number against origin/organizations before the merge (lead does it).

## App (`wt-front-advising`, `lib/features/org/advising/`)
- `adv_availability_page.dart` — weekly rules editor (per weekday rows, slot length, modes, location / link), days
  off list with "affected appointments" → cancel with a reason; reachable from My profile and the advisors page.
- `adv_appointments.dart` — the booking sheet (advisor → date strip → free slots by mode → reason → confirm),
  appointment card + list (upcoming / past), reschedule / cancel sheets, complete / no-show actions, "Add meeting note"
  (opens the notes composer with the template picker and `appointment_id`), "Add to calendar" (.ics: download on web,
  share sheet on phones), Join for video (existing meeting flow) or open the https link.
- `adv_threads.dart` — thread list (filters: status, kind, overdue), thread page (messages, attachments with the
  existing file picker / viewer, composer with offline drafts + `client_id`, template picker for advisors, status and
  Escalate actions with confirmation), new thread / complaint sheet (student: "About my advisor" option explained).
- `adv_templates_page.dart` — list per kind, edit sheet (Arabic + English bodies, placeholder chips).
- `adv_student_hub.dart` — the student's ONE screen (#18): advisor card(s) with office hours and next free time,
  one-tap Book and Message, upcoming / past meetings, student-visible notes, pending survey card, thread list entry.
  Reached from the member dashboard ("My advisor" pill / tile) and the deep links.
- `adv_survey_sheet.dart` — 1–5 rating + optional comment, says plainly that the answer is anonymous.
- 360: a Meetings tab (upcoming / past / no-shows, Book for the student) and a Messages entry; workspace cards show
  unread messages; the director gets "Feedback" (aggregates, hidden below 5 answers) on the advisors page.
- Wiring: deep links + push taps in `adv_wiring.dart` / `app_navigator.dart`, attention counts from `/status`, every
  new error code in `adv_texts.dart` (Arabic + English), times through `AppTime`, layout harness for every new
  widget at 320 / 1400, ar / en, textScaler 1.3.
- Tests: `test/org/adv_appt_models_test.dart`, `test/ui/adv_appt_layout_test.dart`, `test/visual/adv_appt_golden_test.dart`
  (390 / 1440, ar / en, light / dark; use `displayTheme(theme.materialTheme(dark: …), const DisplayPrefs())` as the
  app theme so Arabic names inside English draw, as `adv_case_golden_test.dart` does).

## Backend files (`wt-back-advising`)
`services/organization/advising/` `availability.py` (rules, slots — pure slot maths separated for unit tests),
`appointments.py`, `ics.py` (pure), `threads.py`, `templates.py`, `survey.py`, `hub.py`; router
`routers/organization/org_advising_comm_router.py`; jobs extend the advising job (reminders, thread SLA); tests
`tests/org_v2/advising_slots_unit.py` (DST day, off days, overlaps, notice, horizon, busy), `e2e_advising_appointments.py`
(book race → one winner, reschedule, cancel late, no-show timing, ics, reminders once, survey anonymity: no student id
in the answer row, n < 5 hidden), `e2e_advising_threads.py` (complaint about the advisor invisible to the advisor,
SLA overdue + escalation to a work item, attachments sniffed + presigned + forbidden to others, client_id replay,
rate limits, cross-org attacks on every route). Contract changes in `FLUTTER_API_CHANGES.md`; help page
`org.advising` gains the appointments / messages / hub sections through the migration (help tables are seeded already).
