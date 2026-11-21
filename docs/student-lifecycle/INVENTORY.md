# Student lifecycle: inventory of what exists (step A)

Checked in code on 2026-11-21: back `_wt/sl-back` @ e2c804f, front `_wt/sl-front` @ 72c211c4.
Back paths are relative to `sl-back/` and front paths to `sl-front/lib/`.
"Not verified" marks anything I took from docs or comments without reading the code.

**Docs have drifted.** `sl-front/lib/features/org/CLAUDE.md` still names `routers/organization/…` and `services/organization/…`. The code now lives in `features/org/<area>/` with `api/` routers. The calendar is in `lib/features/calendar/`, not `lib/features/shared/calendar/`. The registrar section of that CLAUDE.md says "no Alembic, `ensure_registrar_tables` adds them". Those columns are frozen in `0001_baseline`, so any new column needs a revision.

**Latest Alembic revision is `0101`** (`migrations/versions/0101_onboarding_nid_kind.py`, down_revision `0100`). This job starts at `0110` (PROGRESS.md).

---

## 1. Member onboarding (D-1200 – D-1219): **built, phases A–D shipped**

**Tables** (`data/onboarding_models.py`, migration `0099_member_onboarding`, plus `0100` help pages and `0101` nid_kind width):

| Table | Key columns |
|---|---|
| `org_member_types` | org_id, key (unique per org), label_ar/en, base_role, module (`students\|teachers\|staff`), fields JSON, documents JSON, chain JSON, settings JSON, preset_key, active, sort, intake_code_hash |
| `org_onboarding_cases` | type_id/type_key, status, step, source (`manual\|excel\|invite\|intake\|self`), subject_user_id, full_name, name_en, name_norm, email, phone, nid_kind (`national_id\|passport`), nid_enc, nid_hash, nid_last4, nationality, birth_date, gender, data JSON, dept_id, program_id, conditional, due_at, decision_reason, submitted/decided/activated_at, member_id, invitation_id, batch_id |
| `org_case_documents` | req_key, version, current, status (`uploaded\|verified\|rejected\|deferred\|waived`; a missing document has no row), bucket/object_key, mime, size, verified_by/at, note, due_at |
| `org_case_events` | append-only timeline: kind, from/to status, reason, details |
| `org_import_batches` / `org_import_rows` | staged dry run (24 h): mode (`submit\|invite\|draft`), per-row state (`ok\|warning\|error`) + messages |
| altered | `org_invitations.case_id` (FK SET NULL); `org_members.onboarding_case_id` (plain Integer) |

**Statuses** (`CASE_STATUSES`): `draft, submitted, under_review, needs_correction, approved, active, rejected, withdrawn`.
- `TRANSITIONS` is in `features/org/onboarding/service.py:57`.
- Approval advances `step` through the chain. The final step leads to `approved`, with `conditional` set when documents are owed.
- `activate` (`service.py:680`) runs automatically when `settings.auto_activate` is on. It creates or links the account and the `OrgMember`, then calls `_place` (program / department).
- Any other transition answers 409 `bad_transition`.

**Approval chain.** Each type holds a list of steps, and each step needs either `{module, action}` or `{org_role: dept_head, scope: case_dept}`. An org_admin acting on a step it doesn't hold is audited as an override.

**Presets** (`data/onboarding_presets/`): `egypt_public`, `egypt_private`, `azhar`, `institute`.
- Each holds the types `student_new`, `student_transfer`, `student_postgrad`, `student_international`, `teaching_assistant`, `faculty`, `admin_staff`. The `faculty` key appears twice in every preset file; I have not checked why.
- Military forms are conditional. Guardian fields apply under 18. Passport and equivalency apply to non-Egyptians.
- The first `GET types` seeds `egypt_public` lazily.

**Back modules** (`features/org/onboarding/`):
- `service.py`: types, cases, state machine, duplicates, activation.
- `validation.py`: Egyptian national ID, passport 5–20, phone, `normalize_ar_name`, conditional `when`.
- `documents.py`: magic-byte sniffing, re-encoding, 60 s presigned links.
- `importer.py`: xlsx / csv with utf-8 / cp1256, 5000 rows, 8 MB, and the template built from the type's config.
- `invite.py`, `notify.py`, `report.py`, `sweep.py`.

**Endpoints** (router `features/org/onboarding/api/org_onboarding_router.py`, prefix `/api/v1/org`):
- Staff: `GET presets`, `GET reject-reasons`, `GET|POST types`, `PUT types/{key}`, `POST types/from-preset`, `PUT types/{key}/intake`, `GET summary`, `GET report` (also `?format=xlsx`).
- Cases: `GET|POST cases`, `GET|PATCH cases/{id}`, and `POST cases/{id}/{submit|claim|request-correction|approve|reject|activate|withdraw}`. Each case lists required / missing fields and documents (`missing_count`).
- Documents and IDs: `POST cases/{id}/documents`, `PATCH documents/{id}` (`verify|reject|waive|defer|reopen`), `GET documents/{id}/file`, `GET cases/{id}/nid`.
- Import and invitations: `GET templates/{type}`, `POST imports`, `GET imports/{b}`, `POST imports/{b}/confirm`, `GET imports/{b}/report`, `POST cases/invite`. All staff routes sit under `/orgs/{org_id}/onboarding/`.
- Applicant: `GET /me/onboarding`, `GET|PATCH /me/onboarding/{id}`, `POST …/{id}/submit|withdraw|documents`, `GET /me/onboarding/documents/{id}/file`, `POST /me/onboarding/intake/{code}`.
- Public: `GET /public/onboarding/intake/{code}` (throttled `intake_ip` 30 / 15 min).

**Permissions** (from CONTRACT §3; the routes I sampled match):
- Viewing uses the type's module `M:view`, creating `M:insert`, editing and corrections `M:update`. Approval needs the step's `need`.
- `onboarding:view|update` configures types and intake links.
- `member_documents:view` opens identity files and unmasks the ID. It is left out of the `viewer` system role.

**Privacy.**
- The national ID or passport is Fernet-encrypted (`helpers/pii.py`, `PII_KEY`) with an HMAC blind index. Lists show only the last 4 digits.
- Opening a document is audited as `onboarding.document_viewed` and unmasking as `onboarding.nid_viewed`.
- On activation, a national ID is also written in plain normalised form to `user_identity_values` (`field_key national_id`) for exams. A passport is not written there.

**Duplicates** (`service.duplicates`, per org only):
- Hard (409): the same `nid_hash` in an open or active case gives `duplicate_case`. The same national ID on a live member, matched through `user_identity_values`, gives `duplicate_member`.
- **A passport is matched only against cases, never against existing members.**
- Soft warnings: same email, same phone, same `name_norm` + birth date, and `reapplicant` (a rejected or withdrawn case).

**Sweep** (`sweep.py`, hourly `org_onboarding_tick` in `features/platform/scheduler_service.py`): reminders at due −7 / −3 / −1 days, an overdue flag that only flags (D-1205), expiry of staged batches, and a purge of rejected / withdrawn documents after `purge_rejected_days`.

**Notifications.** `notify_users` reaches the subject and the step holders. Live event `onboarding`, attention tab `org_onboarding`.

**Front** (`features/org/onboarding/`):
- Data and rules: `onboarding_models`, `_api`, `_rules` (the mirror of the validator).
- Staff pages: `onboarding_page` (stage tabs To review · Needs correction · Conditional · Drafts · Done), `_wizard` (autosave drafts, used by staff and applicants), `_review` (master-detail with document preview and timeline), `_types_page`, `_import`, `_invite`, `_intake` (link + QR), `_report`.
- Applicant and entry: `_applicant` (the My organizations card + page), `_entry` (People's "Add member" / "Import" route into a case while `org.onboarding` is on), `_errors`.
- Home card `features/home/home_application_card.dart` (from `/me/home`).
- Deep links `/org/:orgId/onboarding/:caseId` and `/onboard/:code`. Push types `org_onboarding` and `onboard_intake` in `utils/widget/app_navigator.dart`.

**Gaps seen:**
- `settings.student_code_pattern` is never used, so no student number is generated on activation.
- Transfer credit equivalency (the "equivalency table" of PLAN §2.2) is not built anywhere: there is no registrar transfer-credit model.
- There is no "copy from last year".
- There is no "missing data" indicator for existing members, only for cases.
- Fees are a field only (D-1204).

## 2. Registrar / academic

**Tables:**

| Table | Where | Key columns |
|---|---|---|
| `organizations` | `data/models.py` | `study_system` (`traditional\|credit_hours\|NULL`, rev 0085), `settings` JSON: `academic` (levels, selection, …) and `registrar` (rules), `registrar_state`, `levels_advanced_on` |
| `org_terms` | `data/org_models.py:463` | year_label, kind (`term1\|term2\|summer`, no `makeup` kind), start/end dates, `calendar` JSON (generated milestones) |
| `org_programs` | `:521` | code, manager, capacity, prerequisites, `system_type` (`credit_hour\|traditional`), total_credits, min_cgpa, requirement_groups, entry_level, `progression {max_carry}` |
| `org_program_courses` | `:550` | kind `entry\|required\|elective`, group_key, level_key, term_kind |
| `org_student_academic` | `:563` | stage (`general\|program\|graduated`), program_id, requested_program_id / second_choice + request_status, joined_at, graduated_at, cgpa, earned/attempted credits, `standing` (`good\|probation\|honours`), `probations` count, audit_at, advisor_id |
| `org_level_advances` | `:808` | from/to level, via (`auto\|staff\|hours\|year`), rules snapshot. An append-only log |
| `org_course_runs` / `org_run_results` | `:478` / `:494` | the course-run archive; result `passed\|failed` |
| `org_sections`, `org_registrations`, `org_decisions` | `data/registrar_models.py` | see below |

- **`org_registrations`** is the transcript row: status (`registered\|waitlisted\|dropped\|withdrawn\|completed`), credits, `attempt`, condition, override_by/reason, percent, letter, `grade_state` (`none\|draft\|submitted\|approved`), absence_pct, `denied`, interim_percent.
- **`org_decisions`** holds the cases the server could not settle: kind, status (`open\|accepted\|edited\|rejected\|resolved`), recommendation, alternatives, risk, auto_applied, dedupe.
- Registrar columns come from `REGISTRAR_COLUMNS` / `ensure_registrar_tables`, frozen in `0001_baseline`.

**Rules** (pure, `features/org/academic/registrar/policy.py`, `DEFAULT_RULES`, merged over the org chain's `settings.registrar`):
- Grade scale and pass: A–F at 4.0, pass letter D, `NON_GPA` = W, I, P, NP, IP, and DN (attendance denial).
- Load bands by CGPA; summer load 0–9.
- Levels by earned hours (`level_hours` / `level_step`).
- Standing: `probation_below 2.0` after 12 credits; honours at term GPA ≥ 3.5; `dismiss_after_probations: 0`.
- Retake: `allowed_below C`, at most 3 attempts, counting `latest|highest`.
- Waitlist; attendance warnings at 10 / 20 % and denial at 25 %; graduation `min_cgpa 2.0`.
- Calendar offsets, specialisation by merit, `traditional.max_carry 2`, staff weekly caps.

**Services:**
- `registrar/service.py`: eligibility (`evaluate`), register / cart / drop, `put_grades → submit_grades → approve_grades`, `recompute` (`:882`: CGPA, standing, probation counter, level by hours that never goes down plus an `OrgLevelAdvance`), `attendance_pass`, `degree_audit`, `graduation_candidates`, `graduate` (`:1038`, sets stage `graduated` and audits), and the decisions `ACTIONS` registry.
- `traditional.py`:
  - `cohort_enrol` registers a cohort automatically, carry-overs included.
  - `promote`: everything passed moves to the next year, up to `max_carry` failures move "with carry", more repeat, and the last year opens a graduation decision. It audits `registrar.promote`.
  - `makeup_round` registers failed courses in a summer / make-up term.
- `jobs.py`, the hourly `_registrar_tick`:
  - generates calendars, syncs sections, runs cohort enrolment, promotes waitlists and runs attendance.
  - runs the suggestions in `academic/auto_create.py`, merit allocation after the selection deadline, and `_year_promotion` (automatic once the term-2 `results_release` date has passed).
  - opens a `graduation_candidates` decision.
- Also: `allocation.py`, `consent.py`, `midterm.py`, `record.py`; levels and their prerequisites, plus scheduled auto-advancement, in `academic/academic_levels.py`; the config reader `academic/academic_config.py`.

**Endpoints**, staff, prefix `/api/v1/org/orgs/{org_id}/registrar` (`academic/api/org_registrar_router.py`):

| Group | Routes (permission) |
|---|---|
| Rules and courses | `GET\|PUT rules` (academic view / update); `GET courses`, `PUT courses/{cid}`, `PUT courses/{cid}/requisites` (courses) |
| Programs and staff | `GET\|PUT programs/{pid}` (academic); `PUT members/{mid}/rank`, `GET members/{mid}/load` (teachers) |
| Calendar and sections | `GET\|PUT terms/{tid}/calendar`, `POST …/calendar/generate`, `POST terms/{tid}/sections/sync`; `GET terms/{tid}/sections`, `PUT sections/{sid}` (enrollments) |
| Registrations | `GET\|POST terms/{tid}/registrations`, `POST registrations/{rid}/drop` (enrollments) |
| Grades and attendance | `GET\|PUT terms/{tid}/grades/{cid}`, `POST …/approve` (**academic:approve**); `POST terms/{tid}/attendance/run` |
| Record and decisions | `GET students/{uid}/record` (students:view); `GET decisions`, `POST decisions/{did}/{verdict}` (academic:approve) |
| Graduation and risk | `GET graduation/candidates`, `POST graduation/{uid}` (academic:approve); `GET terms/{tid}/report`; `GET at-risk` (students:view) |
| Advisors and allocation | `PUT students/{uid}/advisor`, `POST advisors/auto`, `POST allocation` |
| Traditional system | `POST terms/{tid}/cohort-enrol`, `POST programs/{pid}/promote` (academic:approve, `dry_run`), `POST programs/{pid}/makeup` |
| Groups | `GET\|POST terms/{tid}/groups/{cid}[/distribute]`, `POST registrations/{rid}/group`, `GET terms/{tid}/students/{uid}/groups` |

- **Midterm router:** `GET|PUT terms/{tid}/midterm/{cid}`.
- **Member routes**, `/api/v1/org/public/{org_id}/registrar`: `terms`, `terms/{tid}/offerings`, `register`, `register-requests`, `exception`, `registrations/{rid}/drop`, `record`, `teach…` (grades), `advising…`, `consents`, `terms/{tid}/my-timetable`.
- **Academic router**, `/api/v1/org/orgs/{org_id}/academic`: `settings`, `terms` CRUD, course runs and archive, `archive-requests`, `programs` CRUD + prerequisites, `levels` (+ `order`, `advance`), `students` (`?stage=&program_id=`), `students/{uid}/level|program|request/{decision}|graduate`.
- **Academic member routes**: `/public/{org_id}/my-path`, `choose-department`, `my-level`, `courses/{cid}/access|eligibility|archive-request`.

**Front:**
- `features/org/org_registrar_staff.dart`, `OrgRegistrarPage` (Academics → Registrar), with tabs Decisions · Terms · Courses · Programs (promote / makeup dialogs) · Staff · Rules · Graduation & at risk.
- `org_registrar_member.dart`: `OrgRegistrationScreen`, `OrgRecordScreen` (also opened by staff with `studentId`), `OrgTeachScreen` / grades, advising, consents.
- `org_registrar_midterm.dart`; `org_registrar.dart` (code → text maps).
- `org_academic_pages.dart` (`OrgAcademicPage`: Calendar · Departments · Graduation & settings · Students · Archive requests; `MyAcademicPathPage`).
- `org_levels*.dart`.

**Gaps seen:**
- **Dismissal:** `dismiss_after_probations` exists only in `DEFAULT_RULES`. Nothing reads it, and there is no dismissed status.
- **Academic warning:** probation is only a cached `standing` plus a counter. No formal warning letter, no notification to the student, no per-term standing history.
- **Repeating a year:** `promote` lists `repeat` students but writes nothing for them: no status, no flag, no notice.
- **Make-up term:** no `makeup` term kind; it is a summer term or one chosen by hand.
- **Transfer credit:** none (no equivalency / credited-course record).
- **Credit-hour progression** is automatic by hours (in `recompute`). **Traditional progression** is automatic once a year in `_year_promotion`, and also manual through `POST promote`.

## 3. Where a student "status" lives today

| Field | Values | Set by | History |
|---|---|---|---|
| `org_members.status` | `active, pending, rejected, suspended, expired` (+ derived `scheduled`, `removed`) plus `ended_at`, `end_reason`, `starts_at`/`expires_at` | `PUT /orgs/{o}/members/{mid}` (`core/api/org_admin_router.py:832`), extend, delete | Audit `member.update` with the changed fields in `meta`, but no `before`. No status-history table and no undo. |
| `org_members.cohort` | `current, incoming` | staff / import | none |
| `org_members.academic_level` | the org's level keys | auto (hours / year / level rules) or staff (`students/{uid}/level`) | `org_level_advances` (append-only, no undo) |
| `org_student_academic.stage` | `general, program, graduated` | academic router, `graduate()` | `joined_at`, `graduated_at` only; audit `registrar.graduate` |
| `org_student_academic.request_status` | `pending, approved, rejected` (department choice) | student / staff / merit allocation | — |
| `org_student_academic.standing` | `good, probation, honours` + `probations` count | `recompute` after grade approval | none (overwritten) |
| `org_registrations.status` / `grade_state` / `denied` | see §2 | registrar | `org_registrations` rows are the transcript |
| `org_onboarding_cases.status` | see §1 | onboarding | `org_case_events` |
| `adv_student_stats.graduation_status` | `on_track, delayed, at_risk, graduated, unknown…` (computed, `advising/graduation.py`) | advising stats job | — |
| `adv_flags.status` | `open, acknowledged, contacted, resolved, dismissed` | advising | audit rows (timeline) |

**Missing:** one enrolment status for a student's academic registration, such as active / suspended enrolment (إيقاف قيد) / leave of absence / withdrawn / dismissed (فصل) / graduated / transferred out. There is also no reason / decision number / effective date for a status change, and no reversible status history.

## 4. Advising, complaints, calendar, notifications, ask-the-user

**Academic advising (D-289).**
- Tables `adv_*` live in `data/advising_models.py`, `advising_request_models.py`, `advising_warning_models.py` and `advising_analytics_models.py`, from migrations 0050–0062.
- Back code is in `features/org/advising/` (about 60 modules). The routers in `api/` have about 126 routes under `/orgs/{o}/advising/…` and `/public/{o}/advising/…`.
- What it covers: assignment and handover, flags, notes, threads, appointments with availability, support requests (which are governance work items), plans, accommodations, outreach, analytics, and the early-warning engine.
- Risk kinds are `gpa_below, gpa_drop, failed_courses, repeated_fail, absence_pct, absence_count, no_contact, graduation_delay, midterm_fail`.
- Retention purge and privacy deletion are in place.
- Permission is the `advising` module plus advisor / director roles (`advising/access.py`). Students are denied by `CONFLICT_RULES`.
- Front `features/org/advising/adv_*.dart`, with the student 360 in `adv_student_page.dart` (header, overview, academic, flags, notes, timeline).
- Kill switches `org.advising`, `.warning`, `.analytics`, `.outreach`.

**Complaints.**
- Table `org_complaints` (`data/org_models.py:282`): ref, dept_id, category (`academic|financial|administrative|technical|conduct|facilities|general`), priority (`low|medium|high|urgent`), status (`open|in_progress|waiting|resolved|closed`), is_anonymous, assigned_to, due_at (SLA), rating.
- `org_complaint_messages` holds internal notes.
- Staff routes are in `features/org/services/api/org_services_router.py`: `GET complaints`, `/export`, `GET|PUT complaints/{cid}`, `POST …/messages`, `POST …/meeting` (creates a `cal_meetings` row with `source_type=complaint`).
- Member routes are in `features/org/core/api/org_member_router.py`: `POST /public/{org_id}/complaints`, `/me/complaints`, `/me/complaints/to-resolve`, `/complaints/{cid}`, `…/messages`, `…/rate`, `…/{close|reopen}`.
- Handled by `complaints:view|update|delete|export`, scoped by department (dept_head and dept_staff have it). Reports are in `features/org/governance/api/org_reports_router.py`.
- Front: `features/org/org_services_pages.dart` (`OrgComplaintsPage`, `OrgComplaintThreadScreen`), `features/profile/compalints/`, and `features/org/org_reports/`.
- There is also a separate platform complaints table, `complaints` (`features/platform/api/complaint_router.py`).

**Governance requests** (`data/governance_models.py`, `org_work_*`, councils): ITEM_STATUSES run from `draft` to `rejected`/`postponed`, plus approval chains, councils and votes.

**Calendar.**
- `features/home/api/calendar_router.py`, prefix `/api/v1/me/calendar`: `GET` (merged range), `GET depts/{id}`, `GET people`, `POST busy`, `POST meetings` (409 `attendees_busy` unless `force`), `POST meetings/quick`, `GET|PATCH|DELETE meetings/{id}`, `POST …/respond|accept-proposal|join`.
- Tables `cal_meetings` (owner, org/dept, audience, `source_type`/`source_id`, mode, status) and `cal_meeting_attendees` (`pending|accepted|declined|proposed`), in `data/calendar_models.py`.
- Front `features/calendar/schedule_page.dart` (`SchedulePage`), `schedule_store.dart` (`CalendarStore`), `calendar_meeting.dart`.

**Notifications.**
- `notify_users(db, ids, title, message, related_type, org_id, data, important, push, action, link)` is in `features/org/core/org_service.py:721`. It writes the in-app row, sends a push according to the org's notify settings, and falls back to e-mail when the push fails (`features/notifications/notification_service.py`). It also emits the attention live event.
- Live event names in `features/notifications/live_update_service.py` include `onboarding`, `org_message`, `org_must_ack`, `org_access_changed`. Front `utils/live_events.dart`; attention keys in `core/attention/attention_service.dart`.
- Reminder sweeps: onboarding (hourly), advising (`_advising_tick_sync`, every 10 minutes: SLA escalation, reminders), registrar (hourly: absence warnings).

**Ask-the-user mechanisms:**
- **Must-acknowledge full-screen card:** `org_messages.delivery = must_ack` with `reason` and `expires_at ≤ 7 d`, and `org_message_recipients.acked_at`. Front `features/org/org_must_ack.dart`, `OrgMustAckHost` in `MaterialApp.builder` (`GET /me/must-ack`). Kill switches `org.messages`, `org.messages.must_ack`.
- **Terms acknowledgement:** `org_term_items.requires_ack` + `org_term_acks`.
- **Dynamic forms:** `org_forms` / `org_form_responses`, plus `org_form_assignments` (governance).
- **Advising post-meeting survey:** `advising/survey.py`, `adv_feedback_tokens`.
- **Schedule occurrence Accept / Reject:** `org_schedule_occurrence_responses`.
- **Invitation prompt:** `features/org/org_invitation_prompt.dart`.
- **None of these can ask a typed question** (e.g. "confirm your data / pick an option") and store a structured answer against a lifecycle step.

## 5. Roles and permissions

- **Models:** `OrgRole` (org_id, key, permissions JSON `{module:[actions]}`, is_system), `OrgRoleAssignment` (user, role, `dept_id` NULL = whole org, valid_from/to), `OrgUserGrant` (allow / deny JSON, dept_id, expires_at; deny always wins). All in `data/org_models.py:133-187`.
- **Legacy rights:** `OrgMember.permissions` holds rights for an admin_assistant.
- **Catalog:** `features/org/core/org_catalog.py` (`MODULES`, `SYSTEM_ROLES`, `CONFLICT_RULES`, `DEPT_PRESETS`, e.g. `student_affairs`, `student_control`, `graduates`).
- **Check:** `org_ctx(module, action)` (`org_service.py:491`) checks org-wide. Department-scoped modules use `ctx.require(module, action, dept_id)` inside the route.

Modules and actions relevant here:

| Module | Actions | Used for |
|---|---|---|
| `students` / `teachers` / `staff` | view, insert, update, delete, approve, export, import | members, onboarding cases, registrar `students/{uid}/record`, `at-risk` |
| `onboarding` | view, update | types, intake links |
| `member_documents` | view | identity documents, ID unmask |
| `requests` | view, approve | join requests; accepting a pending member |
| `academic` | view, insert, update, delete, approve | registrar rules, programs, calendar, grades approval, decisions, graduation, promotion, allocation |
| `enrollments` (dept) | view, insert, delete, export, import | sections, registrations, cohort enrolment, makeup |
| `courses` (dept) | view, insert, update, delete, export, import | course academic data, requisites |
| `complaints` (dept) | view, update, delete, export | complaints inbox |
| `advising` | view, insert, update, delete, approve, export | advising (plus advisor / director roles) |
| `workflow` / `councils` (dept) | … on_behalf / approve | governance requests, council votes |
| `audit` | view, export | activity log |

- **System roles:** `admin_assistant`, `dept_head`, `dept_staff`, `viewer` (no roles / advising / member_documents), `advising_director`, `dean`, `vice_dean_education_students`, `vice_dean_postgraduate_research`, `vice_dean_community_service`, `council_secretary`.
- **No registrar / student-affairs role:** there is no `registrar` or `student_affairs` system role. Student affairs exists only as a department preset.
- **Students are denied** students update / delete / import, academic update / approve, audit, and advising (`CONFLICT_RULES`).

## 6. Org audit log

- **Model:** `OrgAuditLog`, table `org_audit_log` (`data/org_models.py:644`). Columns: org_id, dept_id, actor_id, actor_role, action, entity, entity_id, summary, meta, before, after, ip, user_agent, request_id, created_at. Indexes on (org, time), (actor, time) and (org, entity, entity_id, time). A PostgreSQL trigger (migration 0004) makes it append-only.
- **Writing an entry:** `audit(db, org_id, actor, action, summary, entity=, entity_id=, dept_id=, meta=, before=, after=)` (`org_service.py:703`). It is committed with the change. A `PERM_AFFECTING_PREFIXES` action bumps `perm_version`.
- **Reading:** `GET /api/v1/org/orgs/{o}/audit` (audit:view) and `/audit/export` (audit:export, xlsx), in `features/org/core/api/org_access_router.py`. The workspace person timeline (`ws_person.dart`) and the advising timeline also read it.
- **Read events:** "file opened" is logged ONLY for onboarding documents (`onboarding.document_viewed`) and ID unmasking (`onboarding.nid_viewed`). Opening a student's registrar record, advising 360, entity page or member row is **not** logged. `data_lab_audit` logs changes only.

## 7. The "Students" area in the org dashboard (front)

- **Navigation:** there is no "Students" section. People (`org_dashboard_screen.dart:216`, `_peopleSubs` at `:466`) holds Members (`OrgPeoplePage`), Admissions & appointments (`OnboardingPage`), Departments, and Department join requests. Academics (`_academicSubs`) holds Courses, Academic structure (`OrgAcademicPage`, whose "Students" tab shows path progress), and Registrar.
- **Teacher workspace:** `features/org/workspace/` (Management / Membership tabs, `ws_people.dart`, `ws_person.dart`) has its own people lists per unit.
- **Members page** (`features/org/org_people_page.dart`): a Students · Teachers · Staff switcher, search, status filter, Add (through onboarding), Excel import / template / export.
  - The row menu has edit membership, extend / re-admit, suspend, effective permissions, student number, enable / disable account, remove.
  - Row chips show status, student code, level, cohort and departments.
- **Student file for staff:** there is NO single org student file. Tapping a row opens the platform entity page (`EntityNavigator`, D-290, `design/master_detail/student_detail.dart` over `/api/v1/entities/students/{id}`: courses, grades, payments). It is not org-aware for academic status.
  - The registrar record (`OrgRecordScreen(studentId:)`) is reachable only from Registrar → Graduation & at risk.
  - The advising 360 (`AdvStudentPage`) is reachable only from the advising pages.
  - The onboarding case (`OnbReviewPage`) is reachable only from Admissions.

## 8. Kill switches and help ids

- **Kill switches** (`features/platform/feature_catalog.py`):
  - Onboarding: `org.onboarding`, `org.onboarding.import`, `org.onboarding.invite`, `org.onboarding.intake`.
  - Advising: `org.advising`, `org.advising.warning`, `org.advising.analytics`, `org.advising.outreach`.
  - Governance and messages: `org.governance`, `org.governance.export_hub`, `org.messages`, `org.messages.must_ack`.
  - Other org switches: `org.invitations`, `org.institution`, `org.teacher_workspace`, `org.insights`, `org.search`, `org.setup_checklist`, `org.billing_view`.
  - Platform: `complaints` (+ `complaints.stats`, `.filters`, `.attachments`), `calendar`, `calendar.entry`.
  - **There is no switch for the registrar or academic areas.**
- **Help ids wired in the front:** `org.members`, `org.onboarding`, `org.onboarding.types`, `org.onboarding.import`, `me.onboarding`, `org.advising`, `org.departments`, `org.governance`, `org.timetable`, `org.settings`, `home.org`, `home.org/people`, `home.org/academics`, `home.org/services`, `home.org/settings`, `home.org/timetable`, `home.org/ws_*`.
- **Help ids in `data/help_seed.json`:** also `org.academic`, `org.registrar`, `org.complaints`. Some ids, e.g. `home.org/people`, come from migrations (0098, 0100) rather than the seed. Not verified id by id.

## 9. Main gaps (for the planner)

1. **No academic enrolment status:** suspension of enrolment, leave, withdrawal, dismissal, transfer out, reinstatement. There is also no reasoned, dated, reversible status history. The member status has an audit row only.
2. **Dismissal rule unused:** `dismiss_after_probations` is defined but never read. Probation has no warning notice and no per-term history.
3. **Repeating a year writes nothing:** traditional `promote` computes repeaters but stores no status, flag or notice for them.
4. **No transfer-credit equivalency** (المقاصة) in either onboarding or the registrar. No student-number generation on activation.
5. **No unified staff-facing student file:** members, registrar record, advising 360 and onboarding case are separate screens. The entity page is not org-academic.
6. **No read audit** of student files outside onboarding documents and IDs.
7. **No registrar / student-affairs system role** and no registrar kill switch.
8. **No structured "ask the student" request** with a stored answer tied to a lifecycle step. Must-ack, forms and terms acknowledgements are the nearest building blocks.
9. **Duplicate checks are per organization only.** A passport is not matched against existing members.
