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
