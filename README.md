# Alfaheem app (Flutter)

The Flutter client of the Alfaheem education platform for **Android, iOS and the web** — universities (credit-hour
and traditional systems), training centers and an open course marketplace in one app, Arabic (RTL) by default and
English. Alfaheem by DoubleY, application id `com.doubley.alfaheem` on every platform (D-145); the Dart package
stays `flutter_education_app` (internal, never shown; renaming it would rewrite every import). The backend is the sibling repository [`../back`](../back).

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
`https://alfheemacademy.com/api`). Use the demo accounts only against a local backend.

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
flutter analyze --no-fatal-infos --fatal-warnings   # the CI gate (exit 0); plain `flutter analyze` exits 1 on info lints, which are allowed
flutter test test/org/ test/export/ test/ui/ test/auth/ test/access/ test/admin/ test/perf/ test/contract/   # the CI suites
flutter test test/ui/vod_player_layout_test.dart --plain-name "name"   # one test
EXPORT_SAMPLES=<dir> flutter test test/org/org_export_test.dart        # writes sample .xlsx/.docx/.pdf to open in Office
```

New widgets go
through `test/ui/layout_harness.dart` (`expectNoLayoutErrors`: 320×640 and 1400×900, Arabic and English, text scale
1.3). `test/contract/` checks that every API path the app calls exists in the backend's route snapshot
(`test/contract/api_paths.json`, regenerated from `../back` with
`.venv312/Scripts/python scripts/contract/export_api_paths.py --front ../nextbrain-front` (or `py -3.12`; plain `python` is not on PATH) after a server route is added).

## Build and release

```bash
scripts/build_release.sh apk | appbundle | ipa | web      # release builds: obfuscated, symbols in build/debug-info/
scripts/build_firebase_hosting.sh && firebase deploy --only hosting   # Firebase Hosting copy: landing at /, app at /app/
scripts/server/build_web.sh                               # on the server: the live web deploy (build next to live, swap, smoke test, rollback)
dart run flutter_launcher_icons                           # regenerate app icons
dart run flutter_native_splash:create                     # regenerate splash screens
```

Release signing reads the keystore from the environment / `android/key.properties` (never committed). Do not run
`dart format` on the existing code (it rewrites whole files; see CLAUDE.md).

### Direct app downloads (no stores, D-137)

The apps are downloaded from our own site. `https://alfheemacademy.com/releases/releases.json` (the releases manifest)
says what exists per platform; the web banner, the "Get the app" row and the apps' update prompt read only that file,
so publishing never needs a web build.

```bash
# Android (3 signed APKs: arm64-v8a, armeabi-v7a, universal) and/or the Linux app (built on the server):
D:/platform/nextbrain/back/.venv312/Scripts/python.exe scripts/release/publish_release.py --android --linux \
    --notes-en "What changed" --notes-ar "ما الجديد"
#   --dry-run       build and check only          --no-build   upload what build/releases/<version>-<build>/ holds
#   --min-build N   installed builds below N must update ("Please update to continue")
```

1. Raise `version:` in `pubspec.yaml` (`1.0.1+2`: the `+N` build is Android's versionCode and what the update check
   compares; it must grow every release).
2. Run the command. It builds, refuses a debug-signed APK or a wrong versionCode, uploads under temporary names,
   and lets the server write the manifest from the files it serves (size + SHA-256; the previous manifest is kept as
   `releases.json.bak-*`). iPhone / iPad, Windows and Mac offer the installable web app (`"pwa": true`).
3. Check: `curl -s https://alfheemacademy.com/releases/releases.json`.

**The Android release key** is `C:\Users\ahmed\.alfaheem-keys\` (`alfaheem-release.jks` + `key.properties`),
outside every repo (`NEXTBRAIN_KEY_PROPERTIES` points elsewhere). Back it up offline: without it no installed copy can
ever be updated. Its certificate SHA-256 is in `web/.well-known/assetlinks.json` (Android App Links).

Hand-editing is possible (`scripts/release/release_manifest.py set …` on the server, `--help`); the schema is in
`lib/core/get_app/releases_manifest.dart`. Counts of banner views, downloads and install guides:
`docs/DEPLOY.md` in the backend, "App downloads".

## Troubleshooting

| Symptom | Fix |
|---|---|
| `flutter pub get` downgrades packages | check that `pubspec.lock` only gains the package you added; never add the `excel` package (CLAUDE.md) |
| Android emulator cannot reach `localhost` | use `10.0.2.2` (the host's loopback), or `adb reverse` on a USB device |
| Login works but org pages say the feature needs a server update | the backend is older than the app: update `../back` and rerun its migrations |
| Web build cannot load `dart:io` code | that code must sit behind `kIsWeb` or a conditional import (CLAUDE.md, "Web") |
