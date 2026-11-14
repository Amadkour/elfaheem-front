# Live audit: backend (2026-10-29, read-only agent report; L1, L9 re-verified by hand)

Paths under `../back`. 0 critical, 7+ high.

| id | sev | file:line | issue | proposed fix |
|---|---|---|---|---|
| L1 | high ✔ | services/LiveKit_service.py:283-291, 1973-1979 | student / member tokens: can_publish all sources + data, 24 h — a student can screen share / publish over the teacher, composite egress records it | students `can_publish_sources=[mic,camera]`; screen share host-only (or teacher-granted) |
| L2 | high | live_guest_router.py:142-176 | moderation exists only for guests: no mute / remove / revoke-publish for students, no lock room, no end-for-all kick | host routes `/live/{kind}/{id}/participants/{identity}/{mute,remove,permissions}` + lock, reuse guest helpers |
| L3 | high | services/live_room_service.py:623-642 | a kicked guest re-polls their admitted request and gets a fresh token (no blocked_at / limit / PIN check) | check block in request_payload; mint once (mark consumed) |
| L4 | high | LiveKit_service.py:283-291; live_guest_service.py:174; livekit.yaml | tokens valid up to 24 h after kick / end; duration_hours unbounded (online_sessions.py:92); auto_create lets an old token re-create a deleted room | `room.auto_create: false`; short TTL + refresh; `le=` on duration_hours; kick = remove + block identity at mint |
| L5 | high | live_guest_router.py:56-60, 186-196; deploy/nginx/nextbrain.conf.example:48 | `_client_ip` trusts the first X-Forwarded-For (nginx appends) — spoofable: bypasses per-IP join / PIN limits (4-digit PIN brute force) and the kick IP block | X-Real-IP / last trusted hop; limits in Redis / DB |
| L6 | med | live_room_router.py:148-152 → live_room_service.py:533-546 | signed-in link join checks PIN with no failure limit | same PIN throttle per user + IP |
| L7 | high | LiveKit_service.py:1600 | `recover_stalled_recordings()` never called: restart mid-session loses egress lifecycle; rows stuck; end deletes room without finalizing | call in lifespan; egress_id in DB; reconcile tick with list_egress |
| L8 | high | services/scheduler_service.py:103 | auto-provisioning passes enable_recording=True, ignores session.record_enabled | `bool(session.record_enabled) and settings.is_server_recording` |
| L9 | high ✔ | routers/recorder.py:364-404 | recording-assembly-status: no access check — any signed-in user gets any session's recording_url (bypasses enrollment + exam gate) | teacher / enrolled check + `_assert_exam_gate` |
| L10 | med | online_sessions.py:125-154 vs live_room_service.py:546, 642 | link_join / poll_member call get_student_join_url directly, skipping exam gate, assert_course_open, enforce_live_session_limit | move gates into get_student_join_url |
| L11 | med | LiveKit_service.py:1757-1870; 1950-1954 | no lock on start: double tap → two rooms / rows / egresses / notifications; join takes `.first()` without order_by | row / advisory lock or partial unique index; order by id desc |
| L12 | med | LiveKit_service.py:1851 | host vanishes → LiveKit closes room, OnlineSession.is_active stays True, join keeps minting, auto_create revives a zombie room | LiveKit webhooks (room_finished / participant_left / egress_ended, verified) or reconcile tick |
| L13 | med | LiveKit_service.py:1855 | max_participants = enrolled+5 fixed at creation; guests / late enrollments → "room full" | include link max_guests + staff, or UpdateRoom |
| L14 | med | LiveKit_service.py:1393-1403 | egress picks first non-guest publisher as "teacher": a publishing student drives layout + share-audio sidecar | use host identity `teacher_{course.teacher_id}` |
| L15 | med | LiveKit_service.py:1975-1979 | teacher joining via /join gets `student_{id}` (admin) while lobby host_identity is `teacher_{id}`: host presence wrong, teacher can appear twice | `teacher_{id}` when is_teacher |
| L16 | med | LiveKit_service.py:1986-1989 | attendance recorded at token mint, not at connect; no checkout without /leave | webhooks or list_participants reconcile |
| R1 | high | routers/recorder.py:294-328 | client chunks stored as chunk_{index} with silent overwrite; index resets on teacher reconnect → earlier footage overwritten | prefix with client epoch / server arrival seq |
| R2 | high | manager/state_manager.py:106 | Redis watchdog flag has no TTL, task in-process: after restart never assembled; /end waits 150 s | TTL refreshed per chunk + scheduler sweep |
| R3 | med | state_manager.py:74; local_recorder.py:293-300 | assembly lock 15 min while ffmpeg has no timeout: double assembly / hung forever | refresh lock, ffmpeg timeout, worker queue |
| R4 | med | local_recorder.py:1261, 383-397 | FAILED assembly leaves chunks forever, no retry route; late chunks may trigger second assembly (unverified) | retention sweep, retry endpoint, refuse chunks once assembled |
| R5 | med | recorder.py:296; live_recording_router.py:134 | whole chunk read into memory, no size cap; session recorder ignores record_enabled / is_active | cap + stream to disk; check switch + active row |
| R6 | med | services/live_recording_service.py:253-283, 628-640 | meeting recording idle timer is a process-local threading.Timer; after restart a `recording` row is never recovered → 409 recording_active forever | recover_stuck covers stale `recording` rows |
| R7 | low | live_recording_service.py:542-552 | finalize check-then-set: idle timer + is_final can both assemble | conditional UPDATE recording→assembling |
| C1 | low | online_sessions.py:197-230 | client-mode /end sleeps up to 150 s BEFORE the ownership check — any teacher can tie up the threadpool | ownership first; 202 + job |
| C2 | low | online_sessions.py:81-122 | start lacks assert_course_open + kill switch; only course.teacher_id may start (TAs / co-teachers 403) | add checks + session_access roles |
| C3 | low | all live files | no audit log, consent, retention, metrics; only rate limit is the concurrent-room limiter | audit(), retention setting, counters, per-user mint limit |
| C4 | low | scheduler_service.py `_reminded`/`_started`; guest `_hits` | in-process sets: duplicates / misses with >1 worker or restart | DB / Redis claims |

## Inventory (exists)
Course session: POST /live-sessions/start, GET /{id}/join (202 lobby), GET /{id}/participants (DB roster), POST /{id}/leave, POST /{id}/end?save_recording, GET /{id}/recording, GET /{id}/force_attend (state-changing GET). Client recorder: POST /{id}/recording-chunk, GET /{id}/recording-assembly-status. Guest link CRUD + joins; guest moderation (mute-all, kick+block, mute, allow-speak) — the only server participant controls. Rooms: policy, link, lobby admit / reject / admit-all; joiner link join + request polls. Meeting recordings (cloud) routes; SSE events; scheduler ticks (provision / remind / start, recording retry, live plan, renew).
Missing: student mute / remove / permission change, room lock, screen-share allow / deny, LiveKit webhook endpoint.

## Existing tests (tests/org_v2)
e2e_live_guest_link, e2e_live_lobby, e2e_session_record_flag (not the scheduler path), e2e_meeting_recording, e2e_points_live_plan, e2e_live_events, g3_live_offloop, e2e_auto_captions. None for: real LiveKit / egress lifecycle, local_recorder assembly, concurrent start, restart recovery, assembly-status access, token reuse after end / kick.
