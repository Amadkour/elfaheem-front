# Phase-1 audit — Flutter app (`nextbrain-front`)

Date: 2026-10-24. Branch: `feature/platform-rbac-exams-rag`. Method: an independent read-only audit pass with fresh context, file:line evidence, cross-checked against the backend audit (`../back/docs/AUDIT.md`, which holds the server-side findings, the domain gap analysis and the exam-module analysis).

## 0. Baseline

| Check | Result |
|---|---|
| `flutter analyze` | 292 issues, all `info` (0 errors, 0 warnings) |
| `flutter test test/org/ test/export/ test/ui/` | 321 passed |
| Size | 486 Dart files, ≈215k lines, 37 test files (≈340 tests) |
| Codegen / OpenAPI | none; 436 hand-written `fromJson` in 95 files |
| CI | none |
| Release hardening | none (see H3) |

## 1. High findings

| # | Where | Finding |
|---|---|---|
| H1 | `lib/core/api_client.dart:358-384` (`TokenStorage`), `auth_provider.dart:658` | **Access and refresh tokens, and the cached user with its `role`, live in SharedPreferences** (localStorage on web). `flutter_secure_storage` is used only for offline video keys, the attendance key and the device id. |
| H2 | `api_client.dart:1061-1065` | Refresh token is sent as a **query parameter** (`POST /auth/refresh?refresh_token=…`), so it lands in server and proxy logs. |
| H3 | `android/app/build.gradle.kts:35` and signing config | Release build: `isMinifyEnabled=false`, `isShrinkResources=false`, **signed with the debug key**, `applicationId = "com.example.flutter_education_app"`; no `--obfuscate`/`--split-debug-info` anywhere. |
| H4 | `lib/config/app_config.dart:13` | `AppConfig.testMode` is hard-coded `true`, so `_ApiLogInterceptor` (`api_client.dart:819`) logs decrypted request/response bodies in release builds. |
| H5 | `student_active_exam_screen.dart:38`, `student_course_exams_widget.dart:36-37` | Exam **passcode is checked on the client only** (the server never validates it, see backend H12). |
| H6 | `student_active_exam_screen.dart:265-272`, `student_exam_provider.dart:402-407,263-276` | Exam timer is a local `Timer.periodic` from `duration*60`, not anchored to a server deadline; no autosave; submit posts one request per question and continues when one fails (partial submissions). `Question.fromJson` accepts `correct_answer` (`shared/models/exam_model.dart:168-177`). |
| H7 | `lib/main.dart:1196-1223` | `_Guard` checks login only, not role; on web any signed-in user can open `/admin_dashboard` or `/org_dashboard` by URL (server-side checks are the only protection). |

## 2. Medium findings

- **Transport:** the documented 3× transport retry does not exist (`postMultipart.maxRetries` defaults to 0, lines 1366-1431); `connectTimeout` is 60 min (788); envelope-encryption handshake uses an unpinned bare `Dio` and the header still says "UNVERIFIED" (555-735, 612); multipart bodies are not encrypted (593); a single leaf-certificate pin without backup (774-777) means every cert renewal needs an app release.
- **Providers:** `lib/core/providers.dart` registers `TeacherSchedulesProvider` (62, 66) and `ProfileProvider` (97, 101) twice; `AppModeController` is a singleton outside the tree; `BaseProvider.run()` does not retry `ApiException` and its fallback errors are hard-coded Arabic (`base_provider.dart:85,93,101`).
- **Permissions in UI:** two helpers with different sources: `OrgSession.can()` (`org_providers.dart:66-86`, from `GET /org/mine`) and a local `can()` in `org_member_dashboard.dart:205-212` (from `/me/overview`); `OrgSession` and `AppModeController` each hold a "current org", reconciled by `applyOrgContext` (`app_mode.dart:216-225`).
- **Org exit rule:** `ContextExitButton` appears in 3 org files while 25 org files build an app bar (CLAUDE.md requires it on every org screen).
- **Business logic in widgets:** 299 API calls inside 58 `State` classes (`org_join_pages.dart` 23, `org_registrar_staff.dart` 21, `org_registrar_member.dart` 18, `org_access_joining.dart` 18, `course_profile_parts.dart` 15). The `ApiClient` singleton cannot be faked, so none of it is tested.
- **Exam UI:** teacher side is one 3,348-line `teacher_exam_hub_screen.dart` knowing two question kinds (MCQ or open text, `:1360-1366`); no sections, rubric, media, multi-select, matching or numeric types; no proctoring, consent or calibration code anywhere (no lifecycle/visibility tracking for exams, no camera package; `screen_protector` only in the video player).
- **Web:** `dart:io` imported in 19 files, 4 without a `kIsWeb` guard in the same file (`base_provider.dart` types only; `upload_queue_manager.dart:130,152,223` uses `File(task.path)`; `data_lab_saver_io.dart`; `recorder_native_select.dart`).
- **Localization:** three string systems (4,032 JSON keys, ≈4,057 `t(ar,en)` calls in org by design, ≈880 outside org, ≈592 raw Arabic lines outside org, e.g. `attendance_strings.dart` 143, `app_time.dart` 33).
- **Accessibility:** `Semantics(` 17, `Focus(` 14, `Shortcuts(` 4; keyboard navigation on web essentially absent.
- **Dependencies:** never imported in `lib/`: `chewie`, `flutter_spinkit`, `flutter_background`, `linkify`, `logging`, `cached_network_image`, `mime`; `flutter_webrtc` override tracks a moving `main` branch; `flutter_lints`/`flutter_test` sit under `dependency_overrides`; several `any` constraints; `pointycastle` unconstrained.
- **Tests:** no coverage of providers, `ApiClient` (refresh, encryption, error mapping), auth/`homeRoute`, exams, `BaseProvider`, `OrgSession.can`.

## 3. What exists and is reused

`AppMode.individual/organization` + `AppModeController.openOrg` + `ContextSwitcher`/`leaveToPersonal` (`lib/core/app_mode.dart`, `lib/design/context_switcher.dart`); org join flows (`org_access_joining.dart`, `org_join_scan.dart`, `org_join_pages.dart`); people/roles (`org_people_page.dart`, `org_access_page.dart`, `org_member_form.dart`); platform settings (`admin_platform_settings_page.dart`, `org_platform_settings_page.dart`, `admin_fee_rates.dart`); payments (`features/student/enrollment/`); payouts (`teacher_payouts_screen.dart`, `admin_payouts_page.dart`); exam timetables (`org_schedule_exams.dart` with the `RemoteExamApi`/`MockExamApi` pattern at `:121,150`, `org_my_exams.dart`); the UI kit (`lib/design/app_kit.dart`), `BasePage`, `AppTime`, the layout harness.

## 4. Constraints for the plan

1. Keep `provider` + `BaseProvider` (DECISIONS D-001). New feature logic goes in providers or `XxxApi` Remote/Mock classes, never in `State` classes, so it can be tested.
2. Every new widget gets a plain-values presentational part tested with `expectNoLayoutErrors` at 320×640 / 1400×900, ar/en, 1.3× text scale.
3. Generated API clients must run inside the existing `ApiClient` (interceptors for encryption, refresh, device headers, view-as, guest) rather than replace it.
4. Any new package: check `pubspec.lock` gains only that package (no `archive` 3.x / `image` downgrades).
