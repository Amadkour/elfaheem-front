# Learning Hub Phase 4: real web build QA (2026-11-20)

How it was run:
- Back: `_wt/lh-back` (feature/learning-hub, 670dfc8), compose project `lhdev` (`docker-compose.lh.yml`, gateway :41080, volumes kept). The api auto-migrated 0103 → **0104** on start.
- Seed: 15 courses through `POST /courses` + `/publish` as `lh.tch38899` and `market.teacher`, ids **16–30**, all titled "QA4 …" (Arabic title only). EG: prep g2 in Dokki / New Cairo, prep g2+g3 both in Nasr City, prep whole-stage in Haram, sec g1 Mohandessin, sec g3 Maadi, sec whole-stage online, prim g4 online, prim whole-stage at Giza governorate level, prim g1+g2 both in Shubra, prep g1 recorded online. SA: intermediate g2 online, secondary in-person Olaya, prim g6 both Malqa.
- Front: `_wt/lh-front` (1039a596), `flutter build web --profile --dart-define=API_BASE_URL=http://localhost:41080/api --base-href /app/`. The landing (`npm run build`) was served at `/` and the app at `/app/` with an SPA fallback, by one node server on :41500. That server also proxied `/api/api/v1/…` to the gateway for the landing's same-origin calls.
- Driver: playwright-core + headless Chrome, Arabic, 360×780 and 1366×900.
- New accounts (password `Qa4Pass!2026`): student `lh4.stu1@example.test` (id 34), teacher `lh4.tch1@example.test`. Course 31 was created through the form.

Screenshots: `C:/Users/ahmed/AppData/Local/Temp/lhshots/phase4/`, named by file below.

## Summary

| Step | Result |
|---|---|
| 1. Landing at 360 px, four entry buttons | **Pass** |
| 2. Student join → explorer shows only matching courses | **Pass for the filtering; FAIL for the cards.** The explorer's course cards have no title, and every course is labelled "دروس مسجّلة". |
| 3. Guest books a course → sign up / sign in → back on that course's checkout, also after a reload | **Pass, with two bugs on the way.** After a reload, "تسجيل الدخول" on the register page gives a white screen. The guest sign-in sheet is see-through. |
| 4. Join as a teacher / as a parent | **Pass** (some copy nits) |
| 5. Student home filter bar | **FAIL.** A new student's bar starts empty, not from the profile. Change, Clear and reload work. The home's count is misleading. |
| 6. Teacher creates an in-person course with 2 targets + area + address at 360 px | **Pass** |

No overflow stripes were seen, and RTL was correct everywhere I looked. No Phase 4 call returned 4xx/5xx. The errors seen are listed under "Network and console".

## 1. Landing: pass

- `01_landing_360.png`, `01b_join_buttons_360.png`.
- The buttons sit in a 2×2 grid, each 160×56: انضم كطالب, انضم كمعلم, ولي أمر and أضف مؤسستك.
- Their links are `/app/join?role=student|teacher|parent&lang=ar` and `/app/start/institution?lang=ar`.
- There is no horizontal scroll (scrollWidth 360), and the page is `lang=ar dir=rtl`.
- `80_landing_desktop.png` is the same page at 1366 px.

## 2. Student join → explorer

- Walk: انضم كطالب → `/app/join?role=student&lang=ar`. Country starts on مصر (`02`), stage الإعدادي → grade الصف الثاني (`03`–`05`), حضوري في مركز (`06`), area الجيزة › الدقي (`07`–`10`), skip contact (`11`), confirm (`12_join_confirm.png`).
- **Filtering: pass.**
  - The app asked `GET /courses?…&mode=any&country=EG&stage_id=3&grade_id=10&delivery=in_person&area_id=15`.
  - The explorer said "دورتان" (two courses), at 600 and 100 ج.م.
  - The same query through the API returns exactly **16** (Dokki prep g2) and **14** (Phase 3's Dokki course).
  - Correctly left out:
    - 25 (New Cairo);
    - 22 (Haram, whole stage: another city);
    - 18 (Nasr City);
    - 17 (online).
- **BUG (high): the explorer's course cards have no title, and every course reads "دروس مسجّلة"** (`13_explorer_results.png`, desktop `64_show_more_explorer_desktop.png`; also the parent's explorer, `48_parent_explorer.png`).
  - Course 16 is a live course, yet its card says recorded.
  - The cards show no title, no teacher and no rating, only a placeholder and the price. All the guest or student has to go on is a price.
  - Cause: `CategoryCourseModel.fromJson` reads `json['name']`, which `CourseResponse` does not have (it has `name_ar` / `name_en`). It never reads `type`, so `CourseModel.fromCategoryModel` falls back to recorded. The teacher comes from `teacher.name`, which is present but is not drawn.
  - Likely file: `lib/features/courses/category/model.dart:44` (`title: json['name']`), plus `CourseModel.fromCategoryModel`. The explorer is `lib/features/courses/category/categories_screen.dart:816` (`HomeCourseList` over `e.toCourseModel`).
  - The student home's own list (another model) shows titles correctly (`54_home_filter_bar.png`).
- Minor: in the guest explorer that the join flow opens, the area chip is named generically. Its semantics label is "إزالة المنطقة", not "إزالة الدقي". When the area is picked in the explorer's own sheet, it reads "إزالة الدقي" (`83_explorer_area_chip_desktop.png`). The join hand-off passes only `area_id`, so the chip has no name to show. Likely file: `lib/features/courses/course_filters.dart` (the chip label when `CourseFilterEdu` has no area row).
- Minor (design): a Dokki pick does not include courses tagged at the governorate level (course 24, area = الجيزة). This is the server's rule: `area_id` matches `area_id OR area_parent_id`, never the parent. Worth a decision in `features/courses/course_service.learning_filters`.
- Minor: on the area sheet's second level (`09_area_level2.png`) there is no "the whole governorate" choice. A learner who only knows "Giza" must pick a city.

## 3. Guest book → sign up / sign in → checkout

- As a guest, the course page (`14_guest_course_detail.png`) → انضم الآن → sign-in sheet (`15_book_as_guest.png`) → إنشاء حساب.
  - `pending_intent` = `{"v":1,"kind":"book_course","id":"16","plan":null,"filters":{},"at":…}` (`16_register_from_book.png`).
  - The register page opened with **طالب** preselected.
  - The study step was prefilled from the join draft: EG, الإعدادي, الصف الثاني (`21_study_step.png`).
  - `POST /auth/register` → OTP (`22_otp.png`) → `verify-otp` → the login screen.
- Reload during login: I reloaded `/app/login` and signed in. The pending intent was still there.
  - The app went to `/app/courses/16` and then straight to **إتمام الدفع** (checkout) for that course (`29_after_login.png`), with yearly preselected.
  - The intent was then cleared (`pending_intent` → null).
  - **Pass.**
- **BUG (high): white screen from "تسجيل الدخول" on a register page that is the first route** (`27_login.png`, `27b_login_wait.png`, `28c_register_root_signin_link.png`).
  - After the OTP is verified, the login screen shows but the URL stays **`/app/register`**. A reload during login therefore lands on the register page as the root route.
  - Its "هل لديك حساب بالفعل؟ تسجيل الدخول" link calls `Navigator.pop(context)` and pops the only route, leaving an empty white page.
  - It reproduces on a fresh tab by opening `/app/register` and tapping تسجيل الدخول. From login → register → back it works (`28b_back_to_login.png`).
  - Likely file: `lib/features/auth/register_screen.dart:555` (`onTap: () => Navigator.pop(context)`). It should use `maybePop`, else `pushReplacementNamed('/login')`. Also, the login screen shown after verify-otp should update the URL to `/login`.
- **BUG (medium): the guest sign-in sheet is see-through** (`15_book_as_guest.png`). The page's stat cards and the "انضم الآن" bar show through the sheet's text.
  - `GuestGuard._showSheet` passes `backgroundColor: Colors.transparent`, and `_GuestLoginSheet`'s `Container` has no colour or decoration.
  - Likely file: `lib/features/guest/guest_state.dart:135` / `:258`.
- **BUG (medium, data): the student's area is not shown on the study step.** The join draft had الدقي، الجيزة, but the area tile is empty (`21c_study_area_expanded.png`). The account was nevertheless created with `area_id=15` (DB: `student_study_profiles` 34 → stage 3, grade 10, area 15, EG), and Profile › بيانات الدراسة shows "الدقي، الجيزة" afterwards (`60_study_profile_page.png`). So only the display is lost: `StudyProfile(areaId:)` from `JoinDraft.studyProfile` carries no area name or parent for the tile. Likely files: `lib/features/onboarding/join/join_draft.dart:97` and the study step's area tile in `lib/features/profile/study_profile/` (resolve `areaId` through `EduCatalog.areas`, as the 3.R fix did for the profile page).
- Minor, not Phase 4:
  - Without a date of birth, "إنشاء حسابي" shows a Fluttertoast that is **English and untranslated**: "please select your birth of date". The same goes for "password must be identical" and "please select your role". In `register_screen.dart:169-200`.
  - The terms checkbox ignores taps until the terms sheet is read (by design), but nothing on screen says so.
  - The OTP boxes still lose focus when digits are typed one by one: the code was submitted half-typed and wrong, leaving 4 tries ("رمز التحقق غير صحيح (متبقٍ 4)", `23_otp_filled.png`). Pasting the whole code works. In `verified_screen.dart:349`.
  - As a guest, the course page calls `GET /payments/transfer-status?course_id=16` twice, both **401**.
  - The checkout shows **ر.س** for an EGP course: 600 ج.م on the course page, "686.80 ر.س" on the checkout (`29_after_login.png`). `/payments/price-options` and `/payments/fees/preview` say `EGP`; `/config` says `SAR`, because the dev stack's provider is Moyasar. The checkout labels the course price with the provider's currency.

## 4. Teacher and parent join: pass

- **Teacher** (`30`–`44`):
  - Walk: country مصر → levels (two stages; the grades chosen were الصف الأول الإعدادي and الصف الثالث الثانوي) → أيهما → مدينة نصر، القاهرة → skip → confirm (`38_teacher_confirm.png`) → "أنشئ حساب المعلم".
  - That opens the register page with **معلم** preselected (`39b_teacher_register_role.png`). OTP leads to the complete-profile step, with the levels **prefilled from the join** (`41b_teacher_profile_levels.png`).
  - `POST /auth/teacher-profile` → **201**. The table `teacher_teaching_levels` holds (3, 9) and (4, 14), exactly what was picked. The app then lands on login (`44_teacher_end.png`).
  - Nits:
    - On the delivery step, the teacher sees the student's copy: "في مركز قريب منك" and "أرني كل شيء" (`35_teacher_delivery.png`).
    - The confirm row is labelled "طريقة الدراسة" (`38`).
    - During the complete-profile step the URL still reads `/app/join?role=teacher`, so a reload restarts the join.
    - Years of experience is empty by default, and "متابعة" did nothing with no visible message until I set it.
    - `POST /auth/teacher-documents/overview` → **401** (already noted in Phase 3).
  - Join flow file: `lib/features/onboarding/join/join_steps.dart:279` (the delivery copy) and `:472`.
- **Parent** (`45`–`51`):
  - Walk: country → child's stage/grade (الابتدائي, الصف الرابع) → أونلاين. The area step is skipped, so the flow has 6 steps. Contact has a child-code field. Skip → confirm.
  - "اعرض الدورات المناسبة" → guest explorer with `country=EG&stage_id=2&grade_id=6&delivery=online`. The one result is course 23, which matches the API.
  - After a reload, `/join?role=parent` restarts at step 2 but keeps every answer (`join_draft` in storage).
  - "أنشئ حسابًا" opens the register page with **ولي أمر** preselected (`51_parent_register.png`).

## 5. Student home filter bar: FAIL

- **BUG (high): a new student's bar does not start from the profile's stage / grade.**
  - What happened: `lh4.stu1` registered with prep g2. After sign-in the home bar shows "تصفية" with no filter, and the list mixes SA courses, other stages and SA prices (`52`, `54_home_filter_bar.png`).
  - Cause: the seed key `course_filters_seed_<user>` is written only by `StudyProfileApi._seed`, that is, only when `/me/study-profile` is loaded or saved (the Profile › بيانات الدراسة page). Neither the registration (which sends the profile in `/auth/register`) nor the home ever calls it, so a new account never gets a seed.
  - Confirmed: after visiting the study page, the key appeared (`{"country":"EG","stage_id":3,"grade_id":10}`). The home then started on "تصفية · 1" with الصف الثاني الإعدادي (`61_home_from_profile_seed.png`).
  - Likely files: `lib/features/courses/course_filters.dart:217` (`CourseFilterStore.initial`) and `lib/features/profile/study_profile/study_profile_model.dart:458`.
  - Fix: seed from `/me/home`, or on the first sign-in from the registration's study profile. Or have `initial` fall back to a one-time `/me/study-profile` call when neither key exists.
- Change filters: pass. In the sheet (`55_filter_sheet.png`, `56_filter_sheet_set.png`) I chose الإعدادي → الصف الثاني → حضوري, then عرض الدورات. The result was "تصفية · 2" with chips (`57_home_filtered.png`).
- **Misleading count (medium):** the home then said **"دورة واحدة"** (one course: 25), but `GET /courses` with the same filters returns 5 (25, 22, 18, 16, 14).
  - The home filters only the ~8 courses its marketing call already brought, as D-1325 intends, yet it presents that number as the result.
  - Likewise "تصفية · 1" → "دورة واحدة" on the home, while "مشاهدة الكل" opens the explorer with **6** (`64_show_more_explorer_desktop.png`).
  - Suggest: show no count on the home (or "من المعروض"), or ask `/courses` once for the count. In `lib/features/home/student/home_screen.dart:821-837`.
- Remembered after reload: **pass.** `course_filters_34 = {"stage_id":3,"grade_id":10,"delivery":"in_person"}`, and after a reload the bar showed the same two chips and the same list (`58_home_after_reload.png`, `58b_home_after_reload_bar.png`).
- Clear: **pass.** "مسح" emptied the bar and stored `{}`, and the list returned to all courses (`59_home_cleared.png`).
- Minor:
  - On desktop the grade dropdown truncates the grade to "الصف الثا…" (`62_home_desktop_filters.png`).
  - The sheet offers no country. An EG student with no filters sees SA courses in SAR.

## 6. Create form at 360 px: pass

- Steps: كورساتي › إضافة دورة جديدة (`67_create_form_top.png`). I typed the Arabic title and description (`68`), then:
  - الإعدادي opened its grades (`70_form_stage_tap.png`);
  - الصف الثاني was added as a target (`71`);
  - الثانوي › المرحلة كاملة was added as a second target (`72`, `73_two_targets.png`);
  - then حضوري (`74`) and subject كيمياء (`75_subject_picker.png`);
  - the area tile opened the sheet, where I picked الجيزة › المهندسين (`76_area_sheet.png`);
  - I typed the address (`77_area_address_filled.png`) and pressed حفظ في المسودة.
- `POST /courses` → **201**. Course 31 was stored with:
  - `delivery_mode=in_person, country EG, area_id=16, area_parent_id=12, subject_id=9`;
  - the address "5 شارع شهاب، المهندسين";
  - targets (3, 10) and (4, null).
- It shows in the list as a draft (`78_after_save.png`).
- Minor:
  - The bottom bar still cuts the draft button to "حفظ في الـ…" (`70`, `77`).
  - I did not touch the type chips (مباشر / مسجّل / الاثنان), and the course was saved as RECORDED. Check that the chip shown as selected by default is the one the form sends: `lib/features/courses/teacher/course_form_screen.dart`.

## Network and console

- 4xx / 5xx calls:

  | Call | Status | Note |
  |---|---|---|
  | `GET /payments/transfer-status` (as a guest) | 401 | step 3 |
  | `POST /auth/teacher-documents/overview` | 401 | step 4 |
  | `POST /auth/verify-otp` | 400 | my half-typed code |
  | `GET /releases/releases.json` | 404 | the landing's download manifest, absent from a local `dist` |
  | `assets/LazyFontManifest.json` | missing | written by `scripts/web/postbuild.dart`, which a plain `flutter build` does not run |

  No Phase 4 route failed.
- Console: no page errors, and no errors besides the resource failures above.
- Untranslated text: the three English register toasts in step 3. The guest's "Course" label from Phase 3 was not on any path walked.

## Not done

- Phase 4 kill switches (`join.flow`, `courses.filters`) were not toggled.
- SA was only seeded and seen in lists. No SA join was walked.

## Re-test after the fixes (D-1326, 2026-11-20)

Same stack (`lhdev`, volumes kept, back with the D-1326 changes live through `--reload`), a new `--profile` web build of the front with the fixes, served by the same node server on :41500. Headless Chrome, Arabic, 390×844. Screenshots in `C:/Users/ahmed/AppData/Local/Temp/lhshots/phase4/retest/`. New account: student `lh5.stu1@example.test` (id 36, prep g2, Dokki).

| QA item | Result |
|---|---|
| Explorer cards: no title, all "recorded" (high) | **Fixed.** Cards show the title, teacher and the real type ("مباشر" for live courses) (`r20_explorer_cards.png`). `CategoryCourseModel` keeps the `CourseResponse` and the card is built by `CourseModel.fromJson`. |
| White screen from "تسجيل الدخول" on a root register page (high) | **Fixed.** Fresh tab on `/app/register` → تسجيل الدخول opens the login page at `/app/login` (`r01_register_root_signin.png`). |
| URL stays `/register` after the OTP (high) | **Fixed.** After verify-otp the login page is the only route and the URL is `/app/login` (`r51_login_after_otp.png`); a reload there stays on login (`r52_login_reloaded.png`). |
| Guest sign-in sheet see-through (medium) | **Fixed.** The sheet uses the theme's opaque sheet colour (`r31_guest_sheet.png`). |
| New student's home bar starts empty (high) | **Fixed.** The dashboard call is `student-dashboard?scope=personal&level=profile`; the bar starts on "تصفية · 1 · الصف الثاني الإعدادي - معدّل" with "6 دورات", and `course_filters_seed_36` is written from `study_level` (`r57_new_student_bar.png`). No extra request on home open. |
| Misleading count on the home (medium) | **Fixed.** The count is the server's total: guest with stage 3 / grade 10 → "6 دورات", `GET /courses` with the same filters → 6 (`r15_guest_home_bar_count.png`). Removing the level chip asks `GET /courses?limit=12&scope=personal&country=EG` and redraws the strip without reloading the dashboard (`r58_bar_cleared_level.png`). |
| Area not shown on the study step (medium) | **Fixed.** With a join draft for Dokki, the study step's area tile reads "الدقي، الجيزة" (`r41_study_area.png`); the account was stored with area 15. |
| Checkout in ر.س for an EGP course | **Fixed.** Checkout of course 25 shows ج.م everywhere ("ادفع 686.80 ج.م", `r55_resume_checkout.png`): the label follows `price-options.currency`, not `/config`. |
| PendingIntent after sign-in | **Pass.** A fresh intent resumes after a reload of the signed-in app: course 25, then its checkout. The intent saved during this walk had expired by the time of sign-in (the walk paused for more than 2 h, the new TTL), so it was correctly dropped. |

Not re-walked: the kill switches `join.flow` / `courses.filters` (covered by widget tests), the minor items listed above (OTP focus, English register toasts, area chip name from the join hand-off, governorate-level match, desktop grade truncation). Phone collision note: the first register attempt answered 400 "Phone already registered" because the phone typed belonged to a teacher seed; a different number went through.

The stack was stopped afterwards (`docker compose stop`, volumes kept).
