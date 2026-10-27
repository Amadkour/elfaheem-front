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
| 0.3 | Track A1 security and auth fixes | in progress |
| 0.4 | Track D real-time + push, remove polling | todo |
| 0.5 | Track C feature parity | todo |
| 0.6 | Track B design system + dashboards + screen polish (A2) | todo |
| 0.7 | Track E RAG overhaul (parallel with 0.4–0.6) | todo |
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
| Polling call sites / intervals | 7 new-data polls (attention 60 s, lobby 15/4 s, guest 10 s, quiz 30 s, exam tab 5 min, attendance 5 s) + 12 job-progress polls (1–8 s); 0 SSE/WS | | `docs/polish/realtime-inventory.md` |
| RAG eval (hit rate, correctness, hallucination, latency, memory) | pending | | §5 eval set |
| Dashboard requests on open | pending | | count of API calls per dashboard open |

## 4. Task board

| Id | Track | Task | Status | Changed | Verified by | Next step |
|---|---|---|---|---|---|---|
| A1.1 | Auth | S1 phone change: normalise, 409 `PHONE_TAKEN`, reset `phone_verified` + OTP; S9 re-auth for delete / phone change, revoke tokens on deletion | todo | | | start here |
| A1.2 | Auth | S2 register throttle; S7 phone-link throttle; S10 handshake throttle + shorter TTL | todo | | | |
| A1.3 | Auth | S3 refuse `OTP_PROVIDER=log` outside dev/test; S5 onboarding e-mail fallback default off; S12 MFA default roles | todo | | | |
| A1.4 | Auth | S4 re-own unverified accounts on register; S6 uniform answers (no enumeration) | todo | | | |
| A1.5 | Auth | S11 password policy ≥ 8 + common list (app validators + schemas) | todo | | | |
| A1.6 | Auth (app) | S14 `getMe()` after bootstrap; S15 `MyAuthProvider.logout` posts `/auth/logout`; S16 treat 429 on refresh as transient; S8 CSP on hosting + web access token in memory | todo | | | |
| A1.7 | Auth | Backend e2e `tests/org_v2/e2e_auth_hardening.py` proving S1–S10 closed; app tests for S14–S16 | todo | | | |
| A2 | Frontend | Screen-by-screen audit and polish on web / Android / iOS | todo | | | after B |
| B.1 | Design | Design system pass: one shell for all roles (`lib/design/app_shell.dart`), tokens from `context.colors` only (remove ~60 hard-coded colors), one breakpoint system, leaf-level `AttentionBadge` rebuilds, chart primitives (`lib/design/app_charts.dart`, CustomPaint, no new package unless needed) | todo | | | after D, C |
| B.2 | Dashboards | Super Admin: extend `/admin/overview` (orgs, pending org approvals, 30-day series, alerts), one home with KPIs + trend charts + queue + shortcuts, grouped services | todo | | | |
| B.3 | Dashboards | Org Admin: members KPI, approvals total, activity series in `org_dashboard_summary`; home reorganised (queue first, 1-tap sub-pages); split the 1371-line file | todo | | | |
| B.4 | Dashboards | Student + org member: one aggregate `GET /me/home` (today, upcoming week, attention, inbox preview, notifications count); coordinated skeleton; grouped quick actions | todo | | | |
| B.5 | Dashboards | Teacher + parent: error states, parent overview aggregate (`/parent/overview`), earnings tile | todo | | | |
| B.6 | Frontend (A2) | Screen-by-screen polish pass per feature area (spacing, typography, RTL, dark, empty / error states) with the layout harness | todo | | | |
| C.1 | Parity | Calendar entry for teacher / parent / admin (header icon + More entry) | todo | | | after D |
| C.2 | Parity | Pull-to-refresh on the 17 list screens (shared `AppRefresh` wrapper) | todo | | | |
| C.3 | Parity | One breakpoint system (`app_responsive.dart`), rail shell on all platforms; splash follows the user's dark-mode choice | todo | | | |
| C.4 | Parity | Mic meter on mobile; PiP on iOS (or record as by-nature with reason); web foreground push notification | todo | | | |
| D.1 | Real-time (back) | `live_update_service.emit()` = silent FCM + SSE; Redis pub/sub `nb:live:{user}`; `GET /api/v1/me/events` SSE with heartbeat + `Last-Event-ID`; granular events (`attention_changed`, `job_updated`, `lobby_updated`, `join_decided`, `quiz_started`, `session_live`, `*_updated`); wire `complaints_updated` | todo | | | after A1 |
| D.2 | Real-time (app) | `LiveEventsClient` (SSE over `package:http`, foreground only, backoff, dedupe by event id); `LiveEvents` single bus; `AttentionService` subscribes + stretches poll to 5 min while connected | todo | | | |
| D.3 | Real-time (app) | Replace the 7 new-data polls and 12 job-progress polls with event listeners + slow fallback; service worker fix for data pushes; one refresh on open / resume / pull | todo | | | |
| D.4 | Real-time | Tests: backend e2e for emit + SSE replay; app unit tests for the client (dedupe, reconnect) | todo | | | |
| E.1 | RAG | Eval first: `bench/rag/run_answer_eval.py` + real-corpus question set (ar/en, failed questions, out of scope); record BEFORE numbers in §3 | todo | | | parallel, start here |
| E.2 | RAG | Curated Q&A layer (`rag.qa_pairs`, embeddings, thresholds, direct answer / examples), admin CRUD + "promote to Q&A" | todo | | | |
| E.3 | RAG | Answer cache (`rag.answer_cache`, invalidated by library / Q&A version); budget cut (3 × 800 chars, ≤ 2 queries, ≤ 30 rerank pairs, token guard) | todo | | | |
| E.4 | RAG | Real BM25 on Postgres + Arabic normalisation; data-driven router (glossary / rules in settings, feature-guide deep links) | todo | | | |
| E.5 | RAG | Conversations: table + routes + retention tick (default 90 days, admin setting) + client new chat / drawer / rename / delete; thumbs-down comment; "not sure → contact support" | todo | | | |
| E.6 | RAG | CPU benchmark ONNX INT4 vs llama.cpp GGUF for 0.6B / 1.7B (tok/s, TTFT, memory); streaming partial answers; INT-only model fetch in prod | todo | | | |
| E.7 | RAG | Monitoring counters in `overview` → super admin dashboard; tenant-leak tests; AFTER numbers | todo | | | |
| QA | QA | Full suites in both repos after each track; final re-measure | todo | | | |

## 5. Key decisions

- 2026-10-28: job tracked in root `PROGRESS.md` (this file); design decisions that deviate from existing conventions go to `docs/DECISIONS.md` as D-nnn as usual.
- 2026-10-28: per-track analyses in `docs/polish/*.md`; a resumed session reads this file and only the track file it works on.
- 2026-10-28: web real-time = SSE (not WebSocket): nginx `/api/` already has buffering off; one emitter sends both silent FCM and SSE; Redis pub/sub so exam / rag services can emit.
- 2026-10-28: security fixes make the safe value the DEFAULT (OTP log provider refused outside dev, onboarding e-mail fallback off, MFA for admins) rather than relying on `.env.production`, which was not read.

## 6. Final report

_written at the end._

## 7. Resume note

If this session stopped on the usage limit: automatic resume from inside the session is not possible in this
environment. Reply `continue` and the next session resumes from the first non-done row above.
