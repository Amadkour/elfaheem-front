# Live: what the next session applies (written 2026-10-30)

Resume here for live work. State at hand-off: front `organizations` = `merge/round5` (D-091 – D-097 merged, 2233 tests
green, build installed on the S24); back `organizations` has `allow_pause: false` (1eda111) and the features guide for
round 5 (6f7f781). Nothing is pushed — pushing `organizations` in either repo needs the owner's explicit OK (then open
a PR so CI runs: a push to `organizations` alone runs nothing). Stack notes: `docs/live/NOTES.md`; the older tracker:
`docs/live/PROGRESS.md`; bench reports: `../back/bench/recording/RESULTS.md` (egress engines) and the perf2 report
summarised in D-097 (its scripts are still in the old session's scratchpad: commit a copy under `../back/bench/live/`
when it is re-run).

Rules that still hold: never touch production data / credentials / accounts; no paid services or infra changes
without asking; never force push; secrets are never printed or committed (the owner pasted a partial
`.env.production` earlier — rotate list in §5). Backend changes go in a worktree, never in the running `../back` tree
(the dev API hot-reloads). UI quality is the owner's top priority: render (`test/visual`) and look at the PNGs.

## 1. Recording: the teacher's device records (owner's decision, D-098) — make it cheap for the server

**Decision.** Course sessions record on the teacher's device (`RECORDING_MODE=client`, already the value in
`../back/.env` and `.env.production`; the super admin's Live settings switch, D-089, can still pick `server` per new
run). Reason: no recording CPU on the shared 12-vCPU server during classes (the GStreamer composite would cost ~0.5
core per concurrent recording, the Chrome one 1.5 — and production's Chrome egress under `cpus: 1.5` loses ~80 % of the
audio, so server mode must not be switched on in production before §1.6).

**The hidden server cost.** Device chunks are assembled after the class by `../back/services/local_recorder.py`
(`assemble_and_upload`): concat, then re-encode into THREE quality tiers with `libx264` (`h264_nvenc` / `h264_qsv`
only if present — production has no GPU), and `FFMPEG_THREADS` defaults to `os.cpu_count()` — i.e. every core of the
server, while other classes may be live. Tasks, in order:

1. **Measure first.** A 60-min Android chunk set (and a web `webm` one) through `assemble_and_upload` on the dev stack:
   wall time, CPU-seconds, peak cores, per tier. Write the numbers to `../back/bench/recording/CLIENT_ASSEMBLY.md`.
2. **Never starve live classes:** default `FFMPEG_THREADS` to 2 (env still wins), run ffmpeg under `nice -n 19` /
   `ionice -c3`, and ONE assembly at a time (a DB / Redis lock or the existing job queue); a queued job shows
   "Processing" to the teacher as today.
3. **Fewer encodes:** produce ONE tier by default (the device's own resolution, `RECORDING_QUALITIES`-style setting for
   client mode, a super-admin field in Live settings next to the recording mode), and the extra tiers only on demand /
   at night. When every chunk is already H.264 + AAC in MP4 (Android `MediaRecorder`, iOS), concat with `-c copy`
   (remux, ~2 s for 3 min on the bench) instead of re-encoding; keep the re-encode for web `webm` and mixed audio-only
   / multi-audio-track chunks (the amix path in the file header).
4. **Teacher device load:** check on the S24 and a weak Android that recording + publishing does not lower the stream
   (CPU, thermal, the publisher's own resolution drop): if it does, record at the stream's resolution / 15 fps, and let
   the media plan (`live_media_plan.dart`) drop the recorder's quality before the published layers.
5. **Lost tail:** a killed app loses the chunk in flight; confirm the chunk interval and that `recording_sweeps.py`
   assembles an abandoned run; show the teacher "recording saved up to hh:mm" after a crash.
6. **Server mode stays the fallback** (important sessions, weak teacher devices). Before ANY production use: egress
   v1.8.3 → v1.15.0, `../back/deploy/egress.production.yaml` (`enable_template_sdk: true`, cpu_cost), ≥ 2 CPUs for
   egress, backend deploy (migration 0030 stores each run's mode). Owner's action; prepare the commands if asked.

Docs to update when done: `../back/CLAUDE.md` (Live sessions / recording), D-098, `docs/live/recording_design.md`,
the features guide if the teacher sees something new.

## 2. Live performance follow-ups (perf2 bench, D-097)

1. Confirm `allow_pause: false` on the S24 with a throttled link (1 Mbit/s, then healed): no full-video blackouts;
   the governor's 60 s first-strike release brings HD back.
2. Slow server-side recovery (6–11 fps for > 70 s after a dip, its estimate stuck at ~714 kbit/s): try a newer
   livekit-server (≥ 2 weeks old, compatible with egress 1.15) on the dev stack and re-run the "drop then heal" case.
3. The governor must keep relying on loss / frozen frames, not on the server's quality rating (it said "excellent" at
   30–50 % loss). A test that pins this.
4. Re-run the load bench on a QUIET host (no flutter_tester / Defender) to firm up the ~450 viewers per server figure;
   commit the bench scripts.

## 3. Device checks of round 5 (D-094 – D-096) — not yet seen on a device

- Presenter camera box for viewers over a share / whiteboard (drag, ⋮ size / circle, – to a name pill, other cameras
  as circles); an Android presenter sharing the whole screen from another app keeps a moving camera (the
  `ScreenCaptureService` now adds the `camera` foreground-service type; the next Play Console release needs the
  camera FGS declaration). iOS cannot keep the camera in the background.
- Top row (D-095): one line (LIVE + time = info, countdown, network, lock, recording, full view, minimize); the
  recording menu (Pause / Resume; Stop for a meeting creator); full view + its exit (tap, Esc, F, back).
- Whiteboard (D-096): the hand tool, mouse / one-finger pan, Space / middle-button pan, edge auto-scroll while drawing.
- Re-render the older `test/visual` whiteboard goldens (Select is now an arrow icon); the 390 px bar label
  "Stop S…" is cut — give it a shorter label.

## 4. Open owner decisions (ask, don't guess)

Self-view default when alone in client recording mode ("fill the screen while I'm alone"); does a minimized room
expand by itself on a share request; must a co-host ask to share; does the overlay's Close clear the drawings; the
bronze accent on the sign-in screen; which server the phone used during the Google Drive 400.

## 5. Production actions (the owner's; prepare commands only)

Deploy the backend (migrations 0029 biometric, 0030 recording mode); merge `../back/deploy/livekit.production.yaml`
(`allow_pause: false`, raise the UDP buffers); Google Drive env keys + the exact redirect
`https://nextbrain.site/api/api/v1/cloud/oauth/google_drive/callback`; rotate the secrets the owner pasted (Telegram
token, webhook secret, WhatsApp verify token, the exam / RAG DB passwords; NOT the MFA / evidence encryption keys
without a re-encryption plan); Play Console camera FGS declaration; egress upgrade only if server mode is wanted (§1.6).

## 6. Other follow-ups

`OrgMembershipProvider` / `TeacherCourseScreenProvider` used after dispose; the "Not enrolled" call after a session
ends; `test/org/live_events_soak_test.dart` timing flake; analytics period history (server); complaints paging + the
org timezone; iOS test on the owner's Mac (`docs/live/ios_test_plan.md`); the Kotlin Gradle plugin's built-in Kotlin
migration; CLAUDE.md lines for per-tab navigation (D-081) and the new pages; `docs/live/PROGRESS.md` brought up to
date; remove the old agent worktrees (`.claude/worktrees/`, `git worktree prune`) and the back worktrees in the old
scratchpad.
