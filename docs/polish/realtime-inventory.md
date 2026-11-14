# Track D analysis — polling inventory and real-time plumbing (2026-10-28, read-only)

Kind: **ND** = checks for new data · **JP** = progress of a job the user waits on · **C** = client-only tick (no HTTP).

## App polling sites

| file:line | route | interval | lifecycle | kind | push trigger today |
|---|---|---|---|---|---|
| core/attention/attention_service.dart:101 | GET /me/attention (+ `?org_id` → 2 calls) | 60 s (min gap 5 s, 15 s throttle on route change) | only while a badge listens; resume + every route change | ND | only `LiveEvents.silentTypes` (complaints/transfers/payments/payouts); not lobby, attendance, session, visible types |
| features/live/live_lobby_sheets.dart:120–188 `LiveLobbyController` | GET /live/{kind}/{id}/lobby | 15 s in room, 4 s with LobbySheet open | host, while RoomPage mounted | ND | silent `live_join_request` + resume |
| features/live/live_lobby_sheets.dart:1010–1048 `WaitingForHostPage` | GET /live/requests/{id} / public poll | server `poll_after` (3 s, 1–30) | while waiting | JP | none (admit/reject not pushed) |
| shared/guest/guest_live_page.dart:160 | GET /public/live/{token} | 10 s until live; 60 s after 429 | page open | ND | none (no FCM token) |
| features/live/room/room.dart:1288 `_pollActiveQuiz` | GET /courses/{id}/exams/active | 30 s | students, whole room visit | ND | none (LiveKit data topics exist) |
| features/sessions/material/components/session_material_grid.dart:1283 `_CaptionsAction` | GET /sessions/{sid}/materials | 8 s while captions pending | per tile | JP | none |
| student/dashboard/component/student_exam_tab.dart:43 | GET /student/exams/upcoming | 5 min | tab mounted | ND | none |
| org/org_providers.dart:422 `OrgScheduleProvider._follow` | GET …/schedules/{sid}/runs/{rid} | 2 s; stops after 5 misses / 4 min | while a run is followed | JP | none |
| org/org_registrar_member.dart:160 | GET …/register-requests/{id} | server `poll_after_ms` | after cart submit | JP | none (outbox `registration.processed` not fanned out) |
| shared/rag/rag_chat.dart:287 `RagApi.waitFor` | GET /rag/queries/{id} | 1 s → 4 s, 3 min | per question | JP | none |
| features/exams/exam_generate.dart:222 `waitFor` | GET /rag/exam-drafts/{id} | 1.5 s → 5 s, 4 min | per draft | JP | none |
| features/exams/exam_insights_screen.dart:415 | GET …/exams/{id}/analytics | 2 s × ≤ 30 | after Refresh | JP | none |
| shared/rag/rag_library_screen.dart:89 | GET /rag/documents | 5 s while a document is busy | screen open | JP | none |
| shared/profile/privacy_export.dart:289 | GET data-export status | 5 s while processing | page open | JP | none |
| features/live/meeting_recording_sheets.dart:332, 753 | GET /me/cloud (OAuth wait) | 3 s | sheet open | JP | none |
| features/live/meeting_recording_sheets.dart:544 `RecordingStatusCard` | GET /live/recordings/{rid} | 5 s while not final | detail open | JP | none (`recording_ready` visible only) |
| student/enrollment/enrollment_provider.dart:631 `_pollVerification` | POST payment verify | 5 s × 18 | after checkout | JP | none (`payment_success` visible push exists) |
| auth/verified_screen.dart:477 `_pollLink` | checkPhoneLink | 2 s | QR shown | JP | none |
| features/attendance/teacher_attendance_controller.dart:313,324, …_provider.dart:115 | attendance code / roster `_sync()` | 5 s | attendance screen | ND | students get silent pushes; teacher roster polls |
| teacher/home/queue_work_items.dart:108 | none (old 10 s poll commented out) | 10 s tick | teacher home | C | — |
| clocks / countdowns / local saves (ads slider, calendar 1 min, exam timers, video position 5 s, room clocks, mic meter, announcements visibility 700 ms) | no HTTP | — | — | C | — |

Not polled at all (pull-to-refresh only): unified inbox, notification list, org dashboards, governance lists, calendar feed.

## Backend real-time today

- FCM only: `services/fcm_push_service.py` (`send_push*`, `send_silent_to_tokens`, `send_data_push_to_all_users`; tokens in `FCMToken`, device_types android/ios/web).
- `services/live_update_service.py` `push_live(...)` events `complaints_updated`, `transfers_updated`, `payments_updated`, `payouts_updated`; only transfers/payments ever sent (`manual_transfer_service.py:180–301`) plus `live_join_request` (`live_room_service.py:717`). `complaints_updated` / `payouts_updated` have no sender; app `LiveEvents.complaints` has no subscriber (only `admin_finance_provider.dart:145` listens).
- Other silent pushes: `disable_list_updated` (broadcast), `theme_updated`, attendance `attendance_opened|closed|location_request`.
- Visible pushes used as nudges: `complain`, `transfer_review`, `session_started|session_ended`, `admin_message`; ~80 other types are tap-only.
- `attention_service.py` TABS: home, profile, parent.link, parent.alerts, admin.support, admin.finance, org.people, org.academics, org.timetable, org.services, org.settings.
- No WebSocket / SSE anywhere (only byte `StreamingResponse`s). LiveKit data packets are client-to-client only (`reaction`, `hand`, `chat`); the server never publishes.
- Infra: one uvicorn process per service (core :8000, exam :8001, rag :8002); Redis present (Celery, read cache `services/jobs/cache.py`, outbox stream `nb:events`, consumer group `core`, only `registration.processed` + exam topics). nginx `/api/` has `proxy_buffering off`, 600 s; exam/rag 300 s with buffering; `/livekit/` already upgrades.
- Firebase RTDB: `database.rules.json` is dead config (`firebase_database` not in pubspec).
- Web: FCM via VAPID; foreground `onMessage` handles data pushes only when Notification permission is granted. `web/firebase-messaging-sw.js:33` shows a notification for EVERY payload (no `data.type` filter) and never `postMessage`s the page: a data push in a background tab is lost and pops an empty notification.

## Recommended design (to implement in Track D)

1. **SSE** `GET /api/v1/me/events` on the core (`text/event-stream`, heartbeat comment every 25 s, `Last-Event-ID` replay from a short Redis list, `X-Accel-Buffering: no`). Publish through Redis pub/sub `nb:live:{user_id}` so other workers and the exam / rag services can emit.
2. Auth: EventSource cannot send headers and bodies are enveloped → stream with `package:http` `send()` (works on web via fetch, `Authorization` header allowed), plain events; a short-lived `?t=` ticket as fallback.
3. One server emitter `live_update_service.emit(user_ids, event, data)` sending BOTH silent FCM and SSE, granular names: `attention_changed{tab,org_id}`, `work_item_updated{id}`, `council_updated`, `lobby_updated{kind,id}`, `join_decided{request_id,status}`, `job_updated{kind: schedule_run|rag_query|exam_draft|caption|export|recording|registration, id, status, stage}`, `quiz_started{course_id}`, `session_live{session_id}` + the existing `*_updated`. Wire `complaints_updated`.
4. App: `LiveEvents` is the single bus for FCM + SSE; a `LiveEventsClient` opens the stream when a token exists and the app is in front (reuse `AttentionService` start/stop + `WidgetsBindingObserver`), closes in background; dedupe by server `event_id` (last 200). `AttentionService` subscribes to `attention_changed` and stretches its poll to 5 min while connected (60 s fallback).
5. JP polls become "poll only when no stream": WaitingForHostPage, `_follow`, `RagApi.waitFor`, `exam_generate.waitFor`, captions, recording card, registrar; each listens for `job_updated` with its id and keeps its timer as a 3–5× slower fallback. Student quiz poll → LiveKit data message from the teacher's client.
6. Web background tab: service worker skips `showNotification` when `payload.notification` is absent and `postMessage`s data to open clients.
7. Leave as is: clocks, exam autosave, upload progress, version check, guest page, exam-tab banner (use the exam-reminder push).
