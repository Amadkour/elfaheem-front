# Learning Hub v2: API contract

The back and front streams build against this file. All routes are under `/api/v1`, every
body is JSON, times are naive UTC ISO strings (`…Z`-less, as everywhere else), errors are
`{"detail": {"code": "...", "message": "..."}}` with the codes listed per section. A change
to this file is made by the lead only; a stream that needs a change writes it under
"Requests" at the end and keeps going.

Migrations: `0115` recording off by default (back-cal, only if a server default changes),
`0116` teachers, `0117` packages (back-core), `0118` games, `0119` self-learning
(back-learn), `0120` meeting series (back-cal). Each one's `down_revision` is the previous
number; `0115` follows `0114`. The chain is only complete after the merge, so each stream
tests its models through the test suite's schema set-up, not `alembic upgrade`; the lead
runs the whole chain on PostgreSQL at integration.

Streams: back-core `_wt/lh2-core-back` (sections 1, 2), back-learn `_wt/lh2-learn-back`
(3, 5), back-cal `_wt/lh2-cal-back` (4 + recording default + `_parse_hhmm`). Shared files
(`feature_catalog.py`, `module_settings.py`, `app_features_guide.json`,
`scheduler_service.py`, `main.py` router list) get small appended blocks only, so the
merge stays mechanical.

## 1. Teachers (one flow, every subject) — back-core

Subjects (closed list, server enum): `quran`, `tajweed`, `fiqh`, `nahw`.

Table `teacher_profiles` (0116) replaces `quran_teacher_profiles`: the migration copies
every row (subjects = `["quran"]`, status `published`→`approved`, `pending`→`pending`,
`draft`→`draft`) and keeps the old table untouched (no more writes). The old Quran routes
keep their paths and shapes and read the new table (subject filter `quran|tajweed|fiqh`),
so installed apps keep working.

```
TeacherProfile {
  user_id, name, avatar_url, gender: "male"|"female",
  subjects: [Subject], bio, qualifications, languages: [str], years_experience: int,
  goals: [str], session_types: ["online"|"offline"],      // kept from the Quran card
  status: "draft"|"pending"|"approved"|"rejected", rejection_reason: str|null,
  submitted_at, reviewed_at,
  documents: [{id, doc_type, file_name, status, rejection_reason}],   // owner/admin only
  rating: float|null, reviews_count: int, packages_count: int,
  next_free: datetime|null                                // public list only
}
```

| Method | Path | Who | Notes |
|---|---|---|---|
| GET | `/me/teacher-profile` | teacher | 404 `no_profile` when none |
| PUT | `/me/teacher-profile` | teacher | whole object (draft fields); editing gender, subjects or qualifications on an approved profile sets it back to `pending` |
| POST | `/me/teacher-profile/documents` | teacher | multipart `file`, `doc_type` in `ijazah|certificate|id|other`; image/PDF ≤10 MB, sniffed; private storage |
| DELETE | `/me/teacher-profile/documents/{id}` | teacher | only while not approved |
| POST | `/me/teacher-profile/submit` | teacher | → `pending`; 400 `profile_incomplete` (name, gender, ≥1 subject, bio, ≥1 document) |
| GET | `/teachers?subject&gender&delivery&price_min&price_max&min_rating&available&q&page&size` | anyone signed in | approved only; `size` ≤50; `{items, total, page}` |
| GET | `/teachers/{user_id}` | anyone signed in | approved only (owner/admin see any); includes published packages |
| GET | `/me/teachers` | student | teachers of the student's active package enrolments, each with `active_packages` and `next_session` |
| GET | `/admin/teachers?status&subject&page` | admin, super admin | queue |
| GET | `/admin/teachers/{user_id}/documents/{id}/url` | admin | `{url}` signed, 60 s, audited |
| POST | `/admin/teachers/{user_id}/approve` | admin | notifies the teacher |
| POST | `/admin/teachers/{user_id}/reject` | admin | body `{reason}` (required, ≤500); notifies |

Errors: `no_profile`, `profile_incomplete`, `profile_locked`, `bad_document`,
`file_too_large`, `not_approved`.

Switches: `teacher_onboarding` (the whole flow), `teacher_discovery` (the student list).

## 2. Packages — back-core

```
Package {
  id, teacher_id, teacher: {user_id, name, avatar_url, gender},
  subject: Subject, title, description, goal, level: "beginner"|"intermediate"|"advanced"|"all",
  delivery: "online"|"offline"|"both", location: str|null,
  sessions_count: int (1..200), session_minutes: int (15..240),
  schedule: RecurrenceRule (section 4)|null, series_id: int|null,
  start_date: "YYYY-MM-DD",
  max_students: int (1..500), overbook: "none"|"allow"|"waitlist",
  price: decimal (0 = free), currency: "EGP"|"SAR"|…, discount_percent: int 0..90|null,
  final_price: decimal,
  status: "draft"|"published"|"paused"|"closed",
  seats_taken: int, waitlist_count: int,
  my_enrollment: {status, position}|null,
  created_at
}
```

| Method | Path | Who | Notes |
|---|---|---|---|
| GET | `/packages?subject&teacher_id&delivery&page` | signed in | published only |
| GET | `/packages/{id}` | signed in | drafts: owner/admin only |
| GET | `/me/packages` | teacher | own packages, any status |
| POST | `/packages` | approved teacher | 403 `not_approved` otherwise; created as `draft` |
| PUT | `/packages/{id}` | owner | whole object; `sessions_count`, `schedule`, `start_date` locked once anyone is enrolled (400 `package_locked`) |
| POST | `/packages/{id}/duplicate` | owner | new draft copy |
| POST | `/packages/{id}/status` | owner, admin | `{status}`; publishing creates the meeting series (section 4) when `schedule` is set |
| POST | `/packages/{id}/enroll` | student | `{status:"active"|"waitlisted", position, checkout: {...}|null}`; 409 `package_full` when full and `overbook="none"`; a paid seat returns `checkout` (the existing payment start payload) and stays `pending_payment` until paid; a waitlisted seat is never charged |
| POST | `/packages/{id}/leave` | student | frees the seat, promotes the first waitlisted student (notified, 24 h to pay) |
| GET | `/packages/{id}/enrollments` | owner, admin | roster |

Errors: `package_full`, `package_locked`, `package_closed`, `already_enrolled`,
`not_approved`.

Switch: `packages`.

## 3. Games — back-core

Engines (server enum, front `kGameEngines`): `quiz`, `match`, `order`, `memory`,
`fill_blank`, `word_puzzle`. Config per engine (validated on the server, 400
`bad_game_config` with `{field}`):

- `quiz` `{shuffle, questions:[{prompt_ar, prompt_en, options:[str] (2..6), answer:int}]}` (1..50)
- `match` `{prompt_ar, prompt_en, pairs:[{a, b}]}` (2..12)
- `order` `{prompt_ar, prompt_en, items:[str]}` (2..12)
- `memory` `{prompt_ar, prompt_en, pairs:[{a, b}]}` (2..10) — flip cards, match a to b
- `fill_blank` `{prompt_ar, prompt_en, items:[{text, answer, options:[str]|null}]}` (1..30); `text` holds one `___`
- `word_puzzle` `{prompt_ar, prompt_en, words:[{word, hint}]}` (1..15); letters shuffled per word

Game fields added (0118): `category` (`quran|tajweed|fiqh|nahw|general`), `difficulty`
(`easy|medium|hard`), `level` (str|null), `cover_url`, `theme` (`sand|sea|night|garden`),
`enabled` (bool). Play adds `time_ms`, and progress adds `attempts`.

| Method | Path | Who | Notes |
|---|---|---|---|
| GET | `/games?category&difficulty` | student | existing; new fields included |
| GET | `/games/{id}/leaderboard?period=week|all&page` | student | `{items:[{rank, first_name, avatar_url, best_score, stars, time_ms}], me}` |
| GET/POST/PUT/DELETE | `/admin/games…` | admin | existing CRUD, now validated per engine |
| POST | `/admin/games/reorder` | admin | `{ids:[int]}` |
| GET | `/admin/games/engines` | admin | `[{key, name_ar, name_en, schema}]` (the registry) |
| GET/POST/PUT/DELETE | `/admin/badges…` | admin | badge CRUD |

Switch: `admin.games` (the editor). The play switches stay as they are.

## 4. Recurring meetings — back-cal

```
RecurrenceRule {
  freq: "daily"|"weekly"|"custom",
  interval: int (1..30),               // every n days/weeks
  weekdays: [0..6] ,                   // 0 = Monday; weekly/custom only
  skip_weekdays: [0..6],               // applied after freq (daily except Fri+Sat)
  skip_dates: ["YYYY-MM-DD"],
  start_date: "YYYY-MM-DD", end_date: "YYYY-MM-DD"|null,   // null = no end
  all_day: bool, start_time: "HH:MM"|null, end_time: "HH:MM"|null,
  tz: "Africa/Cairo"                   // the creator's AppTime zone; wall times are in it
}
```

Series table `cal_meeting_series` (0120) and `cal_series_exceptions`
(`series_id`, `date`, `kind: cancelled|moved|edited`, `starts_at`, `ends_at`, `title`,
`notes`, `location`; unique `(series_id, date)`). Occurrences are expanded on read; a
`cal_meetings` row with `series_id` + `occurrence_date` (unique together) is created only
when an occurrence is opened live or edited.

| Method | Path | Who | Notes |
|---|---|---|---|
| POST | `/me/calendar/series` | as meetings today | `MeetingIn` fields + `rule: RecurrenceRule` + `course_id` (teacher of the course) + `reminder_minutes` (0..1440, default 15); 409 `attendees_busy` on the first 8 occurrences unless `force` |
| GET | `/me/calendar/series/{id}` | owner, attendees | |
| PATCH | `/me/calendar/series/{id}` | owner | edit the whole series from today on (past occurrences keep their data) |
| DELETE | `/me/calendar/series/{id}` | owner | ends the series today; future ones disappear; attendees notified once |
| PATCH | `/me/calendar/series/{id}/occurrences/{date}` | owner | edit one: `{starts_at, ends_at, title, notes, location}` |
| DELETE | `/me/calendar/series/{id}/occurrences/{date}` | owner | cancel one; attendees notified |

Feed: `GET /me/calendar` events of type `meeting` gain `series_id`, `occurrence_date`,
`recurring: true`, `cancelled: bool` (cancelled occurrences ARE returned, so the app can
strike them through), and `rule_summary` is NOT sent (the app writes the sentence).

Reminders: every meeting and occurrence gets a reminder `reminder_minutes` before (default
15; single meetings also gain `reminder_minutes` on `MeetingIn`), through `notify_user`
(in-app, push, email fallback), claim key
`mtg_remind:{series_id|m<meeting_id>}:{starts_at_utc_iso}`.

Recording: every meeting, series and occurrence starts NOT recording.

Switch: `calendar.recurring`.

Also fix: `CourseSchedule` HH:MM is wall time in the platform/org zone, not UTC
(`_parse_hhmm` in `scheduler_service.py`).

## 5. Self-learning — back-core

Subjects as section 1. Settings module `self_learning` in `module_settings.REGISTRY`:
`{enabled:false, subjects:["quran","tajweed","fiqh","nahw"], interval_minutes:240,
daily_limit:3, active_from:"08:00", active_to:"21:00", quiet_from:"22:00",
quiet_to:"07:00", student_can_toggle:true, notify:true}`.

```
SlItem { id, subject, kind: "lesson"|"question", category, title, body (markdown-lite),
         lesson_id: int|null,            // the lesson a question reviews
         question: {prompt, options:[str], answer:int, explanation}|null,
         source: {type:"nahw_lesson"|"quran_range"|null, id|ref}, sort, published }
SlCard { item_id, box: 0..5, due_at, last_result: "right"|"wrong"|null }
```

Leitner: box intervals 1, 3, 7, 14, 30 days; right → next box, wrong → box 1 and due in
10 minutes (still capped by the daily limit and active hours).

| Method | Path | Who | Notes |
|---|---|---|---|
| GET | `/me/self-learning` | student | `{enabled, can_toggle, subjects, today:{lessons:[SlItem], reviews:[SlItem]}, progress:{learned, due, streak_days, per_subject:{…}}}` |
| PUT | `/me/self-learning` | student | `{enabled, subjects}`; 403 `toggle_locked` when not allowed |
| POST | `/me/self-learning/lessons/{id}/seen` | student | idempotent |
| POST | `/me/self-learning/reviews/{id}` | student | `{choice:int, client_id}`; idempotent by client_id; `{right, explanation, card}` |
| GET/POST/PUT/DELETE | `/admin/self-learning/items…` | admin | `?subject&kind&page` |
| POST | `/admin/self-learning/items/reorder` | admin | `{ids}` |

Delivery tick (APScheduler, every 5 min): for each enrolled student, in their zone, inside
active hours and outside quiet hours, below the daily limit and at least `interval_minutes`
after the last delivery: deliver the next lesson (or a due review first), claim
`sl:{user}:{item}:{local_date}`, `notify_user` when `notify`.

Switch: `student_tab_self_learning`, `admin.self_learning`.

## Requests
(streams add here)
