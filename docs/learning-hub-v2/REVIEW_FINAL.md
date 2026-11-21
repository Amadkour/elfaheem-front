# Learning Hub v2: final review (Fable, 2026-11-21)

The review covered front a99cfd93 and back a5487f99, read-only. The backend items (B) are with the back fix round.
The front items (F) go into the front fix round together with `QA_WALK.md`.

## Must-fix
- **F1** `lib/features/teachers/teachers_models.dart:651`: the package roster parser reads flat `student_id` / `name`. The back sends `{id, student: {user_id, name, avatar_url}, …}` (`package_service.py:323`), so names show blank and the id shows 0. Read `j['student']` first, and fix the fixture in `test/ui/teachers_models_test.dart:164`, which has the flat shape.
- **B2** `0116_teacher_cards.py` copies `users.name` (255) into `teacher_cards.name` (120), and a long name aborts the migration. Truncate.
- **F3** `lib/features/calendar/calendar_meeting.dart:~455`: a course meeting with Repeat set to "none" posts to `/meetings` with `course_id`, which `MeetingIn` ignores, and an empty audience. The banner says the students are invited, but nobody is. Send `audience.course_ids: [courseId]` for a single meeting.

## Should-fix
- **F4** `package_wizard.dart:222`: changing the start date after setting the repeat leaves `schedule.start_date` on the old date, and the series uses the rule's date. Write the new date into the rule in `_pickDate`.
- **F5** `sl_models.dart:200` reads `per_subject.total`, but the back sends `lessons`. Use `m['total'] ?? m['lessons']`.
- **B6** `camera_fps_host` is always sent as 30; derive it on the server when it is unset.
- **F7** `live_settings_draft.dart:29,97,234` has no admin option for 1080p or the host fps. A server value of 1080p becomes 720p on the next save, and the bitrate table still says 1700 (it is now 1800).
- **B8** `meeting_detail` has no `series_id` / `occurrence_date`.
- **F8** The app must read `series_id` / `occurrence_date` in the meeting detail and ask "this one / this and following" there too, once B8 lands.
- **F9** `series_actions.dart:~97`: "This and following" computes the new clock in the `AppTime` zone, not the rule's `tz`.
- **F10** `lib/core/api_error_text.dart` has no texts for `teacher_only`, `students_only`, `not_pending`, `not_enrolled`, `card_unavailable`, `gateway_error`, `quran_gender_rule`, `bad_rule`, `occurrence_cancelled`, `no_occurrences`, `series_ended`.
- **B11** The 0117 downgrade drops paid package payments; it must refuse.
- **F12** Counts not through `countText`: `teacher_discovery.dart:282`, `package_wizard.dart:679`. Raw motion durations: `game_shell.dart:290,344`, `sl_motion.dart:31,64` (use the motion tokens).
- **B12** `app_features_guide.json` has no entries for the leaderboard or refunds-due.

## Found fine
- `RecurrenceRule` JSON ↔ `RuleIn`; weekday 0 = Monday.
- The `sl_review` outbox.
- The live room: recording, Record for guests, drawing permissions, burned-in, share presets.
- No pubspec change, no http / ws URLs, no hard-coded colors, no raw `Switch`, no static TextStyles, no un-synced loops; the 49 new keys have both languages; the 8 switches are in the catalog.
- Route permissions, document handling, no avatar on the leaderboard, logs carry ids only.
- Migrations are additive and the Quran copy is idempotent.
