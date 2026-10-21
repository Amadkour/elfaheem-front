# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Flutter education platform (VOD courses, live sessions, attendance, organizations) — package name `flutter_education_app`, Firebase project `elfaheem`, backend at `AppConfig.baseUrl` (`https://nextbrain.site/api`). Targets Android, iOS and Web (web is deployed to Firebase Hosting from `build/web`). Default UI language is Arabic (RTL); English is also supported.

## Commands

```bash
flutter pub get
flutter analyze                      # lints: package:flutter_lints/flutter.yaml; platform dirs are excluded
flutter run                          # add -d chrome for web
flutter test                         # test/widget_test.dart is the stock counter template and will fail — there is no real test suite
flutter test test/some_test.dart --plain-name "name"   # run a single test
flutter build web && firebase deploy --only hosting
dart run flutter_launcher_icons      # regenerate app icons
dart run flutter_native_splash:create  # regenerate splash screens (android/ios drawables + assets/images/splash*.png)
```

`flutter_webrtc` is overridden to a fork (`github.com/Amadkour/flutter-webrtc`, `main`) in `dependency_overrides`; `screen_protector` is pinned to 1.5.1 on purpose (see the pubspec comment).

## Architecture

**Startup (`lib/main.dart`)** — `_bootstrap()` paints a boot splash immediately, runs `_initCore()` (storage, `assets/translation.json`, Firebase, Remote Config, connectivity, offline videos, …) with each step wrapped in `_safe(name, fn, seconds:)` timeouts so one slow service never blocks launch, then runs the real app. Only a storage failure shows `_FatalApp`. Routing is a single `onGenerateRoute: _router` switch over named routes; the initial route comes from `MyAuthProvider.homeRoute`, which maps the user role (`admin`/`super-admin`/`developer` → `/admin_dashboard`, `teacher`, `parent`, `org-admin`/`org-staff` → `/org_dashboard`, otherwise student `/dashboard`). Offline start-ups route to `/downloads` (or student dashboard + downloads on top).

**Features (`lib/features/<role>/`)** — `student`, `teacher`, `parent`, `admin`, `org`, plus `shared` (attendance, notifications, profile, subscription, downloads, upload, guest, …) and `auth`. Each role has its own dashboard screen.

**State** — `provider` package. All app-wide `ChangeNotifier`s are registered in `lib/core/providers.dart` (`appProviders`); add new global providers there. Feature providers extend `BaseProvider` (`lib/core/base_provider.dart`) and wrap API calls in `run(() => ...)`, which manages `ProviderState` (idle/loading/success/error), sets `errorMessage`, and does one outer retry. Some app-wide state uses singletons (`XService.instance`, `ViewAsState.instance`, `AppConnectivity.instance`).

**Networking (`lib/core/api_client.dart`)** — `ApiClient` is a singleton (`ApiClient()` returns `ApiClient.instance`) on Dio, with `get/post/put/patch/delete/postForm/postMultipart`. Things it does for every request:
- Throws only `ApiException` (`message` is safe to show to the user; `code` holds server codes such as `DEVICE_MISMATCH`, `VIEW_LIMIT_REACHED`). In UI: `ApiException.from(e).message`.
- Retries at the transport level (3 attempts), refreshes tokens, and redirects to login on 401.
- App-layer envelope encryption (X25519 → HKDF → AES-256-GCM, `{"n","ct"}` bodies) and certificate pinning on mobile (`_pinnedCertSha256`). Server cert rotation requires updating the pin list.
- Sends device-ID headers (device binding / blocked-device dialog lives in `features/student/courses/security/`).
- Adds `X-View-As: <id>` while super-admin "view as" mode is active (`utils/widget/view_as_state.dart`).

**Server-driven theme & feature flags** — `ThemeConfigProvider` (`lib/config/theme/`) loads the theme from `GET /api/v1/theme/{platform}` and builds `materialTheme()`. Always read colors via `context.colors`, never hard-coded colors. The same response sets `AppConfig.disableList` (feature kill-switch ids, e.g. `profile.logout`, `teacher_tab_analysis`). To make UI switchable, wrap it in `ParentComponent(featureKey: '...')` (hides it), or give a `BasePage` a `ValueKey('<id>')` (shows a "coming soon" page). `AppConfig.setDisableList` rebuilds the whole widget tree when the list changes.

**UI kit** — New screens should use `lib/design/app_kit.dart` (role-neutral aliases over the Data Lab / org / admin widgets: `AppHero`, `AppCard`, `AppStatTile`, `AppEmpty`, `AppListSkeleton` rather than spinners, `AppBanner`, `AppField`, `showAppSheet`, `appConfirm`, …; the header comment of that file has the full usage table) and wrap pages in `BasePage` (`lib/utils/widget/base_page.dart`), which handles the background, kill-switch, and the global upload-progress footer.

**Localization** — Strings live in `assets/translation.json` as `{ "key": { "en": "...", "ar": "..." } }`. Use `translate('key')` or `'key'.tr`; a missing key falls back to the key itself. Add both `en` and `ar` for every new key. Current language is `AppConfig.lang` (switched by `LangProvider`); use `pageDirection` for RTL/LTR.

**Offline** — `lib/core/offline/` holds connectivity (one app-wide online/offline answer, wired into `topRouteObserver`) and encrypted offline video downloads (AES-CTR via pointycastle). Offline attendance can relay through a nearby online classmate (`features/shared/attendance/`, `nearby_connections`, Android only).

**Native code** — Live sessions use LiveKit (`features/teacher/sessions/live/`). Screen recording and screen sharing use platform channels (`com.example.flutter_education_app/native_recorder`, `/radios`). The native side is `android/app/src/main/kotlin/.../ScreenCaptureService.kt` and `MainActivity.kt`, and on iOS `ios/Runner/AppDelegate.swift`, `LocalDebugRecorder.swift`, and the `ios/BroadcastUploadExtension` target. Recordings upload in chunks.

**Organizations (`lib/features/org/`)** — The backend source is next door at `../back` (`routers/organization/`, `services/organization/`). Check payloads there; don't trust the notes alone. Shared logic lives in `org_v3.dart`: `orgCall` keeps `detail.code` and its extras, `orgErrorText` turns codes into bilingual text, and `JoinPolicyDraft` / `ScheduleDraft` build PUT bodies. Several org PUTs replace the whole object (join policy, schedule, room, program, academic settings), so always send every field. The server stores naive UTC: send `orgUtc()` and read `orgParseUtc()`. Org screens use `t(ar, en)` from `admin_common.dart` for inline strings instead of `translation.json`. Tests: `flutter test test/org/`.

**Web** — Code that is not web-safe sits behind `kIsWeb` checks or conditional-import stubs (`url_strategy_stub.dart` / `url_strategy_web.dart`, `web_notification_web.dart` using `package:web`). Do not import `dart:io`-only APIs from code that runs on web without such a guard.

## Agent skills

`.agents/skills/` (tracked in `skills-lock.json`) contains Firebase skills (auth, Crashlytics, Remote Config, Firestore, hosting, security rules, …) and `xcode-project-setup`. Consult them for Firebase or Xcode work.
