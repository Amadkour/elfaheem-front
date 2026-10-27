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

_pending: analysis agents running (auth/security, polling inventory, screens + parity, dashboards, RAG pipeline)._

## 2. Parity matrix (feature × Web / Android / iOS)

_pending._

## 3. Baselines (before)

| Measure | Before | After | How measured |
|---|---|---|---|
| `flutter analyze` warnings / errors | pending | | `flutter analyze --no-fatal-infos --fatal-warnings` |
| App test suites | pending | | `flutter test test/org/ test/export/ test/ui/ test/auth/ test/contract/` |
| Backend static gate | pending | | `ruff check .` in `../back` |
| Polling call sites / intervals | pending | | §1 inventory |
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
