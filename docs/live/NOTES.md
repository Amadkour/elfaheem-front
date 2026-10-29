# Live feature: stack notes (2026-10-29)

## Stack (confirmed from code)
- App: Flutter, one codebase for Android / iOS / Web (`flutter_education_app`). Backend: FastAPI in `../back`.
- Live media: LiveKit SFU (WebRTC), self-hosted `livekit/livekit-server:v1.13.7` (docker-compose.yml, dev profile "live").
  Client: `livekit_client` + `flutter_webrtc` fork (pinned ref, D-010).
- Recording: `RECORDING_MODE=server` (default) = LiveKit composite Egress -> MinIO (`services/LiveKit_service.py`, ~2k lines,
  in-process registries, NOT multi-worker safe). `client` mode = device uploads 5 s chunks to `routers/recorder.py`,
  ffmpeg assembles in `services/local_recorder.py`.
- Meeting recordings to Google Drive / OneDrive: always client chunks (`POST /live/recordings/{rid}/chunk`,
  `live_recording_router.py`, `meeting_recording.dart`).
- The 5 s chunks are a RECORDING path only. Viewers watch over LiveKit (WebRTC), never via chunks.

## App files
- Room: `lib/features/teacher/sessions/live/` (`prejoin.dart`, `room.dart`, `widgets/room_screen_share.dart`,
  `widgets/room_recorder.dart` (commented-out legacy), `recorder_web_impl.dart` (JS compositor, MediaRecorder timeslice),
  `widgets/record/recorder_native_{android,ios,shared}.dart`, `live_control_bar.dart`, `live_reactions.dart`).
- Shared live: `lib/features/shared/live/` (lobby, share link, meeting recording, `live_room_host.dart` minimize).
- Whiteboard (D-087): `lib/features/teacher/sessions/live/whiteboard/` — `board_protocol.dart` (topics `board` /
  `board.laser`), `board_controller.dart` (pure: presenter, pages, items, undo / redo, snapshots, permissions),
  `board_painter.dart`, `board_stage.dart` (pointer, text editing, selection, per-device zoom, PNG),
  `board_toolbar.dart` (dock, bar, Board sheet, background tiles), `board_view.dart` (the stage composition +
  Board sheet); the "Whiteboard" region of `room.dart`; the Share sheet's Whiteboard tab in
  `widgets/share_options_sheet.dart`. Tests `test/org/board_*_test.dart`, `test/ui/whiteboard_layout_test.dart`,
  renders `test/visual/whiteboard_golden_test.dart`.
- Native: Android `ScreenCaptureService.kt`, `MainActivity.kt`; iOS `AppDelegate.swift`, `LocalDebugRecorder.swift`,
  `ios/BroadcastUploadExtension`.

## Backend files
- `routers/online_sessions.py` (start/join/leave/end), `live_room_router.py`, `live_guest_router.py`,
  `live_recording_router.py`, `recorder.py`; services `LiveKit_service.py`, `live_room_service.py`,
  `live_guest_service.py`, `live_plan_service.py`, `local_recorder.py`, `scheduler_service.py`.
- Existing tests: `tests/org_v2/e2e_live_guest_link.py`, `e2e_session_record_flag.py`, `e2e_live_lobby.py`,
  `e2e_meeting_recording.py`, `e2e_points_live_plan.py`, `e2e_auto_captions.py`.

## Machine
- i5-12400F (6C/12T physical) but Windows sees 1 socket / 4 logical CPUs, hypervisor present -> boot or BIOS limit.
- 31.8 GB RAM (22 free), Radeon RX 570 4 GB (no NVENC; AMF not reachable from Linux containers under WSL2).
- Docker Desktop not running (needed for postgres / livekit / egress / minio local stack).

## Live media tuning (D-090, 2026-10-29)
The super admin's `live_config` (every join / start payload; parsed in `lib/features/shared/live/live_config.dart`,
missing / older server → the defaults below) drives what the room publishes (`live_media_plan.dart`, built when the
Room is made in `prejoin.dart`) and receives (`live_media_controller.dart` + `live_quality_governor.dart`).

| knob | default | why |
|---|---|---|
| camera host / participant | 720p / 360p (was 1080p60 for everyone) | a teacher fills the stage; students are thumbnails (adaptive stream never asks them for more than ~360p) |
| camera fps | 24 | −15 % bitrate and encoder CPU vs 30, still smooth for a talking head |
| layers (VP8, kbps) | 180p@15 = 100 · 360p@24 = 380 · 720p@24 = 1280 (30 fps: 160 · 450 · 1500; 540p 800) | explicit max bitrates; the 180p layer is what a weak link falls back to. Host camera upload ≈ 1.76 Mbit/s with every layer watched (was ≈ 5.6), a student's ≈ 0.48 (was ≈ 5.6); dynacast stops layers nobody watches |
| codec | VP8, backup VP8 behind H.264 / VP9 | universal decode; H.264 = phone hardware encode (less CPU, ×1.1 bitrate); VP9 = SVC (×0.75 bitrate, more CPU) and never on Safari / iOS (→ VP8), H.264 never on Firefox (→ VP8) |
| audio | Opus mono, host 48 kbps, others 24 kbps; DTX on, RED on | speech needs 24 kbps; the host's mic may carry shared device audio (D-080); DTX sends nothing in silence (most of a class is silence), RED covers loss. Mic only published once unmuted (D1) |
| screen share | Detail: short side 1080, ≤ 2.59 MP, ≤ 15 fps, 2.5 Mbit/s; Motion: short side 720, ≤ 1.15 MP, 30 fps, 3 Mbit/s; fps ≤ `screen_fps_max` (30), Detail at `screen_bitrate_kbps`, Motion 1.2× (≤ 6 Mbit/s); two layers (+ the half-size copy at ¼ bitrate) | "1080p / 720p" is the short side: the S24 Ultra (1440×3120) shared Motion at 590×1280 (logcat 15:19–15:54: "share capture target 590x1280 (input 1440x3120, max 1280)") because the cap was the LONG side — 41 % of the screen's width, soft text. Now 720×1560 Motion / 1080×2340 Detail (was 886×1920). The half-size layer lets a weak viewer keep a picture instead of a frozen single layer; dynacast stops encoding it when nobody needs it; the full layer keeps the text sharp |
| participants' camera | off at the start (`participants_camera_default_off`) | no camera track exists until the student turns it on: no upload, no encoder; the pre-join page says why, with Turn on |
| hidden video | paused (`pause_hidden_video`) | strip tiles are built without a cache extent (an off-screen built tile counted as watched), past the video budget (phone 4, tablet 6, desktop 9) a tile shows the avatar, a minimized room draws no video (the box keeps one), a backgrounded app unsubscribes every video until it returns (audio goes on) |
| recording | `recording_mode` server → no device recorder (Egress records); client → the device recorder as before; missing → as before | the per-session `recording_enabled` switch still decides whether anything records |

**Weak network (the freeze fix).** The bench (`scratchpad/load/RESULTS.md`, 1 Mbit/s cap on a real libwebrtc
subscriber): the SFU kept 720p frozen for ~15 s, went to 360p at 25 s and to 180p @ 15 fps at 30 s for good; 150 ms
jitter flapped 180p ↔ 720p; 5 % loss was fine with NACK. The room now asks for layers itself: every 2 s (and on each
connection-quality event) the governor reads the received videos' counters. Bad = the server rates the link poor /
lost, ≥ 8 % of the video packets lost, a camera that should play (its publisher on a good link) decoded no frame
for ~2 s, or the server paused a track → LOW (180p) at once (setVideoQuality on every remote video; ~2–4 s instead of ~25). Fair = 2–8 % loss (what
jitter looks like) → no change. Good for 12 s → one step up (LOW → MEDIUM → HIGH). A step up that breaks the link
within 45 s doubles the hold (12 → 24 → … 120 s) and puts a ceiling one tier below for 4 min (8, 16, 32 when the same
tier fails again): a 1 Mbit/s link settles on 360p instead of flapping or sitting on 180p. `weak_network: audio_first`:
bad for 8 s at LOW → the cameras are unsubscribed (a screen share stays, at its lowest layer), avatars + "Audio only
to keep you connected" with Show video (which never goes audio-only again in that room). The pill "Poor connection —
video quality lowered" shows while the room holds the video down. Not measured on a device yet (phone tests on hold).

**Whiteboard in server recordings.** Egress records tracks, a board is vectors: while `recording_mode` is server, a
server recording runs and this device presents a board, the page is also published as a `whiteboard` screen-share
track (1280×720, 2 fps, ≤ 500 kbps, one layer, re-rendered only when the page changed). Apps unsubscribe it (they draw
the vectors); Egress puts it on the stage. Web (canvas captureStream) and Android (ElFaheemFrameCapturer via
`pushBoardFrame`); not iOS.

**CPU.** The aurora behind the stage runs only while the waiting card is shown and is its own repaint layer (it
repainted the whole room 60 times a second behind every video). The whiteboard / annotation painters were checked:
their tickers run only while a laser dot fades, `shouldRepaint` compares item lists by identity.
