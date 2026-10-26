# Decisions — platform refactor

Format: **D-nnn — title** · date · status. Context, decision, consequences. Where the brief conflicts with the real code, the deviation and reason are recorded here (the brief asks for this).

## D-001 — Keep `provider` + `BaseProvider`, no state-management migration · 2026-10-24 · accepted
The brief says "follow what the repo uses unless clearly flawed". The app has ~215k lines on `provider`/`ChangeNotifier` with `BaseProvider.run()` handling loading/error/retry uniformly. It is not flawed; a migration would be pure churn. New features use the same pattern.

## D-002 — Static-analysis gate for Dart is "0 errors, 0 warnings"; `info` lints are reduced opportunistically · 2026-10-24 · accepted
Baseline: 292 `info`-level lints, 0 warnings, 0 errors. The brief's definition of done is zero errors and zero warnings. `info` items in files we touch are fixed; a repo-wide sweep of `avoid_print` / `use_build_context_synchronously` in untouched files would bury the real diff (CLAUDE.md's rule against mass re-formatting applies).

## D-003 — Do not run `dart format` · 2026-10-24 · accepted
The brief lists `dart format` in the baseline. CLAUDE.md forbids it because the code base is unformatted and a run would rewrite every file. Recorded as a known deviation; new files are written formatted by hand.

## D-004 — Phase 9: frontend completion · 2026-10-26 · accepted

- **Engine exam authoring** (`exam_authoring.dart` pure drafts + `ExamAuthoringApi`, `exam_authoring_screen.dart`):
  question bank for all ten types with model answers and rubrics (keywords `term ×2 = synonym, synonym`), exams with
  every setting the server accepts, sections (online / paper / hybrid, weight, time box, one-way, pools), placements,
  proctoring policy (defaults 3 looking-away, 1 tab switch, 1 other app) and accommodations, publish / unpublish /
  close / results. Client checks mirror the server's; the server stays the authority. `settings` is merged into what
  was loaded (the server replaces the object) and `duration_minutes` / `max_attempts` are sent only when changed.
- **Paper flow** (`exam_paper_flow.dart`): answer-sheet PDF, scan upload, mapping file, marks import, student picker
  from the exam's attempts (typed ids otherwise — there is no roster route).
- **Admin / org screens**: fee policy and per-organization fees, refunds (partial, pending → reconcile, resolve),
  ledger report + CSV, platform and organization feedback-store settings and exports, organization exam-risk list,
  RAG library (upload, versions, archive, reindex, settings, unhelpful answers). Writes the server reserves for the
  Super Admin are shown read-only to admins.
- **Exam robustness**: unsaved answers are kept on the device per attempt (SharedPreferences) and restored on resume
  only when newer than the server's copy; removed when the attempt ends. Screenshots / recording blocked on phones
  during an exam (`screen_protector`); the web cannot block them and the consent screen says so. Timer and save state
  carry screen-reader labels.
- **API drift**: not a generated client — the hand-written `ApiClient` carries envelope encryption, token rotation and
  device headers that a generator would bypass. Instead `test/contract/api_paths_test.dart` checks every engine / RAG
  call (method + path) against the backend's route snapshot (`../back/scripts/contract/export_api_paths.py`, whose CI
  step fails when the snapshot is stale). The core's legacy endpoints are not covered yet (Phase 10).
- **Release builds**: `scripts/build_release.sh` builds with `--obfuscate --split-debug-info` (symbols kept per
  version); Android release signing comes from `android/key.properties` or CI secrets, and a build without a keystore
  warns that it is debug-signed. R8 minification stays off until live sessions (LiveKit / WebRTC / recording plugins
  use reflection) pass a device test.

## D-005 — Review round for Phase 9 · 2026-10-26 · accepted

Three fresh-context reviewers on `f83fac1` (code / contract with every builder's JSON posted to the real backend — no
422; security / accessibility; spec tests from the server's validators — 37/37). Fixed:
- **A course teacher could create an exam but not use the question bank** (the bank routes authorized by organization
  only): the app sends `course_id` on create and list; the backend authorizes the bank through the course and shows
  such a teacher only the questions they wrote (back D-026).
- **Unsent answers outlived the session** on shared devices: logout removes every `exam.pending.*` entry.
- A restored answer did not reach the open question's text fields (controllers read the answer once): the cards are
  re-keyed after a restore.
- Refunds: the idempotency key renews after `refund_failed` / `refund_gateway_failed` and whenever amount / manual /
  force change; `parseNum` never reads a comma as a decimal point ("1,000" was 1); admins no longer see an
  organization-fees tab whose data only the Super Admin may read.
- Downloads: server file names are sanitized (`safeFileName`: separators, control characters, length); CI release
  builds without a keystore fail instead of shipping debug-signed; 48 dp touch targets in the authoring lists;
  screen-reader labels on the question grid and citation numbers; out-of-order bank searches ignored; a personal
  course opened under an organization falls back to the personal space; RAG settings keep the org admin's external-LLM
  decision when switching to extractive; the exam-risk tile needs `exams.view`; `file_not_in_batch` mapped.

Accepted: `android:usesCleartextTraffic` stays on until the server confirms every media / LiveKit URL is https
(turning it off blind could break video playback); exports of learning data / ledger CSV / answer sheets are plain
files on the device (named without personal data); a restore that races a very early edit may prefer the stored
answer; the "undeclared sensor" hint does not see the platform's default consent text.
