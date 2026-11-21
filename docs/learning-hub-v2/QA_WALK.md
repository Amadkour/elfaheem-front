# Learning Hub v2: QA walk in the real web app (2026-11-21)

## Setup
- Back: a snapshot of `_wt/lh2-back` at `a5487f99` plus the uncommitted migration and calendar edits found in the worktree at the time. The live worktree was being edited, and uvicorn `--reload` kept restarting, so the snapshot was mounted instead.
  - Compose project `lh2qa`, gateway `:43080`, Postgres `:43432`.
  - Demo seed and `load_learn_seed.py` loaded; all migrations ran to head.
- Front: `_wt/lh2-front` at `a99cfd93`, `flutter build web --profile --base-href /`, served on `:43090`, driven with playwright-core (Chromium 1148).
- Accounts:
  - `superadmin@example.test`;
  - `market.teacher@example.test` (Mona), who onboards and publishes;
  - `center.trainer.web@example.test`, whose profile was submitted through the API so there was a second card to reject;
  - students `market.student@example.test` (ar) and `center.trainee2@example.test` (en). `center.trainee1` and `uni.cs.student1` took the seat and the first waitlist place through the API.
- Self-learning test window: the walk ran at 23:30 Cairo, inside the quiet hours. To get a delivery, the self-learning module was switched on through the UI, and its active and quiet hours, interval (15 min) and daily limit were then widened through the API.
- No server errors: the api log has no traceback and no 5xx. The only non-2xx responses are the expected 404 `no_profile` on the first open of the teacher hub, and the 401s caused by my own API logins (below).
- Screenshots: `screenshots/lh2/` (git-ignored); the file names are cited per finding.

Harness notes (not product bugs):
- Logging a user in through the API from a script signs that user's browser session out and then shows "device not allowed". Single device, as designed.
- Flutter web semantics keep their old positions after a wheel scroll, so taps used DOM semantics clicks or mouse clicks with pointer events disabled on the semantics layer.

## Counts
- must: 2
- should: 27
- nice: 21

## must

### M1. Word puzzle: the letter slots and tiles stack vertically at full width, and the solved word is not joined
- Role and flow: student, playing a `word_puzzle` game; also the super admin's live preview in the games editor.
- Language and size: ar, 390×844 (the same widgets are used at every size).
- Steps: Learn → Games → filter "كوّن الكلمة" → "كلمات مبعثرة QA".
- Expected: one row of small square slots and one row of letter tiles, as in a word game. A solved word reads as one connected Arabic word ("فاعل").
- Saw:
  - each slot and each letter tile is a full-width bar, stacked vertically, so a 4-letter word takes the whole screen;
  - the solved word shows as four isolated letters, one per row (ف / ا / ع / ل).
- The game still works end to end: right, wrong, try again and the finish screen.
- Screenshots: `130-st-words-play-ar-390.png`, `131-st-words-solved1-ar-390.png`, `132-st-words-wrong-ar-390.png`, `28-sa-game-words-preview-tiles-ar-390.png`.
- File: `lib/features/games/engines/word_puzzle_engine.dart`. `WordPuzzleSlot` and `WordPuzzleTile` take an unbounded width inside the parent `Column(crossAxisAlignment: stretch)`. Give them a fixed square size from the tokens, and render the solved word as one `Text`.

### M2. A student cannot see a package's days and times before joining
- Role and flow: student, teacher profile → package page.
- Language and size: ar 390, en 1400.
- Steps: Teachers → الأستاذة منى → "تجويد يومي QA".
- Expected: the schedule sentence that the teacher saw in the wizard, "كل يوم ما عدا الجمعة والسبت، من 10:00 ص إلى 11:00 ص". The profile itself says "اختر باقة لترى مواعيدها وتنضم" ("pick a package to see its times").
- Saw: only "8 جلسات × 60 دقيقة", "تبدأ 28 نوفمبر 2026", the delivery mode and the seats. No weekdays and no time of day appear anywhere on the package page, the profile card or My teachers.
- Screenshots: `96-st-package-full-ar-390.png`, `97-st-waitlist-confirm-ar-390.png`, `182-st2-teacher-profile-en-1400.png`.
- File: `lib/features/teachers/teacher_discovery.dart` (`PackagePage`, the package card). Use `describeRule` from `lib/features/calendar/recurrence/recurrence_rule.dart` on `package.schedule`.

## should

### S1. The wizard's summary says "until further notice", but the package has 8 sessions
- Role and flow: teacher, package wizard step 2 (schedule).
- Language and size: ar 390; en 1400 on the edit screen.
- Steps: New package, 8 sessions, Repeat → Every day, skip Fri and Sat, 10:00–11:00.
- Expected: the sentence and the "Ends" field say it ends after 8 sessions. The server's rule has `count: 8`.
- Saw:
  - the "Ends" field shows "حتى إشعار آخر" and the sentence ends with "حتى إشعار آخر";
  - the same package opened in Edit shows "Ends: After a number of times".
- Screenshots: `74-t-pkg-daily-ar-390.png`, `76-t-pkg-step2-summary-ar-390.png`, `192-t2-pkg-edit2-en-1400.png`.
- File: `lib/features/teachers/package_wizard.dart` (pass `sessions_count` into the `RecurrencePicker` as the count) and `recurrence/recurrence_rule.dart` (`describeRule`).

### S2. The package's default time window ignores the session length
- Role and flow: teacher, package wizard step 2.
- Language and size: ar 390.
- Steps: keep "مدة الجلسة 60", choose "كل يوم".
- Expected: the window defaults to 60 minutes, and changing the start time moves the end with it.
- Saw:
  - the window defaults to 5:00–5:30 PM (30 minutes) while the session is 60 minutes;
  - changing "From" to 10:00 kept a 30-minute end (10:30), so the minutes have to be fixed by hand.
- Screenshots: `74-t-pkg-daily-ar-390.png`.
- File: `package_wizard.dart`, the defaults handed to the `RecurrencePicker`.

### S3. The label "التكرار / Repeat" appears twice
- Role and flow: teacher, package wizard step 2.
- Language and size: ar 390, en 1400.
- Saw: "التكرار" twice above the repeat field ("Repeat Repeat" in English).
- Screenshots: `72-t-pkg-step2-ar-390.png`, `192-t2-pkg-edit2-en-1400.png`.
- File: `package_wizard.dart`, which labels the slot while the `RecurrencePicker` labels itself too.

### S4. The live summary and the My packages card have no schedule
- Role and flow: teacher, package wizard summary card; My packages.
- Language and size: ar 390, en 1400.
- Expected: the summary shows the schedule sentence, as the plan asks ("a live summary").
- Saw: subject, level, delivery, sessions × minutes, start date, seats and price, but not the days or times. The My packages card shows only "القرآن · أونلاين · 8 جلسات".
- Screenshots: `76-t-pkg-step2-summary-ar-390.png`, `80-t-pkg-published-ar-390.png`, `190-t2-hub-en-1400.png`.
- File: `package_wizard.dart` (the summary card and `MyPackagesSection`).

### S5. A locked package still looks editable
- Role and flow: teacher, Edit on a package with an enrolled student.
- Language and size: en 1400.
- Expected: the locked fields are disabled, matching the banner.
- Saw: the banner says "the sessions, the schedule and the start date no longer change". Only the start date is greyed out. The sessions stepper, the Repeat dropdown and the weekday chips all look active, and an edit would end in 400 `package_locked`.
- Screenshot: `192-t2-pkg-edit2-en-1400.png`.
- File: `package_wizard.dart`.

### S6. The hub tells a pending teacher to submit the profile
- Role and flow: teacher, hub after submitting.
- Language and size: ar 390.
- Expected: something like "your packages open once your profile is approved".
- Saw: "تُفتح الباقات بعد اعتماد ملفك من المنصة: أكمل ملفك وأرسله للمراجعة أولاً" ("complete your profile and send it for review first") while the profile is already under review.
- Screenshot: `58-t-submitted-ar-390.png`.
- File: `lib/features/teachers/teacher_onboarding.dart` (`TeacherHubPage`, the locked-packages note).

### S7. Wrong Arabic plurals
- Teachers list header: "2 معلم" should be "معلمان" (`92-st-teachers-ar-390.png`, `teacher_discovery.dart`).
- Review queue: "2 مستندات" should be "مستندان" (`60-sa-review-queue-ar-390.png`, `teacher_review_admin.dart`).
- Use `countText`.

### S8. A package with no schedule shows a fake next opening at 2:00 AM
- Role and flow: student, teacher discovery.
- Language and size: ar 390, en 1400.
- Saw: الشيخ محمود's seeded package has no schedule and no series, but the card says "أقرب موعد: 28 نوفمبر 2026 · 2:00 ص" ("Next opening: 28 Nov 2026 · 2:00 AM"). That is the start date at midnight UTC shown in Cairo time.
- Expected: no time, or just the date, when the package has no schedule.
- Screenshots: `92-st-teachers-ar-390.png`, `181-st2-teachers-en-1400.png`.
- File: back `features/teacher_hub` `next_free`, or the front formatting in `teacher_discovery.dart`.

### S9. "Starts 28 Nov" is a skipped day
- Role and flow: student, package page; teacher, wizard summary.
- Language and size: ar 390, en 1400.
- Saw: "تبدأ 28 نوفمبر" (a Saturday, which the rule skips). The first real session is Sun 29 Nov, which the discovery card shows correctly.
- Expected: show the first real occurrence.
- Screenshots: `96-st-package-full-ar-390.png`, `182-st2-teacher-profile-en-1400.png`.
- File: `teacher_discovery.dart`, `package_wizard.dart` (the summary); the back could also return `first_session`.

### S10. A package with an open waiting list says "No seats left"
- Role and flow: student, teacher profile → package card.
- Language and size: ar 390, en 1400.
- Saw: a red "لا مقاعد متبقية" / "No seats left" chip on a package whose overbook is `waitlist`. The teacher is also listed as "Available now".
- Expected: "قائمة انتظار مفتوحة" / "Waiting list open".
- Screenshots: `95-st-teacher-profile-ar-390.png`, `182-st2-teacher-profile-en-1400.png`.
- File: `teacher_discovery.dart`.

### S11. A free package's waiting-list text talks about paying
- Role and flow: student, joining the waitlist of a free package.
- Language and size: ar 390.
- Saw: the toast "…لن تدفع إلا إذا عُرض عليك مقعد" and the banner "…ولن تدفع قبل ذلك", on a free package.
- Expected: no payment wording when `final_price == 0`.
- Screenshot: `97-st-waitlist-confirm-ar-390.png`.
- File: `teacher_discovery.dart`.

### S12. The self-learning settings say "in the student's time zone"
- Role and flow: super admin, Module switches → Daily self-learning → Active hours start.
- Language and size: ar 390, en 1400.
- Saw: "بتوقيت الطالب." / "In the student's time zone." Per C8 there is no per-user zone: the server uses the org zone, else the platform zone.
- Screenshots: `06-sa-modules-sl3-ar-390.png`, `46-sa-modules-sl4-en-1400.png`.
- File: `lib/features/admin/modules/admin_modules_page.dart:82`.

### S13. Arabic user text is laid out left to right in the English UI
- Role and flow: student discovery and teacher profile, admin self-learning list, games editor.
- Language and size: en 1400.
- Saw:
  - "الشيخ محمود (تجريبي)" renders as "(تجريبي) الشيخ محمود";
  - bios and questions are left-aligned with the full stop or "؟" at the wrong end ("؟كم عدد أركان الإسلام");
  - Arabic qualifications are left-aligned.
- Expected: user text picks its own direction (`TextDirection` from the content, or `Directionality` / `textDirection` set per string). The daily learning page already gets this right (`241-st3-daily2-en-390.png`).
- Screenshots: `181-st2-teachers-en-1400.png`, `182-st2-teacher-profile-en-1400.png`, `220-sa-sl-content-en-1400.png`.
- Files: `teacher_discovery.dart`, `teachers_parts.dart`, `self_learning/admin/sl_admin_page.dart`, `games/admin/games_admin_page.dart`.

### S14. An Arabic comma in English text
- Role and flow: super admin, teacher review detail.
- Language and size: en 1400.
- Saw: the languages line reads "Arabic، English".
- Screenshot: `66-sa-review-detail-en-1400.png`.
- File: `teacher_review_admin.dart` or `teachers_parts.dart` (the languages join).

### S15. Desktop: forms span the whole content width and status chips float mid-card
- Role and flow: super admin game editor and teacher review detail; teacher My packages.
- Language and size: en 1400.
- Saw:
  - the game editor's fields are about 1070 px wide;
  - the review detail's "Under review" chip sits in the middle of the hero card;
  - the "Published" chip floats mid-card on My packages.
- Expected: a width role (`AppWidth.form` / `content`), and the status chip at the trailing edge.
- Screenshots: `48-sa-game-edit-memory-en-1400.png`, `66-sa-review-detail-en-1400.png`, `190-t2-hub-en-1400.png`.
- Files: `games_admin_page.dart`, `teacher_review_admin.dart`, `package_wizard.dart` (`MyPackagesSection`).

### S16. The self-learning item dialog hides its actions on desktop
- Role and flow: super admin, Self-learning content → Add.
- Language and size: en 1400×900.
- Saw: the dialog's Cancel / Save row is cut off at the bottom edge ("Write the title" and half-visible buttons). You have to scroll inside the dialog to save.
- Expected: a pinned action row.
- Screenshot: `221-sa-sl-add-en-1400.png`.
- File: `self_learning/admin/sl_admin_page.dart`.

### S17. A course's repeating meeting does not appear in its Sessions tab
- Role and flow: teacher, course page → Sessions → "اجتماع متكرر" → send invites.
- Language and size: ar 390.
- What works:
  - 201 `POST /me/calendar/series` with `course_id = 11`;
  - the toast "أُضيف الاجتماع المتكرر ودُعي طلاب المقرر";
  - the enrolled student sees it in their calendar.
- Saw: the Sessions tab still shows only the empty state "لا توجد دروس بعد", with no series row and no upcoming occurrences.
- Screenshots: `173-t-course-repeat-saved-ar-390.png`, `174-t-course-sessions-after-ar-390.png`, `185-st-calendar-ar-390.png`.
- File: `lib/features/courses/.../course_sessions.dart` (the sessions timeline should list the course's series).

### S18. The course repeating-meeting form defaults to 12:00 AM with no title
- Role and flow: teacher, course Sessions → اجتماع متكرر. The standalone new meeting does the same.
- Language and size: ar 390.
- Saw: From 12:00 AM to 12:30 AM tomorrow, and an empty title.
- Expected: the next sensible slot (or the course's usual time) and the course name as the title.
- Screenshots: `172-t-course-repeat-form-ar-390.png`, `151-t-meeting-new-ar-390.png`.
- File: `lib/features/calendar/calendar_meeting.dart`.

### S19. Old and new teacher flows sit side by side and disagree
- Role and flow: student Quran tab vs Teachers tab; teacher profile; super admin Module switches.
- Language and size: en 390, ar/en 1400.
- Saw:
  - The Quran tab lists "Mona Independent Teacher" (the account name), "No programs open now". The Teachers tab lists the same teacher as "الأستاذة منى", with a published package.
  - The teacher's account has two entries, "My Quran teaching" (the old card) and "My teacher profile and packages".
  - The super admin has "Verify and review Quran teachers" in the Quran module and "Teacher review" in the hub.
- Expected: one teacher identity. At least, the Quran tab should use the card name and link to the packages.
- Screenshots: `202-st3-quran-en-390.png`, `43-sa-modules-sl-en-1400.png`. The teacher's two entries are visible under Profile → تدريسي; there is no screenshot of them.
- Files: `lib/features/quran/quran_tab*`, `profile_screen.dart:248-257`, `admin_modules_page.dart`.

### S20. The self-learning page keeps showing a lesson already marked "فهمت"
- Role and flow: student, My daily learning.
- Language and size: ar 390.
- Steps: tap "فهمت" on سورة الفاتحة (200 `/lessons/1/seen`), then come back after the next delivery.
- Saw: the lesson is back under "دروس اليوم" with an active "فهمت" button.
- Expected: a done state, or the lesson leaves today's list.
- Screenshots: `230-st-daily-review-ar-390.png`, `237-st-daily-after2-ar-390.png`.
- File: `self_learning_page.dart` / `sl_store.dart`, or the back's `today.lessons`, which should mark `seen`.

### S21. The per-subject progress bar reads as complete after one lesson
- Role and flow: student, My daily learning → تقدّمي.
- Language and size: ar 390.
- Saw: after 1 of 2 Quran lessons, the Quran bar is 100% full. After one wrong review it drops to half. The bar's meaning (learned / (learned + due)) is not explained, and the label "1 · للمراجعة 1" doesn't say what the first number is.
- Screenshots: `142-st-daily-seen-ar-390.png`, `236-st-daily-after-ar-390.png`.
- File: `self_learning/sl_widgets.dart`.

### S22. The game type has three different names
- Role and flow: super admin game editor and lists; student games filter.
- Language and size: ar 390.
- Saw: the type menu says "بطاقات الذاكرة / املأ الفراغ / ترتيب الحروف"; the admin list and student chips say "ذاكرة / أكمل الفراغ / كوّن الكلمة". English: "Memory cards / Memory", "Fill the blank / Word puzzle".
- Screenshots: `16-sa-game-type-menu-ar-390.png`, `30-sa-games-list-after-ar-390.png`, `110-st-games-ar-390.png`.
- Files: `games/admin/game_config_draft.dart` vs `games/games_models.dart` (`kGameEngines` names).

### S23. The teacher filter button is off-screen on a phone in RTL
- Role and flow: student, Teachers tab.
- Language and size: ar 390.
- Saw: the "تصفية" button is the last item of the subject chip row, at x = −74: off-screen and only reachable by scrolling the chips sideways.
- Expected: the filter button outside the scrolling chips, next to search.
- Screenshot: `92-st-teachers-ar-390.png`.
- File: `teacher_discovery.dart`.

### S24. Cancelling an occurrence takes one tap, with no confirmation or undo
- Role and flow: teacher, calendar occurrence → إلغاء → هذا الاجتماع فقط.
- Language and size: ar 390.
- Saw: picking "this meeting only" cancels at once (DELETE 200), and attendees are notified. There is no confirm step and no undo toast.
- Screenshots: `157-t-cancel-choice-ar-390.png`, `158-t-cancelled-struck-ar-390.png`.
- File: `calendar_meeting.dart`.

### S25. Game editor validation is far from the field, and the preview hides the mistake
- Role and flow: super admin, new fill-in-the-blank game without `___`.
- Language and size: ar 390.
- Saw:
  - Publish just goes disabled;
  - the reason ("الجملة 1: ضع ___ مرة واحدة") appears only in a banner at the very bottom, and the sentence field is not marked;
  - the live preview draws a blank at the end of a sentence that has none, which hides the mistake.
- Screenshots: `23-sa-game-fill-noblank-ar-390.png`, `24-sa-game-fill-banner-ar-390.png`.
- Files: `games_admin_page.dart` (mark the row's field), `engines/fill_blank_engine.dart` (no appended blank).

### S26. The teacher price filter is cramped
- Role and flow: student, Teachers → تصفية.
- Language and size: ar 390.
- Saw: "أقل سعر / أعلى سعر" are two steppers side by side with about 56 px number fields. You can't type a real price.
- Screenshot: `93-st-teachers-filter-ar-390.png`.
- File: `teacher_discovery.dart` (stack them, or use two plain number fields).

### S27. Navigation: the teacher review, games and self-learning pages sit under "Finance & requests"
- Role and flow: super admin, desktop sidebar.
- Language and size: en 1400.
- Saw: Module switches, Teacher review, Educational games and Self-learning content are all grouped under "Finance & requests". "Teachers" and "App configuration" have none of them.
- Screenshot: `42-sa-finance-hub-en-1400.png`.
- File: `lib/features/admin/admin_services_hub.dart` (section grouping).

## nice

| # | Role / flow | Lang, size | What | Screenshot | File |
|---|---|---|---|---|---|
| N1 | teacher onboarding, admin review | ar 390, en 1400 | small files show "0 KB"; use "< 1 KB" | `55-t-wizard-3-pdf-ar-390.png`, `66-…` | `teachers_parts.dart` |
| N2 | admin review, student profile | ar 390 | a female teacher gets masculine text: "عن المعلم", "يظهر للطلاب ويفتح باقاته" | `61-…`, `63-…`, `95-…` | `teacher_review_admin.dart`, `teacher_discovery.dart` |
| N3 | discovery, profile, My teachers, hub | ar / en | avatar initial of "الأستاذة / الشيخ" is "ا", which reads as "I"; the profile hero's initial has no circle behind it | `92-…`, `95-…`, `101-…`, `182-…` | `teachers_parts.dart` (skip "ال" and titles; reuse the avatar widget) |
| N4 | Nahw tab daily card, daily page | ar 390 | "متتالية: 0 يوم"; use `countText` ("0 أيام" or "لا أيام") | `102-st-nahw-ar-390.png` | `self_learning/sl_widgets.dart` |
| N5 | onboarding review step | ar 390 | the summary leaves out the session types and delivery chosen in step 2 | `57-t-wizard-4-ar-390.png` | `teacher_onboarding.dart` |
| N6 | onboarding step 1 | ar 390 | "الاسم كما يراه الطلاب" is not prefilled with the account name | `52-t-wizard-1-ar-390.png` | `teacher_onboarding.dart` |
| N7 | student games tab | ar 390 | three filter controls at once: Filters button, two dropdowns, a chip row | `110-st-games-ar-390.png` | `games/games_tab.dart` |
| N8 | leaderboard opt-out | ar 390 | hidden state keeps the open-eye icon | `117-st-leaderboard-optout-ar-390.png` | `games/game_leaderboard.dart` |
| N9 | weekly summary | ar 390 | "كل أسبوع يوم الأحد والثلاثاء" should be "يومَي الأحد والثلاثاء" | `154-t-meeting-summary-ar-390.png` | `recurrence/recurrence_rule.dart` |
| N10 | joining the seeded free package | ar 390 | "أنت مشترك. تجد الجلسات في جدولك" although that package has no schedule, so nothing appears in the calendar | `100-st-package-joined-ar-390.png` | `teacher_discovery.dart` (say it only when `series_id` is set) |
| N11 | SL admin add item | ar 390 | "منشور للطلاب" defaults off, so a quick Save makes a draft nobody gets (my test question was saved unpublished); a new item also gets `sort = 0` rather than going last | `11-…`, `13-…` | `sl_admin_page.dart:450` |
| N12 | page headers at 390 | ar 390 | long titles wrap into two lines with a wide empty gap ("مفاتيح / الوحدات", "محتوى التعلّم / الذاتي", "الألعاب / التعليمية") | `07-…`, `09-…`, `14-…` | page header widget |
| N13 | games admin list | ar 390 | the switch and menu squeeze each row's meta onto three lines | `14-sa-games-ar-390.png` | `games_admin_page.dart` |
| N14 | My packages | en 1400 | "1 of 1 seats" should be "1 of 1 seat" | `190-t2-hub-en-1400.png` | `package_wizard.dart` |
| N15 | review list | ar 390 | the date wraps mid-value ("21 / نوفمبر 2026"); the last tab "مبالغ للردّ" is cut at the edge | `60-sa-review-queue-ar-390.png` | `teacher_review_admin.dart` |
| N16 | daily reviews | ar 390 | the subtitle changes from "سؤالا مراجعة" to "سؤال مراجعة واحد" while the counter says "مراجعة 2 من 2" | `230-…`, `233-…` | `self_learning_page.dart` |
| N17 | word puzzle hint | – | `'كلمة من ${n} حروف'` / `'A word of $n letters'` is not `countText` (wrong for 2 and 11+) | – | `word_puzzle_engine.dart:161` |
| N18 | onboarding documents | ar 390 | after the first upload, "اختر ملفاً" is merged into the paragraph's semantics node (screen readers can't press it on its own); the same happens to "النتيجة" under a wrong word-puzzle answer | `56-…`, `132-…` | `teacher_onboarding.dart`, `word_puzzle_engine.dart` |
| N19 | calendar "next" card | ar 390 | a private series ("موعد خاص") shows the group icon | `155-t-meeting-saved-ar-390.png` | `schedule_page.dart` |
| N20 | display serif digits | en 1400 | game header "o of 2" and "Pair 1": the display face's zero reads as "o" | `49-…` | `app_tokens` / the display type role for numerals |
| N21 | approval toast and dialog | ar 390 | the approve dialog copy is fine, but the queue loses the approved card with no "view approved" hint; there is a tab for it, so this is minor | `64-sa-approved-ar-390.png` | `teacher_review_admin.dart` |

## What was walked and passed
- **Super admin:**
  - self-learning module on and saved (PUT 200);
  - content page lists and filters, and a review question was created;
  - games editor: memory, fill-in-the-blank and word puzzle each created, previewed (right and wrong) and published;
  - drag reorder (POST `/admin/games/reorder` 200);
  - review queue: document open through a signed link, approve with confirm, reject (the empty reason is blocked with a clear message; with a reason, 200);
  - the teacher got the approval notification badge.
- **Teacher:**
  - 4-step onboarding with a PDF and a PNG (both 201, sniffed and listed), then submit (200);
  - after approval, the wizard with "every day except Fri and Sat, 10:00–11:00", published with 1 seat and a waitlist. The series was created with `skip_weekdays [4, 5]`, `count 8` and `tz Africa/Cairo`, and appears in the teacher's calendar from Sun 29 Nov with the "متكرر" badge.
  - My packages: Edit / Pause / Roster / Duplicate / Close are shown.
- **Student:**
  - discovery filters (gender + available → GET with `gender=female&available=true`), search box, teacher profile;
  - joined the free package (active), joined the full package's waitlist (position 2);
  - My teachers lists the active package;
  - memory, fill-in-the-blank and word puzzle all played to the finish screen with badges and leaderboard ("أنت · Mark S.");
  - leaderboard opt-out (PUT 200, toast), week / all tabs;
  - daily learning: lesson delivered by the tick → "فهمت" (seen 200) → two reviews, one wrong (explanation, correct answer marked) and one right, then streak 1.
- **Calendar:**
  - standalone weekly series (Sun + Tue, 10:00–11:30) with the summary sentence;
  - cancel one date (DELETE 200; struck through with "أُلغيت");
  - "this and following" on 29 Nov to 9:00. The series split (old one ended, new one active), and dates before the split kept 10:00;
  - course series created and visible to the enrolled student.

## Not walked, or only partly
- Not every flow was walked in all four language × size combinations. Covered:
  - super admin: ar 390 for everything; en 1400 for modules, games, self-learning content and review/reject;
  - teacher: ar 390 for everything; en 1400 for the hub and package edit only. The onboarding wizard and the calendar flows were not re-run in English or on desktop.
  - student: ar 390 for everything; en 1400 for discovery and profile; en 390 for the Quran tab, games and daily learning. Package join and waitlist were not re-run in English.
- **Paid package checkout:** not tried; no card gateway is configured on the dev stack.
- **Promotion from the waitlist on leave, the 24 h offer, and refund-due:** not walked in the UI.
- **The 15-minute meeting reminder:** not checked; the walk ended before any occurrence was near.
- **Self-learning delivery inside the default active and quiet hours:** not observed. The walk ran in the quiet hours, so the window was widened through the API.
