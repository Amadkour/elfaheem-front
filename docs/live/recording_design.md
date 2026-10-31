# Server recording design (research 2026-10-29, read-only; to be proven on the dev stack before adoption)

The owner's objections to server recording (heavy CPU, poor screen-share quality) hold for TODAY's configuration, not
for server recording itself.

## Today (`../back`)
- One RoomComposite (headless Chrome) HLS egress per quality tier (`services/LiveKit_service.py:1380-1387`, layout
  `speaker-dark` :1360), plus an audio-only RoomComposite per audio tier (OGG, :1233-1244) and a Track-egress
  "screen-audio sidecar" (:955-1006). `RECORDING_QUALITIES=all`, `RECORDING_AUDIO=all` (code defaults,
  `config.py:268-269, 297-320`) → up to 3 Chrome video + 2 Chrome audio + 1 sidecar = 6 egress jobs per class.
  (The local `.env.production` says `RECORDING_MODE=client`: production records on the device today.)
- Presets: medium 1920x1080 15 fps 4 Mbps keyframe 4 s; high 24 fps 6 Mbps (:194-201). Screen-share presets
  (8 fps, 10–15 Mbps, :204-211) never apply: `_switch_layout_if_needed` sends `video_bitrate` / `framerate` in
  `UpdateStreamRequest` (:938-943), which only has `add_output_urls` / `remove_output_urls` / `add_destinations`
  (`livekit/protocol/egress.pyi:834-844`); the exception is swallowed (:944-945). `update_layout("screen-share")`
  (:934) is ignored by the default template (layout read once with `useState(initialLayout)`; `screen-share` is not
  one of its layouts — egress `template-default/src/Room.tsx:58,146-162`).
- Why the share is soft: (a) `speaker-dark` gives the stage 5/6 of the width → the 1080p share is shrunk to
  ~1580x889, letterboxed, decoded + re-encoded by Chrome (`pkg/pipeline/builder/layout.go:277-330`); (b) the egress
  container has `cpus: 1.5`, `cpu_shares: 256` (`docker-compose.yml:120-134`) while LiveKit admits a RoomComposite at
  a cost of 4 CPUs (egress v1.8.3 `pkg/config/service.go:31-38`) — starved Chrome drops frames; (c) the publisher
  sends the share as VP8 simulcast with `degradationPreference.balanced` (`prejoin.dart:429-471`) — resolution drops
  before fps, wrong for text; (d) egress v1.8.3 runs against livekit-server v1.13.7 (`docker-compose.yml:91,120`).
- Meetings: device chunks → ffmpeg (`services/live_recording_service.py`) → `cloud_drive_service.upload_file`
  (resumable 8 MiB parts).

## CPU (LiveKit admission costs, egress `service.go`; max_cpu_utilization 0.8)
RoomComposite / Web 4 (docs: 2–6 real) · audio-only composite 1 · Participant 2 · TrackComposite 1 · Track 0.5 ·
v2 media source: follows a participant 2, a named track 1, audio-only 1 (`monitor.go:287-297`). With ~6 cores for
egress on a 12 vCPU box: Chrome ≈ 1 recording at a time; the SDK paths ≈ 2 at default cost, 4–5 once `cpu_cost` is
set from measurement (unverified).

| option | CPU | share quality | all voices | annotations | notes |
|---|---|---|---|---|---|
| RoomComposite Chrome (today) | 4 | shrunk ~1580 px, re-rendered | yes | Chrome custom template only | most expensive |
| RoomComposite + `enable_template_sdk` (egress v1.15, GStreamer) | 4 unless tuned | `single-speaker` = share full frame | yes | no | new code; no share → top speaker (may be a student) |
| ParticipantEgress `screen_share=true` | 2 | full frame | **no** (host share + share audio only) | no | `sdk.go:713-721` |
| v2 `StartEgress` media: host video `prefer_screen_share` + all room audio mixed | 2 | full frame, encoded once | yes (mixed) | no | needs egress ≥ v1.14; camera fallback when nothing is shared unverified (`sdk.go:780-786`) |
| TrackComposite | 1 | full frame | no (one audio track) | no | restart on every re-share |
| Track egress per track + offline mux | 0.5 each | as published | yes after mux | overlay at playback | ffmpeg job, sync / drift risk |

## Recommendation (pending the dev-stack proof)
- ONE egress per room: the v2 media-source job (no Chrome, every voice mixed, the share encoded once at 1920x1080
  full frame), H.264 ~10 fps, 3–4 Mbps, keyframe interval = HLS segment = 6 s (static text needs keyframes and low
  fps, not bitrate). If the host camera does not show when nothing is shared: the GStreamer `single-speaker-dark`
  RoomComposite instead.
- Drop the 3 tiers, the 2 audio composites and the sidecar; derive audio-only (`-c:a copy`) and 720p (off-peak)
  from the HLS afterwards.
- Crash safety: keep HLS segments to MinIO (`_hls_output`, :242-258); never a single MP4.
- Meetings: on egress_ended (webhook), remux HLS → MP4 (`-c copy +faststart`), then the existing `LiveRecording`
  flow (`local_path`, `uploading`, `_upload` → `cloud.upload_file` with its retry tick); delete the MinIO copy after.
- Annotations (D-079): Android whole-screen share burns them into the share track (in every recording for free);
  vector strokes are stored timestamped (JSONL in MinIO, clock = egress `started_at`) and drawn by the VOD player over
  the video; burned in with ffmpeg only for a Drive export, off-peak. Not a Chrome template (forces the 2–6 CPU path).
- Limits: one egress per room (start lock L11), concurrency bounded by `cpu_cost` + a platform cap; live media
  cannot be queued — when admission fails the start answers `recording_by: "device"` and the device recorder runs.

## Migration
1. Infra: egress image ≥ v1.14 (v1.15 for the GStreamer compositor), matched to livekit-server 1.13.7; egress
   `cpus` 1.5 → ~6; `egress.yaml` `cpu_cost` from measurement (+ `enable_template_sdk` if used).
2. `LiveKit_service`: one `start_egress` replaces the tier composites + sidecar; delete `_switch_layout_if_needed`,
   the dead presets and the broken `update_stream`; egress webhook; derive jobs; settings
   `RECORDING_ENGINE=v2|composite|client`, `RECORDING_SHARE_FPS`, `RECORDING_BITRATE`, `RECORDING_MAX_CONCURRENT`.
3. `live_recording_service`: a server-origin path (no chunks, remux, reuse `_upload`).
4. App: share `maintainResolution`, `maxFramerate` 15, simulcast off or a full-res top layer; read `recording_by`
   and skip the device recorder when `server`.
5. Older apps start the device recorder whenever `recording_enabled` is true (`room.dart:1047,1584`): server egress
   only for clients that declare the capability (header / min version); others keep client mode (no double recording).

## Open questions (to answer on the dev stack)
Camera fallback with `prefer_screen_share`; egress v1.14/1.15 ↔ livekit-server 1.13.7; real CPU at 1080p / 10 fps;
students' cameras / voices in recordings (privacy + consent wording); mixed audio vs a separate host channel.

## Device recording frame rate (Android, client mode — D-103, D-108)

Pipeline before a share (no MediaProjection is held): the room → `RoomFrameGrabber` (PixelCopy of the
`FlutterSurfaceView`, room rect from Dart, GPU-scaled to the encoder's long side, ≤ 30 copies/s, one in flight) →
`ScreenPlaceholderRenderer.pushRoomBitmap` (texture upload, draw, `eglPresentationTimeANDROID` = copy time) →
`SegmentedRecorder` (H.264 30 fps 2.5 Mbps + AAC, ~5 s MP4 chunks cut at key frames, `seamless=1`). Fallback when
the copy fails: Dart frames (`toImage` → rawRgba → `setPlaceholderFrame`, ≤ 12 fps, `live_frame_pacing.dart`), drawn
by the renderer's 15 Hz keep-alive clock. During a share: the VirtualDisplay → renderer → encoder at 30 fps, the
share's own capture pass throttled to the share preset's fps.

| | file fps | frames / span | camera region distinct / s | distinct gap p95 |
|---|---|---|---|---|
| before (session 75, S24, D-103 build) | 14.76 | 2057 / 139.4 s | 10.0 (median 12 / s, min 1) | 136 ms |
| after (session 77, S24, D-108 build, 2026-10-31) | 30.01 | 3096 / 103.2 s | 29.1 (camera full stage, 17 s; min 26 / s) · camera box over the board: median 29 / s | 33 ms |

Session 77 in detail: every frame step 33.3 ms (max 33.3, none > 100 ms); the whole picture changes 28.1 times a
second (median 29); `RoomFrameGrabber` logged "probe ok", 590×1280 copies from the 1440×3120 surface, ~30.1 copies / s,
0 failed, and kept running while the whiteboard was open (the board is part of the room picture). 16 seamless chunks,
assembled file 0.70 Mbit/s (the encoder's 2.5 Mbit/s is a ceiling; a still room needs far less). Device load during
the recording: the app 68–110 % of one core (of 800 %), surfaceflinger 20–30 %, cameraserver 3–9 %; thermal status 0
(AP 48.7 °C, skin 37.4 °C, battery 33.5 °C). The published camera kept its three layers (320×180 / 640×360 /
1280×720) while recording. Not measured: the same load numbers with the old build (no A/B on one day), a longer class
for thermal drift, a weaker Android.

How to measure (inside the dev API container, which has ffmpeg): copy the assembled `_high.mp4` out of MinIO
(`minio.Minio(...).fget_object("edu-recordings", "session_<id>/<run>_high.mp4", …)` with the container's `MINIO_*`
env), then `ffprobe -show_entries frame=pts_time` for the frame steps and
`ffmpeg -vf crop=<camera box>,mpdecimate=hi=200:lo=64:frac=0.1,showinfo -f null -` for the distinct frames of the
camera box (session 75: `crop=110:100:438:275`, the camera circle at the board's top right). Target: ≥ 24 distinct/s
with the camera moving, frame steps ≈ 33 ms, no step > 100 ms. Device load: `adb shell dumpsys cpuinfo`,
`dumpsys thermalservice` (status must stay ≤ 1 in a 60 s class) and the published camera layer's resolution in the
room's network pill / LiveKit stats (must not drop when recording starts). Logcat tags: `RoomFrameGrabber` (probe ok,
copied / failed every 10 s, the copy size), `SegmentedRecorder` (`started 576x1280@30 2500kbps`).
