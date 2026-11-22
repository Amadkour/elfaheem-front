# Building every release (one page)

`scripts/release/build_all.py` runs every platform build this machine can make and marks the rest `SKIPPED` with the
reason. It builds and checks; it never uploads (publishing: `publish_release.py`, `release_manifest.py`,
`APP_RELEASES.md`).

## Prerequisites

| Target | Machine | Needs |
|---|---|---|
| `android-apk`, `android-aab` | any | Flutter 3.47 stable, the Android SDK (build-tools: `apksigner`, `aapt2`), a JDK (`jarsigner`), the release key (below) |
| `windows` | Windows | Visual Studio with "Desktop development with C++"; Inno Setup 6 (`winget install JRSoftware.InnoSetup`) for the installer |
| `linux` | Linux (the server, WSL) | the Flutter Linux toolchain, `dpkg-deb`, `appimagetool` |
| `macos`, `ios` | macOS | Xcode; the Apple account items in `APPLE.md` for signed builds |
| `web` | any | Flutter |

On this Windows PC: Android, Windows and web run; Linux, macOS and iOS are `SKIPPED` (Linux builds on the server
through `publish_release.py --linux` or the `linux-website` workflow; macOS / iOS on Codemagic).

## Commands

```bash
.venv312/Scripts/python scripts/release/build_all.py --dry-run          # what would run here, what is skipped and why
.venv312/Scripts/python scripts/release/build_all.py                    # everything this machine can build
.venv312/Scripts/python scripts/release/build_all.py --only android-apk,android-aab
.venv312/Scripts/python scripts/release/build_all.py --skip web
```

(`py -3.12` works in place of the venv's python.) The version is pubspec's `version: X.Y.Z+BUILD`; bump it before a
release. The exit code is 1 when a target that could run failed; a `SKIPPED` target never fails the run.

## Outputs

`build/releases/<version>-<build>/` (git-ignored):

| Kind | File | Offered for download |
|---|---|---|
| `apk` | `NextBrain-<v>-<b>-arm64-v8a.apk`, `-armeabi-v7a.apk`, `-universal.apk` | yes |
| `aab` | `NextBrain-<v>-<b>.aab` | **never** (Play upload; the manifest records it `"listed": false`) |
| `exe` | `NextBrain-<v>-windows-x64-setup.exe` (Inno Setup, unsigned, per-user) | yes, Windows' first choice |
| `zip` | `NextBrain-<v>-<b>-windows-x64.zip` | yes |
| `AppImage`, `deb`, `tar.gz` | `NextBrain-<v>-<b>-x64.*` | yes (AppImage first) |
| `dmg` | `NextBrain-<v>-<b>-macos.dmg` | yes |

Also `build_all.json` (each target: `ok` / `failed` / `SKIPPED` + reason, files, sizes, SHA-256). The web build lands in
`build/web` and is deployed by `scripts/server/build_web.sh`. Debug symbols go to `build/debug-info/<v>+<b>/<target>/`:
keep them with the release, they are the only way to read a crash (`flutter symbolize`).

The manifest kinds per platform are `KINDS` in `release_manifest.py`; the app's installer order is `kInstallerKinds`
in `lib/core/get_app/releases_manifest.dart` (the update offer opens the setup `.exe` on Windows, the `.dmg` on macOS,
the kind the app was installed from on Linux, the APK for the phone's CPU on Android).

## Checksums

`SHA256SUMS` in the output folder, in `sha256sum` format:

```bash
cd build/releases/<v>-<b> && sha256sum -c SHA256SUMS          # Linux / Git Bash
Get-FileHash .\NextBrain-<v>-windows-x64-setup.exe -Algorithm SHA256   # PowerShell
shasum -a 256 NextBrain-<v>-<b>-macos.dmg                      # macOS
```

`release_manifest.py set --expect-sha` compares the uploaded file with these values on the server; the Downloads page
shows the published SHA-256 next to each file.

## The signing key

The Android release keystore lives **outside the repository**, in the release owner's home folder:
`~/.nextbrain-keys/nextbrain-release.jks` with `~/.nextbrain-keys/key.properties` next to it (another path:
`NEXTBRAIN_KEY_PROPERTIES`). The scripts pass its values to Gradle through the environment
(`ANDROID_KEYSTORE_PATH`, …, read by `android/app/build.gradle.kts`) and never print them. Never copy the keystore or
its properties into the repository, never paste a password into a command line, and never create a new keystore: an
APK signed with another key cannot update the installed app. Keep an offline backup of the folder. Without the key the
Android targets are `SKIPPED` (a release is never signed with the debug key). Apple and Windows signing: `APPLE.md`,
`WINDOWS.md`.
