# Progress log — platform refactor (branch `feature/platform-rbac-exams-rag`)

Companion files: `docs/AUDIT.md` (phase-1 audit), `docs/DECISIONS.md` (design decisions and deviations from the brief), `docs/BENCHMARKS.md` (accuracy numbers, backend repo), `docs/CAPACITY.md` (backend repo). The backend repo (`../back`) keeps its own `docs/PROGRESS.md`; both are updated after every phase.

## Phase status

| # | Phase | Status | Accepted when |
|---|-------|--------|---------------|
| 1 | Setup, audit, baseline, branches | **done 2026-10-24** | `docs/AUDIT.md` exists, baseline recorded |
| 2 | Core refactor: modular monolith, RLS, RBAC, audit log | **done 2026-10-24** (app part: auth storage / refresh contract; backend `docs/PROGRESS.md` has the server side and the review round) | cross-tenant leak tests + permission tests pass |
| 3 | Organizations, switcher, membership, sharing, Verification API | **in progress — code complete, review pending** (2026-10-24) | switcher + sharing tests pass, analyzer 0/0 |
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

## Phase 2 — app side (2026-10-24)

### Done (commit `78f967d`)
- Tokens in `flutter_secure_storage` on mobile (SharedPreferences on web), one-time migration from the old keys; `StorageService` keeps only the cached user and UI preferences.
- `ApiClient` refreshes with the token in the body and stores the NEW pair (rotation); parallel 401s share one refresh; `hasSession` / `primeSession()` replace the old `isAuthenticated` flag; change-password and logout follow the new contract (`FLUTTER_API_CHANGES.md`, backend repo).
- Release builds log nothing (`AppConfig.testMode = !kReleaseMode`); duplicate global providers removed; CI workflow (`flutter analyze`, the three real test suites).

### Carried to Phase 3
- Bilingual texts for the new server codes (`too_many_attempts` with `retry_after_minutes`, `otp_cooldown` with `retry_after_seconds`, `otp_invalid` + `attempts_left`, `otp_expired`, `otp_locked`, `refresh_*`, `self_action`, `escalation`) — the client already reads `{detail:{code,message}}`, so nothing breaks, but the message is Arabic-only today.
- Tenant context on member routes (organization switcher), see the Phase 3 plan.

### Checks at the end of the phase
| Check | Result |
|---|---|
| `flutter analyze` | 0 errors, 0 warnings, 292 info |
| `flutter test test/org/ test/export/ test/ui/` | 321 pass |

## Phase 3 — app side (2026-10-24, commit `e881531`)

### Done
- **Switcher** (`lib/design/context_switcher.dart`): shown for everyone while organizations are on (the kill-switch still hides it); the sheet lists live organizations, organizations under review (not enterable) and "Join another organization" → `openOrgJoin`. Test `test/org/org_context_switcher_test.dart`.
- **Sharing with other organizations** (`lib/features/org/org_sharing.dart`, `org_sharing_pages.dart`, workspace area `sharing`): Offers (create / edit / revoke a share, invite code shown once with copy, grants and use log), Requests (approve / reject with a reason), Partners (redeem a code, what we hold, discover and request), Verify (paste identifiers or upload a CSV / TXT / XLSX, yes / no + year), API keys (admins). Pure logic + layout tests in `test/org/org_sharing_test.dart`.
- **Super admin**: `sharing_enabled` on the platform settings page; per-organization switch on the organization review page.
- **Error codes**: `lib/core/api_error_text.dart` gives bilingual texts for `too_many_attempts` (+ retry), `otp_*`, `refresh_*`, `self_action`, `escalation`; `BaseProvider` uses it; the OTP screen shows the server's reason; `org_v3` knows every sharing code.
- **Analyzer**: the 64 pre-existing warnings are gone (unused code, dead branches; one real fix: a session duration fallback that never ran). Phase 2's "0 warnings" line was wrong; the gate is real now.

### Checks at the end of the phase (so far)
| Check | Result |
|---|---|
| `flutter analyze` | 0 errors, 0 warnings |
| `flutter test test/org/ test/export/ test/ui/` | 330 pass |
| Review round | pending (reviewers rate-limited; see backend `docs/PROGRESS.md`) |

## Review rounds
_(one entry per phase: reviewer, findings count by severity, fixes)_

### Phase 2 (2026-10-24)
The three fresh-context reviews ran on the backend diff (which includes the auth contract the app consumes); findings and fixes are in the backend `docs/PROGRESS.md` (round 1) and `docs/DECISIONS.md` D-012. App-relevant outcome: the `/refresh` reply within ~10 s of a lost reply is a fresh pair, not `refresh_reuse`; new codes to localise are listed above.

### Phase 1 close-out (2026-10-24)
- `docs/AUDIT.md` written (app findings; server-side findings, domain gaps and exam-module analysis are in `../back/docs/AUDIT.md`).
- Phase 1 is **done**. Entry points for later phases from the app audit: move tokens to secure storage and stop sending the refresh token in the URL (Phase 2 with the server change), fix release build hardening (Phase 10), build exam/proctoring UI on server-authoritative attempts (Phase 5), introduce `XxxApi` Remote/Mock classes for every new feature so providers are testable (from Phase 3).
