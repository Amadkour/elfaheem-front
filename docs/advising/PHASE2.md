# Phase 2 — Foundation: brief and contract

Read `docs/advising/PLAN.md` (this folder) first: §3.1 scoping, §3.2 data model, §3.8 roles are binding.
Owner decisions after the plan: eligible org types = `university`, `faculty`, and any org whose ancestor is one of
those (one constant `ADVISING_ORG_TYPES`); an optional midterm mark per registration is added now (columns only;
the rule comes in Phase 6).

## Common rules (every agent)
- Work ONLY in your worktree: backend `D:/platform/nextbrain/wt-back-advising`, app `D:/platform/nextbrain/wt-front-advising`,
  branch `feature/academic-advising`. Never touch `D:/platform/nextbrain/back` or `nextbrain-front` (peer sessions).
- Commit locally with `git commit --only <paths>` (after `git add -- <new files>`); never push, never merge.
- Follow the repo's CLAUDE.md files (backend `CLAUDE.md`, app `CLAUDE.md` + `lib/features/org/CLAUDE.md`).
  Don't `dart format` existing files; new files are written formatted by hand.
- The machine is shared and busy: run flutter tests with `-j 2`, one suite at a time; backend e2e scripts one at a time.
- Python: `D:/platform/nextbrain/back/.venv312/Scripts/python` (run with cwd = the backend worktree,
  `PYTHONUTF8=1`, own `DATABASE_URL=sqlite:///<scratch>/x.db` per script). If an import fails because the venv lags
  `requirements.txt`, report it rather than pip-installing blindly.
- No placeholders, TODOs, mock data in production paths, or dead code. Arabic + English for every user-facing text.
- Lead owns: `docs/DECISIONS.md`, `docs/advising/*`, contract snapshots (`test/contract/*.json`), `main.dart`,
  `app_routes.dart`. Don't edit them.
- Final report ≤ 15 lines: what was built, files, test commands + results, open issues.

## Backend scope
1. `data/advising_models.py`: every `adv_*` table of PLAN §3.2 (columns, enums as String + CHECK-free validation
   in code like the rest of the repo, FKs to `organizations.id`, `org_members.id`, `users.id`, timestamps naive UTC,
   soft delete `deleted_at` on flags / notes / plans / templates / categories). Indexes for the dashboard queries
   (org_id first). **Partial unique indexes** (work on PG and SQLite):
   one active primary per (org_id, member_id) on `adv_assignments`; unique active (org_id, member_id, advisor_user_id);
   unique active (advisor_user_id, starts_at) on `adv_appointments`; unique `adv_risk_events.dedupe_key`;
   unique (org_id, member_id) on `adv_student_stats`; unique (org_id, user_id) on `adv_advisor_profiles`.
   Add `interim_percent` (Float, null), `interim_at`, `interim_by` to `OrgRegistration` (model + revision — NOT
   `REGISTRAR_COLUMNS`). Make the e2e schema build see the new models (create_all import path).
2. `migrations/versions/0049_advising.py` (down `0048`): create tables with `create_table_if_missing`, the new
   registration columns with `add_column_if_missing`, PG RLS `tenant_isolation` policy on each `adv_*` table with
   `org_id` exactly as `0048` does, reversible downgrade. Data step: for every org that is eligible, copy each
   non-null `OrgStudentAcademic.advisor_id` (whose advisor is still a live member of that org) into `adv_assignments`
   as type primary, source `legacy`, locked true — idempotent (skip if an active primary exists).
3. `services/organization/advising/`:
   - `access.py`: `eligible(db, org)` (type or ancestor type), `is_enabled`, `require_enabled` (403
     `advising_not_available` / `advising_disabled`, plus 403 `feature_disabled` when the platform kill switch
     `org.advising` is off), role resolution `roles(db, ctx|user, org)` → admin / director / advisor / student,
     where director = head of an org department with preset `academic_advising`, or a holder of system role
     `advising_director`, or org admin; `student_scope(...)` SQL filter used by every later list
     (director/admin: whole org; advisor: EXISTS active assignment; student: own member row);
     `log_sensitive_read(...)` writing `OrgAuditLog` action `advising.sensitive_read`.
   - `policy.py`: Pydantic settings schema with defaults (eligible roles/ranks [default role teacher], mode single,
     max_load 40, warn_pct 80, strategy balanced, auto_assign true, digest off, sla_hours per priority, nudge days,
     retention_months 24, survey on, workflow steps default [director_review, student_department_council,
     faculty_council]); resolution most specific scope → org → ancestor orgs → defaults; pure functions testable
     without a DB.
   - `assignments.py` (minimal now): `set_primary(db, org_id, member_id, advisor_user_id, source, actor)` — ends
     the current primary (history kept), inserts the new one, mirrors `OrgStudentAcademic.advisor_id`, audits
     before/after. Route the registrar's existing `PUT …/registrar/students/{uid}/advisor` and
     `POST …/registrar/advisors/auto` writes through it when advising is enabled for that org, so the two never
     diverge (keep their current responses).
   - `seed.py`: idempotent defaults per org on enable — flag categories (academic, financial, career, health,
     psychological, disciplinary, accessibility, other; health/psychological/financial/accessibility sensitive),
     risk rules (gpa_below 2.0, gpa_drop 0.5, failed_courses 2, absence_pct 15, no_contact 45 days,
     graduation_delay, midterm_fail 50 % disabled until Phase 6 wiring), templates (one per kind, ar + en).
   - `notices.py`: `send(db, after, org_id, user_ids, template_key, data, dedupe_key=None, cooldown=None)` —
     builds ar/en text from a template map, skips deduped / cooled-down recipients via `adv_notice_log`, queues
     `notify_users` into `after` (governance `notify.flush` pattern), logs each delivery. Used by enable now
     (director gets "Academic advising is on").
   - `text.py`: code → (ar, en) for every new error code.
4. RBAC: `org_catalog.py` MODULES gains `advising` (scope org; actions view, insert, update, delete, approve,
   export); SYSTEM_ROLES gains `advising_director` (advising: all actions). Check `CONFLICT_RULES` so a student
   can't hold it.
5. Routes (`routers/organization/org_advising_router.py`, registered in `main.py`, tag `advising`):
   - `GET /api/v1/org/orgs/{org_id}/advising/status` (any live staff member of the org) →
     `{"eligible": bool, "reason": null | "org_type", "enabled": bool, "dept_id": int|null,
       "directors": [{"user_id", "name"}], "me": {"admin": bool, "director": bool, "advisor": bool,
       "advisees": int}, "counts": {"students": int, "assigned": int, "unassigned": int, "advisors": int}}`
     (`counts` only for admin / director, else null).
   - `POST /api/v1/org/orgs/{org_id}/advising/enable` (org admin) body `{"dept_id": int|null}` → uses that
     department (must belong to the org) or the org's existing `academic_advising` department, else creates one
     (kind service, preset academic_advising, Arabic name "الإرشاد الأكاديمي" / English "Academic Advising");
     seeds; imports legacy advisors; idempotent; audits; returns the status body. 403 `advising_not_available`
     for an ineligible org.
   - `POST /api/v1/org/orgs/{org_id}/advising/disable` (org admin) → keeps all data, returns status.
   - Member: `GET /api/v1/org/public/{org_id}/advising/status` (live member) →
     `{"enabled": bool, "role": "student" | "advisor" | "none", "advisors": [{"user_id", "name", "type"}]}`
     (`advisors` = the caller's own active advisors when role is student, else []).
   Errors `{"code","message","message_en"}`. Write `FLUTTER_API_CHANGES.md` (newest first).
6. Kill switch `org.advising` in `services/feature_catalog.py` (not org-manageable); one feature entry in
   `data/app_features_guide.json` (group org, roles org-admin, ar + en, steps, `switch_keys`).
7. Tests (tests/org_v2/): `advising_policy_unit.py` (resolution, defaults, validation),
   `e2e_advising_foundation.py`: enable on a faculty ok and idempotent; on a center 403; a department sub-org of a
   faculty eligible; legacy advisor import (live advisor only, idempotent); second active primary rejected by the DB;
   registrar advisor PUT + auto now write assignments and history; status `me` per role (admin, director via dept
   head, director via system role, advisor, plain teacher); counts hidden from advisors; member status for a
   student in TWO orgs shows only that org's advisor; org B admin gets 403 on org A; kill switch off → 403
   `feature_disabled`; disable keeps data. Run the existing `e2e_registrar.py`, `e2e_traditional.py`,
   `e2e_gov_requests.py`, `e2e_org_v2.py` and the migration round trip on SQLite; run 0049 up/down/up on the
   Postgres container `nb-pg` (localhost:55432, nbtest/nbtest/nbtest, use a NEW database name, never `public` of an
   existing one) if it is running.

## App scope
1. `lib/features/org/advising/adv_models.dart` (pure): `AdvStatus` / `AdvMemberStatus` parsed from the JSON above,
   tolerant of missing keys (older server); role helpers.
2. `adv_api.dart`: `AdvApi(orgId, {client})` — `status()`, `enable({deptId})`, `disable()`; static
   `memberStatus(orgId)`; base `'$orgBase/orgs/$orgId/advising'`, member `'$orgBase/public/$orgId/advising'`;
   calls through `orgCall`; `orgEndpointMissing` → "needs a server update" text.
3. `adv_texts.dart`: error codes `advising_not_available`, `advising_disabled` (+ any the backend adds — check
   `../wt-back-advising/services/organization/advising/text.py` when it exists) merged into `orgErrorText` the way
   `govCodeTexts()` is.
4. `adv_setup_page.dart`: the Academic Advising page for admins / directors: eligibility state ("not available for
   this organization type" with the reason), Enable (pick the existing advising department or create one) /
   Disable with `appConfirm`, the director(s), counts as `AppStatTile`s, empty / loading (`AppListSkeleton`) /
   error states, `OrgPageBody` + `OrgPageHeader` conventions, `t(ar, en)`, tokens only, no overflow.
   Presentational part takes plain values (`AdvSetupView`) for the layout harness.
5. `adv_wiring.dart`: `advEnabled()` (kill switch `org.advising`), `advServiceSubs(OrgSession)` → one `OrgSub`
   ('advising', icon, page) for org admins and holders of `advising` view rights; spread into `_serviceSubs` in
   `org_dashboard_screen.dart` next to `...govServiceSubs(s)`; add the help id the way `_subHelpIds` /
   `test/fixtures/help_page_ids.json` require (check `test/ui/help_ids_test.dart`).
6. Tests: `test/org/adv_models_test.dart` (parsing, older-server tolerance, roles), `test/ui/adv_layout_test.dart`
   (`expectNoLayoutErrors` over every `AdvSetupView` state, ar/en). Run `flutter analyze --no-fatal-infos
   --fatal-warnings` and `flutter test test/org/ test/ui/ -j 2`. `test/contract/api_paths_test.dart` and
   `feature_keys_test.dart` will fail until the lead regenerates snapshots — report, don't edit the snapshots.
