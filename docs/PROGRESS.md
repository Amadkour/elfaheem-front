# Progress log — platform refactor (branch `feature/platform-rbac-exams-rag`)

Companion files: `docs/AUDIT.md` (phase-1 audit), `docs/DECISIONS.md` (design decisions and deviations from the brief), `docs/BENCHMARKS.md` (accuracy numbers, backend repo), `docs/CAPACITY.md` (backend repo). The backend repo (`../back`) keeps its own `docs/PROGRESS.md`; both are updated after every phase.

## Phase status

| # | Phase | Status | Accepted when |
|---|-------|--------|---------------|
| 1 | Setup, audit, baseline, branches | **done 2026-10-24** | `docs/AUDIT.md` exists, baseline recorded |
| 2 | Core refactor: modular monolith, RLS, RBAC, audit log | **done 2026-10-24** (app part: auth storage / refresh contract; backend `docs/PROGRESS.md` has the server side and the review round) | cross-tenant leak tests + permission tests pass |
| 3 | Organizations, switcher, membership, sharing, Verification API | **done 2026-10-25** (review round with Phase 4; backend `docs/PROGRESS.md`) | switcher + sharing tests pass, analyzer 0/0 |
| 4 | Application pipeline under load | **done 2026-10-25** (queue-first cart, server-paced polling, honest busy handling) | load test: no oversold seats, no duplicates |
| 5 | Exam Engine service | **done 2026-10-25** (taking flow v2; review round folded in, backend D-019) | consent · server timer · autosave · integrity events |
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
| Review round | done with Phase 4 (backend `docs/PROGRESS.md` → Review rounds · Phases 3 + 4) |

## Phase 4 — app side (2026-10-24, commits `b63ba5e`, `c1a5e16`)

### Done
- **Queue-first registration** in the member cart (`org_registrar_member.dart`, helpers in `org_registrar.dart`): submit with a client idempotency key (`newIdempotencyKey`), 202 → a waiting sheet that shows the position in line (`regQueueText`, `queue_depth`) and polls when the server says (`poll_after_ms` via `regPollAfterMs`, 1–10 s, for up to 75 s, then points to "My requests"); the result lines come from `regResultLines` for both the queued and the synchronous reply. An older server without the route (`endpointMissing`) gets the synchronous `register` call.
- **Graceful degradation, truthfully**: a 503 (admission control), 429 (throttle) or a dropped socket arrives BEFORE anything is stored, so the app retries the same key 3× (1 / 2 / 4 s, `regQueueBusy`) and, if it still fails, says that nothing was submitted — never "your request is kept", which the first version said and the load test proved wrong (backend `docs/DECISIONS.md` D-015 / D-016, `tests/load/README.md`).
- Tests: `test/org/org_registrar_test.dart` (queue helpers, poll interval clamp, busy detection).

### Checks at the end of the phase
| Check | Result |
|---|---|
| `flutter analyze` | 0 errors, 0 warnings |
| `flutter test test/org/ test/export/ test/ui/` | 331 pass |
| Review round | done with Phase 3 (backend `docs/PROGRESS.md` → Review rounds · Phases 3 + 4; app fixes in commit b6e874b) |

## Phase 5 — app side (2026-10-25, Exam Engine taking flow v2)

### Done (commit d176b2a)
- **Exam Engine client** (`lib/features/shared/exam_engine/exam_engine_api.dart`): the student calls of `/api/v1/exam` over the one `ApiClient` (which gained an optional `headers` argument for `X-Exam-Session`); `EngineResult.unavailable` detects an engine that is not deployed or routed yet, so the legacy exam flow stays in charge until then.
- **Pure logic** (`exam_taking.dart`, unit-tested): the server clock (counts down from the server's `remaining_seconds`, never from the device clock), the paper model with one-way sections, the autosave queue with a monotonic `save_seq` per question (older saves are ignored by the server, retries are safe), the integrity event buffer (urgent kinds flush at once), the policy actions, the bilingual code texts.
- **Screens**: consent (`ExamConsentScreen`: the versioned text, what it requires, what THIS device can and cannot do, hash-bound acceptance), taking (`ExamTakingScreen`: timer chip, progress and lock banner, one card per question type — single / multi / true-false / blanks / matching / ordering / numeric with units / short answer / essay —, question grid, autosave every 4 s, submit with an unanswered-count confirmation, leaving keeps the attempt), result (`ExamResultBody`: by the results policy, "awaiting review" when so). Integrity signals from what each platform offers (`exam_integrity*.dart`: web — tab / window switch, full-screen exit, copy / paste; mobile — app to background) are reported as events; the consent screen says plainly what cannot be prevented. On-device face / gaze models are Phase 9.
- **Entry**: `EngineExamsSection` above the legacy course exams (start / resume / passcode / result), hidden when the engine has no exams for the course or is not deployed.
- Tests: `test/org/exam_taking_test.dart` (clock, paper navigation, autosave queue, events; layout harness over every question type, timer, nav bar, grid, consent and result bodies).

### Checks at the end of the phase
| Check | Result |
|---|---|
| `flutter analyze` | 0 errors, 0 warnings |
| `flutter test test/org/ test/export/ test/ui/` | 338 pass |
| Review round | done (see Review rounds · Phase 5) |

## Review rounds
_(one entry per phase: reviewer, findings count by severity, fixes)_

### Phase 5 (2026-10-25)
App findings from the architecture and security reviews (backend D-019), all fixed: a submit right after the 20-minute exam session expired dropped the last autosave batch (a flush that meets `exam_session_invalid` renews the session and resends the SAME batch; submit now waits until the queue is empty and says so when it cannot); the web integrity hooks reported two `tab_switch` for one Alt-Tab (visibility + blur) so the default "max 1" rule fired on the first switch (`IntegrityDedupe`: one per 1.5 s burst, unit-tested); a blank numeric value with a unit chosen was sent as an answer and flagged the whole attempt for review (`encodeNumeric` sends `{}` when blank); failures carry the server's `detail` (`EngineResult.detail`: reason, question_id, …) instead of an empty map; one permanently refused autosave item poisoned the queue (the server now answers `rejected` per item and the app drops items refused for good: `question_not_in_paper`, `bad_answer`, `answer_too_large`, one-way); failed event uploads were dropped (re-queued unless the refusal is permanent); time-up now submits within the server's grace instead of waiting for the sweeper; the consent `accepted` flag is a boolean; the test-mode request logger redacts `X-Exam-Session` / `X-Enc-Session`; `EngineExamCard` joined the layout harness — and overflowed at 320 px with large text (the action pill moved under the texts). New codes have texts (`too_many_requests`, `answer_too_large`, `attempt_rejected`, `teachers_only`, `course_not_in_org`, `section_locked`, …).

### Phases 3 + 4 (2026-10-24)
App findings from the architecture review (all fixed, commit b6e874b): share dates were parsed as local time and sent as the first second of the chosen day (now `orgParseUtc` / `orgUtc`, expiry = end of the chosen day, `shareExpiryInstant`); swiping the queue sheet away popped the registrar page (the pop now happens only while the sheet is open); a 500 or a dropped socket after the submit retries was reported as "nothing was registered" although the server stores the request before dispatching it (now "could not confirm — check My requests", `regSubmitCertainlyRejected`); the verify dropdown asserted when the chosen grant disappeared; per-sheet text controllers were never disposed; the sharing tab controller ignored a changed admin flag; `methods` compared by join order (`setEquals`). New server codes have texts (`sharing_root_only`, `grant_revoked`, `too_many_keys`, `bad_resource_type`, `code_generation_failed`, `pending_limit`, `idempotency_mismatch`, `gone`, `internal`); `pending_limit` is not treated as "busy". The queue and result sheets are public plain-value widgets under the layout harness. Security review: no app findings.

### Phase 2 (2026-10-24)
The three fresh-context reviews ran on the backend diff (which includes the auth contract the app consumes); findings and fixes are in the backend `docs/PROGRESS.md` (round 1) and `docs/DECISIONS.md` D-012. App-relevant outcome: the `/refresh` reply within ~10 s of a lost reply is a fresh pair, not `refresh_reuse`; new codes to localise are listed above.

### Phase 1 close-out (2026-10-24)
- `docs/AUDIT.md` written (app findings; server-side findings, domain gaps and exam-module analysis are in `../back/docs/AUDIT.md`).
- Phase 1 is **done**. Entry points for later phases from the app audit: move tokens to secure storage and stop sending the refresh token in the URL (Phase 2 with the server change), fix release build hardening (Phase 10), build exam/proctoring UI on server-authoritative attempts (Phase 5), introduce `XxxApi` Remote/Mock classes for every new feature so providers are testable (from Phase 3).
