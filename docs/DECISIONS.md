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

## D-006 — MFA and the teacher onboarding token on the client · 2026-10-26 · accepted

**Context.** The backend adds TOTP MFA as a second login step (back D-027) and a scoped onboarding token for the
teacher-profile / teacher-documents routes, whose e-mail-only fallback will be switched off (back D-028). A 403
`mfa_enrollment_required` can reach a session that predates `MFA_REQUIRED_ROLES`.

**Choice.**
- Login (password and Google) hands `{mfa_required}` / `{mfa_enrollment_required}` answers to `openMfaStep`
  (`mfa_verify_screen.dart`); `AdminMfaPage` covers status, enrolment (QR + secret text), recovery codes shown once,
  regenerate, disable and the forced enrolment. The new pair from `/mfa/confirm` is stored at once
  (`MyAuthProvider.completeSession`).
- **The onboarding token stays in memory** (`TeacherOnboardingToken`), not in secure storage: it is a 6-hour bearer
  credential for one onboarding run; after an app restart login hands out a fresh token plus an access token, which
  the server also accepts. Cleared on finalize, on `onboarding_token: null`, on logout and on every new or ended
  session (`saveTokens`, `clearTokens`, the 401 login redirect).
- **Injection:** call sites pass `TeacherOnboardingToken.headers`, and the `ApiClient` interceptor adds the header to
  any onboarding route that lacks it (pure `onboardingHeaderFor`, unit-tested against the route snapshot), so a future
  onboarding call cannot forget it. The server reads the header before `Authorization`, so a stale bearer does not
  break onboarding.
- **MFA prompt:** a 403 `mfa_enrollment_required` opens `AdminMfaPage` once per session, never for guests, view-as,
  `auth:false` calls or the MFA routes; the error still reaches the caller.

**Alternatives.** Secure storage for the token (an extra credential at rest for no working path); explicit headers
only (one forgotten call breaks onboarding once the fallback is off); opening the MFA page on every 403 (loops when
the user backs out).

**Consequences.** A web refresh or an app kill in the middle of onboarding needs a new login. A user who backs out of
the MFA page sees the server's error text until the next login. Org admins / staff have no MFA entry yet.
*Update (D-009):* a settings entry for every allowed role, and the prompt reopens after a 30 s pause.

## D-007 — The contract test scans every `ApiClient` call, not only the engine / RAG clients · 2026-10-26 · accepted

**Context.** D-004 checked only the Exam Engine and RAG calls; the core's ≈ 950 routes are called from per-screen code
with interpolated paths.

**Choice.** `test/contract/api_call_scan.dart`, a small Dart-aware static scanner (strings incl. raw / triple /
interpolation, comments, brackets), finds every `.get/.post/.put/.patch/.delete/.getBytes/.postForBytes/.postFiles/
.postForm/.postMultipart/.uploadImage(` call in `lib/**.dart` and resolves its first argument (constants, getters,
one-line path functions, scoped locals, `Class.x`, `context.read<T>().x`, typed fields, `widget.x`, one template per
ternary branch). An ambiguous name stays unresolved instead of being guessed. `api_paths_test.dart` requires every
resolved branch to match a route with the same method in `test/contract/api_paths.json` (typed params: a literal can
no longer hide behind `{id:int}`), keeps a commented `knownMissing` allow-list that fails when an entry is stale, and
guards coverage (> 500 calls, < 10 % unresolved). CI runs `test/contract/`.

**Alternatives.** A generated client from OpenAPI (rewrites every screen and bypasses the envelope / rotation /
device logic of `ApiClient`); runtime recording (`ApiClient` is a singleton); regex matching (≈ 60 % coverage, false
positives on shared `base` getters).

**Consequences.** ≈ 93 % of calls are verified; paths passed in as parameters (≈ 7 %) are counted, never checked. A
new call to a route the server does not have fails with `METHOD template file:line`: add the route and regenerate the
snapshot (`back/scripts/contract/export_api_paths.py --front ../nextbrain-front`), or add a `knownMissing` entry with
a reason.

## D-008 — The API base URL is a build-time define · 2026-10-26 · accepted

**Context.** Developers pointed the app at a local backend by editing `AppConfig.baseUrl` and had to remember not to
commit it; the one-command local stack (back D-042) serves everything behind one gateway URL.

**Choice.** `AppConfig.baseUrl` = `String.fromEnvironment('API_BASE_URL')`, defaulting to
`https://nextbrain.site/api` when the define is absent, so every build without it — release included — talks to
production. Local: `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:18080/api` (Android emulator) or the
host's address. The release pipeline already passes `--dart-define=API_BASE_URL=…` to the web build.

**Alternatives.** Flavors / several entry points (more build configuration for one value); a runtime setting screen
(a production build could be pointed anywhere).

**Consequences.** A build made with an `http://` override has no TLS and therefore no certificate pinning; nothing
stops a release build from being made that way (a guard that refuses a non-https override in release mode is an open
item). *Update (D-009):* a release build now accepts only an `https://` override and otherwise uses production.

## D-009 — Review round for Phase 10 · 2026-10-26 · accepted

One fresh-context reviewer on `git diff d168043 -- lib test .github` (R3: 0 critical, 0 high, 2 medium, 7 low), payloads
checked against `../back`; then the app's open Phase 10 items. Fixed:
- **A release build accepts only an `https://` API override** (R3 M1). `resolveApiBaseUrl(override, release:)`
  (`lib/config/app_config.dart`): no override → production; debug / profile take the override as given (the local
  `http://` gateway keeps working); release takes it only when it is `https://` with a host, else production.
  It falls back instead of refusing to start: on mobile the pinned certificate already limits a release build to
  production, and a refusing web build would turn a leftover dev variable into an outage. `AppConfig.baseUrl` is
  `final`, not `const` (a `const` cannot call String methods; asserts are off in release). A non-production HTTPS host
  on mobile still needs its pin; the pipeline should reject a non-https `NEXTBRAIN_API_BASE_URL` (open, back side).
- **MFA for every allowed role** (R3 M2). `MfaSettingsEntry` asks `GET /auth/mfa/status` and shows the "Two-step
  verification" group only when the server says `allowed`, `enabled` or `required` — the roles live in the server's
  `MFA_ALLOWED_ROLES` / `MFA_REQUIRED_ROLES`, never in the app; hidden for guests, in view-as and by `profile.mfa`. It
  sits on `ProfileScreen` and the org dashboard's settings page; admins keep the services-hub tile. The forced prompt
  never stacks two pages and reopens on a later 403 `mfa_enrollment_required` once `mfaPromptCooldown` (30 s) has
  passed since it was dismissed (`shouldOpenMfaEnrollment(..., pageOpen, sinceDismissed)`); reopening at once was
  rejected because screens that reload when shown again would loop.
- R3 lows: last wrong code ends the step; MFA secrets and codes masked in debug logs (`redactForLog`, also inside a
  JSON string body); anchored `isTeacherOnboardingPath`, so an absolute URL to another host never gets
  `X-Onboarding-Token`; super-admin MFA reset; forced-enrolment edge cases ("Sign in again" when already enrolled or
  the enroll token is dead, Retry on a failed status load); theme colour for the step number; the export cooldown text
  names `next_request_at` / `cooldown_hours`.
- Open Phase 10 items: refund sheet for 409 `refund_external_recorded` (warning, lower "Left to refund", same
  idempotency key because the server reserved nothing, Refund off at 0, `onChanged` reloads the list) and the
  refunded / refundable chips; Super-Admin RAG quota override (`RagQuotaOverrideDraft`: platform default = null,
  unlimited = 0, own limit; both keys always sent because the PUT replaces both); `role_swap` / `llm_disagrees` labels;
  `DocStatusBadge` (never "Verified" unless approved); `feeConflictText`; `logo_url_not_allowed` in `orgErrorText`
  (back D-045); dead calls removed; `.gitignore` patterns; `macos/Flutter/ephemeral/` untracked.

Accepted:
- **The cleartext hardening is prepared but not wired in.** `android/app/src/main/res/xml/network_security_config.xml`
  refuses cleartext except 127.0.0.1 / localhost (the offline-video loopback server, needed in release) and 10.0.2.2
  (emulator host); the iOS counterpart is `NSAllowsLocalNetworking`. The manifest keeps
  `android:usesCleartextTraffic="true"` and `Info.plist` keeps `NSAllowsArbitraryLoads` (D-005 still holds) until the
  owner confirms on the server that `MINIO_PUBLIC_URL` / `LIVEKIT_PUBLIC_URL` are https / wss and no stored media URL
  is `http://` (back DEPLOY "Owner checks"). The repository evidence (the https web app already depends on them) was
  judged not enough to risk every image and video of the next mobile release. To switch: replace the manifest
  attribute with `android:networkSecurityConfig="@xml/network_security_config"` and the plist key; then test offline
  video and a live session on release builds of both platforms.
- The inline `t(ar, en)` strings of the auth / profile / admin MFA and export screens stay inline (both languages
  present); moving them to `assets/translation.json` is a separate i18n pass.
- Older code noted by R3, unchanged: the envelope handshake and the `encryption_session_expired` retry use bare,
  unpinned Dio instances; the device-blocked dialog fires only on `/auth/login`. Org staff on `/org_member` reach the
  MFA entry from the personal `ProfileScreen`.

## D-011 — Timetable fixes are previewed on the grid, and the review stage has one AI button · 2026-10-27 · accepted

**Context.** Fixing a timetable meant one text confirmation per conflict, a "regenerate to use it" toast after every
data fix, and no way to see what a fix moves before it is saved. A term without a timetable was discovered only by
opening the Timetables tab and the wizard.
**Decision.** `org_schedule_preview.dart` draws BEFORE / AFTER as two compact grids (`MiniTimetable`) from the server's
`remedies/preview` (or a quick action's `changes`): red where a session was, green where it lands; Apply is the only
write. `org_schedule_autopilot.dart` adds the one-tap path: `TermTimetableCard` ("Generate now" →
`POST …/schedules/auto`) on the Timetables tab, the org dashboard's attention queue and the notification deep link
(`org_timetable` → the Timetable section on that draft, via `timetableRequest`); "Fix automatically" on the next-step
banner, the toolbar and the Quick Actions panel starts `POST …/autopilot`, which the studio follows like a generation.
"Create timetable" now starts the autopilot and falls back to the plain complete generation on an older server. Data
fixes no longer end in a toast: the panel offers "Re-solve now".
**Consequences.** The remedies panel and the quick actions share one comparison sheet; an older server without the
preview route still gets the text confirmation. The mini grids scroll sideways on phones and clip (never overflow) at
large text sizes (`test/ui/autopilot_layout_test.dart`); pure logic in `test/org/org_autopilot_test.dart`.
**Round 2 (same day).** Every "Fix automatically" goes through `runAutopilotWithPlan`: the data fixes the run would make
are shown first (`DataFixPicker`, people / room changes unticked), then the run starts. The summary card offers "Undo
everything" (the `autopilot_before` revision). The Timetables tab shows the server's full blockers
(`GET …/schedules/term-needs`). A second tap while a one-tap run is going follows that run instead of failing. A
"term without a timetable" push shows a "Generate now" button (Android action / iOS category) that calls the one-tap
route from the notification; this part was written against the plugin's API without a device run.

## D-010 — Cleartext only to the device itself; the WebRTC fork pinned to a commit · 2026-10-26 · accepted

**Context.** D-005 kept `android:usesCleartextTraffic="true"` and iOS `NSAllowsArbitraryLoads` until production was
checked: one plain-`http://` media URL would break every image and video in the next release. G4 prepared
`android/app/src/main/res/xml/network_security_config.xml` but left it unwired. `flutter_webrtc` followed the fork's
`main`, so every `flutter pub get` could pull a different native build.
**Checked on production (2026-10-26).** `MINIO_PUBLIC_URL` is `https://nextbrain.site/storage`, `LIVEKIT_PUBLIC_URL`
is `wss://…` (`LIVEKIT_API_URL` is the Docker-network address, never sent to the app), and a scan of every text column
in the `public`, `exam` and `rag` schemas found no value starting with `http://` (other than localhost).
**Decision.** Android uses `network_security_config.xml`: cleartext is refused everywhere except `127.0.0.1` /
`localhost` (the offline-video loopback server, needed in release) and `10.0.2.2` (the emulator's host alias for the
local stack). iOS replaces `NSAllowsArbitraryLoads` with `NSAllowsLocalNetworking`. The fork is pinned to
`163469226e1d261a6461f1b7244c1d0ff0cec770`, the commit every build so far resolved; rebasing it onto upstream (libwebrtc
M150) stays a separate task with its own device tests.
**Consequences.** A media or LiveKit URL that is not https / wss fails on the device instead of loading in clear —
keep `MINIO_PUBLIC_URL` / `LIVEKIT_PUBLIC_URL` https / wss. Updating the fork means changing the `ref:` on purpose.

## D-012 — Enter and shortcuts for every text field come from one keyboard layer, not from each screen · 2026-10-27 · accepted

**Context.** On the web build Enter in a text field did nothing (the default action only takes the focus away) and
every form would have needed its own `onSubmitted` / `Shortcuts` wiring — 91 files build text fields, with four
different primary buttons (`PrimaryButton` is a plain `GestureDetector`, so Flutter's own Enter-on-a-focused-button
never reaches it).
**Decision.** `AppKeyboardSupport` (`lib/design/app_keyboard.dart`), mounted once in `MaterialApp.builder`, listens
to `HardwareKeyboard` and decides from the focused field: a field with its own handler or a search / filter box is left
alone; Enter moves to the next field of the form and on the last one presses the form's primary button, found by one
pass over the element tree (the enabled, visible `PrimaryButton` / `FilledButton` / `ElevatedButton` that shares the
deepest ancestor with the field; a dialog with text buttons only uses the last one); Ctrl+Enter does the same from a
multi-line field; Esc leaves a field; Ctrl+K / "/" focus the search box. It runs only on web and desktop. The web
engine performs the field's own action (unfocus / next) synchronously after the framework's handler, so a focus move
is applied in a microtask. `EnterSubmits(onSubmit:)` / `.none` override the guess (the exam's answer box goes to the
next question, never to Submit).
**Consequences.** New screens need nothing. The button is a heuristic over the widget tree: a form whose primary
action is not one of those button types, or whose Save sits in another branch than a nearer button, must say so with
`EnterSubmits`. `test/ui/app_keyboard_test.dart` drives it with simulated key events.

## D-012 — The assistant is premium by default: a model pipeline with a console, the app assistant follows the open organization · 2026-10-27 · accepted

**Context.** The assistant answered with stitched sentences (the server had no model), exam drafts came from tables
of contents and copyright pages, and nothing about the assistant could be changed without a deploy. The backend
side of this change is D-054 in `../back/docs/DECISIONS.md` (pipeline, agents, platform settings, consent).
**Decision.** The chat (`rag_chat_screen.dart`) renders the writer's answers as blocks (paragraphs, bullets, numbered
steps, bold terms, `[n]` marks), shows the worker's stage trail while it works (`stage` from the poll), offers the
writer's follow-up questions as chips and starter prompts when the chat is empty, and marks model-written answers
"From the sources". The floating app assistant (`app_assistant.dart`) passes the open organization
(`AppModeController`) as `org_id` with `app: true`, keyed per organization, so inside an organization it answers about
the app AND the organization's rules and documents. The Super Admin gets `rag_admin_console.dart` (Overview ·
Settings · Playground with the trace · Questions) in place of the bare documents list; the exam generator sheet gains
difficulty, focus and language, and reports the planner's and reviewer's work in one toast. An organization's answer
setting gains `default` (follow the platform) and shows what applies now.
**Rejected.** A separate "organization assistant" bubble (two bubbles confuse; one bubble that follows the mode is
what members expect); rendering full Markdown (the server never sends headings, tables or links, so a small block
parser that cannot be fooled is enough); streaming (the queue-and-poll contract stays, the stage trail gives the
feedback).

**Addendum (2026-10-27, D-055 in the backend).** The model is now a local open-weight one on the server (no
commercial provider), so answers take ≈ 10–15 s (about a minute with the larger registered model) and the stage trail is the feedback; the chat's suggested questions
come from the server (`GET /api/v1/rag/starters`: questions built from the headings the asker's library actually has)
instead of a fixed list — the fixed list had suggested "how many devices?" to members whose library never stated a
number, and the assistant answered "not found" to its own suggestion. The built-in list stays only as the fallback for
an empty library, with that question replaced by one the features guide answers. The admin console's Settings tab
shows the local model's files status and hides the effort / model knobs and the consent switch, which mean nothing
with it.

## D-013 — Generation is a ladder the creator orders and locks, followed live, with decisions asked in place · 2026-10-27 · accepted

**Context.** The app knew one "Generate" (strict, then every Flexible rule at once, 90 s), followed a run for at most
4 minutes and then invented a failed run while the server was still working, let a run of one timetable leak into
another, and could neither reorder nor save the rules. The backend now climbs a relaxation ladder (D-056 in
`../back/docs/DECISIONS.md`, contract in `docs/backend/ladder-spec.md`).
**Decision.** `org_schedule_ladder.dart` holds the pure models (ladder, options, decision, live state, final
report) and the provider's calls; `org_schedule_ladder_ui.dart` the three presentational pieces, every one taking
plain values so the layout harness pumps them: the ladder editor (drag to reorder, mode per rung, the fixed rules
shown locked, numeric options, presets), the live overlay (stage, placed / remaining, conflicts, the rung being
relaxed and why, the step log, cancel) and the decision dialog (situation, options with impact, the recommended one
marked, "let the system decide"). The result card reads the server's later additions as data: a rung "set aside"
by the pre-check (`not_relevant`), a split handed to a colleague (`splits[].staff`), a proposed room removed again
after a rejected proposal (`removed`). The studio's Create / Generate actions start a ladder run; a `waiting` run is open;
a run is lost only after five failed polls or a 404, never by a client clock. Runs are scoped to their timetable.
**Rejected.** A separate screen for decisions (the fork must be answered where the run is watched); client-side
completion maths (the server's `completion_pct` and proof are the truth); keeping the hard-coded rules list (the
catalog comes from the server so a new rung needs no app release).

## D-057 — Governance screens reuse the org kit and ONE shared filter; the Export Hub generalises the report designer · 2026-10-27 · accepted

**Context.** Requests, complaints, forms, routing, delegation, council voting and designed exports (D-057 in
`../back/docs/DECISIONS.md`, contract in `docs/backend/governance-spec.md`) needed screens for staff, heads,
council members and plain members, in Arabic RTL and English LTR, on phones and wide screens.
**Decision.** `lib/features/org/governance/` holds pure models (`gov_models.dart`, incl. the tally rules mirrored
from the server so previews agree with it), one API client (`gov_api.dart`, one method per route), ONE filter
(`gov_filter.dart`: `ItemFilter` ↔ query string + `ItemFilterBar`, saved per user on the server) used by every
list, and presentational widgets that take plain values so the layout harness can pump them. The Export Hub
(`lib/design/export_hub/`) generalises the complaints report designer into a design document (page, fonts per
element, many logos and signatures, table style, the council items block with the vote result beside and / or
below each item), with the PDF / Word / Excel writers hand-written like the rest of the app (no `excel` package,
D-003); Arabic and English outputs come from different templates, never a mirrored one. `AppTableExport` offers
"Design…" so every existing table export can go through the hub.
**Consequences.** New lists in the module must build on `ItemFilter`; a new export anywhere passes an
`ExportDataset` to `exportHub` instead of writing another sheet. Error codes of the module are mapped in
`govCodeTexts` and merged into `orgErrorText`.

## D-058 — One live-room identity for sessions and meetings; admission is decided before the LiveKit token exists · 2026-10-27 · accepted

**Context.** Hosts wanted a share link, a lobby (approve who joins, or let everyone in), guests who need the
host's consent, and meeting recordings that land in the creator's own Google Drive / OneDrive at a chosen
quality, with a notification when the upload is done. Course sessions already had a guest link and a recording
pipeline into session materials; calendar meetings had neither. Contract: `docs/backend/live-rooms-spec.md`.
**Decision.** A `LiveRoomRef(kind, id)` (session | meeting) names the room everywhere new; the old
`sessionId = -meetingId` convention stays only inside `JoinArgs` for the older room code. Admission is enforced
by the SERVER by withholding the LiveKit token: every join may answer 202 `waiting` and the client polls a
request until it is admitted, so a waiting person never holds a token (nothing to kick, nothing to leak). The host
is alerted in the room (4 s poll + the `live_join_request` silent push) and by a normal notification only when
not in the room, at most once a minute. Meetings record through a separate route family
(`/live/{kind}/{id}/recordings`, chunks like the session recorder) so the course flow is untouched; the server
assembles ONE file at the chosen quality, uploads it to the connected drive, deletes its copy and notifies.
Drive tokens are stored encrypted on the server (the app never sees them); the OAuth consent runs in the
browser. New UI text is inline `t(ar, en)` (org pattern) so parallel work never fights over `translation.json`.
**Rejected.** Admitting with LiveKit room metadata / data messages after a token is issued (a refused person
would already be connected); recording meetings into session materials (they belong to no course); uploading
from the phone to the drive (the phone may die mid-upload, and the drive token would have to live on it).
**Consequences.** `guest_admission` defaults to `approve`, so existing session guest links now wait for the
teacher until guests are switched to automatic. The backend schema is revision `0017_live_rooms`. An operator
must set `GOOGLE_DRIVE_CLIENT_ID/SECRET` and / or `ONEDRIVE_CLIENT_ID/SECRET` (plus `APP_URL` as the public
backend URL for the OAuth redirect) before the drives show as available.

## D-059 — The live room lives above the Navigator so it can be minimized to a box · 2026-10-27 · accepted

**Context.** People wanted to keep a meeting running in a small box while moving around the app, as video apps do.
`RoomPage` was a route: leaving the route disposed the LiveKit room, the recorder, chat and timers.
**Decision.** `LiveRoomLayer` (`lib/features/shared/live/live_room_host.dart`) sits in `MaterialApp.builder`
around the app's Navigator. `PreJoinPage` opens the room into it (`LiveRoomHost.open`); the layer draws the page
full-screen inside its own nested Navigator, or, minimized, keeps the page mounted offstage and draws the box
(`LiveMiniTile`). The back button is answered by an observer registered before `runApp` (so before WidgetsApp's
own): full-screen it closes the room's dialog, else minimizes; minimized it is the app's. The pre-join page stays
beneath the full-screen room and removes itself when the room is minimized or closed, so callers that await it
behave as before. Signing out closes the room.
**Rejected.** A transparent route left on the stack (a route's barrier eats every touch meant for the pages
beneath); re-parenting the page with a GlobalKey between a route and the layer (fragile across the route's exit
animation); a second LiveKit connection for the box (double media, double bandwidth).
**Consequences.** Inside the room `Navigator.of(context, rootNavigator: true)` is the layer's navigator, so
`showDialog` lands above the room without changes. Dialogs the room opens on its own (session ended, connection
lost) call `expand()` first. The Android placeholder screenshot is skipped while minimized (nothing is painted).
`LiveRoomScope.maybeOf` keeps a plain-route fallback for tests and older hosts.

## D-060 — A Content-Security-Policy on Firebase Hosting for the web app · 2026-10-28 · accepted

**Context.** On the web the access and refresh tokens live in `localStorage` (`token_storage.dart`) and the
hosting sent no CSP: one injected script could read them and keep a renewable 7-day session (audit S8).
**Decision.** `firebase.json` → `hosting.headers` sends one `Content-Security-Policy` for every path (JSON has
no comments, so the reasoning lives here). What each source allows: `script-src 'self' 'unsafe-inline'
'wasm-unsafe-eval' www.gstatic.com apis.google.com *.googleapis.com` — `index.html` carries inline scripts (the
`_flutter.config` block and the splash remover that `flutter_native_splash` regenerates, so hashes would break
on every regeneration), CanvasKit is fetched from `www.gstatic.com/flutter-canvaskit/` and compiled as
WebAssembly (`'wasm-unsafe-eval'`; dart2js output needs no `'unsafe-eval'`), the Firebase Auth popup loads
`apis.google.com`; `style-src 'unsafe-inline'` — the Flutter engine writes inline styles; `connect-src` — the
API and LiveKit (`https://nextbrain.site`, `wss://nextbrain.site`), Firebase (Remote Config, Installations, FCM
registrations, Auth, RTDB: `*.googleapis.com`, `*.firebaseio.com`, `*.firebase.com`, `*.firebaseapp.com`,
`*.google.com`) and the CanvasKit / Noto fallback-font fetches (`*.gstatic.com`); `img-src` / `media-src
https:` — avatars, ads and lecture videos come from any https host (Google profile photos, a teacher's link);
`frame-src https:` — the hosted checkout (`IFrameCheckoutPage` opens whatever `checkout_url` the server returns:
Moyasar / Paymob / …) and the Firebase Auth iframe; `worker-src 'self' blob:` — the FCM service worker, the
LiveKit E2EE worker and the recorder compositor; `object-src 'none'`, `base-uri 'self'`. The same header reaches
`firebase-messaging-sw.js`, whose `importScripts` from `www.gstatic.com` is covered.
**Rejected.** Hashes for the inline scripts (regenerated by tooling); keeping the access token in memory on web
and a shorter web token TTL (server-side decisions, not the app's).
**Consequences.** A new third-party origin (a new WebSocket host, a new script host) must be added to
`firebase.json` or the browser blocks it silently — check the console after the first deploy. `'unsafe-inline'`
scripts stay allowed, so the header blocks remote script loads and exfiltration to unknown hosts rather than
every inline injection.

## D-061 — Picture-in-Picture for the course player stays Android-only; the pre-join mic meter uses LiveKit's visualizer · 2026-10-28 · accepted

**Context.** `VideoPlayerScreen` minimizes to a system PiP window through `package:floating` (6.0.0), whose
pubspec declares the Android platform only ("Available only for Android", iOS and web "not planned"); the
parity audit (`docs/polish/screens-parity.md`, "Picture-in-Picture") flagged the iOS gap as unexplained. The
pre-join microphone meter was web-only (`prejoin_mic_meter_stub.dart` returned 0 off the web).
**Decision.** iOS PiP is deferred: the Minimize button is drawn only when `_pipAvailable` is true, and that flag
is set only on Android (`_initOrientationAndPip`), so iOS shows no dead button. Real iOS PiP needs
`AVPictureInPictureController` over an `AVPlayerLayer` — `video_player`'s iOS implementation does not expose its
layer, so it would mean a second native player (or a plugin that brings one) under the same controls, offline
AES-CTR source and screen protection. That is a separate piece of work, not a flag. The pre-join meter on
Android / iOS reads `livekit_client`'s own `createVisualizer(track)` (an `AudioTrackSink` the plugin attaches
to the local flutter_webrtc track by id, so it works before any room exists; bands normalised 0–1, the meter
shows the loudest band) — no new package, nothing in `pubspec.lock` changed.
**Rejected.** A second PiP plugin for iOS (`fl_pip`, `simple_pip_mode`, …: another native player path next to
`video_player`, and `floating` would still be the Android one); a hand-rolled iOS PiP over `video_player`'s
private layer (breaks on the plugin's next release); a new mic-level plugin (the LiveKit visualizer and the
web analyser already cover every platform).
**Consequences.** iOS keeps background audio (`UIBackgroundModes: audio` is already in `Info.plist`) but no
floating window; the parity table says "deferred (D-061)" rather than "gap". If `floating` ever gains iOS, the
only change is the `defaultTargetPlatform` check in `_initOrientationAndPip`. The meter's native scale is the
visualizer's peak band; calibrate `micLevelFromBands` on a device if a normal voice does not reach the middle
segments.

## D-061 — One breakpoint system: phone < 700 · rail 700–999 on every platform · wide ≥ 1000 · 2026-10-28 · accepted

**Context.** Three breakpoint systems coexisted: `responsive_framework` (450 / 800 / 1920) in `main.dart`,
`Breakpoints` (700 / 900 / 1200) in a course-detail component file, and the role shells' own constants — the
student and teacher shells opened the sidebar at 900, parent / admin / organization at 1000, and the rail shell
(600–899 / 999) was web-only, so a tablet app got the phone shell with a bottom bar.
**Decision.** `lib/design/app_responsive.dart` is the single source (`Breakpoints.mobile = 700`,
`Breakpoints.desktop = 1000`, `Breakpoints.shellFor(width)` → mobile · rail · wide); the old path re-exports it.
Every role shell picks its shell from it, and the rail shell is available on every platform. 1000 rather than
the 1200 first proposed: between 1000 and 1199 every shell showed the sidebar before, so 1200 would have taken it
away from laptops; 1000 only moves the student / teacher shells at 900–999 from a 240 px sidebar beside 660 px of
content to the rail, which is what that width wants. 700 rather than 600 for the rail: it is the line the
calendar's week view and the course detail's two-column layout already use, so one width changes everything at
once; a landscape phone (≥ 700 logical px) gets the rail, a short-and-wide window's natural shell.
`responsive_framework` stays in `main.dart`: it scales text and margins and makes no layout decision.
**Rejected.** Keeping two desktop widths (900 for some roles, 1000 for others); a rail shell gated on `kIsWeb`.
**Consequences.** A new shell or a two-column layout reads `Breakpoints` (or `context.isMobile` /
`isTablet` / `isDesktop`), never a literal; `test/ui/app_responsive_test.dart` pins the mapping.

## D-062 — One navigation shell for every role, badges drawn at the leaf · 2026-10-28 · accepted

**Context.** The three shells (`WideShell` / `RailShell` / `MobileShell`) lived in the student dashboard file and
`DashboardItem` in the teacher's; parent, admin and organization imported them from there. They held 22 hard-coded
`Colors.white` / `Colors.black` (sidebar text, icons, dividers, shadows), and every dashboard registered an
`AttentionService` listener that `setState`-ed the whole shell — all five tab pages — on each attention tick (every
60 s, on resume, on route change), beside two or three badge providers (payouts, transfers, complaints, link
requests, alerts) that duplicated keys the attention feed already carries (`admin.finance`, `admin.support`,
`parent.link`, `parent.alerts`, `org.*`).
**Decision.** `lib/design/app_shell.dart` holds the shells, `DashboardItem` and `AppShell(width:)` (picks with
`Breakpoints.shellFor`, D-061). A tab's count is `badge` (what the feed lacks: the teacher's device-switch requests,
the admin's pending payouts) plus the live count of its `attentionKeys`, resolved by `ShellBadge` — a
`ListenableBuilder` at the LEAF (sidebar pill, rail / bottom-bar `Badge`) — so an attention tick repaints a badge and
nothing else; an item without keys never listens (guests, tests). Colours come from the new on-hero roles
(`onHero`, `onHeroFaint`, `heroGlass`, `heroDivider`, `heroEnd`, `heroTint` in `ThemeConfigProvider`, derived from
the server palette, overridable by `on_hero` / `hero_shade` in the theme response). The student / teacher files
re-export the moved names, so the home headers' imports still resolve.
**Rejected.** `AttentionBadge` on every tab (one key per badge, and it ignores the item's own count); keeping the
`max(own, live)` merge of the org dashboard (the feed carries every section key, so the dashboard call no longer
feeds badges); a `kIsWeb` rail.
**Consequences.** A new role dashboard is `AppShell(width:, currentIndex:, onTap:, items:)` and a list of
`DashboardItem`s with `attentionKeys`; a new badge source goes into the server's attention feed, not into a
provider in the shell. `test/ui/app_shell_layout_test.dart` pins the three shells, the width choice and that a feed
tick does not rebuild the shell.

## D-063 — Charts are hand-drawn CustomPaint primitives, not a chart package · 2026-10-28 · accepted

**Context.** No dashboard had a chart or a trend (Track B analysis, shared problem 5). A chart package (`fl_chart`,
`syncfusion_flutter_charts`, …) brings its own colour system, its own text styles, its own RTL and dark-mode
behaviour, and a dependency that `pubspec.lock` must follow (the `excel` lesson in CLAUDE.md).
**Decision.** `lib/design/app_charts.dart` — `AppSparkline`, `AppBarChart`, `AppDonut`, `AppTrendTile`, `AppLegend`
— is pure `CustomPaint` (about 600 lines) following the dataviz method: thin marks (bars ≤ 24 px, 4 px rounded
caps square at the baseline, 2 px lines, ≥ 8 px end markers with a surface ring, 2 px surface gaps between
touching bars and donut parts), hairline grid, compact ticks, text in text tokens never the series colour, a
legend for ≥ 2 series, tap / hover reveals a group's values, and a semantics label that carries the values. The
palette is derived from the theme — primary · accent2 · a teal from the primary hue (−60°) · purple · a rose from
the primary hue (+90°), each snapped into the mode's OKLab lightness band — and was validated with the method's
script on the default theme (light #FFFFFF, dark #1E2342: every check passes; the contrast warning is relieved by
the value labels and the semantics). Status colours (success / warning / danger) are never series colours.
**Rejected.** A chart package (see above); SVG assets; a web-only (`package:web`) chart.
**Consequences.** A dashboard draws a trend with `AppTrendTile(label:, value:, delta:, spark:)` and a breakdown with
`AppDonut`; a server aggregate that gains a time series feeds `spark` directly. A sixth series folds into "other"
(textLight) — facet or fold rather than invent a hue. Line / area charts over time with axes are not built yet;
add them here, not from a package.

## D-060 — Students host live meetings on a points plan; the platform gets a points wallet · 2026-10-28 · accepted

**Context.** Students may now create live meetings, but only online and private ("Only me"; people come through
the share link), free for the first 15 minutes of each meeting, then through a monthly "live meeting" plan priced
in points (30 points / 30 days). The platform had no points: only the money ledger of course purchases. Contract:
`docs/backend/live-rooms-spec.md` Part 2.
**Decision.** A points wallet in the core: `user_points` (balance), `points_ledger` (every change, balance after),
`points_topups` (buy points with a bank-transfer / InstaPay receipt the admin approves, the same manual flow as the
student subscription) and `service_subscriptions` (what points bought, first service `live_meeting`). A debit is one
conditional UPDATE and an approval a compare-and-set, so balances never go negative and a top-up is credited once.
The free time is per meeting, counted from the room's first join (`cal_meetings.live_started_at`) and enforced by
the server: joins after the limit are refused and a 60 s tick deletes the LiveKit room; the app only shows the
countdown. Prices, days, free minutes and the price of a point are app settings the super admin edits.
**Rejected.** Charging money directly per plan (the user asked for points; points also serve later services);
per-day free minutes (a per-meeting limit is what people know from Zoom, and it is a setting); enforcing the limit
in the app alone (a modified client would ignore it).
**Consequences.** Students get points by card (Moyasar / Paymob, verified server-side, credited once), an approved
receipt or an admin grant. Free time is capped per meeting AND per day (30 minutes by default), so opening a new
meeting every 15 minutes no longer avoids the plan. Plans remind 3 days before the end and may renew themselves
from the balance (Part 3, 2026-10-28).
Quick meetings ("Meet now") and direct guest links (admitted without the lobby) come in the same release.

## D-071 — An optional, unique @username; the app mirrors the rules, the server decides · 2026-10-28 · accepted

**Context.** People asked for a WhatsApp-style handle: chosen at sign-up or later, unique, and usable to sign in.
Contract shared with the backend: lowercase `a–z 0–9 . _`, 3–30 characters, at least one letter, no leading /
trailing / double dot, not `www…`, not ending like a domain (`.com`, `.io` …), a reserved list; errors
`USERNAME_INVALID` / `USERNAME_RESERVED` / `USERNAME_TAKEN` (409, with up to 3 `suggestions`);
`GET /auth/username/check`; `username` on register and `PUT /auth/me` (null / "" removes it); policy
`username_login`; kill switch `auth.username`.
**Decision.** `lib/features/auth/username.dart` holds the mirrored rules and the reserved list in ONE place
(`UsernameRules`), an input formatter that lowercases and drops impossible characters, the defensive check parser
and the error reader. `UsernameField` validates every keystroke locally and asks the server only for a name the
rules accept, after 450 ms, dropping stale answers; the account's own name counts as available. The server stays
the authority: a submit error lands on the field with its suggestions, and an older server (bare 404 / 405 on the
check route, or a throttle) means "can't check now", never a block. Login and forgot-password accept a username
only when the policy says `username_login: true` — a MISSING key counts as false, so an older server is never sent
an identifier it cannot resolve. The app never asks whether a typed sign-in identifier exists: an unknown
username fails exactly like an unknown e-mail (no enumeration on login / reset / OTP routes; only the sign-up
check route, throttled per IP, answers "taken").
**Rejected.** Usernames in Arabic or with capitals (unique index on a lowercase ASCII column, unambiguous to type
and read out); checking availability on every keystroke (load on the throttled route); making it mandatory.
**Consequences.** A new reserved word or rule is changed on both sides (`../back` and `UsernameRules`). The Google
sign-up sheet did not ask for a username in v1 (the route took none; v2 below adds it). Hiding the
feature (`auth.username`) hides the field and the "or username" wording, but the server still resolves usernames
at login until the admin turns `username_login` off.

**v2 (2026-10-28).** *Confirmation:* names the server filled in from the e-mail come with `username_confirmed: false`;
after sign-in (and on a start with a cached session) ONE trigger — `topRouteObserver.didPush` of a role home →
`UsernameConfirmPrompt` (`username_confirm.dart`), re-checked when the signed-in user changes — offers a sheet once per
run: Keep (`POST /auth/me/username/confirm {}`), Change (UsernameField, `{username}`) or Remove (`{username: null}`); a
dismissal is remembered per user id and asked again after 7 days at the earliest. A missing key counts as confirmed
(an older server never prompts); not in view-as, offline, or while an account setup is owed; kill switch `auth.username`.
*Cooldown:* `username_change_available_at` in the future makes the profile field read-only with "You can change it
again on <date>" (AppTime) and a Remove / undo action; 429 `USERNAME_CHANGE_TOO_SOON` (`detail.retry_at`) puts the
current name back, locks the field and is worded by `apiErrorText`. *Google:* the role sheet (shown before the account
exists — register: before Google, login: after 409 `GOOGLE_ROLE_REQUIRED`) holds the optional field; `username` goes to
`POST /auth/google`, and a refused name re-opens the sheet with the error and suggestions on the field, reusing the same
Google token. *Search:* the people pickers whose search the server now matches by @username (org members list and the
manual add picker, calendar invitees, the teacher's course students, the admin parent-link requests) say so in the
hint and show `AppUsernameLine` under the name (`lib/design/app_username.dart`, `usernameFrom` reads the row
defensively). The sign-in identifier kind is decided in ONE place, `identifierKindOf` (mirrors `usernames.classify`).

**Admin edit (round 3, 2026-10-28).** Platform admins set, change or remove someone's @username (e.g. an offensive
one) from the student / teacher and admin edit sheets: `AdminUsernameField` (`lib/features/admin/admin_username_field.dart`:
`UsernameField` with the row's name as current + Remove / Keep + "the person is notified"), `adminUsernameBody` sends
`username` only when it changed (null = remove), a USERNAME_* answer lands on the field with its suggestions; kill switch
`auth.username`. Server: `PUT /admin/users/{id}` and `/admin/admins/{id}` take `username`, same rules and claim as
`PUT /auth/me`, the existing who-may rules unchanged (admins: students / teachers; super-admin: admins). Deliberately
outside the person's cooldown and never stamping `username_changed_at` (an admin fix must not cost the person their own
next change, nor wait 14 days); the result is confirmed, also after a removal (no prompt about a name that is gone). An
admin editing their OWN account goes through the person's rules (cooldown), so the admin form is no way around it. Each
change is audited (`platform.username_changed`, before / after, org_id null) and told to the person in-app.

## D-072 — Premium UI fonts chosen per language, display & reading settings · 2026-10-28 · accepted

**Context.** The whole UI was drawn in Tajawal (plus Bahij for some headings), written as the literal
`fontFamily: 'tajawal'` / `'bahji'` in ~1,200 places, and people could not change the font, the size or the zoom
for young learners or older eyes. Arabic icons also pointed the wrong way in places.
**Decision.** `AppFonts` (`lib/core/display/app_fonts.dart`) holds a catalog of OFL families, one choice per
language: Arabic IBM Plex Sans Arabic (default) · Readex Pro · Noto Kufi Arabic · Almarai · Cairo · Tajawal; English
Inter (default) · Plus Jakarta Sans · Lexend · Atkinson Hyperlegible Next · Nunito (the Arabic ones too). Every
literal became `AppFonts.family` (`'bahji'` → `AppFonts.display`, a bold-only alias of the same font, which is how
Bahij drew); `const` was dropped where that required it and `AppTheme`'s text styles became getters. The two
defaults are pubspec fonts (first frame); the rest are asset folders registered by `FontLoader` when chosen or
previewed (web downloads only what is used); Latin-only files are subset to Latin. Static weights 400–800 (a variable
font's `wght` is not driven by `fontWeight`). The other language's font is the theme's `fontFamilyFallback`.
`DisplaySettings` (device-local) adds text size × the system's, whole-interface zoom (`DisplayZoom`: lays out at
size / zoom, draws × zoom, so breakpoints, insets and hit tests follow), bold text, high contrast (the palette's
muted ink pulled toward the main ink), reduce motion and larger touch targets, with presets; `AppDisplayScope`
applies them in `MaterialApp.builder`. A font or contrast change rebuilds every mounted element.
**Rejected.** `google_fonts` (network at first run, offline app); swapping the bytes behind the family name
'tajawal' at run time (a family cannot be unregistered, so a second switch needs a restart); removing the literals
and inheriting from the theme (RichText, TextPainter and button text styles do not inherit).
**Consequences.** New UI never writes a family name: `appText(...)`, theme styles or `fontFamily: AppFonts.family`.
Documents keep their own fonts (PDF / Word / certificates / the export designer). A `static final` TextStyle
would freeze the font: make it a getter. Icons: `DirIcons` (`lib/design/app_icons.dart`) for logout / login /
exit / subdirectory / north-east / outward, never a language ternary over an icon that mirrors by itself
(`test/ui/rtl_icons_test.dart` reads lib/ for both).
**Added the same day.** Reading spacing (Normal · Comfortable · Wide, `ReadingSpacing`): taller lines and wider
word gaps through AppDisplayScope's default style, the theme's text styles and `appText` (letter spacing in English
only — spaced Arabic loses its joins). Baloo Bhaijaan 2 (rounded, for children) joins the Arabic catalog and the
"Young learners" preset. Reduce motion also parks the decorative loops (shimmers, pulses, live dots, the card
shine) through `syncMotionLoop` and the boot splash's float; spinners, recording indicators and the typing cursor
keep moving, since they tell something. The font tiles are separate list children, so the page loads a font only
when its tile scrolls in. The preferences also follow the account: `GET/PUT /api/v1/me/ui-prefs` (`users.ui_prefs`,
revision 0024), pulled at every sign-in and pushed 2 s after a change, the newer copy winning
(`displaySyncDecision`); a server without the route keeps them on the device. High contrast now also lifts
`secondText`, the on-hero muted / faint / border ink and the video player's dim labels, and the screens whose
UI colours were hard-coded (teacher queue card, exam-analysis kDanger … constants, image upload placeholder,
update dialog, parent report hero) read the palette. What stays hard-coded on purpose: palette definitions,
the admin's theme swatches, Google / card-network / Excel-Word brand colours, certificate and paper artwork, the
splash, payment-card art, file-type colours, and the always-dark video / live-room / cropper chrome.

## D-073 — One design language for the sign-in module · 2026-10-28 · accepted

**Context.** Each auth screen drew its own chrome: the login page had a private layout and switches, the other
pages a primary app bar over a tinted panel, fields were flat grey boxes with an UPPERCASE label, buttons the
generic `PrimaryButton`, and several strings (password rules, terms row, strength words) were Arabic-only.
**Decision.** The look lives in two shared files, so every auth screen inherits it. `auth_shell.dart`:
`AuthScaffold` (BasePage + language rebuild) over the plain-values `AuthLayout` — on a phone / tablet a
brand-gradient hero (back · logo tile · admin name + tagline · language + theme switches, then the page title and
subtitle in on-hero ink) with the form card rising 36 px over its rounded bottom; from 900 px the brand panel
(`AuthSidebar`: logo, headline, mission, features, the admin's stats) beside a calm surface holding the card
(title inside it, max width 440–600). `auth_widgets.dart`: `authHeroGradient` (the theme's primary gradient,
deepened toward `heroShade`, more so in dark mode), `authText` / `authTracking` (AppFonts; letter spacing for Latin
only), `authInputDecoration` (filled, 16 radius, hairline border, a primary stroke plus a 4 px halo on focus via
`AuthFieldBorder`, which lerps so the InputDecorator animates the ring; the prefix icon follows focus / error),
`AuthButton` (gradient, 54 dp, press scale, spinner, light haptic — a `FilledButton` underneath so Enter-to-submit
and screen readers still find it), `AuthOtpBox` (tabular digits, focus ring, error), `AuthPasswordStrength` /
`AuthRequirement`, `AuthOrDivider`, `AuthTextAction`, role cards with a check badge. Every colour comes from
`context.colors` (on-hero roles on the hero), motion is implicit and skipped under `disableAnimations`, forms are
`AutofillGroup`s with the right hints / keyboards / input actions, the last field submits, touch targets are 48 dp.
Login shows a full-width "Continue with Google" button instead of the icon-only circle.
**Rejected.** A font package or a custom display face (D-072 owns fonts); restyling `app_inputs.dart` / the phone
field globally (other screens rely on them — the auth fields match their geometry instead, and the register e-mail
became `AuthEmailField`, which reuses `validateEmail`).
**Consequences.** New auth screens use `AuthScaffold(title:, subtitle:)` and never draw their own header, logo or
switches. `IconTextField`, `StyledDropdown` and `SectionLabel` are shared with profile / complaints screens, which
pick up the new field look. Renders: `test/visual/auth_screens_golden_test.dart`; layout: `test/auth/auth_premium_layout_test.dart`.

## D-074 — Profile links by username: `https://nextbrain.site/@name` · 2026-10-28 · accepted

**Decision.** A confirmed @username is a public profile link, built exactly like the course share link: the route
`/@name` reaches `onGenerateRoute` (Android app link `pathPrefix="/@"` in the same auto-verified intent filter as `/c/`
and `/live/` — verification is per host; web path URL strategy), is parsed by `profileLinkFrom` (one "@", any case,
`%40`, full `https://nextbrain.site/@name` URLs; anything else is not a profile link) and, like `/c/<id>`, a signed-out
visitor goes to login first with the link pending. `PublicProfileScreen` loads the public, unauthenticated
`GET /api/v1/public/u/{username}` (`routers/public_profile_router.py`); only a TEACHER with a CONFIRMED name, an
active, complete account and no pending deletion has a profile — every other case (unknown, auto-filled name =
the e-mail's local part, students, parents, admins, inactive) is the same 404 `user_not_found`, so the route says
nothing about who exists. The courses are the visitor catalogue's own cards (`CourseService.get_courses` +
`CourseResponse`, published / public / not archived / not members-only) without the `teacher` block (which carries
e-mail and phone); the app draws them with the existing `CourseCard`, tapping one opens the usual course page. Every
call counts against the caller's address (`public_profile` bucket, 60 / 10 min → 429). Teachers share the link from
Profile ("Share my profile link", the course link's share sheet / web copy dialog). Kill switches `auth.username` and
the new `profile.public_link` (web list → 403 `public_profiles_disabled`). A link-preview page `/share/og/u/{name}`
mirrors `/share/og/{id}`; neither is wired in nginx (bots get the SPA).
**Rejected.** Public profiles for students / parents (no "public profile" notion exists for them); showing the page
signed out (the course link does not either — the page itself needs no token, so this is a routing change only); iOS
universal links (the app declares no associated domains for `/c/` either).

## D-075 — @mentions in announcements, complaints and meetings: suggest within reach, notify once · 2026-10-28 · accepted

**Decision.** Typing "@" + letters in an organization announcement's body, a new complaint, a complaint reply or a
meeting's notes shows suggestions (`Mentions` / `MentionTextField` in `lib/design/app_mentions.dart`: debounced
250 ms, avatar + name + LTR "@username", tap or Up / Down / Enter / Tab, Esc; on web / desktop the open list takes
Enter / Esc through the new `AppKeyboard.keyClaim`, so Enter picks instead of submitting). One endpoint,
`GET /api/v1/me/mentions/suggest?context=&ref=&item=&q=`, reuses each flow's own scope: announcement = the org tree's
live members for someone who may write announcements there (narrowed to a saved announcement's audience), complaint
= the complainant + `complaint_staff_ids` re-checked with `_visibility` (a new complaint: the platform admins, the
form's "staff" targets), meeting = owner + invitees (a new meeting: the calendar people scope). Rows follow
`usernames.shown` exactly: confirmed names only, auto-filled ones to platform admins. The SERVER parses the saved
text with the same token rule (`services/mentions.py`; an e-mail is never a mention) and notifies only people who can
ALREADY open the item — the announcement's audience snapshot once it is live (never a draft), the complaint's
complainant + staff, the meeting's owner + invitees — so a mention can neither reveal an item nor reach anyone the
writer could not reach; anything else is ignored silently. One notification per person per item (a reply is its own
item), deduplicated by `mention_notices` (context, ref_id, user_id) unique, migration 0027 — an edit tells only the
names it added. Plain notification pipeline (`notify_user`: in-app + push), type `mention`, bilingual title; taps
reuse the existing targets (org home for announcements, `calendar` for meetings, `support` + `target_id` → the
complaint's detail screen, now also for ordinary complaint notifications). Read views render "@name" highlighted
(`MentionText`, LRI/PDI-isolated in Arabic); a tap opens the public profile (D-074) unless `profile.public_link` is
off. Kill switch `mentions` (also off with `auth.username`): plain fields and text in the app; switched off on
EVERY platform → the server neither parses nor suggests. No per-type notification preferences exist, so none apply.
**Rejected.** Suggesting or notifying the wider people-picker scope for meetings / complaints (a non-invitee would
learn the meeting exists and land on a 404); notifying at draft time; diffing old / new text instead of a dedupe
table (removing and re-adding a name would notify twice, and concurrent saves race); an overlay list (inline lists
work in sheets and dialogs and are layout-testable).

## D-076 — Username rollout numbers for platform admins: a kind-only event log + a daily sign-in counter · 2026-10-28 · accepted

**Decision.** The admin "Usernames" page (Support & security, kill switch `admin.username_stats`,
`lib/features/admin/admin_username_stats.dart`) reads `GET /api/v1/admin/usernames/stats?days=7|30|90` (admins and
super admins, `require_admin`). The SNAPSHOT (accounts, with a username, confirmed, still waiting for the
keep-or-change answer, none) is computed from `users` at request time, so it is exact from day one; only the FLOWS
start at deploy (migration 0026, no back-filled history): `username_events` holds one row per change — the kind
(backfilled · chosen_at_signup · set_in_profile · changed · removed · confirmed_kept / _changed / _removed ·
admin_set · admin_cleared) and the UTC time, never a name, `user_id` without a foreign key — and `sign_in_daily`
counts successful sign-ins per UTC day and method (email · phone · username · id = the data-lab ID login · google;
"successful" = the password or Google was right, so an MFA step counts at the password). `login_history` keeps one
row per user and `auth_attempts` is pruned after 2 days, so neither could answer a 90-day window. Events are written
from the one place each change happens (`username_service.change` / `confirm` / `backfill`, register and Google
sign-up in `auth_service`, the admin edit in `admin_panel._set_username_by_admin`): `username_stats.note` queues the
kind on the session and `commit_claim` writes it in its own commit AFTER the change is committed, swallowing any
error, so a refused claim writes nothing and a stats failure never fails the request. `prompt_conversion` =
answered / (answered + still pending) over the window. The page shows tiles (snapshot), trend tiles with
sparklines, a donut (confirmed / waiting / none), the flows as bars, sign-in methods as a donut and the daily trend
folded into at most 10 bars (`usernameTrend`); everything from `app_charts.dart`.
**Rejected.** Storing old / new names in the log (the stats need counts only); a row per sign-in (grows without
bound and says who signed in when — a per-day counter answers the question); adding a method column to
`login_history` (it keeps only the latest login per user); writing events inside the user's transaction (a logging
error would roll the change back).

## D-077 — Lazy shell tabs: a role dashboard builds a tab on its first visit and keeps it · 2026-10-28 · accepted

**Decision.** `AppShell` (D-062) draws its tabs through `LazyTabStack` (`lib/design/app_shell.dart`): an
`IndexedStack` that builds the open tab at once and every other tab only the first time it is shown, then keeps it
mounted (state and scroll position survive switching back). There is no preload option: no role needs one. A tab's
count still comes from `ShellBadge` at the leaf (its `badge` + the live attention keys), never from the tab's own
widget, so an unbuilt tab still shows its badge. Opening a home used to build every tab and fire every tab's loads:
requests on open went student 17 -> 11, teacher 15 -> 11, super admin 10 -> 7, org admin 15 -> 4 (parent and
member 3, unchanged). The budgets in `test/perf/home_requests_<role>_test.dart` were lowered to the new numbers, so
a regression fails CI.
**Rejected.** Building every tab at open (the old `IndexedStack`: one home's open cost every tab's requests);
rebuilding a tab on every visit (loses its state and re-fetches); a per-tab preload flag (no role uses it, and it
would quietly bring the cost back).

## D-078 — Live classes stay on LiveKit (WebRTC SFU) + server recording; the 5 s chunks are a recording path only · 2026-10-29 · accepted

**Decision.** Live delivery stays on the self-hosted LiveKit SFU (WebRTC: adaptive stream, dynacast, simulcast,
sub-second latency, reconnection in the SDK) for every platform. The device-uploaded 5 s chunks that the server joins
with ffmpeg were never the live path: viewers always watched over WebRTC. They are the client recorder
(`RECORDING_MODE=client`) and the meeting recorder to Google Drive / OneDrive. Server recording (LiveKit Egress) is
the target for both, tuned for low CPU and high screen-share quality (the design follows the recording research in
`docs/live/`); the device recorder stays as the fallback while older app versions exist. The audit that led here is
`docs/live/audit/` (2026-10-29).
**Rejected.** Replacing WebRTC with LL-HLS or RTMP/SRT ingest for live classes (seconds of latency, no two-way
audio, a transcoder per room — worse for interactive teaching); fixing the chunk path as a live transport (it was
never one); a second media server next to LiveKit.

## D-079 — Live annotation: vector strokes over the data channel, burned in only for Android whole-screen share · 2026-10-29 · proposed

**Decision.** Annotations are vector strokes sent on the LiveKit data channel, never pixels: topic `annot`
(reliable) for stroke start / points / end, undo, erase and clear, and `annot.laser` (lossy) for the laser pointer.
Points are normalised to the shared video's content rect (0..1 on both axes, mapped through each viewer's `contain`
fit), carry pressure 0..1, and are batched every ~33 ms. Tools: pen, highlighter, stroke eraser, undo (per author),
clear all (host), colour, thickness (a fraction of the frame width), laser (fades). Late joiners get the current
board from the presenter as a snapshot packet. The presenter and the host draw; students draw only when the host
allows it. This is what Zoom / Teams do: the presenter annotates on top of the share, viewers see it in real time.
Where the presenter shares the WHOLE screen from Android, a floating toolbar + canvas is drawn over other apps
(`SYSTEM_ALERT_WINDOW`, asked once, with an in-app fallback when refused); MediaProjection captures that overlay,
so the strokes are burned into the shared video (and every recording) and are not also sent as vectors (no double
drawing); students cannot annotate in that mode. iOS cannot draw over other apps (ReplayKit has no overlay), and a
browser cannot draw over another tab or window, so there the presenter annotates on the in-app view of the share and
the strokes travel as vectors.
**Rejected.** Sending annotation as video (latency of the video path, blurry text, recording-only quality); burning
in on every platform (impossible on iOS / web); absolute pixel coordinates (break across screen sizes and
orientations).

## D-080 — Android screen share: share-only mode, device audio mixed into the mic, a "soft mute" while it runs · 2026-10-29

**Decision.** The Android share no longer depends on a recording: `ScreenCaptureService` runs a share-only mode
(MediaProjection + `ScreenPlaceholderRenderer`, no MediaRecorder, FGS type mediaProjection + microphone). Every
share start switches the renderer to live; share stop releases the VirtualDisplay and keeps the projection only
while a recording runs below API 34 (a 34+ projection makes one VirtualDisplay); the system's own Stop ends the
share (event `shareStopped` on `live_events`) without ending the recording. Device audio (API 29+) is captured
with `AudioPlaybackCaptureConfiguration` (usages MEDIA / GAME / UNKNOWN, the app's own uid excluded: no echo of the
remote voices) and mixed into the outgoing mic buffer through WebRTC's `JavaAudioDeviceModule.AudioBufferCallback`
in the flutter_webrtc fork (`ElFaheemAudioMixer`), the way LiveKit's native Android SDK does it — not a separate
`screenShareAudio` track, which the fork cannot feed. Because the shared audio rides on the mic track, muting the
mic during such a share zeroes the mic samples natively ("soft mute", `LiveMicGate` in the app) and keeps the
track publishing; viewers then see the presenter's mic as on. At share end a soft mute becomes a real mute again.
Presets: Detail (≤1920 px long side, ≤15 fps, 2.5 Mbps, maintain resolution) and Motion (720p, 30 fps, 3 Mbps,
maintain frame rate), one layer each. A phone call (call audio mode, not a media app taking focus) mutes the mic
and restores it afterwards.
**Rejected.** LiveKit mute during device audio (it disables / stops the mic track: the shared audio would go
silent too, and the SFU drops a muted track's packets); a second AudioRecord-fed track (no custom audio source in
this WebRTC build); muting on every audio-focus loss (a video played in another app during the share would mute
the presenter).

## D-081 — The role's tabs stay on every page: one navigator per shell tab · 2026-10-29 · accepted

**Decision.** Every tab of `AppShell` (D-062, D-077) owns a navigator (`AppTabNavigator`, `lib/design/app_shell_nav.dart`),
the Instagram / YouTube / Teams pattern: a page opened from inside a tab keeps the role's tab bar (phone bottom bar,
tablet rail, desktop sidebar + top bar), each tab keeps its own back stack while the person switches tabs, a tap on
the current tab goes back to its root, and the system / browser back pops the visible tab first, then goes to the
home tab, then leaves as before. The tab stack is one GlobalKey'd subtree, so a rotation that changes the shell kind
(phone landscape is the rail) keeps every stack. Code written for one app-wide navigator keeps working because the
tab navigator hands up what must not live in a tab: dialogs and bottom sheets (they still cover the bar), any
`fullscreenDialog` page (image cropper, attendance live, forms), the auth routes and the role homes by name
(`shellRootRouteNames`), guest live links, and every replace / remove-until that would remove the tab's own root
(sign-out, "back to home"), plus a `pop` / `maybePop` of the tab root. Named routes inside a tab are built by the app's
own `_router` (the root navigator's `onGenerateRoute`), so `pushNamed` behaves the same. Full-screen experiences stay
full-screen: the live room already lives in `LiveRoomLayer`; the exam sittings are pushed on the root navigator; the
video player, the legacy quiz and the pre-join page call `AppShellNav.markFullScreen(context)` and the shell draws no
chrome while such a page is the visible tab's top. Deep links (`AppNavigator`: notification taps, pushes, shared
links) push into the visible tab when a shell is on screen (the bar stays) and onto the root navigator otherwise;
org dashboards and other homes still open on the root. `topRouteObserver` reports the page the person sees
(`currentRoute` = the visible tab's top inside the shell, `rootRoute` = the root navigator's top) and refreshes
the attention badges on tab pushes / pops as it did on root ones (a tab's own first page is not a navigation: the
request budgets are unchanged). `leaveToPersonal` also pops the tab it was pressed in. Tests:
`test/ui/app_shell_nav_test.dart`; renders: `test/visual/nav_assistant_golden_test.dart`.
**Rejected.** A persistent bar drawn around the single root navigator (pages would keep the bar but every dialog /
sheet would sit inside the content area beside it, and a tab switch would have to drop the pages: no per-tab
stacks); `go_router` / `StatefulShellRoute` (a rewrite of every route and of the 300+ `Navigator.push` call sites);
pushing every page on the root (today's behaviour: the bar disappears, the request that started this).
**Known differences.** A tab's first page no longer shows an implied back arrow when the dashboard itself was pushed
above another page (the org dashboards have their exit button); on web the address bar keeps the dashboard's path
while pages are open inside a tab.
## D-082 — Fingerprint / Face ID sign-in with a device-bound key; the sign-in hero speaks the dashboard hero's language · 2026-10-29

**Context.** The owner asked for biometric login "to accelerate login", and for login bars that feel like the
dashboard. The cheap way — keep the refresh token alive across a sign-out and unlock it with the fingerprint — turns
a sign-out into a no-op for anyone who can read the app's storage, and a stolen refresh token into a permanent one.
**Decision (security).** Each phone enrolls its own credential (`lib/features/auth/biometric.dart`, back
`services/biometric_service.py`, migration 0029):
- *Key.* An Ed25519 pair made on the phone with package:cryptography (already in the lock file, pure Dart); the
  private seed lives in the keystore (`BiometricKeyStore` in `token_storage.dart`: Android EncryptedSharedPreferences,
  iOS Keychain `unlocked_this_device`), apart from the session tokens, so a sign-out keeps it. The server stores only
  the public key and sha256 of the device id.
- *Enrolment proof.* An access token alone cannot enroll (a leaked one would mint a credential that outlives it):
  the call needs the `biometric_enroll_token` every login answer now carries (10 minutes, bound to the user, their
  token_version and `X-Device-Id`) or the password (+ the MFA code), which the Security switch asks for. Students
  enroll only a device registered to the account. One active key per device, at most 5 per account.
- *Login.* `local_auth` with `biometricOnly: true` (never a silent fallback to the device PIN — the password form is
  the fallback) releases the seed; the app signs `nextbrain/biometric-login/v1\n<credential>\n<challenge>\n<device
  id>` over a single-use 2-minute challenge, which the server claims with a compare-and-set before checking the
  signature. The session then starts through the password login's own gates (`start_biometric_session`: deactivated,
  unverified, temporary-password expiry, the student's single session) and its **second factor**: the biometric check
  is enforced by the app, not bound into the key (pure Dart cannot ask the keystore for a biometric-bound key), so the
  key counts as one factor and an MFA account still answers `mfa_required`.
- *Revocation.* The switch / "Not you?", every "sign out everywhere" event (`revoke_user_tokens` except a student's
  new sign-in and a plain sign-out: password change / reset, revoke-all, MFA on / reset, deletion), 5 bad signatures,
  a deactivated account, a student device no longer registered, 90 days unused (`BIOMETRIC_IDLE_DAYS`). Throttle kind
  `biometric` (10 per key + address, 20 per key, 30 per address / 15 min); the enrol token, challenge, signature and
  seed are in `logSensitiveKeys`.
**Decision (product).** Android 9+ and iOS only (Android 8 needs an AppCompat launch theme for the legacy fingerprint
dialog; the app's themes are not AppCompat, so those phones simply don't get it), hidden on web and by the kill
switch `auth.biometric`. After a password / MFA / Google sign-in the app offers it ONCE per account and phone ("Not
now" is remembered; the Security switch next to two-step verification stays — it now shows for every role on a
supporting phone). The login screen greets the remembered account by name with its photo, the big fingerprint / Face
ID button and "Not you?", prefills the identifier, and opens the prompt by itself once per app run — never right after
a sign-out. `MainActivity` extends `FlutterFragmentActivity` (local_auth's requirement; the MediaProjection
`startActivityForResult` / `onActivityResult` path is unchanged — both exist on `FragmentActivity`), manifest
`USE_BIOMETRIC`, iOS `NSFaceIDUsageDescription` (English only: the project has no InfoPlist.strings localisation).
**Decision (look, amends D-073; colours amended by D-088).** The sign-in hero speaks the dashboard hero's language:
`AuthHeroBackdrop` carries the home hero's signature ring and a soft top sheen, and the phone hero floats on the same
brand glow as the home hero; the wide brand panel uses the same surface (one extra glow for its height). Its colours
are a blend of the theme's **primary (70 %) and accent (30 %)** — the owner's call, D-088: `authHeroGradient` runs pure
primary over the first 40 % of the surface, then straight into the accent ("Accent 1" on the admin Theme page), so the
mean colour is exactly 70 / 30; the tall wide panel runs corner to corner, the short phone hero toward its end side
(the accent stays in the part above the card). Each stop is guarded by `authHeroStop`: deepened along its own hue
(lightness only, saturation capped at 0.62 — a cream accent becomes bronze instead of greying) until even the muted
on-hero ink — subtitles, tagline — reads at 4.5:1 with a margin for the glows (6.4:1 in dark mode, the step deeper a
bright block needs there). A monochrome theme (accent ≈ primary) gets shades of the primary. The primary button
(`AuthButton`) uses the same 70 / 30 stops, deepened until its label reads at 4.5:1 (the server's
`gradient_primary`, accent → accent 2, put white text on cream). The splash → login hand-off is untouched (the logo
tile keeps its Hero tag).
**Rejected.** Keeping the refresh token across sign-out; an HMAC device secret (a server-side secret to protect,
where a public key needs none); skipping MFA after a fingerprint; the dashboard sidebar's charcoal for the wide
panel (rendered muddy next to the brand hero); a separate biometric settings page.

## D-083 — Live annotation ink like a real pen; the Android whole-screen overlay is a bubble outside the app; the presenter's window is never secure while sharing · 2026-10-29 · proposed

Amends D-079 (what the overlay looks like and when it shows; burned-in only stays).
**Decision.** (1) Ink. The drawer filters its pointer samples before they go out (`annotation_ink.dart`,
`AnnotationInk.kt`): a 2-D One Euro filter (one speed for both axes; min cut-off 1 Hz, β 0.025, d-cut-off 1 Hz —
roughly half the jitter at slow speed, under 3 px behind the nib at writing speed, and the stroke still ends on the
nib), pressure through an exponential average with a 0.08 step limit, samples under 0.8 px apart dropped. The
filtered points are the wire points, so every device draws the same numbers with the same renderer: the midpoint
chain of quadratic Béziers; a stylus stroke (`pr: 1` on its start, additive in protocol v1; older senders are guessed
from the pressures and the guess sticks) is ONE filled shape — circles and bands along the densely sampled centre
line, all clockwise under non-zero fill — with causally averaged radii (pressure factor 0.55–1.45) and tapered ends;
finished pieces are cached and only the last piece is rebuilt, so nothing already drawn moves; a finger / mouse
stroke is one stroked path with round caps (constant width); the highlighter one translucent stroked path. x / y go
out with 5 decimals (4 were a 0.26 px grid on a 2560 px screen), pressure with 3. A finished stroke is no longer
re-simplified (RDP moved the curve under the pen as it lifted), and snapshots carry every point (late joiners draw
exactly what the others see). (2) Android whole-screen share: the overlay is ARMED when the share starts (with the
permission) and shows only while the presenter is outside the app: a 56 dp draggable bubble that snaps to a side;
tap → a compact toolbar (pen, highlighter, eraser, laser, use apps, colour, thickness, undo, clear, hide tools,
close = clear) and a transparent canvas over the app below (touches pass through when drawing is off). Back in the
app the windows go and the strokes are kept for the next time the presenter leaves; a rotation clears them; the
share stopping (Dart or natively, `ScreenCaptureService.stopShare`) clears everything. Strokes stay burned into the
video only (MediaProjection captures the overlay), never also sent as vectors. (3) Screen protection has one owner
(`lib/core/screen_security.dart`): protected screens (course video, exams) protect / release with themselves as the
owner; a whole-screen share (Android MediaProjection, iOS ReplayKit) clears an OWNERLESS protection —
`ShareWindowGuard.kt` clears FLAG_SECURE and marks the Flutter view not sensitive (API 35+), logging what it found —
and puts back exactly what it changed at the end; an open protected screen keeps its protection (a course video or
an exam paper never goes out in a share).
**Rejected.** Sending the overlay's strokes as vectors as well (double drawing on every viewer, or a mode switch per
viewer); showing the overlay over NextBrain itself (it took every touch in the app); clearing FLAG_SECURE for the
whole share regardless of who set it (a course video under the room would be broadcast); smoothing on the receiver
only (the drawer's preview and the viewers would differ); Catmull-Rom through every sample (it passes through the
jitter); per-axis One Euro (flattens curves where one axis slows down).

## D-084 — The Analytics tabs compare with the class, not with a previous period · 2026-10-29

**Decision.** The student's and the instructor's Analytics tabs are one summary page (`shared/analytics/
analytics_summary.dart` pure, `analytics_summary_ui.dart` plain-value widgets): concentric rings for progress ·
attendance · exams around the overall figure with ONE sentence, four count tiles, "For you" (up to three
plain-language nudges, one of each kind before a second, each opening what it is about), one bar per course for the
metric picked in a segmented control (the class average as a tick), and compact lists (exam results / students who
need attention, the first 3 + "Show all" in place). The full course cards with search, sorting and every per-course
shortcut moved one tap down ("All courses"), keeping their feature keys. The page reads only what the screens already
load (enrolments + the Data Lab profile; the course list + `GET /data-lab/overview`): no new request. The owner's
brief asked for a week / month / term switch and a trend line; neither payload carries a date (both are snapshots),
so the deltas are "vs class" (the class averages the teacher shares) and the segmented control picks the METRIC.
A real period switch needs a dated history from the server (e.g. a weekly snapshot of the profile); the same widgets
then take it. Tests: `test/ui/analytics_summary_test.dart`, `analytics_summary_layout_test.dart`; renders:
`test/visual/analytics_golden_test.dart`.
**Rejected.** A period switch over undated numbers (it would change nothing); calling `GET /student/exams` from the
tab for dated exam scores (one more request on every open, and only exams would follow the period); a percentile
("ahead of 70 % of your class": the server sends class averages, not the distribution).

## D-086 — One Complaints page in the profile: New complaint · My complaints · To resolve · 2026-10-29

**Context.** The owner (item 9): the complaints entry of the profile tab, for everyone but the super admin, opens a
new complaint and the history, and non-students may open the complaints they must solve from it. The app had two
complaint systems with separate screens: platform complaints (`/api/v1/complaints`, one list mixing my own with the
ones I handle, no create button on it) and organization complaints (`/api/v1/org/…/complaints`, reachable only
inside the organization's pages).
**Decision.** `ComplaintsHubPage` (`lib/features/shared/profile/compalints/complaints_hub_*.dart`) is the page of the
profile's Help-center tile, the parent's "More" tile, the `support` deep link without an id and the profile's
complaints attention item, for every role whose home is not the admin dashboard (admin / super-admin / developer
keep `ComplaintsScreen`, the console).
- *One row shape* (`HubRow`, pure, `test/org/complaints_hub_test.dart`) over both sources; a row opens its existing
  thread (platform `ComplaintDetailScreen`; organization member side `OrgMyComplaintThread`, made public; staff side
  `OrgComplaintThreadScreen`, which now takes `orgId` / `canAct` so it works without opening the organization).
- *My complaints*: platform `scope=mine` + `GET /org/public/me/complaints`; unread replies first, then the latest
  change.
- *To resolve*: platform `scope=to_resolve` + the new cross-organization `GET /org/public/me/complaints/to-resolve`
  (departments where I may update complaints + those assigned to me, never my own). Most urgent first: open, overdue,
  nearest reply-by, priority, unread, oldest. A platform complaint has no reply-by on the server: its priority's usual
  window (the organizations' SLA hours from its creation) orders it but is never shown as a deadline. Quick Start /
  Resolve are optimistic and rolled back on refusal; Reply opens the thread. Shown to everyone but students and
  parents, and to anyone who has rows there (a student who is a department's staff member).
- *New complaint*: no organization → the platform form (`NewComplaintScreen(formOnly: true)`); a member of
  organizations first picks the destination (the app team or one of them → the organization's composer).
- Both lists are loaded at once (4 requests on open), at most 100 platform rows and 50 / 100 organization rows per
  list, filtered and searched on the device; an older server's ignored `scope` is split by owner, its missing
  cross-organization route reads as "nothing there".
**Rejected.** Merging the two complaint systems on the server (a migration and every existing screen); listing the
governance work items instead (their comments are not the complaint thread); opening the organization (mode switch,
timezone, disable list) just to read one complaint; server-side search per keystroke over two sources.

## D-088 — Sign-in colours 70 % primary / 30 % accent; the language is a switch in the settings row; Terms, Privacy and About are reading pages with the assistant one tap away · 2026-10-29

**Context.** The owner asked for (1) the login bars to mix the app colours, primary 70 % and accent 30 %; (2) the
language to change with a switcher like the login's, not a page; (3) premium privacy / terms / about pages; (4) a bot
on the privacy and terms pages that opens the app assistant.
**Decision.**
- *Sign-in colours* — see D-082 (look), which this amends: `authBrandStops` = primary · primary · accent at
  0 · 0.40 · 1 (mean colour exactly 70 / 30), every stop deepened along its own hue for the on-hero ink; the same
  stops paint `AuthButton`. The a11y guideline test keeps guarding the contrast on the default theme.
- *Language* — `AppLanguageTile` (`lib/design/app_language_switch.dart`) is the row on every role's settings page
  (profile = student / teacher, admin More, parent More, org Preferences; kill switch `profile.change_language`
  unchanged): icon · "Language" · `AppLanguageSegmented`, a pill with "عربي" · "EN" (the login toggle's labels) and a
  sliding primary thumb, 48 dp hit areas, a selected state for screen readers, no slide under Reduce motion. A tap goes
  through `LangProvider.changeLang` and then `refreshWholeUi()` after the frame, as the old page did on its pop.
  `ChangeLanguageScreen` is deleted.
- *Reading pages* — `TermsScreen(privacy:)` and `AboutScreen` (same routes, providers and endpoints) are rebuilt
  from plain-value parts (`about_terms_parts.dart`): a calm hero card (brand icon tile, title, intro, meta pills:
  updated · version · read time · sections), the sections as numbered cards with 16 px body text at 1.85 (ar) / 1.7
  (en) line height through `appText` (the person's reading spacing applies), bullets and numbered steps parsed from
  the admin's text (`readingBlocks`, pure); a table of contents that follows the scroll — section chips pinned under
  the app bar on a phone, an "On this page" column beside a 760 px reading column from 1000 px; a closing note.
  "Privacy" in the profile opens the same content introduced as privacy & terms (the server has one terms document).
  About: hero with the logo, figures, mission quote, features (equal-height rows), team, and ONE "Contact & support"
  card (contacts, the assistant, the installed / latest version and release notes). Loading draws the page's shape
  (`ReadingSkeleton`); an error / empty page is `AppEmpty` with a retry. The accordion and the terms search are gone:
  the table of contents does that job on a document of a few sections, and an open page reads better than a closed one.
- *Assistant on the page* — a bot button in the app bar and, on a phone, a floating "Ask about this page" pill (it
  folds to the bot disc while scrolling down) or, wide, a card under the table of contents. They call
  `AppAssistant.ask(question)`: the pop-up opens on a NEW chat with a page-specific question typed in the box, NOT
  sent (`RagChatViewState.draft`; before the conversations load the boot opens a new chat instead of the latest). Shown
  only when `AppAssistant.availableFor` (signed in, not a guest, kill switch `rag.app_assistant` off).
**Rejected.** A single flat 70 / 30 colour (no depth, and the accent disappears into the mix); greying a light
accent toward the shade for contrast (cream became taupe); keeping the language page next to the switch;
`Scrollable.ensureVisible` for the active chip (it also scrolls the page under the pinned header back up); sending
the page question automatically (the person should see and own what is asked).

## D-085 — "My schedule" and "My calendar" are one page · 2026-10-29 · accepted

**Decision.** `SchedulePage` (`lib/features/shared/calendar/schedule_page.dart`) is the only schedule / calendar page:
the student and teacher shells' Schedule tab (`asTab: true`), the top-bar calendar icon, `'/calendar'` (deep links,
notification taps, AppNavigator `calendar` / `live_lobby`, the org and department dashboards; `CalendarScreen` /
`CalendarView` are thin names for it) all open it. Views: Agenda (phone default — today pinned, then only the days
that hold something, a "now" line), Day (week strip + time grid on phones), Week (desktop default), Month (desktop:
the big grid; phone: a month of dots + the picked day's list). Desktop gets a sidebar: New meeting / Meet now, a mini
month showing the visible range, Up next, invitations to answer, the filters. Filters are four kinds (classes · exams
· live · meetings) + the organizations, remembered on the device (`calendar.filters.v1`). Colours come from the
theme per kind (classes primary, a lab toward success, exams danger, live purple, meetings gold).
**Data.** ONE `GET /me/calendar?detail=true` per visible range through `CalendarStore` (cached 3 min; the agenda
and the day view fetch whole weeks from the start of their week so the week view reuses them; a wider chunk serves
every range inside it). `detail=true` (additive, back `b2c4784`) adds each changed date's `change` (online /
substitute / cancelled with the answers, `can_respond` / `can_edit`), keeps cancelled dates with `cancelled: true`
(an older app never asked, so it never shows them as classes) and returns `pauses` (exam windows pausing the
weekly classes). A personal course's weekly appointments (`GET /student|teacher/schedules`) are expanded to dated
`course_weekly` events in the app (cached 15 min, never failing the page). Live: the store reloads on the new
stream-only `calendar_updated` (every meeting notification), `meeting_live`, `session_live` and timetable /
exam-timetable `attention_changed`; "Live now · Join" comes from the home's `MeHomeService.liveNow` (no extra
request). No polling; a one-minute clock only moves the now line. Answers (invitation, one-date change) are
optimistic patches of the cache, then a reload.
**Rejected.** Keeping the tab and the calendar side by side with a shared header (two loaders, two caches, the same
data drawn twice); a calendar package (none draws RTL, theme roles and our event kinds without forking); fetching
`/public/schedule/me` beside the feed for the changes (a second call per range; the feed already knows the dates).
**Removed.** `ScheduleTabBody` and its parts, `StudentScheduleTab`, `TeacherScheduleTab`, `StudentSchedulesProvider`,
`TeacherScheduleOverviewProvider` (the tab's own `/me/calendar` call for "upcoming meetings" is gone).
Tests: `test/ui/schedule_logic_test.dart`, `test/ui/schedule_layout_test.dart`, `test/ui/calendar_test.dart`;
renders: `test/visual/schedule_golden_test.dart`.

## D-087 — Live whiteboard: a presented board of vector items on the data channel, never a video track · 2026-10-29 · proposed

**Context.** The owner: "when share I need to add: can share background and whiteboard to draw on it and typing".
**Decision.** The Share sheet gets two tabs, Screen | Whiteboard (every platform: Android and the web already had
the sheet; iOS and desktop now ask Screen | Whiteboard before the system picker; a phone browser, which cannot share
a screen, gets the Whiteboard tab only). The whiteboard is a 16:9 PAGE of vector items — pen / highlighter ink (the
annotation ink of D-083: same filter, Bézier chain, pressure shape, cache), shapes (line, arrow, rectangle,
ellipse; Shift = square / circle / 45°), text boxes (typed on the phone keyboard or a physical one; the box's
direction follows its first strong letter, so Arabic runs right to left by itself; move, width handle, font size
S / M / L / XL, colour), laser — on a background (white · blackboard · grid · lined), with several pages (add,
previous / next, delete; the presenter's page is everyone's page), undo / redo per person (add, remove, change;
a restored item keeps its id and author), clear page and Save as PNG (1920 px, the page without the selection
frame). Protocol (`whiteboard/board_protocol.dart`): the annotation protocol's sibling on the board SURFACE's own
topics, `board` (reliable: state on / off + background + pages, ink start / points / end, `put` = a whole shape or
text box, last writer wins by revision, delete, clear page, snapshot chunks + request) and `board.laser` (lossy);
page-normalised coordinates, widths and font sizes as fractions of the page width, every packet `v: 1`, unknown
types / keys / item kinds ignored, an unknown background drawn as white, and `bv` (the board's feature version): a
client that receives a newer one shows "update the app" over the board instead of half a board. Apps from before the
board route neither topic (unknown topic = dropped, live_data_route.dart), so they never crash; they keep showing
the presenter's camera. Rules (`whiteboard/board_controller.dart`, pure, unit-tested): one board presenter, who
answers late joiners' snapshot requests (and re-sends the board after a reconnect); the presenter and hosts draw,
edit and remove anything and clear a page; students draw only with the ROOM'S DRAWING PERMISSION (the annotation
permission: everyone or chosen students, from the Board sheet or the participants panel) and edit / remove only their
own items; every packet is checked against the LiveKit sender, never a payload field (a lead may restore an item
with its original author). A board counts as presenting for the one-share rule (D-079's arbiter): its presenter is
in the arbiter's presenters, so a host's takeover, a hand-over and the lead host's enforcement stop it like a screen
share, "Ask to share" can end in a board, and a host stops a participant's board from the board's bar. Who may
present: a host, or someone the server lets share their screen. The presenter's board is kept on their device when
they stop (a switch to a screen share and back finds the pages again); viewers drop it. Each device can pinch /
Ctrl+wheel to zoom its own view (never sent; a "150 %" chip fits the page again). Page and ink colours are content
constants (they travel on the wire and must look the same in every theme, like a PDF's paper), not theme tokens.
Kill switch `live.whiteboard` (back `services/feature_catalog.py`), features guide `live_whiteboard`.
**Recording.** The device recorders capture the room UI, so they show the board as everyone sees it (Android's room
capture at ~2 fps; the web recorder's placeholder still refreshes as the board changes, but a camera that is on wins
over it in the web compositor). LiveKit composite Egress (server recording) records tracks: a board is not a track,
so a server recording shows the cameras while a board is presented. If that matters: publish the page as a low-fps
canvas track only while a server recording runs.
**Rejected.** Publishing the board as a video track for everyone (blurry text, a second encoder on the presenter,
the latency of the video path, and every viewer's zoom would magnify pixels); a separate whiteboard service or a CRDT
library (one presenter owns the state; per-item last-writer-wins is enough); putting board items on the `annot` topic
(an older app would draw them over a later screen share); a free-size infinite canvas (viewers on a phone and a
projector must see the same page; zoom is per device instead); image / PDF page backgrounds (needs an upload route
and a snapshot path for large binaries — later).

## D-089 — Live performance: one recommended set, every either-or a super-admin switch, sent as `live_config` · 2026-10-29 · accepted

**Context.** The owner: "apply all best practice points to improve and minimize the CPU and network connection in
live, and where there are two approaches that must choose one, make the super admin able to switch between them".
Measurements: `back/bench/recording/RESULTS.md` (the Chrome composite needs ~1.5 cores, peak 3, and is BROKEN under
production's `cpus: 1.5` — 6.6 fps, ~80 % of the audio lost; the GStreamer composite 0.5 core pixel-exact; the v2
media egress cheap but black with no share and one failure on a share stop; LiveKit kept a killed egress ACTIVE for
60 s) and the LiveKit load bench (a 720p viewer at a 1 Mbit/s cap froze ~15 s, then 180p for good; webhooks waited
up to 9.7 s on the dev API).
**Decision.** The server keeps ONE settings object (`app_settings` `platform.live`, `GET/PUT
/api/v1/admin/live-settings`, super admin, audited) and sends its effective values as `live_config` (contract v1) in
every live start / join payload; older apps ignore it, the live room applies it (the room code's own model).
Recommended set, and why: VP8 (decodes everywhere, simulcast solid; H.264 = hardware encode on phones, VP9 = ~30 %
less data for more CPU) · weak network `adaptive` (simulcast steps down; `audio_first` keeps only the voice below a
threshold with "Show video") · teacher camera 720p, attendees 360p (thumbnails), 24 fps · screen share 15 fps,
2.5 Mbit/s cap (text needs keyframes, not frames) · DTX + RED on (the voice is protected first) · attendees join with
the camera off · video nobody sees is paused · recording on the server, engine `composite`, ONE 1080p copy (one job
per class instead of up to six). Recording mode replaces the env-only RECORDING_MODE at runtime (the env stays the
default while unset, so production keeps recording on the device until the super admin picks); a run stores its
mode and engine (migration 0030) and finishes in them. Engine `media` = one v2 StartEgress media job (host screen
share preferred + every voice): its black-while-nothing-is-shared caveat is written on its card. The reconcile tick
gets an egress watchdog (no playlist write for 120 s → stop, mark `stalled`, salvage the segments, save the partial
recording); the webhook answers within 2 s and finishes slow work on its own pool. LiveKit: congestion control with
`allow_pause`, codecs, PLI throttle, room guards (dev config in the back repo; production as reviewed proposals
`back/deploy/livekit.production.yaml` / `egress.production.yaml`: egress v1.15 + the SDK compositor + `cpu_cost`,
egress `cpus` 1.5 → 3). The admin page (`lib/features/admin/live_settings/`, kill switch `admin.live_settings`) shows
each either-or as cards with trade-off tags and a Recommended badge, and a live estimate of the data per viewer.
**Not chosen.** Per-organization overrides (a later layer, like the feature disable list); per-room settings chosen
by the teacher (one more decision in front of a class); a recording "auto" mode that picks the engine by whether the
host shares (the media egress cannot switch source mid-run; restarting splits the recording).

## D-090 — Live media follows the super admin's `live_config`; the room lowers video itself on a weak link · 2026-10-29 · proposed

**Context.** The owner: "apply all best practice points to improve and minimize the CPU and network connection in live,
and where there are two approaches, make the super admin able to switch between them". Every publisher sent a 1080p60
camera at 5 Mbit/s; on a 1 Mbit/s downlink the SFU froze 720p for ~15 s and then sat on 180p; an Android Motion share
was 590×1280.
**Decision.** Every live join / start payload carries `live_config` v1 (video codec, weak-network mode, camera caps per
role, camera fps, screen fps / bitrate ceilings, Opus DTX / RED, participants' camera off at the start, pause hidden
video, recording mode / engine); every field is optional and an older server gets the recommended defaults
(`live_config.dart`, numbers and reasons in docs/live/NOTES.md "Live media tuning"). Publish: the role's cap at
camera_fps with explicit simulcast layers (180p@15 · 360p · cap), VP8 backup behind H.264 / VP9 (VP9 never on Safari
/ iOS), Opus mono 48 / 24 kbps, adaptive stream + dynacast on, the SDK's per-source degradation (camera keeps frame
rate, screen keeps resolution). Screen share: "1080p / 720p" is the SHORT side with a pixel ceiling (a portrait phone
shares 1080×2340 / 720×1560), two layers. Receive: a pure governor (`live_quality_governor.dart`) drops every remote
video to LOW on the first bad sample (poor / lost rating, ≥ 8 % loss, a frozen camera, a server-paused track), climbs
one tier per 12 s of good, doubles the hold and keeps a ceiling below a tier that broke the link (no flapping);
`audio_first` drops the cameras (screen kept) after 8 s bad at LOW, with Show video. Hidden video stops (no
off-screen strip tiles, a video budget per screen size, nothing drawn while minimized, everything unsubscribed while
the app is in the background). A student's camera starts off (no track until turned on). In server recording mode
the device recorder does not run and a presented board is published as a 2 fps `whiteboard` track for Egress
(amends D-087's "Recording"); client mode keeps the device recorder.
**Two approaches → a switch.** codec (VP8 universal / H.264 cheaper CPU on phones / VP9 less bandwidth), weak network
(adaptive layers / audio first), recording (server Egress / device), Egress engine (composite / media), DTX, RED,
participants' camera default, pause hidden video.
**Rejected.** Leaving layer choice to the SFU alone (the measured 15 s freeze and the 180p floor); unsubscribing
instead of lowering on every weak sample (a re-subscribe costs a renegotiation, and adaptive layers are enough
outside `audio_first`); disabling hidden tracks with `disable()` (the SDK has no way back to "unset": a re-enabled
hidden tile would keep its video forever — the background case unsubscribes, the minimized case simply draws no
renderer); one screen-share layer (a weak viewer froze on it); a long-side cap for shares (portrait phones lost
60 % of their width).

## D-091 — "Go live" from the instructor home: one sheet, existing routes, autoJoin · 2026-10-29 · accepted

**Context.** The owner: "make the teacher able to go live quickly from home". A live session could only be started
from the course studio (course → session → Start → pre-join → Join); the home only had "Enter room" for a session
that already ran, and the header's "Meet now" made a calendar meeting, not a class.
**Decision.** The instructor home's header carries a red "Go live" pill at the end of the context-switcher line (the
line under the greeting: an action beside the name squeezed it to "Ahm…" on a phone); it becomes "Return to live"
while a room of mine runs — the open room (`LiveRoomHost`, minimized or behind a page) is expanded, else a session of
mine the dashboard reports live is resumed. A tap opens one sheet (a dialog from 720 px): the course — the one with a
timetable slot within ±60 min, else the one remembered on the device (per user, with the camera / microphone choice),
else the next slot's, else live → published → most students — then the session: a live session of that course
scheduled within ±60 min (or running, or a slot with no session yet) is offered first, else "New live session now"
with an optional title (empty → "Live class · Thu 29 Oct · 10:40 PM", the way Meet now names a meeting after its
start); the Record switch (the session's own, else the course's latest live session's, else on); camera /
microphone; one big button. It runs on routes that already exist — `POST /sessions` (type live, now, 60 min) or
nothing for an existing session, `PUT /sessions/{id} {record_enabled: true}` when Record is turned on for a session
whose switch is off (`enable_recording` may only turn recording off), then `PreJoinPage(autoJoin)` whose `onStart` is
`POST /live-sessions/start` ("start or resume", carrying `recording_enabled` and `live_config`, D-090). A slot without
a session creates it at the slot's start, so the dashboard matches it (course + start) and the home's "Live now" card
shows it. "Meet now" stays one tap away as the sheet's secondary action (the header icon left; it comes back when the
kill switch `teacher.quick_live` hides Go live). Nothing is fetched when the home opens: the sheet asks
`GET /courses/{id}/sessions` for the course it shows (cached per course while open), so the request budgets are
unchanged. Files: `lib/features/teacher/home/go_live.dart` (pure, `test/org/go_live_test.dart`), `go_live_sheet.dart`
(`test/ui/go_live_layout_test.dart`; renders `test/visual/go_live_golden_test.dart`).
**Rejected.** A new server route ("quick live" in one call): the two existing calls do it, and `POST /quick_session`
ignores the title and the Record switch; a floating button (the app assistant floats in the same corner); a primary-
action slot in `AppShell` (one role needs it; the header is there at every size); starting the room from the sheet
without the pre-join page (device setup, permissions and the Join retry live there).

## D-092 — The live room's self-view: my camera in a box or circle I can put anywhere, in every state; the renderer never takes a tap again · 2026-10-29 · proposed

**Context.** The owner (Galaxy S24 Ultra, teacher): "when I open the camera, sometimes my app becomes slow, and the
bottom bar doesn't show again when I tap the screen" and "I need to show my image when I open the camera, in any
position, in a box or circle or without background" — in every state: sharing, the pre-join page, the whiteboard and
annotation. Root causes found (logcat7.txt + code): (1) `_syncAurora` called itself while the stage was empty —
166 Stack Overflows (~98 000 frames each, logged with the trace and sent to Crashlytics) in 3 minutes; (2) every
LOCAL track (my camera on the stage, my own screen share) was drawn by livekit_client's VideoTrackRenderer, which on
phones wraps the video in its own GestureDetector (onTapDown → focus, scale → zoom): it won every tap, so "tap the
stage to show the bar" never fired, and on a share each tap threw `PlatformException(setFocusMode … Video capturer not
compatible)`; (3) that renderer's build() makes a new `FutureBuilder(future: _initializeRenderer())` — a re-attach
(srcObject over the channel) on every build — and the room rebuilt everything once a second (the session clock) and
on every speaker change; (4) the Android placeholder screenshot (whole room → PNG, 2×/s, a GPU read-back of the camera
texture) started on any participant event for a teacher, even with no device recording (server mode); (5) turning
the camera on opened it twice (setCameraEnabled, then setCameraPosition(front) = a full restartTrack); (6) the share's
border glow repainted two large blurred shadows every frame; the aurora ran under the opaque waiting card.

**Decision.** `LiveVideoView` (`widgets/live_video_view.dart`) is the only way the room, the pre-join page and the
minimized box draw a track: the renderer behind an IgnorePointer (the tap goes to the stage), one renderer instance
while track / fit / mirror stay the same (`LiveStableChild`, a parent rebuild stops there), its own RepaintBoundary.
Tap-to-focus is kept for a local CAMERA on Android / iOS only (`LiveCameraFocus`, guarded: the first failure turns it
off for the run). The clocks tick a ValueNotifier read by the badge column only; the screenshot loop runs only while
the device recorder records frames; the camera restarts only when it did not come up on the front camera; the
share's glow is still; the aurora stops while my camera is on; the recursion is gone.
Self-view (`lib/features/shared/live/live_self_view.dart` rules, `widgets/self_view_pip.dart` widgets): while my camera
is on, it is always somewhere — a floating box (3:4 on phones, 16:9 on wide stages) or circle, small or medium, over
the waiting card, someone's video, a shared screen (mine too), the whiteboard and the annotation layer; it takes only
its own touches (drawing goes on around it) and keeps clear of the badge column (measured), the thumbnail strip, the
annotation toolbar, the board's bar and dock, the share's bottom bar and the bottom badge row. Drag anywhere; a drop
snaps to the nearer side edge (a fling carries it, 120 ms projection) and into a corner within 56 px of an end; the
side and the height fraction are what is stored, so a keyboard, the chat column or a rotation keeps it in place.
Tap → swap with the stage's video (never a board); long-press or ⋮ (shown with the bar) → options: Box / Circle,
Small / Medium, "Fill the screen while I'm alone", "Show me on the big screen", "Hide self view" (a chip brings it
back; per room). Shape, size, side, height and "alone on the stage" are remembered on the device
(`SelfViewStore`, SharedPreferences `live.self_view.v1`); the pre-join preview shows the camera in the same shape
with a Box / Circle switch. Never the stage AND the box at once (the "camera twice" fix holds). Alone, the default is
the box over the waiting card (what the owner asked for); a client-mode recording, which screenshots the teacher's
screen, then shows the waiting card with the box — "Fill the screen while I'm alone" puts the camera back on the
stage. The minimized box keeps its rule (a share, else a camera, else an avatar).

**Background ("without background").** Not added. livekit_client 2.13.1 has only the `TrackProcessor` interface (no
blur / virtual background; the web processors are the separate JS `@livekit/track-processors`, no Dart wrapper);
the flutter_webrtc fork exposes a Java `ExternalVideoFrameProcessing` hook on Android only, which would need an ML
segmenter (ML Kit selfie segmentation or MediaPipe, a native dependency) running on every 720p24 frame in the
encoder path — the CPU / heat this decision is fixing. The circle is the minimal look (mostly the face). Revisit with
a GPU segmenter on the native side if the owner wants it for everyone, not just the self-view.

**Android whole-screen share.** In-app only. A camera bubble over other apps would be captured by MediaProjection
like every overlay window: the students would see my camera twice (the camera track and inside the shared screen,
covering the content) and so would the recording; a FLAG_SECURE bubble shows as a black box in the share. (The
annotation bubble is different: it is meant to be captured.)

**Rejected.** Forking livekit_client to drop the renderer's detector (the IgnorePointer does it without a fork);
`RepaintBoundary` alone (the re-attach happens in build, not paint); a full-stage self-preview when alone with no
way to choose (the owner asked for a box or circle anywhere); remembering "hide self view" across rooms (a hidden
view would surprise the next class); free positioning without snapping (a box left in the middle covers the stage).

## D-093 — Live drawing: name tags while people draw; whiteboard page formats (landscape · portrait · continuous) · 2026-10-29 · proposed

Amends D-079 / D-083 (annotation) and D-087 (whiteboard).
**Context.** The owner: "if the host allows participants to draw, show the writer's name inside the drawing while
they're drawing", and "the drawing paper may be landscape or portrait, and may be continuous, to make drawing easy on
mobiles, web or tablets".
**Decision.** (1) Name tags (Zoom / Miro / FigJam style), on a shared screen's annotation and on the whiteboard
(`annotation/live_presence.dart`, `presence_tags.dart`): while someone else draws, a pill in their ink colour with
their name follows their pen tip (an open stroke's last point), the corner of the shape they drag, the caret of the
text box they type (estimated from the text, no layout in the controller) or their laser; it stays while the pen is
down and 1.5 s after the last activity, then fades over 0.35 s, and glides (45 ms time constant) instead of jumping
per 33 ms batch. NO new message: the tags come from the packets the room already receives, keyed by the REAL LiveKit
sender (a forged `a` changes nothing). Nobody sees their own tag; the presenter's tag shows only once someone else may
draw (the room's permission is open), a co-host's always. The name is the participant's LiveKit display name (a
guest's is the name they typed; never an identity — unknown → "Participant" / "Guest"), cleaned of bidi controls and
control characters, whitespace collapsed, at most 24 characters + "…"; an Arabic name runs right to left by itself.
The label is white or near-black, whichever contrasts more with the pill; a small content (< 480 px wide: a phone's
view) gets compact tags. Tags are interface: never in the PNG or the recording track. (2) "Show who drew what",
host-controlled, default off: `au: 1` on the annotation permission packet (additive; older apps ignore it; a
permission without it turns it off) — the mouse over an item, or a long press when not drawing, shows "Drawn by …" on
the shared screen and on the whiteboard (a translucent listener: the video below keeps its taps). (3) Page formats:
`fm` on the board state — `l` landscape 16:9 (absent = l), `p` portrait 3:4 (a portrait phone's stage fills its width
with it; a tablet's shape), `c` continuous: a column 20 page widths long, x by the width, y by that whole length (one
5-decimal wire unit = 0.26 px on a 1280 px column), so every 0..1 clamp, parser and snapshot keeps working. A
landscape board stays `bv: 1` (byte for byte the D-087 packet); portrait / continuous announce `bv: 2`, so an app from
before this decision shows its "update the app" overlay instead of squeezing the page into 16:9 (it drops nothing and
never crashes). Distances are measured in page widths on both axes (hit tests, Shift squares, tiny shapes). A
continuous page is shown down to its extent (1 width — or 60 % of a screen — below the lowest content, at least 1.5
screens, never above the presenter's view): it grows as people draw near its end. Each device scrolls (two fingers,
the wheel, one finger when not drawing or with "Stylus only") and zooms its own view; the column fills a phone's or a
tablet's width and is a portrait page's width on a laptop (max(480, 0.8 × height)). The presenter's view travels as
`vp {y, h}` — lossy on `board.laser` at most every 100 ms while it moves, once reliably on `board` 350 ms after it
stops, and to every late joiner after their snapshot; viewers follow it eased (centred when they see more, its top
when less) until they scroll themselves, then "Follow …" snaps back; a rail beside the column shows where they are and
where the presenter is. The presenter picks the format in the share sheet (a portrait phone starts on Portrait) and
changes it in the Board sheet: every item is remapped (positions kept in page widths; a page whose content would run
past the new bottom is scaled down evenly and centred; values rounded as they travel) and the board goes out again as
a snapshot — receivers clear on the state's new format and rebuild; undo history starts again. Portrait / continuous
pen and text steps are 1.6× (fractions of a narrow page). Save as PNG is drawn from the items (`board_export.dart`,
not a screenshot): 1920×1080 / 1440×1920, or on a continuous page the part on screen or the whole board down to its
last line as one tall image (1600 px wide, capped at 8192 px). The recording track (D-090) reads the presenter's
visible part of a continuous page. (4) Comfortable drawing: a finger's stroke is held 70 ms before it goes out, so a
pinch / two-finger scroll that starts with one finger never shows anyone a dot; a palm near the pen neither draws nor
scrolls; "Stylus only" (this device, remembered, offered once the first time a pen touches a board) makes fingers
scroll / zoom and never draw, also on a shared screen.
**Rejected.** A lossy cursor message for the tags (the stroke / put / laser packets already carry the position and the
sender; a cursor stream costs traffic for no new information); y in width units for continuous (every parser and clamp
of D-079 / D-087 assumes 0..1 — a second path for one format); an unbounded page (no bound for snapshots and exports;
20 widths ≈ 10 phone screens / 40 laptop screens, and pages still add more); free-size pages per device (a phone and a
projector must show the same content); cropping content on a format change (silent loss) or refusing the change once
a board has content; a screenshot for the PNG (it carried the zoom, the selection and the tags, and could not export
what is off screen).

## D-094 — Viewers see the presenter's camera over a share or a whiteboard; the camera keeps streaming while an Android presenter shares from another app · 2026-10-30 · proposed

**Context.** The owner: "when I share content and open the camera, the content and the camera show for me only; the
participants see only the content". Root causes: (1) the room draws remote cameras only in the thumbnail strip, which
is off while a share or a board fills the stage (`!_isScreenShareMain && !_isBoardMain`), so no viewer drew the
presenter's camera at all — the presenter saw it only in their own self-view (D-092); (2) because nobody drew it,
adaptive stream paused the camera track (its view registration is what makes it stream), so even the bits stopped;
(3) on Android, a presenter who shares the whole screen and leaves the app kept the camera on (D8 never turns it off
while sharing), but ScreenCaptureService ran as `mediaProjection|microphone` only — from Android 11 a background app
may use the camera only through a foreground service of type camera started while it was in front, so the frames froze.
**Decision.** (1) While a screen share or a whiteboard fills the stage, every viewer gets the presenter's camera (when
it is on) in a floating box with the self-view's look (`SelfViewTile`): drag anywhere, snap to an edge or a corner, ⋮ /
long-press for shape (box / circle) and size, "–" minimizes it to a name pill for the rest of the room; its default
side is opposite my self-view and a rest spot that would overlap my self-view (or its "Show" chip) moves to the other
end, then the other side. Other cameras that are on sit as up to 3 bubbles beside it (the share and the box count
against `liveVideoBudget`; the rest is "+n", which opens the participants panel); tapping a bubble pins that camera
into the box for this share. The presenter sees nothing new; a camera that is off draws nothing (never an empty box);
minimized without video or my camera swapped onto the stage, nothing floats. Rules are pure
(`live_presenter_cam.dart`: `presenterCamPlan`, `presenterDockSize`, `presenterCamSpot`, `PresenterCamStore` for
shape / size / position), the widget takes plain values (`widgets/presenter_cam_box.dart`), the video is a
`LiveVideoView` (D-092) — drawing it is what resumes the track. It reuses the self-view's keep-outs (annotation toolbar,
board bar and dock, share bottom bar, badge column) and takes only its own touches, so the stage tap and drawing work
around it. `presenterCamShown` is exposed for a future focus mode. (2) ScreenCaptureService adds the camera type while
a projection is held and CAMERA is granted (manifest: `mediaProjection|microphone|camera` + `FOREGROUND_SERVICE_CAMERA`);
a refused camera type (while-in-use rules) falls back to the same call without it, so a share never fails for it.
Play Console needs the camera foreground-service declaration for the next release.
**Rejected.** Turning the thumbnail strip on over a share (it covers the top of the content and the annotation /
board bars, and decodes every camera); compositing the camera into the shared screen on the presenter's device
(costly, burns it into the share and the recording); a separate camera foreground service (two notifications, and the
camera type must be on the service that is in front when the share starts).

## D-096 — Whiteboard: a hand to move the paper; the view scrolls by itself when drawing reaches an edge · 2026-10-30 · proposed

**Context.** The owner: "make the drawing paper scroll with the mouse or the hand when the pen is not selected …
and when I draw near the bottom, scroll automatically, also at the top, left and right". A continuous page (D-093)
scrolled with two fingers, the wheel, or one finger only when not drawing; a mouse drag never moved it, and a stroke
had to stop at the screen's edge.
**Decision.** (1) A new local tool `BoardTool.hand` (open palm, key M, tooltip "Hand: move the page"), second in the
dock beside Select, which is now drawn as a mouse pointer. With the hand, one finger, the mouse or the pen drags the
view (a continuous page up / down, a zoomed page around; grab / grabbing cursor) and draws nothing. The same pan
comes from: Select on empty paper (a drag on an item still moves the item), Space held with any tool (desktop), the
middle mouse button, and every pointer of whoever is not drawing (viewers included). The view is this device's
(D-093): the presenter's pan goes out as `vp` like any scroll, a viewer's pan leaves "Follow". The phone's dock keeps
two rows of 7: the page tools on the first (select · hand · pen · highlighter · shapes · text · eraser), undo /
redo · 3 colours (the current one always shown) · style · laser on the second. (2) Edge auto-scroll
(`board_edge_scroll.dart`, pure): a stroke, a shape or a moved selection within the edge zone (12 % of the stage,
28–72 px) scrolls the view that way at 60 → 900 px/s (quadratic in the depth, eased in over 250 ms), driven by the
stage's ticker while the pointer is held still; an edge is armed only once the pointer was outside its zone or moved
24 px towards it, so writing along the bottom never scrolls. It stops at the page's limits (a continuous page grows
under the stroke, D-093). The drawing pointer's events stay in the frame of its down, so each frame the held pointer
is mapped onto the moved page and the stroke follows without a gap; the laser, text and the hand never auto-scroll.
Pinch, two-finger pan, "Stylus only" and palm rejection are unchanged. Tests: `test/org/board_edge_scroll_test.dart`,
`test/ui/whiteboard_hand_layout_test.dart`; renders `test/visual/whiteboard_hand_golden_test.dart`.
**Rejected.** Select alone panning on empty paper (no visible way to know the paper moves; the owner asked for an
icon); a hand that is a mode switch outside the tool row (one more control to find); auto-scroll on entering the
zone with no arming (a line written at the bottom ran away); a timer instead of the ticker (frame-locked steps keep
the stroke smooth).

## D-095 — The live room's top row: one line above the stage; recording moves up from the bar; full view · 2026-10-30 · proposed

Amends D-058 / D-060 (meeting Record / Stop pinned on the bar, the info chip), D-090 (the badge column) and D-092.
**Context.** The owner: "the top icons info, times, recording — make all of it in one line and remove the app logo of
the top corner of live; also remove the record button from the bottom and make it in the top row with the record
time; also show the live time and an icon to make the shared content full and remove the top and bottom bars".
**Decision.** (1) `widgets/live_top_row.dart` (`LiveTopRow`, plain values; room.dart `_buildTopRow()` maps its state,
rebuilt by `_clockTick` + the recorder only, D-092) is ONE 48 px line above the stage, never inside it: start — ⓘ LIVE
+ how long the room has been live (`live_started_at`, else the person's own time; the chip is the info button) · the
free-time countdown (+ Upgrade) · weak network · Room locked; end — the recording control · Full view · Minimize.
Below 600 px labels become icons (the times stay), chips tighten, the ⓘ glyph drops when a status pill sits beside
the clock; a still-crowded row scrolls its start group under an edge fade — it never wraps. (2) Recording leaves the
bar (`LiveRecBadge`, the bar's Pause / Resume and `meetingRecordAction` are gone): `liveRecPhase` picks the device's
recorder first, then the creator's "Record", then the server's "● REC" (everyone, no controls — D-090 server mode
included); recording / paused shows the dot + time and a tap opens Pause / Resume (the gate the bar had,
`showsRecorderControls`) and, for a meeting's creator, Stop recording. (3) No app logo in the room: the waiting
card's `showLogo` is false, and its own "live" chip is off (the row says LIVE). The recording placeholder is a
screenshot of the live screen, so the recording has no logo either — a recording-only logo would need a second,
off-screen render of the card and break the stated parity. (4) Full view (`_focus`, offered whenever something fills
the stage — share, board or a camera): the row, the bar and the thumbnail strip step aside; `LiveFocusExitButton`
takes the participant badge's corner (with a red dot while this device records); a tap on the stage, Esc, F and the
back button (`PopScope` — `LiveRoomHost.handleBack` asks the room's navigator first) bring them back. The annotation
and board toolbars live on the stage and stay; the self-view box stays and keeps clear of the exit button.
**Rejected.** Keeping the vertical badge column (it grew with every pill and sat over the video); a Record button on
both the bar and the row; an auto-hiding row (the recording state must stay visible); a full-screen route for full
view (the room is not a route, D-059).

## D-097 — Weak-network follow-up from the perf2 bench: `allow_pause` off, a healed dip climbs back to HD after 60 s · 2026-10-30 · accepted
**Context.** The after-tuning bench (scratchpad `perf2/RESULTS.md`; a real libwebrtc publisher, netem on the
subscriber's downlink) found two weak spots: LiveKit's `congestion_control.allow_pause` paused the whole video 1–2
times per run (up to 11.6 s) on a 1 Mbit/s link that carries 360p, and the governor's 4-minute ceiling held a link
that had healed at 360p for ~4 min (720p came back 224 s after the cap was lifted).
**Decision.** (1) `allow_pause: false` in `../back/scripts/dev/livekit.dev.yaml` and the production proposal
`deploy/livekit.production.yaml` (2.5 s frozen and 0 pauses in the same run); the app's governor steps down to 180p /
audio only itself. (2) `LiveQualityGovernor.firstStrikeCalm` (60 s): a FIRST strike's ceiling also ends after 60 s
of unbroken good samples; repeat strikes keep the 8 / 16 / 32-minute ceilings. On a link that never carries 720p this
costs one more 720p probe in 10 minutes (4 drops instead of 3, still ~80 % of the time on 360p).
**Not changed.** The screen share's half-size layer: livekit_client 2.13.1 keeps the share's frame rate on it
(`_computeDefaultScreenShareSimulcastParams`); the 3 fps layer on the bench came from the Python SDK's default.

## D-098 — Course sessions record on the teacher's device; the server's after-class assembly is made cheap · 2026-10-30 · accepted (owner)
**Context.** The recording bench (`../back/bench/recording/RESULTS.md`) made the GStreamer composite the best SERVER
engine (0.5 core per recording), but the owner wants the shared 12-vCPU server (API, database, LiveKit, the local AI
model) free of recording work during classes, and production's egress (v1.8.3 Chrome under `cpus: 1.5`) loses ~80 %
of the audio until it is upgraded.
**Decision.** `RECORDING_MODE=client` stays the default (dev and production env): the teacher's device records and
uploads chunks; the super admin's Live settings switch (D-089) keeps `server` as the per-run fallback once egress is
upgraded (v1.15.0, `enable_template_sdk`, ≥ 2 CPUs). The after-class assembly (`local_recorder.py`) is the remaining
server cost — three libx264 tiers with `FFMPEG_THREADS` = all cores — and is to be measured and made cheap (2 threads,
`nice`, one job at a time, one tier by default, `-c copy` remux for H.264/AAC chunks): `docs/live/NEXT_SESSION.md` §1.
**Trade-offs accepted.** The teacher's device spends CPU / battery / upload on recording; a killed app loses the chunk
in flight; the recording is the teacher's screen layout.

## D-100 — "My courses" shows one side: the personal account or the open organization · 2026-10-30 · proposed

**Context.** The owner: "when the teacher opens the personal profile, only the individual courses; when he opens an
organization, only the organization's courses; and the student distinguishes between them in a premium, smart way".
`/my-courses` and `/my-enrolled-courses` mixed every course: an organization course (a `Course` row linked by
`org_courses`) showed in the personal account, and nothing said where a course lived.
**Decision.** The server tags every course payload with `org` (the owning organization, null = personal; `Course.org`
over a `selectin` link) and both list routes take `scope` = all | personal | org + `org_id` (an organization includes
its sub-organizations, by `path`), echo `scope` and count every side in `scopes` on the first page
(`services/course_scope.py`). The app keeps the side in pure `course_scope.dart` (`CourseScope`, `CourseOrg`, chips,
smart default; `test/org/course_scope_test.dart`) and draws it with plain-value parts in `course_scope_bar.dart`.
**Teacher:** the list follows the mode strictly — `TeacherCoursesProvider` listens to `AppModeController` itself, so
every reader (Courses tab, analytics hub) sees the same side; a mode change empties the list at once (the other side
never flashes) and reloads only if the list was ever loaded (no request at app start). `CourseScopeBanner` says which
side is shown, its count, "+n in your organizations / personal account" and Switch (the context switcher). In
Organization mode there is no "Add course" (a course created there would be a personal one) and the empty state says
the organization assigns the courses. **Student:** the list opens on the mode's side, but a chip bar
(`CourseScopeChipBar`: All · Personal · each organization by size, counts, the organization's logo / initial on its
brand tint) lets the student look at another side without leaving the mode; the bar is drawn only when courses live on
more than one side. Smart: the personal account with no personal course opens on All (an empty page would hide courses
the student has), Organization mode stays on its organization even when empty (with "Browse its courses" into the
organization's catalogue), and a mode change drops the student's pick. A list that mixes sides puts `CourseOrgBadge` on
every card (under the favourite heart). An older server ignores the scope: the app shows what it sends, unfiltered.
**Rejected.** Filtering on the client from the home payloads (an older server sends no `org`, so an organization page
would come out empty, and paging / totals would be wrong); a chip bar for the teacher (the owner wants the side to be
the mode; Switch is the one way across); making the student's chip switch the app mode (a list filter should not move
the whole app); grouping the student's All list in sections (paging is by enrolment date; sections would reorder pages
as they arrive).

## D-101 — The schedule's week rolls (yesterday · today · tomorrow first); the grid opens with the next appointment on the 5th row · 2026-10-30 · proposed

**Context.** The owner: "make the first column yesterday, today the second and tomorrow the third; and the first
future appointment in the fifth row". The week was the calendar week (Saturday / Monday first), so on a Thursday most
of it was over, and the time grid scrolled to an hour before the week's earliest event (07:00 at the latest) — often
far from what comes next.
**Decision.** (1) The Week view is a rolling 7 days whose SECOND column is the focused day (`calWeekDays`,
`calWeekFrom` in calendar_models.dart): opening the page or Today shows yesterday · today · tomorrow …; a date picked
outside the window becomes the second column; a tap inside it (the phone's day strip, a day header) keeps the columns
where they are; the arrows move them by exactly 7 days. The page keeps the window's first day (`_weekFrom`) and hands
it to the title ("28 Oct – 3 Nov 2026"), the mini month's highlighted range and the fetch range. The Day view fetches
the same rolling week and the Agenda starts the day before its first day, so switching between them is served from
the cache. The Month stays a real month (Saturday / Monday first by language). (2) The grid opens on its focus
(`calFocusMinute`): the first appointment still running or to come in the shown days (a class in progress counts as
next; cancelled / declined skipped), else now when today is shown, else the earliest one (a past week), else 08:00;
`calFocusOffset` puts that hour row on the 5th row of a tall grid (≥ 11 hour rows: desktop), the 3rd on a phone
(≥ 7), the 2nd on a very short one, 10 px higher so the top hour label is whole. The controller is made at the first
layout (the viewport is known: no jump); if the events arrive after the grid opened it takes the focus once
(animated), never after the person scrolled. (3) Day headers say Yesterday / Today / Tomorrow and past days are drawn
quieter; the Today button goes quiet when the page already shows today the way it opens.
**Rejected.** Keeping the calendar week and only scrolling it (on a Thursday the past days still take most of the
screen); re-centring the window on every tap (the strip would move under the finger); a fixed row on every screen
(row 5 on a phone pushes the appointment and what follows to the bottom); following the next appointment on every
clock tick (the grid would move by itself while being read).

## D-102 — Calm homes, one course card, one sessions timeline (student and teacher share the language) · 2026-10-30 · accepted

**Context.** The owner: the homes are "too complex and not attractive"; the course lists and the course page must be
premium, simple, light on the eyes and consistent between the two roles; the course page has a cover with the image
and its actions over it, and the sessions below it in a smart, elegant layout. A real-app sweep (web build on the local
stack, every student / teacher screen captured) then listed what still looked or worked wrong.
**Decision.** One type scale for these surfaces: titles w600, rows w500, meta w400 in the muted colour, figures w600,
never w800 / w900 (one hero title may be w700); hairline borders instead of shadows; one strong accent per card.
Homes: a light greeting header, ONE live / next-up card on a card surface, "Needs you" as one slim row of outlined
pills (zero counts hidden), Today, a three-line courses card, an inbox preview. "This week" left the student home (the
schedule page has it) and the teacher's stats hero and separate "Enter room" card left the teacher home (the button
sits on the running row of Today; students · rating · earnings head the courses card). Course lists: ONE
`CourseListCard` for both roles — a media row on phones (scans faster than a stack of covers), a tile grid from 600 px;
the student's three gradient stat cards became the counts on the filter; the teacher's details panel and toolbar became
the ⋮ menu; the heart shows only on favourites (it was never tappable on the card). Course page: the cover keeps its
image with one frosted button style for both roles; sessions are ONE timeline (`course_sessions.dart`) whose rows differ
only by role (progress and Join for the student, ⋮ and reorder for the teacher). The primary gradient is built from the
primary colour (the server's accent blend made pills, tabs and buttons gold). Digits are Western 0-9 in both languages
(`AppTime.useLatinDigits`), which most screens already used. A server-generated session title carries `title_auto` and
is shown in the reader's language; Go live sends no name when the teacher typed none.
**Rejected.** A full-bleed coloured hero on every home (it fought the live state for attention); keeping the cover
grid on phones for the lists (half the screen per course, titles cut to one line); a separate sessions widget per role
(the two pages drifted apart before); Arabic-Indic digits everywhere (clocks, counts and server text are already 0-9).

## D-135 — The device recording is ONE continuous encode cut into chunks; the server joins it with a stream copy; the room frames reach the Android recorder at ~12 fps · 2026-10-30 · accepted

*Numbered D-103 until 2026-10-31 (its branches and commits still say D-103); renumbered because D-103 is the organization dashboard.*

**Context.** The owner, on the S24 recordings (D-098, client mode): "a leak every 5 seconds — make the video one block
without any leak", and "the camera is shown in slow motion — make the movement normal". Evidence from the dev stack's
last Android recordings (run 12, `session_69/…_medium.mp4`, 131.9 s): the recording's own REC clock reads 00:20 /
01:41 at playback 20 s / 100 s (real time overall — nothing is time-stretched), but the picture changes only every
~475 ms (152 frozen stretches > 400 ms in 132 s) and video steps of 136 ms plus 31 ms runs of digital silence sit at
chunk boundaries. Causes: (1) **gaps** — the recorder stopped one MediaRecorder and started the next every 5 s
("ping-pong"): the renderer moved to the next recorder's surface before the old one stopped (its video ended early),
the new encoder needed ~100 ms and a key frame, both recorders captured the mic for a moment (sound twice), every file
began with a new AAC encoder's priming silence, and the server's concat put each file after the previous file's
longest track; (2) **"slow motion"** — before a share the Android recording draws the room from screenshots Dart sends:
a PNG every 500 ms (encode + platform channel + decode), so the camera moved in ~2 fps jumps.
**Decision.** Android records with `SegmentedRecorder` (MediaCodec H.264 on the renderer's input surface + MediaCodec
AAC on an `AudioRecord(MIC)` stamped from its sample count on the monotonic clock; the renderer stamps every frame with
`eglPresentationTimeANDROID(System.nanoTime())`): both encoders run for the whole recording (until a pause) and a
`MediaMuxer` is swapped for a new file at the first key frame ≥ 4.75 s into the chunk (a sync frame is requested
0.4 s before); the two encoders' output is merged in timestamp order, so every frame and every AAC frame lands in
exactly one chunk. Chunks keep the same upload protocol (index, epoch, upload token, is_final) plus the form field
`seamless=1`; a stop while paused sends an empty final chunk (the finalize ping). The MediaRecorder ping-pong stays as
the fallback when the encoders / mic cannot be set up. The server (`local_recorder.py`) marks such chunks and joins a
run whose chunks are all marked with the concat demuxer and `-c copy`, each file's `duration` taken from the audio
clock (`lead_N + audio_span_N − lead_N+1`) — no re-encode, the device's own timestamps; anything inconsistent, an
unmarked chunk (older apps), iOS and web keep the legacy re-encode unchanged. The room frames: raw RGBA
(`toImage` → `rawRgba` → `setPlaceholderFrame`) as soon as the previous one is done, at most 12 fps and at most 50 % of
the time capturing (`live_frame_pacing.dart`); an older native side falls back to the PNGs. Cheap server (D-098 §1.2):
`FFMPEG_THREADS` defaults to 2, every ffmpeg / ffprobe of the assembly runs under `nice -n 19` + `ionice -c3`
(`FFMPEG_NICE`), and one assembly at a time per host (`ASSEMBLY_CONCURRENCY`, an asyncio semaphore + `flock`).
**Measured** (`../back/tests/org_v2/recording_gapless.py`: frame-numbered source + beeps through the real assembly):
old-style chunks — 9 timeline jumps up to 467 ms, 27 source frames lost, 270 ms of audio holes, A/V error up to 155 ms,
47 s of class → 48.37 s of video (speed 0.972); new chunks — 0 jumps (max frame step 71 ms = 1.06 frame), 0 lost / 0
held frames, 0 audio holes at the boundaries, A/V ≤ 10 ms, speed 1.000, duration 47.02 s, stream copy in ~1–3 s
instead of a full libx264 pass. The same new chunks on an older server still assemble in real time (one 133 ms step,
A/V ≤ 67 ms).
**Trade-offs accepted.** The device's AAC encoder delay (~20–45 ms, audio slightly late) is not compensated; a
recorder restart (reconnect, resume after pause) starts a new encoder, so its first ~20 ms is the encoder's priming;
the room frames cost the teacher's phone a full-screen read-back ~12 times a second (paced to ≤ 50 % duty, 1×
logical pixels as before); the iOS recorder (one AVAssetWriter per chunk, untested on a device here) is unchanged.
**Rejected.** `MediaRecorder.setNextOutputFile` (switches only on a max file size, not on time); fragmented MP4 / a
hand-written MPEG-TS muxer on the device (more code, and older servers would not accept the new container); a native
camera-frame bridge into the recording (needs the flutter_webrtc fork, and drops what the room shows around the camera).

## D-105 — The camera floats over the shared picture, not in the empty bars beside it · 2026-10-30 · proposed

Amends D-092 (self-view) and D-094 (the presenter's camera for viewers).
**Context.** The owner: "why when open camera with share content the camera not show in the front of the shared
content". A real two-browser run on the local stack (web profile build, Chrome with fake devices: a teacher sharing,
a student watching, phone 390 × 844 and laptop 1280 × 800; screenshots in `screenshots/share_cam/`) showed that
D-094 itself works on the web: the presenter's camera is subscribed, streams and is drawn in its box for the viewer,
over a share, in full view and over the board, and the presenter's self-view stays on top of their own share. What
was wrong is WHERE: a share is drawn `contain` in the share view, and both boxes were placed by the STAGE's edges.
A phone's portrait screen (what an Android presenter sends) is a narrow column in the middle of a laptop's stage —
the viewer's camera box sat in the empty left bar and the presenter's self-view in the right one, far from the
content; a laptop's 16:9 screen is a band across a phone's stage — the box sat in the black area under it. In every
case the camera was beside the content, never in front of it; the same for the whiteboard's page on a phone.
**Decision.** While a screen share fills the stage, the presenter's camera (viewers) and the presenter's own
self-view (on their own share) float over the PICTURE: the shared frame's real aspect comes from the share view's
renderer (`_AnnotatedShareVideo` now always owns the renderer and reports the aspect; the publication's announced
dimensions until the first frame), `shareContentRect` fits it like the view does (`kShareVideoInsets`), and
`selfViewOverContent` (pure, `live_self_view.dart`) turns the picture's inside (10 px in, never past the stage's own
keep-outs — the share's bottom bar, the badges) into the box's keep-out and scales the box to at most 55 % × 45 % of
the picture, so a phone's column or a laptop's band keeps most of its content readable; a picture too small for a
52 px box keeps the old stage placement. Drag / snap / side / height work as before, inside the picture. On the
whiteboard the presenter's camera does the same over the page as it is on screen (its zoom / pan included, read from
the page's render box, `_boardPageKey`; the room's 1 Hz clock re-places it only when the page moved, since the board
lays itself out without rebuilding the room); the presenter's own self-view on their board keeps the stage edges (they
draw on that page). A viewer's own self-view keeps the stage edges (it is not the presenter's content). Tests:
`test/org/live_over_content_test.dart`, `test/ui/presenter_cam_layout_test.dart` (over the shared picture).
On a continuous board the box rests beside the page's vertical scrollbar, still on the corner (D-109 (5)).
**Android (not runnable here; the owner checks on the S24).** A presenter who shares the whole screen and leaves the
app keeps the camera on (D8 never turns it off while `screenShareActive`, which is true from the tap through the
system dialog) and `ScreenCaptureService` carries the camera foreground-service type (D-094); nothing in the share
path mutes, unpublishes or restarts the camera. While the presenter is in another app their own phone shows no
camera over that app (D-092: an overlay would be captured into the share and the viewers would see the camera twice)
— the viewers see it in the box over the picture. Viewers on an app or web build from before D-094 see no camera at
all over a share (the box is drawn by the viewer's app).
**Rejected.** Burning the camera into the shared screen on the presenter's device (D-094's reasons: cost, the
recording, and the camera twice for viewers); a fixed size over the picture (a laptop-sized box covered a phone's
band); keeping the stage placement and only moving the default corner (the bars beside a portrait column are where
the box ended up in the first place).

## D-106 — The pre-join page never joins by itself; a meeting's live texts say «اجتماع» · 2026-10-30 · accepted (owner)

**Context.** The owner: "don't move from the pre-join screen to the live screen automatically, the user must click
the Join button", and "when joining a free meeting change «الحصة» to «اجتماع»". `JoinArgs.autoJoin` pressed Join as
soon as the devices were ready for Go live (D-091), the homes' Live now banner, Meet now, the schedule's Join, a
direct guest link and the Rejoin after a lost connection, so people landed in a room before checking their camera and
microphone. The room's words were written for course sessions («انضم للحصة», «انتهت الحصة», "Session Ended", Teacher /
Student tags), so a calendar meeting said «حصة» everywhere.
**Decision.** `PreJoinPage` ALWAYS waits for the person: the camera / microphone preview and device pickers, then Join —
the page's one primary button (54 px, filled primary), which holds the keyboard focus so Enter presses it on the web
and desktop, and takes the focus back after a failed or cancelled join. `JoinArgs.autoJoin` stays as a deprecated,
ignored parameter for source compatibility; no caller passes it; `openMeetingRoom` / `openCourseLiveRoom` lost theirs.
A Rejoin opens the pre-join page with the room's mic / camera choice and waits too. After Join, a 202 `waiting` still
follows the lobby by itself. A guest's DIRECT link still skips the name step on the landing page (it goes on to the
pre-join page, which waits). Room texts follow the room's kind (`LiveRoomRef.kind`, from `JoinArgs.roomRef` or the
`-meetingId` convention): `live_room_words.dart` — `liveTr(key, kind)` reads `<key>_meeting` from translation.json
for a meeting (26 paired keys), `liveT(kind, ar:, en:, meetingAr:, meetingEn:)` for inline texts, `liveRoleLabel`
(Host / Participant in a meeting), `liveRoomNoun`. Each meeting text carries its own Arabic grammar (masculine
«الاجتماع»: «انتهى الاجتماع», «هذا الاجتماع», «قد يتم تسجيله»), never the session text with the noun swapped. RoomPage sets
`LiveRoomWords.current` while mounted, so leaf texts deep in the room (the background-call notification, the whiteboard
export hint, the share sheet, the recording banner) follow it without the kind threaded through every widget. Course
sessions keep their texts.
**Rejected.** Keeping auto-join for "Meet now" or Go live only (the owner asked for every entry, and the preview is the
one chance to fix a wrong camera or a muted microphone); swapping «الحصة» for «الاجتماع» inside one string (gender
agreement breaks: «انتهت الاجتماع»); an InheritedWidget for the kind (the room's dialogs and sheets live in the room
layer's own Navigator, outside the page's subtree).

## D-107 — Whiteboard: a continuous page grows sideways when a stroke is held at its left or right edge · 2026-10-30 · proposed

Amends D-093 (continuous page) and D-096 (edge auto-scroll).
**Context.** The owner: "when try to write on left or right edge of the board the board must scroll right or left to
extend the area of drawing." A continuous page grew only downward; left / right auto-scrolled only a zoomed page.
**Decision.** (1) Formats: only the CONTINUOUS page grows sideways (the infinite-canvas format). Landscape and portrait
stay fixed sheets with a clear edge: they are the slide (the 16:9 recording, the 1920×1080 PNG, a projector) and the
sheet of paper; "Add page" is their way to more room, and a zoomed fixed page still auto-scrolls inside itself (D-096).
(2) Coordinates: the column stays at x 0..1 and x may run from −`kBoardSideMax` to 1 + `kBoardSideMax` (1.5: a page 4
widths wide, ≈ 4 phone screens, ≈ 2 laptop screens); y unchanged. Nothing is rewritten: growing to the LEFT is a
negative x, so no stroke moves for anyone. The page's reach is derived, never stored (`boardContinuousSpanX`): the
column, widened to what is drawn outside it + 0.08 width of paper, to the presenter's view and to what this device's
edge auto-scroll grew it to; content inside the column never widens it (a line written at the very edge of a phone
does not). A device's sideways position is measured from the column centred on its stage (`ContinuousView.panX`), so
a page that grows keeps every line where it was on every screen; a page narrower than the stage stays on it (a
laptop shows the grown paper beside the column without moving), a wider one always covers it. (3) Growing: the D-096
rules unchanged (zone 12 % of the stage, 28–72 px, armed only after leaving the zone or travelling 24 px towards the
edge, 60 → 900 px/s quadratic, eased over 250 ms, the held pointer re-mapped every frame so the stroke never gaps);
on a continuous page the side edges' room is the cap, not the current page: a stroke, shape or moved selection held
at the right / left edge scrolls that way and the page grows under it (`scrolledBy(grow: true)`), up to the cap. A
mouse that leaves the column on a laptop simply draws on: the paper grows to the stroke. Text boxes open inside the
current reach (a box never widens the page by itself). (4) Wire, compatible: x travels on the widest range for ink
(`boardPoint`), shapes, text boxes and the laser; the annotation over a shared screen keeps its 0..1. An app from
before this decision clamps x to 0..1, so a drawing beside the column would reach it as a smear along the column's
edge — therefore the presenter announces `bv: 3` (`kBoardFeatureVersion` 3) as soon as anything on the board lies
outside the column (sticky while presented in that format; any participant's item counts, the presenter re-sends
the state before the first such point): an older app shows its existing "update the app" overlay instead of wrong
content. Until then a continuous board stays `bv: 2`, byte for byte the D-093 packets, and older apps keep drawing it.
The presenter's view carries its sideways part, `vp {x, w}` (page widths; left out while it is the column — keys older
apps ignore), clipped to the page's reach (a laptop's wide stage never widens viewers' pages). (5) Viewers: their page
reaches as far as the content and the presenter's view; "Follow" glides sideways too (`boardFollowLeft`: centred on
the presenter's view, nothing to do when the viewer sees the whole width); one finger / the mouse / Shift + wheel pans a
grown page sideways (D-096 hand and non-drawer pan) and leaves "Follow". A second, horizontal rail along the bottom
(never mirrored: page x runs left to right in every language) shows the view across the page and the presenter's
mark; the Follow button sits above it. (6) Export: Save as PNG of the whole board is as wide as what is drawn (1600 px
per width, at most 6400 × 8192, scaled evenly); "visible" is the presenter's view. The 2 fps recording track of a
continuous page (D-090) is now drawn from the items: the presenter's view widened to 16:9 over the page beside it
(`boardRecordingWindow`), so a phone presenter fills the frame and a grown page is recorded around the pen, redrawn
when the view moves. (7) A format change from a grown page to a fixed one centres the content and narrows it to fit.
Tests: `test/org/board_grow_sideways_test.dart`, `test/ui/whiteboard_grow_layout_test.dart`; renders
`test/visual/whiteboard_grow_golden_test.dart`.
**Rejected.** Growing the fixed formats (breaks the 16:9 recording / PNG / projector and the sheet-of-paper metaphor);
moving the origin or rewriting every item when growing left (every stroke jumps for everyone, a snapshot per growth);
an extent message on the wire (the reach follows from the content and the presenter's view, as the length does in
D-093); keeping `bv: 2` and letting older apps clamp (they would show a wrong drawing silently); an unbounded width (no
bound for snapshots, exports and the recording).

## D-104 — Course video: quality switches in place; "Listen only" is a bar at the top of the app · 2026-10-30 · proposed

**Context.** The owner: switching the video quality closed the video; add an option to only listen to the recording,
shrunk to a progress bar at the top of the whole app, so the person can move to any screen and let the phone screen
sleep. Root cause of the closing: since D-081 a bottom sheet opened from inside a tab goes to the ROOT navigator while
the player is a page of the TAB's navigator, and the quality / speed sheets closed themselves with
`Navigator.pop(playerContext)` — that popped the tab's top page, the player, and left the sheet open.
**Decision.** (1) The player's sheets go through `showVodPicker`, which closes the sheet with its own context and returns
the choice. A stream switch (`_switchVariant`) opens the new stream next to the old one (`openVodController`), carries
the place, play / pause, speed and captions (`VodCarry`), shows "Switching quality…" over the last frame, and on a
failure keeps the old stream playing with a notice instead of the error screen. (2) "Listen" in the player's top bar
hands the playing controller to `VodListenSession` and closes the page — nothing is disposed, so no second
POST …/play (a counted view). The session moves to the lecture's audio track (paired with the quality on screen),
else the lightest video tier, so no picture is decoded for nobody; Expand pushes the player again with the same
controller and goes back to the stream it showed. `VodListenLayer` sits in MaterialApp.builder OUTSIDE the assistant,
banners and live-room layer: the bar takes the status bar and everything else is laid out below it (keyed slot, no
Navigator rebuild), so nothing covers it and it covers nothing. Wakelock is released; `allowBackgroundPlayback` keeps
the sound with the screen off. The window is not screen-protected while only the bar shows (no picture is drawn;
FLAG_SECURE never blocked audio capture anyway); the protection comes back with the player. One sound at a time:
`MediaFocus` — opening another lecture's player or a live room (RoomPage) stops the bar; signing out stops it. The
resume position is saved every 5 s, on leaving the app and on close; the 75 % "watched" mark still counts. The bar is
PAINTED after the app (a bottom-up Column): a route's modal barrier (BlockSemantics) drops the semantics of whatever is
painted before the Navigator, which made the bar's buttons unreachable for screen readers and dead on the web while
semantics are on (found in the real web build). ViewAsBanner and the offline banner are built the old way and likely
have the same problem (not changed here).
**Rejected.** Making the player a non-route host like the live room (D-059) — a larger change to every caller for the
same result; an overlay bar drawn over the pages (it would cover app bars and back buttons); a media notification and
lock-screen controls (needs `audio_service`, a new package — follow-up); keeping the picture stream in listen mode.
**Round 7 (2026-10-31).** The owner: on the phone a quality pick STILL closed the video; add an "Audio" option that closes
the video and plays as a WhatsApp-like bar, also in the background and with the screen off. (1) Closing, reproduced on the S24 with a screen recording: the sheet rises from the bottom and its LAST row (the audio rows then, "Audio only" now) lands right under the chip that opened it, so a second tap on the chip (the sheet takes ~1 s to appear on a busy phone) or a tap while it is still sliding picks that row, which leaves the picture. A deliberate tap on 360p → 720p switches in place and the page stays. Fix: `VodSheetSettle` (in `showVodPicker`) ignores pointers until the sheet's entrance animation has completed; test "a tap while the sheet is still sliding in picks nothing". Also: the old stream is disposed only after the frame that draws the new one (`_switchVariant`). A build pointed at `http://127.0.0.1:18080` (a local stack over `adb reverse`) got 403 on every stream: links on 127.0.0.1 were taken for the offline loopback server and sent without `X-Device-Id`; every stream link now carries the header (the loopback server ignores it). Paused after a switch (seen twice, on the S24 and the web, not reproduced): `openVodController` had a 25 s limit on `initialize` only, and a seek into an unbuffered stream can hang; it now has ONE deadline over open + seek + speed + volume, 10 s for a switch (the old stream is there to go back to, with the "Couldn't switch" notice and playback resumed), 25 s for a cold start.
(2) The quality sheet ends with ONE "Audio only" row (`VodAudioOnlyTile`, answers `vodAudioOnlyChoice`): the page
closes into the bar exactly like the Listen button (same controller, same place, no second POST …/play); the old
in-place audio-track rows are gone from the sheet (the bar picks the audio track itself). (3) The bar is drawn like
WhatsApp's voice-note bar: play / pause first, title + time (a tap anywhere on them goes back to the video), a speed
chip that steps 1× → 1.5× → 2× (`VodListenSession.cycleSpeed`; a fixed pill of its own, so the label is never cut —
it was at 390 px), close; the ±10 s buttons and an explicit expand button only from 600 px. (4) Outside the app
WITHOUT a new package: Android `VodMediaService` (Kotlin) is a `mediaPlayback` foreground service for the whole
listen session (FOREGROUND_SERVICE_MEDIA_PLAYBACK) with a framework `MediaSession` + `Notification.MediaStyle`
notification (−10 s · play / pause · +10 s · close, seek line, lock screen, headset buttons) and a partial wake lock +
Wi-Fi lock while the sound plays, so Doze / Samsung's battery manager do not cut the stream with the screen off; iOS
`VodNowPlaying` (AppDelegate.swift) publishes MPNowPlayingInfoCenter and takes MPRemoteCommandCenter commands (the
sound already went on through UIBackgroundModes audio). Both speak `com.example.flutter_education_app/vod_media`
(`vod_media_controls.dart`; `VodMediaSync` sends only state changes and jumps — the OS runs the clock from the rate).
Audio focus stays with ExoPlayer (video_player sets it). Screen protection never blocked the sound. `audio_service` /
`just_audio_background` rejected: they want to own the player, and the lecture already plays in video_player's
controller (handed over, not reopened, so no extra counted view).

## D-108 — The live room has ONE top line (the whiteboard's header joins it, the rest folds into ⋮); full view shows only the content and slides the bars in on a tap · 2026-10-31 · proposed

Amends D-095 (the top row and full view) and D-087 (the board's own bar in the room).
**Context.** The owner (round 7): "sometimes when I open the board, some of the header icons stack (for example the page
number and the record info). I need all icons in one row, never more than one row and never stacked. Also when I
click full screen, I need ONLY the shared content in full screen; when I click on the screen, show the items with an
animation, and when I click again hide them again." With a board on the stage the room drew two bars: its top row
(LIVE, REC …) and, under it, the board's own `WhiteboardTopBar` (title, ‹ 2 / 3 ›, Board options, Stop). Full view
kept the self-view box, the side column, the board's bar and dock, and a floating exit button.
**Decision.** (1) In the room the board draws no bar (`WhiteboardRoomView(showTopBar: false)`; other callers keep it):
`LiveTopRow.board` (`LiveTopBoard`, plain values) puts the title, "You can draw", the page (‹ 2 / 3 › + Page for the
presenter, "2 / 3" for everyone else), Board options and Stop presenting on the same line as the recording — start ·
centre · end groups. (2) The line never wraps or scrolls any more (the start group's sideways scroll is gone): a
custom render object (`_FoldRow`) lays every piece out at its natural width and folds by priority until it fits — a
labelled chip first becomes its icon, then the least important pieces move into a ⋮ menu (board title, "You can
draw", network, lock, Board options, Minimize, Full view, the presenter's page arrows → "2 / 3", Stop, the free-time
countdown). The LIVE time, the recording control and the page number never leave the line (nor Exit in full view);
if even those do not fit (320 px at text scale 1.3 with everything on) the line is drawn slightly smaller. Folded
pieces stay built (they are measured) but are not painted, hit-tested or in semantics — tests find the drawn one
with `.hitTestable()`. (3) Full view: only the shared content — the share, the board page or the camera on the stage,
plus the presenter's camera box over a share / board (part of what is presented; its other cameras' bubbles go) — no
top row, bar, thumbnails, side column, participant badge, chat toast or self-view box. A tap on the content slides
the top row down and the bar up OVER the content (`widgets/live_focus_chrome.dart`, `LiveFocusChrome`: slide + fade
200 ms, at once under Reduce motion; the content never moves); the next tap, or 4 s without a touch on them, slides
them out. On entry a hint says "Tap the screen to show the controls" for ~2.6 s. The Full view chip reads Exit while
in full view; Esc, F and the back button still leave it; opening a wide side panel leaves it. (4) **The board is
view-only in full view, for the presenter too** (`viewOnly`: no dock, no input, board keys off): in full view a tap
must always mean "the controls", and a stroke cannot be told from that tap; the pen on a shared screen is put down on
entry. To draw, leave full view (one tap → Exit, or Esc / F).
**Rejected.** Keeping the board's bar and only making each bar one line (still two stacked lines — what the owner
reported); a scrolling start group (hides the page or the REC time off-screen with no hint); drawing in full view with
a long-press or a dedicated handle to show the bars (an invisible gesture, and the dock would cover the content); the
floating exit button of D-095 (the owner wants only the content).
**Amended (round 7, drawing in full view).** The owner wants the presenter, and anyone allowed to draw, to keep
drawing in full view, so (4) is replaced: the page keeps its input there (`WhiteboardRoomView(fullView: true)`: no room
kept for a bar or a dock, the board's keys stay on except Esc, which leaves full view once no box is selected). A tap
on the page of someone in draw mode is a dot of ink (the board's own tap claim, as outside full view), so for them a
small glass **Controls** chip (`LiveFocusHandle`, 34 px drawn / 48 px hit, top centre) shows while the bars are hidden;
its tap slides the top row and the bar in, and the board's tool dock comes WITH the bar (`WhiteboardDock`, the dock
taken out of `WhiteboardRoomView`, drawn above the bar in `LiveFocusChrome`'s bottom), so the content still never moves.
Tool, colour and size live in the board controller, so the pen keeps what was picked before or in the dock after the
bars slide out (the next chip tap, or 4 s without a touch on the bars, as before; a stroke on the page does not count
as a touch on them; the bars sliding out never cuts a stroke, the page is not inside their layer). The hint reads "Draw
on the board · Controls at the top shows them" for them. Viewers, and a drawer outside draw mode (hand tool), keep
"a tap shows / hides the bars"; a tap off the page still toggles for everyone. The chip takes the top-centre 48 px of
the page from the pen while it is shown. A pen on a shared SCREEN is still put down on entry (its toolbar is chrome).
Rejected again: "a tap toggles only when not drawing" with no chip (a drawer would have no way back to the tools
except Exit); a long press (invisible, and it fights the pen's own hold). Tests: `test/ui/live_focus_chrome_layout_test.dart`
(the chip), `test/ui/whiteboard_full_view_layout_test.dart` (a tap is a dot and never reaches the room, a stroke stays
whole, a viewer's tap reaches the room, the dock with the bars keeps the tool).

## D-109 — Whiteboard: the continuous page's rails are scrollbars (long press grabs the thumb) · 2026-10-31 · proposed

Amends D-093 / D-107 (the rails were indicators only).
**Context.** The owner (round 7): "I need the vertical scroller to move up and down and the horizontal one right and
left when I long-press the scroller indicator."
**Decision.** (1) Both rails' thumbs are draggable. A finger or a pen grabs a thumb with a long press
(`kLongPressTimeout`, haptic tick); the mouse grabs it on press, no wait. Grabbed, the thumb grows from 6 to 12 px,
takes the accent with a soft glow, and the drag moves the view along that axis in proportion to the page: the thumb's
free travel maps onto the view's free travel (`BoardRailMetrics`, pure, `board_scrollbar.dart`; thumb ≥ 18 px, the
same mapping both ways, clamped). A tap on the track beside the thumb moves 90 % of a screen that way. Hit targets: the
thumb ≥ 44 × 44 px however thin it is drawn, the track 24 px across. (2) The rails stay drawn as before (thin, inside
the page's edge on a phone), so they must not eat strokes: a pointer that lands on a rail is HELD BACK from the pen and
from the view pan (a translucent listener on top of the stage claims it; `_down` / `_zoomDown` keep the down event)
until it grabs (then nothing draws), taps the track, or — a finger or pen that moves past the touch slop first, or a
tap on the thumb — is handed to the board as if it had just come down there (the stroke starts at the original point,
no gap). So writing at the very edge of a phone still works; only a finger held still on a thumb for 0.5 s scrolls. A
rail press is ignored while a stroke, a pan or a pinch runs, and a grabbed thumb blocks new strokes and pinches. (3)
The rest reuses the existing paths: a viewer who drags a thumb leaves Follow exactly like a hand drag (`_leaveFollow`),
the presenter's view goes out with the next build's `reportViewport` like any scroll, edge auto-scroll belongs to a
drawing pointer only and so never runs at the same time. The presenter's mark on the rails is unchanged. (4) Web QA
of round 7: a long press just off the thumb drew a stroke (the thumb shrinks as the page grows, so a press aimed at it
from a moment ago lands on the track, which had no long press). A finger or pen held still on the TRACK now grabs as
well: the thumb first jumps under it (centred, clamped), then drags; a tap on the track still pages, a move first
still draws.
**Rejected.** Making the whole 44 px strip along the edge opaque (it would block writing at a phone's edge); a
`GestureDetector` long press in the arena (the board reads raw pointers, a stroke would start before the arena
decides); moving the rails outside the page on phones (there is no room: the column fills the width).
Tests: `test/org/board_scrollbar_test.dart`, `test/ui/whiteboard_scrollbar_layout_test.dart`; renders
`test/visual/whiteboard_grow_golden_test.dart` (`rails`, `vgrab`, `hgrab`).
(5) **The floating cameras rest beside the vertical rail** (web QA, 1280 × 800): the presenter's camera box sits on
the page's bottom-end corner (D-105), which is exactly where the continuous page's vertical rail runs (8 px outside the
end edge, or inside it with no room; the left edge in Arabic), so the thumb was half hidden and a press there dragged
the box. The board marks the rail's drawn strip (`WhiteboardStage.railKey`); the room reads it in the stage's frame,
widens it to the thumb's hit width (`boardRailHitStrip`, `kBoardThumbHit` 44 px) and hands it to both floating layers
(`PresenterCamLayer.rail`, `SelfViewLayer.rail`). `selfViewClearOfRail` (pure, `live_self_view.dart`) grows the
keep-out on the side whose column the strip reaches, by the strip + 4 px, so the box stays on the page's corner, just
beside the rail (11–30 px further in); mirrored in Arabic. No rail (a fixed page, a page that fits, a screen share):
nothing changes — D-105 is untouched for shares. The room's 1 Hz clock re-places the boxes when the rail comes, goes or
moves (the page grew, a zoom). Tests: `test/org/live_over_content_test.dart` (`selfViewClearOfRail`),
`test/ui/presenter_cam_layout_test.dart` (beside the board's scrollbar, both directions; a share keeps its corner).

## D-110 — The Android device recording copies the room from Flutter's own surface at 30 fps · 2026-10-31 · proposed (measured on the S24)

Amends D-135 (its "room frames at ~12 fps" part).
**Context.** The owner (round 7): "the live camera is shown in the recorded video as slow motion (like 10 frames per
second or less). I need it at a normal frame rate like real videos." Session 75 on the S24 (D-135 build): the file is
576×1280 at 14.76 fps (2057 frames / 139.4 s), and the camera circle changes only 10.0 times a second (median 12, gap
p95 136 ms). Three caps stacked: (1) Dart drew the room (`RepaintBoundary.toImage` → `rawRgba` → platform channel →
`glTexSubImage2D`), ~55 ms a frame on the S24, paced to ≤ 12 fps / ≤ 50 % duty (`live_frame_pacing.dart`); (2) the
renderer's clock drew at 15 fps, and `postDelayed` after the draw stretched even that; (3) the encoder was set to 15
fps. Before a share the recorder never holds a MediaProjection (the teacher grants one only for a share), so the
picture has to come from inside the app.
**Decision.** `RoomFrameGrabber.kt`: while the device recorder records video and nothing is shared, the native side
reads the already-composited frame of Flutter's own `FlutterSurfaceView` with `PixelCopy` (camera texture, board and
controls included — what the teacher sees), cropped to the room's rectangle and scaled by the GPU to the encoder's
long side (1280) into one reused bitmap, uploaded with `GLUtils.texSubImage2D` and drawn into the encoder AT ONCE,
stamped with the copy's time (`eglPresentationTimeANDROID`, stamps forced monotonic). One copy in flight, the next at
most every 33 ms after the previous one started (deadline based) → 30 fps; no Dart work, no channel copy. Dart
(`room.dart`) starts it with the room's rectangle in physical pixels (`startRoomCapture`, answers whether a first copy
worked within 2.5 s), re-sends the rectangle and "visible" (not minimized) every 500 ms (`updateRoomCapture`), stops
it on a share / pause / end (`stopRoomCapture`). The renderer's own clock becomes a keep-alive in placeholder mode
(draws only when no frame was pushed for 45 ms: the app in the background, the Dart fallback) and is deadline based;
during a share it draws the recording at 30 fps (the share's capture pass stays throttled to the share's own fps).
`SegmentedRecorder` encodes 30 fps at 2.5 Mbps by default (was 15 fps / 2 Mbps; a mostly still room compresses well,
so not doubled; a meeting's picked quality keeps its own bitrate). Chunks, the gapless cut and `seamless=1` are
unchanged. The Dart frames (D-135) stay as the fallback when the copy does not work (an older native side, a Flutter
surface `PixelCopy` cannot read); the PNG path stays behind them.
**Measured** (S24, session 77, 103 s): 30.01 fps, every frame step 33 ms; the camera changes 29.1 times a second
(was 10.0, session 75); PixelCopy ~30 / s, 0 failures; thermal status 0, the app 68–110 % of one core; the published
camera kept its 1280×720 layer. Details in `docs/live/recording_design.md` ("Device recording frame rate").
**Trade-offs accepted.** The copy is the WHOLE composited room, so a sheet or dialog opened over the room and the
app's toasts are in the recording too (the Dart capture only saw the room's body); the teacher's own view, as in a
share. A GPU→CPU read and a CPU→GPU upload of ~2.9 MB per frame (~90 MB/s each way at 30 fps), on background threads.
iOS is untouched: it records the app with ReplayKit (`RPScreenRecorder`), which delivers the screen at its own rate
and has no 12 / 15 fps cap in our code; web composes in the browser.
**Rejected.** MediaProjection of the app's own screen for the whole class (a system consent dialog at every
recording start, the privacy chip all class long, and on Android 14+ the one projection could no longer serve a later
share); compositing the WebRTC camera texture natively (needs a change in the flutter_webrtc fork and drops what the
room shows around the camera — the board, the controls); simply raising the Dart pacing (each Dart frame already
cost ~55 ms on the S24: 30 fps would not fit in the UI / raster threads).

## D-111 — ONE course page: the course profile's parts are tabs of the course details / studio; one frosted header capsule; the sessions timeline as cards on a line · 2026-10-31 · proposed

**Context.** The owner: "in the course details there are two profiles (course details, course profile) — make it ONE
smart page, as premium as possible; redesign the header icons (back, share, refresh, edit); the sessions list is too
simple." The student's course details and the teacher's studio (both `CourseSpace`) each had a "Course profile" quick
action that pushed `CourseProfileScreen` (overview · lectures · sections · attendance · announcements · certificates ·
team · archive) — a second page about the same course with its own hero and tabs.
**Decision.** The profile's parts became tabs of the one page (`lib/features/shared/course_profile/course_profile_hub.dart`):
student — Announcements (unread count) · Progress (per-part progress, attendance, grade, certificates) · Archive (closed
course: code / request) and the teaching team in About; staff — Announcements · Attendance (open attendance, by hand,
the numbers, the attendance report, certificate rules) · Team (assistant grants) · Archive (access policy, requests,
versions). The existing profile widgets are reused (`CpOverviewTab(merged: true)` drops what the page already shows);
every capability is still the server's (`caps`), an archived course is read-only (an archived-course spotlight card;
the student's Sessions tab reads the profile's material then, the buy card / bar are hidden), a TA posts to sections &
labs unless granted, and Edit shows only with `course_settings` once the profile is known. The profile is loaded
LAZILY (`CourseProfileHub`): when one of its tabs or About's team block is first built — opening the page costs no
extra request. `openCourseProfile`, the `/course-profile` route and `course_profile` notifications open
`CoursePageLoader`, which reads the profile (it needs the role), then GETs the course and opens the student page or the
studio at the asked tab (old names mapped by `cpMergedTab`) or the smart one (closed → Archive, unread → Announcements).
`CourseProfileScreen` stays only for an earlier run (Archive → Versions, read-only) and as the fallback when the course
itself cannot be opened. Header: back is one frosted disc; every other action sits in ONE frosted capsule at the end
(48 px targets, labels for screen readers, the favourite a toggle), the teacher's Edit carries its word on wide screens,
and rarer actions (Ask the course documents, Refresh on web / desktop) go behind its ⋮; phones refresh by pulling.
Sessions: each session is its own card on the timeline — a kind tile (live · video · section), "Up next" / "Live now"
as the highlighted cards with their one primary action (the student's Start / Continue, Join, Enter room), a date chip,
length and files, a progress ring on the student's node, a breathing live node (parked by Reduce motion), quieter done
cards, and month headers when the dated sessions span months (`courseSessionGroups`).
**Unread.** The course payload `GET /courses/{id}` carries the page's state for the signed-in caller: `closed` (the
organization archived the last run, the profile's own `closed`) and `announcements_unread` (announcements with an id
above the person's `course_announcement_seen.last_id`, their own posts excluded — one indexed count, back migration
0031). `CoursePageState` parses them, the page feeds them to the hub (`CourseProfileHub.seed`): the badge shows on open
with no extra request, a closed course loads the profile at once (its archive state and read-only material are there),
and the page opens ONCE on `openingTab()` when nobody asked for a tab — a student's closed course without a pass →
Archive, unread → Announcements (a student only when enrolled) — until the person picks a tab. Showing the
Announcements tab posts `POST /course-profile/{id}/announcements/seen {last_id}` (the newest id shown), not the list
GET: the list may be prefetched without being shown. An older server sends neither field: "unread" is then newer than
the last one seen on this device once the profile is loaded, the page keeps its first tab, nothing is posted.
**Rejected.** Loading the profile on every open (one more request per course page for data most visits never read);
keeping the profile as a page behind a quick action (the owner's complaint); a separate Team / Archive for students
(the team is a block in About, the archive appears only for a closed course).

## D-103 — One organization dashboard for every non-student org role · 2026-10-31 · accepted

**Context.** Org staff who "managed nothing" (an assistant, a teacher-member) were bounced from `/org_dashboard` to
`/org_member`, so the same person met two different organization UIs depending on a cached flag, and members without
any right had no dashboard at all. The owner wants ONE dashboard per role, simple enough for a first-time user.
**Decision.** `OrgDashboardScreen` is refitted in place (no second dashboard, no v2 route): every person who is in an
organization and not a student there — org admin, sub-admin, staff, member without rights — opens it.
`GET /org/mine?members=1` lists those organizations with `access` (admin · staff · member) and `member_role`; an older
server's items are read the same way (`orgAccessOf`). The "manages nothing → /org_member" hop is gone
(`AppModeController.orgStaffHome` removed); `/org_member` stays the student's organization page. From a personal home,
choosing an organization where I am not a student opens the dashboard on it. Every page has the same header
(`OrgPageHeader`: title · one primary action · Refresh with "Updated …" · calendar · bell with the unread count · the
shared context switcher, phones included); the shell's top bar is off for this shell so nothing appears twice. The
switcher selects in place (`OrgSession.select`, remembered by `AppModeController`), and its "Personal" entry replaces
the per-page exit button. **Students are blocked from the dashboard only** (403 `student_forbidden` on the dashboard /
search APIs; grants they hold keep working elsewhere): they see "This dashboard is for staff" with one "Back to my
home" button, never "Create organization". While the dashboard is open, `org_access_changed` and any 403
`org_forbidden` / `student_forbidden` from an org call reload `/mine?members=1` (kept organization when still listed,
else the next, else the staff-only page) and re-derive the sections.
**Cost.** The org-admin home makes one more request on open (5): the bell's unread count, the same call every other
role shell makes. The membership overview is loaded only when the switcher is used.
**Rejected.** A separate "staff dashboard" route (two UIs to keep in step); keeping the hop for members without rights
(the same person would land on different pages by a cached flag); hiding the dashboard's student block behind a client
check only (the server is the authority, the app follows its 403).

## D-130 — Export Studio: interactive exports render in the app, scheduled ones on the server · 2026-10-31 · accepted

**Context.** The Export Studio brief asks for PDF / Word generated on the server for Arabic correctness. The app
already writes PDF / Word / Excel itself (`lib/design/export/`, `lib/design/export_hub/`): Arabic shaping and embedded
fonts are done and unit-tested, and the rows come from the API that served the page, which already applied the
caller's permissions, filters and sort. Scheduled exports and expiring links, however, run when no app is open.
**Decision.** An interactive export keeps rendering on the device from the saved template (`ExportDesign` JSON,
versioned); the app reports it to the export log (column keys and row count only). The server renders only what it
must: scheduled runs and links made from a server run, from the SAME template JSON, through a registry of server
datasets (`../back/services/export_datasets.py`) whose columns each carry a visibility rule, so a forbidden field is
never produced. Formula injection: the app writes every text cell as an inline string (never parsed as a formula),
the server passes every text cell through `helpers/xlsx_safe.py`.
**Cost.** Two renderers (Dart, Python) read one template schema; the server's covers the table-oriented subset and
datasets are added one by one.
**Rejected.** Moving every export to the server (re-implements tested writers, sends every page's data back up, adds
load for the common two-click export); client-only schedules (impossible without an open app).

## D-131 — Certificate design v2: independent language designs, many logos and signatures · 2026-10-31 · accepted

**Context.** One design row held both layouts but SHARED orientation, background, logo, signature and theme, and a
single logo / signature URL was pasted into every logo / signature box. Saving reset 20 of 28 fonts to Tajawal (stale
allow-list on the server), which is what made "the Arabic design" fail to save.
**Decision.** The font allow-list is the renderer's catalog. English gets its own nullable `*_en` columns
(orientation, background, theme, logo, signature); NULL means "same as Arabic", so every existing design renders
exactly as before. Each logo / signature box carries its own image (`src`, checked like every uploaded image) and a
signature box its name and title; `langs` says whether a certificate is Arabic, English or both, and issuing renders
only those. One `design_spec(design, lang)` builds what the renderer draws, for preview, course issuing and
standalone issuing alike.
**Rejected.** A second row per language (breaks every course link to a design); a JSON blob replacing the columns
(no backward-compatible read for older apps).

## D-132 — Standalone certificate issuing · 2026-10-31 · accepted

**Context.** Issuing required a course and an enrolled student; organizations also certify workshops, competitions
and external participants.
**Decision.** Separate tables (`cert_issue_batches`, `cert_issued`, `cert_recipient_lists`); the course flow and its
tables are untouched. The template's dynamic fields decide the columns of a pasted list or sheet; rows are validated
and matched to platform students, unmatched names may still be issued as manual recipients. Every issued
certificate stores a serial and a random verify token (public verify route, QR field kind); revoke and re-issue keep
history. Batches run as background jobs in chunks and produce a ZIP and a merged PDF.

## D-133 — One studio engine, two data models · 2026-10-31 · accepted

**Context.** The certificate designer (logical units, server-rendered) and the Export Hub designer (page fractions,
client-rendered) each had their own canvas, drag, resize, snap and undo.
**Decision.** `lib/design/studio/` owns selection, move / resize, snap guides, align, undo / redo, zoom and the
property primitives, and talks to each studio through a host adapter; each studio keeps its own document model and
renderer. A fix in the engine reaches both.
**Rejected.** One shared document schema for certificates and exports (forces a migration of every stored design for
no user-visible gain).

## D-134 — Expiring export links require sign-in · 2026-10-31 · accepted

**Context.** Shared download links must "never expose data to unauthorized users", and exports often hold students'
personal data.
**Decision.** A link is a hashed random token with an expiry (default 7 days, max 30) and revoke; downloading needs a
signed-in user who passes the audience rule (`me`, or `org` = members of the same organization who pass the
dataset's permission check). Every download is logged. No anonymous public links.

## D-120 — Course roadmap + "Recommended for you": personal accounts only; the teacher's path first, the engine's list apart; ONE calm journey card on the home · 2026-10-31 · proposed

**Context.** The owner's brief: a teacher-defined roadmap per course (previous · "You are here" · next with
prerequisite status) on the course page for both roles, a backend hybrid recommendation engine with a reason per pick,
a "Recommended for you" list with "Edit my interests" on the student's profile, and exactly ONE small shimmering card
on the student home — for individual accounts only. A forward roadmap already existed (`course_next_steps`, edited as
`next_course_ids` in the course form, a dark "journey" footer with "Enroll in the whole roadmap" and an auto "similar
courses" strip on the student page, a read-only footer on the studio); personal courses had no linked prerequisites,
no level / tags, no interests.
**Decision.**
- *Who.* An account that belongs to an organization (role org-admin / org-staff, or a live membership of an approved
  organization while organizations are on) gets neither feature, in any mode and on any course; an organization course
  has no roadmap (owner's answer: "any org membership"). The server enforces it (`services/learning/access.py`: 403
  `individual_only` / `org_course` / `feature_off`, and `GET /courses/{id}` empties `next_courses`,
  `recommended_courses`, `similar_courses`, `recent_completed_courses` for them); the app hides the parts
  (`roadmapOrgAccount`, `roadmapHiddenError`). With organizations switched off memberships do not count. The roadmap
  bundle checkout stays as it was (organization programmes use it with their own prerequisite checks).
- *Roadmap.* Extends the existing data: next courses stay `course_next_steps`; prerequisites are new course links
  (`course_prereq_links`, the owner's own personal courses, never also a next step: 422 `roadmap_cycle`), advisory only
  (owner's answer: show status, never block enrolment); `courses.level` / `courses.tags` are new (migration 0031). Read
  and edited through `GET/PUT /api/v1/roadmap/courses/{id}` (+ `/candidates`). On the course page it is a "Path" tab
  (`lib/features/shared/roadmap/roadmap_tab.dart`) for both roles: ONE vertical path (`roadmap_path.dart`): previous →
  the course tinted "You are here" → the next courses numbered, each with its prerequisites as ✓ / ○ chips; the student
  sees states and live % (done = enrolment completed or every material done, the app's rule) and "Enroll in the whole
  path"; the teacher sees drafts and edits in one sheet (`roadmap_editor.dart`: add · drag to reorder · remove next
  courses, prerequisites, level, topic words). The tab replaces both old footers; the teacher's own picks stay a
  separate "Picked by your instructor" list under the path.
- *Recommendations.* `services/learning/scoring.py` (pure, `tests/org_v2/recs_unit.py`): item-item collaborative
  filtering (cosine over students who took both, ≥ 2 shared students, else its weight is shared out) 0.35 · content
  (same / related category, tags, the next level up) 0.30 · same teacher in a matching field (a teacher of several
  fields lends weight only to the matching courses) 0.25 · popularity (recent enrolments + a little rating) 0.10, the
  cold-start fallback; ≤ 3 picks per teacher; ONE reason per pick (the strongest signal) with its Arabic and English
  sentence. Never an enrolled / dismissed / private / draft / organization course, nor a next step of a course the
  student took (the teacher's path has priority and the two lists never mix). Cached per student in `course_recs`,
  rebuilt only when older than 6 h or when the student's enrolments / interests change, refreshed hourly for students
  who asked lately (`learning_recs_tick`); only counts of other students are used.
- *Profile.* "Recommended for you" (3 + "See all", the reason under each, "Not interested") and "My interests"
  (fields picked or inferred from the courses taken; "Show recommendations" switch) — `recommendations.dart`.
- *Home.* ONE card under "My courses" (`home_journey.dart`), from `/me/home`'s `journey` (no request of its own):
  "Continue your journey in <field>", the next step only, a light bar of the path done; card surface + hairline like
  the calm home (D-102). Its light sweep is the attendance entry's exact band, now the shared `AppShineBand`
  (`lib/design/app_shine.dart`), crossing in ~1.8 s every 6 s; Reduce motion parks it (and the attendance entry now
  goes through `syncMotionLoop` too). No clear field (no roadmap, no completed course or chosen interest with a cached
  pick) → no card. Tap → `JourneyPage` (`GET /me/journey`).
- *Switches.* `roadmap` (all), `roadmap.path` (the tab), `roadmap.recommendations`, `roadmap.journey`,
  `course.enroll_roadmap`, `roadmap.teacher_picks` — a key off on every platform turns the route off too.
**Rejected.** A second roadmap table beside `course_next_steps` (two truths for one path); blocking enrolment on
prerequisites (changes checkout and the roadmap bundle — the owner chose status only); computing recommendations on
each request or inside `/me/home` (the home reads only a cached pick); a gradient hero card on the home (it would
compete with the live card, the page's one strong accent); mixing the teacher's next steps into the engine's list.
**Round 2 (same day, the review's points).** Next courses reorder from each row's ⋮ menu and the screen reader's
actions too (keyboard / one hand); `GET /courses/{id}` hides drafts from everyone but the owner; "Not interested" has
Undo (`showAppNotice` gained an optional action) and the interests sheet "Show hidden courses again"; the old footers
are deleted. Speed: the hourly tick stores the collaborative counts in `course_pairs` / `course_stats`, so a request
reads only its own rows; "last asked" is written at most hourly; the home's journey is cached on the prefs row with a
signature of everything it depends on; `AppShineBand` rests on a timer (no ticker between passes); a course reaching
100 % marks the lists stale. Product: the course form shows level / topic words and, for a personal course in edit
mode, links to the Path editor instead of its own next-courses field (and stops sending `next_course_ids`, which
would undo the Path tab); interests group sub-fields under their field (a picked parent covers its sub-fields at
0.9; a course taken outside the picks now counts half even in its own field); the super admin's Recommendations
page (`admin_recs_page.dart`) shows shown / opened / dismissed / enrolled per reason and edits the four weights.
**Real app (2026-10-31, profile web build on a copy of the dev database, the worktree's API in its own container).**
Verified: the home card from `/me/home`, the journey page, the student's Path tab (89 % "You are here", the next
steps with a prerequisite not done, "Enroll in the whole path"), "Recommended for you" with reasons, the interests
sheet, the teacher's editor, an org member without card, the admin page counting the browser's own `shown` events.
Fixed from it: interests without sub-fields share one wrapped row (each had a row of its own); the owner opening
the public page (a share link) gets the owner's path (`can_edit` wins over the student page); old deep links may
name the `path` tab (`cpMergedTab`).
**Accessibility (2026-10-31).** `test/ui/roadmap_a11y_test.dart` runs `meetsGuideline` (tap targets, labels, WCAG
contrast; ar / en, light / dark, phone / wide) over every D-120 widget. It caught `AppSwitchTile` exposing only its
46x28 switch to screen readers and the tap-target check although the whole row toggles: the tile is now ONE merged
node (title + subtitle read once, toggled state) with a 48 px minimum height. That is a kit change, so every
settings row that uses the tile gains it. Migration 0031 was also run through Alembic on PostgreSQL (0001 → 0031,
down to 0030 and up again).
**Round 3 (2026-10-31, the owner's "do all").** *"Your next step is ready":* when a personal course reaches 100 %,
the first course its roadmap places next that the student can see and has not enrolled in is announced once (in-app +
push, no e-mail fallback; the tap opens that course through the existing `related_type: course` target). Never for
an organization account or course; kill switch `roadmap.next_notice`; once per student and next course (the
notification row is the record, so no new column). Sent from a thread after the progress commit
(`services/learning/notices.py`), so marking a lesson done never waits on FCM. *Exploration:* ranks 5 and 15 of
"Recommended for you" show the most popular course (≥ 2 recent students) from a field the student never touched,
neither chosen nor taken, nor a sub-field of one, with the reason `explore_field` ("Popular in Design, a field new
to you"). One field per slot; skipped on a cold start (everything is new then) and when the top 5 already reaches
outside. Rejected: a random pick (the list would change on every visit and the reason could not be told); a
separate "Explore" row (a second list beside the roadmap and the recommendations).
**Amendment (2026-10-31, "personal context, not personal account").** The roadmap and the home card never appeared
for most students: (1) *who* — any live membership of an approved organization closed every part in every mode, on
the server (`access.is_org_account` → `/me/home` journey null, 403 `individual_only`, course detail lists emptied, no
tick, no notice) and in the app (`roadmapOrgAccount` read `AppModeController.available`); (2) *data* — the interest
card waited for a cached "Recommended for you" list, so a student who never opened the profile list got no card
even with a completed course or a chosen interest. Now: hidden only in Organization mode (`isOrg`) and for
org-admin / org-staff logins; a member's personal space gets the path, the list, the card and the notice for
personal courses. The server has no per-request mode, so its guarantee is the data one: an organization course
(`Course.org_link`) never reaches a roadmap list, a journey step or pick, or a served recommendation — filtered at
read time too, so a course moved into an organization after it was cached / named drops out. With no cached list
the card takes the field's most popular personal course (one query; the engine still never runs inside the home).
The card's only intentional absence is "no clear interest yet" (no roadmap course, no completed course, no chosen
interest) or recommendations turned off by the student. App gate: `homeJourney()` (`home_journey.dart`).

## D-136 — Brand gradient: primary fills are a gradient derived from the primary family, every stop AA under the on-hero ink · 2026-10-31 · accepted

**Context.** The owner: "why is primary only one flat colour? Give primary buttons and the overall UI some gradient so
it feels premium." The server already sends `gradient_primary`, but it is built from the two ACCENT colours (gold /
olive, M22), and the production `primary_light` (#34A883) carries white text at 2.97:1 only.

**Decision.** `ThemeConfigProvider` derives the brand gradient roles from `primary_light` / `primary` / `primary_dark`
(no new server key; optional `primary_gradient_start` / `_end` replace the outer stops and pass the same guard):
`brandStops(dark:)` = lift · primary · deep, the lift moved toward primary_light (≤ 55 % light, ≤ 35 % dark) only as
far as `onHero` keeps 4.6:1 on it, the deep end stopping short of primary_dark in dark mode so the fill still
separates from the page. Roles: `primaryGradient` (135°, `AlignmentDirectional.topStart → bottomEnd`, mirrored in
Arabic), `primaryGradientPressed` (each stop 16 % toward hero_shade), `heroGradient` (primary → deeper; no lift under a
hero's muted subtitle) + `heroGlow` (a radial accent2 light in the top-end corner, alpha capped by the same contrast
rule), `surfaceGlow` (a 5 % / 10 % wash for headers) and `primaryButtonShadow`. Flat `primary` stays THE colour for
text, icons, outlines and focus rings. Production: lift #178467 (4.6:1), primary #0F7B5F (5.2:1), deep #0A5642
(8.7:1).

Applied in shared widgets only: the Filled / Elevated button themes paint the gradient (an `Ink` in
`backgroundBuilder`, so the ripple, hover and focus overlays draw on top) when the button's Material colour IS the
primary, so a danger / success / tinted / disabled button keeps its own fill without any screen change;
`PrimaryButton` (now an InkWell with a ripple, a pressed variant and a keyboard focus ring), `AppPrimaryButton`
(+ soft coloured shadow; disabled = flat neutral well), `OrgPrimaryButton` (through the theme) and the org page FAB,
`AppHero` and `HomeHeroCard` (hero gradient + glow), `AppChoiceChip` selected, the phone bar's active tab (it used the
server accent gradient, which faded to cream under a white icon), the light sidebar (`slideBarGradient`: the brand
gradient instead of the server's `gradient_slider`, which faded to the cream accent under the on-hero labels) and the
dark sidebar's selected item (a brand pill). Not changed: the raw `FloatingActionButton` theme
(Material cannot take a gradient there), chart colours (D-063), progress bars (they carry score colours). Checked by
`test/ui/brand_gradient_test.dart` (contrast of every stop for four palettes, the button rule) and by eye in
`test/visual/brand_gradient_golden_test.dart`.

## D-137 — Direct app downloads from our own site, one releases manifest, the web app on iPhone · 2026-11-01 · accepted

**Context.** No Google Play or App Store account, zero budget. Students must still get the app from the platform: the
web build offers the right build per device, the native apps learn about new versions, and publishing a version must
not need a web build.

**Decision.** One static manifest, `https://nextbrain.site/releases/releases.json` (schema in
`lib/core/get_app/releases_manifest.dart`), and the files beside it in `/root/nextbrain/releases/` on the server
(outside `build/web`, which `flutter clean` wipes), served by nginx at `/releases/` (immutable cache for versioned
names, `no-cache` for the manifest and the `-latest` links, range requests, rate limits, an access log without IP or
user agent). `scripts/release/publish_release.py` builds, checks and uploads; `release_manifest.py` on the server writes
the manifest from the files it serves. Readers: the web banner and the "Get the app" row / sheet (replace the earlier
`web/app_links.json` store links), and the native update prompt (replaces the placeholder store URLs of
`VersionCheckService` and its `GET /app/version-check` call; the build number decides, `min_build` forces).
- Android: three APKs signed with the release key (arm64-v8a is the banner's button, armeabi-v7a for 32-bit phones,
  universal), native libraries stored compressed (`useLegacyPackaging`, ~49 MB instead of ~84 MB per ABI). R8 stays
  off (D-026: it needs a device pass of live sessions first). All variants keep pubspec's versionCode
  (`--target-platform`, not `--split-per-abi`, whose versionCode offsets would make a later universal APK a
  "downgrade" and break the build-number comparison).
- iPhone / iPad: the installable web app (Share → Add to Home Screen), because every native route without the App
  Store needs a paid Apple account (TestFlight, Ad Hoc, Custom Apps, EU Web Distribution) or breaks Apple's terms
  (enterprise certificates, free 7-day signing as distribution). The installed web app asks for notifications only
  from a tap (iOS rule), through the banner's "Turn on notifications" strip.
- Windows / Mac: the installable web app (Chrome / Edge prompt, Safari's Add to Dock). A native Windows build would
  need Visual Studio and has no `video_player` implementation; macOS needs a Mac.
- Linux: a native preview (.deb + .tar.gz) built on the server (`scripts/release/build_linux.sh`); `video_player` and
  Firebase have no Linux implementation, so recorded lessons do not play there and the banner offers the web app
  first (`"primary": "pwa"`), the packages listed under it.
- Kill switches `get_app.banner`, `get_app.entry`, `app.update_prompt`. Analytics: `GET /releases/ping/<os>/<event>`
  beacons answered 204 by nginx and counted from its log (no personal data, no backend route).

**Not done / owed.** A signed Windows / macOS build (code-signing certificates remove SmartScreen / Gatekeeper
warnings); iOS native through TestFlight once an Apple Developer account (or the nonprofit / education fee waiver)
exists; the `applicationId` is still `com.example.flutter_education_app` (Play rejects `com.example`; changing it
means a new Firebase Android app and a reinstall for everyone). Done in D-145: `com.doubley.nextbrain`.

## D-140 — Requests for someone else: who may file them, and where the person's details live · 2026-11-01 · accepted

**Context.** The owner's brief (Studio + Requests, items 3.1–3.5): any member and a department manager can submit a
request or complaint — to an academic or service department, or to the Department Council — for themselves, for
another member picked from a searchable list, or for a person outside the system entered by hand (name required;
phone, e-mail, national id or student number, relation optional, all validated). The server must enforce a "create
for others" right; members get it for the council path only if the governance spec says so. Before, the staff route
took a bare `source_user_id` (never checked for membership) and the app never sent it; attachments were URLs only.
**Decision.**
- *Who may file for others.* A new action `workflow.on_behalf` ("Create for others") on the `workflow` module.
  It is held by the org / platform admin, the head of the target entity, and the system roles `dept_head` and
  `dept_staff` of that entity (migration 0037 backfills the existing roles once; an admin may take it away or grant
  it to anyone, per entity). A plain member does NOT have it by default, also not on the council path: the spec
  (§6, `to_council`) puts a member's OWN request before their Department Council, so filing for someone else stays a
  staff / manager right there too (the head of a scientific department has it, and may use `to_council` for others).
  The check is `beneficiary.can_create_for_others` on the server; the member entity list carries
  `can_submit_for_others` so the form shows the choice only where it will be accepted.
- *Who it is for* is a separate row, `org_work_beneficiaries` (kind `member` with `user_id`, or `external` with
  name and the optional fields), not columns on the item: the personal details then travel only where needed. The
  submitter stays `source_user_id` (they withdraw, resubmit and are excluded from a council vote); the member it was
  filed for sees, follows and comments on the item and gets every notice. A picked user must be a live member of the
  SAME organization (422 `beneficiary_not_member`), and a request for someone else is never anonymous (422
  `beneficiary_anonymous`).
- *Where the details show.* List and search: the name. Detail and export: name, relation, and the contact / id fields
  only for the people who handle the item and the submitter. Timeline and audit trail: the kind, the user id and the
  name — never contact details. Notifications: the item's ref and title only. Logs: nothing of it.
- *Attachments* are real uploads (`org_work_attachments`): the type comes from the magic bytes, the size is capped
  (`GOV_ATTACHMENT_MAX_MB`, 10), the storage key is made by the server, files sit in private storage and are opened
  through a 10-minute link handed out after the item's own view check; older URL entries are kept only when they are
  our own signed file links.
- *Export* takes `ids=` (one item, the selected ones) next to the filters, each id checked for `workflow.export`.

## D-141 — The approval chain is a list of existing moves, not a second workflow · 2026-11-01 · accepted

**Context.** Item 6.7: a configurable chain per department (manager → council), steps editable by the org admin, every
step recording who approved or rejected, when and why; a rejection needs a reason; the requester can resubmit after
editing; the item page shows the current step and the whole history. The governance module already routes
(approval / vote), decides with a compare-and-set, escalates and reopens.
**Decision.** A chain is `Organization.settings.governance.chains[dept_id]` = ordered steps of four kinds —
`manager` (first only: the entity's head and delegates decide with the usual `decide`), `entity` (an `approval` route
to another entity), `council` (a `vote` route to the entity's Department Council), `faculty_council` — edited by the
org admin (`GET|PUT …/entities/{id}/chain`, the entity page's "Approval chain" tab). A new item snapshots its entity's
chain into `org_work_items.chain`, so changing the settings never moves items already filed. Approving a non-final step
is a compare-and-set on the item's version (the first decision still wins, the others get the lock-out notice) that
records the step and enters the next one through the existing route code; a council's close does the same for a
council step; the last step's approval, or a rejection at any step, is the existing final decision. Every rejection
— chain or not — needs a reason (422 `reason_required`, ≥ 3 characters), which reaches the requester. The requester
resubmits a rejected item (`POST …/items/{id}/resubmit`, edits allowed): the decision is cleared and a new round starts
at the first step, the earlier rounds kept in `chain.rounds`; a staff "reopen" restarts the chain the same way. No
chain configured = the single decision by the entity, exactly as before.

## D-143 — App versions from the Super Admin dashboard: the app follows the server's release row · 2026-11-02 · accepted

**Decision** (contract `docs/release/APP_RELEASES.md`; the server side is D-143 in `../back/docs/DECISIONS.md`).
- `lib/features/admin/app_releases/` draws only what the server says: the buttons come from the release's `actions`,
  "live" is `current: true` (a replaced live release shows "Replaced"), the build number is prefilled from
  `next_build_number`. Creating, publishing and rolling back ask for the account password (re-auth).
- iOS has no native build: an iOS version is a record (notes, policy, store URL) and iPhone users install the web app.
- `GET /app/version-check` answers with `download_url` / `source` / `notes`: when `download_url` is present it wins in
  `VersionCheckService` (store buttons, notes); an older server keeps the manifest rule.
- A web release reloads open tabs through `app_release_live` (`lib/core/release/web_release_watch.dart`): `must` = a
  strip with no close button, otherwise it can be closed; also offered after a rollback. Only signed-in tabs hear it
  (the event stream exists only while signed in); the others get the new build on their next load.
- Kill switch `admin.app_releases` (services hub tile, super admins only).

## D-144 — App versions through Codemagic: a channel per version, Codemagic builds everything · 2026-11-02 · accepted

**Decision** (contract `docs/release/APP_RELEASES_CODEMAGIC.md`; the server side is D-144 in `../back/docs/DECISIONS.md`).
Supersedes the build-server part of D-143: every version has a download channel, `store` (Codemagic builds it and
hands it to Google Play / App Store Connect) or `website` (Codemagic builds it and uploads the files to our server,
which keeps them in MinIO), and Codemagic runs every build. The D-143 page, statuses and actions stay.
- `codemagic.yaml` holds six workflows (`android-store`, `android-website`, `ios-store`, `web-website`,
  `linux-website`, `windows-website`); our server starts them through the Codemagic API with the `NB_*` variables.
  Android, web and iOS run on `mac_mini_m2` (Codemagic's free minutes), Linux on `linux_x2`, Windows on `windows_x2`
  (both need billing). Android website = three APKs built with `--target-platform` (same versionCode, D-137), not the
  contract's `--split-per-abi`. The Play track comes from `GOOGLE_PLAY_TRACK` (Codemagic's documented override for API
  builds), set from `NB_PLAY_TRACK` in a step.
- The New version form offers only the valid platform × channel pairs, prefills the editable settings from the
  server's defaults (workflow, Play track + package name, store link, branch; never a secret) and keeps Create OFF while
  the pair is not ready — the server's `missing` list (its own lines, the env names shown for the owner), a 400
  `channel_not_configured`, or a setup that could not be read. A value typed for this version covers what the server's
  re-check covers too (a real package name, a workflow id, a known track).
- The website channel's files are offered by `AppDownloadBanner` above every web page (sign-in included), under the
  D-143 reload strip, which keeps the top spot; one offer per device, closed per browser per version, kill switch
  `app.download_banner`. While anything is published there the D-137 "Get the app" strip steps aside (one offer).
- The applicationId stays `com.example.flutter_education_app` in phase 1: Google Play refuses it, so the
  `android:store` pair stays not ready until the owner picks a real id (a new Firebase Android client, everyone
  reinstalls); `NB_PACKAGE_NAME` is recorded, not applied to the build. Superseded by D-145 (`com.doubley.nextbrain`).

**Not verified.** No Codemagic build has run yet (no account set up): the Windows image's shell / Git bash path, the
`linux_x2` apt packages, `GOOGLE_PLAY_TRACK` being honoured, the `ios-store` signing and App Store submission.

## D-145 — One identity: NextBrain by DoubleY, com.doubley.nextbrain · 2026-11-02 · accepted

**Decision** (the owner, 2026-11-02). Users see one product name, **NextBrain**, made by **DoubleY**, and every
platform carries one application id, **`com.doubley.nextbrain`**: Android `applicationId` + `namespace`, the iOS and
macOS bundle id, the Linux GTK `APPLICATION_ID`. The iPhone app was never published, so the iOS bundle id moves too
(from `com.softkour.alfaheem`).
- **Android:** `applicationId` and `namespace` `com.doubley.nextbrain`; the Kotlin sources moved to
  `android/app/src/main/kotlin/com/doubley/nextbrain/` (package lines changed, nothing else). Every platform channel is
  `com.doubley.nextbrain/<name>` on BOTH sides (`native_recorder`, `rec_events`, `screen_share`, `notifications`,
  `radios`, `live_events`, `live_call`, `annotation_overlay`, `share_window`, `vod_media`, iOS `broadcast_state`), and
  the Android service intent actions are `com.doubley.nextbrain.<ACTION>`. The signing setup did not change.
- **iOS:** Runner `com.doubley.nextbrain`, `com.doubley.nextbrain.RunnerTests`, the screen-share extension
  `com.doubley.nextbrain.BroadcastUploadExtension`; the App Group is `group.com.doubley.nextbrain` in both entitlements,
  `RTCAppGroupIdentifier` / `RTCScreenSharingExtension` in Info.plist and `kAppGroup` in AppDelegate.swift and
  SampleHandler.swift (they must stay identical); the recording IPC Darwin names are `com.doubley.nextbrain.frame` /
  `.audioframe` / `.stop` / `.wants_changed` in AppDelegate.swift and the extension's DarwinNotificationCenter.swift.
  Display name and bundle name "NextBrain". `DEVELOPMENT_TEAM` (MVHKS8482X) unchanged.
- **macOS:** the `macos/` runner had been committed as empty files (every Xcode file 0 bytes since the first commit),
  so it was refilled from Flutter 3.47.7's `flutter create` template, then given `PRODUCT_NAME = NextBrain`,
  `PRODUCT_BUNDLE_IDENTIFIER = com.doubley.nextbrain`, the DoubleY copyright and the network-client entitlement. Never
  built (no Mac here).
- **Windows:** binary `nextbrain.exe` (`BINARY_NAME`), window title "NextBrain", Runner.rc CompanyName "DoubleY",
  ProductName / FileDescription "NextBrain", copyright DoubleY. **Linux:** `APPLICATION_ID com.doubley.nextbrain`, the
  .deb's desktop entry `com.doubley.nextbrain.desktop` with `StartupWMClass=com.doubley.nextbrain`, maintainer DoubleY.
  **Web:** `<meta name="author" content="DoubleY">` (title and manifest already said NextBrain).
- **App links:** `web/.well-known/apple-app-site-association` names `MVHKS8482X.com.doubley.nextbrain`;
  `assetlinks.json` names `com.doubley.nextbrain` with the same certificate fingerprint (the same key signs it).
- **Texts:** the About page ends with "Developed by DoubleY" / "تطوير DoubleY" (`about_developed_by`); the leftover
  ElFaheem / Al-Faheem fallbacks users could see (Remote Config default `app_name`, the sign-in brand fallback, the
  sidebar fallback, the Google role question, the Android notification channel name, the web notification title,
  two translations) say NextBrain.
- **Firebase: a NEW project, `nextbrain-2y`** (display name NextBrain, project number 647242717565). Its apps:
  `NextBrain (Android)` `1:647242717565:android:b49304b99ce6da89d69414` (com.doubley.nextbrain; the old Android
  app's SHA-1 / SHA-256 copied onto it), `NextBrain (iOS + macOS)` `1:647242717565:ios:9e1944ca9c37d70bd69414`
  (com.doubley.nextbrain: a bundle id is unique per project, so one Apple app serves both, and both
  GoogleService-Info.plist files are its config), `NextBrain (Web)` `1:647242717565:web:7c22c255a55be260d69414` and
  `NextBrain (Windows)` `1:647242717565:web:b5d10b704f2f574fd69414`. `lib/firebase_options.dart` now has android,
  ios, macos, web and windows blocks (Firebase starts on macOS and Windows too; Crashlytics is skipped on Windows /
  Linux, which it does not support); `firebase.json`'s flutterfire block and `web/firebase-messaging-sw.js` name the
  new project. The old project `elfaheem` stays as the fallback for the apps already installed (old Android
  installs keep their pushes; the backend accepts both projects during the move). Its NextBrain apps, registered
  there first (`1:520907928286:android:4806ebf35b912c5a77884f`, `1:520907928286:ios:4da3fb02e605cfe677884f`), are
  unused and harmless. Hosting (`.firebaserc`, the `hosting` block) is unchanged.
- **Owed in the new project's console:** the Web Push certificate (Cloud Messaging → Web Push certificates →
  Generate key pair) for `NotificationService.webPushVapidKey`, which still holds the old project's key; Google
  sign-in enabled under Authentication (then re-download GoogleService-Info.plist, which gains `CLIENT_ID` /
  `REVERSED_CLIENT_ID`, and add the reversed id as a URL scheme in ios/Runner/Info.plist), plus whatever else the
  old project had switched on (Remote Config, Crashlytics, the APNs key for iOS push).

**Not changed, on purpose.** The Dart package name `flutter_education_app` (pubspec `name:`): it is internal, never
shown, and renaming it rewrites every `package:` import in thousands of files and breaks every other open branch. The
signing key. Internal names users never see and that would break compatibility: the Android notification channel id
`elfaheem_main` (internal; it must match the backend, whose pushes name it), the attendance relay service id
`com.elfaheem.attendance.relay` (older app versions must still find a relay), the envelope-encryption HKDF labels
`elfaheem-envelope-*` (the server must match), the flutter-webrtc fork's `ElFaheem*` classes, the web recorder's
`_ElFaheemCompositor*` globals, and the Dart class `ElFaheemApp`.

**Consequence.** A build with the new id is a NEW app: on Android it installs next to an old
`com.example.flutter_education_app` install instead of updating it (the old one should be uninstalled; the D-137 /
D-144 update dialog of old installs points to the website download), and everyone signs in again once. The server's
`PLAY_PACKAGE_NAME` / `IOS_BUNDLE_ID` (D-144) must be set to `com.doubley.nextbrain`.

## D-146 — A free build runner on the owner's own computer; Codemagic only for the store uploads · 2026-11-03 · accepted

**Context.** The first builds through Codemagic (D-144) failed in two ways. Android → website had no keystore uploaded
to Codemagic, which is a setup gap and not a bug. Windows → website failed with "The selected instance type is not
available with the current billing plan": Codemagic's free minutes cover only its Mac machine, and Linux and Windows
need a paid plan. GitHub Actions is not an option either, because the account's jobs do not start (billing). The owner
asked for a fully free way.

**Decision** (the owner, 2026-11-03). A third executor, **`runner`**, is the default for new versions
(`APP_RELEASE_DEFAULT_EXECUTOR`, default `runner`). `tools/runner/nextbrain_runner.py` runs on a computer the owner
already has. A Windows PC builds Windows, Android and web; Linux or WSL builds Linux, Android and web. It claims a
queued version (`POST /api/v1/builder/runner/claim` with the platforms it builds), checks out the branch in its own
clone, and runs **the same workflow of `codemagic.yaml`** at that commit with the same `NB_*` variables (the upload token
included). The workflow's own last step uploads the files through the website channel's upload route. Steps are bash
(Git Bash on Windows, with `zip_shim.py` for the missing `zip`), or PowerShell for the Windows workflow. A step that
uses `sudo` is skipped: its packages are installed once by hand (README). The Android key comes from a local
`key.properties` (`NB_KEY_PROPERTIES`) and never leaves the machine.
- **One source of steps.** `codemagic.yaml` stays the only description of a build, and the runner and Codemagic run it
  alike. A workflow change needs no runner change, unless it uses a Codemagic feature the runner does not implement
  (`publishing`, `ios_signing`, `integrations`).
- **Server side** (`../back/services/app_release_runner.py`, migration 0042 `app_release_runners`). A runner release is
  a Codemagic release in everything but who builds it (`HOSTED_EXECUTORS`): channels, MinIO, publish, rollback,
  downloads and the update prompt are the same code. A claim is a conditional UPDATE on `status = 'queued'`, filtered
  by the platforms the runner declares; a runner builds one version at a time. `report` is the log and the heartbeat
  (status forward only, progress up only, below 100 until the end). `finish ok` makes the version ready (then live)
  only when the website files are complete, and otherwise fails it with `upload_missing`. A runner silent for
  `APP_BUILDER_STALE_SECONDS` fails the version with `runner_lost`. Cancel answers the runner's next call with 409,
  and the runner kills the step. Every runner shares the build agent's token (App versions › Build runner › New token).
- **Not on the runner:** the store channels (`runner_channel`). Google Play / App Store uploads stay on Codemagic,
  whose free Mac minutes cover them, and an iPhone build needs a Mac and a paid Apple account anyway.
- **Dashboard.** The form gets **Build on: My computer (free) | Codemagic**, defaulting to the server's choice. It is
  hidden for a store channel, which is always Codemagic. When no runner for the platform is on, a note says the version
  waits in the queue; Create stays on. The page shows a **Build runner** card (machines, platforms, online, busy, the
  token) and marks Codemagic "optional".

**Verified.** The backend e2e `tests/org_v2/e2e_app_releases_runner.py` passes 95 checks; the Codemagic (304), agent
(233 + 32) and claim race suites still pass; 0042 round-trips on SQLite and PostgreSQL. On this PC, against a stand-in
server: the real `web-website` workflow (clone, the bash steps, `flutter build web` in about 7 min, the zip shim, the
real `upload_artifacts.sh`) ended live. A PowerShell workflow with the Windows packaging steps and an `android_signing`
keystore ended live with the key passwords masked. A failing step reported its error and `CM_ENV` carried a variable
between steps.

**Not done.** A real Windows (`flutter build windows`) or Android build through the runner: this PC has no Visual
Studio, and the release keystore is not here. The first real ones run on the owner's PC.


## D-164 — One design engine: layout v4 (computed fields, page mode, grids, page breaks) · 2026-11-04 · accepted

**Context.** The owner's brief (session 6, "Unified design engine"): exports must pass through a design studio whose
flow is poor, large lists lack layout control, there is no logic for computed columns, and the same engine must serve
data exports, certificates, exam papers / covers, bubble sheets and the user-guide export. The audit
(`docs/design_engine/AUDIT.md` in the front repo) found one shared canvas (`lib/design/studio/`) but two document
models and two server renderers (layout v3 in mm via reportlab; certificates in 1000-unit space via Pillow).

**Decision.** The layout document becomes THE engine document, version 4 = v3 + optional keys (contract
`docs/design_engine.md` = front `docs/design_engine/ENGINE.md`): document-level **computed fields** (`calc.` keys;
cases of nested all/any condition groups → a value expression of text / number / field / concat / math; first match
wins, else a value; evaluated on the server per row before sort / group / totals, mirrored in the app for its row
preview and checked against a parity fixture), **mode `page`** (one page per item), **list columns**, cards up to 4
per line with **per_page / fill_page** (2×2, 3×3 grids), **items_per_page**, **group page breaks**, custom page sizes and
background images, ellipse / opacity / photo shapes, letter spacing / line height / shrink / shadow. The server
accepts schema 3 and 4 and keeps the version it was sent; older apps keep the unknown keys.
- Computed fields are DATA from a closed vocabulary with depth / item / text caps — never code, never `eval`.
- A computed key is not a source column: `referenced_fields` reports the source columns it reads (what the file may
  reveal), so dataset column checks still apply.
- Excel stays data-focused: page mode is refused, free-form elements are simplified with a note in the studio.
- Image values may be an export asset id or a URL on the platform's own storage (the certificate rule), never another
  host.

**Not done here.** Exam papers, covers, bubble sheets and the guide export are not migrated by this job (the exam
sessions own them); they get the API (`engine.py`, `design_engine.dart`).

## D-165 — Certificates render through the design engine; the legacy renderer stays for unsaved designs · 2026-11-04 · accepted

**Context.** Certificate designs are Pillow-rendered from `fields` / `fields_en` in a 1000-unit space. The audit found
the Arabic / English saving problems (a background regenerate committed to the stored design behind the user's back
and wiped theme keys; no save concurrency check; drafts dropped silently) and a designer that rebuilt everything per
drag frame.

**Decision.** `certificate_designs.document` (JSON, nullable) + `document_version` (migration 0045, reversible). A design
saved by the new Certificate Studio holds a v4 page-mode document (one design per language, never an implicit English
fallback) and renders through the engine (PDF, and PNG at the legacy pixel size); a design with no document renders
with the legacy renderer exactly as before, and a legacy save clears `document` — whatever saved last renders.
Saving sends `version`; a stale version answers 409 `design_conflict` instead of overwriting. The legacy designer stays
reachable behind the kill switch `certificates.engine`. `scripts/migrate_cert_designs.py` converts legacy designs
(dry run by default; writes only the new columns; rollback = `document` null). The draft endpoint no longer commits to
a stored design and merges theme keys instead of replacing them.
- Review (2026-11-04): the document save applies the legacy save's image rule to every image (stored in the design,
  the user's own upload, an allowed host, an org logo for images — never someone else's signature); a legacy save
  also moves `document_version` on, so a studio tab on the old version gets 409.

## D-240 — Results start as a draft; nothing unreviewed is ever published; the teacher picks what students see · 2026-11-04 · accepted

**Context.** The owner's grading brief (session 9): grades start as draft, the teacher reviews, then publishes;
low-confidence results are never published unreviewed; a setting for score only / + own answers / + correct answers.
The old gate refused only `high_stakes` exams, so an ordinary exam could publish with answers still queued.
**Decision.** `POST /exams/{id}/results/publish` refuses (409 `review_pending`, or `review_items_open` when a scan item
is open — both carry `open_answers` / `open_items`) for EVERY exam while any answer is queued / proposed /
needs_review / in moderation or any OMR review item is open. `{graded_only: true}` publishes and HOLDS every attempt
that still has something open, and on a high-stakes exam every attempt with an uncleared integrity flag; a held
attempt shows by itself once a person resolves it (`results_visibility.sync_attempt` / `resync` after recompute AND
after every review-item status change). `POST …/results/unpublish` (audited; refused 409 `unpublish_after_submit` on
an `after_submit` exam, whose students already saw it). `exam.settings.results_view` = `score` (default) | `answers` |
`answers_key`; answers are shown only once the exam has ended or its results are published, the key only when the
student has no attempt left; `answers_key` with `after_submit` needs an end time (422 `answers_key_needs_end`).
**Consequences.** Visibility reaches the core through `exam.attempt.finalised.results_visible` and the outbox topic
`exam.results.visibility`; a one-time resync (`grading.visibility_resync_v1`, jobs.tick) corrects rows written before
this. Notes: docs/grading/notes/BA.md, FX.md.

## D-241 — Organization paper templates: covers, mark sheets and answer tables, published by the org's teachers · 2026-11-04 · accepted

**Decision.** `omr_templates` gains `org_id` (NULL = global, D-155 unchanged) and `kind` = `bubble` | `answer_table` |
`mark_sheet` | `cover` (migration exam_0009). Org templates need no super-admin approval and every teacher of the org
(exams view) can use them; editing needs exams update; a personal-space template is its owner's only. Registration:
photograph a blank → `detect` proposes fields on the DESKEWED page (stored as the template's blank) → the teacher
confirms / draws / resizes → spec validated (unique question numbers, max > 0, no overlaps, identifier present, sum
rule) → test on one filled sheet (identifier masked) before batch scanning. A PUT makes a new version; sessions keep
theirs. Answer-table templates can be an exam's sheet (the wizard list returns them with `kind`); mark sheets and
covers cannot. Exams the system generates keep their own layout and skip registration. Notes: BD.md.

## D-242 — How a handwritten mark is read: two readers or a very sure one, and never from a misplaced box · 2026-11-04 · accepted

**Decision.** `mlkit.marksheet` (pure library): numbers by component segmentation + the digits CNN (D-157), "7.5",
"7,5", "½", "7½", Arabic-Indic digits; `ok` only when a second reader agrees above 0.95 or the digit CNN alone is above
0.993; a value above the field's max is `above_max` (a read error until a person confirms), crossed out / not a
multiple of the step is `low`. Answer rows: ink ratio per cell with the four outcomes of D-154; letter mode only with
two agreeing readers. Fail-closed alignment (round 2): a registration must keep ≥ 90 % of the reference's printed ink
within 2 px, and each field's printed lines are matched locally (± 2 % of the page): a field that moved is
`unreadable` (`misaligned`), more than 35 % moved refuses the page. A row reads `blank` only if no cell has faint ink.
**Measured** (synthetic teacher sheets, 45 per split): wrong-but-accepted 1 / 3 → **0 / 0 / 0** (seeds 1001 tune, 2002,
3003 fresh); ~38-42 % of fields to a person (most numbers: no second reader yet); answer rows ~86-88 % automatic.
No real teacher sheets measured yet. Notes: BC.md.

## D-243 — Grade review by camera ("Moraga'a"): the system compares and proposes, a person changes the grade · 2026-11-04 · accepted

**Decision.** A session = course + gradebook column + registered template (mark sheet / cover) + optional exam. The
phone only captures (quality gate synchronous: 422 with the exact reason, 409 duplicate); reading runs on the server at
low priority. Per sheet: identifier (QR > ID digits > name — a name never links by itself), every mark checked against
its max, the parts summed by the system (`paper_sum_error` when the paper's own total disagrees; the computed total is
used), scaled to the column (`paper × column_max / paper_max`, Decimal half-up to the rounding step, default 0.5 when
scaled), match when |scaled − recorded| ≤ step / 2. Three lists: match / mismatch / unreadable. Applying a correction
is a person's action through the core (`expect_old`; 409 `value_changed`; row locked; audited in `data_lab_audit` +
`manual_changes`). ONE "done" notice per pause (90 s); pages follow the scan retention unless a row is still open. The
same session in `import` mode fills marks from paper, still per person decision (bulk apply only for clean rows).
Notes: BD.md, FX.md.

## D-244 — What parents see of exam grades: a platform default, an organization override · 2026-11-04 · accepted

**Decision.** Super admin `grades.parents_see` = `always` | `when_published` (default) | `never`; an org admin may
override (`inherit` | …) through `GET/PUT /api/v1/org/orgs/{id}/grades/visibility`. The effective value gates every
parent-facing grade read (overview, child report, profile strip, alerts). `when_published` shows an Exam Engine result
only when `exam_results.results_visible` (migration 0043) is true. Notes: BB.md.

## D-245 — Cancelling a question recalculates every attempt, logged · 2026-11-04 · accepted

**Decision.** `POST /exams/{id}/questions/{qid}/void {reason, mode}`: `remove` takes the question out of score AND max,
`full_marks` gives everyone its points; restore undoes it. Stored in `exam.settings.voided_questions`; every attempt
recomputed; every changed score a grade-log row. Item analysis adds per-option shares (upper / lower group), unused
distractors and `key_suspect`; `options` stays the old counts map for installed apps, the new list is `option_stats`.
Notes: BA.md.

## D-246 — One grade log: every score change is a manual_changes row · 2026-11-04 · accepted

**Decision.** Teacher marks, bulk approve (one row per answer), appeal decisions, OMR / OCR fixes, void / restore,
recompute changes, automatic regrade (actor 0, `regrade`) and the first automatic acceptance (actor 0, `auto_accept`)
all write `manual_changes` (who, when, old, new, reason). `GET /exams/{id}/grade-log` (managers; the student is hidden
under anonymous grading). `actor_name` is null for now (the engine has no cheap name lookup). Notes: BA.md.

## D-247 — Exam notices: one outbox topic, the core delivers · 2026-11-04 · accepted

**Decision.** The engine emits `exam.notify {user_ids, kind, title / body ar + en, data (flat scalars)}`; the core
consumer writes the in-app notification, sends the push and the live event `exam_notice`, deduplicated by event id.
Kinds: `appeal_created`, `appeal_decided`, `results_published`, `batch_done` (scan batch finished),
`mark_session_done`. Notes: BB.md.

## D-248 — "Exam grading" is a model-hub task · 2026-11-04 · accepted

**Decision.** New hub role `exam_grading` (a generation model, optional, no fallback); the models list carries
`tasks: [{task: "exam_grading", roles: ["exam_grading", "nli", "embedding"]}]`. When active, the open-answer grader
asks it a yes / no per undecided criterion; it can only lower confidence (a disagreement abstains → the teacher),
never raise a score. Inactive = the previous behaviour. A library row is unique per ref, so it needs a model other
than the `generation` one. Notes: BE.md.

## D-249 — Bubble-sheet accuracy: blurry-but-placed photos and heavy erasures go to a person · 2026-11-04 · accepted

**Context.** Measured at the start of the job on the production code: real photos 15 of 21 read, 0 wrong; the old
synthetic bench (seed 1001, 224 sheets) **188 wrong of 9 900 auto-graded**, all in heavy erasures (D-163's known limit).
**Decision.** (1) A placed photo with blur between 0.75 and 1.3 mm is read with every answer to review (tier `retake`,
`photo_blurry`) instead of refused. (2) A sheet with heavy-erasure evidence (lopsided mark pairs AND erased residues
above per-sheet shares) sends every clear / multiple answer to review (`erasures`). (3) OMR wall budgets scale with
`OMR_BUDGET_SCALE` (default 1) — benches on a loaded machine must raise it. (4) A mark sheet without corner marks is
found by its table border / page edges / feature matching / QR (D-242).
**Measured.** Old bench wrong auto-grades 188 / 202 / 195 → **0 / 0 / 0** (seeds 1001 tuned, 2002, 3003); review
13.2 % → 17.2 % overall, all of it in heavy erasures (~90 % of that condition), every other condition unchanged. Real
photos: 18 of 21 read (was 15), 0 wrong; students identified by QR unchanged (7 of 21). The erasure margin is thin
(tuned on synthetic sheets; real sheets use one pen, likely easier). Notes: BE.md, BE2.md.

## D-250 — Handwritten numbers: a second, independent reader that can veto; nothing is accepted on one doubtful opinion · 2026-11-04 · accepted
The digits CNN alone accepted numbers at 0.993+; on 232 crops without a max rule it accepted 14 WRONG numbers that way
(the bench's max / sum rules caught them, real sheets do not always have them). A second reader of a different family
(PaddleOCR PP-OCRv5 English + Arabic text-line recognisers, ONNX on CPU, loaded through `mlkit.registry.resolve`;
`mlkit/marksheet/second.py`) now reads every number. `ok` needs: the same value from both readers, the second reader itself
at `second_min_conf` 0.5 or more (a line reader always emits something - a 0.05 match is no opinion, note `second_unsure`),
the CNN at `digit_pair_min` 0.7, every old rule (max, step, crossed out, alignment, faint ink, sum), AND - for any number
accepted below the old solo bar - the sum rule verified (parts and total read and adding up; `sum_unverified` otherwise,
for parts as well as the total: the independent review found a sheet without a readable total would else auto-accept
every part at the lower floor). Missing model or `MARKSHEET_SECOND_READER=off` = exactly the old behaviour; a failing read
= review. Measured (bench n=45 × seeds 1001 / 2002 / 3003): wrong-but-accepted 0 / 0 / 0 before and after; fields to a
person 38.4 / 41.1 / 42.3 % before → 39.9 / 42.6 / 44.0 % after - the reader buys SAFETY (its veto; 14 → 3 wrong on the
crop check), not automation. Cost ~50 ms CPU per number. The stray-mark tolerance ships OFF (`stray_area_frac` 0).
Limits: a missed decimal point ("4.5" → "45") is a shared blind spot (only the max rule stops it); Arabic-Indic digits are
read less well by the second reader. Fewer reviews need a better digits model trained on real teacher handwriting.
Notes: `docs/grading/notes/G1.md`.

## D-251 — Tiny printed QR codes read with the sheet's known geometry; heavy erasures get a second sheet rule · 2026-11-04 · accepted
In chat-app photos the student QR is 56–72 px (1.5–1.9 px per module) and neither OpenCV detector finds it.
`mlkit/omr/qrgrid.py` cuts it with the sheet's homography, finds the three finder patterns, samples the module grid
(unsharp mask + a self-trained linear equaliser scored on the modules the standard fixes) and hands the clean matrix to
`QRCodeDetector.decode`: Reed-Solomon still decides, the payload checks are unchanged, so a wrong student is practically
impossible. Real photos: students identified 7/21 → 11/21, wrong IDs 0 (the other 10: sheet not placed, code outside or cut
by the frame, blur). Budget `QR_GRID_BUDGET_S` 1.2 s full / 0.4 s quick × `OMR_BUDGET_SCALE`. Erasures: 78 new synthetic
erasure scenarios showed the D-249 rule never fires on pen sheets with heavy residue; a second arm (≥ 3 questions and ≥ 8 %
of them whose lighter mark is under 0.7 of the darker) cuts wrong auto-grades there 523 → 389 and keeps the old bench at 0
wrong; review on the old bench 17 → 22 % (all in its simulated `double_marks`, whose pen/pencil mix a real student does not
make). The remaining cases are lone heavy residues no bubble measurement separates (AUC ≤ 0.83): real erasure photos are
needed to go further. Switch: `erasure.strict_share` 9999 turns the arm off. Notes: `docs/grading/notes/G2.md`.

## D-252 — "Exam grading" shares the generation model by default · 2026-11-04 · accepted
A model-hub library row is unique per ref, so the generation Qwen could not also serve `exam_grading`: a second LLM would
double RAM and CPU on the CPU-only server for a ≤ 6-token yes/no check. The role now has a mode: `shared` (default when it has
no own model: the same loaded object, generation's queue and limits with the `grading` priority class), `own` (a dedicated
model, today's flow; activating one sets it) or `off`. Kept in the role's hidden `limits["_mode"]` slot, no schema change.
Shared with no generation model = off. The hub runs ONE worker by design (the models live in that process) and caches the mode 5 s, so a
change applies at once; activating a model for the role (also a roll-back) sets `own`, overriding `off` on purpose. Safety unchanged: the check never changes a score or raises a confidence, ≤ 2 per
answer, 30 / minute. `PUT /api/v1/models/roles/exam_grading/mode` (super admin, audited `set_mode`); the AI Models page shows
"Model source". Notes: `docs/grading/notes/G3.md`.

## D-253 — The grade log records who by name, at write time · 2026-11-04 · accepted
`manual_changes.actor_name` (nullable, engine migration `exam_0010`, reversible) is filled by a column default from the
request's caller (the per-request context `org_gate` already uses), only when the row's `actor_id` IS that caller; the
system actor, jobs outside a request and rows written for someone else stay null, and old rows stay null (append-only):
the app keeps its `u<id>` fallback for those. Every writer of `ManualChange` gets it without passing it. Closes review
finding 11a. Privacy: the name is kept in an append-only audit table (a grade record names who changed it);
a user erasure leaves the row with the `actor_id` and needs a DBA-run redaction. Notes: `docs/grading/notes/G3.md`.

## D-270 — A static landing site at the root; the web app moves to /app/; first-run onboarding in the apps · 2026-11-04 · accepted

**Context.** The site opened straight on the login screen, and so did a fresh install of the phone app: nothing showed
what the platform offers before asking for an account. The owner asked for a welcoming page first (a sentence-builder
search with live counts, trust numbers, how it works, features, FAQ, entry points for students, teachers and
institutions), fast and well indexed in Arabic and English, and for 2–3 onboarding screens plus a guest search in the
apps.

**Decision** (the owner's brief, 2026-11-04).
- **Landing = a separate static site** (`landing/`, Astro, no client framework, self-hosted fonts), built by
  `scripts/build_landing.sh` (Docker `node` image when the machine has no node, as on the server). `/ar/` and `/en/`
  are separate pages with hreflang, canonical, Open Graph, JSON-LD and a sitemap; `/` picks the language (saved choice,
  then the browser) and first forwards a hash route (`/#/payment/callback`, still what `FLUTTER_APP_URL` callbacks
  use) and an installed PWA started at `/` to `/app/`. Flutter web was not used for it: its first paint is a
  multi-megabyte download, which a page meant to be found and opened cold cannot afford. The page prefetches the app's
  bundle when idle, so `/app/` opens fast afterwards.
- **The web app lives under `/app/`** (`--base-href /app/` in every web build: `scripts/build_release.sh`,
  `codemagic.yaml`, the owner's `build_web.sh`). `lib/utils/web_base_path.dart` reads `<base href>`, and the start-URL
  parsers strip it, so routes stay `/c/12`, `/login`. Share links keep their root form (`/c/<id>`, `/@name`,
  `/verify/<t>`, `/live/<t>`): nginx sends a person on to `/app/…` (302, query kept) and every other unknown root path
  too, so printed certificates and old mails keep working; `.well-known/*`, `/flutter_service_worker.js`,
  `/firebase-messaging-sw.js` and `/releases/` stay at the root, and the landing ships a self-unregistering `/sw.js` for
  browsers that registered the app's worker at `/`. The served build is still the live web release
  (`/root/nextbrain/www/app` → `app_releases/web/current`), and `switch_web` refuses a build whose `<base href>` is not
  `APP_WEB_BASE_HREF` (default `/app/`, code `web_base_href_mismatch`), so a rollback to a release built for the root
  cannot blank the site. nginx: `../back/deploy/nginx/nextbrain.conf.example`; the live cutover is `deploy_landing.sh`
  in the workspace root (backup, build, swap, `nginx -t`, smoke test, automatic rollback).
- **Numbers come from three public, read-only routes** (`../back/routers/public_landing_router.py`): `stats`
  (students, teachers, courses), `options` (subjects = top-level categories, levels = their children, only those with
  public courses) and `match` (courses and distinct teachers for subject / level / mode). Counts only, cached 300 s per
  process and by `Cache-Control`. "A course" is always the anonymous catalogue (`public_catalog_filter`: published,
  not private, not archived, not a members-only organization course) — the same rule as an anonymous `GET /courses`,
  so no organization's private course is counted. There is no "level" or "center" field on a course: level is the
  sub-category, and `mode=center` means the course belongs to an organization (`OrgCourse`), `online` that it does not.
  `GET /courses` takes the same `mode` plus `with_subcategories`.
- **Apps:** a signed-out start on a phone / desktop opens the onboarding once (device-local flag), then the guest
  search (the same sentence builder, live counts) with Log in / Create account; signed-in people never see it. On the
  web the landing does the pitch, so a signed-out start stays on the login, and `/app/explore?subject=&level=&mode=&lang=`
  (the landing's button) starts guest mode with those filters.
- **Not invented:** testimonials come from `landing/src/content/testimonials.json`, empty until the owner adds real
  ones (the section is hidden while empty); the trust badges name real features only.

**Consequences.** Every web build must use `--base-href /app/`, or `switch_web` refuses it. `firebase.json` (Firebase
Hosting at its own root) was left as it is and does not match an `/app/` build; production is nginx.

**Round 2 (2026-11-04, the owner's follow-up).** Testimonials: the owner asked for them "generated with premium
touches"; they are NOT generated — invented quotes under real-looking names would mislead visitors. The section shows
real reviews students wrote (`rates.review`, course or teacher, 15+ characters) that the super admin picked and ordered
in the app's new "Landing page" screen (services hub, kill switch `admin.landing`), as "Ahmed M." + stars + course;
hidden while none is picked. The public landing routes are rate limited per visitor IP (`X-Real-IP`, the API listens
on 127.0.0.1 only), default 120 a minute (a school behind one address makes many visits), editable there (10 – 600,
or off). The desktop hero's second column is a live preview of up to 3 real public courses
(`GET /public/landing/highlights`, one request per view), an abstract drawing when it cannot load. Firebase Hosting
gets the same layout (`scripts/build_firebase_hosting.sh`: landing at /, app at /app/, share links as 302s, every other
old URL through 404.html, `PUBLIC_LANDING_API_BASE` for the landing's requests). The app builder runs
`scripts/web/postbuild.dart` like the server build. Contract: `../back/docs/landing/CONTRACT.md`.

## D-170 — The browser's history follows the app's pages; one route registry · 2026-11-04 · accepted

**Problem.** On the web, Home → page 2 → page 3 and browser Back left the site. Reproduced on a profile build against
the local stack (teacher: My courses → Add a course → Back landed on the Home tab, the next Back left to about:blank).
The root `MaterialApp`'s navigator pins Flutter's single-entry browser history (one entry; Back = one system back, else
leave), the URL changed only for named root routes, and the pages opened inside a role tab (D-081) or pushed as plain
`MaterialPageRoute`s (300+ call sites) never reached the browser at all.

**Decision.** `MaterialApp.router` around the SAME root navigator (`lib/core/routing/app_router.dart`: same
`navigatorKey`, observers, `_router`, start), so the navigator stops reporting to the engine, and
`lib/core/routing/web_history.dart` keeps one browser entry per page the person can go back to
(`AppShellNav.pageStack`: the root pages and, above a role shell, its visible tab's pages; dialogs and sheets are not
entries). App pushes / pops / replaces are mirrored by `planHistory` (pure: go back over the entries that are gone,
rewrite the top's URL on a tab switch, push the new ones), all through one queue. Browser Back runs the system back
(live room, then the navigator → the shell pops its tab, then the home tab, D-081) once per entry; a step the app
refuses is pushed again. A guard entry under the first page gives Back on the first page one more system back (the
home tab) before it leaves the site; Forward re-opens a closed page that has a URL; an entry of an earlier page load
opens its page or is skipped on the way out. Mobile is unchanged (no history; the hardware back as before; a warm app
link is pushed by name, as WidgetsApp did).
`lib/core/routing/app_routes.dart` is the ONE registry of pages with a URL: a stable id per page (also the Info
button's and the assistant's `page_id`), its path pattern (`/courses/:courseId`, `/org/:orgId`), aliases, and the URL
of a pushed route (`'/course-profile' + 12 → /courses/12`). A role home's tab is `<home>/<tab>`
(`/dashboard/my-courses`; the tab key is the DashboardItem label). Refresh / a typed URL / Forward open registry pages
over the home (`resolveWebEntry`), and a page opened signed out opens after the sign-in (`SignInReturn`).

**Rejected.** go_router / a declarative page list: a rewrite of every call site and of the tab navigators (D-081
rejected it for the same reason). The Router's own reporting (`currentConfiguration`): it can only push or replace, so
every in-app Back would ADD a browser entry (Back then walks forward again).

**Known limits.** A page pushed without a name keeps the URL of the page under it: Back / Forward step through it, but
a refresh opens the page under it. Pages get their own URL by being added to the registry and opened by name. The course
page has one wherever it opens from (`/courses/<id>`: `'/course-profile'` with the id, or `'/course-detail'` with the
`CourseModel`, read through `AppRoutes.courseIdOf`). Back on
the home tab's first page leaves the site, as on Android (the browser cannot be kept from leaving).

## D-171 — Web start-up: the splash paints first, and only the fonts of the first frame are downloaded · 2026-11-04 · accepted

**Context.** Cold on production the HTML splash painted at about 1.24 s (TTFB 0.74 s) because two classic scripts in
`<head>` blocked it, and Flutter web downloaded EVERY family of `FontManifest.json` (3.5 MB) before its first frame.

**Decision.** (1) `web/index.html`: `video_protection.js` and `recorder_compositor.js` load with `defer` (the first only
patches `createElement` for the course player's `<video>`, the second is reached by Dart when a teacher starts a
recording: neither is needed before Dart runs); the duplicated `flutter-first-frame` listener is gone; `preconnect` to
gstatic (CanvasKit). (2) `scripts/web/prune_font_manifest.dart <build/web>` (post-build, idempotent) moves PaperPlex,
bahji, tajawal, uiInter and moyasar's ReadexPro out of `assets/FontManifest.json` into `assets/LazyFontManifest.json`
(the files stay in the build); `LazyFonts` (`lib/core/display/lazy_fonts.dart`) registers them with `FontLoader` on
demand, a no-op off the web and on an unpruned build (`flutter run`, tests). Kept eager: MaterialIcons, CupertinoIcons,
uiPlexArabic (the default Arabic UI font, which draws the Latin of the Arabic UI itself) and NotoSansSC (a 59 KB file
whose NAME keeps the engine from fetching Noto Sans SC from Google for CJK glyphs).

**Rules.** The UI font of the open language is loaded by `AppFonts.start(lang)` (reads the saved language itself: the
language is applied after the `display` step) and `AppFonts.ensureLanguage` (before `LangProvider.changeLang`
switches); the other language's choice loads in the background. A screen that draws with a lazy family awaits
`LazyFonts.ensure` or sits under a `LazyFontGate` (admin filters, data lab, org report designer, the card form, the
export previews). `LazyFonts.prefetchLater` fetches whatever is left 10 s after start-up, so a forgotten screen finds it
loaded. A new family on the lazy list needs the same treatment.

**Start-up chain.** The theme request (on a first visit the first real frame waits for it) starts right after the
token store loads (`ThemeConfigProvider.prefetch`, taken by the first `load()`: still one request), and Firebase →
Remote Config run beside display / identity / language instead of after them. Same steps, same limits, same order of
effects; the start waits for the longest, not the sum. **Delivery** (front `scripts/web/postbuild.dart`, back
`deploy/nginx/nextbrain.conf.example`): the main script and its deferred parts get a content hash and an `immutable`
cache, every compressible file ≥ 1 KB a `.gz` / `.br` copy served by `gzip_static` / `brotli_static`, HTTP/2; no
dynamic gzip, so API replies are unchanged. CanvasKit stays on Google's CDN (measured a wash; `--self-host-canvaskit`
exists). No `dart:html` is left (the checkout and data-lab web files use `package:web`), so `flutter build web
--wasm` compiles; production stays on the JS build until a measured trial (the skwasm renderer, the plugins' JS
interop under wasm, and postbuild hashing / caching `main.dart.wasm` / `.mjs`).

## D-180 — One design system: the kit completed in lib/design, gradient as a touch with written rules · 2026-11-04 · accepted

**Context.** The owner: "a harmonious colour gradient touch across the whole app; many current designs are weak", and
other sessions (subscriptions, RAG, exams, organizations) build on the result. The audit
(`docs/admin/SUPER_ADMIN_AUDIT.md`) found the kit real but incomplete: tokens without an elevation, icon or full type
scale; no data table, button variants, shared search field, error state, tabs, drawer or KPI card; three search boxes,
three chip widgets, two steppers and four page-header styles in the admin pages alone; the D-136 gradient used without
a stated rule.

**Decision.** Complete the kit in `lib/design/` (additive — no existing widget changes behaviour, so other sessions'
screens are untouched until they opt in):
- tokens: `AppElevation` (0–4; dark mode adds a hairline instead of a heavier shadow), `AppIconSize`, `AppBorder`, and
  `AppType` grown to display · headline · pageTitle · section · body · bodyStrong · row · label · meta · overline ·
  figure · figureLarge (same sizes in Arabic and English, w400–w600, D-102);
- `app_gradients.dart`: the roles (`brand`, `hero`, `heroGlow`, `wash`, `strip`, `chart`) and the RULE — headers, the
  one primary action, the selected tab/pill, key chart series and one highlighted KPI; never behind text, forms, lists
  or tables, never two gradient fills side by side, never the legacy accent/teal/gold getters in new UI;
  `AppGradientSurface`, `AppAccentStrip`, `AppGradientText` (plain primary under high contrast);
- components: `AppButton` (primary/secondary/tonal/ghost/danger, busy blocks double submit), `AppIconButton`,
  `AppButtonRow`, `AppStatusBadge`/`AppCountBadge` (`AppTone`), `AppTabs`/`AppUnderlineTabs`, `AppSearchField` (350 ms),
  `AppPagination`, `AppDataTable` (controlled, server-paging friendly; a real table on wide screens, cards on phones —
  never a sideways-scrolling table on a phone), `AppErrorState`/`AppLoadingState`/`AppStateView` (a failed refresh keeps
  the data), `appErrorMessage` (never `'$e'`), `showAppDialog`, `showAppDrawer` (end-side panel, sheet on phones),
  `AppUnsavedGuard`, `AppKpiCard`/`AppKpiGrid`, `AppPageHeader`/`AppSection`. All exported by `app_kit.dart`;
  documented with examples in `lib/design/README.md`.

**Not done here.** Migrating the ~100 existing call sites of the older widgets (`PrimaryButton`, `SearchBox`,
`StatusChip`, `PremiumHero` …): each session moves its own screens when it touches them; the Super Admin pages move in
D-181.

## D-181 — The Super Admin dashboard on the design system: one page frame, a real overview, global search · 2026-11-04 · accepted

**Context.** The audit (`docs/admin/SUPER_ADMIN_AUDIT.md`) walked every Super Admin page: four header styles, the
title drawn twice (app bar + hero), a doodle background behind tables, centred spinners, failed loads shown as "no
data", `'$e'` error texts, red Activate buttons, ±1 steppers for values in the hundreds, deletes without a confirm or
with one that does not name the item, money without thousands separators, and no way to find a person, course or
payment without knowing which tab holds it.

**Decision.**
- Every pushed admin page is `AdminPage` (`lib/features/admin/admin_page.dart`): `AppPageHeader` once (title, ONE
  primary action, secondary actions, Refresh with "Updated …"), `AppUnsavedGuard` through `dirty:`, a readable max
  width, no doodle background. A shell tab registers its reload through `AdminRefreshScope.register`, so the shell's
  Refresh reloads data instead of re-creating the page.
- Records are `AppDataTable` (a table on wide screens, cards on phones, search / filter / sort / load-more); settings
  are `AppSection` + `AppCard` groups with typed number fields next to any stepper; loading is a skeleton, a failed
  load is `AppErrorState` with the server's text and Retry, a failed refresh keeps the data.
- Overview: a greeting, the global search field, six KPIs (revenue 30 days is the one highlighted card), ONE "Needs
  your attention" list whose rows deep-link, then charts, health and shortcuts.
- Global search: `GET /api/v1/admin/search?q=&limit=` (backend `routers/admin_search_router.py`, admin-only; the
  admins group is super-admin only; capped per group) plus the pages the viewer can open, in a command palette
  (Ctrl+K or "/", a full sheet on phones) — `admin_global_search.dart`.
- Hub tiles carry the brand tint only (no colour per service); labels renamed where the audit found them wrong
  (Flags → "Student review & read flags", Terms → "About & terms", Requirements, Send message).
- One money formatter, `money()` in `admin_common.dart` (thousands separators); amounts typed with Arabic digits or
  "2,5" parse (`parseAmountLoose`).

**Consolidated, nothing lost.** The owner asked for best practice ("premium and smart"): the duplicated entry points the
audit found (R1–R8) were folded into one home each — one Fees page (Rates · Policy), one App versions page (Build &
publish · Update prompt, each tab with its old role and kill-switch rules), one Parent linking page (Requests ·
Settings), the Feature guide shows the app switch read-only and links to Features, the View-as and Teachers hub tiles
went (their paths are the user rows, the Teachers tab and the search palette), and the Overview's hubs block became
"Recently opened" (`AdminRecents`, per user, on this device; the palette shows the same as Recent). Every call, field,
kill switch and role check of the old screens is kept, and the old page classes still open for any caller. Screens owned by other sessions (courses ↔ students, RAG, exams and the grading
feedback store, organization flow) were not redesigned.

## D-210 — One course-access rule, expiry enforced, an organization's charge stops at its own courses · 2026-11-04 · accepted

**Context.** A student who paid for a six-month plan was told to "subscribe" again. The investigation (fix/subscriptions,
Phase 1) found no expired or overwritten plan on the server: every six-month purchase of 20–29 Oct was active with the
full 180 days. What it found instead: at least eight places decided course access on their own, all from
`enrollments.status` and none from `expires_at` (an expired plan kept full access); an admin could drop a paid
enrollment with no reason and no trace (student 228, course 9); the app told enrolled students whose next session was
locked by progress to "complete the current session or subscribe"; and an organization with unset billing (the rule of
2026-10-30) would 402 its student members on every call, including the courses they bought themselves.

**Decision.**
- `services/course_access.py` (`get_course_access` / `_many`) is the only rule. Order: staff → organization charge →
  enrollment (ACTIVE / COMPLETED and now < `expires_at`; the expiry instant is expired) → pending / failed / refunded
  payments. It returns `{has_access, reason, source, subscription_id, payment_id, plan, starts_at, expires_at, days_left,
  status, flags}`; every course payload carries it as `access`, and `is_enrolled` means `access.reason == "enrolled"`.
- Expiry is enforced. The app says "your plan ended on …, renew", never "subscribe", to someone who paid.
- A course bought in the personal account stays open whatever an organization charges. An organization's account charge
  gates only that organization's courses (402 `SUBSCRIPTION_REQUIRED`, reason `org_subscription_required`); the global
  guard keeps 402-ing the whole app only for the platform-wide switch.
- Every completed payment gets a plan (inferred from the price paid; the legacy single price was the yearly one). An
  inferred end date in the past or within 14 days becomes now + 14 days, so nobody loses access on the day of the backfill.
- Denied requests are refused with their exact reason: 403 `course_access_denied` + `reason`, logged as an
  `access_denied` event (one per user, course and reason every 10 minutes).

## D-211 — `subscription_events`: an append-only history of access and money state · 2026-11-04 · accepted

One row per change (created, payment_succeeded, payment_failed, activated, renewed, expired, cancelled, refunded,
admin_extended, admin_reactivated, admin_granted, plan_backfilled, access_denied), with the actor (system / admin /
user / webhook), the reason and a before / after snapshot, written in the same transaction as the change.
PostgreSQL refuses UPDATE and DELETE with a trigger and the app role loses those rights (the ledger's pattern, D-025).
The past is backfilled once from payments, enrollments and platform subscriptions (`backfilled = true`, original times).
Two types beyond the brief: `admin_granted` (access with no payment) and `plan_backfilled` (D-210's backfill).

## D-212 — The Super Admin's Courses ↔ Students console · 2026-11-04 · accepted

`/api/v1/admin/course-students/…` (super admin only; kill switch `admin.course_students`) and
`lib/features/admin/course_students/`: courses with active / expiring / expired students, revenue and issues; each
course's full roster with a status badge and the inconsistencies (paid without access, access without payment); a
student drawer whose first block is the live access diagnostic per course, then the subscriptions, payments and the
event timeline. Students are found by academic ID, national ID (shown masked), e-mail, phone or @username. Extend,
reactivate, grant and cancel each need a reason and write one event plus a notification to the student. The older admin
enroll / unenroll / re-subscribe calls keep working and now write events too.

## D-260 — Course delete is a soft delete; the super admin restores or deletes for good · 2026-11-04 · accepted

**Context.** A course delete erased the course and everything under it when it had no payments (a teacher's mistake
was final), and archived it when it had (D-025). The owner asked for a soft delete everywhere, with the platform's
super admin deciding whether a course is deleted permanently. **Decision.** Every course delete (teacher
`DELETE /api/v1/courses/{id}`, admin `DELETE /api/v1/admin/courses/{id}`) only archives the course
(`courses.archived_at`, the flag every query already honours), drops its enrollments and removes its favourites;
`course_deletions` (migration 0046, back `data/course_trash_models.py`) remembers each enrollment's old status, the
favourites, the published flag, who deleted it and why. The super admin's trash (`/api/v1/admin/course-trash`, app:
Admin services → Deleted courses, kill switch `admin.course_trash`) restores a course exactly as it was (each
enrollment back to its old status unless it changed since; an expired plan stays expired) or deletes it permanently
after a reason and the typed course id. A permanent delete never removes money or certificate records: when payments,
earnings or issued certificates point at the course, the row stays as a tombstone (state `purged`: name, teacher,
price, enrollments and every money row kept, content and files removed); otherwise everything is erased (`erased`).
What hangs from a course is read from the models' foreign keys, so a new table is covered without a code change, and
a money row found deeper stops the delete (409 `purge_blocked`, nothing removed). Access: a course in the trash
answers `course_deleted` to everyone but the platform staff, its teacher included. Every change writes
`subscription_events` (`cancelled` / `admin_reactivated`, meta `by`). **Consequence.** Nothing a teacher or an admin
does can erase a course. Courses archived before this (no `course_deletions` row) show as "legacy": a restore brings
the course back but not its students (their old status was never recorded; Courses & students can reactivate them).
An organization's DELETE `/orgs/{id}/courses/{cid}` is unchanged: it unlinks the course from the organization and
never deleted the course. Files are removed after the commit and only when no other row still uses the same URL; the
RAG documents of a course are not touched.

## D-280 — Tenant isolation in the organization modules is checked by the application, object by object · 2026-11-04 · accepted

**Problem.** The org-flow audit (2026-11-04, `feat/organizations-flow`) found routes that loaded an object by id and
never compared it with the organization in the path: an advisor could run any registrar action through an advisee's
decision, `GET …/access/users/{uid}` returned any platform user's e-mail and phone, a course archive and extra-session
rooms of another organization were readable, members-only courses could be bought by strangers. PostgreSQL RLS
(migration 0003) separates whole organization TREES only, so siblings, a parent and its children are separated by the
application alone, and no test sent organization B's ids through organization A's routes.

**Decision.** Every org route compares what it loads by id or receives in the body with `ctx.org` (or the allowed
subtree) and answers 404 / 422 `foreign_reference` otherwise; member routes need `live_member()` in an approved
organization; advisors may only accept / reject / edit within the decision's own options and students. Each fix has a
test that fails without it (`tests/org_v2/e2e_of_b1_*` … `e2e_of_b6_*`: two organizations, B's ids through A's routes,
B's rows unchanged, plus the legitimate path).

## D-281 — Shared system roles are copied on write by a sub-organization · 2026-11-04 · accepted

System roles (teacher, student, …) are stored on the ROOT organization. Platform admins and the root's own admin edit
them in place; a faculty admin who edits one gets a copy with the same key in their own organization, and the
assignments in that organization and below move to the copy, so the university and the sibling faculties keep the
original. A later edit through the original id lands on the existing copy (`_role()` resolves the nearest copy);
`copy_on_write` on the role tells the app a copy will be made. Rejected: editing in place (one faculty changed every
faculty's rights) and read-only system roles (the owner wants organization admins to manage their roles).

## D-282 — An organization admin suspends the membership, never the account; the admin seat is handed over · 2026-11-04 · accepted

`PUT …/members/{mid} {is_active}` sets the membership `suspended` / `active` (re-activation needs `requests.approve`);
`User.is_active` belongs to the platform. Department staff / head seats need the rights they hand out
(`assert_can_grant`) and nobody appoints themselves. The admin seat moves with `POST /api/v1/org/orgs/{id}/transfer-admin`
(the organization's own admin) or `POST /api/v1/admin/orgs/{id}/transfer-admin` (platform admins), one shared helper:
the old admin stays as administrative staff or leaves; leaving ENDS the membership (status `removed`, `ended_at`),
the role assignments (`valid_to`) and grants (`expires_at`) rather than deleting them, so the history stays (only the
department seat, which has no end date, is removed). The new admin's global account role is unchanged; they reach the dashboard
through the context switcher (D-286).

## D-283 — Organization invitations by e-mail or phone, and join links · 2026-11-04 · accepted

Table `org_invitations` (migration 0048, RLS like 0003, reversible). Only the sha256 of the link token is stored, so a
resend issues a new link and the old one stops working. Inviting needs the insert right of the invited role (students /
teachers / staff). The invitation page `https://nextbrain.site/i/<token>` opens signed out; accepting or declining
needs a signed-in account whose VERIFIED e-mail / phone equals the contact. There is no SMS provider: a phone invitation
is found by the invitee in `GET /org/public/me/invitations` (and an in-app notice when the account exists) and staff share
the link. `https://nextbrain.site/j/<CODE>` opens the join-by-code flow with the code filled, kept through sign-in.
Accepting places the person directly (no department join policy: the organization chose them). Parents cannot join an
organization (403 `role_cannot_join`); they follow their child's organization instead (D-287).

## D-284 — Printed legacy join codes live in `org_join_codes` · 2026-11-04 · accepted

`Organization.join_code` was a second code system next to `org_join_codes` (keyed hashes, one unit per code). Lookups
now read only `org_join_codes`; each organization's legacy code is copied there idempotently
(`join_service.sync_legacy_codes`): every organization once at start-up (owner engine), one organization when it is
created or its code regenerated, and on a lookup miss at most once per 5 minutes per process — not by an Alembic data
migration, because the hash is keyed with `SECRET_KEY` and codes written after deploy (organization creation, the old
regenerate route kept for installed apps) must be copied too. Inside an `org_ctx` session only that organization is
synced (RLS forbids writing another tree's rows). `OrgInvitation` stays in the frozen `ensure_org_tables` list on
purpose: the e2e harness runs `create_all` before `org_models` is imported, so without it the table is missing there.
Codes on posters keep working; regenerating through the old route retires the old code at once. The column stays.

## D-285 — Org file links expire; reports are shared with members only; members-only courses are enforced · 2026-11-04 · accepted

`/org/files/{token}` tokens carry a signed expiry (7 days); tokens without one work until `org_files.legacy_until`
(deploy + 30 days), then 410 `link_expired`. A link STORED in the data (materials, term files, attachments, report files,
form answers) is a durable reference: every API that returns it mints a fresh 7-day link (`file_links.fresh`), so only a
link copied out of the app expires; with no `SECRET_KEY` nothing is signed (503 `links_unavailable`, never the
old literal key). `POST …/reports/share` goes only to live members of the sharing organization or admins of
organizations that consented to share with it (422 `share_target_not_allowed`; no free e-mail addresses; 20 per hour).
A `members_only` organization course is enforced in `course_access.py` (D-210's one rule) on enroll and in
`PaymentService.assert_can_purchase` (every payment path): 403 `members_only`.

## D-286 — One rule for where an organization opens, and switching clears the previous one · 2026-11-04 · accepted

`AppModeController.opensDashboard`: any non-student membership or management right opens `/org_dashboard` (D-103), a
student membership opens the member home — in the switcher, notification / link taps, and the start-up overview alike.
Switching from organization A to B closes A's pages and clears its timezone, feature offs and attention focus before
B is selected in both `AppModeController` and `OrgSession` (a notification for B used to leave the dashboard on A).
A remembered organization that disappears is replaced with a notice naming both; a failed `/org/mine` keeps the last
list with Retry instead of looking like "no organizations". The admin home's More page carries the switcher too.

## D-287 — Parents follow their child's organization; organization admins see setup and billing; soft delete · 2026-11-04 · accepted

- Parent view (`/api/v1/org/parent/children[/{sid}/orgs/{org_id}]`, kill switch `parent.org_view`): read-only, computed
  AS the child (today, next 7 days with one-date changes, announcements the child received, approved grades,
  attendance), only for an active parent link and a live member child; never another student's row.
- First-run checklist (`…/setup`, kill switch `org.setup_checklist`) and a read-only billing page (`…/billing`, kill
  switch `org.billing_view`) for organization admins; `notice: unset_yearly_default` says plainly when nobody configured
  billing and students are asked for the platform's yearly plan on the organization's own courses (D-210).
- Platform admins edit an organization, delete it SOFTLY (status `deleted`, data kept, typed name + reason; 409
  `has_children` while it has live sub-organizations) and restore it.

## D-288 — An organization never attaches an existing account: the person accepts an invitation · 2026-11-05 · accepted

**Problem.** Adding a member by e-mail (one person or an Excel sheet) attached any EXISTING account to the
organization without the person agreeing (review finding F6). **Decision (owner, 2026-11-05):** bulk Excel import stays;
an existing account gets a pending invitation (`org_invitations` with `target_user_id`, `member_spec`, `source`
`manual` / `excel`, migration 0048) and sees it in the app as a notification and a dialog (Accept / Reject / Later,
`lib/features/org/org_invitation_prompt.dart`, kill switch `org.invitations`). Accepting applies exactly what the admin
entered (role, student code, window, profile, department seat, assistant permissions). Rejecting notifies the inviter
and blocks re-inviting from the same organization for 7 days. An account the organization creates right there (no
account for that e-mail yet) still joins at once with a generated password. The "create a manager here" forms refuse
an existing account's e-mail (`existing_account_invite_first`): invite first, pick after the accept. Applies to every
org role; parents never get one (D-287). **Cost.** The dialog adds no request while the attention item
`org_invitations` is 0, so the home request budgets do not move. Backend tests that used `POST /members` only as set-up
accept through the shim `tests/org_v2/_c7_compat.py`; `e2e_of_f6_consent.py` tests the real flow.

## D-289 — Academic Advising is a module per organization membership, built on governance, the registrar and the calendar · 2026-11-05 · accepted

**Problem.** Faculties need full academic advising (advisor assignment, caseloads, student 360, flags, notes,
appointments, early warning, council escalation, analytics). The platform had only `OrgStudentAcademic.advisor_id`
(one advisor, no history) and the registrar's advisee list. **Decision.** A new module (`adv_*` tables, migration 0050,
`services/organization/advising/`, `lib/features/org/advising/`, kill switch `org.advising`, plan
`docs/advising/PLAN.md`):
- Every advising row hangs on the student's MEMBERSHIP (`org_members.id`) plus `org_id`, never on the global user: a
  student in a faculty and a learning center has two separate advising records. Postgres RLS on every table.
- Only `university` / `faculty` organizations and their sub-organizations can switch it on (`ADVISING_ORG_TYPES`);
  others get 403 `advising_not_available`.
- Assignments get their own history table (`adv_assignments`, one active primary per membership by a partial unique
  index); `advisor_id` stays as a mirror of the primary so the registrar's advisor routes and `advisor_decide` keep
  working. Existing advisors are imported as locked `legacy` assignments, never overwritten by auto-distribution.
- No second workflow engine: support requests, council escalation and referrals are governance work items, with one
  new chain step `student_department_council`. No new term entity: `OrgTerm`. Appointments mirror into `CalMeeting`.
  Exports and scheduled reports are Export Studio datasets.
- One priority scale (low · normal · high · urgent) for flags, alerts, threads and requests.
- The Advising Director is the head of the `academic_advising` department or a holder of the system role
  `advising_director`; org admins hold every director right.
- An optional midterm mark per registration (`interim_percent`) feeds the early-warning "failing midterm" rule.
**Cost.** One pre-computed row per student (`adv_student_stats`) must be kept in step by every advising write and a
claimed job; that is what keeps advisor lists and director counts fast at 100 k students per organization.

## D-290 — Connected detail views: one scoped entities API, enrollment history on the enrollment row · 2026-11-05 · accepted

**Problem.** Every list (admin students / courses / teachers / categories, the teacher's students, the student's
courses, the org's people) opened its own one-off sheet or page, nothing linked to anything else, and the data a
student's story needs (when they first came, were last active, finished, withdrew and why) was not stored. **Decision
(owner-approved plan, 2026-11-05):** ONE scoped router, `/api/v1/entities/{students|courses|teachers|categories}/{id}`
plus paged sub-lists and a per-course timeline (`../back/docs/master_detail/CONTRACT.md`), serves every role; the server
decides what a viewer may see (out of scope = 404, never 403) and lists the `sections` the app may open, so the app has
one master-detail framework configured per entity, never a copy per role. The history lives on `enrollments`
(migration 0051: first / last activity, completed_at, withdrawn_at + reason code + text, two indexes, idempotent
backfill from views, completions, video views and `cancelled` events). Status-driven stamps sit in ONE SQLAlchemy
listener on `Enrollment.status`, so the ten paths that drop, reactivate or complete an enrollment (payments,
registrar, imports, consoles, org runs, the trash) cannot forget them; `services/enrollment_history.py` adds the reason
code and the throttled activity stamps (one indexed UPDATE, at most one write per 10 minutes). **Deliberate
deviations.** "Liked" is the existing Favorite, not a new like model; the timeline is composed on read from the
existing tables (no new event table); no background statistics job until a benchmark asks for one; organization staff
scope arrives with the org rollout (phase 7) and gets 403 `entity_forbidden` until then.

## D-291 — Google Forms import picks the form with the Google Picker · 2026-11-07 · accepted

A teacher imports a draft exam's questions from a Google Form. The form is chosen in the Google Picker, opened in the
system browser from a server page, not from a list inside the app. `forms.get` accepts `drive.file`, the non-sensitive
scope the drive connection already has, and `drive.file` covers what a user picks; listing someone's forms ourselves
needs `drive.metadata.readonly`, a restricted scope with Google's verification and a security assessment. So existing
connections keep working with no new consent. The cost is one more browser step, and a web API key
(`GOOGLE_PICKER_API_KEY`) with the Forms and Picker APIs enabled on the project.

The core reads the form because it holds the Google token; the Exam Engine imports the rows because it owns the exam,
through the Excel import's row checks. What has no engine type (scale, date, time) is reported, never dropped silently.
A choice question without a correct answer is refused by row, and the preview says so first. Images are not copied,
because a Forms image URL expires. Forms' responses are not imported.

## D-300 — All exams page + "Import from Google Forms" as a way to start a new exam · 2026-11-08 · accepted

A teacher (or an organization's staff) saw exams only course by course (the course exam hub), so there was no answer to
"what are all my exams, and which drafts are waiting?". `AllExamsScreen` (`exam_all_screen.dart`, pure part
`exam_all.dart`) lists every Exam Engine exam the person manages: personal ones, the organizations where they hold exam
rights, and the courses they teach. It is ONE engine call, `GET /api/v1/exam/exams/mine?org_ids=&course_ids=`, because
per-space lists cost one call per organization plus one per course taught in an organization without org-wide rights.
The engine does not know a person's organizations or courses, so the app sends them (from `/org/public/me/overview`,
already loaded, and `/my-courses`); the engine re-checks every space with the core and leaves out what it refuses,
never failing the page. Course names come from `/my-courses`, plus one page of `/org/orgs/{id}/courses` only for
organizations with exams in courses the person does not teach. An older engine (422 / bare 404 on `/exams/mine`) gets
the per-space lists, with a banner saying what may be missing. Trade-off: the list is capped at 300 exams (newest
first) and filtered in the app; a person with more needs server paging later. Search, status tabs (All without the
archive, Draft, Published, Closed, Archived), course and type (online / paper / exam file) filters; cards on a phone,
a dense table from 900 px. Quick actions: publish a draft, results, printable paper, edit. Kill switch `exam.all_exams`.
Opened from the teacher analytics header and pass-rate tile, and from the course exam hub's hero.

"Import from Google Forms" (D-291) was only a button inside an existing draft's editor. It is now also the fourth way to
start in the quick builder's chooser: pick the form first, see the preview, then "Create the exam" makes the draft
(named after the form, online, in the builder's course / organization / timetable slot) and imports the rows; a clean
import goes straight to the editor, one with refused rows shows the report first. The draft is made only after the pick,
so backing out of the picker leaves nothing behind. The option follows `exam.google_forms_import` (hidden while the
server lacks `GOOGLE_PICKER_API_KEY`).

## D-301 — Exam generation is a background job the teacher never waits on blindly; the Super Admin switches the automatic exam tools · 2026-11-08 · accepted

**Why.** "Create automatic exam takes a long time, then shows try later" had four causes: (1) the wizard waited a fixed
10 minutes and then dropped the job id with "still being written — try again shortly", while the run went on and a new
attempt answered 409 `exam_gen_busy` until it ended; the questions already written were thrown away; (2) production
writes every question with the exam model (qwen3:8b on CPU, ~235 s a question measured in D-198) plus a second model
call that checks it, and retries up to three times; (3) a slot's retries could outlive the 600 s job lease (lease
renewed only between slots), so a slow slot could restart the job; (4) a timed-out wait looked like a server error.

**Decision.** The job (`/rag/exam-gen`, already a resumable worker job) is followed, not awaited: the Generate step shows
waiting / writing / done / stopped / failed, N / M ready with the time left (the run's own pace), the questions as they
arrive, and "Add the N ready now" (stops the rest), Stop, "Keep it running" (leave; opening the generator again for the
course resumes it via `GET /exam-gen?course_id=`), Try again. `speed` fast (default: the hub's chat model, rules-only
checks, two attempts) | quality (the exam model + the support check). The exam's own questions are sent as
`avoid_prompts` and never written again; the focus text retrieves the matching passages (cached); a course with nothing
indexed can be written from a topic (`topic_only` warning, never without a model). `RAG_EXAMGEN_PARALLEL` writes the next
slots' first attempts at once for a model server that decodes several sequences (default 1: the CPU Ollama does not
gain). Kill switches `exam.auto_create` and `exam.auto_correct`: hidden in the app and refused by the services (403
`feature_disabled`) through the core's `GET /internal/v1/features/{key}`, off only when off on every platform, failing
open when the core cannot answer (a switch, not an access rule).

**Trade-offs.** Fast is the default although the owner chose qwen3:8b for exams (D-198): the teacher can still pick Best
quality per run, and the rules (answer in the passage, distinct options, de-dup) apply to both. Measured locally on CPU
(3 questions, cold): fast 316 s, quality 468 s — CPU decoding stays the floor; the real cure is that nobody has to sit
through it. "Add the N ready now" stops the job rather than leaving it running, so a model is never busy for questions
nobody will take.

## D-302 — Own sheets: template-free bubble sheets and written answer tables · 2026-11-08 · accepted

Teachers already own bubble sheets from other publishers and often run quizzes on a ruled table ("question | answer
number"). Teaching the platform a sheet (D-155) needs corner marks, a blank AND a filled copy, numbers typed in and a
super admin's approval; that is the right bar for GLOBAL sheets, too heavy for a teacher's own paper. So a second,
lighter path: one photo / scan / PDF → `POST /omr/auto-templates/detect` finds the layout with no marks at all
(`mlkit/omr/autolayout.py`: bubble-shaped contours of the dominant size, circles or rectangles, grouped into lattices
by their own gaps, a 10-tall block = the shaded ID, QR / barcode noted; `mlkit/omr/written_table.py`: the ruling's
cells, the question column by its printed numbers) → the teacher confirms it once on the picture (block roles,
numbering left / right first, down / across, start number; numbers or letters, options) → it is saved as the
teacher's (or the organization's) template, published at once like D-241's answer tables, never global.

Reading follows "never guess": a page is placed by laying the layout's bubbles on the page's own bubbles (iterative
closest point + RANSAC homography, 0 / 180°, a coarse ink fingerprint picks the way up and refuses another sheet);
every question whose bubbles do not sit on printed bubbles goes to review; fills are calibrated on the sheet itself
(its blank and shaded levels); a written cell is accepted only as a digit the CNN and the PP-OCR reader agree on (or
the CNN alone at its strict threshold) or a confident letter, and only when it is one of the options. Digits and
letters are the teacher's choice per sheet, never mixed: an Arabic ٢ reads as "C" to a letter reader. Corner marks
are deliberately NOT used on foreign sheets: four shaded square bubbles near the corners look exactly like them.

Trade-offs: the synthetic bench (`back bench/omr/auto_synth.py`, numbers in `back/bench/omr/AUTO.md`) has no real
student photos; written tables send more cells to review than bubbles (handwriting), which is the price of no wrong
grades; the live camera scanner and printing stay NextBrain-sheet features (hidden for own sheets: upload photos /
PDFs instead); a touching-cells strip (|A|B|C|D| boxes sharing borders) and options printed vertically are not
detected yet. The Super Admin's `exam.auto_correct` switch (read by the engine through the core's new
`GET /internal/v1/features/{key}`) turns detection and reading of own sheets off; NextBrain's own sheets keep working
exactly as before.

## D-303 — The teacher's automatic to-do list · 2026-11-08 · accepted

**What.** `GET /api/v1/me/todo` (core) derives a teacher's to-do from live data — ungraded submissions, transfer
receipts, open course complaints, lessons of the last 14 days without attendance / material, live runs whose
recording never arrived, students at risk (inactive 14 days · missed most tracked lessons · failing or falling core
exam scores), calendar clashes in the next 7 days, quiet courses, low-engagement lessons (one item per course) — and
`GET /api/v1/exam/me/todo` adds the Exam Engine's queues (answers to decide, appeals, scanned-sheet questions) in the
same item shape. Every item carries its evidence (`why`), a priority from a 0–100 score, a deep link and a
fingerprint `fp`. Home: a "Your to-do" card (top 3 from the ONE `/me/home` call, `todo` block) that takes over the
Needs-you pills it covers; a full page with priority tiles, group filters, Done / Snooze / Dismiss (+ Undo) and the
hidden list with Restore. Badge: attention tab `teacher.todo` = the high-priority items, on the teacher's Home tab.
Kill switch `teacher_home.todo`.

**Why this way.** Nothing is stored except the teacher's choices: one `app_settings` row per teacher
(`teacher_todo:<id>`, no migration); a done / dismissed item returns only when its fingerprint (the evidence) changes,
a snoozed one after its date. The list is computed over ALL the teacher's courses once and cached 60 s in-process; a
scope (personal / org, like `/me/home`) is a filter over it, and `/me/home` hands its calendar events to the clash
check and the badge, so the home costs no new request (budgets unchanged). The busy-teacher run (12 courses × 150
students × 12 lessons, SQLite, cache off) answers in ~270 ms.

**Trade-offs.** The core cannot read the engine's schema, so the home card and the badge do not include exam review
items — they appear on the full page (the app merges the engine's list and applies the core's states to it). The
cache is per worker (another worker may show an item up to 60 s after it was fixed; the teacher's own choices clear
it). "At risk" uses the core exams only, and treats an enrollment without an activity stamp as unknown, not inactive.
Org staff whose home is the organization dashboard have no entry yet (the API serves them; the teacher
home's Organization mode shows the card).

## D-304 — Page widths are roles, measured against the room the page has · 2026-11-08 · accepted

Pages chose their width by pixel: `BasePage(useWebCard: true, maxWith: 900)` and friends, measured against the WINDOW.
Between 900 and 1100 px every card was a fixed 650 px whatever it asked for (a 1360 sessions page and a 1440 laptop
with the sidebar open both got 650), pages without a number got 900 on a 1920 screen (the teacher's and the student's
analytics, the teacher's student list, the student's record), and admin settings forms stretched to 1200 with the
value 900 px away from its label. **Decision.** Five page-width roles in `app_tokens.dart`, `AppWidth.form` 600 ·
`reading` 860 (= `Breakpoints.contentMax`) · `content` 1120 · `wide` 1440 · `full`, with `inside(available)` = the role's
max, never wider than the room less the existing `AppSpace.gutter` each side. `BasePage` measures the card with a
LayoutBuilder (the room a shell's sidebar or rail leaves), takes `width:` (a role, wins) or the old `maxWith` (kept, so
nothing that names its own width changes), and defaults to `content`. `AdminPage(width:)` and `AppWidthBox` apply the
same roles to other bodies; `Helpers.calculateRemainingWidth` now answers from the roles. Every page that had no width
got an explicit role; settings forms in the Super Admin's hubs take `reading`. **Trade-offs.** Pages that named a
pixel width keep it (other tracks own those screens; they move to a role when next touched). Phones (< 600) are
unchanged: no card, the page pads itself. Dialog widths are not themed: a theme cap would also cut the deliberately
wide dialogs (designer previews at 980), so a runaway AlertDialog still needs its own constraint.

## D-305 — Parent home: "How is my child doing?" + Message the teacher · 2026-11-08 · accepted

The parent's Today tab listed every child as one dense card of raw figures; it said little about whether a child was fine and offered nothing to do about it. The ONE `GET /parent/overview` call now carries a `pulse` per child (server `services/parent_pulse_service.py`): a status word (on track · keep an eye · needs you · quiet), the last 7 days (attendance, missed sessions and homework), 6-week attendance and grade lines, the average against the class average and the 4 weeks before, subjects marked strength / needs focus, the next 7 days, the roadmap, and at most 4 plain-language findings each with ONE action (message the teacher · open the report · alerts). The home draws a child switcher and that child's picture (`parent_pulse_widgets.dart`, `HomeDashboard`: main = hero, findings, this week; side = subjects, learning path, latest marks). New: `POST /parent/children/{id}/message-teacher` — a short note delivered as the teacher's notification + push; the parent's phone only when they turn it on; 3 per teacher a day.

Why / trade-offs: no extra request on open (the home budget stays 4; the server reads the child's calendar once for today + 7 days instead of today only). Class averages are aggregates of exams with at least 5 results, never a person, and follow D-244 grade visibility. Windows are rolling (last 7 / 28 days), not calendar weeks, so Saturday morning is never "empty". The message is one-way (no thread model exists; the teacher answers by phone or through the school) — a real parent ↔ teacher conversation is future work. No migration (Notification rows, rate limit counted from them). Kill switches `parent.insights` (pulse off → the old per-child cards, kept) and `parent.message_teacher`. Teacher notes / feedback to parents are not shown: there is no such data yet.

## D-306 — Free meetings: recording stopped at start, the whole room in the recording, full-screen board · 2026-11-08 · accepted

**Recording stopped at start.** A meeting (Meet now or a calendar meeting, never tied to a course session) opens with
the recording stopped, whoever opens it; its creator presses Record (top row) and is told so once when the room
opens. This was already true in practice (meetings join with `isTeacher: false` and the server sends
`recording_enabled: false`), now it is one pure rule, `liveRecordsAtStart` (live_recording_layout.dart), that the
room's `_deviceRecords` reads. Course sessions keep recording on the teacher's device at the start (D-098): a
different code path, unchanged. The Record sheet now says what the recording holds.

**The whole room in one video.** The device that records composes it; how depends on the platform:
* Web: the compositor (web/recorder_compositor.js) used to draw this browser's camera and its own share only. Now the
  room sends a layout (`recordingLayout`: the stage — whiteboard or shared screen — letterboxed with up to 4 camera
  thumbnails on the end side, else the cameras that are on in a 1 / 2 / 2×2 / 3×2 / 3×3 grid with "+N", names and a
  ring on the speaker) and the sources it names: remote cameras and screens are the LiveKit tracks the room already
  receives (wrapped, never stopped), the whiteboard is re-rendered into a canvas at 2 fps while it changes. Every
  remote voice is mixed by audio TRACK (a shared screen's sound no longer replaces its sharer's voice), including
  the ones already in the room when Record is pressed mid-meeting (they were missed).
* Android: the recording is the room UI itself (D-110 native copy of the Flutter surface; whole-screen
  MediaProjection while this phone shares), so cameras, board and shares are in it as seen. Fixed: that copy was
  gated on `isTeacher`, so a meeting creator's Android recording showed the native placeholder card. Audio: the
  microphone plus, new, the other people's voices — `RemoteAudioMix.kt` taps WebRTC's played-out audio (the fork's
  PlaybackSamplesReadyCallback, reached by reflection) and mixes it into the recorder's PCM; without the hook the
  recording stays microphone-only.
* iOS: RPScreenRecorder records the app's screen (everything visible) with the LiveKit microphone tap; the other
  people's voices are NOT mixed (no playout tap on iOS yet; it needs native work on a Mac).
* Desktop (Windows / macOS / Linux): no device recorder at all (unchanged).

Trade-offs: on a loudspeaker the Android microphone also hears the voices from the room, a few tens of ms after the
mixed copy (a slight doubling); earphones avoid it. The web recorder's own camera / microphone capture is unchanged
(its microphone is what records the host's voice). Not yet seen on a device or a real browser call.

**Full-screen board.** Full view gives the content every pixel: no rounded frame, no side gutter, and on a phone /
tablet immersive system bars plus every orientation (restored on leaving, minimizing or closing the room), with the
safe area still respected. A fixed page keeps its shape (stretching would distort what was drawn), so where it
fights the screen's shape a "Turn your device…" pill shows for 5 s; a continuous page fills both ways. On a touch
screen the scrollbar thumb is big (12 px, 24 px held, ≥ 56 px long, 56 px hit target, a grip); a long press grabs it
and the finger drags the page up / down (D-109 behaviour, now finger-sized).

## D-307 — One share-link scheme for everything + the Meeting links page · 2026-11-08 · accepted

**Context.** The owner asked for deep links to share anything (page, user, material, course, meeting, teacher,
roadmap) and for one screen with every meeting link. The app had three unrelated link forms (`/c/<id>?ref=`,
`/@name`, `/live/<token>`), two share UIs (a web dialog and the bare system sheet) and no way to send a lesson, a
session, a meeting or a path.

**Decision.**
- **One scheme** (`lib/core/share/app_links.dart`, pure): the existing short forms stay (`/c/<id>?ref=` keeps the
  referral counter, `/@name` the public profile, `/live/<token>` the no-account guest link) and everything else is
  `https://nextbrain.site/s/<kind>/<id>` (kind = course · teacher · material · session · meeting · roadmap) plus
  `/s/page/<pageId>?<params>` for any page of the route registry (D-170: page ids never change, so a page link never
  breaks). Root form like the others: nginx forwards unknown root paths to `/app/` (D-270), the phone apps claim
  `/s/` (AndroidManifest `autoVerify` + `web/.well-known/apple-app-site-association`), crawlers get an Open-Graph card.
  ONE path prefix keeps it to one intent filter, one AASA entry and one nginx location for every new kind.
- **Landing (`ShareLinkPage`, main.dart route `/s/…`):** signed in → the target opens in its place and applies its
  own permissions (a lesson / session → the course page on Sessions, a path → its Path tab, a meeting → the Schedule
  page with its detail, a teacher → the public profile, a page → by name; never another role's home or a sign-in
  page). Signed out or guest → a public preview from `GET /api/v1/public/share/{kind}/{id}` + Sign in / Create
  account, and `SignInReturn` brings the person to the target after the sign-in. A signed-out `/c/<id>` now shows the
  same preview instead of jumping straight to the login.
- **What a preview may say:** only what the catalogue already shows a visitor. A public course (and its lessons /
  sessions / path) shows names, picture, teacher; a private or organization course and EVERY meeting show only their
  kind; a teacher only with a public profile (D-074 rules). One 404 `share_not_found` for every "no"; the route is
  throttled per address (`share_preview`, 120 / 10 min) so ids cannot be walked fast. No `/s/user/<id>`: students,
  parents and staff have no public page, so a user is shared only as `/@username` (teachers).
- **One Share sheet** (`lib/design/app_share_sheet.dart`): what is shared, the link (LTR), Copy, the system share
  sheet (apps; the web shows the link instead), a QR code; the course and profile shares now use it too (their old
  dialog stays for anything else). New Share actions: meeting detail (member link), the teacher's session menu, a
  lesson row (teacher), the course path. Kill switch `share.links`.
- **Meeting links page** (`/meeting-links`, `GET /api/v1/me/meeting-links`, kill switch `live.meeting_links`): every
  online room of the person from 7 days back to 60 ahead (meetings owned / invited, live sessions of the courses taught
  or studied), live first, then by day, ended last; Join / Open, Copy, Share + QR, and for the host the guest link,
  marked expired once the room ended. "Recurring" = a session made from the course's weekly slots (there is no
  recurring calendar meeting). Entries: the Schedule page (toolbar + ⋮), the teacher home header, the org Home's
  primary action. One call, never on a home's open (home budgets unchanged).

**Trade-offs.** A member link (`/s/meeting/<id>`) only helps people who can already open the meeting; outsiders
need the guest link, which the page and the sheets say. A material link opens the course page on Sessions, not the
file itself (opening a file needs the enrolment checks of the course page anyway). The `/s/` nginx location (preview
cards) and a web deploy with the new AASA are owner actions; until then people still reach the app through the
catch-all redirect, and the phone apps open `/s/` links only after the store builds with the new manifest.

## D-308 — Privacy policy and terms of service as versioned legal documents · 2026-11-08 · accepted

The app had one "Privacy & terms" page that showed the terms sections under two names, and the website had no
/privacy at all (Google's OAuth verification rejected it for "insufficient content"). Now there are two documents,
`privacy` and `terms`, written once in Arabic and English and shipped as versioned files in the backend
(`data/legal/<doc>.json`: version, effective date, intro, "At a glance" points, sections). The super admin may replace
either whole document from About & terms → Privacy & terms; the edit is stored in the AppSetting key `legal.<doc>`
(no table, no migration) and "Restore default" removes it, so a newer shipped version shows again. Public read:
`GET /api/v1/app-content/legal/{doc}` (`?lang=ar|en|both`).

- **Consolidated, not replaced.** The older terms_meta / terms_sections rows stay (installed app versions and the
  assistant's sync read `GET /app-content/terms`); saving or restoring the terms rewrites them from the document, and
  their editor stays as "Terms (older apps)". The app's TermsScreen, the sign-up sheet and the assistant all read the
  new documents; the privacy policy is also indexed for the app assistant.
- **Everyone can read them, before signing in.** Routes `/privacy` and `/terms` (no guard), a "Privacy & terms"
  group on every role's settings page, links under every auth card (kill switch `terms.links`) and a privacy link in
  the sign-up agreement row.
- **The website serves real HTML.** The landing builds `/privacy/`, `/terms/` (English, the URLs given to Google and
  the stores) and `/ar|en/privacy|terms/` from a bundled copy (`landing/src/content/legal/`, refreshed by
  `back/scripts/contract/export_legal.py`), or from the live document when the build has `LANDING_API_ORIGIN`.
  `build_landing.sh` refuses to swap in a build whose legal pages are missing or lack the Limited Use sentence.
  Trade-off: a super admin's edit reaches the website only at its next build.
- **Open points for the owner.** Governing law is written as "the law applicable where DoubleY operates" until the
  owner names a country; the retention periods (14-day deletion, 3-day export copy) follow the code, the 12-month
  security log and 90-day backup windows are commitments to keep.

## D-309 — One app-update screen per platform; the learning path on the personal home · 2026-11-08 · accepted

**App versions.** The super admin had two places for one question ("what are users told to update to?"): the build
page (D-143/D-144) and the "Update prompt" list of raw `app_versions` rows with three switches (force, recommend,
active). The rows' flags were also a trap: `force_update` blocked even the newest version and `recommend_update`
prompted it, and a manual prompt opened nothing in the D-143 app, which only shows the server's prompt when it names
a link. Now App versions is ONE screen: a card per platform (Android, iOS, Windows, macOS, Linux, web) with the
latest and minimum version and "who sees what"; an editor with the message (ar / en), the store / download link, and a
live preview that draws the real `UpdateDialog` for the blocking and the dismissible case plus a "Try a version"
field. The policy is two numbers (below the minimum → blocking; below the latest → dismissible): "Require the latest"
sets the minimum to the latest. Smart default: a newer live release is offered ("Use 2.2.0") with its notes and
effective minimum. Validation: valid versions, minimum ≤ latest, https link required on native platforms unless the
live release has its own link; raising the minimum asks to confirm.

It is a view over what existed, so nothing is lost and old apps are untouched: android / ios / web still read the
newest active `app_versions` row (a changed version adds a row, the old rows stay and the former list is one tap away
as "Update prompt history"); desktop platforms and every store link go in the AppSetting `app_update_policy` (no
migration). Saving clears the legacy flags; until then the check still honours them and the card says so. The
version check only gains additive fields (the store link when no live release names one). Build a version stays
the screen's primary action for the super admin. Trade-off: two stores for the same policy (rows vs setting),
hidden behind one service (`services/app_update_policy.py`).

**Learning path.** D-120's journey card showed only with a clear field and the page made its own call. The home card
now shows the path as segments, the next course with where the student is in it, and a "Continue" / "Start" button
straight into that course; `/me/home`'s `journey` carries its `steps` so the full page draws with no call (refresh,
a changed interest or an older server without steps still use `GET /me/journey`). A student with no path gets
`journey_hint: pick_interests` and a "Plan your learning path" invite that opens the interests sheet. Trade-off: the
home payload grows by the path's course briefs (a handful), and the cached journey is the full one; the home's
request budget is unchanged.

## D-310 — Meetings: End for everyone or Leave, handing the host over, the recording seen by everyone · 2026-11-08 · accepted

**End / Leave (owner: "a premium selection").** A meeting's host pressing End (the bar, or hang-up on the mini box)
no longer gets the plain "Leave?" dialog, which left the room running for the others without saying so. A sheet
offers two large choices — **End meeting for everyone** (danger; "the recording is saved" when this device records;
it is the host controls' end-for-all, so it is offered only while those controls are on) and **Leave meeting** (the
others stay) — plus Cancel. Everyone else, and every course session, keeps the plain confirmation: a class has one
teacher, and its End flow (recording drain, the session's end call) is unchanged.

**Handing the host over.** After Leave, while at least one signed-in person (never a guest) is in the room, a second
sheet asks "Give someone host controls?": the people with their photo and name (one person is pre-selected), **Make
host and leave** (disabled until someone is picked; a failure — they left meanwhile — keeps the sheet open with the
reason) and **No, just leave**; closing it keeps the host in the room. "For this meeting only": the server stores
`cal_meetings.acting_host_id` (migration 0063, no foreign key on purpose, it lives for one room) and every live host
check of the meeting reads `acting_host_id or owner_id` (`calendar_service.meeting_host_id`, `Room.host_id`): lobby,
policy and link, the controls, end for everyone, the admin LiveKit token and starting a recording. It never changes
the person's role or the meeting's owner, and it is cleared when the room closes (end for everyone, LiveKit's
room_finished, a retired room), so the next room is the owner's again. Only the current host may hand over
(`POST /api/v1/live/meeting/{id}/host {user_id}`, audited `live.host_handover`); the target must be the owner or an
invitee who did not decline, not removed, and in the LiveKit room now. LiveKit gives the new host every publish
source (the app's server-host test), the old host camera + microphone.

**Telling the new host's room.** Three paths, the server always deciding: the event `live_host_changed` (SSE + silent
push, to the owner and invitees; the room binds the SSE stream while it is open), a LiveKit data packet on topic
`host` from the leaving host — only a hint, the room confirms it with `GET …/host` — and one `GET …/host` when a
meeting room opens (a rejoin after a handover, the owner coming back). The room then starts the lobby and the host
controls and may record, without rejoining (`RoomPage._hostOverride`); a host handed away stops them.

**Who pays, who owns.** Billing stays on the owner: the free minutes and the live plan (`live_plan_service`) keep
reading `owner_id`, so a handover never moves the cost to the new host (who could otherwise end up paying, or a
student could dodge the limit by handing over), and the live plan's Upgrade stays the owner's button
(`RoomPage.isOwner`). Editing the meeting and the meeting's recordings list stay the owner's; a recording the new host
starts goes to the NEW host's drive (the recorder is theirs). The owner rejoining never waits in the lobby and passes
the lock, as a member; the host may hand the room back to them. Kill switch `live.host_handover` (Leave then just
leaves).

**The recording indicator (owner: "pause icon while paused, live recording icon while recording").** The recording
device already drew it in the top row (D-095); the gap was that a meeting records on its host's device (D-098) and
nobody else's room knew. The recording device now publishes its state on the LiveKit data topic `rec`
(`live_rec_signal.dart`: recording / paused / off + the elapsed time; on every change, to a newcomer, and every 15 s;
forgotten after 45 s of silence or when the sender leaves), and every other room draws the same control without its
menu: a pulsing red dot + REC + the time while recording, the amber pause glyph + "Paused" («متوقف مؤقتًا») while
paused, and a notice "This meeting is being recorded". A remote recording takes the slot before the Record offer (a
second recording of the same meeting helps nobody). The dot now follows Reduce motion (`syncMotionLoop`, parked fully
lit: the colour and the label still say it). Trade-off: a data packet is not proof — any participant could send one;
the worst case is a false "REC", and guests' packets are ignored. Tests: `test/org/live_host_handover_test.dart`,
`test/ui/live_host_handover_layout_test.dart`; backend `tests/org_v2/e2e_meeting_host_handover.py`.

## D-311 — Records: my meeting recordings as a library, edited without touching the original · 2026-11-08 · accepted

**What.** My profile › Records (kill switch `profile.records`) lists every meeting recording the person OWNS (D-058:
recorded on the host's device, assembled on the server, stored on their Google Drive / OneDrive), one item each,
newest first, grouped by meeting (title + date), with cover, title, length, size and a status chip (recording ·
editing · saving to the drive · ready · failed + Retry). Tap a ready item → the editor; ⋯ → play & edit · rename ·
cover · open in the drive · retry · delete; long-press → multi-select with a bar (Merge 2+ ready items in a chosen
order, Delete). Files: `lib/features/shared/records/` (`records_api.dart` pure, `records_parts.dart` plain values,
`records_page.dart`, `records_notice.dart`); backend `routers/records_router.py`, `services/records_service.py`,
`services/records_edit.py`, migration 0064; contract `../back/FLUTTER_API_CHANGES.md` "Records".

**Edits are non-destructive.** Trim (keep [a, b]), split (two items), cut a period ([a, b] removed, the rest joined),
speed (0.5 · 0.75 · 1.25 · 1.5 · 2, audio pitch kept with `atempo`) and merge each make a NEW row (kind `edit`,
`operation`, `op_params`, `source_ids`); the source is deleted (row + drive file) only when the person switches
"Delete the original" on, and only after every output of the job is done. Why: an edit renders for minutes on the
server and lands on the person's drive; a failed or wrong edit must never cost the original. Trade-off: the drive
holds both until the person deletes one.

**Jobs.** A background job per request (a split's two halves share one download): download the source(s) from the
drive (`cloud_drive_service.download_file`: Google `alt=media`, OneDrive `/content`), ffmpeg with local_recorder's
helpers (frame-accurate re-encode at the source's quality; a merge normalises sizes / fps / audio first — an audio-only
part gets a black frame, a silent video a silent track; all audio → `.m4a`), upload with the recording pipeline's
`_upload` (so a failed upload keeps the file and gets the same automatic retries), temp files removed. States
assembling (stage downloading → processing) → uploading → done | failed with `progress`, each step a
`job_updated{kind: recording}`; the library watches with `EventOrPoll` (no timer polling while the stream is up).
At most 3 running edits per person, 2 jobs per worker. A cover (cropped wide with `showAppImageCropper`, public
images bucket `record-covers/<owner>/`) is inherited by edits and embedded as the file's attached picture (a stream
copy). A failed download is not retried automatically (Retry re-runs the job); a failed upload is.

**Preview.** `POST …/play` returns a 2 h signed URL `/api/v1/me/records/stream/<token>` (bound to the owner, the row
and its drive file id) that proxies the drive with HTTP Range — a web `<video>` / `video_player` cannot send a bearer
token, so the token is the credential, as in routers/stream.py, without device binding (the person's own files, not
paid content). Trade-off: playback bytes flow through the API server.

**Ownership.** Someone else's record is 404 `record_not_found` on every route (the library never says what exists).
Edit rows stay out of the meeting's own recordings list, so attendees only ever see the room recording.

**After a meeting.** When the meeting recorder's stop reaches the server (End for everyone, or a plain Stop) the app
shows "Saving your recording to Records" with Open; the ready / failed notification now opens Records on the item
(`related_type: live_recording`, push module `records`, AppNavigator case `records`) instead of the calendar.

## D-312 — Records: play first, share with chosen people or by link, the Studio · 2026-11-08 · accepted

**Play first.** A tap on a ready record opens the PLAYER, not the editor: the app's one course video player
(`VideoPlayerScreen.fromLegacy` on the signed stream of D-311, through `RecordPlayerPage` in
`lib/features/shared/records/records_share.dart`), so the owner sees the recording exactly as a student sees a lesson
(controls, speed, gestures, fullscreen, screen protection). The player gained `actions: [VodAction]` — caller buttons
on its top bar (`VodActionButton`, icons only below 720 px, the help button gives them its place below 480 px). Records
puts **Open in Studio** (pops the player, opens the Studio) and **Share** (the sheet over the player) there; the item
sheet has Play · Open in Studio · Share too. Why reuse instead of a records-only player: one player to keep right, and
"like a student sees it" is literal.

**Sharing** (`records_share_api.dart` pure, `records_share_parts.dart` plain values, `records_share.dart`; backend
`services/records_share.py`, migration 0065 `record_shares` + `record_share_people`; kill switch `records.share`):
- Two audiences: **Only people I choose** (signed in, on the list) or **Anyone with the link** (anyone signed in; the
  chosen people are still notified and listed). No signed-out playback: recordings are meetings, and the playback
  bytes flow through our server (D-311).
- The link is `https://nextbrain.site/s/record/<token>` — D-307's scheme, kind `record`, but by the share's random
  TOKEN, not the record id: "anyone with the link" then really means that (ids can be walked); stopping the share
  kills the token and sharing again makes a new one. `AppLink.record(token)`; the apps already claim `/s/`.
- People picker: the calendar invitee picker's people half (the same search rule `username_service.people_filter`,
  the same rows), on the record's own reach — the people I know (my organizations, students of my courses, teachers
  of my courses, the meeting's host and attendees, those already chosen) by name or @prefix, ANYONE else only by the
  exact confirmed @username, a platform admin anyone. A record can go beyond my organizations, yet the platform's
  directory is never searchable by name.
- Newly chosen people get a notification (`record_shared`, `related_type: record_share`; push / tap module
  `records_shared` with the token → `SharedRecordPage` → the player; AppNavigator case `records_shared`). The sheet
  shows who it is shared with and whether they opened it, the views, Copy link / Share via (phones), Save, Stop
  sharing.
- Everyone not allowed gets the same 404 `record_not_found` (never "it exists but…"); every stream request re-checks
  the share, so removing a person or stopping the share stops playback mid-way. Records › **Shared with me** (a tab)
  lists the shares I am chosen for.
- Previews never leak: the public / Open-Graph card of a people-only share is the generic "Recording" card; only an
  anyone-with-the-link share shows its title and cover (the bot already holds the link). nginx needs the new location
  `^/s/record/[A-Za-z0-9_-]{8,64}/?$` (owner action, `deploy/nginx/nextbrain.conf.example`).

**The Studio** (`records_studio.dart` + plain values `records_studio_parts.dart`, replacing the D-311 editor):
- A large preview on a dark stage with its own transport (play / pause, −5 / +5 s, current / total mm:ss, a
  preview-speed chip that never changes the file), the **filmstrip timeline** below, the tools Trim · Cut a part ·
  Split · Speed · Cover · Merge, each with one line saying what it does; a live summary ("New length 12:40", the two
  parts of a split, the merge's total) or why it cannot be made; Undo / Start over of the pending selection (the last
  50 states, a drag counts once); ONE primary button — "Save as new", or "Save and replace" when "Replace the
  original" is picked (D-311's delete-after-success, confirmed first). Cover saves at once (no new item). Merge picks
  other ready items, numbered in order after this one. The Speed tool previews at the chosen speed.
- Filmstrip: the server makes ONE sprite of 24 frames (160×90, letterboxed) per record and drive file, cached on disk
  (`POST …/frames` → ready / pending / unavailable, `GET …/stream/frames/<token>`), with ffmpeg reading the drive over
  HTTP with input seeks (download fallback), so a long recording is never downloaded whole just to draw its strip.
  The app stretches the sprite over the whole length (each tile = its slice of time, so zoom stays right), waits for
  `job_updated{kind: record_frames}` with JobWatch while pending, and draws a tinted track (a shimmer while pending)
  when there are no frames (audio, no ffmpeg, a failure). Trade-off: 24 frames are coarse on a 2 h recording at ×16 —
  the strip is a guide, the preview is the truth.
- **Time runs left → right in Arabic too**: media timelines do, and so does the player's own chrome; the transport
  and the timeline are wrapped in an LTR Directionality, the panels around them follow the language.
- Handles: trim shades what goes and frames what stays; cut stripes what goes in red; split is an accent marker with
  two knobs; the playhead has a head on the ruler. 48 px grab zones; zoom ×1 – ×16 with a scroll that follows the
  playhead (a drag pans when zoomed, the mouse wheel scrolls).
- Keys (web / desktop, never while typing the name): Space, J / K / L, ← / →, I / O (start / end), S (split here),
  Ctrl+Z.
- The saved job stays in the Studio, inline (`StudioJobCard`, EventOrPoll on `job_updated{kind: recording}`): stage,
  progress, then Play or Retry, "Another edit", "To Records". The Studio pops with every item it made or changed.
- Wide (≥ 960 px): the editor on the left, a 400 px side panel (tools with their descriptions, the tool's controls,
  the summary, save). Phones: one scrolling column and the tools as a bottom segmented bar.

**Library polish.** Bigger covers with a play mark, a summary line (count · total length · in progress), the empty
state names the Studio and sharing, tabs My recordings · Shared with me.

Tests: `test/org/records_share_api_test.dart`, `test/ui/records_studio_layout_test.dart` (the layout harness on every
tool, the job card, the share sheet / picker / list, the LTR timeline in Arabic), `test/ui/records_layout_test.dart`;
backend `tests/org_v2/e2e_records_share.py`, `records_frames_check.py` (real ffmpeg, dev image). Contract
`../back/FLUTTER_API_CHANGES.md` "Records: share + studio frames".

## D-313 — Meeting room round 2: a smooth board in the recording, the paused Record from the start, content edge to edge with floating controls, every End choice explained · 2026-11-08 · accepted

Four owner requests for MEETINGS (course sessions keep their behaviour; the board capture is shared because only
meetings record on the web this way).

**(4) The board in the web recording (owner: "slow, with stops").** D-306 re-rendered the page into the compositor's
canvas from a 500 ms timer: 2 frames a second, so a stroke appeared in jumps. Now the room renders a frame on EVERY
board change — stroke points included (`BoardScene` notifies per point) — scheduled by `BoardRecPacer`
(`whiteboard/board_rec_pacing.dart`): at most the compositor's 30 fps, one capture in flight, nothing at all while
the page is still (the canvas keeps the last picture and the compositor redraws it every 33 ms), a re-send every 2 s
and a 100 ms check that notices a scroll of a continuous page (a scroll fires no change). On the web the capture runs
on the UI thread, so the pacer keeps an average of the capture time and steps down a ladder — 30 fps → 24 → 24 at
¾ size → 15 → 12 at ½ → 8 → 5 — when a capture costs more than 35 % of the frame period, and climbs back one step after
45 cheap frames (< 15 %); a weak laptop records fewer / smaller board frames rather than a stuttering room. When the
drawing stops on a reduced frame, one full-size frame follows 350 ms later, so a still page is always crisp. The frame
is drawn from the items (`BoardRecordingFrames`, board_export.dart; fixed pages too, no longer a RepaintBoundary
screenshot): everything except the strokes still being drawn is rasterized ONCE into a cached image (keyed by size,
window, paper, page and the items by identity + version) and each frame is that image + the open strokes, so its cost
no longer grows with how full the page is. Debug builds log one line a second (`[REC] board frames: n/s, capture avg /
max ms, tier`) and every tier change.
*Measured* (`BOARD_REC_BENCH=1 flutter test test/org/board_rec_pacing_test.dart`, this Windows dev box, host Skia —
not a browser): a drawing frame (cache + one open stroke + RGBA read-back) 12.3 / 11.9 / 10.3 ms at 1280×720 for a
page of 10 / 100 / 400 strokes, 6.5–8 ms at 960×540, 2.6–4.4 ms at 640×360; the old way (the whole page every frame)
20.8 / 55.3 / 160.8 ms at 1280×720. So a full page that used to cost 160 ms a frame (it could not have run at more
than ~6 fps) now draws at 30 fps on this box, and a weaker machine settles on a lower tier by itself.
The same bench in Chrome (CanvasKit, `flutter test --platform chrome --dart-define=BOARD_REC_BENCH=1`) did not start on this box (the browser test runner hung at loading), so the browser cost — where the RGBA read-back is a GPU stall on the UI thread — is NOT measured; the pacer is what keeps it in check there, and the debug log line is how to read it in a real call.
**Android** needed no change: since D-110 its recording is the native 30 fps PixelCopy of the Flutter surface
(RoomFrameGrabber.kt), and the board is drawn on that surface as it is drawn on screen — no Dart capture of the board
at all (the 12 fps Dart frames of live_frame_pacing.dart are only the fallback when PixelCopy fails). Not measured on
a phone in this round.

**(5) The paused Record from the first second (owner: "show the pause button by default").** Interpretation: a
meeting still opens NOT recording (D-306 `liveRecordsAtStart`; nothing is ever captured without the tap), but the
person who may record sees the recording control at once in a clear paused / not-yet state: the amber pause glyph +
"Not recording" (phones: the glyph) + "● Record", one tap = start (the setup sheet's destination + quality the first
time; the next Record in the same meeting during this app session starts straight on with the same choice —
`RecordingStart.destination`, room.dart `_recChoice` — and falls back to the sheet if that start fails, e.g. a drive
disconnected). The opening notice says "Not recording yet". Everyone else sees nothing until the recording really runs
(then D-310's REC / Paused).

**(6) The board / a shared screen edge to edge, the controls over it, a hide / show button.** In a meeting whose stage
shows the whiteboard or a shared screen (`liveStageOverlayOn`), the room uses the overlay layout
(`widgets/live_stage_overlay.dart`): the content takes the whole stage (no rounded frame; on a phone / tablet the
system bars go immersive and the device may turn, as in full view — the safe area still pads the content), and the top
row, the control bar and — for whoever draws — the board's tool dock float over it on a translucent scrim; the
camera boxes (presenter + others, my own) stay over the page and keep clear of the bars. One small toggle, always on
screen at the top centre under the top row (eye + chevron, 34 px drawn, 48 px target, a label from 600 px), hides /
shows all of it with an AppMotion slide (at once under Reduce motion); hidden, it still shows the recording (red dot,
or the pause glyph while paused / not recording yet). F toggles it, Esc and the back button bring the controls back,
a tap on content nobody draws on toggles too. The choice is remembered per meeting for the app session
(`LiveOverlayMemory`; shown by default). **No auto-hide** (decided): the owner asked for a button, and controls that
leave by themselves fight it and would hide the REC state while recording. Full view stays for course sessions; in the
overlay its button is gone (the overlay already is full, its toggle is the hide). An open side panel (chat / hands on
a wide screen) keeps its column. Course sessions keep their layout. Trade-off: on the Android device recording (the
room UI as seen) the floating bars are in the recording while shown — hiding them gives a clean recording.

**(7) A description under every End choice.** The host's End sheet (D-310) now says what each option does under it:
End for everyone — "Everyone leaves now; the recording is saved to Records" while this device records (else "…and the
meeting closes"); Leave — "The meeting continues without you; you can hand the host role to someone"; Cancel — "You
stay in the meeting; nothing changes". The handover sheet too: under Make host and leave, under No, just leave ("You
leave and the meeting goes on for the others without a host; you can come back later"), and a new Cancel ("You stay
in the meeting as its host"; closing the sheet did the same before, without saying so). Bilingual (t(ar, en)).

No kill switch, no server change. Tests: `test/org/board_rec_pacing_test.dart`, `test/org/live_stage_overlay_test.dart`,
`test/ui/live_stage_overlay_layout_test.dart`, `test/ui/live_host_handover_layout_test.dart` (descriptions). Not seen
yet on a device or in a real browser call.

## D-314 — The whiteboard: smooth, realistic ink, and a board that fills the whole stage · 2026-11-08 · accepted

Amends D-083 (the ink's renderer), D-093 (the continuous column) and the share sheet's default page.
**Context.** The owner: "When I draw with the pen, the ink is discrete. I need the ink smooth, more realistic." and
"When I start sharing the board, make the board fill all the width and height (not only the height)."

**Why the ink looked discrete (measured, `test/org/board_ink_smooth_test.dart`).**
(1) The main cause: every pen sample rebuilt the whole board. A point added to the stroke notified the `BoardScene`,
and the stage, the room's board view and the dock all rebuilt on it (`Listenable.merge([_c, _c.scene])`): ~500 widgets
per sample, the page's extent / sideways reach re-measured over every stroke, and every item on the page repainted. In
the widget test that was 22 – 55 ms a sample (debug build, 1400×900, 0 or 150 strokes); a real browser (CanvasKit draws
on the UI thread) or a phone lost frames, so the stroke under the pen advanced in jumps. Now 0 widgets and ~5 ms.
(2) A stylus stroke was a circle + a band per node (a node every 0.3 pen widths): thousands of sub-paths per stroke
that every frame filled under non-zero — heavy on the web, where nothing is raster-cached.
(3) The centre line was the chain of quadratic Béziers through the samples' MIDPOINTS: it never passes through a
sample and cuts every corner. Flutter delivers one sample per frame (the Android embedding sends no historical
samples, iOS no coalesced touches; only the web expands `getCoalescedEvents`), so at 60 Hz a quick loop came out
flattened — 1.6 px off its samples on a 25 px loop.
(4) A viewer saw a remote stroke grow one 33 ms network batch at a time (2 – 4 points at once).
(5) A continuous page's y travelled with 5 decimals of its 20-width length: 1/5000 of a width, 0.4 px on a page as wide
as a 1920 px screen (see below), 1.5 px zoomed in.
Pointer input itself was fine: every PointerMove reaches the One Euro filter (D-083, unchanged), nothing is
throttled before drawing, and the drawer's stroke was already drawn locally, never after the network echo.

**Decision — ink.** (a) `BoardScene.settled` notifies on every change except a stroke's new points and laser dots;
the stage, `WhiteboardRoomView`, the dock and the options sheet listen to it. The stage paints two layers: what is
finished (RepaintBoundary, repainted only when it changes) and the open strokes (repainted per sample). A stroke still
being drawn re-lays the page out only when it reaches past what the last layout measured (a quarter screen below the
content of a continuous page, or beside the column, D-107). The recording keeps listening to every change (D-313).
(b) The centre line is a centripetal Catmull–Rom spline through the samples (`annotInkPiece`; α = ½: no cusp or loop
inside a piece, so it adds no wiggle; prefix-stable — pieces 1 .. n − 2 never move, as before). The loop above: 0 px
off its samples, under 60 % of the old error against the real curve. D-083 had rejected "Catmull–Rom through every
sample (it passes through the jitter)": the samples it now passes through are the One Euro filter's output, not raw
digitiser points. (c) A stylus stroke is ONE filled outline (`annotInkOutline`: left edge, round cap, right edge, round
cap, clockwise; a round join where the centre line turns tighter than the pen, so the inner edge never opens): pixel
for pixel the old union (0 differing pixels over 12 random scribbles with hairpins), ~2 sub-paths instead of
thousands. Pressure, causal radii, tapers, finger / mouse (one stroked path, round caps) and the highlighter are as in
D-083. (d) A viewer reveals a remote stroke at the drawer's pace: the points of a batch are drawn over the time since
the previous batch (16 – 120 ms), the tip interpolated between two points, never ahead of what arrived; a finished
stroke is drawn whole at once (`BoardController.inkShown` / `stepReveal`, driven by the stage's frame clock). The
drawer's own stroke is never delayed. (e) Board points carry y with 6 decimals (`kBoardYDigits`,
`boardPointJson`); x and the pressure as before. A fixed page's points are 5-decimal numbers already, so its packets
are byte for byte the old ones; a continuous stroke is 22.7 bytes a point (≈ +1 byte). The annotation over a shared
screen draws with the same renderer, so (b) and (c) apply there too; its wire, the reveal and D-083's screen-security
rules are unchanged.
**Compatibility.** Same protocol (`v` / `bv` unchanged). An older app draws a new app's strokes with its midpoint chain
and union (a few px rounder or flatter on a fast loop, nothing else) and reads the 6-decimal y as the 5-decimal number
it knew; a new app draws an older app's strokes with the spline.

**Decision — the board fills the stage.** (1) A continuous page's column is the stage's WHOLE width
(`ContinuousView.columnWidth`); it was capped at max(480, 0.8 × height), so a laptop got a reading-width column with
bare margins beside it. Page coordinates are page-width fractions, so this is a pure view change: every device still
puts everyone's ink at the same place of the page, and viewers keep following the presenter's top / sideways view
(D-093 / D-107). New pens, shapes and text boxes keep their old pixel size (`boardContinuousStyleFactor`: the old
column ÷ the full width, 1 on a phone or a tablet), so a medium pen is not 2.5× thicker on a laptop. (2) The share
sheet starts on the CONTINUOUS page on every device (it was landscape, portrait on a phone): it fills the width and
the height for the presenter AND for every viewer, whatever their screen's shape. Landscape and portrait stay one tap
away, still fitted whole (`contain`): they are the slide and the sheet of paper, and stretching would distort what is
drawn. (3) The web recording follows the presenter's full-width view (`boardRecordingWindow`: the whole width, widened
to 16:9 by more page below); a fixed page is recorded whole as before. The D-313 overlay layout is unchanged.
**Trade-off.** One page width now means a different number of pixels on each screen, as on a phone already: what a
laptop presenter writes across 1920 px is shown at 390 / 1920 on a phone (it was 390 / 760) — smaller but whole, and
the viewer can zoom; a phone presenter's page is the width of the phone everywhere. Rejected: a "screen-shaped" fixed
page with the presenter's aspect (a new format: older apps would need `bv` 4 and see "update the app", and every
viewer with another shape is letterboxed anyway); stretching a fixed page to the stage (circles become ellipses);
keeping the landscape default and only widening its column (a 16:9 page cannot fill a 2:1 window without distortion).

No kill switch, no server change. Tests: `test/org/board_ink_smooth_test.dart` (rebuilds per sample, the spline vs the
midpoint chain, the outline vs the union, the reveal, the 6-decimal y and bytes per point, the full-width view and
recording window, the pen's pixel size), `board_format_test.dart` / `board_grow_sideways_test.dart` (the full-width
column), `whiteboard_*_layout_test.dart`. `INK_RENDER=<dir>` writes before / after PNGs. Not verified: a real stylus
(S Pen, Apple Pencil, a Windows pen), finger on a touch screen, Impeller on a device, a real browser call with remote
viewers, the browser cost of the outline.

## D-315 — The Studio on session video materials (drafts, then publish as new or in place); records shared with guests by e-mail · 2026-11-08 · accepted

**The Studio's source is pluggable.** `StudioSource` (`lib/features/shared/records/studio_source.dart`) is all the
Studio page talks to: `RecordStudioSource` (a drive recording, D-311 / D-312, unchanged behaviour) or
`MaterialStudioSource` (`material_studio_api.dart`: a course session's VIDEO / RECORDED material in MinIO). A source
names its tools (a material has no Cover — the course page draws none), whether its jobs make drafts, and its
`job_updated` kinds (`material_edit`, `material_frames`). The ffmpeg side is the same `records_edit.render` (trim · cut
· split · speed · merge); the server job (`services/material_studio.py`) downloads the material from MinIO (an HLS
playlist is read over a presigned URL), renders, and uploads into the videos bucket (`session_<sid>/studio_<uuid>.mp4`,
faststart, length from ffprobe, quality from the source's height) — what an uploaded video material is after
`/materials/from-upload`, which has no other post-upload step (captions stay the teacher's own action). Shares the
Records worker slots and the 3-running-edits cap.

**A draft, never a material, until it is published** (`material_edits`, migration 0066). Why: a draft row in
`session_materials` would reach every enumeration of a session's materials (student lists, progress and completion
counts, offline downloads, exports, search) and each would need a "hidden" filter; keeping the output outside the table
means a student cannot see it by construction. Publish has two modes, picked in a sheet that says what each means:
- **A new material** (the default): a VIDEO material right after the original; nothing a student already has changes.
- **Replace the original**: the new file goes into the original's ROW, so its id — and with it completions, progress,
  view counts, ratings, the place in the list — is kept. The old file's fields and its captions (whose times no longer
  match) are kept in the draft (`replaced`) and the old objects stay in MinIO until the staff press **Delete the old
  file**; **Restore the original** puts them back. A second replace of the same material waits until the first is
  confirmed or restored (409 `material_replace_pending`). Deleting the material deletes a pending replace's old file.
  A student's offline copy is an encrypted file on their device: it keeps playing (the old version) until they
  download again — nothing breaks. Trade-off: no "updated, download again" hint for them yet.

**Who.** Exactly who may edit the material today: the material routes' roles plus `can_manage_session` on the course
and the session's track (teacher, platform admins, org staff with `courses.update`, an assistant on section sessions or
with `lecture_edit`); others 403, as every material route. Archived org course: writes 409 `course_archived`. A merge
stays inside one course and only takes sessions the person may edit. An org course's publish / restore is audited.
The Studio's preview plays through the platform's own stream link issued without a device (staff only), so the
Studio's player needs no headers. Kill switch `materials.studio` (the button, the player action, the drafts strip;
the server refuses edit / merge / publish when it is off everywhere).

**Entries.** The teacher's session materials list: a Studio button on a video material (next to captions), and
**Studio drafts** above the list (only the course staff see it; Play · Publish · Discard · Retry; after a replace
Restore the original · Delete the old file; follows running jobs with EventOrPoll, draws nothing when empty). The
teacher's player: **Open in Studio** on the lecture playing NOW (`VideoPlayerScreen.actionsFor`, lectures switch in
place). In the Studio the save button is **Save as draft** with a note that students don't see it, and the inline job
card puts **Publish** next to Play. Files: `material_studio_api.dart` (pure), `material_studio_parts.dart` (plain
values), `material_studio_page.dart`; backend `routers/material_studio_router.py`, `services/material_studio.py`.

**Guests by e-mail** (the Share sheet of D-312, under `records.share`): the owner types addresses (the app's e-mail
rule, `kEmailRegex`; up to 20 at a time, 100 per record), an optional message and how long the link works (7 days ·
30 days · never). Each guest gets ONE personal link `https://nextbrain.site/s/record/g_<secret>` — the D-312 scheme
and nginx location, a `g_` token — e-mailed through the platform's SMTP (`services/email_service.py`). When SMTP is not
configured (production today) the guests are still created, the answer says `mail.code: email_unavailable` and the
sheet says so and offers Copy link per guest; a send failure is per guest (Resend). Guests show in the people list
with a **Guest** badge, opened / views / e-mail state / expiry, Copy link and ⋯ (Resend · Revoke). Stopping the share
deletes them (every link dies).

**The guest's page** (`record_guest_page.dart`): main.dart sends a `/s/record/g_…` link to `GuestRecordPage` before the
share-link page, signed in or not, outside the guards; it calls ONLY `/api/v1/public/records/guest/…` with
`auth: false` (nothing can redirect to the login). The card (title, who shared it, length, message, expiry) and Play →
a 2 h signed stream token bound to the guest row; EVERY stream request re-checks the row, its expiry, the share and the
record, so a revoke / stop / expiry stops a running playback. A plain player (play / pause, ±10 s, scrub; LTR like
every media control), not the course player: that one reads providers and authenticated APIs. Views and first / last
opened are counted. Anything invalid is the same 404; the card / play calls are rate-limited per IP (`record_guest`,
120 / 10 min); a guest's stream token never works on the owner's stream route and the other way round. A link-preview
bot gets the generic "Recording" card for a guest link. Why a personal token per guest rather than the share's link
token: it can be revoked alone and counted alone, and an e-mail that is forwarded leaks one guest, not the share.
Trade-off: playback bytes flow through the API server (as D-311).

Data: ONE revision `0066_studio_materials_guests` (`material_edits`, `record_share_guests`). Contract
`../back/FLUTTER_API_CHANGES.md` "Studio on session materials + record guests by e-mail". Tests: backend
`tests/org_v2/e2e_material_studio.py`, `e2e_records_guests.py`, `material_studio_ffmpeg_check.py` (real ffmpeg, dev
image); app `test/org/records_guests_api_test.dart`, `test/ui/records_guests_layout_test.dart`. Not yet seen in a real
browser against the local stack.


## D-316 — A material card has ONE ⋯; the Studio is left with one pop (2026-11-08)

A teacher's material card carried separate Studio, Share, Settings and Delete icons. They are now one ⋯
(`MaterialMoreButton`) that opens `MaterialOptionsSheet` (`components/material_tile_parts.dart`): the material on top,
then Open in Studio (videos) · Edit details and Share lesson link · Delete apart, each with a line saying what it does.
Captions stay on the card and so does the drag handle, because the first shows a live job status and the second has to
be grabbed. The card is `_MaterialCardShell`: raised, ink + hover, the type's colour on its start edge, the number on
the corner of the type tile.

Leaving the Studio: `MaterialStudioPage` and the `RecordStudioPage` inside it each had a `PopScope` that popped, so one
Back closed the Studio AND the course page under it, the second pop carrying a List into a `bool` route. The inner page
now owns the only PopScope and pops `popResult()`. The player's Open in Studio no longer pops then pushes from the tile's
context: the navigator and the reload are read when the tile is tapped, and `pushReplacement` swaps the player for the
Studio in one step. Tests: `test/ui/material_studio_nav_test.dart`, `test/ui/material_tile_layout_test.dart`.

## D-317 — The ink keeps up with the pen · 2026-11-08 · accepted

Amends D-314. The owner: "when open the board why there are a delay in ink? I need to make it a realistic".
Measured in `test/org/board_ink_latency_test.dart`. Two causes on the drawer's device, neither of them the network:
(1) The filter (D-083's 1 Hz speed estimate) treated each stroke's start as a still pen: at 1000 px/s the ink was 16.5 px
behind, and took about 200 ms to catch up. The board now uses its own `boardInkFilter` (min cut-off 1.5, beta 0.08, speed
cut-off 12 Hz): about 3 px at most, from the first sample, with over 40 % of a digitiser's jitter still removed. The
annotation over a shared screen and its Kotlin twin keep the D-083 values.
(2) A pen-down and a pen-up each rebuilt the board (541 widgets) and repainted every finished stroke: 98 and 83 ms on a page
of 120 strokes in the debug test, for every letter written. Now 20 ms each with no rebuild: a pen-down changes nothing
finished (`_changedLive`), and a pen-up repaints only the finished layer (`BoardScene.finished`), while the layout and the
toolbar wait for [kBoardInkSettleDelay] (250 ms) after the last pen-up and never land inside a stroke.
Viewers: the reveal's upper bound is 50 ms (was 120), so a late batch catches up quickly.
Not changed: the web recording's capture (D-313), which shares the UI thread while recording; the 70 ms finger hold (it only
delays what goes out, and it is what tells a pinch from a stroke). Not measured on a real device or browser.

## D-318 — The ink while recording, and Quality and size in the Studio · 2026-11-08 · accepted

Amends D-313. The owner: "the drawing work fine but when recording there are a delay in ink why?".

**The cause.** For every change of the board the web recording made a Flutter raster of the page (`toImage`) and read it
back as RGBA (`toByteData`), on the UI thread that also draws the pen. D-313 noted that this cost had never been measured
in a browser. Measured now (a throwaway page, `flutter build web --profile`, Chrome on the Windows dev box, 1280 × 720):
a drawing frame took 33 – 36 ms on average (p95 45 – 54 ms), which is the whole of a 30 fps frame, and Chrome logged "GPU
stall due to ReadPixels". The pacer could only make the stall rarer. A second cost: `_sendLiveScreenPlaceholderWeb`
took a PNG of the whole room 1.2 s after each board change, for a still the compositor does not draw while the board is
on the stage; it now returns at once when the board is on the stage.

**The fix.** Ink no longer needs a raster (`whiteboard/board_rec_ink.dart`, `BoardRecordingFrames.next`). The recorder keeps
a base picture on its own 2D canvas; an open stroke goes as path commands on top of it, frame by frame, and a finished
stroke is drawn into the base once. The geometry is the painter's (`AnnotationPainter.traceStroke`, through
`AnnotPathSink`). A raster remains for what ink cannot express: the first frame, a page turn, a scroll, an undo, a shape
or a text. The same bench: 0.6 ms a frame on average, p95 1 – 1.4 ms, on a page of 10 or of 150 strokes, through the real
`WebRecorder.pushBoardFrame`. The 2-second re-send of a still page is gone: nothing is rendered when nothing changed.
`test/org/board_rec_pacing_test.dart` checks no raster while writing and compares the vector strokes with the raster
pixel by pixel. Not exercised in a real meeting. Android (D-110, PixelCopy off the UI thread) is unchanged and not measured.

**Quality and size.** A new Studio tool on recordings and session videos (never audio), a new operation `quality`
{height?, level} on the existing edit routes, no migration. Resolution: Original · 1080p · 720p · 480p (the short side, so
an upright video is handled); level: Smaller file · Balanced · Best quality (CRF 30 / 26 / 20 with a bitrate ceiling per
height, `-maxrate`). The ceiling is what lets the panel say "up to about X" (the same table in `records_edit.py` and
`records_api.dart`); a quiet video such as a whiteboard comes out well under it. Raising the resolution is allowed, and the
panel says it cannot add detail the original lacks. The original is kept unless Replace is chosen; on a session video the
result is a draft, as for every Studio edit (D-315). It is its own save: a trim and a change of quality are two jobs.

## D-319 — Open in Studio on the web, a closed meeting, recording quality 144p – 2160p · 2026-11-08 · accepted

**Open in Studio closed the Studio (web only).** The player is replaced by the Studio. `WebHistory` steps the browser back over the old page and pushes the new one; the popstate of that step was followed only after the whole sync (one queue), so the entry it landed on was no longer the top and read as the person pressing Back, which closed the Studio. Every replaced page on the web had this. The sync now remembers where its own step lands (`_ownLandings`). Reproduced first with a fake browser (`test/ui/web_history_replace_test.dart`). This is what D-316 could not reproduce: its test ran without the history.

**Closed in the calendar.** `end-for-all` sets `cal_meetings.status = "ended"` (no column needed): listed with `status: "ended"`, no Join (409 `meeting_ended`, guests `live_ended`), no recording, nobody busy, the calendars of the owner and invitees told at once. Only the host's End for everyone closes it: a room that merely emptied can be rejoined. Given a new time, an ended meeting opens again.

**Recording quality.** Audio only, or 144 · 240 · 360 · 480 · 720 · 1080 · 1440 · 2160p, picked by the creator on the new-meeting form (`cal_meetings.record_quality`, migration 0067); the Record sheet opens on it and the host can still change it. Before this the web canvas was always 1920 × 1080 and only the bitrate changed, and on Android "720p" capped the LONGER side to 720. Now the web canvas really has the picked height (the compositor keeps drawing in 1920 × 1080 space, the context scales it) and the native recorders get the 16:9 width as the longer side. The board is drawn at the picked size between 480 and 1080 lines (above full HD a page change would cost too much for what it adds). 1440p and 2160p warn that they need a strong device and that the picture is only as sharp as the camera or screen being shown.
## D-321 — The schedule page has two tabs; a closed meeting is finished on the calendar · 2026-11-08 · accepted

Amends D-085. The owner: "in my calender, please inhance the calender UI to be more attractive and premium and have tow tabs (one for schedule meetings and second for the calender grid", and "when close the meeting make this meeting is closed in the calender."

**Two tabs on the ONE page.** Scheduled meetings is the former Agenda, Calendar holds Day · Week · Month. `CalView.agenda` stays the list's value, so `initialView`, the deep links and the data flow did not change, and the view switch simply no longer offers it. A phone opens on the list, a desktop on the week, a phone's Calendar tab on the month. The last tab and grid are remembered per device (`calendar.view.v1`, beside the filters).

**The list always starts today** and no longer follows a picked date; the grid keeps its own date when the tabs flip. A day picked on the sidebar's mini month from the list opens that day on the Calendar tab, and the agenda's old week-by-week arrows are replaced by "Show the next two weeks" and the grid, so nothing became unreachable.

**What is finished moves away from what is coming.** "Coming up" holds only what is not over; "Past and ended" lists it newest first, and is fetched only when first opened (14 days at a time, up to 84) so the normal open costs the same one request. A cancelled date is left out of the past list (it never happened); the grid still draws it. Live rooms lead the list, on their own cards, and are not repeated under their day.

**Ended meetings.** `status: "ended"` on a meeting (older servers send none) beats the clock and a stale live key: never live, never joinable, over even before its scheduled end, a calm "Ended" chip and a muted block, no strike-through because it did happen, not draggable, no clash. A room still open past its scheduled end is not over.

**Visuals.** A gradient hero with today's date, what is left and the next event (Join when open), one card per event with the kind's colour on its edge, date tiles for the days, the page tabs from `AppTabs`, a tinted today in the month grid. On a phone the two tabs drop their icons and count: `AppTabs(expand:)` overflows when one tab is wider than an equal share. The invitation count still shows in the list and the banner.

Rendered at 390×844 and 1440×900, ar / en, light / dark. Not exercised against the real backend's `status` field or in the real web app.
## D-320 — The Studio becomes an edit bay · 2026-11-08 · accepted

The owner asked for a premium, attractive Studio after D-312. The page keeps every tool, key and job flow; its layout and
drawing are new (`records_studio_parts.dart`, the page only wires the new values).

**A dark bay in both themes.** The top bar, tool rail, stage, transport and timeline are dark in light mode too, as in every
video editor: a picture is judged against a dark surround. `StudioBay` derives all of it from the server theme (`heroShade`,
the on-hero ink, `accent2` as the bay's one bright colour, raised until it reads on the deck), so a re-themed platform keeps a
matching bay. The inspector follows the theme, which is what makes light mode look intended rather than inverted.

**Layout.** Wide (`studioIsWide`: ≥ 960 px, or a phone held sideways): an 80 px icon rail, the stage over the transport and
timeline, an inspector of 300 – 380 px. Phones: stage, transport and timeline pinned; the inspector a rounded sheet that scrolls
under them; the tool strip at the foot (it scrolls sideways below 50 px a tool). Keeping the timeline in view while the panel
scrolls is the point of the pinning. The on-screen keyboard folds the bay and strip with `Visibility(maintainState)` rather than
switching layout: a different tree would drop the focus of the name field and close the keyboard again.

**The inspector.** Which tool and what it does, its controls, the summary, the name and Keep / Replace; Undo and the ONE primary
button are pinned under it (`StudioSaveArea` hands out `form` and `actions`). A job takes the whole inspector, because the tools
are off until Another edit and on a phone the job would otherwise sit below the fold. A job with nothing running and a failure
now says so instead of "Saving". Choices are equal-width cells, not chips.

**Timeline.** The track now leaves the handle's width at both ends. Before, a handle at 0:00 or at the end was drawn outside the
scroll area, so a freshly opened Trim showed no handles at all. One clip frame with chevrons (trim: what stays, cut: what goes,
striped), the length on the clip, a time bubble while dragging, and the playhead can be dragged when zoomed. Zoom moved to the
transport so the timeline needs no header row: − ×N + on wide windows, one chip that cycles ×1 → ×16 → ×1 on phones (the cost: no
direct zoom out there).

**Time stays left → right in Arabic** (D-312): the in / out readouts and their buttons, the two split parts and the speeds are
laid out LTR, so Start sits on the same side as its handle. The rest of the inspector follows the language.

**Smaller additions.** The stage dims and says "This part will be removed" while the playhead is in what goes
(`studioStageNote`; not on a Cut just opened, when nothing is chosen yet). A play mark over a paused picture. A meter beside the
"Now X · New: up to about Y" line. Merge shows the open record as row 1 with covers on the rows. Key letters moved from button
labels to tooltips (the hint list stays on web and desktop, now at the end of the inspector).

Tests: `test/ui/records_studio_layout_test.dart` (adds the stage note and a handle dragged from the very start of the track).
Looked at by throwaway renders at 390×844 and 1440×900, Arabic and English, light and dark, with a stand-in picture and no
filmstrip sprite; not seen with a real sprite or a real player, or on a device with the keyboard open.

## D-330 — NextBrain Messages: one conversation model, two kinds · 2026-11-08 · accepted

**Direct chats are per pair and per context** (`d:<low>:<high>:c<course>` or `:o<org>`), not one thread per pair. A teacher and a student with two shared courses get two chats. That is what makes the course filter and the course-level block exact, and a parent's chat says which child it is about. A course group is one row per course (`g:c<course>`); its members are computed from the live roster when anyone lists, opens or sends to it, so no enrolment path needs a hook. `chat_conversations.kind` and `settings` are free, `chat_messages` has `reply_to_id`, `edited_at`, `deleted_at` and `meta`: reactions, edit/delete, voice notes, office hours and announcement mode (phases 3–4) add rows or fields, not tables.

**Link rule, computed on every send** (`services/chat/rules.py`): a chat needs a course, a child or an organization; a lost link ends the chat at once (`composer.state = ended`). A parent's chat is decided by the old `parent.message_teacher` switch, so that kill switch keeps working. Student-to-student needs the teacher's or the organization's `student_dm`.

**Only unread counts are not stored.** Unread = messages after `last_read_id`, one GROUP BY, so it cannot drift; read and delivered are monotonic compare-and-set marks.

## D-331 — The three block levels · 2026-11-08 · accepted

`person` (anyone) is every direct chat between the two in any context; groups stay. `course` (teacher only) is that course's direct chat, its group, and a direct chat in the course's organization, because that was the way around it. `all_courses` (teacher only) is every direct chat and the groups of every course the teacher has now or later. Both directions of a direct chat stop; the blocker sees "you blocked this person", the blocked person only "messaging is off for this conversation" (never the level or reason, reason stays with the blocker). A block is only a row in `chat_blocks`, it never touches an enrolment, and no new chat can be created while one applies. Block and unblock go through `audit()` with `org_id` NULL.

## D-332 — Delivery: events carry the message, ticks are direct-only · 2026-11-08 · accepted

`chat_message` carries the whole message on the stream (no fetch, no timers; the thread keeps a slow `EventOrPoll` for when the stream is down). `attention_changed` is sent only for direct chats and the app counts a group message locally (`AttentionService.bumpLocal`), because a badge re-read per group message per member would be hundreds of `/me/attention` calls. Delivered / read ticks exist only in direct chats. A push is not written to the notifications table: a chat is its own list and a busy group would bury everything else. Presence is online or nothing, no "last seen", because many users are minors.

## D-333 — The chat look and the parent's note · 2026-11-08 · accepted

One design for every role: `ChatHomePage` (list and open chat side by side from 860 px), bubbles from `chat_widgets.dart` on tokens, entered through `ChatEntryIcon` next to the calendar in every role's shell, home header and the org header (a bottom-bar tab would overflow at 320 px with five tabs already there). The parent's "Message the teacher" (D-305) now opens the chat, and the phone number option is gone because in a chat a person shares it by typing it. Hidden while the kill switch is on; the old route stays for older apps and files its note into the chat too, without a second push.

## D-340 — Any answer sheet: four checked pictures, a detection the teacher corrects, nothing used before Confirm · 2026-11-08 · accepted

The owner's brief: a teacher uses ANY answer sheet, even one designed outside the platform, teaches it in a few minutes and corrects a whole class. D-302 ("use your own sheet") already detected a sheet from one picture; it had no review loop, no quality checks per picture and no way to say "the sheet has 50 questions". Teaching is now a guided draft on the server (`omr_sheet_imports`, `exam_0012`): an image of one question, the student ID area, an empty sheet, a filled sheet, in this order, each checked the moment it is sent (blurry, cut off, wrong page, already marked / no marks) with the instruction in both languages (`mlkit/omr/teach.py`). Detection is a pure function of the four pictures and a list of the teacher's constraints: a tap on the sheet (wrong region, missing question, extra bubble, "this is the ID area"), or a note parsed by plain rules in both languages (no model: "50 questions, 4 choices"), so any number of rounds never loses a correction, undo is dropping the last one, and the note echoes what was understood. Anything unsure is drawn on the sheet. Confirm detection saves an ordinary `auto_bubble` template (the D-302 path from there on), reusable by that teacher / organization. Rejected: a heavier model-based layout finder, because a printed lattice is exactly what contours find and a person confirms the result anyway.

Kept from D-302: rectangles and circles are detected from the sheet and changeable by the teacher; a small one-row group (a printed form / version row) is left out by default and shown as unsure rather than becoming "question 51".

## D-341 — A correction run is an exam; every mark keeps its evidence · 2026-11-08 · accepted

The brief's steps 4 to 6 (key, correct, review, results) overlap entirely with paper exams. A run (`POST /bubble/runs`) is an `Exam` with `settings.bubble_run`, one paper section and one private MCQ per sheet question: upload, live progress (`EventOrPoll` on `job_updated`), the review queue, evidence (each page's image and its reading, immutable), results and publishing are the existing code, and the app reuses `OmrScanSection`, `OmrReviewPage`, `OmrResultsPage`. The key lives on `exam_forms` in letters per question; correcting it re-decides every page already read (`omr_setup.put_forms`); a cancelled question is D-245's void; marks per question are on `exam_questions.points` and each attempt's snapshot. "Several correct": mode `any` (one correct choice among the listed ones earns the mark, `accept_any` on the key — a flawed question) or `all` (the student shades exactly those, `mcq_multi`). Several versions: one key per form; the teacher can tap a printed version row on the sheet during review (it is then read like an answer), and a sheet without one goes to review where a person chooses the version, never a guess. A marked key sheet is read back as a PROPOSAL with anything unclear highlighted; nothing is saved until the teacher saves the grid.

## D-342 — Marks reach a Data Lab column only with a person's confirmation · 2026-11-08 · accepted

`preview` shows the mark before and after per student, scaled to the column (rounding 0.5 when the scales differ, D-243's rule), and blocks a student whose sheet still has an open review item. `apply` re-computes the values on the server (the app sends only what it was shown), writes each cell with `expect_old` and the real person's id through the existing gradebook route, needs `confirm_overwrite` when a row replaces an existing mark, and reports a cell that changed since the preview instead of overwriting it. Excel stays the results page's export.

## D-343 — Learning from the teacher's corrections, inside a fence · 2026-11-08 · accepted

Every resolved bubble review item on an own sheet records, per bubble, its fill level and what the teacher said (`template.learned.corrections`). `learn_tune` turns repeated, consistent corrections into this sheet's faint-mark levels, only inside the default band and never past a contradicting correction, so an in-between mark is still asked about. The server shows "this sheet improved from N corrections" where it applies. Rejected: lowering thresholds across all sheets from a global model; a pooled number would hide the one sheet whose marks are faint on purpose.

Measured on the owner's real phone photos (bench/omr/teach_real.py, the empty sheet being the platform's own render since none was photographed): on the papers never used to set a threshold (`real_heldout`), 8 of 10 photos read, 351 of 400 questions right, 49 sent to review, 0 wrong auto-graded; the 2 others are asked for a retake.

## D-356 — Exam Hub front: one wizard, one hub, printed identifiers, our own PDF replay · 2026-11-09 · accepted
Exams were reached through several lists, a quick form and a separate paper setup, each ending somewhere different. The client now has ONE hub (`ExamHubScreen`: Creation, Results & Correction) and ONE new-exam wizard (`openExamCreateWizard`, one server draft however often the teacher goes Back); the older screens stay reachable from inside those flows, nothing was deleted. The hub only opens flows and re-reads its list on return. Where two parts had built the same thing the better one stayed: one Excel totals import (`openHubDegreesImport`), used by the hub and by Get Result.

Correction decides from the exam itself, inside `correctionRouteOf`, so every caller agrees: an online exam goes to the marking screen, a paper exam to scans or bubble sheets. An exam older than the setup route reads `delivery: online` whatever it was, so an exam with paper sections counts as paper.

The wizard records what it planned in `settings.paper_plan` and Deliver opens on it (personal copies or versions), switchable; versions are made on Finish, and a draft published from the list that never got there is offered them in Deliver. What is printed under a student's name is `settings.print_identifiers`, chosen per exam, and is separate from the identifier sheets are matched on (at most four; national id, phone and email cut to the last four digits).

Deliver's preview replays the actual pages of the actual PDF with our own painter (`paper_page_replay.dart`) rather than the `printing` package, which adds two lock entries and loads pdf.js from a CDN at run time. Cost: one more renderer to keep in step with the paper builder, which a test covers.


## D-380 .. D-382 — Certificate fonts (2026-11-09)
Full text in `../back/docs/DECISIONS.md`. D-380: a font chosen on a certificate field is kept through save, reload, preview and the issued file (legacy keys resolve to their family, an unknown font is refused with its name, never swapped). D-381: the picker `cert_font_picker.dart`, the renderer's catalog (`GET /exports/layout/fonts`) as the only list, a font not bundled is loaded from the server. D-382: Reem Kufi and Aref Ruqaa stay out of the catalog (the PDF renderer cannot join them); a converted design names the replacement.

## D-384 — The certificate template gallery · 2026-11-09 · accepted

The server's template collection (back D-383) opens as a full page, `studio/cert_template_gallery.dart`: real thumbnails per card (four at a time, skeleton, session cache), category filter, Arabic / English toggle, one tap to use. A larger preview offers another colour; by default a template keeps its own colours. A template fills the other language's page too when that page is empty, never overwriting work.

## D-385 — Studio keyboard on the web and desktop

The engine's keys lived in the canvas Focus only, so they stopped working after a click on the toolbar and acted on the hidden canvas after a language switch, and there was no save, zoom, Tab, group or list of keys. `lib/design/studio/studio_shortcuts.dart` is one table of commands dispatched through `AppKeyboard.keyClaim`, so it is gated by `AppKeyboardSupport.enabled` (nothing on phones), fires only for the canvas on screen on the current route, never while an `EditableText` has the focus, and leaves plain keys to a focused control. Ctrl on Windows, Linux and the web, ⌘ on macOS. Hosts give Ctrl+S with `StudioKeyboardScope(onSave:)`. Groups (Ctrl+G) are new: selecting a member selects the group, the layers panel still picks one element; stored in the element's `group` key.

## D-386 — A required student photo instead of a grey placeholder

The renderer drew a grey silhouette for any recipient without a photo, in issued certificates too. Now an issued certificate never draws a stand-in: `render_design` draws nothing unless the variables carry the preview flag (`PHOTO_SAMPLE`), and the stand-in is a marked "SAMPLE" image (design previews only). A design's photo is **required by default**; the engine studio can mark one `photo_optional` (there was no such setting before), the classic designer's photo stays required. The server enforces it with 422 `photos_required` on every issuing path (batches, saved lists, re-issue, the course paths) and checks each recipient's photo can be read before rendering; a recipient's photo is stored in the issued row's `values` under the server-owned key `_photo_url` (never returned, never set from the client's values, only from a URL `POST /photos` returned). The issue flow gains a Photos step between Who and Preview, shown only when the design holds a photo.


## D-387 — Certificate studio workspace: top bar, rail, inspector, canvas first on a phone · 2026-11-09 · accepted
The studio was a screen of stacked strips: an AppBar, two equal-weight language bars, a toolbar in a card, a page crowded against a carded panel. It is now one workspace (`cert_engine_shell.dart`, plain values and slots): a top bar with the name, one save status, undo / redo, zoom, the language switch, Preview and one primary action; a rail (Templates, Elements, Fields, Images, Layers); the page on a quiet backdrop with a raised shadow; an inspector. Below 720 px the canvas comes first with a bottom tool bar and a non-modal sheet (a modal sheet would hide the page being edited); 720–1180 px the tool panel floats over the canvas so the page keeps its width.
`LayoutCanvasEditor` is shared with the export designer, so the workspace is an opt-in: `canvasOnly` draws just the canvas and hands the host a `LayoutEditorHandle` (controller, add, field focus). The export designer is untouched. The Templates tab is one slot (`CertTemplatesSlot`) and the top bar has one slot for a keyboard button, so the gallery and the shortcuts sheet land without touching the layout.

## D-388 — The inspector answers the selection, and folds the rest · 2026-11-09 · accepted
One long property list made a person scroll past borders and shadows to reach the position. `CertInspector` shows content, text style and position first for a text, and folds spacing, background and border, effects, arrange and layer; a line, a box, an image or a QR code shows only what it has; several elements show align, distribute and match; nothing selected shows the page. Every capability of `LayoutElementProps` stays reachable, rules and computed values included. Colours are one row that opens in place. Alignment is drawn physically (left on the left, in Arabic too) because the page is physical. The certificate's text chips insert the certificate's own values, where the shared chips offered the export designer's.

## D-389 — One primary action: Save, then Issue; a saved-elsewhere state that stays visible · 2026-11-09 · accepted
The top bar has one filled button. While there is something to save it is Save; when everything is saved it becomes Issue (the standalone flow, hidden by `certificates.standalone` and for a design attached to a course certificate, which the course issues). A refused save used to exist only as a dialog: cancelling it left no trace. The status now stays red ("Saved elsewhere: tap to resolve") until the person decides, and tapping it reopens the same dialog. The preview draws the server's PNG as a sheet on a desk, with a skeleton of the sheet while it renders.
## D-375 — Messages delivery, tried with two real clients · 2026-11-09 · accepted
The chat had never run against two signed-in people. `tests/org_v2/e2e_chat_two_clients.py` now drives two users and a second device through a real uvicorn, real Redis and Postgres: send, the SSE stream, receipts, unread, typing, reconnect with Last-Event-ID, a retried send, racing sends, an attachment, paging, a group. Before the fixes it failed on six counts, all real:

Typing and presence went through `emit`, so they sat in the 100-entry replay list: after a reconnect the other side saw a ghost "typing…", and a burst of typing pushed real messages out of the list. They are now live only (`realtime._ephemeral`), never replayed. Sending moved the sender's read and delivered marks up to their own message, so a message that arrived a moment earlier was counted read without being seen, and the other side's tick said read for something nobody read. The sender's marks no longer move on send. `read` on another device said only "something was read"; it now says how far and what is still unread. The chat's `last_message_id` is set with a compare-and-set, like the read marks, because two sends in flight can commit in the opposite order (the race did not show in this run; the code was still unsafe).

`last_message.body` of a photo or file with no caption was the Arabic word from the push text, shown in an English app too. It is the message's own text now, empty for a bare attachment; the app names it.

## D-376 — One controller per conversation, kept for a while · 2026-11-09 · accepted
`ChatHub.acquire` / `release` hands out ONE `ChatThreadController` per conversation, reference counted. Two screens of the same chat (a push tap on an open chat) used to register two controllers: the second replaced the first, and when it closed the first stopped hearing events. After the last screen closes the controller stays (eight idle at most, least recently used out) and stays current, so reopening paints at once, and a message still going out finishes. Every counter is idempotent by message id, because a stream replays the last ten minutes on every fresh start: before, each page reload added those messages to `unread` again. A sync fetches from the last fetch, not from the newest message on screen, so a live event that arrives ahead of a gap no longer hides the gap.

## D-377 — Sending: serial, four states, nothing typed is lost · 2026-11-09 · accepted
One message of a chat is in flight at a time, oldest first, so the server's order is the order typed; two quick sends used to race. States: `sending`, `queued` (offline, in the persisted outbox, goes out on reconnect), `sent` / delivered / read from the marks, `failed`. Failed keeps the text across restarts with tap to retry and a delete; a failure only for lack of a server (the phone thought it was online) also retries by itself on the next reconnect. Before, anything the server refused vanished from the outbox, and a 5xx span "sending" forever. Files upload once: a retry reuses the ids. A web page's picked bytes die with the page, so such a message shows as failed instead of going out without its attachment. Another account signing in on the device never inherits the outbox (it used to send it as the new user). Drafts survive a cold start: the composer used to be built before the drafts were read and then saved the empty text over them.

## D-378 — The conversation holds its place · 2026-11-09 · accepted
The list is a `CustomScrollView` with a center sliver. While the person reads history, a new message arrives below the anchor and nothing on screen moves; reaching the bottom folds the anchor away. Nothing is marked read while scrolled up; the jump-to-latest button counts what came in meanwhile, and the first unread message of an opened chat gets a "new messages" line. Typing dots are only drawn at the bottom, and a message clears them. Enter sends and Shift+Enter is a new line on the web and desktop (by platform, not by width, so a phone's Enter stays a new line); an IME composing keeps its Enter.

## D-379 — Inbox and desktop · 2026-11-09 · accepted
The inbox puts what needs the person first: message requests (one row, opening a sheet of cards with Accept · Decline · Block, D-370), then "New" (unread and not muted), then "Earlier"; filters and search show the rows as they came. From 860 px it is a real master-detail: the list beside the open chat, the conversation kept in one 860 px reading column with its composer, bubbles capped so they stay bubbles, and "start a chat" in the empty pane. A request I received puts Accept · Decline · Block where the composer was. Bubbles run together (tight inner corners), and a failed bubble says so in red with its two actions. Presence is an `EventOrPoll` that stops in the background instead of a bare timer.

## D-370 — Message anyone: requests for people with no link · 2026-11-09 · accepted
The owner asked that anyone can message anyone. A chat still needs a relationship to be direct (course, parent/own child, organization); everyone else goes through a message request: `POST /chat/requests` holds the first message, the receiver accepts / declines / blocks (`/requests/{id}/…`), nothing more is sent until accepted, and declining is quiet (the sender keeps reading `pending`). A request is `chat_conversations.request_state` (migration 0069) with key `d:<a>:<b>:r`, not a second table. Student ↔ student never goes through a request; it stays with the per-teacher and per-organization `student_dm` switches. An adult with no link (parent, teacher, org staff, org admin, admin) cannot find or request a student unless the platform setting `CHAT_ADULT_TO_STUDENT_REQUESTS` is on (default off, fail-safe: many students are minors; 403 `chat_student_requests_off`, one test `rules.adult_to_student_closed` for search and send); the super admin keeps support reach, and a student may still request an unrelated adult. Every block level covers a request (`_direct_covered`: no-context chats have no course to escape to). A waiting request never counts as unread and its receiver sees no presence or ticks either way. A relationship that appears later (`chat.requests` on or off) turns a waiting request into an ordinary chat on the next send. Kill switch `chat.requests`; caps `CHAT_REQUESTS_PER_DAY` (10).

## D-371 — The New message sheet · 2026-11-09 · accepted
`GET /chat/people` feeds one sheet (`chat_new_message.dart`): with no text, recent people and suggested links; with text, links first then anyone by name or @username (two letters, at most 20, no paging, 60 searches a minute per person). Each row says how the chat starts (`reach.state`: thread · direct · request · request_sent · request_received · unavailable, with the reason in both languages when it is impossible), so nothing is refused after the person wrote. Only a confirmed @username is shown or searched: an auto-filled one is the e-mail's local part (D-071). E-mail, phone and national ID are never returned or searched. A request is written inside the sheet, so the conversation screen never has to invent a first-message state.

## D-372 — One thread per person; parent and own child · 2026-11-09 · accepted
Starting a chat with no context named reuses the most recently active thread they can write in, and otherwise a link no block covers: before, a course-level block made a no-context start open the blocked course's thread with a dead composer, and a pair with two courses got two threads and two rows in the contact list. `people` shows one row per person. A chat with a named course or organization still means that context. Parent ↔ their own linked child is a link (`…:f`), which it was not before.

## D-373 — Refusals say why, before the person writes · 2026-11-09 · accepted
`composer` carries `reason` / `reason_en`; `rules.STATE_TEXT` is the one list. A stranger's start answers `chat_request_needed`, not the old `chat_no_link` "you can no longer send messages here" sent to someone who had never written.

## D-374 — Messages in every role's profile · 2026-11-09 · accepted
`ChatEntryTile` (next to `CalendarEntryTile` in `calendar_entry.dart`) is the row with the attention feed's unread count, in the student / teacher profile, the parent and admin More pages and the organization settings. Requests are deliberately not in the badge: the calm place for them is the inbox line (`GET /conversations` → `requests`).

## D-360 — One premium language: organic gradient everywhere, one collapsing header, side sheets, focus mode, one number field · 2026-11-09 · accepted

**Context.** The owner asked for one premium design language on every screen, role and platform. This replaces the "gradient as a touch" rule of D-180.

**Decision.** `lib/design/app_mesh.dart` builds every gradient from a main colour and its companion hue: layered radial blobs for large surfaces, a multi-stop angled blend for small fills, a faint wash for cards. Blob positions are random-looking but seeded, shaders are cached in unit space, and fills are moved until the on-hero ink keeps AA. `AppHeader` is the one page header; it listens to the Scaffold's own scroll notifications, so a page needs no slivers. It reacts to scroll direction, animating between open and compact. `showAppSheet` and `showAppModalSheet` are a floating side panel from 700 px up and a refined bottom sheet below; they open on the nearest Navigator, as before, so tab-scoped providers stay readable. `AppFocusMode` folds the shell's sidebar and top bar and is remembered per device. `AppNumberField` is for real quantities only, never phones, codes or IDs.

**Kept from D-180.** No opaque fill behind body text, forms, lists or dense tables; no gradient values in a screen.

## D-400 .. D-403 — Certificates: a non-user's instructor, template colours, wording library, modern templates (2026-11-09)
Full text in `../back/docs/DECISIONS.md`. D-400: a standalone batch with a recipient who has no account, on a design that prints the instructor, needs the name: the inline `IssueTeacherField` at the preview step (blocks Issue, scrolls to the field), a prompt on a saved list, the server enforces it with 422 `teacher_name_required`. D-401: curated palettes per template plus a custom colour (`cert_template_colours.dart`), painted into the page by the server with inks fitted to it; `LayoutDesign.extra['template']` remembers what the template drew, so the studio's Template colours panel changes only what the person left alone. D-402: the wording library, the rail's Wordings tab (`cert_wordings_panel.dart`), `GET /certificate-designs/preambles`. D-403: the twelve `mod_*` templates.
## D-410 .. D-412 — Premium certificate fonts (2026-11-09)
Full text in `../back/docs/DECISIONS.md`. D-410: the catalog grows to 40 more OFL families, the renderer's files only (no app bundle or web build growth); `GET /exports/layout/fonts?include=all`. D-411: harakat are kept and placed by the renderer. D-412: the picker (language tabs, style groups, search) and per-row lazy loading of the regular file only.
## D-420 — Public certificate verification: Real or Fake first, a number or a QR code, an expiry that the server judges · 2026-11-09 · accepted

**Context.** `/verify/<token>` existed for the printed QR only, with no way to type a number, no expiry and an answer that named only valid or revoked. The owner asked for a verification tab: type the number or scan, and read expired or not, fake or real, and every detail.

**Decision.** (1) `/verify` is a public entry form (`cert_verify_page.dart`, kill switch `certificates.verify` on the in-app entries only: a printed QR always works), reached from the sign-in page, Profile, My certificates, Certificate designs, and the admin, parent and organization settings. (2) A typed or scanned value goes through `parseCertCode`: a link counts as ours only when it is https on `nextbrain.site` / `www.nextbrain.site` with the exact path `/verify/<token>` or `/app/verify/<token>`; anything else is shown as a foreign code with its host as plain text and is never opened or sent. The scanner is the join-code scanner, `openQrScanner`, imported deferred so web does not load it. (3) `cert_issued.expires_at` / `cert_issue_batches.expires_at` (0070, NULL = does not expire, so every existing certificate reads as not expiring). The issuer sets it on the preview step; a re-issue keeps it, and re-issuing an expired one asks for a new date. The state is computed from the server's clock only. (4) `GET /public/certificates/lookup?number=` beside `/verify/{token}`. A number is guessable, a token is not, so the number answer is smaller: no image and no results (grade, score, rank). `EF-…` numbers are built from course, certificate and student ids, so their name is masked as well. (5) A course certificate older than `cert_issued` is found through its `certificate_issuances` row: otherwise a genuine old paper would read as fake. (6) Per-address limits on `auth_attempts` with the trusted-proxy address: 60 / min on the token route, 20 / min and 40 misses / hour on the number route.

**What "real" proves.** Numbers carry no checksum and certificates no signature, so "real" means a matching record exists in NextBrain's database and nothing more: it cannot tell that the words on a paper or PDF were not edited around a real number. The page says so and asks the reader to compare the name and details. The only integrity check is the number's shape and alphabet.

**Consequences.** `valid` is now false for an expired certificate, so an app older than this reads an expired one as "revoked" (no certificate has an expiry until an issuer sets one). `course.id` left the public answer. The expiry is not printed on the certificate unless the design has a column for it. Lists issued from the saved-lists page have no expiry control in the app yet; the API takes it.

## D-540 — Messages: reply to a message, copy it · 2026-11-09 · accepted
A message can quote an earlier one of the same chat (Reply on hover, a swipe on touch, the message menu; Copy beside it). The server had the `reply_to_id` column since the first round; `POST …/messages` now takes it and every message payload (list, send answer, `chat_message` event) carries `reply_to` {id, kind, body (200 chars), sender_id, sender_name, deleted}, fetched for the page in one query. A quoted id that is gone or from another chat is ignored rather than refused: nothing typed is lost over a quote. No migration. Tapping a quote scrolls to the original, loading older pages if needed, and tints it for a moment.

## D-541 — The chat look (replaces the look of D-333 and D-379) · 2026-11-09 · accepted
Judged against WhatsApp Web, Telegram and Teams in the real app. Own bubbles are a calm tint of the brand on the card colour and the other side's the card colour, over a page tinted very slightly with the brand: the old solid brand bubble with white text was unreadable on the app's gold, and long reading text must not sit on a block of colour. Inks are computed from the server palette with a contrast floor (`chatBubbleInk`, `chatReadableOn`). Runs read as one block: tight inner corners, a tail on the last bubble. The time sits in the bubble's corner on the side the text ends (a right-to-left message in an English screen ends on the left) and the text keeps room for it with an invisible copy, so a short line never wraps for the clock. Pictures fill the bubble (several become a tidy grid, a caption goes under), a file is a typed tile. A deleted message says so instead of an empty bubble. Links are found and open outside. Desktop: reply and more buttons appear on hover beside the bubble (no reflow, the slot is always reserved), words are selectable, and menus are real popups at the pointer; touch: swipe and long press. The hover buttons are 36 px: they exist only for a mouse and every action is also in the keyboard-reachable menu.

## D-542 — The inbox is by time, not by state · 2026-11-09 · accepted
Deviates from D-379's "New / Earlier" sections. WhatsApp, Telegram and Teams keep one chronological list with pinned chats on top and an Unread filter, and sections moved a chat when it was read, which made the list jump under the pointer. Rows are two lines (the course or child moved to the header and to a suffix on the name for a parent's chat). Roles and courses left the filter row for one "More" sheet: four chips everyone understands. The split follows the pane, not the window (the role's sidebar takes room): from 760 px, the list at 30 % between 340 and 420 px, and the two header bars share one line.

## D-543 — A conversation is a full-screen place on a phone · 2026-11-09 · accepted
A chat opens on the root navigator, over the role's bottom tabs, and hides the floating assistant bubble, which sat on the composer. The reading column of a wide screen went from 860 px to 1120 px (bubbles capped at 620 px): a 860 px column left dead sides on a large window while the pane was already narrow enough to read.

## D-544 — A chat opens where the new messages start · 2026-11-09 · accepted
With ten or more unread messages the thread opens on the first of them, under the "new messages" band, rather than at the very end; reaching the end marks them read and a chat left halfway keeps its count, the honest reading of "read". The first page asks for enough messages to hold what is unread. The typing dots open upwards as they arrive, so the last message slides out of their way. Messages are keyed by id in the list, which also fixes a real bug: without keys a new message reused the row's state and a picture bubble could show another message's image.
## D-520 — The phone as a person's companion device (Teams' "Add a device") · 2026-11-09 · accepted

**Context.** The owner: "when open / join meeting can use the cam or speaker or mic of mobile... when the user open the app from mobile open the request... mix between mobile captures and another device in web and stream it to participants and record... premium business logic like the Microsoft Teams".
**Decision.** From the pre-join page or the room's bar (web / desktop, never on a phone) a signed-in person picks camera, microphone and / or speaker. The server keeps one `live_companions` row per person (`services/live_companion.py`, migration 0071) and rings the phone: a visible high-priority push (android / ios tokens only, so the asking browser never notifies itself) plus the real-time event, and the app asks `GET /me/live-companion/pending` when it opens, resumes or signs in, so whatever is pending shows at once as the incoming-call screen. Accepting returns a LiveKit token for `companion:<primary identity>` that publishes exactly the requested sources, subscribes only when the speaker was requested (client: audio only) and never the person's own mic. Every client folds that identity into the person (`lib/features/shared/live/companion/`): one tile, one name, one count; the host's mute / remove / permissions reach the phone from `services/live_controls.py`; the LiveKit webhook ends the row when the phone or the person leaves. The QR / link fallback is `/s/companion/<secret>` (the secret stored hashed): it opens that same person's request and nothing else, `ask` says `pushed: false` when no phone is signed in.
**Rejected.** A separate participant for the phone with a duplicate tile (rejected by the brief); merging the phone's media on the server (no such path in LiveKit: an egress composite can only tile participants); a `hidden` participant (hidden tracks are not delivered to others).

## D-521 — What the companion obeys · 2026-11-09 · accepted

**Decision.** The phone is the person, already inside: a locked room does not stop it (the lock admits no NEW person; the person is present, as a student already in the attendance may come back). Everything else applies: the person must be in the LiveKit room to ask and to accept, a removed person's next ask is 403, an ended run or meeting refuses, what the host took away from the person (a revoked mic, mute-all without allow-unmute) is removed from the phone at Accept and whenever it changes, and a host's own phone counts as the host in mute-all. Guests have no account, so no phone. One companion per person: a new request ends the previous. Kill switch `live.companion` (403 `feature_disabled`).

## D-522 — Device handover and echo safety · 2026-11-09 · accepted

**Decision.** The moment the phone starts publishing a microphone or camera, the web's own turns off; the moment the phone leaves, the web's previous state comes back and a notice says so (`CompanionHandover`). The phone's speaker means the web mutes the room's audio elements; the track stays subscribed so a recording running on this device still has it. The web never plays its own phone's microphone, in any mode. Echo: Teams mutes a companion by default because the phone sits next to the laptop. Here the person explicitly asked, so what they asked for is on, but the sheet warns whenever the sound is split across two devices (mic on one, speaker on the other), the one combination no echo canceller can help with, and it recommends one device or a headset. Phone mute is the phone's mute: the web mic does not come back while the phone is still connected.

## D-523 — The phone in recordings · 2026-11-09 · accepted

**Decision.** Client recording (D-098, web): `_syncRecordingScene` draws the person's tile with the phone's camera (`ParticipantTrack.companion`), and `_attachRemoteAudioToRecorder` adds the phone's voice like any remote track. The web recorder keeps subscribed to its own phone's tracks though it does not play them. Server composite egress: the phone joins with the person's own name, so the composite's tile says the right name (the person's web tile has no video then, so no second tile), and the audio mix has every participant. The `media` engine follows the host identity's camera only; it does not pick up a host's phone camera (its voice is captured by the room mix). Documented as a limit; `composite` is the default engine and `client` the default mode.

## D-524 — The phone's camera in the background · 2026-11-09 · accepted

**Decision.** On Android the microphone stays alive through the existing `LiveCallService` (foreground service, type microphone). The camera pauses when the app goes to the background and resumes on return (this device's tile shows the avatar meanwhile), as Teams does on a phone: a `camera` foreground service would add a new permission path and could not be verified on a device in this round. Not done: a `camera` foreground service type, iOS background capture (not allowed for third-party apps without a special entitlement).
## D-500 — A bubble sheet from ONE picture, no corner marks; the lattice is its own calibration target · 2026-11-10 · accepted, partly verified

The owner: "creating a bubble sheet is very bad ... it must not need the black squares in the corners; detect the questions, their options and the student identifier automatically". Both exam wizards offered "Upload a custom layout" (`omr_template_learn`, four corner marks required) and "Use your own sheet" (D-302, one photo, but the page was found from the paper edge only). Both teacher buttons now open ONE flow: `openBubbleSheetFinder` (front `paper/bubble/bubble_one_photo.dart` + `bubble_import_screen.dart`) → `POST /omr/sheet-imports/{id}/sheet` → `mlkit/omr/sheet_finder.py`. The super admin's template library keeps the corner-mark learner for printable NextBrain sheets; the four-picture draft (D-340) still finishes for drafts already begun; a written answer table is one tap away (D-302 page).

How it finds a sheet: bubble-like contours anywhere → the lattice's own axes (neighbour directions modulo 90°) → a homography fitted so every run of bubbles is straight (damped least squares on the rows and columns, robust to strays) → the page flattened from the lattice, the paper's edge only bounding how far it goes → blocks with holes (a question with fewer options keeps its count), blurred lines recovered by the page's OWN average bubble (`Evidence`), fragments merged, lines grown while the print continues → roles (10 rows of digits; when geometry cannot tell, the glyph inside the bubbles repeats DOWN an answer column and ACROSS an identifier row) → sideways from the lattice's shape, upside down from the question numbers getting wider down a column (9 → 10) plus the heading and the ID position, right-to-left from the side the numbers are printed on. Anything weak is an `unsure` item drawn on the sheet; a picture with bubbles against its edge, bubbles the layout does not explain, or shapes reaching past a page is flagged "part of the sheet is outside the picture". One-tap fixes are constraints like D-340's (rotate, numbering direction, choices per group, missing / extra bubble, missing question, drag the ID box). The reader keeps the photo's own proportions (`read_auto`): a one-picture frame need not have the paper's aspect.

Measured (`bench/omr/sheet_finder_eval.py`, `bench/omr/teach_real.py`; all real photos are ONE sheet design, ours): layout exactly right (50 questions × 4, 10-digit ID) on the held-out photos 6 / 10 as taken and 6 / 10 with the corner squares painted out (the old detector: 1 / 10); the held-out set was looked at during development (two pictures, one earlier run), so it is not a clean hold-out any more. Reading those layouts: 0 wrong automatic marks everywhere. The four-picture flow's real-photo bench after the reader change: held-out 9 / 10 read (was 8 / 10), 383 / 450 right, 67 to review, 0 wrong; dev 6 / 9 (was 5 / 9). Weak, stated plainly: two held-out photos come out wrong WITHOUT a photo warning (40 questions; an ID not found, shown as "no student ID area" to fix); the "outside the picture" warning also fires on most good photos of stacked papers; 2 of 6 exact layouts are refused by the reader on their own photo (a retake, never a wrong mark); the synthetic hold-out of other publishers' designs gets only 2 of 4 clean scans exact. Not seen in the real web app: the local stack's core API never finished starting on the shared machine.
## D-510 — Background removal on the device, no model and no server (supersedes D-390)

**Context.** The owner asked for a free tool without models; D-390's model was never deployed and its weights' dataset forbids commercial use.
**Decision.** `lib/design/image_background_engine.dart` (plain Dart, unit-tested on synthetic pictures) does it all on the device; the server route, service, hub role, model entry and throttle scope are gone (back `docs/DECISIONS.md`, D-510). The kill switch `image.background` stays. Because nothing is sent any more, the tool is no longer hidden for guests or "view as"; the kill switch alone hides it.

## D-511 — The Background tab is the mode

The tool has its own tab on phone AND desktop (desktop used to stack it under the crop controls), because a tap on the picture has a different meaning there: on Adjust it only drags, on Background it picks. The first visit reads the picture and shows the result at once (transparent, or white where `allowTransparent` is false); the Original tile goes back. The panel order is hint with undo / redo / start over, tool, sliders, then the replacement tiles.

## D-512 — What the border says, and what a tap means

Border colours are clustered in Lab, with the upper part weighted most: a colour must have a share of itself in the upper half, so a shirt along the bottom edge is not background (a floor or a table is not either; one tap removes it). If the clusters explain less than 35 % of the border the picture is left whole and the person is told to tap. A flood accepts a pixel within the colour's tolerance, or within a wider reach when it is close to its neighbour (gradients, vignettes). A tap on what is kept removes that connected colour; a tap on something removed brings it back. "Also inside shapes" also takes the colour where it is not connected, and turns on by itself for flat graphics (logos), never for photos, where it would take the whites of the eyes.

**What real photos added.** On a plain background (the border's main colour varies little) the background enclosed by the subject also goes, such as the gap between an arm and the body: only connected areas that match the colour tightly and cover at least 0.15 % of the picture, so the white of an eye stays. Two guards keep a wrong guess from eating the picture: a border whose main colour varies a lot (a mottled studio backdrop, an old photo) is not guessed at all, and on a border that is not perfectly plain, an automatic result that keeps under 18 % is tried again with a tighter range, twice; if it is still under, the picture is left whole and the hint asks the person to tap what should go.

## D-513 — One small mask, any resolution

The mask is made at 640 px on the long side and is never remade at a larger size; the outline becomes a narrow band where each pixel is explained as a mix of the local background and subject colours, which gives alpha and the pixel's true colour (no fringe of the old background). The colours on each side come from beyond the edge's own blur. The screen shows 1400 px; the file is rendered from the same mask at up to 2400 px when the person presses Use photo, so what was seen is what the file gets. Generators that yield often run on an isolate on a phone and in 10 ms slices on the web, one job at a time, changes folded into the next run.
## D-560 .. D-562 — Student / parent / teacher pages under the one shell chrome (premium round 2, sweep 1) · 2026-11-10 · accepted

**D-560 — A `useWebCard` page runs the full height and shows the pattern only in a real margin.** Under the shell's
sheet (D-551) the old card kept a 12 px margin top and bottom, so every scrolling page stopped short of the window's
edge and its content was cut by an invisible line, and the page pattern showed as a thin noisy strip beside a card of
the same colour. `BasePage(useWebCard: true)` now draws the body edge to edge in height, at its width role, and paints
the pattern only when each side margin is at least 64 px (a 1920 window around a 1440 page).

**D-561 — One title per screen on a tab's first page.** The analytics pages' own 28 px title (`AnPageHeader`) repeated
the shell bar's title right under it: under the bar only its sentence ("How your learning is going") stays, a little
larger. The parent tabs drew the calendar and messages again under the bar: only on phones now (the bar carries them
from the rail up). Analytics (student, course) take the `wide` role like the teacher's, the course lists' filter keeps
whole labels (its own row below 900 px, up to 520 px beside the search), and the home's "Join your university" card
and its error banner sit on the same 20 px inset as the sections above them instead of 20 px wider (student) or a
narrow 860 px column (teacher).

**D-562 — A late Firebase never leaves a grey screen.** `RemoteConfigService` read a `late` field that is set only
once Firebase has started; when start-up timed that step out (a slow device or network) the app root's first build
threw and the web app stayed grey. The getters now answer the defaults until it is ready.

## D-580 — One page transition for every route, a tab entrance · 2026-11-10 · accepted
`lib/design/app_motion_kit.dart`. Every route (the 61 named routes in `main.dart` moved from a 300 ms `PageRouteBuilder` fade to `MaterialPageRoute`, so the theme decides) uses `AppPageTransitionsBuilder` on Android, web, Windows, macOS and Linux: the new page fades in over the first 70 % while it glides 24 px in from the reading end (right in English, left in Arabic), 300 ms in, 240 ms back; the page under it stays still, because fading or sliding it shows the empty window behind. iOS keeps `CupertinoPageTransitionsBuilder`: the native slide carries the edge back swipe, which the named routes now get as well (they had none as page-route-builders). Reduce motion: `AppNoPageTransitions`, with a ZERO duration (the old `_NoTransitions` kept 300 ms of invisible delay). A shell tab coming to the front fades in and rises 8 px in 220 ms (`AppTabEntrance` in `LazyTabStack`); the tabs of the shell's first frame appear with the page. Dialogs from `showAppDialog` settle from 96 % (`AppPopIn`); sheets keep Material's slide.

## D-581 — Numbers count, once · 2026-11-10 · accepted
`AppCountUp(value, memoryKey:)` replaces the Text of a figure in the shared tiles (`AppKpiCard`, `HomeHeroFigure`, the home's stat pills / rows, `AppTrendTile`, `AppStatTile`, `AppHeroStat`, the donut's total; `AppRing` counts with its fill). It finds the ONE number in the display string and keeps its prefix, suffix, grouping and decimals ("EGP 1,240", "84%", "1.2K"); a string with no number or two ("12:30", "3/5", a date) is drawn as is. Counts up 900 ms the first time, glides old → new in 600 ms on a change. The memory (last value per key, bounded to 400) makes a rebuilt, refreshed or revisited tile glide from what it showed or stay still, never count from zero twice. While it counts, the final value is laid out invisibly under the moving one: it holds the width (nothing around it shifts) and it is the only text in the semantics tree, so a screen reader hears the final value; `find.text(final)` still finds one widget in tests. Count badges (`AppCountBadge`, the shell's tab badges) pop once when their number changes, never on the first build. Latin digits as before.

## D-582 — Entrances, charts, fills, press · 2026-11-10 · accepted
`AppReveal(index:, group:)` (and `HomeEntrance`, now a thin wrapper of it): fade + 12 px rise, 50 ms stagger, only for the first 8 indexes (12 on a home), and each `group:index` plays ONCE per route (an `Expando` on the ModalRoute): a refresh, a skeleton → content after a pull, a lazy tab revisit or a scroll back never replays it. Applied to the KPI grid, the course card lists (`CourseCardSliver`) and the homes. Charts draw in once (`AppDrawIn`: the sparkline from the reading start, bars from the baseline, the donut sweeps; the hot-bar label waits for the end). Progress fills from 0 then glides (`AppFill`: `AppProgressBar`, `AppRing`, the course card's progress). The skeleton crossfades into the content (`AppSkeletonSwitch` in `AppStateView`, `AppAsync`, `AppKpiCard`): keyed only on "skeleton or not", so a change inside the content never remounts it. Press feedback: `AppButton` 0.97, tappable `AppCard` / `AppStatTile` / `AppTrendTile` 0.98 (`AppPressScale`, released when the finger moves 10 px, i.e. a scroll). Every moving part sits between two RepaintBoundaries so a frame re-records only that widget; nothing loops.

## D-583 — 3D only on the hero surfaces · 2026-11-10 · accepted
`AppTilt` on `HomeHeroCard` (max 2.5°, glare), the highlighted `AppKpiCard` (glare), the other KPI cards and `CourseListCard` (max 3°). Mouse: the side under the pointer sinks (perspective 0.0011, a wide surface tilts less: min(max, 1300 / width) degrees), the card lifts at most 5 px, a grounded two-layer shadow (ambient + key) fades in under it, and on the hero a soft light follows the pointer. Touch: a press sinks it 1.5 % toward the finger. `AppTiltLayer` shifts the hero's ring and the course cover (over-scanned 4 % so its edge never shows) against the tilt: parallax. At rest the transform is the identity, so text is drawn exactly as without it. Not applied: the page heroes (`AppHero`, a tilting page header reads as a gimmick), the nav's active item and the empty states (a one-shot settle only).

## D-584 — Personal control stays one switch · 2026-11-10 · accepted
Reduce motion in Display & reading stays ON / OFF (no Full / Reduced / Off: with every effect one-shot and short, a middle step would differ by too little to choose). Its subtitle now says what it stops (page transitions, counting numbers, 3D tilt), and the app follows the system's reduce-motion setting as before. While the Super Admin switch is off, the switch shows on and locked with "Turned off for every account by the administrator".

## D-585 — `app.animations`: the Super Admin's switch for every account · 2026-11-10 · accepted
A catalog key (`../back/services/feature_catalog.py`, tab Profile next to Display & reading, super-admin only), named after the existing `app.*` platform keys. In the disable list (= off) every account behaves as Reduce motion: `AppDisplayScope` listens to `AppConfig.disableListVersion` and applies `reduceMotion: true` over the personal prefs, so `MediaQuery.disableAnimations`, the page transitions, counts, entrances, tilt and the parked decorative loops all follow, live on a theme fetch or the `disable_list_updated` push, and from the cached disable list on the next start (the boot splash reads it too). The theme route is public, so a guest or the sign-in screen gets it as well.

## D-620 — 3D beyond the hero surfaces: lists, images, numbers (extends D-583) · 2026-11-10 · accepted
`lib/design/app_motion_kit.dart`, `lib/design/app_depth.dart`. The editorial theme (D-610 .. D-629, `.interface-design/system.md` §6) lets depth reach three more places, each with a hard limit. (1) **Cards in a scrolling list** (a featured course card, an image card, the ONE key KPI): `AppTilt.subtle` — at most 2° under the mouse, no glare, the hover shadow at 60 %, and on touch a press depth only (it sinks 1.5 %; it does NOT turn toward the finger, so a list being scrolled never wobbles). The pose is a ValueListenable that repaints the transform, the shadow and the glare; nothing is laid out while it moves (checked by a layout probe in `test/ui/app_depth_test.dart`). The full `AppTilt` stays on the hero surfaces only. (2) **Course covers in lists**: `AppParallaxImage` drifts the picture at most 8 px against its Scrollable (a `Flow` delegate repainting on the scroll position: no rebuild, no layout per frame; the picture is drawn 2 × 8 px taller and clipped, so its edge never shows). Outside a Scrollable, in an unbounded box or under Reduce motion it is just the picture. (3) **Key figures** (a streak, points, a score): `AppOdometer` = `AppCountUp(roll: true)` — each digit rolls on its own column from the old digit to the new one (up when the number grows, down when it shrinks), the ones first and each higher place 60 ms of the run later, with a slight drum perspective; digits are tabular, the final text holds the width and is the only thing a screen reader reads, and the `memoryKey` memory is the one `AppCountUp` keeps (a revisit never rolls again). The ten glyphs are laid out once per style and painted per frame. Limits: no tilt on page headers, navigation, tables or forms; at most one rolling figure per screen block; nothing tilts or rolls under Reduce motion or the `app.animations` switch; at rest every transform is the identity.

## D-621 — Flip, parallax, odometer, expanding card, slide-in, sheet motion · 2026-11-10 · accepted
The motion pieces of the editorial theme, all driven from their current on-screen value so a second toggle mid-way turns them around without a jump (`test/ui/app_depth_test.dart` toggles each one mid-flight). Curves are named once in `AppEase` (`app_motion_kit.dart`): `out` = cubic (0.23, 1, 0.32, 1), a strong ease-out for entrances AND exits (never ease-in on UI); `drawer` = cubic (0.32, 0.72, 0, 1), the iOS sheet curve. **`AppFlip3D(front:, back:, flipped:)`** turns a card over on a perspective Y axis (quiz answer reveal, flashcards) with a critically damped spring (stiffness 300, no overshoot, about 300 ms to the eye) seeded with the current angle and speed; it turns toward the reading end, so the other way in Arabic; both faces are laid out (the card takes the larger), only the visible one is painted, hit-testable and in the semantics tree; Reduce motion = a 160 ms crossfade. **`AppExpandCard(header:, child:, expanded:)`**: the lesson / accordion card — height (the one layout animation the kit allows), chevron turn and a body fade that starts a quarter of the way in, 260 ms open / 220 ms close on `AppEase.out`; the header is a 48 px button with `expanded` semantics, focusable, Enter / Space, and the focus ring on the card border; a closed body is offstage (kept, not read, not focusable). Reduce motion: opens at once. **`AppSlideIn(visible:, child:, from:)`**: a feedback panel that slides in by its own size from the bottom or the reading end in 260 ms and leaves in 180 ms (both `AppEase.out`), fading over the first 40 % of the way; while leaving it cannot be tapped and is not read, once gone it is out of the tree; a live region by default. Reduce motion: a 150 ms fade. **Sheets**: `showAppSheet`'s phone sheet gets `AppEase.sheet` — 280 ms in on `drawer`, 200 ms out on `out` reversed. Flutter's own bottom sheet already lets a drag catch the sheet mid-animation and splits the curve where the finger let go, so the settle after a short drag runs on the drawer curve from there and reads like a spring; a fling faster than 700 px/s or a drop past half still dismisses. A true spring on release would need our own route (not worth a fork of `ModalBottomSheetRoute`). The side panel (wide windows) enters in 280 ms on `out`; a dialog route has one duration both ways, so its exit curve reaches the closed place after 200 ms. Reduce motion: no slide (`AnimationStyle.noAnimation`); the drag still follows the finger, because the person is making that motion.

**D-500, round 2 (2026-11-10).** (1) A one-photo layout is now read the way it was found: `sheet_finder.place_layout` runs the finder on the page, matches every saved answer block to a page block of the same rows x columns and fits ONE homography from all their bubbles; it is used only when the fit is tight, orientation-preserving and unique, a symmetric sheet's two placements being told apart by its printed ink or refused; otherwise the general fit runs as before. (2) "Part of the sheet is outside the picture" comes only from the sheet's own lattice: a block's bubble against the photo's edge, its next row or column off the photo or the frame, or bubble shapes past its end lying on its own lines; shapes from a sheet stacked underneath no longer count. (3) Numbering across the rows is detected from where the one-digit question numbers are; when it cannot be told on side-by-side columns the teacher is asked (`order_unsure`, one tap "Order: down / across"). (4) A column shorter than its neighbour is always asked (`column_short`); a digit grid one row short is completed from the print. Measured once on hold-outs not used for tuning: fresh synthetic designs (`bench/omr/designs.py`, 3-5 options, 1-3 columns, LTR / RTL, down / across, ID top / side / none, seed 13000, 48 photos): 33 exact layouts, 32 numbered right, 0 wrong layouts without a check flag, 0 wrong marks in 990 read answers; the owner's held-out photos: 6 / 10 exact as before, all 6 now read their own photo (was 4), the cut-off warning on 4 photos (was 7), 0 wrong marks. Still weak: rectangular-bubble designs (most of the 15 synthetic misses), two real photos where part of a column or the ID grid is not found (now flagged, not fixed), and "check the numbering order" showing on our own sheet's low-resolution photos.

**D-500, round 3 — framed sheets (2026-11-10).** The owner's 150-question sheet (five columns of 30 numbered right to left and down, every option in its own rounded column with dotted row lines, a 3-digit ID grid whose first digit prints 0-2 only) came out as 131 questions x 5 options, no ID, numbered across. Causes and fixes in `mlkit/omr/sheet_finder.py`: (1) "is a bubble printed here?" compared a whole patch with the page's average bubble, and that average carried the column frame, so a bare frame wall beside a column and the letter row under a column's rounded top passed as bubbles (a 5th option, two header rows): only a disc around the centre is compared now, and a second test asks for a closed ring of ink at any radius near the bubble size (a smaller ID bubble, or one whose contour never closed because it touches the frame, passes; a wall, a letter or a dotted line does not). A block whose end line shows rings keeps growing only onto rings (the notes box under a column stopped passing). (2) Pieces of one block found apart are joined: side by side when the rows line up (the shorter piece laid on the longer one's rows) and the columns between them are printed (`merge_columns`), end to end when they overlap by a row or two (`dedupe` unions them). (3) A digit grid may be ragged: it grows down a run of its columns while the others stop (holes), re-centred row by row so a step read off two rows does not drift off the print; a short edge column is kept or added when its printed cells run from the top or bottom with closed rings and bare paper past them; a missing 10th row is checked on the live columns only. (4) The numbering order compares each column's question numbers with that column's own widths (on a 150-question sheet 31-99 are narrow only next to 100-150), and a narrow run of about nine rows means down. Reading (`autolayout._read_placed`): the ID's printed digits are subtracted like the answer letters (left in, a blank ID bubble read half shaded and pulled the threshold band onto every real mark), and "every bubble sits on a printed one" also accepts the page's own lattice (on this design few rings close as contours, so every question was held for alignment). Measured: this sheet exact from a 780 px scan up and on 3 of 4 simulated phone photos of 2500 px and more (the 4th is one question short and flagged); a shaded copy reads 150 / 150 answers and the ID on the scan and on 2 of 3 phone photos, the 3rd refused with "retake", 0 wrong marks anywhere. Synthetic designs (dev, 96 photos): 78 exact (was 70), 69 numbered right (was 65), 0 confident wrong layouts, 2668 read answers all right with none left for review (was 2542 right, 6 to review), 0 wrong marks. Regression test: `tests/omr/framed_sheet_unit.py` (fixtures at 1560 px; at 1250 px with strong JPEG compression this design is borderline). Still weak: phone photos under about 1800 px of this pale design.
## D-570 .. D-575 — Super admin and organization pages: one header language, full-width pages (2026-11-10) · accepted

**D-570 The organization dashboard's header lies on the shell's gradient.** `showTopBar: false` stays (every org page needs its own title, primary action and switcher), but `OrgPageFrame` (`org_page_header.dart`) now draws the header edge to edge on the same `AppMeshSurface(seed: 3)` as the sidebar, painted at the window's coordinates (shifted by the sidebar / rail width, 0 in focus mode) so the two read as one surface, and the page is a sheet with a rounded top-start corner under it — the look of every other role's shell. Before, the header was a gradient box floating inside a centred card on the doodle pattern. Phones keep the header above the page. The header is ONE row from 600 px (the rail included), `AppHeader`'s heights (72 / 84 open, 56 compact), title at the start with one status line (subtitle · "Updated …"), then the one primary action, then the tools in the shell's order — Search · Refresh · calendar · messages · assistant · notifications · help — then the switcher pill, and the focus toggle LAST at the end edge. While focus mode hides the sidebar the toggle becomes the labelled "Exit focus mode" in the same corner. Search keeps its label and the pill its name from 1040 px (1160 with a primary action); below 900 px a primary action moves under the title. Tools are glass on the gradient (`ChromeBar`), no longer card-coloured trays.

**D-571 Remote Config never blanks the first frame.** `RemoteConfigService.appName` read a `late` field that is only set once Firebase answers; when Firebase is slow or blocked (its start-up step is cut off by a time limit) the app's first real build threw and the page stayed grey. The client is nullable now and every getter falls back to the defaults.

**D-572 Super admin home and tabs.** A shell tab's `AdminPage` no longer draws a second Refresh under the shell bar's own; five KPI cards make one row of five on a wide window (`AppKpiGrid(maxColumns: 5)`, five columns from 1100 px, only for a grid that asks), never three above two with a hole; the duplicate "Active subscribers" tile left Activity & health (it is a KPI already). `AppSettingsHeader` (every role's account hero) centres its avatar and name in the card: as a Stack child it had sized to itself and sat off-centre.

**D-573 Member lists use the width.** `PagedList(minTileWidth:)` lays cards side by side once each can be that wide (two per line on a desktop, three on a very wide one), one line's cards at the same height; the organization's members list uses 520 px. A list of short cards no longer runs as one long column with empty right halves.

**D-574 Readable fills on any palette.** The timetable list's tab indicator and its "New timetable" button used the raw primary colour under white text, unreadable with a light brand colour; they take the brand gradient (`c.primaryGradient`) and the kit's `OrgFab` (made public from `org_page_kit.dart`). A header's primary action is capped at the touch height so a button that fills its height cannot grow to the whole header.

**D-575 A card page's header spans the page.** `BasePage(useWebCard: true, appBar: …)` now puts the header across the page above the card on screens from 600 px, instead of inside the card (a second floating gradient box: the landing page, Data Lab control, complaints, help, subscriptions, inbox, profile and other shared pages).

## D-550 — Gradients mix hues around the brand colour · 2026-11-10 · accepted

The owner found the gradients poor: shades of one hue read as flat. `AppHarmony.of(main, ink)` (`lib/design/app_contrast.dart`) walks the colour wheel from the brand colour: warm mains (red, orange, gold) toward pink and violet, cool mains (green, teal, blue, purple) toward blue and magenta. Partners sit about 26° (near), 56° (far) and 88° (a deep tone) away, plus a contrasting spark (the theme's `accent2` on the default surface). Every blend STARTS on the brand colour so it still leads (the first cut put the far hue first and a green brand read as navy and violet; tuned after the real-app look). `AppMesh` paints five soft blobs; buttons and hero stops (`_brand` in `theme_config_provider.dart`, `AppMesh.blend`) are three-hue linear blends. Every stop and every mix passes `ensureContrast` against the on-hero ink, and dark yellows turn to amber instead of olive. A grey brand gets slate tones.

## D-551 — One continuous shell chrome, one header per screen · 2026-11-10 · accepted

On desktop and rail the sidebar and the top bar are ONE `AppMeshSurface(seed: 3)`; the content is a sheet with a rounded top-start corner under it (no corner when the page draws its own header across the top, `showTopBar: false`, or in focus mode). `ShellChrome` (`app_shell_nav.dart`) tells a page whether the shell's bar owns its header (`ownsHeaderOf`: the bar is shown and the route is the tab's first); `AppHeader` and `AppPageHeader` then fold into a slim row on the surface (the page's own actions, "Updated …"), so the title is drawn once. The bar's buttons sit together at the end edge: Refresh, the app-wide tools (calendar, messages, assistant, bell), help, and the focus toggle LAST; a pushed page's own header carries the same app-wide tools. Focus mode keeps a slim bar with a labelled "Exit focus mode" in the same corner (it replaces the floating `AppFocusExitPill`). Pushed pages hide the shell bar and draw their own header.

## D-590 — The Studio edits one project, rendered once · 2026-11-10 · accepted

**Decision.** The Studio (Records and session materials) no longer makes one file per tool. Every change — split, remove a part or a marked period, keep only a period, trim a part's edge, per-part speed, texts, pictures, quality — is a step of ONE edit list (`studio_project.dart`: clips over the SOURCE in play order + overlays + quality), rendered by ONE job (`POST …/render`, op `project`, `services/studio_render.py`: trim / atrim + setpts / atempo per clip → concat → scale → looped PNG overlays → yuv420p). The timeline shows OUTPUT time (removed parts close up, as in every editor). The legacy one-shot ops (trim, cut, split, speed, quality, merge) stay on the server for older apps; the app keeps Merge (originals) and "Two files" (the project rendered twice, split at the playhead). The filmstrip asks for 25 frames (25 × 160 px = 4000 px: a wider sprite exceeds the 4096 px texture limit of many phone GPUs and drew black in WebGL; the server takes 8–120) and the same job keeps the audio peaks (4 a second, ≤ 4000, inline in the frames answer) for the waveform strip.

## D-591 — Why the old cut / trim cursor felt bad, and the new timeline · 2026-11-10 · accepted

**Cause.** The old timeline chose the grip in `onHorizontalDragStart`, which Flutter fires after the drag slop (≈ 18 px on touch) and with the position where the drag was ACCEPTED, so a finger put on a handle often grabbed the playhead or nothing; the handle then jumped to the finger (absolute placement, no grab offset); `onTapDown` moved the playhead under every press, including a press meant for a handle; the player's own position updates (every ~250–500 ms) overwrote the playhead during a scrub, so it jumped back; the band was 62 px with handles on the clip frame, and the playhead sat on top of both handles at 0:00; nothing showed the frame at the edge being dragged. **Decision.** `studio_timeline.dart` is a raw `Listener`: the grip is decided where the pointer goes DOWN, moved by the distance dragged (no jump), with 48 px hit areas and tabs drawn outside the clip; the playhead scrubs at once from the ruler or any empty lane (one seek in flight, the newest target wins, player updates ignored while scrubbing); dragging a clip edge previews that very frame on the stage with its exact time ("Start · 01:23.45"); snapping to the playhead, cuts, marks and overlay edges within 8 px (a line shows it; Alt turns it off); zoom by Ctrl/⌘+wheel around the pointer, pinch (which also pans) or the transport's log slider, up to ≈ 8 px a frame; the view follows the playhead while it plays. The preview plays THROUGH the edit (a ticker interpolates between player updates, skips removed parts at their exact edge, plays each part at its speed). Text is drawn by the app (`studioTextPainter`, the chosen AppFonts catalog font, Arabic shaped and right to left like everywhere in the app) and the same painter rasterises it to the PNG the server overlays, at the video's own size — so the preview is the render. Rejected: ffmpeg drawtext (the api image has no app fonts, and drawtext's Arabic shaping depends on the ffmpeg build's harfbuzz/fribidi; the preview would never match).

## D-592 — Overlays stick to what they were put on · 2026-11-10 · accepted

**Decision.** A text or picture is anchored in SOURCE time: removing a part before it moves it along with its content; a part removed under it shortens it; everything it covered removed → it is not drawn (the panel says "In a removed part"). The app maps it to output time for the lane and for the render (`StudioEdit.overlayOut`); dragging it on its lane re-anchors both ends. Animations (fade, slide ×4, pop, typewriter in reading order — right to left for Arabic) use the same curves in the preview (`studioOverlayLook`) and in ffmpeg (fade alpha, scale eval=frame, overlay x/y expressions, geq alpha mask for typewriter).

## D-593 — History, restore and autosave · 2026-11-10 · accepted

**Decision.** Every step is a snapshot of the edit with its words ("Removed 01:10 – 01:25", "Speed ×1.5 on …", "Added the text “…”") and its time. Undo / redo move the head; tapping any row restores that step; the later steps stay (struck through, "undone — tap to bring it back") until a NEW change, which drops them — silently for one, after a yes for two or more. "Back to the original" is itself a step. The whole history autosaves 1.5 s after each step (`studio_projects`, one row per person + source, ≤ 512 KB, revision 0072) and is also stored with every rendered draft, so "Continue editing" on a finished job reopens it. 120 steps at most (the oldest after the original go first).

## D-594 — Why progress stopped at 50 %, and the job's life · 2026-11-10 · accepted

**Cause.** `material_studio._run_one` (and `records_service._run_one`) wrote `processing 50 %` and then ran the whole ffmpeg render through `local_recorder._run_ffmpeg` (`communicate()`, nothing read until the end, under `nice`, with a 6 h budget): nothing moved between 50 % and 85 % for as long as the render took — minutes to tens of minutes for a lecture on a busy server. And when the API restarted (a deploy) during a job, the BackgroundTask died with it: the draft stayed `assembling · processing · 50 %` forever, Retry was refused for 30 minutes ("not failed") and the app kept polling. **Decision.** A change still in the making (a text being typed, a slider held) is committed as a step before a render, and typing commits after a 0.7 s pause — the first real-app round rendered a typed text that the history did not have yet. Every Studio ffmpeg run goes through `studio_render.run_ffmpeg`: `-progress pipe:1` read live (`out_time_us` against the expected output length; stderr drained at the same time so a full pipe never stalls ffmpeg). Stages and their share: queued (waiting for a worker slot) → downloading 1–30 % (bytes read from MinIO / the drive) → processing 30–92 % (ffmpeg) → uploading 92–100 % (bytes sent). Every whole percent is written with `job_updated`; with nothing new a heartbeat every 8 s (also while queued). A running job without a heartbeat for 3 minutes is dead: the next read marks it failed ("stopped on the server — retry"). Stop (`POST …/cancel`) drops a marker file every worker of the host sees; ffmpeg is killed within a second and the job ends as stopped (Run again / Discard). The app shows the four stages, the percent (animated), the time left at the pace of the last 90 s, and Stop. Tests: `tests/org_v2/studio_progress_check.py` (the progress parser, a real ffmpeg render reporting 0→100, cancel, the reaper).

## D-596 — Download before or after editing · 2026-11-10 · accepted

**Decision.** The Studio's top bar downloads the original; a finished job and a draft in the session's drafts strip download their file. The server answers a signed 2 h link (`/api/v1/studio/download/<token>`, the Studio's own staff roles re-checked when it is used; Records: the owner's play token with `?dl=1`) that streams the file with `Content-Disposition: attachment` and its name. Web: the browser downloads the link itself (never held in memory); Android / desktop: streamed to a temp file with progress, then saved to Downloads; iPhone: the share sheet (Save Video / Files). A plain file save, not the encrypted course downloads. An HLS-only material answers 409 `material_not_downloadable`.

## D-597 — Time runs left to right in Arabic too; the canvas · 2026-11-10 · accepted

**Decision.** The timeline, the transport and every in / out pair stay left → right in Arabic (the player's own bar, every editor, and the numbers in the readouts read that way); the panels, words and lists around them follow the language. The bay stays dark in both themes; the canvas around the picture can be switched dark / grey / light from the top bar to judge a text against more than one surround.

## D-610 — Warm Editorial is the built-in default palette; Material 3 roles mapped from it · 2026-11-11 · accepted

**Context.** The editorial theme overhaul (`.interface-design/system.md`) makes the server preset `warm_editorial` the platform default (backend D-610, revision 0073). The app still opened on the old indigo palette when it had no server answer and no cache, and `materialTheme()` built its `ColorScheme` from a seed, so dialogs, menus, date pickers and chips fell back to Material's own purples and greys. **Decision.** `AppTheme` (the last-resort fallback) holds the preset's values exactly (system.md §2, light and dark); its gradients are re-derived from them. `ThemeConfigModel` takes an optional `accent3` (the sky block tone), parsed and cached only when sent; `context.colors.accent3` derives one when it is absent (`ThemeConfigProvider.deriveAccent3`: hue 214 turned 15 % toward the primary, mixed 15 % into the canvas, lightened until `text_light` reads at AA on it). Dark mode's canvas is now `dark_background` (it was the card tone at 90 %, so a card had no tone step under it). `materialTheme()` builds a strict `ColorScheme`: surface = paper, `surfaceContainerLowest … Highest` from paper / canvas / input (dark: canvas → input), primary (dark: the AA-lifted primary), `primaryContainer` = the emerald block, `secondaryContainer` = peach, tertiary = gold (AA on canvas and cards), error = danger, outline / outlineVariant from the divider, `surfaceTint` transparent, shadow = the warm `card_shadow_color`. Every component theme is set in ThemeData, never in a widget: buttons (radius 14, height 48, padding 24, label 15 · 600, a 2 px primary ring on keyboard focus; Filled / Elevated keep the D-136 brand fill), inputs (warm fill, hairline, 2 px primary focus ring, radius 14), cards (tone + hairline, no elevation, radius 16), chips (radius 10), sheets and dialogs (radius 28, editorial title), menus, navigation bar / rail (emerald block indicator), tabs, list tiles, dividers, tooltips and snack bars (inverse surface), progress, date / time pickers. **Contrast.** Gold `#94691A` and success `#12805C` reach 4.5:1 only on canvas and cards, warning never: on blocks and inputs they are icons, fills or large text, and `context.colors.blockAccentInk` darkens them for text. **Consequences.** A first launch looks like the platform after its first theme fetch; other presets keep working (every widget reads roles). `test/ui/theme_contrast_test.dart` pins the old-palette regressions to the old surfaces and checks the new captions on the peach and sky blocks.

## D-611 — Editorial headings in Markazi Text, with a "Same as text" setting · 2026-11-11 · accepted

**Decision.** Headings use an editorial face made for Arabic and Latin: Markazi Text (OFL; static 500 / 600 / 700 instances cut from the Google Fonts variable file with fontTools' instancer, `assets/fonts/editorial/` with `OFL.txt`), declared in pubspec as `uiEditorial` so headings draw from the first frame; the web font prune keeps it in `FontManifest.json` (about 560 KB). `AppFonts.editorial` is the heading family (never a literal; `app_fonts_guard_test` also catches `'uiEditorial'`). `AppType.display / headline / pageTitle / section` and the theme's `display*`, `headline*` and `titleLarge` (app bar and dialog titles too) use it; body, rows, labels, meta and figures keep the person's UI sans (D-072). **Sizes.** system.md's 32 · 24 · 22 · 18 are OPTICAL sizes: Markazi's letters are small on their body (cap height 0.48 em against Inter's 0.73; the Arabic alef 0.53 em against Plex's 0.74), so drawn at those numbers a section heading looked like 12 px sans. The face is drawn at 1.3 × (Latin) / 1.25 × (Arabic) of the role's size (`AppFonts.editorialScale`), line height 1.15 / 1.3 (Arabic marks), −1 % tracking on Latin only; judged on the student and teacher home renders. **Setting.** Display & reading › Headings: Editorial (default) / Same as text (`DisplayPrefs.editorialHeadings`, JSON `headings: 'editorial' | 'text'`, device-local and carried by the account sync as any other field); "Same as text" draws the heading roles in the text font at the earlier sans scale 28 · 22 · 20 · 16. The wording matches the backend's features guide entry `editorial_headings`.

## D-612 — Tokens: radii by hierarchy, `xxxl`, tone-first depth · 2026-11-11 · accepted

**Decision.** `AppRadius` names every step of the hierarchy: chip 10 · `control` 14 (buttons, inputs) · card 16 · `block` 24 · `sheet` 28 (was 24) · hero 32 · `pill` (a full stadium). Kit widgets that used `sheet` as a pill (status badges, count bubbles, pill tabs) moved to `pill`, the KPI highlight and `AppGradientSurface` to `block`, the home greeting to `hero`. `AppSpace.xxxl` = 64, plus `gapXl`, `sectionHead` (32 above, 12 below) and the hero / block paddings of system.md §4. Depth is tone first: canvas → paper card (+ warm hairline) → tinted block; `cardShadow` (level 1) is a whisper (3.5 % / 3 % of the warm charcoal tone) and `AppElevation` 2–4 use `context.colors.shadowTone` (`card_shadow_color`) instead of the text colour or black, so no neutral grey shadow sits under every card. `AppTheme.radiusControl` / `radiusSheet` back the new names.

## D-613 — Blocks · 2026-11-11 · accepted

**Decision.** `AppBlock(tone:, child:, padding:, hero:, onTap:)` (`lib/design/app_blocks.dart`, exported by `app_kit.dart`) is a full-width tinted container (radius `block`, padding 24; a hero block 32 on top) that groups one subject. `AppBlockTone`: peach (`accent`), sky (`accent3`), gold (an accent2 tint), emerald (a primary tint), paper (card + hairline); dark mode draws each as a deep surface of its hue (`ThemeConfigProvider.darkBlock`, ≈ `#3A2A22` / `#1F2A38` for the preset) with a faint edge. Ink keeps AA on every tone in both modes (`AppBlock.colorsOf(context)`: ink, muted, faint, `accentInk(color)`). `AppBlockTone.forKey(key)` is FNV-1a over the code units (stable across runs and between the VM and the web) and picks among the category tones only (peach, sky), because gold and emerald carry meaning and are never handed out by a hash. Test: `test/ui/app_blocks_test.dart` (layout harness, AA per tone and mode for the default and a palette without `accent3`, the cache round trip, `forKey`).

## D-622 — The home hero is a block; the brand gradient is one emerald family · 2026-11-11 · accepted

**Context.** The editorial brief (`.interface-design/system.md` §1) forbids gradient washes as decoration. The role homes' greeting (`HomeHeader`, D-360 / D-550) was a teal → blue mesh with an olive corner glow under white ink, and the brand gradient (`ThemeConfigProvider.brandStops` / `_brand`) walked the colour wheel (a −7° lift, a +16° deep end, `AppHarmony` near / far stops), so emerald drifted into blue on every button and header; `heroGlow` was `accent2` (gold), which turns olive over emerald. **Decision.** (1) `HomeHeader` is `AppBlock(hero: true)` — peach for a student's or a parent's home, sky for every other role (`HomeHeader.toneForRole`; `tone:` overrides; the role is read from `MyAuthProvider` when one is in scope, peach otherwise) — with the name in `AppType.display` as the page's one memorable element, the greeting and the day line in the UI sans, the actions as paper chips (`ChromeIconButton` off a `ChromeBar`), the tilt of D-583 kept; `HomeHeroCard`, `HomeHeroTag`, `HomeDayRibbon` and `HomeHeroFigure` draw in the block's ink (`homeOnHero` = `AppBlock.colorsOf(context).ink`; the ribbon's sessions are emerald, the primary subject). (2) The brand gradient is ONE family: `primary_light → primary → primary_dark` from the live primary (`_settle` pulls a server `primary_dark` of another hue back to the primary's), no hue turn, three shades at 135°; `heroGlow` is the family's lift stop; the mesh (`app_mesh.dart`) paints a main colour with lights of its own hue (`AppMeshFamily`: base, lift, deep), no spark. `AppMesh.companion` stays for pickers. The gradient is a touch again (D-136 / D-180): headers, the primary button, the selected tab, the sidebar, one KPI. (3) The boot splash keeps the native cream / emerald frame 1 and draws the app's name as an editorial wordmark (by hand at the display role's optical size: there is no theme scope above the MaterialApp), warm emerald / gold / peach lights, charcoal ink — no blue, no mint. (4) `BasePage`'s wide-page doodle pattern (D-560) is gone (plain warm canvas) and its "coming soon" page is a vector mark on a peach block (no emoji, no gold text). **Tests.** `test/ui/home_hero_block_test.dart`; `brand_gradient_test` / `premium_foundation_test` keep their AA and "three stops, two different ends" checks (the stops are now shades, not hues — the comment says so).

## D-614 — Headers, tabs, chrome chips and settings on the canvas · 2026-11-11 · accepted

**Context.** D-360 gave every page header the organic brand gradient (`AppMeshSurface`), glass chrome on it and a gradient pill tab. The Warm Editorial brief (`.interface-design/system.md` §1, §2) forbids gradient washes as decoration, keeps emerald for the primary action / success and gold for achievements, and the derived brand stops (`brandStops`) turn the hue toward teal — the "blue" the pill tab was not allowed to show.

**Decision.** `AppHeader` and `AppPageHeader` (`lib/design/app_header.dart`, `app_page_header.dart`) are editorial mastheads on the canvas: `Material(color: background)`, a 2 px SOLID primary `AppHeaderStrip` on top (`color:` on `AppHeader` recolours it; `accent: false` on `AppPageHeader` drops it), the title in `AppType.pageTitle` (collapsing to `section`) in ink, the asymmetric rhythm (24 above the title, 16 under it; 8 / 8 compact), breadcrumbs and "Updated …" in the light inks, the chrome as paper chips, the one primary action bare and the secondary actions on an `AppHeaderTray` (card surface + hairline, radius `control`), and an `AppHeaderRule` (warm hairline) closing the header — unless the `bottom` is an `AppUnderlineTabs`, whose own rule closes it. `AppHeader.seed` stays for callers and changes nothing. `ChromePlate` (`chrome_button.dart`) is THE chip: a 40 px plate in a 48 px target, paper (card surface, hairline, radius `chip`) on the canvas and glass inside a `ChromeBar` or with `onHero: true`, with the press depth; `ChromeIconButton` and `AppBackButton` are both one. `AppTabs` selects with solid primary (no gradient, no shadow — a pill does not float); `AppUnderlineTabs` draws labels in ink with a 2 px ink rule; both show the focus ring on the track. `AppSection` carries its own `AppSpace.sectionHead` (32 above the heading, 12 under it; `spaceAbove: false` opts out), so callers put nothing between two sections. `AppSettingsGroup` is an editorial heading (`AppType.section`, a quiet glyph, the same 32 above) over a paper card (hairline, hairline dividers aligned with the text, no shadow); `AppSettingsTile` rows are at least 48 px with a faint icon well whose glyph is `blockAccentInk`-ed to AA; `AppSettingsHeader` is a peach `AppBlock` hero (avatar with a paper ring, name in `headline`, paper chips for role / email / username) instead of the gradient card; `AppSettingsPage` follows the page gutter (`gutter:` null) and lets each group bring its own space. `AppRefreshAction` is a 48 px ink button that swaps to a spinner while it runs; `AppRefresh` keeps the emerald-on-paper indicator.

**Consequences.** A `leading:` handed to `AppHeader` now sits on the canvas: the three callers that colour a close icon `c.onHero` (`checkout_pages.dart`, `checkout_web_impl.dart`, `export_layout/layout_computed_builder.dart`) need `c.textDark` or a `ChromePlate` when their screens are restyled. Callers that add a gap before an `AppSection` (26 at the time) double the rhythm until they drop it. `AppBackButton(onHero: true)` still means "on a hero / gradient surface" (glass) and stays right on course covers and the exam hero.

## D-630 — Colour distribution: one forest hero, sage for sky, red only where it means something · 2026-11-11 · accepted

**Context.** On the live instructor home (web, Arabic, 2560 px) after the Warm Editorial theme shipped, the owner judged the colour distribution "very very bad": the sky hero (D-622) was a pale cold blue-grey with no weight on the cream canvas; red was everywhere (a solid red Go live, a red icon tile and a red "Urgent" pill on every to-do, red Join / Enter room buttons); emerald showed only in the sidebar pill and one solid inbox tile, so the rest read as white cards on cream; seven white boxed chips ran along the top bar.

**Decision.** (A) **One signature hero.** Every role's home hero (`HomeHeader`, the super admin's greeting) is `AppBlockTone.forest`: `ThemeConfigProvider.blockForest` takes the theme's `primary_dark` hue, holds saturation at 0.62 and lightness at 0.145, then deepens until the cream ink reads at 7:1 (≈ `#0E3B2E` for the default preset; dark mode lifts it to ≈ `#14392D` with a cream hairline). Ink is the light canvas cream (`heroInk`), muted cream at 78 % (`heroInkMuted`, ≈ 9:1), faint at 66 %; `accentInk` lifts an accent until it reads on the forest. Inside it `ChromeBar` is in scope, so chrome buttons, the avatar and the context switcher draw as translucent cream plates. Derived from the theme, so other presets keep a deep hero of their own hue. `HomeHeroCard` (a second block) defaults to peach; the organization block under a home's hero (`OrgMemberHero`) stays sage, never a second forest. The hero keeps `AppTilt` and its one entrance. (B) **Sky → sage.** `accent3` is now a warm sage (`#E4ECE3`, dark `#1E2A23`); `deriveAccent3` derives a grey-green (hue 120 leaning 15 % to the primary); a server still sending the retired `#DCE7F5` gets the sage. The enum keeps `AppBlockTone.sky` (`AppBlockTone.sage` is the same value). (C) **Red only where it means something:** live now, destructive actions, errors, unread count badges. Go live is the primary action — on the forest a cream plate in emerald ink, elsewhere the solid primary — with a small red live dot; Join (Live now) and Enter room are emerald buttons, the pulsing dot / label / ring keep the red. To-do priority: urgent → warning (amber tint pill, ink darkened to AA), soon → primary, later → quiet ink; the kind icon sits in a neutral input-tone well. `HomeTodoCard` counts are amber. (D) **Emerald carries the 10 %:** primary buttons, nav selection, links, success, progress; the inbox icon tile is tonal (emerald block + emerald ink), never solid. (E) **60 / 30 / 10:** canvas; paper cards + tinted blocks (the course figures sit on a peach band at the top of the "My courses" card; a free day's agenda rests on a sage block; streaks / achievements keep gold); accent. A screen uses at most two block tones besides the hero. (F) **Ghost chrome:** `ChromePlate` off a hero has no plate and no border — ink icon, 48 px target, an ink wash on hover / press, a 2 px focus ring (primary on the canvas, cream on a hero); count badges ring in the canvas colour. (G) **Motion:** the course figures count up once (`AppCountUp`, remembered per label); nothing new loops.

**Consequences.** Every `ChromeIconButton` on the canvas (top bars, page headers) is now a ghost. Screens that pass `AppBlockTone.sky` get sage. A widget dropped into the forest hero must read `AppBlock.colorsOf(context)` / `ChromeBar.of(context)` rather than `c.textDark` / paper colours. The backend preset's `accent3` moves to `#E4ECE3` separately.

## D-631 — Premium dashboard structure; Amiri + Playfair Display headings · 2026-11-11 · accepted

**Context.** The owner asked for the structure of modern admin dashboards (grouped sidebar, a top bar with search and the person, a page title with a breadcrumb, a greeting hero, stat cards with a coloured footer band, KPI sparklines, ring stats, shortcut tiles, section cards with period tabs) in OUR Warm Editorial colours, and for Arabic headings in a high-contrast modern naskh.

**Decision.** Headings (`AppFonts.editorial`) are Amiri Bold for Arabic and Playfair Display 600 / 700 for Latin (OFL, subset to their scripts; `uiEditorial` / `uiEditorialLatin`, each the other's fallback); `AppFonts.editorialFamily` picks by language, the optical scale is 1.3 (Arabic) / 1.05 (Latin). Markazi Text is gone. Amiri was chosen over Noto Naskh Arabic (low contrast) and El Messiri (not naskh) after a side-by-side render; its line box needs no change at `height` 1.3. The shell (`app_shell.dart`) groups the sidebar tabs under tinted headers, the open tab a tinted pill with its count, a fold-to-icons button (`appSidebarCollapsed`, session only); the top bar is a paper band with a search box that opens the screen's existing Ctrl+K palette (shown only under an `AppCommandPaletteScope`), ghost chrome buttons (`ChromeGhost`) and the person; a page head carries the title and an `AppBreadcrumb` from 640 px. New pieces live in `app_dashboard_kit.dart` (`AppGreetingHero`, `AppStatCard`, `AppKpiSpark`, `AppRingStat`, `AppShortcutTile` / `AppShortcutGrid`, `AppSectionCard`, `AppBreadcrumb`); `HomeHeader(greetingHero: true)` draws a home's header as the hero; `CourseListCard` insets its cover and prints the price in the primary ink. No route, callback, provider, data model or API changed.

**Consequences.** Every page under the wide shell starts about 56 px lower (the page head). `Breakpoints.sidebarW` is 248 (was 220). The tinted open tab uses an opaque `lerp(cardBg, primary)` rather than `primaryTint` (translucent, which fooled the contrast check). Role homes adopt the pieces separately (docs/premium_dashboard_handoff.md). `AppDashSize` holds the kit's own sizes (hero avatar, ring, tile and band heights) so no piece draws a raw number. Merged on top of D-630: `AppGreetingHero` is the forest hero, the branch's own primary-hue sage tone was dropped for D-630's `accent3` sage (`AppBlockTone.sage`, an alias of `sky`; cover and category tones use it), and Go live stays the primary with the small red live dot.

<<<<<<< HEAD
## D-648 — Floating chrome: the shell's sidebar and top bar, and every pushed page's bar, are white rounded cards · 2026-11-11 · accepted

**Context.** The owner compared the live web app with the Spike admin template: the sidebar's group headers were tinted plates that read as buttons ("الرئيسية" twice: the General plate and the Home tab), the page title sat in two places (bar and page head), and the course page's floating capsule drew "Edit course" as a translucent tint whose label washed out.

**Decision.** `ChromeCard` (`lib/design/chrome_button.dart`) is the one floating chrome surface: the card colour, the card radius, the level-1 shadow (a hairline in dark mode), its own Material, ghost buttons inside, no rule under it, `ChromeCard.barHeight` = 64 for every bar. The wide / rail shells inset the sidebar (or rail) card and the top-bar card from the window by the page gutter (`shellInset`; `sideChrome` includes it). Sidebar groups are small muted labels (capitals in English); a one-tab group named like its tab draws none. The signed-in person sits in a tinted box at the sidebar's foot; the top bar carries the title (the home tab's name as one small breadcrumb line above it on other tabs — the old page head under the bar is gone), the search pill, the ghost tools and the avatar. `AppHeader` / `ScreenAppBar`, `AppPageHeader` (outside the shell's bar), `OrgPageHeader` / `OrgPushedPage` and the course page's desktop bar (`CourseSpaceBar`, pinned over both columns) are the same card with Back inside it (`appBarCardMargin`); the accent strip shows only for a page's own colour. The course bar's primary action is a solid primary pill with its ink lifted to 4.5:1; a `ChromePlate` without `onTap` draws its ink at 38 %. Phones keep the bottom bar; their page bars are the same card with a small top inset.

**Consequences.** Presentation only: no tab, badge, key, callback, kill switch or help id changed. Pages under the wide shell start about 40 px higher (no page head). `AppPageHeader.accent` no longer draws anything. Renders: `test/visual/premium_dashboard_golden_test.dart` "shell chrome per role".
=======
## D-632 — A tinted canvas under pure white cards; chart series from theme tones · 2026-11-11 · accepted

**Context.** The owner judged the component backgrounds "not good": on the live app (green preset) white and cream cards sat on a cream page (`#FBF7EC`; warm_editorial `#FFFDF9` on `#FBF7F0`) behind a visible hairline and almost no shadow, so nothing lifted off the page. The reference was Spike Admin: a softly tinted page, pure white cards, no border, one very soft shadow. The analytics rings and bars drew exams in a violet borrowed from the `purple` role (primary +120° as well), off an emerald theme; the profile hero's faint initial watermark read as a rendering glitch.

**Decision.** (A) **Canvas.** The green and warm_editorial canvases become the pale sage-grey `#F1F4F0`; warm_editorial's cards become `#FFFFFF`, its inputs `#F4F6F2` and its divider `#E6EAE3` (green's caption ink `#68756D` → `#617068`, 4.7:1 on the new canvas). Backend preset + migration 0075 (only values that still equal the old ones) and the app's `AppTheme` fallbacks. Dark mode keeps its deep canvas and raised card tone. (B) **Cards lift by shadow, not border.** `ThemeConfigProvider.cardShadow` (level 1) is now a wide low ambient plus a tight contact line (6 % / 5 % of the shadow tone); `cardEdge` is the card's edge: the shadow tone at 6 % in light mode, a quiet step above the card in dark mode, the full divider under High contrast. `AppLift` casts the shadow under a `Material` card; `AppShadow.cardEdge` is the side. AppCard, the dashboard kit's paper (AppStatCard, AppSectionCard …), a paper AppBlock, AppKpiCard, AppSettingsGroup, CourseListCard, the home quick tiles / agenda and a plain course session card use them. This replaces D-612's "a resting card has no shadow". Tinted blocks stay flat. (C) **Chart series** come from theme tones only: `appChartPalette` is primary · peach (`accent`) · sage (`accent3`) · gold (`accent2`) · terracotta (gold −30°), never the `purple` role; `anDistinctColors` picks the metric colours from those first (hue gap 45°) and falls back to primary-derived hues only when no theme tone is even 20° apart — the green preset draws emerald · gold · terracotta. The super admin's pending-subscriptions row is gold, not purple. (D) The profile hero's initial watermark is removed (visual only).

**Consequences.** No API shape, route, provider or model changed; the theme values are data (migration 0075, FLUTTER_API_CHANGES). `test/ui/analytics_metric_colors_test.dart` mirrors the new palette and checks no violet series on an emerald theme; `test/ui/design/app_cards_layout_test.dart` checks the lifted card. The shell, nav and top bar were restyled separately and keep their own surfaces.
>>>>>>> pd2/surfaces
