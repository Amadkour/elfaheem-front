# Progress log — platform refactor (branch `feature/platform-rbac-exams-rag`)

Companion files: `docs/AUDIT.md` (phase-1 audit), `docs/DECISIONS.md` (design decisions and deviations from the brief), `docs/BENCHMARKS.md` (accuracy numbers, backend repo), `docs/CAPACITY.md` (backend repo). The backend repo (`../back`) keeps its own `docs/PROGRESS.md`; both are updated after every phase.

## Phase status

| # | Phase | Status | Accepted when |
|---|-------|--------|---------------|
| 1 | Setup, audit, baseline, branches | **done 2026-10-24** | `docs/AUDIT.md` exists, baseline recorded |
| 2 | Core refactor: modular monolith, RLS, RBAC, audit log | not started | cross-tenant leak tests + permission tests pass |
| 3 | Organizations, switcher, membership, sharing, Verification API | not started | |
| 4 | Application pipeline under load | not started | load test: no oversold seats, no duplicates |
| 5 | Exam Engine service | not started | |
| 6 | Grading engine + OCR + benchmark + review UI | not started | section-13 numbers reported |
| 7 | RAG service + evaluation | not started | |
| 8 | Feedback store, monetization, analytics, appeals | not started | |
| 9 | Frontend completion, localization, accessibility | not started | |
| 10 | Hardening, capacity doc, final docs | not started | |

## Phase 1 — Setup, audit, baseline

### Done
- 2026-10-24: both repos had the branch `feature/platform-rbac-exams-rag` locally only; the only uncommitted change in each was `CLAUDE.md`. Committed as `chore: snapshot before platform refactor` and pushed; `origin/feature/platform-rbac-exams-rag` now exists in both repos and tracks the local branch. The earlier local commits were already on `origin/organizations`.
- Installed `ruff`, `bandit`, `pip-audit` into the backend's local `.venv312` (git-ignored).

### Baseline (frontend, Flutter 3.47.7 stable)
| Check | Result |
|---|---|
| `flutter analyze` | 292 issues, **all `info`** (0 errors, 0 warnings); ran in 150 s |
| `flutter test test/org/ test/export/ test/ui/` | **321 passed**, 0 failed (1 min 27 s) |
| `test/widget_test.dart` | stock counter template, fails by design (documented in CLAUDE.md) |
| Dart files / LOC | 486 files, ~215k lines |
| Test files | 37 |
| CI | none (`.github/workflows` absent) |
| `dart format` | code is intentionally not formatted (CLAUDE.md); not used as a gate |

### Next steps
- Write `docs/AUDIT.md` from the five independent audit passes (auth/RBAC/tenancy, exam module, infra/boundaries, Flutter, domain coverage).
- Decide the Python lint rule set (see DECISIONS) and bring both repos to zero errors/warnings.

## Review rounds
_(one entry per phase: reviewer, findings count by severity, fixes)_

### Phase 1 close-out (2026-10-24)
- `docs/AUDIT.md` written (app findings; server-side findings, domain gaps and exam-module analysis are in `../back/docs/AUDIT.md`).
- Phase 1 is **done**. Entry points for later phases from the app audit: move tokens to secure storage and stop sending the refresh token in the URL (Phase 2 with the server change), fix release build hardening (Phase 10), build exam/proctoring UI on server-authoritative attempts (Phase 5), introduce `XxxApi` Remote/Mock classes for every new feature so providers are testable (from Phase 3).
