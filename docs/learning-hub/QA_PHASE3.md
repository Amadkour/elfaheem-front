# Learning Hub Phase 3: real web build QA (2026-11-20)

How it was run:
- Back: `_wt/lh-back` (feature/learning-hub, f085a08), compose project `lhdev` (`docker-compose.lh.yml`, gateway :41080). Core migrations were at 0103 and the edu seed loaded (EG/SA catalog, geo areas). The demo seed was run after the api started.
- Front: `_wt/lh-front` (29ceee0a), `flutter build web --profile --dart-define=API_BASE_URL=http://localhost:41080/api`, served on :41500 with SPA fallback.
- Driver: playwright-core and headless Chrome, in Arabic, at phone size (390×844) and desktop size (1366×900).

Screenshots are in `C:/Users/ahmed/AppData/Local/Temp/lhshots/phase3/`. Below, they are named by file only.

## Summary

| Flow | Result |
|---|---|
| (a) New student: country, stage, grade, area, then reopen | **Pass, with one bug.** Everything saved, but on reopen the area shows the governorate only. |
| (b) New teacher: teaching levels, then first sign-in | **Pass** |
| (c) Parent links a minor, with and without consent | **Pass, with one UI issue.** The refusal toast uses the success style. |
| (d) Teacher creates an in-person course with targets, area and address | **Fail (blocker).** In create mode the stage chips and the area tile do nothing. The teacher's course page also never shows the address. |
| (e) Super admin renames a grade, then the student picker | **Pass** |

No overflow stripes were seen. The pages were RTL as expected. No console errors came from Phase 3 code.

## (a) Student registration: pass, with one bug

- The sign-up form leads to the study step (`a04_study_step.png`). In order:
  - Country: مصر.
  - Stage: الإعدادي.
  - Grade: الصف الثاني الإعدادي.
  - Gender: ذكر.
  - "Add school and governorate", where the area sheet goes الجيزة › الدقي (`a06_area_sheet.png`, `a07_area_level2.png`, `a08_study_filled.png`).
- Then OTP and sign-in.
- The database row `student_study_profiles` holds `country_code=EG, stage_id=3, grade_id=10, area_id=15 (الدقي, parent 12 الجيزة), stage=preparatory, grade=2, governorate=giza, gender=m`. Everything persisted.
- **BUG: the city level is lost on reopen** (`a12b_study_profile_reopen_scrolled.png`, `a13_study_profile_desktop.png`).
  - Profile › بيانات الدراسة shows the area as **"الجيزة"** instead of **"الدقي، الجيزة"**.
  - Cause: `_areaFromProfile` builds a level-1 `EduArea` from the old `governorate` key, with `id = areaId`. That is the city's id (15) wearing the governorate's name. It never resolves the area's own name or its parent.
  - Likely file: `lib/features/profile/study_profile/study_profile_form.dart:116`. Fix: resolve `area_id` through `EduCatalog.areas` (or have the server return `area {name, parent}`, as courses already do).
- Minor:
  - The study step and the study page show the label **"الدولة" twice** above the country dropdown (`a04_study_step.png`, `a13_study_profile_desktop.png`). The likely cause is `EduCountryPicker` adding its own label over `AppDropdown`'s, in `lib/design/edu_pickers.dart:152`.
  - On desktop the area tile sits right against the "تاريخ الميلاد" label below it, with no gap (`a13`).

## (b) Teacher registration: pass

- The complete-profile step offers "المراحل والسنوات التي أدرّسها". I chose الإعدادي → الصف الثاني + الصف الثالث, plus الثانوي → كل الصفوف (`b05_levels_two_stages.png`).
- The choice was stored in `flutter.pending_teaching_levels`. On first sign-in the app sent `PUT /api/v1/me/teaching-levels`, which returned **200**, and the pending key was cleared.
- The table `teacher_teaching_levels` holds exactly (4, null), (3, 10) and (3, 11). The home screen loaded fine (`b09_teacher_first_signin.png`).
- Seen on the way; not Phase 3, but in the same flow:
  - The bio field says "نبذة مختصرة (اختياري)" (optional) yet blocks on submit. Its error text mixes languages: **"نبذة مختصرة (اختياري) is required"** (`b07_bio_required_mixed_lang.png`). This is in the teacher complete-profile form, `lib/features/auth/additional_register_screen.dart`.
  - `POST /api/v1/auth/teacher-documents/overview` returned **401** while registering, because there is no session yet.

## (c) Parent link and consent: pass, with one UI issue

- I registered a new parent, then redeemed the student's code under الربط.
- **Without consent:** `POST /parent/link/redeem` returned 422 `consent_required`. The consent dialog appeared (`c08_consent_dialog.png`), and "أوافق" stayed disabled until the box was ticked. I chose Cancel, and the child was not linked. The notice read "يلزم موافقة ولي الأمر على حساب الطالب القاصر" (`c09_consent_declined.png`).
  - **UI issue:** that refusal is drawn with the **green success check**.
  - Cause: `plToast` / `showAppNotice` is called without `error: true`. Likely file: `lib/features/parent/parent_link_screen.dart`, the `plToast(p.errorMessage)` call (and the `plToast` helper).
- **With consent:** I ticked the box and pressed أوافق. The second redeem returned **200**, showed "تم الربط بنجاح" and the request "تمت الموافقة" (`c11_linked.png`). The child appears under الأبناء (`c12_children_phone.png`, `c13_children_desktop.png`). The table `parent_consents` has the row `kind=minor_account, text_version=v1`.
- My first code had expired. `POST /parent/link/redeem` returned **400** `LINK_CODE_INVALID`, and no error notice was visible 3.5 s later (`c06_consent_dialog.png`). This may be timing; worth a second look.

## (d) In-person course: fail (blocker)

1. **BLOCKER: in the create form, the stage chips and the area tile do not respond.**
   - Where: كورساتي › إضافة دورة جديدة › "لمن هذا الكورس وأين".
   - Tapping a stage chip (for example الإعدادي) never selects it and never shows its grades. I tried mouse clicks, semantics clicks, phone and desktop, on a fresh form and on a filled one (`d03_stage_tapped.png`, `d07_stage_150ms.png`, `d09_fresh_stage_tap.png`).
   - Tapping "محافظة / مدينة أو منطقة" never opens the area sheet (`d14_area_sheet.png`).
   - The delivery chips (provider state) do work.
   - **In edit mode the same section works**: the stage chip opens its grades (`d24_edit_stage_tap.png`), and targets, area and address prefill correctly (`d23_edit_form_prefilled.png`).
   - So a new in-person course cannot be created from the UI: it is refused for want of an area, and the area can't be picked.
   - Likely files: `lib/features/courses/teacher/course_form_screen.dart` (create path around the `CourseSetupSection` at line ~735, and what differs from edit, maybe `_setupReady` / catalog load) and `lib/features/courses/course_setup_views.dart` (`_CourseSetupSectionState`, and `_open` in `EduAreaPicker`).
   - `test/ui/course_setup_test.dart` passes because it pumps the section on its own.
   - In the create form, each tap also scrolled the page back to the last-focused title field (`d06_stage_click_desktop.png`, `d14_area_sheet.png`).
2. **The in-person check without an area works, but uses the wrong tone.**
   - Client side, "اختر المنطقة للكورس الحضوري" shows as a notice and as an inline line (`d11_save_without_area.png`, `d12_area_missing_line.png`).
   - The notice has the **green success icon**, because `_showSnack(msg, color)` ignores `color` and calls `showAppNotice(msg)` without `error: true` (`course_form_screen.dart:520`).
   - The server's 422 is bilingual: `{"code":"course_area_required","message":"اختر المحافظة أو المنطقة للكورس الحضوري","message_en":"Pick the area for an in-person course"}`. Its wording differs slightly from the client's `courseAreaRequiredText()`.
   - The inline error sits under the address field rather than under the area tile.
3. To test the rest, I created the course through the API as the new teacher:
   - Targets: (3, 10) and (4, whole).
   - Area 15. Address "12 شارع التحرير، الدور الثالث". Published.
   - Course id 14.
4. **As a stranger** (the unenrolled new student), the About tab shows the chips "الإعدادي - الصف الثاني الإعدادي", "الثانوي", "حضوري" and "الدقي، الجيزة", with **no address**. **Pass** (`d21_stranger_about.png`, `d22_stranger_about_desktop.png`).
5. **FAIL: as the teacher**, the course page (CourseSpace › عن الكورس) has **no "لمن هذا الكورس وأين" block at all**, so the address is never shown (`d19_teacher_about_tab.png`).
   - The API does return it: for the teacher, `GET /courses/14` has `address` set; for an anonymous viewer it is `null`.
   - `CourseWhoWhereBlock` is used only in `lib/features/courses/student/details/components/about.dart`. The teacher's About tab in `lib/features/courses/course_space/` needs it.
   - Same tab, not Phase 3: the rating card has an untranslated **"Course"** label.
- Minor:
  - The section shows **"المادة" twice** ("المادة" + "المادة (اختياري)").
  - The subject picker is a raw `DropdownButtonFormField` (`course_setup_views.dart:228`), where the UI kit expects `AppDropdown`.
  - On phone, "حفظ في المسودة" is cut off as "حفظ في المـ..." (`d02_form_targets.png`). This is not new.

## (e) Rename a grade: pass

- The super admin opens Education levels, which sits under **المالية والطلبات**, an odd group for it (`e03_edu_levels_page.png`).
- In الإعدادي › الصف الثاني › تعديل الاسم, I renamed it to "الصف الثاني الإعدادي - معدّل" (`e06_rename_dialog.png`). `PATCH /admin/edu/grades/10` returned **200** and the catalog reloaded (`e07_after_rename.png`).
- The student's study page shows the new name right away (`e08_student_picker_no_reload.png`), and so does the course target chip (`e10_course_target_after_rename.png`).
- Minor:
  - On desktop the country bar and the grades panel sit flush with the left screen edge, with no gutter (`e03`).
  - Counts such as "2 صفوف", "0 صفوف" and "3 مواد" are built by hand instead of with `countText`. Likely file: `lib/features/admin/edu/edu_levels_page.dart:110,136,170`.

## Not Phase 3, seen in passing

- **OTP boxes on web:** focus often fails to move to the next box. Two of three sign-ups needed box-by-box typing; once, all six digits landed in box 1 (`a10_otp.png`, `c03_parent_after_verify.png`).
- **A second sign-in from another browser** (another device id) signs out the first browser session. The student also gets the "جهاز غير مسموح به" (device not allowed) dialog. This is expected device binding.

## Re-test after the fixes (D-1315, 2026-11-20)

Same stack (`lhdev`, gateway :41080; the backend mounts the worktree, so it ran the fixed code), a fresh `flutter build web --profile` of the fixed front, served on :41500, playwright-core + headless Chrome, Arabic. The two QA accounts were given the demo password in the local database to sign in again. Screenshots: `C:/Users/ahmed/AppData/Local/Temp/lhshots/phase3/retest/`.

| Item | Result |
|---|---|
| (d) BLOCKER: stage chips and area tile in the CREATE form | **Pass** (desktop 1366×900). Title typed first, then الإعدادي opened its grades (`r07_stage_tap.png`), الصف الثاني selected (`r08`), حضوري, the area tile opened the sheet (`r10_area_sheet.png`) → الجيزة › الدقي (`r11`, `r12_area_filled.png`), address typed, "حفظ في المسودة". The new course (id 15) is stored with `delivery_mode=in_person, area_id=15, area_parent_id=12`, the address and target 3/10 (`r13_saved.png`). The earlier failure did not reproduce on this build; no single cause was isolated. `test/ui/course_setup_test.dart` now pumps the real create form over FakeApi and taps a stage chip, so a regression fails a test. |
| (d) the teacher's own course page has no who/where block | **Pass.** CourseSpace › عن الكورس shows "لمن هذا الكورس وأين" with the two targets, حضوري, "الدقي، الجيزة" and the address "12 شارع التحرير، الدور الثالث" (`r03_teacher_about.png`). |
| (a) the student's area reopens as the governorate only | **Pass** (phone 390×844). Profile › بيانات الدراسة shows **"الدقي، الجيزة"** (`s04_study_reopen.png`). |
| (c) consent-refused toast styled as success | Fixed in code, not re-walked: `plToast` is error-toned by default and only the success notice passes `error: false`. The course form's `_showSnack` now honours the danger colour too (the in-person "pick the area" notice). |

Not re-walked: (b), (e) and the minor items above (they were not in this fix round).

