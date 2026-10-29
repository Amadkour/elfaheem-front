# iOS live share + recorder — Mac test plan (written 2026-10-29, nothing run yet)

Everything in `ios/` from the 2026-10-29 change was written on Windows and has **never been
compiled**. Do §1–§3 before any scenario. Audit ids (I1–I14): `docs/live/audit/ios_web.md`.
Dart wiring that must be applied first: `docs/live/ios_share_wiring.md`.

Files changed: `ios/Runner/AppDelegate.swift`, `ios/Runner/Info.plist` (RTCAppGroupIdentifier,
RTCScreenSharingExtension), `ios/Runner.xcodeproj/project.pbxproj` (LocalDebugRecorder.swift
removed from the Runner target: 4 lines), `ios/BroadcastUploadExtension/SampleHandler.swift`
(rewritten) + new `SocketConnection.swift`, `SampleUploader.swift`,
`DarwinNotificationCenter.swift` (the extension folder is an Xcode 16 *synchronized* group: new
files join the extension target with no project edit — check §2). Deleted:
`ios/Runner/LocalDebugRecorder.swift`, `ios/LocalDebugRecorder.swift`,
`ios/LocalDebugRecorder 2.swift`. New Dart: `lib/features/teacher/sessions/live/widgets/ios_share.dart`.

## 1. Toolchain and pods

- **Xcode 16.x** (16.2+ recommended). Required: the project uses
  `PBXFileSystemSynchronizedRootGroup` for the extension; Swift 5 mode; `loadUnaligned` needs
  Swift 5.7+.
- Flutter 3.47.7 (CI version). Check whether Swift Package Manager is on:
  `flutter config --list` → `enable-swift-package-manager`. The fork has a `Package.swift`; with SPM
  on, flutter_webrtc / WebRTC come from SPM, not CocoaPods — either is fine, but not both.
- From the repo root:
  ```bash
  flutter clean && flutter pub get
  cd ios
  pod install --repo-update
  # Podfile.lock still pins WebRTC-SDK 144.7559.01 (flutter_webrtc 1.4.0 / livekit 2.8.1);
  # the fork and livekit_client 2.13.1 need 150.7871.01:
  pod update WebRTC-SDK
  grep -n "WebRTC-SDK\|flutter_webrtc\|livekit_client" Podfile.lock   # expect 150.7871.01, flutter_webrtc 1.6.2, livekit_client 2.13.1
  cd ..
  ```
  Commit the new `Podfile.lock` with the change.

## 2. Build checks (fix compile errors here first)

1. `open ios/Runner.xcworkspace`, scheme Runner, a real device (ReplayKit broadcast does not run
   on the simulator), Product → Build.
2. Expected risk points if it fails to compile:
   - `import flutter_webrtc` in AppDelegate.swift (module name; with CocoaPods it is the pod's
     module, with SPM the target `flutter_webrtc`).
   - `ShareAppAudioMixer` conformance to `ExternalAudioProcessingDelegate`: the Swift names were
     derived, not checked by a compiler — `audioProcessingInitialize(withSampleRate:channels:)`,
     `audioProcessingProcess(_:)`, `audioProcessingRelease()`. Xcode's fix-it shows the expected
     names if they differ. Also `AudioManager.sharedInstance()` vs a property, and
     `RTCAudioBuffer.rawBuffer(forChannel:)` (livekit_client uses exactly this name).
   - Extension: `CIImageRepresentationOption(rawValue:)`, `FileHandle.write(contentsOf:)`,
     `Darwin.rename`, `CMGetAttachment(... RPVideoSampleOrientationKey ...)`.
3. Target membership: select `SocketConnection.swift`, `SampleUploader.swift`,
   `DarwinNotificationCenter.swift`, `SampleHandler.swift` → File inspector → only
   **BroadcastUploadExtension** ticked (not Runner). Runner's Compile Sources must no longer list
   `LocalDebugRecorder.swift`.
4. Info.plist of the **built** app (`Products/Runner.app/Info.plist`) contains
   `RTCAppGroupIdentifier = group.com.softkour.alfaheem` and
   `RTCScreenSharingExtension = com.softkour.alfaheem.BroadcastUploadExtension`.

## 3. Signing and capabilities

- Team `MVHKS8482X` on both targets. Runner bundle id `com.softkour.alfaheem`, extension
  `com.softkour.alfaheem.BroadcastUploadExtension` (must equal RTCScreenSharingExtension).
- **App Groups** capability on BOTH targets with `group.com.softkour.alfaheem` ticked (Signing &
  Capabilities). In the Apple developer portal the group must be assigned to BOTH App IDs and the
  provisioning profiles regenerated — otherwise `containerURL(forSecurityApplicationGroupIdentifier:)`
  returns nil: the extension then stops at once with "App Group … not found".
- Extension deployment target 15.0, Runner 15.6 (unchanged).
- Embed: Runner → Build Phases → *Embed Foundation Extensions* contains `BroadcastUploadExtension.appex`.

## 4. Logs to keep open

Console.app, device selected, filter `SampleHandler OR SocketConnection OR [SHARE] OR [REC]`.
Also select the process `BroadcastUploadExtension` separately (its logs are its own process).
Key lines: `[SampleHandler] started`, `live socket connected`, `iOS_BroadcastStarted — extension
live`, `app audio mixing into the microphone: on`, `[REC] finalised chunk #N`, `stop requested by
the app`, `live socket closed by the app`.

## 5. Scenarios (two devices: the iPhone/iPad presenter + any viewer, ideally a second phone)

| # | scenario | steps | pass when |
|---|---|---|---|
| 1 | start share from the app | join as teacher, tap Share | ONE system sheet ("Start Broadcast" for our extension, not a list); after Start the 3-2-1 countdown, `live socket connected` within ~2 s, viewer sees the presenter's screen within ~3 s; switch to Safari / Photos, viewer follows |
| 2 | second tap while the sheet is open | tap Share, then tap Share again before Start | no second sheet; button shows the sharing / pending state (I3) |
| 3 | cancel the sheet | tap Share, Cancel | UI back to "Share", no red pill, recording (if on) resumes ≤ 10 s (watchdog) |
| 4 | stop in the app | tap Stop sharing | red status pill disappears within ~1 s, iOS shows "Screen sharing stopped" / "تم إيقاف مشاركة الشاشة", viewer's share tile goes away (I2) |
| 5 | stop from Control Center | stop via the red pill / Control Center | app UI resets to "Share" by itself, viewer's tile goes away, no stale publication (I3) |
| 6 | leave the room while sharing | Leave | broadcast ends (pill gone) within ~2 s; App Group has no growing `broadcast_audio_queue` (I2) |
| 7 | kill the app while sharing | swipe the app away | the broadcast ends (socket closed → extension finishes) |
| 8 | static screen / late viewer | share a still page, a viewer joins 30 s later | late viewer sees the picture within ~1 s (1 fps keep-alive) |
| 9 | rotation | rotate the device during the share | viewer sees it upright (Buffer-Orientation → rotation) |
| 10 | app audio | play a YouTube / Safari video with sound while sharing, mic ON | viewer hears the video's sound clearly (mixed into the mic); then mute the mic → app sound stops for viewers (documented limit) |
| 11 | echo (I5) | presenter on loudspeaker, viewer talks for 30 s | viewer does NOT hear themselves back; presenter's voice clear. Also during a share with app audio |
| 12 | phone call during share | call the presenter's phone, answer, hang up | share survives or ends cleanly; after the call the mic works again, recording continues with a new chunk (`forced chunk rotation: audio interruption ended`) |
| 13 | headset / Bluetooth | plug/unplug wired headset, connect AirPods mid-share | audio continues; `forced chunk rotation: audio route changed` and/or `mic format changed mid-chunk`; no failed writer |
| 14 | long share memory | share 20 min, scrolling content | Instruments → *Allocations* + *VM Tracker* attached to `BroadcastUploadExtension`: persistent ≤ ~25 MB, no growth, never near 50 MB; no jetsam (Console: "EXC_RESOURCE / memory limit"). Repeat with detail mode on (`setShareDetailMode(true)`) |
| 15 | CPU / heat | same 20 min | extension CPU ≲ 20–30 % on one core; frame rate to viewers ≈ 15 fps while scrolling |
| 16 | DRM app | open Netflix / Apple TV+ | black frames / no sound, nothing crashes |

## 6. Recording (teacher recording ON)

| # | scenario | pass when |
|---|---|---|
| R1 | record, no share, 2 min | chunks every `chunkSecs`, no `has received no frames yet` loops on a static screen (session now starts on the first mic sample, I7); server assembles; no audio holes at chunk joins (listen at 0:05, 0:10, …) |
| R2 | record + share + stop share | chunk boundary at share start and stop; broadcast chunks show the shared screen; app audio present ONCE (mixed in the mic track while the mixer is live — not doubled with the system-audio track) |
| R3 | background > 30 s while recording | `background task expiring — rotating chunk`, recording continues (I8), chunks keep uploading |
| R4 | upload failure | airplane mode for 2 min mid-recording, end the session | failed chunks are moved to `Application Support/rec_pending/` (`kept for a later retry`); next recording start (or `retryPendingUploads`) uploads them; a 4xx drops them; >72 h old are swept (I11). **Server question:** what happens to a chunk that arrives after its recording was assembled? |
| R5 | audio-only meeting recording + share | records audio straight through, no 10 s pause at share start |
| R6 | chunk validity | `ffprobe` every downloaded chunk: valid MP4/M4A, audio PTS continuous across chunks (no gaps > 50 ms), mic track duration ≈ video duration (I14: sample-clock PTS) |
| R7 | pause / resume quickly | pause and resume within 1 s | no lost or overwritten chunk index |
| R8 | the TEMP Photos copy is gone | record a session | nothing new appears in Photos (I6) |

## 7. Top risks to look at first

1. Compile issues in the Swift names listed in §2 (never compiled).
2. Two pickers, or LiveKit not publishing: the Dart wiring (`useiOSBroadcastExtension: true` in
   `RoomOptions`, no `setScreenShareEnabled(true)` before the broadcast) is not applied yet.
3. App Group / profile mismatch → extension ends at once.
4. Socket framing: if `live socket connected` shows but viewers see nothing, compare one frame's
   header with flutter_webrtc's `FlutterSocketConnectionFrameReader` (Content-Length / Buffer-Width /
   Buffer-Height must equal the JPEG).
5. App-audio mixer on the WebRTC audio thread (glitches, crackle, latency ≈ 100–300 ms): turn it
   off with `IosShareNative.setAppAudio(false)` to isolate.
6. App audio heard twice by viewers (mixed + picked up acoustically by the mic) on loudspeaker.
7. Recording: first broadcast frame racing the pause/rotate at share start (chunk index advanced
   synchronously now — verify no chunk is overwritten), audio-video sync of mic-anchored sessions.
