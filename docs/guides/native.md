# Native code

Moved verbatim from the root `CLAUDE.md` (which keeps a short summary and the rules a session must never miss). Keep this file in step with the code.

**Native code** — Live sessions use LiveKit (`features/teacher/sessions/live/`). Screen recording and screen sharing use platform channels (`com.example.flutter_education_app/native_recorder`, `/radios`). The native side is `android/app/src/main/kotlin/.../ScreenCaptureService.kt` and `MainActivity.kt`, and on iOS `ios/Runner/AppDelegate.swift`, `LocalDebugRecorder.swift`, and the `ios/BroadcastUploadExtension` target. Recordings upload in chunks.
