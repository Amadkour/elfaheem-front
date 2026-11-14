# Live audit: iOS + Web (2026-10-29, read-only agent report; I1 re-verified by hand)

| id | plat | sev | file:line | issue | proposed fix |
|---|---|---|---|---|---|
| I1 | iOS | critical ✔ | room_screen_share.dart:511-515; prejoin.dart:459-463; livekit_client 2.13.1 local.dart:~846-851; ios/Runner/Info.plist | live viewers never see an iOS share: setScreenShareEnabled → requestActivation is a no-op without RTCScreenSharingExtension, returns without publishing; the extension never opens the rtc_SSFD socket; its JPEG frames only feed the AVAssetWriter recording | useiOSBroadcastExtension: true, RTCAppGroupIdentifier / RTCScreenSharingExtension in Runner Info.plist, extension speaks flutter_webrtc's socket protocol; app-group path for recording only |
| I2 | iOS | high | AppDelegate.swift:2704-2782, 2031-2047; SampleHandler.swift:198 | stopping the share / ending the session never stops the extension: red pill keeps capturing; audio files pile up in the app group | stop-request Darwin notification → finishBroadcastWithError |
| I3 | iOS | high | controls.dart isScreenShareEnabled(); room_screen_share.dart:486, 573 | share state read from the LiveKit publication (never exists, I1): 2nd tap re-runs START, picker again | drive iOS share state from broadcast events |
| I4 | iOS | high | SampleHandler.swift:371-378 | new CIContext per frame, full-res JPEG, extra copies: 50 MB jetsam risk | reuse CIContext, downscale ≤720p |
| I5 | iOS | high | room_screen_share.dart:68-74, 521-525; AppDelegate.swift:1184-1191 | during a share both AEC off (WebRTC + .videoRecording session with defaultToSpeaker): students hear echo | keep AEC on; app audio as a real track / mix |
| I6 | iOS | high | prejoin.dart:503, 533; AppDelegate.swift:790-812, 1294, 1420, 1623, 3275; LocalDebugRecorder.swift:173-180 | TEMP LocalDebugSave ships; starts after the room closes, mirrors the next session into Photos (= D12) | remove / kDebugMode gate |
| I7 | iOS | high | AppDelegate.swift:1985-1989, 2225-2279, 1315, 1385 | 5 s chunk rotation gap (new writer after finishWriting); mic audio dropped until first video frame (ReplayKit only sends on change) → audio holes | double-buffer writers; start at first sample of any type |
| I8 | iOS | high | AppDelegate.swift:638-648, 1978-1983 | bg task expiry finalises the chunk but never begins a new writer: nothing recorded until share stops | beginChunkWriter in expiry, or rely on audio bg mode |
| I9 | iOS | medium | AppDelegate.swift:465-477 | uploadFinished ends the shared BroadcastRecord bgTask mid-broadcast | separate task id |
| I10 | iOS+Web | high | AppDelegate.swift:733, 2421, 2439-2450; recorder_compositor.js:820, 831; room_recorder.dart:819, 835-840; back/config.py:57 | upload token = access token captured once (60 min): recordings cut at ~1 h (= A7) | updateToken channel or per-recording upload token |
| I11 | iOS | medium | AppDelegate.swift:2447-2450, 2501-2516 | chunk deleted after 5 failures; unsent never retried after relaunch; upload_chunk_* never swept | keep, retry on launch, sweep both |
| I12 | iOS | medium (unverified) | AppDelegate.swift:308-334 | interruption / route-change observers only during a share; mic format change mid-chunk can fail the writer | observers for the whole recording; rotate on format change |
| I13 | iOS | medium (unverified) | SampleHandler.swift:247-249, 505-506; AppDelegate.swift:1441-1443 | .audioApp PCM forwarded without the big-endian flag; host assumes little-endian → noise | byte-swap when IsBigEndian |
| I14 | iOS | low | AppDelegate.swift:1499; room.dart:752-762 | mic PTS = arrival time after a Dart round trip per 10 ms frame (~100 calls/s) | batch; timestamp by sample count |
| W1 | Web | high | room_screen_share.dart:331-337, 368-379 | getDisplayMedia audio:true but tab audio never published (TODO) (= D6) | publish LocalAudioTrack(TrackSource.screenShareAudio, …) |
| W2 | Web | high | recorder_compositor.js:1161-1163; room.dart:595-605; room_recorder.dart:887, 928 | compositor.stop() stops every source track incl. LiveKit's remote audio + the published share: "Stop recording" mid-meeting kills remote audio and the share | clone on addStream, or stop only own tracks |
| W3 | Web | medium | room_screen_share.dart:338-349 | browser "Stop sharing" not handled (= D17) | onEnded → detach + clear |
| W4 | Web | medium | recorder_compositor.js:831; back/services/local_recorder.py:1060-1080 | WebM timeslice chunks byte-concatenated; only chunk 0 has the header: losing it ruins the recording; 4xx never retried | retry chunk 0, IndexedDB spill, or self-contained segments |
| W5 | Web | medium | recorder_compositor.js:1032 | upload chain holds every blob on slow networks (unbounded); dropped after ~14 s offline | capped queue + IndexedDB + backoff |
| W6 | Web | medium (unverified) | recorder_compositor.js:303-305, 385, 986, 1056 | software VP9 1080p30 canvas on main thread from a 720p source; hidden tab throttles setInterval to 1 Hz | 720p, VP8, worker / OffscreenCanvas |
| W7 | Web | low | room_screen_share.dart:332-337; prejoin.dart:467 | share capped 1280×720, no contentHint, no systemAudio / suppressLocalAudioPlayback / selfBrowserSurface / surfaceSwitching | 1080p15 detail, constraints explicit |
| W8 | Web | low (unverified) | recorder_compositor.js:389; room_recorder.dart:1067-1069 | older Safari falls back to video/webm (throws); recorder opens a 2nd getUserMedia | mp4 fallback; reuse LiveKit tracks |

Fine: pre-join mic meter and compositor mixing never reach AudioContext.destination (no local echo). First ~295 lines of recorder_compositor.js are commented-out dead code.

## System / tab audio today
- iOS: no screen and no system audio reach viewers (I1). The extension captures .audioApp (DRM excluded) but only into the local recording, possibly as noise (I13). Viewers hear app sound only acoustically through the teacher's mic with AEC off (echo, I5). flutter_webrtc's broadcast capturer is video-only; live app audio needs mixing the .audioApp PCM into the mic via the fork's AudioProcessingAdapter (unverified) or a custom track.
- Web: Chrome / Edge capture tab audio (system audio on Windows / ChromeOS); the app requests it but doesn't publish it — W1 is a few lines. Firefox / Safari give no display audio.

## iOS facts
Runner deployment target 15.6, extension 15.0, Podfile 15.0. App group `group.com.softkour.alfaheem` (Runner + extension entitlements, AppDelegate.swift:541, SampleHandler.swift:107). Bundle ids `com.softkour.alfaheem`, `com.softkour.alfaheem.BroadcastUploadExtension`. RTCAppGroupIdentifier / RTCScreenSharingExtension absent. Fork FlutterBroadcastScreenCapturer reads `rtc_SSFD` in the group named by RTCAppGroupIdentifier, video only.
