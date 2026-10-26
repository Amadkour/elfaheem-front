# Security scan — Flutter app (Phase 10)

Date: 2026-10-26 · branch `feature/platform-rbac-exams-rag` · report only: `pubspec.yaml`, `pubspec.lock`, the
manifests and `Info.plist` were not changed. The backend report is `../back/docs/SECURITY_SCAN.md`.

## Tools and commands

| Tool | Version | Command |
|---|---|---|
| Flutter / Dart | Flutter 3.47.7 stable (2026-10-08) · Dart 3.13.5 | `flutter pub get --enforce-lockfile` (the lockfile is unchanged), `flutter pub outdated --show-all`, `flutter pub outdated --json --show-all` (fields `isCurrentAffectedByAdvisory`, `isCurrentRetracted`, `isDiscontinued`; pub takes these from the GitHub Advisory Database for the pub ecosystem) |
| Secret scan | own script (no gitleaks on this machine) | `git log -p --all` over every added line plus every tracked file. Rules: private keys, AWS, MinIO, JWT/HMAC secrets, Moyasar `sk_/pk_`, Paymob `egy_sk_…` / base64-JWT `ZXlK…` keys, Firebase service-account JSON, Google API keys, passwords in URLs, GitHub/Slack tokens, generic `api_key=`. It prints only file, commit, rule and a fingerprint, never a value. |
| Manual review | — | `android/app/src/{main,debug,profile}/AndroidManifest.xml`, `android/app/build.gradle.kts`, `ios/Runner/Info.plist`, `.gitignore` files, the `flutter_webrtc` fork in the pub cache (`resolved-ref 163469226e…`) |

## Dependencies

- **Advisories:** none. All 250 packages (direct, dev and transitive) report `isCurrentAffectedByAdvisory = false`. None is retracted or discontinued, and `pub get` printed no advisory.
- **Outdated:** 39 upgradable packages are held back by `pubspec.lock`, all patch or minor bumps:
  - Firebase: `firebase_core` 5.0.0→5.1.0, `firebase_auth` / `_messaging` / `_crashlytics` / `_remote_config` x.0.0→x.0.1, `_flutterfire_internals`.
  - Others: `flutter_local_notifications` 22.3.3, `file_picker` 13.2.0, `moyasar` 3.0.6, `cached_network_image` 4.0.5, `chewie` 1.17.4, `geolocator` 14.1.2, `web` 1.1.2, `webview_flutter_wkwebview` 3.27.2, `android_file_picker` 2.1.2, …
  - One package is held back by a constraint in `pubspec.yaml`: `screen_protector` (see below).
  - None of these bumps is a known security fix. Suggestion: a routine `flutter pub upgrade` in its own commit, checked as CLAUDE.md asks (only the expected packages move, nothing is downgraded).

| Pinned / overridden | Finding | Risk | Recommendation |
|---|---|---|---|
| `flutter_webrtc` → fork `github.com/Amadkour/flutter-webrtc`, `ref: main`, locked at `163469226e1d` (2026-08-26) | The fork is based on upstream **1.6.0** and bundles **libwebrtc M144** (`io.github.webrtc-sdk:android:144.7559.09`, pod `WebRTC-SDK 144.7559.09`). Upstream `1.6.2+hotfix.4` ships **M150** (`150.7871.01`). Chrome 146 (March 2026) fixed three High-severity WebRTC bugs (CVE-2026-4444 stack overflow, CVE-2026-4445 / -4446 use-after-free). libwebrtc is Chrome's WebRTC code, so M144 is very likely affected. No advisory names flutter_webrtc itself, so this is an inference from the Chromium fixes and wasn't proven against this build. Also, `ref: main` is a moving branch: the lock pins the SHA, but `flutter pub upgrade` would pull whatever is on the fork's `main`. | **Medium.** Remote peers in a live session send media and SDP to this code. LiveKit's SFU sits in between, which limits who can reach it. | Rebase the fork's own changes (`ElFaheemFrameCapturer`, `ElFaheemBridge`, `GetUserMediaImpl`, screen-capture permission handling) onto upstream `1.6.2+hotfix.4`, or at least bump `webrtc-sdk` / `WebRTC-SDK` to `150.7871.01`. Pin `ref:` to a tag or commit SHA, not `main`. Do a device test pass of live sessions and recording first. |
| `screen_protector: 1.5.1` (pinned; 1.5.3 resolvable) | No CVE or advisory was found (pub advisory data, plus a web search). The pin is for a build reason: 1.5.2+ only compiles its Kotlin code on AGP < 9. Note that screen protection is a deterrent on the client and doesn't protect content against a rooted or jailbroken device. | Low | Keep the pin. Look at 1.5.3+ again when the AGP/Kotlin issue is fixed upstream. |
| `flutter_lints`, `flutter_test` overrides | SDK or dev only. | None | — |

## Secret scan

| # | Where | Status |
|---|---|---|
| A1 | `lib/features/student/enrollment/enrollment_provider.dart`, added in **0cc7e27** (2026-09-16, "teacher profile"), removed in **0864033** (2026-09-25, "reals"); 4 occurrences (`apiKey:` / `"api_key":`, 272 characters, Paymob's base64-JWT API-key format) | **Critical: a real Paymob merchant API key in git history.** The repo (`Amadkour/nextbrain-front`) is private, but the commit is on `production`, `organizations`, `inverse_otp` and their `origin/*` copies. Any app or web build made from those commits had the key compiled into the client, and anyone who had that build can pull it out. A Paymob API key lets you get merchant auth tokens, which open the merchant API (orders, payment keys, transaction inquiry, refund/void). **The owner must rotate it in the Paymob dashboard** (Settings → Account info → API key → regenerate) and update the backend env value that holds the same key (`PAYMOB_SDK_API_KEY` / `PAYMOB_SECRET_KEY` in `config.py`). Then check the Paymob transaction log for 2026-09-16 onward. The current code has no Paymob key (`git grep` on HEAD finds nothing); payments go through the backend. |
| A2 | `lib/firebase_options.dart` (3 keys), `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`, `macos/Runner/GoogleService-Info.plist`, `web/firebase-messaging-sw.js` (and the old copies under `my-front-code/` in f4dd54a) | Expected. **Firebase client API keys are public identifiers, not secrets.** Security depends on these keys being restricted. Suggestion: in Google Cloud Console → Credentials, restrict each key to the Firebase APIs it uses and to its app (Android package + SHA-1, iOS bundle id, HTTP referrer `nextbrain.site/*` for web). Also turn on App Check for Remote Config / FCM. |
| A3 | `.agents/skills/firebase-auth-basics/references/ios_setup.md:60,71` | False positive: sample code in a vendored skill document. |

No private keys, service-account JSON, keystores, `key.properties`, AWS/MinIO keys, Moyasar secret keys or JWT
secrets are tracked or anywhere in history.

**`.gitignore` coverage.** The app's `.gitignore` covers `android/key.properties`, `*.jks`, `*.keystore` (also
`android/.gitignore`). It does **not** cover:
- `.env*`, `*firebase-adminsdk*.json`, `*service-account*.json`;
- `*.p12`, `*.p8`, `*.pem`, `*.mobileprovision`.

There is also no `macos/.gitignore`, so `macos/Flutter/ephemeral/flutter_native_integration.env` (generated, holds
local paths only) is tracked. See "Needs change elsewhere" below.

## Platform configuration

| # | Sev | File:line | Finding | Recommendation |
|---|---|---|---|---|
| P1 | Medium | `android/app/src/main/AndroidManifest.xml:38` `android:usesCleartextTraffic="true"` | Plain HTTP is allowed to every host. The only cleartext use in `lib/` is the loopback server for offline playback (`lib/core/offline/offline_video_service.dart:436`, bound to `127.0.0.1`, token protected). | Use a network security config with cleartext only for `127.0.0.1` / `localhost` (diff below). First check that no server media URL is `http://` (`MINIO_SECURE` / `MINIO_PUBLIC_URL` on the server). |
| P2 | Medium | `ios/Runner/Info.plist:31-35` `NSAllowsArbitraryLoads = true` | ATS is switched off for every host. | Replace it with `NSAllowsLocalNetworking = true`, which covers the loopback server, after the same media-URL check. |
| P3 | OK | manifest `android:allowBackup="false"` | No app-data backup. | — |
| P4 | OK | manifest | No `android:debuggable` attribute, so release builds aren't debuggable. The release build fails in CI without a keystore (`build.gradle.kts`). | — |
| P5 | OK / info | manifest `:48-117` | Exported components: only `MainActivity`, which needs it for the launcher plus App Links (`https://nextbrain.site/c/…` and `/live/…`, `autoVerify`). The notification receivers, `ScreenCaptureService` and `FlutterRTCMediaProjectionService` are `exported="false"`. | Keep `assetlinks.json` on `nextbrain.site` in sync with the release SHA-256. |
| P6 | Info | `android/app/build.gradle.kts` `isMinifyEnabled = false` | R8 is off (recorded as decision D-026). Dart code is obfuscated with `--obfuscate --split-debug-info`, but Java/Kotlin is not shrunk or obfuscated. | Already a planned item: turn R8 on after a device test pass. |
| P7 | Info | manifest permissions | Broad set: fine and coarse location, Bluetooth scan/advertise, nearby Wi-Fi, `SCHEDULE_EXACT_ALARM` **and** `USE_EXACT_ALARM`, ignore battery optimisations. | Play policy limits `USE_EXACT_ALARM` to alarm and calendar apps. Keep only `SCHEDULE_EXACT_ALARM` unless reminders need exact timing. |

Proposed P1 change (not applied; those files are not owned by this task):

```diff
<!-- android/app/src/main/AndroidManifest.xml -->
-        android:usesCleartextTraffic="true"
+        android:networkSecurityConfig="@xml/network_security_config"
```
```xml
<!-- android/app/src/main/res/xml/network_security_config.xml (new) -->
<network-security-config>
    <base-config cleartextTrafficPermitted="false" />
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">127.0.0.1</domain>
        <domain includeSubdomains="false">localhost</domain>
    </domain-config>
</network-security-config>
```
P2: in `ios/Runner/Info.plist`, replace `<key>NSAllowsArbitraryLoads</key><true/>` with
`<key>NSAllowsLocalNetworking</key><true/>`.

## Residual risk

- **A1:** the Paymob key from 0cc7e27 stays valid until it is rotated. It must be rotated before anything else on
  this list. **The owner has to do it.**
- **WebRTC:** the native WebRTC stack lags upstream by about 6 milestones until the fork is rebased.
- **Cleartext and ATS:** both stay allowed for every host until P1 and P2 land. Certificate pinning in `ApiClient`
  protects the API host on mobile, but not media hosts or the web build.
- **Firebase client keys:** they are public by design. How much they expose depends on the GCP key restrictions and
  App Check, which this scan can't see.
- **Coverage of the dependency scan:** pub's advisory data only covers packages that have GitHub advisories. Native
  SDKs pulled in by plugins (WebRTC, the Paymob/Moyasar native SDKs, ML Kit inside `mobile_scanner`) are not covered.
