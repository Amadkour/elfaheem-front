# Apple builds: macOS `.dmg` and iOS TestFlight

Learning Hub Phase 8 (D-1362). Two Codemagic workflows in `codemagic.yaml`:

| Workflow | Makes | Runs without the owner's Apple account? |
|---|---|---|
| `macos-website` | `NextBrain-<version>-<build>-macos.dmg` in `build/nb-upload/`, uploaded to our server | Yes: an **unsigned** `.dmg` |
| `ios-testflight` | an `.ipa` sent to TestFlight (testers only, no App Review) | No: it stops at its first step |
| `ios-store` (older) | an `.ipa` sent to TestFlight **and** App Review | No |

Both need a Mac, so neither runs on this PC (logged as a gap in `docs/learning-hub/PROGRESS.md`). They run on
Codemagic's `mac_mini_m2` (its free minutes), or on the owner's runner on a Mac (D-146). The macOS workflow uses
only tools that ship with macOS (`security`, `codesign`, `notarytool`, `hdiutil`).

This file holds no secret. Every value below goes into Codemagic, never into the repository.

## What the owner provides

1. **Apple Developer Program membership** (paid, yearly) for the account that owns the app.
2. **Team ID**: the 10 characters on developer.apple.com, Membership details.
3. **Bundle ids** registered under Certificates, Identifiers & Profiles, Identifiers:
   - `com.doubley.nextbrain` (iOS app and macOS app). Turn on **App Groups** and **Associated Domains**.
   - `com.doubley.nextbrain.BroadcastUploadExtension` (the iOS screen-share extension). Turn on **App Groups**.
   - The App Group `group.com.doubley.nextbrain`, given to both ids.
4. **The app in App Store Connect**: My Apps, New App, iOS, bundle id `com.doubley.nextbrain`, SKU of the owner's
   choice. It must say the same as `IOS_BUNDLE_ID` on our server.
5. **An App Store Connect API key**: App Store Connect, Users and Access, Integrations, App Store Connect API, Team
   keys, role **App Manager**. Write down the **Issuer ID** and the **Key ID**, and download the `.p8` file. Apple
   lets you download it only once.
6. **For a signed macOS `.dmg` only**: a **Developer ID Application** certificate (Certificates, +, Developer ID
   Application; the Account Holder must create it). Export it from Keychain Access as a `.p12` with a password.

## Where each one goes in Codemagic

| What | Where in Codemagic | Name |
|---|---|---|
| API key (iOS) | Team settings, Team integrations, Developer Portal, Manage keys | key name **`app_store`** (Issuer ID, Key ID, `.p8`) |
| iOS signing | nothing to upload: `ios_signing` fetches or creates the distribution certificate and profiles through that key | — |
| TestFlight switch | App settings, Environment variables, group **`app_store`** | `NB_TESTFLIGHT_ENABLED` = `1` |
| Developer ID certificate | group **`macos_signing`** (mark it Secure) | `MACOS_DEVELOPER_ID_P12_BASE64` = the `.p12` in base64 (`base64 -i id.p12`) |
| its password | group `macos_signing`, Secure | `MACOS_DEVELOPER_ID_P12_PASSWORD` |
| notarisation key | group `macos_signing`, Secure | `APP_STORE_CONNECT_PRIVATE_KEY` = the `.p8` contents |
| | group `macos_signing` | `APP_STORE_CONNECT_KEY_IDENTIFIER` = Key ID |
| | group `macos_signing` | `APP_STORE_CONNECT_ISSUER_ID` = Issuer ID |

Create the group `macos_signing` before the first macOS build, **even empty**: the workflow names it. With the group
empty, the build makes an unsigned `.dmg`. With the certificate alone, the `.dmg` is signed but not notarised.
With all five values, it is signed, notarised and stapled, and Gatekeeper opens it with no warning.

The iOS extension needs its own App Store profile. If `xcode-project use-profiles` reports a missing profile for
`com.doubley.nextbrain.BroadcastUploadExtension`, add a second `ios_signing` entry for it, or create both profiles in
the portal and upload them under Team settings, Code signing identities.

## Turning the workflows on

- **iOS TestFlight**: add the `app_store` key and `NB_TESTFLIGHT_ENABLED=1`, then start `ios-testflight` from
  Codemagic, or from App versions once the server offers it. Apple's first processing of a build takes 10 to 30
  minutes. Internal testers see it in TestFlight at once; external testers need Apple's beta review once.
- **macOS**: the workflow uploads the `.dmg` through `upload_artifacts.sh`. Our server accepts a `.dmg` for a release
  only once Phase 9 lists the macOS platform. Until then, run it from Codemagic directly and take the `.dmg` from the
  build's artifacts.

## Opening an unsigned `.dmg` (Gatekeeper)

For the person installing, while the `.dmg` is not notarised:

1. Open the `.dmg` and drag **NextBrain** onto **Applications**.
2. In Applications, **Control-click** NextBrain, choose **Open**, then **Open** again in the dialog. macOS remembers
   this choice.
3. On macOS 15 and later that dialog has no Open button: double-click once and close the warning, then open
   **System Settings, Privacy & Security**, scroll to the "NextBrain was blocked" line, choose **Open Anyway** and
   confirm with the password.
4. If macOS says the app "is damaged", the download was quarantined. Run
   `xattr -dr com.apple.quarantine /Applications/NextBrain.app` in Terminal once.

A notarised `.dmg` needs none of these steps.

## Not done here

- No build was run: this PC has no Mac. The first real run is the owner's, after the steps above.
- The macOS app keeps the App Sandbox (`macos/Runner/Release.entitlements`) with network access only. A feature that
  needs more (camera for live classes, files) needs its entitlement added before it works in the signed build.
