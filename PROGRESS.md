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
| 0.2 | Analysis phase, no code changes → §1 findings, §2 parity matrix, §3 baselines | in progress |
| 0.3 | Track A1 security and auth fixes | todo |
| 0.4 | Track D real-time + push, remove polling | todo |
| 0.5 | Track C feature parity | todo |
| 0.6 | Track B design system + dashboards + screen polish (A2) | todo |
| 0.7 | Track E RAG overhaul (parallel with 0.4–0.6) | todo |
| 0.8 | Final verification: full test run, re-measure baselines, final report (§6) | todo |

## 1. Findings (ranked by severity) — filled by the analysis phase

Detailed per-track analyses live in `docs/polish/` (read only the one for the track you are on):
- `docs/polish/realtime-inventory.md` — Track D: every polling site, the backend's FCM-only plumbing, the SSE + `LiveEvents` design. Key facts: no WebSocket/SSE exists; `complaints_updated` is never sent; web service worker shows an empty notification for every data push and drops it for the page; admit/reject is never pushed to the waiting participant.

- `docs/polish/screens-parity.md` — Track C: route table, parity matrix, list screens without pull-to-refresh, dark mode / breakpoint facts.

_pending: auth/security, dashboards, RAG pipeline reports._

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
| A1 | Auth | Audit registration / login / tokens / reset / deletion, close holes, add tests | todo | | | after §1 |
| A2 | Frontend | Screen-by-screen audit and polish on web / Android / iOS | todo | | | after B |
| B | Dashboards | Design system + Super Admin · Org Admin · student / user dashboards | todo | | | after D, C |
| C | Parity | Parity matrix, close gaps (pull-to-refresh, calendar entry, …) | todo | | | after D |
| D | Real-time | Silent push (mobile) + WebSocket/SSE (web), one refresh on open/resume/pull, remove polling | todo | | | after A1 |
| E | RAG | Hybrid pipeline (scope → router → curated Q&A → hybrid retrieval → rerank → grounded gen → cache), CPU benchmarks, chat sessions, admin knowledge tools, eval, safeguards | todo | | | parallel |
| QA | QA | Tests across tracks, regression | todo | | | |

## 5. Key decisions

- 2026-10-28: job tracked in root `PROGRESS.md` (this file); design decisions that deviate from existing conventions go to `docs/DECISIONS.md` as D-nnn as usual.

## 6. Final report

_written at the end._

## 7. Resume note

If this session stopped on the usage limit: automatic resume from inside the session is not possible in this
environment. Reply `continue` and the next session resumes from the first non-done row above.
