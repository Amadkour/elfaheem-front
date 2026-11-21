# Learning Hub v2: live fixes, self-learning, teachers, packages, games, recurring meetings

## Context
The owner's brief: fix three meeting bugs, then extend Learning Hub (games, Quran, Nahw, shipped 2026-11-21) with:
- a shared self-learning engine;
- one teacher onboarding and approval flow;
- standalone packages;
- a games registry with an admin editor;
- recurring meetings.

Base: NextBrain production (front 173b6f02, back 44edd0b5). Afterwards, Alfaheem gets it through the usual sync, and no Alfaheem names go into NextBrain.

Owner decisions (2026-11-21):
- Packages are a new table that reuses the checkout, and their schedule becomes a recurring meeting series.
- Existing Quran programs (course-based) stay as they are.

The current Learning Hub state is known from exploration. These already exist and are reused:
- games admin CRUD API with no editor;
- the Quran teacher card with verify;
- `TeacherDocument` approval;
- `private_storage` and onboarding `documents.py` (magic-byte sniffing);
- APScheduler and `live_claims` for idempotency;
- notification `_dispatch` (in-app, then push, then email);
- `feature_catalog` and `module_settings` (platform ← country ← org);
- the org timetable pattern (weekly slots + an exceptions table, expanded on read).

The following do not exist yet: self-learning / spaced repetition, packages, waitlists outside the registrar, meeting recurrence and meeting reminders.

## Working setup
- Branch `feature/learning-hub-v2` from origin/production in both repos, with one worktree per stream (`_wt/lh2-<stream>-front|back`).
- Migrations start at 0115, chained in merge order; decisions start at D-1500.
- Execution agents run on Opus. Fable writes the contract up front, then does one final review.
- Commits use `--only`. Push and deploy only when the owner says so.
- Tests cover the changed code only.

## Streams (parallel unless marked)

### S1. Live fixes (front only, mainly `lib/features/**/live/room.dart`)
- **A1 annotation:** root cause is that `AnnotationLayer` only wraps `_PremiumScreenShareView` (room.dart:7017). `_canAnnotate` also turns false in burned-in mode (room.dart:4650, 4700), and full view puts the pen down (4460).
  - Fix: once the Android overlay is granted, keep the in-app layer and toolbar available while the app is in front; burned-in applies only when backgrounded.
  - Allow the pen on a share in full view (extend D-108 r7 from the board to the share).
  - Wrap the share in the stage-swap and tile views with the same `_AnnotatedShareVideo`, which already uses normalized coordinates and `AnnotFit.contain`.
  - `canDraw` and the sender check stay unchanged.
- **A2 camera:** in `live_config.dart` and `live_settings_service.py`:
  - host default 720p at 30 fps;
  - top layer ~1.7–2.0 Mbps (fix `cameraBitrateKbps`, which yields 1.28);
  - simulcast layers 720/360/180, `degradationPreference: maintainResolution` for the host camera;
  - adaptiveStream and dynacast stay on;
  - a "high" option allowing 1080p when bandwidth allows, as an admin live setting.
  - Screen-share presets stay separate. Also align the screen max fps (server 15, app 30).
- **A3 recording:** `record_enabled` default False:
  - `SessionModel` column default + migration 0115 (new rows only; existing rows unchanged);
  - `POST /sessions`, quick session, scheduler slot session (`scheduler_service.py:195`) and course-profile term sessions;
  - `liveRecordsAtStart` returns false unless the session has `record_enabled=true` explicitly set by the host;
  - the go-live and session form toggles default to off;
  - the record indicator in `live_top_row.dart` reads "Not recording · Record" for every room type.
  - Meetings already open stopped.

### S2. Foundations backend + contract (blocks S3–S6 front; Fable writes CONTRACT.md first)
1. **Teacher onboarding (one flow, every subject):** generalize `quran_teacher_profiles` into `teacher_profiles` (migration with a backfill copy; keep the old table as a read view for old apps).
   - Fields: subjects[] (quran, tajweed, fiqh, nahw), gender, bio, qualifications, languages, years, photo, status draft/pending/approved/rejected + reason.
   - Attachments reuse `TeacherDocument` + onboarding `documents.py` sniffing (image/PDF ≤10 MB, private bucket, 60 s signed links).
   - Admin approve/reject reuses the existing verify endpoints, with a reason, `notify_user` and an audit row.
   - Only approved teachers can publish a package (server check).
2. **Self-learning engine** (`features/self_learning/`):
   - Tables: `sl_items` (subject, kind lesson|question, body, answers, order, category), `sl_enrollments` (user, subjects, on/off), `sl_cards` (user, item, box, due_at, last_result; Leitner intervals 1/3/7/14/30 days, a miss goes back to box 1), `sl_deliveries` (unique user+item+date).
   - Settings are a `module_settings` module `self_learning`: enabled, subjects, interval_minutes, daily_limit, active hours, quiet hours, student_can_toggle.
   - An APScheduler tick every 5 minutes works per user in their AppTime zone and claims `sl:{user}:{item}:{yyyymmdd}` through `live_claims` before calling `notify_user`.
   - Nahw lessons and Quran meta can be referenced as items, so there is no duplicate content.
3. **Packages** (`features/packages/`):
   - Tables: `packages` (teacher, subject, title, description, delivery online/offline/both, sessions_count, duration, schedule → `series_id`, max_students, overbook none|allow|waitlist, goal, level, price, currency, discount, start_date, status draft/published/paused/closed) and `package_enrollments` (status active/waitlisted/cancelled, position).
   - Capacity is enforced under a row lock; the waitlist is promoted on cancel.
   - Checkout reuses the existing card/points flow through a `payable_type='package'` hook (enrolment_provider + payment service).
   - Duplicate, pause and close are supported.
4. **Recurring meetings** (`features/home/` calendar):
   - `cal_meeting_series`: owner, title, mode, location, room, course_id nullable, RRULE string, dtstart wall time + tz, until nullable, all_day / time window, excluded weekdays, record default false, reminder_minutes default 15.
   - `cal_series_exceptions`: date → cancelled | moved | edited fields.
   - Expansion happens on read in `events_for` within the ≤62-day range, like `_timetable_events` (`wall_to_utc` is DST-safe). A concrete `cal_meetings` row is created only when an occurrence is joined or edited.
   - Add `python-dateutil` for rrule (pubspec unaffected).
   - Edit one or all, cancel one (notify attendees).
   - The reminder tick claims `mtg_remind:{series|meeting}:{occurrence_utc}`, so a moved occurrence gets reminded again. Single meetings get reminders too.
   - Also fix the `CourseSchedule` timezone bug (`_parse_hhmm` reads times as UTC).
5. **Games registry:**
   - Per-engine config validation server-side (modelled on `nahw_bad_exercise`), with engines quiz, match, order, memory, fill_blank and word_puzzle.
   - Game fields: `template_key`/theme/category/difficulty/level/cover/sort.
   - Badge CRUD API.
   - Results already exist (`game_plays`/`game_progress`); add `time_ms` and attempts, plus a leaderboard endpoint (paginated, per game/category, privacy: first name only).
6. **Switches:** new keys in `feature_catalog.py` (`student_tab_self_learning`, `packages`, `teacher_onboarding`, `calendar.recurring`, `admin.games`, …) and in `app_features_guide.json`, then regenerate the contract snapshots. Seed: extend `load_learn_seed.py` with a few lessons and questions, one package, one game of each new engine.

### S3. Self-learning + Nahw front (after the contract)
`lib/features/self_learning/`:
- a lesson card with a single entrance animation;
- a review card with instant feedback and a small celebration;
- a progress ring with learned / due / streak.

It is used by a Quran tab section and the Nahw tab, both reusing `learn_kit`. Also: an admin content page (items, questions, order) in the module page style, and the student on/off control in settings. Motion goes through `syncMotionLoop`, tokens and `AppCard`, and nothing hard-coded.

### S4. Teachers, packages, discovery front
- **Onboarding wizard:** profile → subjects → attachments (`AppField` and the existing upload sheet), plus a pending state screen.
- **Admin review queue** extending `quran_admin_page.dart` into a subject-filtered list.
- **Package wizard** of three steps (basics, schedule via the recurrence picker from S5, price & capacity) with defaults, a live summary and duplicate/pause/close.
- **Discovery:** teacher list with filters (gender, subject, delivery, price, rating, availability) and search; a teacher profile page (`CourseSpace` style slots); a "My teachers" list with active packages and the next session.
- Every screen uses `BasePage`, the `AppListSkeleton` / `AppEmpty` states and `expectNoLayoutErrors`.

### S5. Recurring meetings front
In `calendar_meeting.dart`:
- a "Repeats" section: daily / weekdays chips / custom interval, an end date or "no end", any time or from–to, skip weekdays and skip dates;
- a live summary sentence built with `AppTime` and `countText` (ar/en);
- a recurring badge in the `SchedulePage` events;
- "this occurrence / whole series" choices on edit and cancel;
- cancelled occurrences struck through;
- a "Repeat" entry inside the course sessions timeline (course_id set).

The picker is a widget shared with the package wizard.

### S6. Games front
- New engines `memory`, `fill_blank`, `word_puzzle` in `kGameEngines`.
- A shared `GameShell`: progress bar, sound effects (small bundled assets, lazily loaded, a mute toggle stored per user), correct/wrong feedback (a light particle painter, parked under Reduce motion), a stars/points/badge finish screen.
- Existing engines move into the shell.
- An admin game editor: list (enable, category, difficulty, level, cover, drag reorder) and a typed form per engine with a live preview through the engine's `build`.
- A leaderboard section.

### S7. Integration (Fable)
Merge order: S1, S2, S5, S4, S3, S6. Then:
- full analyzer;
- the contract tests;
- the risky backend tests on PostgreSQL: rrule expansion with DST / excluded days / exceptions, reminder idempotency, SRS scheduling and quiet hours, package capacity + waitlist promotion, approval permissions, game config validation;
- migrations on a copy of the production dump;
- the real web app on the local stack (playwright), checking ar/en at phone width;
- one Fable review, then the final report.

## Critical files
- **Front:** `lib/features/**/live/room.dart`, `live_config.dart`, `live_media_plan.dart`, `live_recording_layout.dart`, `lib/features/calendar/calendar_meeting.dart`, `schedule_page.dart`, `lib/features/games/**`, `lib/features/quran/**`, `lib/features/nahw/nahw_tab.dart`, `lib/features/admin/modules/`.
- **Back:** `data/models.py` (sessions), `data/calendar_models.py`, `features/home/calendar_service.py`, `features/platform/scheduler_service.py`, `features/games/games_service.py`, `features/quran/`, `features/profiles/api/teacher_documents_router.py`, `features/platform/feature_catalog.py`, `module_settings.py`.

## Risks
- `room.dart` is huge and touched only by S1.
- The teacher table generalization has to keep old apps working (read view and old endpoints kept).
- Notification volume from self-learning (daily limit + quiet hours enforced on the server).
- Lazily expanded series and the "join creates a row" step must not double-create (unique series_id + occurrence_utc).
- Package payment must not charge for a waitlisted seat (charge on promotion; promotion offer valid for 24 h).

## Verification
- `flutter analyze --no-fatal-infos --fatal-warnings`.
- `flutter test` on the touched folders plus `test/contract/`.
- Backend pytest for the new services on SQLite and PostgreSQL (the nb-pg container).
- Alembic upgrade on a copy of the production dump.
- A manual walk in the web app on the local stack: create a recurring meeting skipping Fri/Sat and cancel one date, get the 15-minute reminder, approve a teacher, publish a package, fill it with the waitlist on, play a new game, and get a self-learning lesson then its review.
- A live room on two devices for A1–A3.

## Then
Push to production when the owner says so. After that, sync to Alfaheem (elfaheem-front/back sync) with Alfaheem's own seed and branding untouched.
