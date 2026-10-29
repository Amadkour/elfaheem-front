# Live audit: Android (2026-10-29, read-only agent report, not yet re-verified)

Paths are relative to `android/app/src/main/kotlin/com/example/flutter_education_app/` unless shown in full.

| id | sev | file:line | issue | proposed fix |
|---|---|---|---|---|
| A1 | critical | ScreenCaptureService.kt:655, :392-393 | `MediaRecorder(this)` needs API 31 but minSdk is 24; the first prepare/start is outside try on the recorder thread, so Android 7–11 crash when a teacher joins with recording on | SDK_INT>=S ? MediaRecorder(this) : MediaRecorder(); wrap prepare/start, emitError |
| A2 | critical | ScreenCaptureService.kt:339-341 | API 29–33 FGS type is MICROPHONE only, so MediaProjection.start() throws on Android 10–13 (AOSP); MICROPHONE is an API 30 constant used from 29 | MEDIA_PROJECTION(+MICROPHONE) from Q; gate MICROPHONE on R |
| A3 | high | lib/…/live/widgets/room_screen_share.dart:183, :212; fork ElFaheemFrameCapturer tick() | with no native recorder (recording off) no projection is requested; viewers get the fork's green test frame | share-only mode of ScreenCaptureService (projection + renderer, no MediaRecorder) |
| A4 | high | ScreenCaptureService.kt:246, :621; MainActivity.kt:142-146; room_screen_share.dart:183 | a second share in one session is green: stop → switchToPlaceholder, switchToLive only in activateLiveProjection; Dart skips step 1 because isScreenRecording is still true | ACTION_SWITCH_TO_LIVE on every share start |
| A5 | high | ScreenCaptureService.kt:585-598, :405, :416, :474 | onStop (user stops from notification / chip / cast tile) sets projectionRevoked, which the chunk loop treats as STOP (recording ends); Dart gets no event, keeps a frozen / green track; callback registered only on 34+ | separate revoke from stop; projectionStopped event → Dart unpublishes; register on all levels |
| A6 | high | ScreenPlaceholderRenderer.kt:615-622; fork rgbaToI420Frame | full-res glReadPixels into a new ~10 MB direct buffer per frame at 15 fps + per-pixel Java RGBA→I420 on the encoder's GL thread: heat, fps drops, GC/OOM, recording stalls | GPU downscale ≤720p, reuse buffers, libyuv; best TextureBuffer |
| A7 | high | lib/…/live/widgets/room_recorder.dart:822; ScreenCaptureService.kt:734; ../back/config.py:57 | Bearer token captured once (60 min); after an hour every chunk 401s and is deleted: long lectures silently lose the rest | session-scoped upload token, or a refresh callback; handle 401 separately |
| A8 | high | ScreenCaptureService.kt:703-723 | 4 tries 2/4/8 s then file.delete(): a >15 s network drop leaves permanent holes (Dart comment claims 45 s) | keep files until uploaded, retry until stop + drain, persist queue |
| A9 | high | ScreenCaptureService.kt:299 | RESUME needs isProjectionGranted but PAUSE does not: pause before the first share / audio-only meeting can never resume | gate on isRunning / shouldPause |
| A10 | medium | ScreenCaptureService.kt:140-320, :803-816 | START_STICKY null-intent restart leaves a zombie FGS; no onTaskRemoved (swipe away keeps projection + uploads running, static sinks point at a dead engine) | START_NOT_STICKY; onTaskRemoved → ACTION_STOP; notification Stop action |
| A11 | medium | ScreenCaptureService.kt:212-229 | STORE_PROJECTION error branches return without startForeground after startForegroundService (unverified reachability) | startForeground first, then stopSelf |
| A12 | medium | ScreenCaptureService.kt:349-365, :603 | size / dpi fixed at start: rotation letterboxes landscape into portrait; Android 14 single-app share resize not handled | DisplayListener → virtualDisplay.resize + setDefaultBufferSize; onCapturedContentResize |
| A13 | medium | ScreenCaptureService.kt:68-69, :149-150 | course recording 8 Mbps native-res 15 fps (≈3.6 GB/h upload) on top of the LiveKit uplink | 720p ~2 Mbps; tiny placeholder bitrate |
| A14 | medium | ScreenCaptureService.kt:325-331 | 14+: startForeground(MICROPHONE) throws if RECORD_AUDIO denied | check permission, emit error |
| A15 | low | ScreenCaptureService.kt:455-467 | empty / failed final chunk skipped → is_final never sent for course sessions; server waits for idle watchdog | zero-byte is_final marker or stop route |
| A16 | low | MainActivity.kt:283-295; ScreenCaptureService.kt:543-553 | stopRecording returns at once; FGS ends after 120 s drain while daemon uploads continue | keep FGS until queue empty |
| A17 | low | ScreenCaptureService.kt:729-750 | native upload skips cert pinning + envelope encryption, buffers whole body | OkHttp + CertificatePinner; fixed-length streaming |
| A18 | low | AndroidManifest.xml:120-123 | FlutterRTCMediaProjectionService entry names a class not in the fork; fork fallback capturer has no projection FGS | remove or implement |
| A19 | low | fork AudioSwitchManager.java:45 | audio-focus listener is a no-op: on a phone call the mic goes silent with no signal | handle focus loss: mute, banner, pause recording |
| A20 | low (unverified) | ScreenCaptureService.kt:656; room.dart:1014 | recorder uses AudioSource.MIC with speaker forced; remote voices only via speaker leak | record the WebRTC mix or VOICE_COMMUNICATION |
| A21 | low | ScreenCaptureService.kt:246; ScreenPlaceholderRenderer.kt:292-315 | after share-off VirtualDisplay keeps capturing (privacy indicator stays); release() vs attach latch may hang (unverified) | stop VirtualDisplay on share-off; latch timeouts |

Not a bug: each chunk is its own MP4 (own moov, keyframe first, timestamps from 0), so every chunk decodes alone; the server must re-timestamp on concat. Upload order kept by one thread. One projection only, shared with the fork's ElFaheemFrameCapturer via ElFaheemBridge.pushFrame, so the live share depends on the recorder service (A3–A5).

## System audio during a live share
- Today none: no AudioPlaybackCaptureConfiguration in android/ or the fork; the fork's getDisplayMedia builds video only and ignores `audio: captureScreenAudio` (livekit_client 2.13.1). The screenShareAudio loop in room_screen_share.dart:236-248 is dead code.
- Media played on the speaker reaches students only as mic leak (AEC partly cancels it).
- Possible on API 29+: AudioPlaybackCapture from the existing projection, usages MEDIA / GAME / UNKNOWN, needs RECORD_AUDIO; apps with allowAudioPlaybackCapture=false (or targeting <29 without opt-in) excluded; call audio never capturable.
- Missing piece: injecting that PCM into WebRTC needs a fork change (custom audio source published as screenShareAudio, or input mixing).

SDK: minSdk 24, targetSdk 36, compileSdk 37. Fork ref 163469226e1d…, checkout `C:\Users\ahmed\AppData\Local\Pub\Cache\git\flutter-webrtc-163469226e1d261a6461f1b7244c1d0ff0cec770`. livekit_client 2.13.1.
