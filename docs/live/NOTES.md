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

## Live performance (D-089)
Super admin › App configuration › Live performance (`lib/features/admin/live_settings/`) → `GET/PUT
/api/v1/admin/live-settings` (back `services/live_settings_service.py`, stored in `app_settings` `platform.live`).
Every live start / join payload carries `live_config` v1 (session start / join, meeting join, signed-in link join,
public guest join, lobby polls): `video_codec`, `weak_network`, `camera_max_host`, `camera_max_participant`,
`camera_fps`, `screen_fps_max`, `screen_bitrate_kbps`, `audio_dtx`, `audio_red`, `participants_camera_default_off`,
`pause_hidden_video`, `recording_mode` (the RUN's; meetings always `client`), `server_recording_engine`. The live
room applies them (the media code's own model). Server-only: `server_recording_tiers` single | all.

| switch | recommended | what it does end to end |
|---|---|---|
| codec | vp8 | publish codec; the app falls back to vp8 where the device lacks it |
| weak network | adaptive | adaptive = simulcast + dynacast step down (server `allow_pause` pauses what cannot fit); audio_first = viewers drop to audio below ~0.35 Mbit/s, "Show video" |
| cameras | 720p host / 360p others / 24 fps | publish caps (simulcast top layer) |
| screen | 15 fps / 2.5 Mbit/s | share encoding caps (text: resolution first) |
| DTX / RED | on / on | Opus DTX, redundant audio |
| cameras off at join | on | attendees publish no camera until they choose |
| pause hidden video | on | adaptive stream: no download for tiles off screen / minimized room |
| recording mode | server (unset = env) | new runs: egress or device chunks; a run keeps its mode (`online_sessions.recording_mode`, migration 0030) |
| engine | composite | composite = RoomComposite (Chrome, or GStreamer with `enable_template_sdk`); media = one v2 media job, share pixel-exact, BLACK when nothing is shared |
| tiers | single (unset = env) | one 1080p HLS egress per class vs the env's tier lists + audio composites + sidecar |

Server robustness: egress watchdog in the 60 s reconcile tick (HLS playlist not written for 120 s → StopEgress,
row `stalled`, segments salvaged — playlist closed or rebuilt — and saved as a partial recording; nothing on MinIO →
FAILED); a FAILED egress with segments is salvaged at finalize; the LiveKit webhook answers within 2 s and finishes on
its own pool (claim kept, once). LiveKit config: dev `back/scripts/dev/livekit.dev.yaml` (congestion control +
`allow_pause`, codecs opus/red/vp8/h264/vp9, PLI throttle, room guards); production proposals (NOT applied)
`back/deploy/livekit.production.yaml` and `back/deploy/egress.production.yaml` — egress v1.8.3 → v1.15.0,
`enable_template_sdk: true`, `cpu_cost` from the bench peaks, egress `cpus` 1.5 → 3 (≥ 3 cores per Chrome job),
UDP buffers `net.core.rmem_max/wmem_max=5000000`, LiveKit `use_external_ip: true`.

## Machine
- i5-12400F (6C/12T physical) but Windows sees 1 socket / 4 logical CPUs, hypervisor present -> boot or BIOS limit.
- 31.8 GB RAM (22 free), Radeon RX 570 4 GB (no NVENC; AMF not reachable from Linux containers under WSL2).
- Docker Desktop not running (needed for postgres / livekit / egress / minio local stack).
