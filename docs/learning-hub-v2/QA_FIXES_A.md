# Learning Hub v2: QA fixes, round A (2026-11-22)

The findings of `QA_WALK.md` for teachers, packages, the recurrence picker, the calendar and course sessions.
Decisions: front D-1647 – D-1665, back D-1699, D-1702, D-1703.

Commits:
- front: `e8d611bf` (S17), `4fd622ff` (S19), `67b50e63` (everything else), `cb48b642` (fixes from the real-app walk);
- back: `6cf3bd8d` (S17), `45e3d081` (S19), `5febaadc` (S8).

The real-app check is in the last section. Screenshots are in `screenshots/lh2/fix/`: `before-*` are copies of the walk's shots, `after-*` are new.

## must

| # | Status | What changed |
|---|---|---|
| M2 | fixed | The package page, the package card on the teacher profile, My teachers and My packages show the days and times. The sentence comes from `packageScheduleText`, which calls `describeRule` with times formatted by `AppTime`, e.g. "Every day except Fri and Sat, 10:00 AM to 11:00 AM, for 8 sessions". The times are in the rule's zone. When that zone is not the reader's, the sentence names it ("Egypt (Cairo) time"). A package with no schedule says the teacher agrees the times (D-1648). |

## should

| # | Status | What changed |
|---|---|---|
| S1 | fixed | `RecurrencePicker(fixedCount:)` keeps the rule's `count` equal to the package's sessions. "Ends" becomes the read-only line "After 8 sessions", and `describeRule(sessions: true)` says "for 8 sessions". `packageScheduleSynced` follows a change to the sessions field (D-1647). |
| S2 | fixed | A new rule's window is one session long. A change to the minutes field moves the end time (`packageScheduleSynced`), and the From field keeps the length. |
| S3 | fixed | The wizard no longer labels the slot. The picker takes its own `label`. |
| S4 | fixed | The live summary and the My packages card show the schedule sentence. The summary also shows the first real day. |
| S5 | fixed | A locked package draws the minutes field, the sessions field and the whole Repeat section disabled (`RecurrencePicker(enabled: false)`), to match the lock banner. The rule is never re-synced while locked. |
| S6 | fixed | `teacherPackagesLockedText` words the note by status. Under review: "your packages open as soon as it is approved". Rejected: "change it and send it again" (D-1659). |
| S7 | fixed | Review queue: "مستندان" via `countText`. The teachers header was already fixed in D-1646. |
| S8 | fixed | The back adds `next_free_kind` (`day` / `session`, D-1703). A `day` opening shows "Starts: 28 Nov 2026" with no time (D-1656). |
| S9 | fixed | `RecurrenceRule.matches` / `firstDate` port the server's occurrence test, so "Starts Sun 29 Nov 2026" is the first real session (D-1649). This applies to the card, the package page and the wizard summary. |
| S10 | fixed | A full package with a waiting list shows the "Waiting list open" chip in the warning tone (D-1653). "Available now" stays, because the server counts an open waiting list as available (C1). |
| S11 | fixed | The waiting-list toast and banner of a free package don't mention payment (D-1657). |
| S13 | fixed in my files | `UserText` gives typed text the direction of its first strong letter. It covers teacher names, bios, qualifications, review comments, package titles, goals, descriptions, the review queue and the review detail (D-1651). The self-learning and games pages belong to the other round. |
| S14 | fixed | `teachersJoin` joins with ", " in English and "، " in Arabic, in discovery, the review detail and the onboarding summary. |
| S15 | fixed in my files | `TitleWithStatus` puts the status chip at the trailing edge of the title line, on My packages, the review queue card and the review detail. The pages already use width roles (`AppWidth.content` / `reading` / `form`). The game editor belongs to the other round. |
| S17 | fixed | New `GET /me/calendar/series?course_id=` (back D-1699). The course Sessions tab, for the teacher and the student, shows a "Repeating meetings" block above the lessons. Each card has its rule sentence and its next 3 dates, and a cancelled date is struck through. A date opens the calendar's date sheet. The block also shows before the first lesson (D-1660). |
| S18 | fixed | `calNextSensibleSlot` replaces the next full hour. It keeps the next full hour between 08:00 and 21:00; otherwise it picks 10:00 that morning or the next day. The schedule page's New meeting and the course's Repeating meeting use it. A course meeting starts with the course name as its title (D-1661). |
| S19 | fixed | One identity and one way in (D-1664, D-1665, back D-1702):<br>• The Quran list uses the card's name and `packages_count`, and the Quran tab card and teacher page link to the packages.<br>• Profile has one teacher entry.<br>• `TeacherHubPage` opens the Quran record sheet.<br>• The old Quran hub leads to the teacher profile and folds its Quran-only fields away.<br>• The Quran admin page links to Teacher review.<br>The old Quran routes are unchanged. The admin hub's grouping (S27) is the other round's. |
| S23 | fixed | The Filters button sits beside the search field, outside the scrolling chips (D-1654). |
| S24 | fixed | After the scope, `seriesCancel` asks `appConfirm`, naming the date and saying the invitees are told. This is a confirm, not an undo: the server has no "restore a date" call (D-1662). |
| S26 | fixed | The price fields are stacked, each full width, with step 50 (D-1655). |

## nice (my areas)

| # | Status | What changed / why not |
|---|---|---|
| N1 | fixed | `fileSizeLabel` shows "< 1 KB" (the shared helper, so the org pages get it too). |
| N2 | fixed | `teacherG` gives the feminine for a woman teacher: "عن المعلمة", "لم تكتب المعلمة نبذة", and the approve dialog. |
| N3 | fixed | `teacherInitialName` skips titles and "ال" ("الأستاذة منى" → "م"). The profile hero's avatar sits on a paper ring. |
| N5 | fixed | The onboarding review step lists the session types and delivery. |
| N6 | fixed | A new profile's display name starts with the account name. |
| N9 | fixed | Two weekdays read "يومَي الأحد والثلاثاء", three or more "أيام …". |
| N10 | fixed | "The sessions are in your schedule" shows only when the package has a series. Otherwise the text says the teacher agrees the times. |
| N14 | already fixed | `seatsTakenText` (D-1646). |
| N15 | partly | The submitted date no longer breaks inside itself (non-breaking spaces). Skipped: the cut last tab is the shared `AppTabs` scrolling behaviour, outside these files. |
| N18 | skipped | Not reproduced without a screen reader. The documents step's "Choose a file" is a separate `AppButton`; the merged node seen in the walk is the empty-state action, a kit widget (`AppEmpty`). |
| N19 | fixed | `calEventIcon`: a private meeting shows a person icon (D-1663). |
| N21 | skipped | Minor (the review queue's Approved tab exists). |

## Real-app check

- **Stack:** compose project `lh2fixa`, built from `lh2-back` (gateway `:47080`, Postgres `:47432`), with the demo seed and `load_learn_seed.py`.
- **App:** a profile web build served on `:47090`, driven by playwright-core.
- **Test data:**
  - Mona's card was approved in the database.
  - Her package "تجويد يومي QA" has the daily rule except Fri and Sat, 10:00–11:00, 8 sessions, 1 seat, a waiting list and starts Sat 28 Nov. `center.trainee1` took the seat.
  - Course 11 has a weekly series on Sun and Tue, 18:00–19:00.
- **Result:** no server errors (4xx / 5xx) in any walk.

| Flow | Seen | Screenshot |
|---|---|---|
| Student, Teachers (ar 390) | Filters sits beside the search; "معلمان"; the avatar letter is "م"; Mona shows "Next opening 29 Nov 10:00 AM", and the seeded teacher with no schedule shows "Starts: 28 Nov 2026" | `after-S23-S8-teachers-ar-390` |
| Filter sheet (ar 390) | price fields stacked at full width | `after-S26-filter-ar-390` |
| Teacher profile (ar 390) | the package card has the schedule sentence, "تبدأ الأحد 29 نوفمبر 2026" and "قائمة انتظار مفتوحة"; "عن المعلمة"; the avatar ring | `after-M2-S10-profile-ar-390` |
| Package page, join the waiting list (ar 390) | the schedule before joining; the free package's toast and banner don't mention payment | `after-M2-S9-package-ar-390`, `after-S11-waitlist-free-ar-390` |
| Student, Teachers and profile (en 1400) | Arabic names, bios and qualifications read right to left ("الشيخ محمود (تجريبي)"); "Arabic, English"; "for 8 sessions" | `after-S13-S8-teachers-en-1400`, `after-M2-S13-S14-profile-en-1400` |
| Teacher, Profile → hub (ar 390) | one teacher entry; the My packages card has the schedule and the chip at the edge; the Quran record sheet card | `after-S4-S15-hub-ar-390` |
| Locked edit (ar 390) | the Repeat section is disabled, and "Ends" reads "بعد 8 جلسات" | `after-S5-locked-edit-ar-390`, `after-S5-locked-edit2-ar-390` |
| New package, daily (ar 390) | one "التكرار" label; 5:00–6:00 PM for 60 minutes; "Ends after 8 sessions"; the summary has the schedule and "Starts Sun 29 Nov" | `after-S1-S2-S3-wizard-ar-390`, `after-S1-S2-wizard2-ar-390`, `after-S4-S9-summary-ar-390` |
| Course Sessions (ar 390) | the "Repeating meetings" block with the rule ("يومَي الأحد والثلاثاء") and 3 dates above the empty lessons | `after-S17-course-sessions-ar-390` |
| Course repeating meeting (ar 390) | title = course name; starts at a sensible hour | `after-S18-course-repeat-form-ar-390` |
| Cancel one date (ar 390) | the confirm names the date and that invitees are told; after confirming, the date is struck with "أُلغي" | `after-S24-cancel-confirm-ar-390`, `after-S24-cancelled-ar-390` |
| Super admin, Teacher review (en 1400) | "Under review" chip at the trailing edge in the queue and the detail; "Arabic, English" | `after-S15-review-queue-en-1400`, `after-S15-S14-review-detail-en-1400` |
| Student, Quran tab (en 1400) | the card's name "الأستاذة منى" and "1 package" | `after-S19-quran-tab-en-1400` |

Fixed after the walk (`cb48b642`), checked on a second build (`after2-*` shots):
- typed names keep the page's side next to their avatar instead of crossing to the far edge;
- the locked sessions and minutes fields fade like the Repeat section;
- the hub status card and the Quran cards no longer show "ا" as the avatar letter.

Not walked: the paid-package flow, which has no gateway on the dev stack, and a reader in a zone other than the teacher's (that case is covered by the `describeRule(withZone:)` unit test).
