# Learning Hub Phase 6: games, Quran, nahw, module switches, real web build QA (2026-11-21)

How it was run:
- Back `_wt/lh-back` (feature/learning-hub, f3555bc), compose project `lhdev` (gateway :41080, volumes kept), started with the
  same `.env` copy as Phase 5 (`MINIO_PUBLIC_URL` :41900, `APP_URL` :41080) as `DEV_ENV_FILE`.
  `python -m data.migrate` took the schema 0105 → **0107**; `scripts/dev/load_learn_seed.py` → "114 surahs / 6236 ayahs /
  30 juz, 45 nahw exercises, 6 games", 63 rows added.
- Front `_wt/lh-front` (9330b459), `flutter build web --profile --dart-define=API_BASE_URL=http://localhost:41080/api
  --base-href /app/` into `C:/Users/ahmed/AppData/Local/Temp/lhweb6/app`, served at `/app/` with an SPA fallback on :41500.
- Driver: playwright-core + headless Chrome, Arabic, 360×780 and 1366×900. Where a form is longer than the phone, the
  viewport was made taller for the clicks (see "Test notes") and the 360×780 screenshots were taken separately.
- Accounts (demo password): student `lh4.stu1` (34, EG prep g2), teacher `market.teacher` (29), teacher `lh.tch38899` (32),
  parent `lh.par85720` (33), super admin `superadmin`; `lh5.stu1` (36) and `market.student` (30) for API checks only.
- Local data set up by SQL (no UI exists for these, see 4.1):
  - `courses.program_kind='quran'` for 26 (market.teacher) and 24 (lh.tch38899);
  - `student_study_profiles.gender='m'` for 34 and 36;
  - `parent_student_links` 33 → 34;
  - enrolment 34 → course 26 (the card checkout cannot complete locally);
  - org member 36 → org 2 (for the org-layer check);
  - device bindings cleared before each browser sign-in. Passwords of 31/33/34/35/36 set to the demo password.

Screenshots: `C:/Users/ahmed/AppData/Local/Temp/lhshots/phase6/` (file names below).

## Summary

| Step | Result |
|---|---|
| 1. Student tabs at 360 px | **Fail (high, layout):** 10 tabs in the bottom bar, 38 px wide each, labels overlap or are cut |
| 2. Games: quiz, match, order; progress, badge, replay | **Pass.** Bugs: the quiz question is not exposed to screen readers; "all pairs done" is styled as an error; the order game's check/result sits under the nav |
| 3. Nahw: lesson, right/wrong feedback, persistence | **Pass.** Lesson pages don't survive a reload (dashboard) |
| 4. Quran | **Mostly pass. FAIL: the gender block shows a generic "payment failed" page, not the bilingual message** (high). The app cannot create a Quran program (expected gap). The teacher page body is missing from the semantics tree (high a11y) |
| 5. Module switches: country tab key, org over country, source labels | **Pass.** The country's tab switch needs a second app launch to take effect (cached theme) |
| 6. Parent: linked child games / Quran / nahw; unlinked 404 | **Pass** (UI + API). Page titles overflow the header at 360 |

No untranslated keys were seen. Console/network: apart from the expected 403s, the only errors were `/releases/releases.json` 404 (static server) and `/api/v1/models/downloads` 503 (model hub not running locally, unrelated).

## 1. Student tabs on a phone: FAIL (high)

- The student shell now has **10 tabs**: الرئيسية، كورساتي، المتجر، الألعاب، القرآن، النحو، جدولي، التحليلات، حسابي (+ home) (`01_home_360`, crop `01b_nav_360_crop`).
- Each tab is **38×50 px** (below the 48 px target). "الرئيسية" runs into "كورساتي", and "جدولي" and "التحليلات" are cut to "جدولي التحليـ…".
- The D-1340 decision ("nine student tabs on a phone") is still open, and with the store the count is 10. Options: move الألعاب / القرآن / النحو under one "تعلّم" hub tab, or let the phone bar show 5 tabs plus "المزيد".
- Likely files: `lib/features/home/student/dashboard/dashboard_screen.dart:90-190` (the item list) and the `AppShell` phone bar. `test/ui/a11y_guidelines_test.dart` should catch the target size once the student shell is pumped at 360.
- Each tab at 360: `02_tab_كورساتي` … `09_tab_حسابي`. No overflow stripes.
  - Games: the "صفك الدراسي" chip hides all 6 seed games for a prep student (they are primary-grade). The empty state offers "اعرض كل المستويات", which works (`04`, `10`).
  - Quran and Nahw look clean (`05`, `06`).

## 2. Games: pass, with bugs

- **Quiz** (تحدي جدول الضرب, 8 questions, all right). Instant "إجابة صحيحة!" (`12_quiz_feedback_360`), result 3 stars, "8 / 8 · 100%", "+5 نقطة", new badges أول لعبة and علامة كاملة (`13_quiz_result_360`).
  - DB: `game_plays` 1 has stars 3, `points_awarded` 5 and `new_badges ["first_play","perfect"]`; `user_badges` has both; points 1500 → 1505 (points rewards were turned on for the platform first).
- **Replay is not double-counted.** The same `client_id` was re-POSTed through the API: 200 with `duplicate: true` and the first play's result. There is still 1 row, `plays` stays 1, and the balance stays 1505. **Pass.**
- **Match** (طابق الحيوانات): a wrong pair (cat ↔ سمكة) is marked red at once (`16_match_wrong_360`); the 6 right pairs follow; result 2 stars, 5/6 (`19_match_score_360`).
  - **BUG (medium): when all pairs are done, the "اكتملت الأزواج" card uses the error style** (pink, "!" icon) because one mistake was made (`18_match_result_360`). It reads as a failure. Likely file: `lib/features/games/engines/match_engine.dart` (feedback tone), `learn_kit/learn_question.dart` (feedback card).
- **Order** (رتّب الكواكب): one wrong first pick (نبتون) shifts every item, so the check gives **0 / 8** (`25_order_checked_360`), 0 stars and no points.
  - A second play in the right order gives 8/8, 3 stars and +5; progress shows `plays 2`, best 8 (`28`, `29`).
  - **Medium (UX):**
    - a wrong pick gets no feedback until "تحقّق";
    - positional scoring makes one early slip score zero;
    - at 360 the "تحقّق" button and the result card are below the fold, under the bottom nav (`23_order_done_360`, `25`): the player has to scroll to find out that something happened.
  - Minor RTL: the numbers in the picked list read "1. نبتون" with the number at the left end (`23`).
  - Likely file: `lib/features/games/engines/order_engine.dart`.
- **Progress page** (تقدّمي وشاراتي, `30_games_progress_badges_360`): 4 plays, 8 stars, 2 perfect, 3 games, badges 2 of 5. This matches the DB (3+2+3 stars) and the balance (1515 = +5 ×3). **Pass.**
- **BUG (high, a11y): the quiz question, "السؤال 1 من 8" and the score are missing from the web semantics tree.** Only the header, the options ("أ, 27"…) and the nav are present, so a screen reader hears the options without the question.
  - Likely file: `lib/features/learn_kit/learn_question.dart:72` (the prompt `Semantics(header:)`) and `learn_progress.dart:29` (`excludeSemantics` with a label).
- Minor:
  - the floating assistant button overlaps the feedback card's "التالي" at the left edge (`12`);
  - the 404 from the games API (`LINK_NOT_FOUND`) has no `message_en`, while Quran and nahw send one (back `features/games/games_service.py`, `child_progress`).

## 3. Nahw: pass, with bugs

- Lesson أقسام الكلمة → ابدأ التمارين (5 exercises).
  - **Classify:** one wrong (كتاب → فعل). After تحقّق the wrong chip is red, the right answer is outlined, and the result reads "5 من 6 صحيحة" with the explanation (`38_nahw_classify_feedback_tall`).
  - **Choose:** "قلم" (wrong) → "ليست صحيحة" + explanation (`39_nahw_choose_wrong_tall`); the right answers → "إجابة صحيحة" (`40`, `42`).
  - Result: 2 stars, "8 / 10 · 80%" (`43_nahw_lesson_result_tall`).
  - DB: `nahw_attempts` holds score 8/10 and the answers; `nahw_progress` (34, lesson 1, 8/10, done).
- **Persistence:** after a reload the Nahw tab shows "أقسام الكلمة · أتممته · 80%" and the level "أتممت 1 من 3" (`44_nahw_after_reload_360`). **Pass.**
- "Instant feedback" here comes after تحقّق per exercise, not on tap. That is fine for multi-part exercises, but noted.
- **Medium: `/app/nahw/lessons/1`, `/app/games/…`, `/app/quran/teachers/29` and `/app/quran/progress` change the URL but do not survive a reload** (they land on the dashboard, `45`, `59`). This is the same gap Phase 5 fixed for the store with registry routes. Likely file: `lib/main.dart` `_router` / the route registry (`store.item` pattern).
- **A11y (medium):** in the classify exercise every row's buttons are announced as "اسم / فعل / حرف" without the word being classified (18 identical buttons). Likely file: `lib/features/nahw/nahw_exercise_view.dart` (put the item text in each chip's semantics label).
- Minor copy: the lesson result's button says "العب مرة أخرى" (play again), which is games wording (`43`).

## 4. Quran

### 4.1 Quran program: done by SQL; the app cannot
- Neither the course form (front: no `program_kind` anywhere in `lib/`) nor the course create/update API (`program_kind` is only a list filter in `features/courses/api/courses.py:198`) can make a Quran program.
- Courses 24 and 26 were set with `UPDATE courses SET program_kind='quran'`. **Gap (high for the feature):** a teacher has no way to publish a program for the "البرامج" list. Likely files: back course schemas, front course setup form.

### 4.2 Teacher profile with a gender: pass
- Teacher › حسابي › تعليم القرآن (`51_quran_teacher_hub_360`): I chose معلم, حفظ + تجويد, فردي, مصر, the ijazah and a bio, then pressed نشر البطاقة → "منشورة" (`54_quran_card_published_tall`). The API shows it published, `gender m`, and course 26 under it.
- The second teacher (32, `f`, حفظ + مراجعة, حلقة جماعية) was set through `PUT /me/quran/teacher-profile`.
  - Note: the API's goal value is `revision`, while the card shows it as مراجعة. My first try with `review` got a helpful 422 listing the allowed values.

### 4.3 Student filters teachers by gender: pass
- Quran tab: 2 teachers (`55_quran_tab_teachers_360`). Filter sheet (`56`) → معلمة → only the female teacher, chip "معلمة", "معلم واحد" (`57_quran_filtered_female_360`).
- Minor: the count says "معلم واحد" for a female result; use a neutral or gendered form (`countText`).

### 4.4 Booking goes to course checkout: pass
- Teacher page → احجز opens `/app/courses/26` (the course page), and انضم الآن opens إتمام الدفع with the plans and "ادفع 686.80 ج.م" (`60_quran_book_checkout_360`, `61_quran_join_checkout_360`).
- **BUG (high, a11y): the Quran teacher page body is missing from the semantics tree.** Only the header and the nav are present, so احجز cannot be reached by a screen reader. I had to tap it by coordinates. This happened twice, on fresh navigations.
  - Likely file: `lib/features/quran/quran_teacher_page.dart` (look for a `Semantics`/`ExcludeSemantics` or `IgnorePointer` wrapper around the body, or a custom scroll view without semantics).
- Minor: the teacher's name is in a large font and cut to "Mona Independent…" at 360 (`58`).

### 4.5 `gender_matching=same` and the mismatched booking: server pass, app FAIL
- Super admin › المالية والطلبات › مفاتيح الوحدات › المنصة › تحفيظ القرآن › جنس المعلم والطالب → "الجنس نفسه فقط (يُرفض الحجز غير ذلك)" → حفظ (`74`, `76_gender_same_saved`). The row is `quran|platform|''|{"gender_matching":"same"}`, labelled "مضبوط للمنصة" with "استخدم الافتراضي (بلا شرط)".
- The student's list keeps both teachers and marks the female one "غير متاح لك". Her page shows the notice "الحجز مع هذا المعلم غير متاح لك: البرنامج يشترط أن يكون المعلم من نفس جنس الطالب", and احجز is disabled (`62`, `63`). **Pass.**
- Server: `POST /courses/24/enroll` and `POST /payments/create-web-session` both answer 403 with:

  ```json
  {"code":"quran_gender_rule","message":"يُشترط أن يكون المعلم من نفس جنس الطالب","message_en":"The teacher must be of the student's gender","reason":"gender_differs"}
  ```

  **Pass.**
- **BUG (high): the course page itself does not block.** Opening `/app/courses/24` (by link, search or the course list) shows انضم الآن and the full checkout. Paying then gives the 403, and the app shows a generic **"فشلت عملية الدفع — فشل إنشاء جلسة الدفع. حاول مرة أخرى"** with "حاول مرة أخرى" (`66_female_join_360`, `67_female_pay_block_360`). The bilingual rule message is lost, and "retry" can never succeed.
  - Likely file: `lib/features/payments/enrollment/enrollment_provider.dart:439` (the create-web-session error path) and its failure page. Show `apiErrorText` / `ApiException.message` for `quran_gender_rule` / `quran_teacher_unverified`, and don't offer retry on a 403.
  - Better still, the course page should read the same flag the teacher page reads and disable انضم الآن.

### 4.6 Teacher records progress: pass
- Record sheet (سجل التسميع): program, student, surah 1 الفاتحة, ayahs 1–7, حفظ, ممتاز → حفظ (`80`, `81_record_filled_tall`). This created `quran_progress` 1 (34, teacher 29, course 26, 1:1–7, memorization, grade 5).
- A second entry (النبأ 1–40) went through the API.
- Probes:
  - ayah 1–8 of الفاتحة → 422 `quran_bad_range` "نطاق الآيات يجب أن يكون بين 1 و7";
  - a student not in the teacher's course → 403 `quran_not_your_student`.
- Minor: the record sheet's kind chip "حفظ" and the save button "حفظ" have the same label (`81`).

### 4.7 Student surah/juz map: pass, with a UX issue
- تقدّمي في الحفظ (`68_quran_progress_map_360`): 47 / 6236 ayahs, 2 / 114 surahs complete, 0 / 30 juz, juz 1 4.7 %, juz 30 7.1 %. The numbers are right (7 + 40; 40 / 564). The last entries are listed with their grades (`69b_quran_progress_full_tall`).
- **Medium (UX): tapping a juz tile shows its surahs BELOW all 30 tiles** ("سور الجزء 1"), about 900 px further down on a phone. Nothing visible changes where the user tapped (`69_quran_juz1_surahs_360`).
  - Likely file: `lib/features/quran/quran_progress.dart`. Open the surahs in a sheet, or expand them right under the tapped row.
- Minor: the ring says "1%" while the summary says 0.8 %. At 1366 the header's progress icon sits outside the header card, top-left (`111_quran_1366`).

## 5. Module switches: pass

- **Country tab key.** I chose دولة › مصر (EG) › تبويبات الطلاب في مصر › الألعاب off, then حفظ (`78`, `79_country_EG_games_off`, `79b_country_EG_saved`).
  - `edu_countries.EG.disabled_features = ["student_tab_games"]`, SA = `[]`.
  - `GET /theme/web`: `lh5.stu1` (EG) gets `student_tab_games`; `market.student` (no profile) does not; guest `?country=EG` does; guest `?country=SA` does not.
  - The EG student's bar loses الألعاب (`90_EG_student_after_2nd_reload_360`, crop `90b_EG_nav_crop`). **Pass.**
  - **Minor: it took two reloads.** The first launch still used the cached theme, and the dashboard builds its tab list once in `initState`, so a live `setDisableList` does not drop the tab (`dashboard_screen.dart:186`).
- **Org over country.** Country EG games `points_daily_cap` 21; org 2 (مركز نكست برين للتدريب) cap 5 (`94_org_cap5_saved`). For EG student 36 (a member of org 2), `GET /module-settings/games` → 21 and `?org_id=2` → **5**; SA guest → 20. **Pass.**
  - A non-member asking with `org_id=2` gets 403 `org_forbidden` (good).
- **Where each value comes from:** every field carries a source tag:
  - "القيمة الافتراضية";
  - "من المنصة";
  - "مضبوط للمنصة" / "مضبوط لهذه الدولة" / "مضبوط لهذه المؤسسة", with "استخدم المنصة (20)" / "استخدم الافتراضي (…)" to reset (`76`, `79`, `94`). **Pass.**
  - Note: the org tab shows the org row against the platform value only (it can't know a member's country). That is fine, but it is worth one line of help text.
- Minor: saving on the مؤسسة tab also re-sent `PUT /admin/edu/countries/EG/features` (the last country picked). That is harmless here, but it could overwrite another admin's change. Likely file: `lib/features/admin/modules/admin_modules_page.dart` (save only the dirty scope).

## 6. Parent: pass

- Parent `lh.par85720` › الأبناء: each child card has التقارير / الألعاب / القرآن / النحو (`97_parent_children_tab_360`).
  - For the linked child (34): games 4 plays / 8 stars / 2 badges (`99_parent_child_games_360`), the Quran juz map (`100`), nahw "أتممت 1 من 3 · 80%" (`101`). No 4xx.
- API, as the parent:
  - linked 34 → 200 for `/parent/children/34/games`, `/quran/progress` and `/nahw`;
  - unlinked 36 and unknown 99999 → **404 `LINK_NOT_FOUND`** on all three. **Pass.**
- Medium (layout): the pushed pages' titles ("ألعاب طالب المرحلة الرابعة") wrap to two lines and are clipped by the 360 header card (`99`).
- Note: the parent also sees "طالب اختبار المرحلة" (31), linked on 2026-11-20 by an older test, though `parent_student_links` had no row for it. It may come from another link table; I did not check further.

## Test notes (not app bugs)

- Signing in through the API as a user who is signed in in the browser ends the browser session (single session). API probes used other accounts or ran last.
- With Flutter web semantics on, a mouse-wheel scroll left the semantics rects stale. Taps then hit the wrong node, so long forms were driven in a taller viewport without scrolling. A real touch user is not affected, but a screen-reader user may be; worth one manual check on a phone with TalkBack.
- Local data changes are left in the `lhdev` volumes:
  - `program_kind`, genders, parent link, enrolment 34 → 26, org member 36 → 2, passwords;
  - module settings rows (games platform `points_rewards`, quran platform `gender_matching=same`, games EG cap 21, games org 2 cap 5);
  - EG `disabled_features` = `["student_tab_games"]`.

  Reset the rows and EG features before the next QA run if defaults are wanted.

## Re-walk after the 6.F fixes (2026-11-21)

Same stack (`lhdev`, volumes kept, back a5a45ae with no new migration), the web app rebuilt from the 6.F tree into the same folder and
served on :41500, playwright-core + headless Chrome, Arabic, 360×780, student `lh4.stu1` (34, EG, gender m).
Screenshots: `C:/Users/ahmed/AppData/Local/Temp/lhshots/phase6/fix/`.

| Item | Result |
|---|---|
| Student bar at 360 (high) | **Pass.** Five slots: الرئيسية · كورساتي · التعلّم · جدولي · حسابي, no overlap (`f01_home_360`). التعلّم opens a sheet with المتجر / الألعاب / القرآن / النحو / التحليلات, each with its hint (`f02_learn_sheet_360`). |
| EG Games switch (medium) | **Pass, one launch.** With `student_tab_games` off for EG, the theme is fetched again right after the sign-in and the Learn sheet has no الألعاب in the same session (`f02_learn_sheet_after_signin_360`). The first rebuild missed it: the password sign-in goes through `completeSession`, which did not call the refresh; fixed there (`auth_provider.dart`). |
| Mismatched Quran booking (high) | **Pass.** `/app/courses/24` no longer offers انضم الآن; the page shows "هذا البرنامج يشترط أن يكون المعلم من نفس جنس الطالب. اختر معلماً آخر." (also in the semantics tree, `f04_course24_360`). The checkout's 403 path (bilingual reason + "العودة إلى الكورس", no retry) was not walked, since Join is no longer reachable for this course. API: `POST /courses/24/enroll` → 403 `quran_gender_rule`. |
| Quran teacher page semantics (high) | **Pass.** After a reload of `/app/quran/teachers/29` the tree holds the header, the bio, the ijazah, the goals and "احجز: QA4 قرآن تأسيس…" (`f_dump_quran_teachers_29`). |
| Quiz question semantics (high) | **Pass.** `/app/games/1` (reloaded) reads "السؤال 1 من 8, النقاط 0", "٦ × ٦ = ؟" and the four options (`f12_game1_reload_360`). |
| Deep routes after a reload (medium) | **Pass** for `/app/quran/teachers/32`, `/app/quran/teachers/29`, `/app/quran/progress`, `/app/nahw/lessons/1`, `/app/games/1` (`f05`–`f09`, `f12`). |
| Juz surahs (medium) | **Pass.** Tapping الجزء 1 opens a sheet "سور الجزء 1" with الفاتحة 7/7 and البقرة 0/286 where the user is (`f08_juz1_sheet_360`). |

Back fixes probed on the live stack: course 26 `PUT {program_kind:'course'}` with an enrolment → 409 `program_kind_locked`;
`PUT /admin/edu/countries/SA/features {disabled:['student_tab_gamez']}` → 422 `feature_unknown`; `GET /admin/quran/teachers?status=published` → 200.
The match / order tone and placement, classify chip labels and the parent titles are covered by widget tests only (not re-walked).

Data left in the volumes: as listed above, except EG `disabled_features` is back to `[]` (reset after the walk).
`users.device_id` of 34 and `user_devices` were cleared for the browser sign-ins.
