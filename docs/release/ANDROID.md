# Android release build and signing (Learning Hub Phase 8, N1)

The direct-download APKs and the Play App Bundle are built on the owner's PC with the release key that lives OUTSIDE
the repo. Nothing secret is in this file or anywhere in the repo.

## The release key

- `~/.nextbrain-keys/nextbrain-release.jks` + `~/.nextbrain-keys/key.properties` (`storeFile`, `storePassword`,
  `keyAlias`, `keyPassword`). Back this folder up offline: losing it means no installed APK can ever be updated.
- Never copy either file into the repo, never print a password, never create or replace the keystore (D-1360).
- Certificate (public, checked 2026-11-21 with `keytool -list -v -storepass:env …`):
  - alias `nextbrain`, `CN=NextBrain, O=NextBrain, C=EG`, RSA 4096, SHA384withRSA, valid 2026-10-31 → 2126-10-07
  - **SHA-256 `74:2C:D5:76:FF:D6:47:DC:57:A1:2D:6A:5F:EC:65:9F:43:2E:4F:08:97:EF:7B:C1:36:31:25:C5:04:11:48:A2`**
  - SHA-1 `69:6E:79:85:BC:77:41:57:E4:3B:43:07:94:DB:2B:26:91:31:C1:C5`
- The published `NextBrain-1.0.0-1-arm64-v8a.apk` (releases.json, 2026-11-01) is signed by the same certificate
  (`apksigner verify --print-certs`: `742cd576…041148a2`), so a new build upgrades it in place.

Checking the key without a password on the command line:

```bash
P=~/.nextbrain-keys/key.properties
prop() { grep -E "^[[:space:]]*$1[[:space:]]*=" "$P" | head -n1 | cut -d= -f2- | tr -d '\r'; }
export NBSP="$(prop storePassword)"
keytool -list -v -keystore "$(prop storeFile)" -storepass:env NBSP -alias "$(prop keyAlias)" | grep -E 'SHA256|Owner'
unset NBSP
```

(`keytool` / `jarsigner` come with Android Studio: `C:\Program Files\Android\Android Studio\jbr\bin`.)

## Building

`scripts/build_release.sh` signs from `android/key.properties`, else the `ANDROID_KEYSTORE_*` / `ANDROID_KEY_*`
environment, else it reads `~/.nextbrain-keys/key.properties` (or `NEXTBRAIN_KEY_PROPERTIES`) into that environment.
With none of them it refuses (S13), and so does gradle.

```bash
scripts/build_release.sh apk         # three APKs, same versionCode (D-137) → build/releases/<name>-<build>/
scripts/build_release.sh appbundle   # build/app/outputs/bundle/release/app-release.aab
py -3 scripts/release/publish_release.py --aab --no-build   # copy + check the AAB (below)
```

- `apk`: `NextBrain-<name>-<build>-arm64-v8a.apk`, `-armeabi-v7a.apk`, `-universal.apk`, each built with
  `--target-platform` and `-P disable-abi-filtering=true` (the plugins' native libraries follow the target,
  `android/app/build.gradle.kts`). Not `--split-per-abi`: its versionCode offsets would make a later universal APK a
  downgrade. These are the same files `publish_release.py --android` builds and uploads.
- Every build is obfuscated; symbols are in `build/debug-info/<name>+<build>/` (`android-<arch>/` per APK). Keep them
  with the release: `flutter symbolize -i trace.txt -d build/debug-info/<version>/android-arm64-v8a/app.android-arm64.symbols`.

## `publish_release.py --aab`

Builds the AAB (unless `--no-build`), copies it to `build/releases/<name>-<build>/NextBrain-<name>-<build>.aab`,
writes `….aab.sha256`, checks `jarsigner -verify` and the signer's SHA-256 (`keytool -printcert -jarfile`; with
`--android` in the same run it must equal the APKs'), and lists it in `manifest-draft.json` there as kind `aab` with
`"published": false`. It never uploads the AAB or touches releases.json: the Play upload stays on Codemagic
(`android-store` workflow). `--aab` alone opens no SSH connection.

## Verifying a build

```bash
BT="$LOCALAPPDATA/Android/sdk/build-tools/<latest>"
"$BT/apksigner.bat" verify --print-certs build/releases/<v>/NextBrain-<v>-arm64-v8a.apk | grep SHA-256
jarsigner -verify build/releases/<v>/NextBrain-<v>.aab       # "jar verified."
keytool -printcert -jarfile build/releases/<v>/NextBrain-<v>.aab | grep SHA256
```

All three must show the SHA-256 above.

## Results (2026-11-21, 1.0.0+1)

Built on this PC with `scripts/build_release.sh apk` + `appbundle` (about 50 min per build under load), all signed by
`742cd576…041148a2` (`apksigner verify --print-certs`; `jarsigner -verify` → "jar verified."):

| file | bytes | SHA-256 |
|---|---|---|
| `NextBrain-1.0.0-1-arm64-v8a.apk` | 60150059 | `f0aa63a340f953d358b04bd79a2be141a8f6cc99a8318a141c0e2162ecc45cc6` |
| `NextBrain-1.0.0-1-armeabi-v7a.apk` | 58632071 | `1511ec78e186069460a34f213285b52c5767fb8b29a0a2a059e1184ea8399dd4` |
| `NextBrain-1.0.0-1-universal.apk` | 133460513 | `75bd23ed4d14601fbec32b4a334db16ccd6cf69ab725d8d1174253a8267d2a5b` |
| `NextBrain-1.0.0-1.aab` | 217276274 | `5bfbd51cca7e6487c76dce15b7fc97f80659e31a348d15d0abb40ab138cae492` |

The new APKs are about 11 MB larger than the published 1.0.0+1 ones (Phase 1–7 code and assets). pubspec is still
`1.0.0+1`: bump the build number before publishing, or installed apps see no update (the version check compares
build numbers; `adb install -r` upgrades in place either way).

### Install check (emulator Pixel 3a API 36, arm64 translation)

- **The published 1.0.0+1 APKs are NOT the same app.** They were built on 2026-11-01, before D-145, with the
  application id `com.example.flutter_education_app` (`aapt2 dump badging`); every build since is
  `com.doubley.nextbrain`. Same key, but a different package: the new APK installs BESIDE the old one, it cannot
  upgrade it, and the old app's update check cannot replace itself. Installed `pub-arm64.apk`, then the new arm64 APK
  with `pm install -r`: both are on the device, the new one opens to its onboarding screen with no crash (logcat crash
  buffer empty).
- The Phase 7 database (`nb_local_v1.db`, sqflite) opens lazily on the first offline game play, which needs a signed-in
  student and a published game: NOT done here (no production test account on this PC; the emulator's system services
  kept dying under the build load). Owed: one offline play on a phone with a test student account.

### Owner actions

1. Decide how users of the old `com.example.flutter_education_app` APK move over: publish the new APKs under the
   same file names (they install as a new app), and tell them to uninstall the old one; its update dialog can only
   point to the download page.
2. Bump `version:` in pubspec (e.g. `1.0.1+2`) before the Phase 9 publish.
3. Keep `~/.nextbrain-keys/` backed up offline, and the symbols in `build/debug-info/1.0.0+1/`.
