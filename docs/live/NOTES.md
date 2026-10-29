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
