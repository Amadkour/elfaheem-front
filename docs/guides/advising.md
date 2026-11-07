# Academic Advising

The developer guide to the Academic Advising module (D-289): what each file does, how the flows run, the kill
switches, the deep links and the tests. Plan and history: `docs/advising/PLAN.md`, `PHASE2.md` … `PHASE9.md`,
`CHANGELOG.md`. Backend: `../back/services/organization/advising/` and `../back/routers/organization/org_advising*.py`
(check payloads there; don't trust the notes alone). Keep this file in step with the code.

## Where it lives and who sees what

- App code: `lib/features/org/advising/` (prefix `adv_`). Org screens rules apply: `t(ar, en)` from
  `admin_common.dart`, `orgCall` from `org_v3.dart` (toasts `orgErrorText`), naive UTC through `orgUtc()` /
  `orgParseUtc()`, `OrgPushedPage` for pages pushed from the org dashboard.
- Two server bases: staff `GET|POST /api/v1/org/orgs/{org}/advising/…` and the student's own
  `/api/v1/org/public/{org}/advising/…`. The app never mixes them: the student side is `AdvCommApi(org, student:
  true)` or the static `member*` methods (`AdvApi.memberStatus`, `AdvSupportApi.memberSupport`,
  `AdvAnalyticsApi.memberOutreach`, …).
- Eligibility: universities, faculties and the units under them (`advMaybeEligible`, `/status` `eligible`).
- Roles (PLAN §3.8): org admin (everything, settings) · advising director (system role `advising_director`: every
  student, advisor, load, analytics, sensitive notes with an audited read) · advisor (only the students assigned to
  them; their own sensitive notes; team notes of shared students) · student (own advisors, office hours,
  appointments, conversations, student-visible notes, plans, request status — never flags, risk or internal
  notes) · aggregate-tier viewer (the RBAC right `advising` `view` organization-wide, e.g. a dean: dashboard totals
  only, groups under the small-count threshold hidden, no student lists). `GET …/advising/status` `me` says what
  the caller may do (`leads`, `advisor`, `analytics`, `outreach`, the badge counts); screens read it rather than
  guessing from roles.

## Files

| File | What it holds |
|---|---|
| `adv_models.dart` | Pure models of Phases 2–4: status, policy and scopes, advisors, assignment plans, workspace items, the 360 profile, categories, flags, notes, timeline, `AdvPage` (the paging envelope with facets). |
| `adv_appt_models.dart` · `adv_warning_models.dart` · `adv_support_models.dart` · `adv_analytics_models.dart` | Pure models of Phases 5 · 6 · 7 · 8 (appointments, threads, templates, surveys, the hub · rules, alerts, graduation · requests, the approval chain, plans, accommodations · dashboard, drill-downs, compliance, health check, outreach). |
| `adv_api.dart` · `adv_comm_api.dart` · `adv_warning_api.dart` · `adv_support_api.dart` · `adv_analytics_api.dart` | One HTTP client per phase, one method per server route; every method throws `ApiException`. |
| `adv_texts.dart` · `adv_support_texts.dart` | Server error codes → Arabic + English, merged into `orgErrorText`. A new server code gets its text here. |
| `adv_setup_page.dart` | The advising page under Services → Academic advising: eligibility, Turn on / off (picks or creates the advising department), and the Work tiles every other page opens from (`_open(key)`). |
| `adv_wiring.dart` · `adv_comm_entries.dart` · `adv_support_wiring.dart` | Every plug-in point: the dashboard Services entry (`advServiceSubs`), the member home's "My academic advisor" row (`AdvMemberHubEntry`), the Work tiles of later phases, and the deep links. |
| `adv_config_page.dart` · `adv_advisors_page.dart` · `adv_students_page.dart` · `adv_distribute_page.dart` · `adv_handovers_page.dart` | Phase 3: settings per scope with inheritance, advisors and their load, manual assignment with history, distribute / rebalance / reassign (preview → apply), handovers. |
| `adv_workspace_page.dart` | The advisor's workspace (a director: every student) with search, one filter sheet, risk cards, and (Phase 9) selecting students to message (`AdvSelection`, `AdvSelectionBar`, `AdvSelectionActions`). |
| `adv_student_page.dart` · `adv_flags.dart` · `adv_notes.dart` · `adv_draft_store.dart` · `adv_categories_page.dart` · `adv_case_parts.dart` | The student 360 (Overview · Academic · Flags · Early warning · Notes · Meetings · Support · Timeline), flags with their state machine, notes with visibility / sensitive / contact logging and offline drafts, categories. |
| `adv_appointments.dart` · `adv_availability_page.dart` · `adv_threads.dart` · `adv_message_store.dart` · `adv_templates_page.dart` · `adv_survey_sheet.dart` · `adv_student_hub.dart` · `adv_comm_parts.dart` | Phase 5: booking, office hours and days off, conversations with files and offline drafts, templates, the anonymous survey, and the student's ONE screen (the hub). |
| `adv_rules_page.dart` · `adv_alerts_page.dart` · `adv_warning_section.dart` · `adv_warning_parts.dart` | Phase 6: rules (system + custom), the engine and Run now, alerts with "Propose a meeting", the 360's Early warning section, graduation. |
| `adv_requests.dart` · `adv_request_composer.dart` · `adv_request_chain_page.dart` · `adv_plan.dart` · `adv_accommodations.dart` · `adv_support_360.dart` · `adv_support_hub.dart` · `adv_support_parts.dart` | Phase 7: requests and referrals with an approval chain, support plans, accommodations, the 360's Support section and the student's side. |
| `adv_director_page.dart` · `adv_drill_page.dart` · `adv_advisors_stats_page.dart` · `adv_reports.dart` · `adv_outreach.dart` · `adv_analytics_parts.dart` | Phase 8: the director dashboard (manage · aggregate), drill-down lists, advisor stats, Export Studio reports (`adv.*` datasets), group outreach and its tracking, the student's messages. |
| `adv_parts.dart` | Shared pieces: `AdvPageFrame`, `AdvRowCard` (with the selection check mark), `AdvLoadState`, `AdvStepper`, the advisor / student pickers. |

Every screen is split into a page that loads and a plain-value view (`AdvWorkspaceView`, `AdvStudentView`,
`AdvHubView`, `AdvDirectorView`, …): the views are what the layout, accessibility and golden tests pump.

## Flows

**Turn on.** An org admin opens Services → Academic advising and turns it on (`POST …/advising/enable`), choosing or
creating the advising department. Existing registrar advisor links are imported and reconciled then. Turning it off
(`…/disable`) keeps every record.

**Setup.** Settings (`GET / PUT …/policy`) are per scope (organization · department · program · level · cohort) and
inherit; the page shows where a value comes from. Advisors get a status (available, leave, sabbatical, left), an
own maximum and contact fields. Distribution runs one engine for distribute · rebalance · reassign:
`POST …/assign/preview` then `…/assign/apply` with the preview's hash (409 `plan_stale` when another preview came
after). New students are assigned automatically (welcome notice to the student, one grouped notice per advisor).

**Advisor's day.** The workspace (`GET …/workspace`) lists my students by risk (score 0–100 with reasons), with
facets (open, urgent, no contact in 30 days) and the strip of unread messages and today's appointments. A card opens
the 360 (`GET …/students/{mid}/profile`): flags (`allowed_next` state machine, compare-and-swap), notes (private ·
team · student, sensitive, "log as a contact"; written offline, they wait in `AdvDraftStore` and send on reconnect,
idempotent by `client_id`), meetings, support, timeline. Appointments come from office hours; conversations carry
files; after a meeting the student gets an anonymous survey.

**Group messages (outreach).** A director messages any group of the organization's students, an advisor only their
own advisees (`me.outreach`, kill switch `org.advising.outreach`). Entry points: the dashboard's drill-down lists
("Message these students": the drill's audience), the Group messages page (presets), and the workspace's selection
(Phase 9: long press a card or More → "Select students to message", tap to choose, the page's check box, then
"Message N selected students" → the composer with the explicit `member_ids` audience, at most 5 000).
`POST …/outreach/preview` gives the count, who is left out (not advised by the sender, weekly cap reached) and an
`audience_hash`; `POST …/outreach` sends with it (409 `advising_audience_changed` when the list changed). The
tracking page shows delivered / read and "Message those who have not read it".

**Student.** The member home shows "My academic advisor" (`AdvMemberHubEntry`) when the student has an advisor; it
opens the hub (`AdvStudentHubPage`): advisors with office hours and the next free time, Book, Message, meetings,
shared notes, a pending survey, requests and support plans, and advising messages (`AdvHubOutreachSection`, each
opened with `showAdvStudentMessage`, which marks it read).

**Early warning.** Rules (built-in + up to 50 custom) run daily and on "Run now"; alerts carry their reasons and
"Propose a meeting" (opens the 360 on Notes ready to log a contact). Advisors and directors get digests.

**Requests and support.** An advisor files a support request or a referral; it follows the approval chain of its
scope (director review first, then the configured steps; a council step runs through governance). Approved
accommodations become rows the student sees with dates; support plans have items and reviews.

**Analytics.** The director dashboard (`GET …/analytics/overview` and its sections) with KPIs against the previous
period, filters, refresh as a job, 27 drill-downs (`GET …/analytics/students`), advisor stats, compliance per
term, the daily data check (badge on the advising page) and Export Studio reports with schedules. The unfiltered
dashboard is a copy the server refreshes every 10 minutes: "Updated …" in the header shows its `computed_at`, and the
header's Refresh asks for `?fresh=1` (12 an hour; a refused one keeps the figures and says why,
`advFreshFailedText`). Filtered views and the org-wide lists' counts are live within 60 s; the caller's own changes
show at once.

**Retention.** Settings (organization row only) hold two periods after a student's membership ends:
`retention_months` (sensitive notes, default 24) and `records_retention_months` (every other advising record, default
84, 12-240, never shorter; 422 `advising_retention_order`, the draft checks it first). The server's daily purge
(`../back/services/organization/advising/retention.py`) keeps a request, conversation or case link until its governance
item closes, and never deletes governance items, the audit log, aggregates or anonymous survey answers.

## Kill switches

| Key | Hides |
|---|---|
| `org.advising` | the whole module: the Services entry, the member home row, every advising deep link (`advEnabled()`; `AppNavigator` checks it before routing). |
| `org.advising.warning` | early warning: rules, alerts, the 360's Early warning section, the warning deep links (`advWarningOn()`). |
| `org.advising.analytics` | the dashboard, drill-downs and reports (the server answers 403 `feature_disabled` and `/status` `me.analytics` is null, so the tiles do not show). |
| `org.advising.outreach` | group messages: the Group messages tile, "Message these students" on drill-downs and the workspace selection (`advOutreachOn()` with `me.outreach`). |

All four are platform switches in `../back/services/feature_catalog.py`, snapshotted in
`test/contract/feature_keys.json`; the features guide entries are in `../back/data/app_features_guide.json`.

## Deep links (push data `module: advising` or `kind: org_adv_*`, routed by `AppNavigator`)

| Push | Opens |
|---|---|
| `member_id` (urgent flag, escalation, review due) | that student's 360 (`advOpenStudentLink`) |
| `screen: alerts` / `workspace` / `advisor`, `action: propose_meeting` | the alerts (since the digest), My students by last contact, the student's hub, the 360 ready to log a contact (`advOpenScreenLink`) |
| `kind: org_adv_appointment` · `org_adv_thread` · `org_adv_survey` | the appointment list or the hub, the conversation, the hub with the survey open (`advOpenCommLink`) |
| `kind: request` · `plan` · `accommodation`, `org_adv_request` · `org_adv_plan` | the request or the Support section, by audience (`advOpenSupportLink`) |
| `kind: org_adv_outreach` + `outreach_id` | student (`audience: student`): their messages with that message's sheet open on top (looked up page by page; marked read) · sender: the tracking page (`advOpenAnalyticsLink`) |
| `screen: health` | the analytics dashboard with its data check |

## Tests

- Pure models: `test/org/adv_models_test.dart`, `adv_assign_models_test.dart`, `adv_case_models_test.dart`,
  `adv_appt_models_test.dart`, `adv_warning_models_test.dart`, `adv_support_models_test.dart`,
  `adv_analytics_models_test.dart`, `adv_draft_store_test.dart`; Phase 9's selection and outreach deep link:
  `adv_selection_test.dart`.
- Layout at 320×640 and 1400×900, ar / en, text 1.3 (`expectNoLayoutErrors`): `test/ui/adv_layout_test.dart`,
  `adv_assign_layout_test.dart`, `adv_case_layout_test.dart`, `adv_appt_layout_test.dart`,
  `adv_warning_layout_test.dart`, `adv_support_layout_test.dart`, `adv_analytics_layout_test.dart`.
- Accessibility: the group "academic advising" in `test/ui/a11y_guidelines_test.dart` (workspace, workspace while
  selecting, the 360, the hub, the director dashboard).
- Request budget: the member home's `org-member` budget in `test/perf/home_requests_harness.dart` counts the
  "My academic advisor" row.
- Contract: `test/contract/api_paths.json` (every advising route), `feature_keys.json` (the four switches).
- Visual review (not CI): `test/visual/adv_*_golden_test.dart`, e.g.
  `flutter test test/visual/adv_case_golden_test.dart --update-goldens --plain-name workspace_select`.
- Backend: `../back/tests/org_v2/e2e_advising_*.py`, `advising_*_unit.py`, `pg_advising_lock.py`, `advising_perf_pg.py` (Python 3.12, `PYTHONUTF8=1`, a per-run
  SQLite `DATABASE_URL`).
