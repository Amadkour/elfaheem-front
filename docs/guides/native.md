# Native code

Moved verbatim from the root `CLAUDE.md` (which keeps a short summary and the rules a session must never miss). Keep this file in step with the code.

**Native code** — Live sessions use LiveKit (`features/teacher/sessions/live/`). Screen recording and screen sharing use platform channels (`com.doubley.nextbrain/native_recorder`, `/radios`, …: every channel is `com.doubley.nextbrain/<name>`, identical on the Dart and native side, D-145). The native side is `android/app/src/main/kotlin/com/doubley/nextbrain/ScreenCaptureService.kt` and `MainActivity.kt`, and on iOS `ios/Runner/AppDelegate.swift`, `LocalDebugRecorder.swift`, and the `ios/BroadcastUploadExtension` target. Recordings upload in chunks.
