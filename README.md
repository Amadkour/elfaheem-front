# NextBrain app (Flutter)

The Flutter client of the NextBrain education platform for **Android, iOS and the web** — universities (credit-hour
and traditional systems), training centers and an open course marketplace in one app, Arabic (RTL) by default and
English. Package `flutter_education_app`; the backend is the sibling repository [`../back`](../back).

- Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · decisions: [docs/DECISIONS.md](docs/DECISIONS.md)
- Developer documents (guides and slides for the app, the core, the Exam Engine, RAG and operations):
  [documents/](documents/)
- Backend setup, demo accounts and services: [../back/README.md](../back/README.md)
- Working notes for code assistants (architecture, conventions, test gotchas): [CLAUDE.md](CLAUDE.md)

## Prerequisites

| Tool | Version |
|---|---|
| Flutter (stable channel) | Dart SDK `>=3.10` (see `pubspec.yaml`); `flutter doctor` must be clean for your target |
| Android Studio / Android SDK | for Android builds and the emulator |
| Xcode + CocoaPods (macOS) | for iOS builds |
| Chrome | for `flutter run -d chrome` |
| Docker | only to run the backend locally (see below) |

## Setup and run

```bash
flutter pub get
flutter run                     # a connected device / emulator
flutter run -d chrome           # web
```

By default the app talks to production (`AppConfig.baseUrl` in `lib/config/app_config.dart`,
`https://nextbrain.site/api`). Use the demo accounts only against a local backend.

### Against a local backend with demo data

1. Start the backend stack and the demo data in `../back` (one command, details in its README):

   ```bash
   cd ../back && ./scripts/dev/setup.sh          # Windows: .\scripts\dev\setup.ps1
   ```

   It prints the URLs and the demo password (`SEED_DEMO_PASSWORD` in `../back/.env`).
2. Point the app at the local gateway, which routes the core, the Exam Engine and RAG exactly like production:

   | Target | Base URL |
   |---|---|
   | web / desktop / iOS simulator | `http://localhost:18080/api` |
   | Android emulator | `http://10.0.2.2:18080/api` |
   | Android phone over USB | `adb reverse tcp:18080 tcp:18080`, then `http://localhost:18080/api` |

   Pass it at build time, for example `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:18080/api`.
   Without `API_BASE_URL` every build, release included, talks to production. The local gateway is plain HTTP, so the certificate pinning of `ApiClient` (HTTPS only) is not involved.
3. Sign in with a demo account, for example `uni.admin@example.test` (university admin), `uni.cs.student1@example.test`
   (credit-hour student), `center.admin@example.test` (training center), `market.teacher@example.test`
   (marketplace teacher) or `superadmin@example.test`. The full list per mode is in
   [../back/README.md](../back/README.md#demo-accounts).

## Tests and checks

```bash
flutter analyze                                   # gate: no " warning - " / " error - " lines (info lints are allowed)
flutter test test/org/ test/export/ test/ui/ test/auth/ test/contract/
flutter test test/ui/vod_player_layout_test.dart --plain-name "name"   # one test
EXPORT_SAMPLES=<dir> flutter test test/org/org_export_test.dart        # writes sample .xlsx/.docx/.pdf to open in Office
```

`test/widget_test.dart` is the stock counter template and fails; it is not part of the suite. New widgets go
through `test/ui/layout_harness.dart` (`expectNoLayoutErrors`: 320×640 and 1400×900, Arabic and English, text scale
1.3). `test/contract/` checks that every API path the app calls exists in the backend's route snapshot
(`test/contract/api_paths.json`, regenerated from `../back` with
`python scripts/contract/export_api_paths.py --front ../nextbrain-front` after a server route is added).

## Build and release

```bash
scripts/build_release.sh apk | appbundle | ipa | web      # release builds: obfuscated, symbols in build/debug-info/
flutter build web && firebase deploy --only hosting       # web, deployed from build/web
dart run flutter_launcher_icons                           # regenerate app icons
dart run flutter_native_splash:create                     # regenerate splash screens
```

Release signing reads the keystore from the environment / `android/key.properties` (never committed). Do not run
`dart format` on the existing code (it rewrites whole files; see CLAUDE.md).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `flutter pub get` downgrades packages | check that `pubspec.lock` only gains the package you added; never add the `excel` package (CLAUDE.md) |
| Android emulator cannot reach `localhost` | use `10.0.2.2` (the host's loopback), or `adb reverse` on a USB device |
| Login works but org pages say the feature needs a server update | the backend is older than the app: update `../back` and rerun its migrations |
| Web build cannot load `dart:io` code | that code must sit behind `kIsWeb` or a conditional import (CLAUDE.md, "Web") |
