# Live hardening: progress (resume here)

Branch `feature/live-hardening` in both repos (cut from `feature/platform-polish`); everything is merged into
`organizations` in BOTH repos at the end (owner's rule). Decisions: D-078 (keep LiveKit + server recording), D-079
(annotation). Audits: `docs/live/audit/`. Stack notes: `docs/live/NOTES.md`.
WebRTC fork: branch `nextbrain/1.6.2-hotfix.4` (from upstream `v1.6.2+hotfix.4`) PUSHED to
github.com/Amadkour/flutter-webrtc at 3806a48 (owner OK 2026-10-29); pubspec.yaml pins that ref. Local clone
`D:\platform\nextbrain\flutter-webrtc`.
2-hour scope set by the owner (2026-10-29): FOLLOW-UP = recording-to-server code + production infra, whiteboard / polls /
Q&A / grid / audio-only, the full weak-network suite, device + Mac tests; `organizations` gets the code before device
tests.
Owner answers (2026-10-29): iOS written untested, tested later on the owner's Mac after deploy; annotation like
Zoom / Teams; breakout rooms + live captions deferred; meeting recordings move to the server only if server load and
screen-share quality are solved; production accounts are never used (local stack + demo accounts only).

## Resume after the reboot (2026-10-29, owner rebooted to remove `numproc 4` → 12 threads)
1. Docker Desktop up → `cd ../back; powershell -File scripts/dev/setup.ps1 -WithLive` (dev stack) and `docker start nb-pg`.
2. Task 6 (backend resilience + teacher controls) was STOPPED mid-way: big uncommitted diff in ../back (new
   routers/live_controls_router.py, livekit_webhook_router.py, services/live_lifecycle.py, live_claims.py,
   upload_tokens.py, chunk_store.py, recording_sweeps.py, live_controls.py, data/live_ops_models.py,
   migration 0028_live_ops.py, tests e2e_live_resilience.py / e2e_live_controls.py, edits to many live files,
   front test/contract snapshots). Its last step was "update the dev LiveKit config". Restart an agent to review the
   diff against the task-6 brief, finish, run every live e2e on SQLite + PostgreSQL, then commit.
3. Task 5 bench (../back/bench/recording, project nb-recbench) was STOPPED while building the publisher; no
   RESULTS.md yet; containers removed. Restart it on the now-12-thread machine (quiet, nothing else running).
4. Task 4 + the two room fixes (own camera twice → `_stageTracks`; Share for meeting hosts) are uncommitted in the
   front tree; waiting on (a) the owner's OK to push the fork branch, (b) device tests on the S24.

| # | task | status | evidence |
|---|---|---|---|
| 0 | machine check, stack, lk 2.19.2, phone (S24 Ultra, Android 16) | done | Windows sees 4 of 12 threads (owner to run bcdedit as admin) |
| 1 | audit (backend, Dart, Android, iOS + web) | done | docs/live/audit/*.md |
| 2 | phase 1 app fixes (18 items) | verified | front 0fbb5e8: analyze 0 warnings, 196 tests, debug APK, web build |
| 3 | phase 1 backend fixes (13 items) + host TTL units | verified | back c9047b3, 066ada3: e2e_live_hardening 156 checks on SQLite + PostgreSQL, all live e2e pass |
| 4 | Android share end to end: fork rebuild, share-only mode, repeated share, system audio, detail / motion, call handling + independent review fixes | done, NOT device-tested | fork pushed 3806a48 + 00e021c (review fixes), pinned in pubspec; D-080 soft mute |
| 5 | recording design (server egress: CPU + share quality) | research done (docs/live/recording_design.md); bench results pending; the code move to server recording is a FOLLOW-UP | |
| 6 | backend resilience + teacher controls API | verified | back 7b075fb, a10c12d (see above) |
| 7 | web share: tab audio, browser stop button, presets | done, NOT browser-tested | front working tree → committed with this row set |
| 8 | iOS: broadcast via flutter_webrtc socket, stop request, memory, AEC, app audio mix, recorder fixes, LocalDebugRecorder removed | written, NEVER compiled (Windows) | docs/live/ios_test_plan.md, ios_share_wiring.md (applied) |
| 9 | app resilience: background camera, Rejoin, connect retry, tile order, permission updates, upload token + epoch (Dart, Kotlin, Swift), LiveCallService | done, NOT device-tested | |
| 10 | features: teacher controls UI, annotation (D-079) + Android overlay, locked pill; whiteboard / polls / Q&A / grid / audio-only / consent = FOLLOW-UP | done (in scope part) | |
| 11 | load + weak-network tests | load run pending (bench/load); full weak-network suite = FOLLOW-UP | |
| 12 | docs (dev + ops), features guide, merge into organizations | todo | |
