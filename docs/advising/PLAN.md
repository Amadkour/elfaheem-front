# Academic Advising — Phase 1 plan (awaiting approval)

Branch `feature/academic-advising` in both repos, worktrees `D:/platform/nextbrain/wt-back-advising` and
`wt-front-advising`, cut from `origin/organizations` (back `5927644`, front `5b0081ee`). Alembic head `0048`.
Decision numbers: next free is **D-289** (front `docs/DECISIONS.md`).

## 1. Discovery summary (what exists and is reused)

| Area | Existing | Use in advising |
|---|---|---|
| Org type | `Organization.type` ∈ university · faculty · department · institute · school · center · other; no behaviour hangs on it | Eligibility gate (§3.1) |
| Membership | `OrgMember` (unique org_id+user_id), role teacher · teacher_assistant · admin_assistant · student · org_admin, `academic_rank` (professor … demonstrator), `program_id`, `academic_level`, `cohort` | Every advising row hangs on `org_members.id` (per-org membership, never the global user) |
| Academic record | `OrgStudentAcademic` per (org,user): cgpa, credits, standing, probations, **`advisor_id`** (single, no FK, no history); registrar `Student`, `recompute`, `degree_audit`, `traditional_audit`, `absence`; policy `gpa` / `term_gpa` / `standing` | Early-warning data source; `advisor_id` kept as a mirror of the primary advisor |
| Terms | `OrgTerm` (year_label, term1/term2/summer, dates) | Term scope for rules and reports — no new term entity needed |
| Grades | `OrgRegistration`: final `letter` / `percent` / `grade_state`, `absence_pct`, `denied` — **no midterm / interim component** | GPA / failure rules; midterm rule needs a decision (Q2) |
| Attendance | `attendances`, `attendance_sessions`, registrar absence warnings (hourly) | Absence rules |
| Existing advising | registrar `PUT …/students/{uid}/advisor` (teacher only), `POST …/advisors/auto`, member `GET /public/{org}/registrar/advising` (advisees + `OrgDecision` cases, `advisor_decide`), app `OrgAdvisingScreen` | Kept working; the new workspace absorbs the screen (consolidate, not delete) |
| Departments | `OrgDepartment.preset = academic_advising` exists; `kind` service/scientific/council; `OrgDeptMember.is_head` | The Advising department and its head = Advising Director |
| RBAC | `org_ctx(module, action)`, `OrgCtx.require/can`, `MODULES`, `SYSTEM_ROLES`, dept-scoped grants | New module `advising` + system role `advising_director` |
| Workflow | Governance D-057: `OrgWorkItem` (request type, beneficiary, priority, `due_at`, `version`, CAS decide), per-dept `chains` (manager · entity · council · faculty_council), councils + voting, SLA tick, `notify.stakeholders` | Support requests, council escalation and referrals — no second workflow engine |
| Calendar | `CalMeeting` (`source_type`/`source_id`), attendees, `busy()` → 409 `attendees_busy` | Each appointment is mirrored as a `CalMeeting` (shows in `/me/calendar`) |
| Notifications | `notify_users` (in-app row → FCM → e-mail fallback), `notify.flush(after)` after commit, `live_events.emit` (SSE), attention `TABS`/`ORG_KEYS`, `/me/inbox` rows; no delivery log, no templates engine | Same channels; advising adds its own notice log (dedupe / cool-down / delivery) |
| Audit | `OrgAuditLog` append-only + `audit(..., before, after)`; no read logging | All mutations; sensitive reads logged as `advising.sensitive_read` |
| Uploads | governance `attachments.py` (sniff, size cap, private store, 10-min presign) | Same helpers for thread / request attachments |
| Exports | Export Studio: `register(Dataset…)`, async runs, schedules with e-mail, share links | Analytics exports and scheduled reports are datasets, not new machinery |
| Jobs | APScheduler ticks in every worker, `live_claims.claim` for once-only work, CAS rows | One `_org_advising_tick` (15 min) with claimed sub-jobs |
| Cache | Redis `cache.cached(key, ttl, fn)` fail-open | Director aggregates |
| Kill switches | `feature_catalog.py`, org-manageable keys, `app_features_guide.json` | `org.advising` (+ sub keys) |
| App plug-in | `gov_wiring.dart` pattern (service subs, dept tabs, member pills, deep links), `OrgPageHeader`/`OrgPageBody`, `orgCall`/`orgErrorText`, `t(ar,en)`, `AppShell`, charts, `exportHub`, layout harness | `adv_wiring.dart` mirrors it |

Gaps found: no bookable availability, no person-targeted complaints, no referrals, no notes, no caseload rules,
no risk engine, no disciplinary record, no midterm grades, governance settings not inherited from parent orgs,
the governance `council` chain step only works when the owner dept is scientific (the Advising dept is a service
dept, so escalation needs a new step kind, §3.7).

## 2. Assumptions (stated per the brief's "best practice" rule)

1. **Eligibility:** advising can be switched on only for orgs of type `university` or `faculty`, and for their
   sub-orgs (a `department` under a faculty inherits it). Center / school / institute / other: hidden, server 403
   `advising_not_available`. (Q1 asks about `institute`.)
2. **Advising Director** = the head of the org's Academic Advising department, plus anyone granted the new
   `advising_director` system role. Org admins have every director right.
3. **"Advising team"** visibility = the student's current advisors + the director(s) + members of the Advising
   department.
4. **Existing `advisor_id` values** are migrated into the new assignment table as `primary`, `source=legacy`,
   locked like manual assignments (never overwritten by auto-distribution). `advisor_id` stays and is written by the
   advising service only, so the registrar's advisor routes and `advisor_decide` keep working.
5. **Default eligibility** = role `teacher` (today's behaviour) until the admin changes it; ranks map as
   professors = professor / associate / assistant professor, lecturer = lecturer, assistant lecturer, TA =
   role `teacher_assistant`, demonstrator = rank demonstrator.
6. **Severity and priority are one scale** (low · normal · high · urgent) for flags, alerts, threads and requests;
   the brief asks for both and two scales confuse users.
7. **Times** are stored as naive UTC (org convention) and shown through `AppTime` in the org timezone.
8. **Anonymous survey:** the answer row stores no student id; a single-use token prevents double answers; scores
   are shown only for groups of ≥ 5 answers.
9. **Rate limits:** per-user write budgets (messages, bookings, outreach) through the existing `throttle.py`,
   extended with an "every call counts" mode.
10. **OpenAPI:** FastAPI generates it; advising routes get the `advising` tag and P9 commits a generated
    `docs/advising/openapi.json` (no OpenAPI file is committed today).
11. **CHANGELOG:** neither repo has one; the job keeps `docs/advising/CHANGELOG.md` + `docs/advising/PROGRESS.md`
    (multi-session tracker, like `docs/live/`), and backend contract changes go to `FLUTTER_API_CHANGES.md` as usual.

## 3. Architecture

### 3.1 Scoping and isolation
- Every table: `org_id` (FK organizations, indexed first in every composite index) + `member_id`
  (FK `org_members.id`) where the row is about a student. A student in a faculty and a center has two memberships,
  so two separate advising records. No query reads advising data without `org_id`.
- Postgres RLS `tenant_isolation` policy on every new table (same as `0048`).
- One access module `services/organization/advising/access.py`:
  `scope(ctx) → SQL filter` (director/admin: whole org; advisor: `EXISTS active assignment(advisor=me)`;
  student: own membership only). Every list and 360 query goes through it; tests attack each route as
  another org's admin, another advisor, a student of org A reading org B.

### 3.2 Data model (new revision `0049_advising`, all tables prefixed `adv_`)

Configuration
- `adv_policies` — org_id, scope_type (org · program · dept · level · cohort), scope_ref, `settings` JSON
  (validated by a Pydantic schema), version, updated_by. Resolution: most specific scope → org → parent orgs → defaults.
  Settings hold: eligible roles/ranks, single|multi mode, max_load, warn_pct (80), strategy, auto-assign on/off,
  digest mode, SLA hours per priority, nudge periods, retention months, survey on/off, workflow steps.
- `adv_advisor_profiles` — org_id, user_id, max_load override, availability status
  (available · leave · sabbatical · left) with dates, office location, contact note, bio. Unique (org_id, user_id).
- `adv_flag_categories` — org_id, key, name_ar/en, `sensitive`, `system`, active. Seeded: academic, financial,
  career, health/physical, psychological/social, disciplinary, accessibility, other.
- `adv_templates` — org_id, kind (meeting_note · outreach · support_request · message), name, body_ar/en with
  placeholders, system, active.
- `adv_risk_rules` — org_id, kind (gpa_below · gpa_drop · failed_courses · absence_pct · absence_count ·
  repeated_fail · no_contact · graduation_delay · midterm_fail if Q2 = yes), params JSON, priority, cooldown_days,
  enabled. Seeded with defaults.
- `adv_conflicts` — org_id, advisor_user_id, member_id, reason (relative · disciplinary · other), note, active.

Assignment
- `adv_assignments` — org_id, member_id, advisor_user_id, type (primary · co · support),
  status (active · ended), source (auto · manual · legacy · handover), locked, started_at, ended_at,
  end_reason, run_id. **Partial unique index**: one `active` `primary` per (org_id, member_id); unique active
  (org_id, member_id, advisor_user_id). History = ended rows (never deleted).
- `adv_assign_runs` — org_id, strategy, scope, dry-run plan hash, counts, status, actor. Apply needs the plan hash
  from the dry run (409 `plan_stale` if the data changed) → idempotent.
- `adv_handovers` — org_id, member_id, from/to advisor, summary JSON snapshot, acknowledged_at.

Casework
- `adv_flags` — org_id, member_id, category_id, priority, status (open · acknowledged · contacted · resolved ·
  dismissed), source (manual · rule), risk_event_id, note, outcome_note (required on resolve), review_due_at,
  owner_id, timestamps, soft delete.
- `adv_risk_events` — org_id, member_id, rule_id, term_id, evidence JSON (rule, values, thresholds),
  dedupe_key UNIQUE, flag_id, fired_at.
- `adv_notes` — org_id, member_id, author_id, visibility (private · team · student), sensitive, category_id,
  appointment_id, template_id, body, edited_at, soft delete.
- `adv_threads` — org_id, member_id, kind (message · complaint · outreach), subject, status (open · answered ·
  closed · escalated), priority, sla_due_at, last_message_at, work_item_id (when escalated).
- `adv_messages` — thread_id, org_id, sender_id, body, created_at; `adv_message_reads` (thread, user, read_at).
- `adv_attachments` — org_id, owner type/id, storage key, name, mime, size (governance storage helpers).
- `adv_plans` — org_id, member_id, title, status (draft · active · completed · cancelled), measure
  (e.g. target term GPA), follow_up_at, student_visible. `adv_plan_items` — goal/action, owner, due_at, status, done_at.
- `adv_case_links` — org_id, member_id, kind (support_request · referral · complaint_escalation), work_item_id,
  created_by. (The request itself is a governance `OrgWorkItem`.)

Appointments
- `adv_availability` — org_id, advisor_user_id, weekday, start/end (local time), slot_minutes, modes,
  location / video link (https only), valid_from/to.
- `adv_availability_off` — advisor, date range, reason.
- `adv_appointments` — org_id, member_id, advisor_user_id, starts_at, ends_at, mode (in_person · video · phone ·
  chat), location/link, status (booked · cancelled · completed · no_show), reason, cancelled_by, cal_meeting_id,
  reminder flags. Unique active (advisor_user_id, starts_at) — two students can never take one slot.
- `adv_feedback` — org_id, advisor_user_id, term_id, rating 1–5, comment (no student id);
  `adv_feedback_tokens` — appointment_id, token hash, used_at.

Outreach, notices, analytics
- `adv_outreach` — org_id, sender_id, filter snapshot JSON, subject, body, count;
  `adv_outreach_recipients` — member_id, delivered_at, read_at.
- `adv_notice_log` — org_id, user_id, template_key, channel, dedupe_key, notification_id, status, sent_at
  (delivery log + de-duplication + cool-down).
- `adv_student_stats` — one row per (org_id, member_id): primary_advisor_id, cgpa, last term GPA, absence max,
  failed count, open flags by priority, risk_score + reasons JSON, last_contact_at, meetings this term,
  graduation status, updated_at. The advisor list and every director count read this table only; indexes
  (org_id, primary_advisor_id, risk_score DESC), (org_id, risk_score DESC), (org_id, last_contact_at).
- `adv_term_stats` — per org/term/advisor pre-computed aggregates (meetings, no-shows, response times, alerts
  opened/resolved, GPA change after intervention, retention).

### 3.3 Backend layout (`services/organization/advising/`, routers `org_advising_router.py` + member router)
`access` · `policy` (settings schema, resolution) · `assign_algo` (pure: round-robin, capacity, department-aligned,
manual lock, conflicts, continuity) · `assignments` (dry run / apply / reassign / handover) · `flags` (lifecycle
state machine, pure transitions) · `risk_rules` (pure evaluators + explanation) · `risk_engine` (bulk snapshot per
org → evaluate → upsert events/flags) · `score` (pure risk score + reasons) · `notes` · `threads` · `appointments`
(slots, booking, CAS, ics) · `requests` (governance bridge: support requests, escalation, referrals) · `plans` ·
`outreach` · `stats` · `analytics` · `notify` (templates ar/en, dedupe, digest, `flush(after)`) · `jobs` ·
`export_data` (Export Studio datasets) · `text` (code → ar/en).
Routes: staff `/api/v1/org/orgs/{org_id}/advising/…`, students `/api/v1/org/public/{org_id}/advising/…`.
Lists: `page`, `size ≤ 100`, sort, filters, envelope `{items,total,page,size,pages,facets}`; errors
`{code, message, message_en}`.

### 3.4 Assignment and welcome
- Dry run → plan (per advisor: before / after load, students moved, conflicts skipped, over-capacity warnings) →
  apply with plan hash. Bulk insert, one transaction, audit summary + one audit row per batch.
- Advisors on leave / sabbatical / left are excluded; over 80 % of capacity → warning; never above max unless forced
  with a reason.
- New students: the tick assigns students without an active primary (claim per org). Join approval also triggers
  it straight away.
- Welcome: student gets "Your academic advisor is X" with contact and office hours (in-app + push + e-mail when the
  org's e-mail channel allows); each advisor gets ONE grouped notice for the batch.
- Reassignment (advisor leaves / overload / manual): bulk move with handover summary to the new advisor; history
  intact.

### 3.5 Early warning
- Hourly claimed job per org (after the registrar tick), plus "evaluate now" for the director. Builds one bulk
  snapshot (no N+1), runs the pure rules, writes `adv_risk_events` keyed by
  `dedupe_key = rule:member:term:bucket`, opens or updates one flag per (member, rule category), respects
  cool-down, notifies the advisor(s) with a "Propose a meeting" action, urgent → director too.
- Digest option: advisor gets a daily summary instead of single alerts.
- Explanation stored on each event and shown in the UI ("CGPA 1.62 < 2.00, down 0.48 since Term 1").
- Risk score (0–100) per student: grades, attendance, open flags, days since last contact; reasons listed.

### 3.6 Appointments
Weekly availability + days off → free slots computed on read in the org timezone, minus booked appointments and
the advisor's calendar busy times. Booking is a CAS insert (unique slot) and creates a `CalMeeting`
(`source_type="advising"`). Reminders 24 h and 1 h before (notice log dedupe). Advisor marks completed / no-show and
writes meeting notes from a template; completion sends the anonymous survey link. `.ics` per appointment.

### 3.7 Requests, council escalation, referrals
- A support request = governance `OrgWorkItem` (type `request`, beneficiary = student, payload
  `advising.{member_id, support_type}`) owned by the Advising department, linked in `adv_case_links`.
- New governance chain step kind **`student_department_council`**: resolved when the request is submitted to the
  council of the student's program department. Default advising chain = [Advising Director review →
  student_department_council → faculty_council]; the admin adds / removes / reorders steps (e.g. Student Affairs
  committee = an `entity` step). Reuses councils, voting, SLA timers, attachments, CAS decisions.
- The app shows the requested stages (draft · submitted · at department council · at faculty council · approved ·
  rejected · needs more info · closed), derived from status + current step.
- Final decision → student AND advisor notified (beneficiary + submitter), outcome written to the student timeline.
- Referral to Medical Care / Youth Welfare / Student Affairs = a work item routed to that service department
  (presets `healthcare`, `student_activities`, `student_affairs`); its outcome returns to the advisor.
- Complaint threads the advisor escalates become governance complaint items to the Advising Director.

### 3.8 Roles and privacy
| Role | Sees |
|---|---|
| Org admin | everything in the org, config |
| Advising Director | every student, advisor, load, analytics; sensitive notes (audited) |
| Advisor | own assigned students only; own sensitive notes; team notes of shared students |
| Student | own advisors, office hours, appointments, threads, student-visible notes, plan, request status; never flags, risk, internal notes |
| Council members | the requests on their agenda (governance rules) |
| Service dept staff | referrals routed to them only |
- Sensitive categories (health, psychological, financial, accessibility): readable only by the owning advisor and
  the director; every read audited.
- Retention: sensitive notes purged N months (configurable) after the membership ends; student data included in
  the existing privacy export and erased on account deletion.

### 3.9 Analytics
Director page from `adv_student_stats` / `adv_term_stats` (+ 60 s cache): load distribution, unassigned,
struggling by category and priority, risk trend, GPA distribution, meetings / completion / no-show, response time,
complaints, request pipeline, advisor activity (active = meeting, reply or note in the last N days), outcomes.
Every chart drills down to a permission-scoped student list. Exports, async jobs, scheduled e-mailed reports and
the compliance report are Export Studio datasets (`adv.students`, `adv.advisors`, `adv.flags`,
`adv.appointments`, `adv.compliance`).

### 3.10 Flutter (`lib/features/org/advising/`)
`adv_models.dart` (pure) · `adv_api.dart` (`AdvApi(orgId)`) · `adv_wiring.dart` (service sub, department tab
`advising`, member pill "My advisor", deep links `org_adv_student` / `org_adv_appointment` / `org_adv_thread`,
inbox actions, attention keys) · `adv_config_page.dart` · `adv_director_page.dart` · `adv_workspace_page.dart`
(my students, risk-sorted, debounced search, filters, paging) · `adv_student_page.dart` (360: overview, GPA trend,
grades, attendance, flags, notes, meetings, requests, plan, timeline) · `adv_appointments.dart` (availability
editor, booking) · `adv_threads.dart` · `adv_requests.dart` · `adv_plan.dart` · `adv_student_hub.dart` ·
`adv_draft_store.dart` (offline drafts, synced on reconnect). Presentational widgets take plain values for the
layout harness. Strings: `t(ar,en)` per org convention; error codes in `orgErrorText`. The registrar's
`OrgAdvisingScreen` becomes the workspace's "Registration cases" tab (same API, still reachable).

### 3.11 Tests
Backend: `advising_algo_unit.py`, `advising_risk_unit.py`, `advising_flow_unit.py` (state machines) ·
`e2e_advising_assign.py`, `e2e_advising_casework.py`, `e2e_advising_appointments.py`, `e2e_advising_requests.py`,
`e2e_advising_isolation.py` (two orgs, one student, every route attacked) · `advising_perf_pg.py` (100 k students on
`nb-pg`, p95 of list endpoints < 300 ms). App: `test/org/adv_*_test.dart`, `test/ui/adv_*_layout_test.dart`,
a11y entries, contract + feature-key + payload snapshots.

## 4. Delivery phases and the 26 defaults

Each phase = backend + app slice, gates green (backend suite, `flutter analyze` CI flags, test suites, web build,
gitleaks), then merged into `organizations` → `production` (backup tag, fast-forward), **not deployed** (owner's
rule: one deploy after all sessions).

| Phase | Content | Defaults |
|---|---|---|
| 2 Foundation | migration 0049, models, RLS, access module, RBAC module + director role, audit helpers, notice log, kill switches, eligibility gate | 1, 3, 4, 8 (rules), 9 (reuse OrgTerm), 11 (indexes) |
| 3 Config + assignment | policy screens, profiles/leave, dry run + apply, new-student auto-assign, welcome notices, reassignment + handover, conflicts/continuity | 2, 5, 17, 22 |
| 4 Workspace | my students (risk-sorted), 360, flags + lifecycle, notes + visibility, timeline, offline drafts | 6 (flags), 7 (lifecycle), 8 (notes), 21, 23, 24 (category) |
| 5 Appointments + messages | availability, booking, reminders, no-show, meeting notes, ics, threads/complaints + escalation, templates, student hub, survey | 6 (threads), 15, 16, 18 |
| 6 Early warning | rules, engine, events, score, alerts, digest, nudges, graduation risk | 7, 13, 20, 21 (score) |
| 7 Requests + councils | support requests, `student_department_council` step, configurable chain, outcomes, referrals, support plans, accommodations | 6 (requests), 12, 14, 24 |
| 8 Analytics | director dashboard, drill-down, Export Studio datasets, scheduled reports, outreach, outcomes, compliance, health check | 10, 19, 25, 26 |
| 9 Hardening | 100 k perf on PG, security review, retention purge, privacy export/delete, OpenAPI, docs, feature guide, documents | 8 (retention), 11 (verify) |

Core (must ship): 1–9, 11, 17, 18, 21. Advanced (after core is stable, still in this job): 10, 12–16, 19, 20, 22–26.
Nothing is dropped. Changes to the brief: no new term entity (OrgTerm exists, #9); one severity/priority scale;
no new workflow engine (governance); disciplinary conflicts are declared by hand because the platform has no
disciplinary records (#22).
