# Native code

Moved verbatim from the root `CLAUDE.md` (which keeps a short summary and the rules a session must never miss). Keep this file in step with the code.

**Native code** — Live sessions use LiveKit (`features/live/room/`). Screen recording and screen sharing use platform channels (`com.doubley.nextbrain/native_recorder`, `/radios`, …: every channel is `com.doubley.nextbrain/<name>`, identical on the Dart and native side, D-145). The native side is `android/app/src/main/kotlin/com/doubley/nextbrain/ScreenCaptureService.kt` and `MainActivity.kt`, and on iOS `ios/Runner/AppDelegate.swift`, `LocalDebugRecorder.swift`, and the `ios/BroadcastUploadExtension` target. Recordings upload in chunks.

**Paper-scan folders (Android)** — `com.doubley.nextbrain/scan_folder` (`ScanFolderChannel.kt`, registered in `MainActivity.configureFlutterEngine`, which hands it `onActivityResult` request 4721): `pickTree` opens the system folder picker (`ACTION_OPEN_DOCUMENT_TREE`), `list` walks the tree through `DocumentsContract` (sub-folders, ≤ 5000 files, ≤ 8 levels), `read` returns one file's bytes. No storage permission: scoped storage hides another app's files from `dart:io`, the SAF grant does not. Dart side: `lib/features/exams/paper/scan/scan_folder_io.dart`; the whole flow is in `docs/guides/paper-exams-omr.md`.
