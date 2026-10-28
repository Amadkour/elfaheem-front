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
