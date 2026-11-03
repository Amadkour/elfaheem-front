# Native code

Moved verbatim from the root `CLAUDE.md` (which keeps a short summary and the rules a session must never miss). Keep this file in step with the code.

**Native code** — Live sessions use LiveKit (`features/teacher/sessions/live/`). Screen recording and screen sharing use platform channels (`com.example.flutter_education_app/native_recorder`, `/radios`). The native side is `android/app/src/main/kotlin/.../ScreenCaptureService.kt` and `MainActivity.kt`, and on iOS `ios/Runner/AppDelegate.swift`, `LocalDebugRecorder.swift`, and the `ios/BroadcastUploadExtension` target. Recordings upload in chunks.

**Paper-scan folders (Android)** — `com.example.flutter_education_app/scan_folder` (`ScanFolderChannel.kt`, registered in `MainActivity.configureFlutterEngine`, which hands it `onActivityResult` request 4721): `pickTree` opens the system folder picker (`ACTION_OPEN_DOCUMENT_TREE`), `list` walks the tree through `DocumentsContract` (sub-folders, ≤ 5000 files, ≤ 8 levels), `read` returns one file's bytes. No storage permission: scoped storage hides another app's files from `dart:io`, the SAF grant does not. Dart side: `lib/features/shared/exam_engine/paper/scan/scan_folder_io.dart`; the whole flow is in `docs/guides/paper-exams-omr.md`.
