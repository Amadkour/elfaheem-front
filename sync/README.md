# sync/ — Alfaheem on top of NextBrain

This folder exists only in Alfaheem (never in NextBrain), so it never conflicts. Decisions: `docs/DECISIONS_ALFAHEEM.md`.

| File | What |
|---|---|
| `identity.env` | Every Alfaheem value: names, application id, domain, certificate pins, App Links fingerprints, splash colours, server folder. |
| `keep_paths.txt` | Files where Alfaheem's copy always wins (Firebase files, the original images, the generated icons and splash images). |
| `brand_assets.txt` | NextBrain brand images Alfaheem never drew; each is generated from the Alfaheem logo. |
| `apply_identity.py` | Writes `identity.env` over a freshly merged tree. Idempotent (`--check` shows what it would change). |
| `gen_brand_assets.py` | Generates the brand images (splash art, `assets/icon/*`, `logo_mark.png`, web PWA splash, landing icons, og image, the offline page's inline logo). |
| `post_merge.sh` | `apply_identity` → `gen_brand_assets` → `flutter pub get` → `flutter_launcher_icons` → `flutter_native_splash` → `apply_identity` → `check_identity`. |
| `check_identity.py` | The gate: NextBrain's name, domain, ids, Firebase project, pins and images; allow-list in `check_allow.txt`. |
| `sync.sh` | The whole sync; stops with the merge uncommitted for review. |

## A sync

```bash
git checkout production && git checkout -b sync/nextbrain-<date>
sync/sync.sh                      # or sync/sync.sh <nextbrain-commit>
# review: git diff --cached --stat ; the gate printed "0 problem(s)"
flutter analyze --no-fatal-infos --fatal-warnings
flutter test test/org/ test/export/ test/ui/ test/auth/ test/access/ test/admin/ test/perf/ test/contract/
MSYS_NO_PATHCONV=1 flutter build web --release --base-href /app/
(cd landing && npm ci && npm run build)
git add -A && git commit          # then review, merge into production, push (by hand)
```

The remote is fetch-only: `git remote add nextbrain D:/platform/nextbrain/nextbrain-front` then
`git remote set-url --push nextbrain DISABLED`. Never add an Alfaheem remote to a NextBrain checkout.

When the gate fails:
- a NextBrain name or domain in a new file: let `apply_identity.py` handle it (extend its rules), or, when it must
  stay (an internal name, history), add a line to `check_allow.txt` with the reason;
- an image in neither list: a new NextBrain brand image. Generate it from the Alfaheem logo in
  `gen_brand_assets.py` and add it to `brand_assets.txt` (a non-brand image goes in `keep_paths.txt` only if
  Alfaheem has its own copy; otherwise list it in `brand_assets.txt` with a generator).

## Firebase (A-004): files the Firebase step must rewrite for the new project

- `android/app/google-services.json` (package `com.doubley.alfaheem`; the kept file is still registered for
  `com.example.flutter_education_app`, so Android Firebase does not initialise until it is replaced)
- `ios/Runner/GoogleService-Info.plist`, `macos/Runner/GoogleService-Info.plist` (bundle `com.doubley.alfaheem`)
- `lib/firebase_options.dart` (android, ios, macos, web; windows optional)
- `ios/Runner/Info.plist`: the Google sign-in URL scheme (`CFBundleURLSchemes`, still NextBrain's `nextbrain-2y` iOS app)
- `lib/features/messaging/notification/notification_service.dart`: the web-push VAPID key (still NextBrain's)
- `web/firebase-messaging-sw.js`, `firebase.json` (written from `lib/firebase_options.dart` by `apply_identity.py`:
  re-run it after `flutterfire configure`)
- `.firebaserc` (default project)
- the server's FCM service account (backend `.env.production`)
