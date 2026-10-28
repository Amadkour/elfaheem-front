# PROGRESS.md — platform audit · dashboards · real-time · parity · RAG overhaul

Single source of truth for the multi-session job started 2026-10-28 (brief: "Platform Audit, Dashboard Redesign,
Real-Time Refresh and RAG Chatbot Overhaul"). **On every resume: read this file first, then continue the first
task that is not `done`/`verified`. Never redo finished work.** The older `docs/PROGRESS.md` is the phase log of the
2026-10-24 RBAC/exams/RAG refactor and stays as history.

Repos: app `nextbrain-front` (this), backend `../back`. Branch in BOTH: `feature/platform-polish` (from
`organizations`, created 2026-10-28; CI runs on `feature/**`). Commit small and often, in both repos.

Status values: `todo` · `in progress` · `done` (code written, not yet verified) · `verified` (test or measurement
recorded below) · `blocked (why)`.

## 0. Execution order (from the brief)

| # | Step | Status |
|---|---|---|
| 0.1 | Safety net: branch `feature/platform-polish` in both repos | done |
| 0.2 | Analysis phase, no code changes → §1 findings, §2 parity matrix, §3 baselines | done (2026-10-28) |
| 0.3 | Track A1 security and auth fixes | done (verified by tests; see owner actions) |
| 0.4 | Track D real-time + push, remove polling | done (verified; 3 backend emits pending) |
| 0.5 | Track C feature parity | done (verified) |
| 0.6 | Track B design system + dashboards + screen polish (A2) | in progress (B.1 app + backend aggregates agents) |
| 0.7 | Track E RAG overhaul (parallel with 0.4–0.6) | in progress (E.1 eval baseline agent running) |
| 0.8 | Final verification: full test run, re-measure baselines, final report (§6) | todo |

## 1. Findings (ranked by severity) — filled by the analysis phase

Detailed per-track analyses live in `docs/polish/` (read only the one for the track you are on):
- `docs/polish/realtime-inventory.md` — Track D: every polling site, the backend's FCM-only plumbing, the SSE + `LiveEvents` design. Key facts: no WebSocket/SSE exists; `complaints_updated` is never sent; web service worker shows an empty notification for every data push and drops it for the page; admit/reject is never pushed to the waiting participant.

- `docs/polish/screens-parity.md` — Track C: route table, parity matrix, list screens without pull-to-refresh, dark mode / breakpoint facts.
- `docs/polish/auth-security.md` — Track A1: flow map, findings S1–S17 with file:line and fix, existing tests, open questions.
- `docs/polish/dashboards.md` — Track B: per-dashboard structure / data / weaknesses, backend feeds, 10 shared problems, what the redesign builds on.
- `docs/polish/rag-pipeline.md` — Track E: layer-by-layer exists / missing / wrong, facts (models, numbers, routes), ranked 8-step plan.

### Ranked problems (all tracks)

**Critical / High**
1. [A1-S1] `PUT /auth/me` stores a raw phone: no normalisation / uniqueness, `phone_verified` kept → lockout of another user's phone login, or "verified" with an unverified number.
2. [A1-S2] `POST /auth/register` has no throttle; each call creates a user and sends e-mail / paid SMS.
3. [A1-S3] `OTP_PROVIDER` defaults to `log`: unset in production = every phone OTP in the server log.
4. [E] No curated Q&A layer, no answer cache, prompt budget too large (4 × 1200 chars, up to 100 reranker pairs) → every question costs retrieval + 9–15 s generation; answers wrong / vague on the 0.6B.
5. [D] Only FCM; no SSE / WebSocket; 7 new-data polls + 12 job-progress polls; web background tab drops data pushes and shows empty notifications.

**Medium**
6. [A1-S4..S10] unverified-account squatting; onboarding e-mail fallback on by default; account enumeration via 404s; unthrottled phone-link start / status; web tokens in localStorage with no CSP; delete / phone change without re-auth and without revoking refresh tokens; unthrottled crypto handshake fills Redis.
7. [B] Dashboards: whole-shell `setState` per attention tick; 5–9 uncoordinated self-fetching widgets per home; no aggregate for student / parent; no charts / trends; counts drawn 2–3×; ~60 hard-coded colors; key actions 2–3 taps deep; teacher home has no error state, parent uses an empty state as loader.
8. [C] Calendar unreachable for teacher / parent / admin; pull-to-refresh missing on ~17 list screens; three breakpoint systems; mic meter web-only; PiP Android-only.
9. [E] No chat sessions (implicit 2 h window), no retention, no streaming, `GLOSSARY` / intent rules hard-coded, Postgres path lacks real BM25, no answer-quality eval.

**Low**
10. [A1-S11..S17] password policy ≥ 6; MFA roles empty by default; cached user never refreshed (`getMe()` unused); local-only logout keeps the refresh family; per-IP login lock behind NAT; 429 on refresh logs out.
11. [D] `complaints_updated` never sent; `database.rules.json` is dead config.
12. [C] Boot splash follows OS brightness, not the user's toggle.

## 2. Parity matrix (feature × Web / Android / iOS)

Full matrix in `docs/polish/screens-parity.md` §B. Unexplained gaps to close (Track C):
1. Calendar has no plain entry for teacher, parent and admin on any platform (student: top bar; org admin: dashboard button).
2. Pull-to-refresh missing on ~17 list screens (notifications, calendar, org courses / people / schedule hub / studio / today / changes, section hubs, exams section, attendance, subscription, RAG chat / console, admin services hub, MFA page); admin tabs only get a refresh button in the phone shell.
3. Pre-join mic level meter is web-only (mobile stub returns 0).
4. Picture-in-Picture is Android-only (iOS missing).
5. Web foreground push is a snackbar only (browser Notification call commented out); background-tab data pushes are dropped by the service worker.
6. Three breakpoint systems (450/800/1920, 700/900/1200, 900 vs 1000 shells); rail shell is web-only.
7. Boot splash follows OS brightness, not the user's dark-mode choice.
By nature (recorded, no action): offline downloads / exam sittings, QR scan (could be enabled on web with mobile_scanner), nearby / BLE attendance relay, native recorders, native payments, pickers, share sheets, keyboard shortcuts, Crashlytics.

## 3. Baselines (before)

| Measure | Before | After | How measured |
|---|---|---|---|
| `flutter analyze` warnings / errors / infos | 0 / 0 / 245 | | `flutter analyze --no-fatal-infos --fatal-warnings` (2026-10-28, HEAD 74cfdc7) |
| App test suites | 925 passed, 0 failed; contract: 1129 calls, 0 unknown, 72 unresolved | | `flutter test test/org/ test/export/ test/ui/ test/auth/ test/contract/` |
| Backend static gate | 8 ruff errors (pre-existing) | | `ruff check .` in `../back` |
| Polling call sites / intervals | 7 new-data polls (attention 60 s, lobby 15/4 s, guest 10 s, quiz 30 s, exam tab 5 min, attendance 5 s) + 12 job-progress polls (1–8 s); 0 SSE/WS | SSE stream + silent FCM; attention 5 min, lobby 60/16 s, quiz 0 (LiveKit + event, 5 min fallback), exam tab 0, attendance 30 s; job polls 10–30 s fallbacks only while the stream is down | `docs/polish/realtime-inventory.md` |
| RAG eval, 71 q (`bench/rag/answer_eval`, laptop, shared CPU) — extractive | correct 52% (28/54) · found 65% · retrieval@5 96% · not-found 100% · small talk 0% · injection 100% · halluc 0 · leaks 0 · p50/p95 3.0/4.8 s · RSS 1.9 GB | | `run_answer_eval.py --generator none` |
| RAG eval AFTER E.3 — extractive | correct **82 %** (44/54, was 52 %) · found 83 % · retrieval@5 96 % · not-found 100 % · small talk **100 %** (was 0 %) · injection 100 % · halluc 0 · leaks 0 · p50/p95 2.6/4.2 s | | `results/20261027-232904-none.json` |
| RAG eval AFTER E.3 — qwen3-0.6b | correct 59 % (32/54; generation misses 13) · found 83 % · small talk 100 % · halluc 0 · leaks 0 · p50/p95 15.8/38.8 s (was 22/44) | | `results/20261027-235030-qwen3-0.6b.json` |
| RAG eval — qwen3-0.6b INT4 light | correct 59% (32/54) · found 78% · retrieval@5 96% · not-found 100% · small talk 100% · injection 100% · halluc 0 · leaks 0 · p50/p95 22/44 s · RSS 4.2 GB · 17/48 writer calls failed · ar 52% / en 64% | | `run_answer_eval.py --generator onnx --model qwen3-0.6b` (25 min) |
| Dashboard requests on open | pending | | count of API calls per dashboard open |

## 4. Task board

| Id | Track | Task | Status | Changed | Verified by | Next step |
|---|---|---|---|---|---|---|
| A1.1 | Auth | S1 phone change: normalise, 409 `PHONE_TAKEN`, reset `phone_verified` + OTP (`phone_verification` in the answer); S9 `password` (+ `code` for MFA) on `PUT /auth/me` phone change and `DELETE /auth/me`, deletion bumps `token_version` + revokes refresh tokens | verified | back 2dc8225 | `e2e_auth_hardening.py` 10/10 + 9 auth / MFA scripts pass | Google-only accounts must set a password (forgot-password) before delete / phone change |
| A1.2 | Auth | S2 register 20/h per IP; S7 phone-link start counted as resend, status 30/15 min; S10 handshake 300/15 min per IP, session TTL 12 h → 2 h | verified | back 2dc8225 | same | |
| A1.3 | Auth | S3 `OTP_PROVIDER` unset / `log` refused outside development / test; S5 `TEACHER_ONBOARDING_EMAIL_FALLBACK` default false; S12 `MFA_REQUIRED_ROLES` default `super-admin,admin` in production / staging (explicit empty = opt out) | verified | back 2dc8225 | same | **DEPLOY BLOCKER: see §5 owner actions** |
| A1.4 | Auth | S4 never-verified sign-ups re-owned on register (201, same user id, squatted phone released); S6 unknown identifiers answer uniformly (verify / reset → 400 `otp_invalid`, resend / forgot → 200) | verified | back 2dc8225 | same | residual: forgot-password by phone lists the real account's e-mail way too (bounded by throttles) |
| A1.5 | Auth | S11 `check_password_policy` ≥ 8 + 34 common passwords → 400 `WEAK_PASSWORD`; app rule ≥ 8 | verified | back 2dc8225, front e33a3c5 | same | |
| A1.6 | Auth (app) | S14 `getMe()` after bootstrap; S15 server logout on every path; S16 429 on refresh transient; S8 CSP on hosting (D-060); re-auth sheet for delete / phone change; phone change re-verifies by OTP; password ≥ 8; codes `WEAK_PASSWORD` / `PHONE_TAKEN` / `REAUTH_REQUIRED` mapped | verified | e33a3c5 | `flutter test test/auth/ test/contract/` 65 passed; analyze 0/0 | layout test for `reauth_sheet.dart` pending; check the CSP in the browser console after the first web deploy |
| A1.7 | Auth | `tests/org_v2/e2e_auth_hardening.py` (10 checks); app `refresh_429_test.dart`, `password_rule_test.dart`, `reauth_sheet_layout_test.dart` | verified | | | phone-change → OTP step end-to-end on a running stack not yet exercised (unit-level only) |
| A2 | Frontend | Screen-by-screen audit and polish on web / Android / iOS | todo | | | after B |
| B.0 | Dashboards (back) | `GET /admin/overview` + organizations / series[30] / alerts / realtime, `expire_due` off the read path, money cached 60 s; org dashboard + members / pending_total / series; NEW `GET /me/home` (today, upcoming, attention, inbox preview, unread, courses_progress or teacher block + earnings, org_overview); NEW `GET /parent/overview` | verified | back 6e03e7f, front f45a7b9 (snapshot) | `tests/org_v2/e2e_dashboards_aggregates.py` 27 checks + 8 regression scripts | RAG worker alerts stay in the RAG console; drop `CACHE_KEY_MONEY` on manual-transfer approval if live money is wanted |
| B.1 | Design | `lib/design/app_shell.dart` (AppShell for all five roles, `DashboardItem.attentionKeys`, `ShellBadge` leaf — no shell `setState`), hero tokens `onHero` / `heroGlass` / … derived from the server palette (`theme_config_provider.dart`), `app_charts.dart` (sparkline, bars, donut, trend tile, legend; OKLab-snapped palette validated with the dataviz checker), `app_settings.dart` (grouped, searchable past 8 tiles; admin + parent More ported); dashboard hero files 0 hard-coded colors (lib/features total 1284 → 1233) | verified | e317d5f (D-062, D-063) | `test/ui/ test/org/ test/contract/` 940 passed; analyze 0/0 | sidebar 240 → 220; org timetable badge = feed item count |
| B.2 | Dashboards | Super Admin home: pulse trend tiles from `series`, alerts + pending queue drawn once, charts row, health, hub shortcuts; one cached call refreshed on open / resume / pull / events | verified | 27a1290 | `admin_overview_test.dart` 12, `admin_home_layout_test.dart` | tile delta = last 15 d vs previous 15 d (series has 30 rows) |
| B.3 | Dashboards | Org Admin home (`org_dashboard_home.dart` / `_model` / `_settings` split): members hero, queue first with `pending_total` once, trend tiles, one-tap shortcuts into section + chip, department return reloads only when attention changed | verified | b0698ca | 1079 tests (ui / org / contract / auth / export) | |
| B.4 | Dashboards | Student + member homes on `GET /me/home` (`lib/core/home/me_home.dart`): next-up hero, this week, continue learning, grouped quick actions, older-server fallback | verified | b0698ca | same | |
| B.5 | Dashboards | Teacher home: error / retry, earnings + pending from `/me/home`, overflow-safe live queue; Parent: Today tab on `/parent/overview`, skeleton, app_kit empties | verified | b0698ca | same | `legacy_stats_row.dart` kept (instructor profile uses `StatsRow`) |
| B.6 | Frontend (A2) | Screen-by-screen polish in 3 areas: auth + shared, learning, org + admin sub-pages (`docs/polish/screen-audit-*.md`) | in progress (3 agents) | | | |
| C.1 | Parity | `lib/design/calendar_entry.dart` (`CalendarEntryIcon` in HomeHeader / app bars, `CalendarEntryTile` in More / profile) for teacher, parent, admin; key `calendar.entry` in the catalog | verified | front C commit | `test/ui/app_refresh_layout_test.dart` (tap opens /calendar, kill switch hides) | features-guide entry pending |
| C.2 | Parity | `lib/design/app_refresh.dart` (`AppRefresh`, `AppRefreshAction` for web / desktop) on notifications, calendar, studio list tabs, member today, exams section, subscription, admin hub, MFA page; org courses / people / hubs already had it via `PagedList` | verified | same | 303 ui / contract / widgets tests | skipped: attendance sheets (private `_sync`), rag chat / console (Track E) |
| C.3 | Parity | `lib/design/app_responsive.dart` is THE breakpoint set (phone < 700, rail 700–999 on every platform, wide ≥ 1000; D-061); all five shells use it; `SplashTheme` reads the cached dark-mode key before the first frame | verified | same | `test/ui/app_responsive_test.dart` | |
| C.4 | Parity | Mic meter on Android / iOS via `livekit_client` `createVisualizer` on the pre-join local track (no new package); web foreground push → browser `Notification` popup (click routes through `AppNavigator`), toast only as fallback; iOS PiP deferred (D-061: `floating` is Android-only and `video_player` exposes no AVPlayerLayer) | verified (unit) | 1a44707 | `test/ui/prejoin_layout_test.dart` 17 passed; analyze 0/0 | **needs a device check:** meter scale on a real phone (calibrate `micLevelFromBands`), browser popup + click routing in Chrome / Safari |
| D.1 | Real-time (back) | `helpers/live_bus.py` + `services/live_events.py` (`emit` = silent FCM with `event_id` + Redis pub/sub, 100-event replay, catalogue at the top of the file) + `routers/live_events_router.py` (`GET /api/v1/me/events` SSE, heartbeat 25 s, lifetime 3000 s, `?t=` ticket); exam / rag `publish_live`; hooks in 14 services; stream excluded from envelope / rate-limit / subscription guards; nginx location | verified | back b24dca2; front 82ee4a8 (snapshot) | `tests/org_v2/e2e_live_events.py` 34 checks on local Redis + 16 regression scripts pass | `.env.example`: `LIVE_EVENTS_HEARTBEAT_SECONDS=25`, `LIVE_EVENTS_MAX_SECONDS=3000` (add once the auth agent releases the file). Skipped hooks: expiring memberships (date-driven), RAG mid-answer stages, document `processing`, `live_join_request` expiry |
| D.2 | Real-time (app) | `lib/core/live/live_events_client.dart` (SSE over `package:http`, token × foreground × binds, backoff 1→30 s, `Last-Event-ID`, 90 s stall watchdog, 401 → ticket, dedupe 200 ids); FCM data pushes go through the same `ingest`; `AttentionService` listens to `attention_changed` + `*_updated`, polls 5 min while connected; service worker relays data pushes to the page | verified | 9820998 | `test/org/live_events_client_test.dart` 29 passed; analyze 0/0 | optional: `LiveEventsClient.instance.sessionChanged()` in `MyAuthProvider.completeSession` for an instant reconnect at login |
| D.3 | Real-time (app) | `lib/core/live/event_wait.dart` (`EventOrPoll`, `JobWatch`, `pollInterval` 4× while connected); every job-progress poll listens to `job_updated{kind,id}`; lobby / waiting page on `lobby_updated` / `join_decided`; quiz start over LiveKit topic `quiz` (`widgets/live_quiz.dart`) + server `quiz_started`; exam tab fetch on open / resume; attendance roster on `attendance_roster_updated` + 30 s fallback; payment wait ends on `payments_updated` | verified | 714d6e1 | `test/org/` 610 passed (event_wait 10, live_quiz, lobby controller), 44 ui tests; analyze 0/0 | backend emits `attendance_roster_updated`, `quiz_started`, `exam_analytics` — agent running |
| D.4 | Real-time | Tests: backend e2e for emit + SSE replay; app unit tests for the client (dedupe, reconnect) | verified | with D.1 / D.2 | `e2e_live_events.py`, `live_events_client_test.dart` | |
| E.1 | RAG | `bench/rag/answer_eval/` (71 q over the features guide, seeded terms / about, synthetic org rules; scores retrieval, correctness, hallucination, not-found, injection, leak, latency, RSS) | verified | back 5e522ca | §3 before rows | diagnosis: gate threshold 7.31 (calibrated on the synthetic bench) rejects 17 right answers whose top logit is −1.3…5.8 because ar/en twins split the margin; writer fails 17/48 calls; no small-talk path without the model |
| E.2 | RAG | `rag_service/qa.py` + `routers/qa.py` + migration `rag_0007` (RLS); match inside SQL before the planner; direct ≥ 0.955 (no model call), examples ≥ 0.91 (calibrated: 0/30 false directs); `/api/v1/rag/qa` CRUD, toggle, `from-query`; overview `qa` counters + `query_id` on not_found / unhelpful | verified | back dbbab24, front 2842b80 (`rag_qa_admin.dart`: list / sheet / promote-to-Q&A / console tab / library entry, key `rag.qa_admin`) | backend 8/8 + 7/7 PG; app `rag_qa_test.dart` + `rag_qa_layout_test.dart` 35 passed | chat side: open a `qa` citation's `deep_link`, label for stage `qa` (E.5) |
| E.3 | RAG | Gate recalibrated on both benches (`bench/rag/calibrate_gate.py`, ar/en twins as one section), extractive small-talk path, light budget cut + token guard, writer retry, answer cache `rag_0008` keyed by library version | verified | back ccbc1bc (committed by the owner as "RAG ENHANCEMENT") | rag e2e 14/14, qa 8/8, cache 7/7, premium 14/14, examgen 8/8, check_thresholds 27/27 | **finding: the 0.6B writer now LOWERS correctness (82 % extractive vs 59 % with the model; 13 generation misses) → E.6 decides the default by measurement** |
| E.4 | RAG | Real BM25 on Postgres + Arabic normalisation (`textnorm.py`); data-driven router (`rules.py`, `router_rules` setting, feature-guide deep links) | in progress (fresh agent after 3 network drops; continues from disk) | | | |
| E.5 | RAG | Chat sessions: app (front 2ea31da) + backend `rag_0009` conversations, `/api/v1/rag/conversations` CRUD + messages paging, `ask.conversation_id`, history per conversation, id-less asks join the scope's latest chat within 2 h (old app builds keep follow-ups), retention prune default 90 days (`conversation_retention_days`, D-064) | verified | back fe09c32, front 2e24732 | `e2e_rag_conversations.py` 9/9 SQLite + 8/8 Postgres, `pg_rls.py` 6/6, rag e2e / qa / cache / premium green | console field for retention (E.7 agent); conversations not in the privacy export yet; `tests/rag/migration_rag_0004.py` asserts head = rag_0006 (stale since rag_0007) |
| E.6 | RAG | CPU benchmark ONNX INT4 vs llama.cpp GGUF (0.6B / 1.7B, Q4/Q5) with load-gated timing; default chosen by eval; INT-only fetch | in progress (agent) | | | |
| E.8 | RAG | Streaming partial answers (generator → `queries.answer` / SSE `job_updated{stage}`), after E.4 / E.5 land (same pipeline files) | todo (queued) | | | |
| E.7 | RAG | `rag_service/monitoring.py` (SQL counters by path: cache / qa_direct / model / extractive; p50/p95 per path; rates; by_day), `not_found` grouped in SQL (407 → 24 ms), `GET /api/v1/rag/admin/monitoring/summary`; console health block, AI assistant card on the super admin home, retention field in the console | verified | back b082857, front 778451d | `e2e_rag_monitoring.py` 5/5 SQLite + PG; 63 app tests | `/overview` still ~570 ms on PG from the older loop for its other fields |
| A1.8 | Auth | Residual audit: device switch flow, imported temp passwords, IDOR sweep, whoami cache bust, nginx `limit_req` | in progress (agent) | | | |
| QA | QA | Final: tenant-leak suite across chunks / Q&A / cache / conversations, full suites both repos, re-measure baselines, final report §6 | todo (after all) | | | |
| GUIDE | Docs | Features-guide sweep (`../back/data/app_features_guide.json`): calendar entry (teacher / parent / admin), pull-to-refresh note, new dashboards, chat sessions — one edit at the end of Track B / E | todo | | | |

## 5. Key decisions and owner actions

**Owner actions before the next backend deploy (from A1.3, D-060 in `../back/docs/DECISIONS.md`):**
- `.env.production` has no `OTP_PROVIDER`: set `OTP_PROVIDER=twilio | whatsapp_cloud | none` (with credentials) or the API refuses to start.
- Admins / super-admins without MFA get the enrolment step at their next login (set `MFA_REQUIRED_ROLES=` explicitly empty to opt out).
- Teacher onboarding from app builds without `X-Onboarding-Token` is refused unless `TEACHER_ONBOARDING_EMAIL_FALLBACK=true`.
- Redis is required for the real-time stream (already in compose); nginx needs the `/api/v1/me/events` location from `deploy/nginx/nextbrain.conf.example`.
- Web: check the browser console for CSP-blocked origins after the first hosting deploy (D-060 in this repo).


- 2026-10-28: job tracked in root `PROGRESS.md` (this file); design decisions that deviate from existing conventions go to `docs/DECISIONS.md` as D-nnn as usual.
- 2026-10-28: per-track analyses in `docs/polish/*.md`; a resumed session reads this file and only the track file it works on.
- 2026-10-28: web real-time = SSE (not WebSocket): nginx `/api/` already has buffering off; one emitter sends both silent FCM and SSE; Redis pub/sub so exam / rag services can emit.
- 2026-10-28: security fixes make the safe value the DEFAULT (OTP log provider refused outside dev, onboarding e-mail fallback off, MFA for admins) rather than relying on `.env.production`, which was not read.

## 6. Final report

_written at the end._

## 7. Resume note

2026-10-28 ~06:00: the Fable usage limit stopped four agents mid-task (B.3, B.4, B.5, E.3). E.3 was complete (owner committed it); B.3–B.5 left near-finished code with 5 layout overflows — a follow-up agent finishes them. The session continues on Opus.


If this session stopped on the usage limit: automatic resume from inside the session is not possible in this
environment. Reply `continue` and the next session resumes from the first non-done row above.
