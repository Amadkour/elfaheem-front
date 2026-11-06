# Academic Advising — changelog

## Phase 3 — Settings and assignment — 2026-11-05
Backend (`wt-back-advising`):
- Settings per scope (org · department · program · level · cohort) with inheritance: `GET / PUT /policy`,
  `DELETE /policy/{id}`.
- Advisors and their profiles (status leave · sabbatical · left with dates, max-load override, office, contact note,
  bio; the advisor edits only their own contact fields): `GET /advisors`, `GET /advisors/me`, `PUT /advisors/{uid}`.
- Conflicts of interest (block a pairing everywhere): `GET / POST /conflicts`, `DELETE /conflicts/{id}`.
- Students and manual assignment with history: `GET /students`, `PUT /students/{mid}/advisors`,
  `GET /students/{mid}/history`.
- One distribution engine (`assign_algo.py`, pure, deterministic; strategies balanced · round robin · department ·
  continuity) for distribute · rebalance · reassign: `POST /assign/preview` → `POST /assign/apply` (plan hash,
  409 `plan_stale`, idempotent re-apply, capacity override only with a reason), `GET /assign/runs`.
- Handovers with a case summary: `GET /handovers`, `POST /handovers/{id}/ack`.
- New students are assigned automatically (10-minute job + right after a join is approved) with a welcome notice to
  the student and ONE grouped notice per advisor (deduped); e-mail through the existing helper, text escaped.
- Owner decision: an existing link to a departed advisor is kept (locked legacy primary, counted "away").
- Security review fixes: only the newest preview's hash applies; the registrar's advisor routes obey conflicts, away
  and capacity; a PostgreSQL advisory lock per organization stops two applies racing past capacity; escaped e-mail;
  the job skips suspended organizations and filters in SQL.
- Migration `0052_advising_assign` (down `0051_enrollment_history`): `adv_assign_runs.mode`, `params`, `result`.

App (`wt-front-advising`):
- `adv_config_page` (settings with "inherited from" hints and scope overrides, leave guard), `adv_advisors_page`
  (load bars, status, edit sheet, "Reassign their students"; an advisor sees their own card), `adv_distribute_page`
  (mode · strategy · scope → preview → apply, run history), `adv_students_page` (filters, student sheet: primary,
  co / support advisors, lock, override with reason, conflicts, history), `adv_handovers_page` (summary,
  Acknowledge), `adv_parts`; the advising page's "on" state links to them.
- Every new server code and warning has Arabic + English text; end / handover reasons are labelled; typed notes keep
  their own direction.

Tests: `advising_algo_unit` 52, `e2e_advising_assign` 376, `pg_advising_lock` 4 (PostgreSQL), `e2e_advising_foundation`
176; regressions `e2e_registrar` 85, `e2e_org_v2` 71, `e2e_enrollment_history` 35, `e2e_gov_requests` 253,
`e2e_governance` 318, `e2e_engine_exam_gate` 52, `spec_help` 10; 0050 → 0052 up / down / up on SQLite and PostgreSQL.
App: `adv_assign_models_test` + `adv_assign_layout_test`; suites contract 63, org 2324, ui 1787, export 257, auth 154,
perf 29; web build.

## Phase 2 — Foundation — 2026-11-05
Backend (`wt-back-advising`):
- `data/advising_models.py`: the 29 `adv_*` tables of PLAN §3.2, each with `org_id`; partial unique indexes (one
  active primary advisor per student, one active row per student + advisor, one active appointment per advisor and
  start, unique risk-event dedupe key, one stats row per student, one profile per advisor). `org_registrations` gains
  the optional midterm mark `interim_percent` / `interim_at` / `interim_by`.
- Migration `0050_advising` (down 0049, after `0049_engine_exam_gates`): the tables, the midterm columns, the PG `tenant_isolation` RLS policy on every
  `adv_*` table, and the `org.advising` help page for a database whose help content is already seeded. No data step:
  existing registrar advisors are imported and reconciled when an admin turns advising on.
- `services/organization/advising/`: `access` (eligibility: university / faculty and units under them; roles admin ·
  director · advisor · student; `student_scope`; audited sensitive reads), `policy` (settings with defaults and
  most-specific-scope resolution), `assignments` (`set_primary` with history, `advisor_id` mirror, legacy import that
  reconciles), `seed` (flag categories, risk rules, templates, ar + en), `notices` (deduped, cooled-down
  notifications), `setup`, `text` (11 error codes, ar + en).
- RBAC: module `advising`, system role `advising_director` (not for students; not given to `viewer`).
- Routes: `GET …/orgs/{id}/advising/status`, `POST …/advising/enable`, `POST …/advising/disable`,
  member `GET …/public/{id}/advising/status`. The registrar advisor routes write through `set_primary` once advising
  has been on.
- Kill switch `org.advising`; features guide entry; help page `org.advising` (org admin + member).

App (`wt-front-advising`):
- `lib/features/org/advising/`: `adv_models`, `adv_api`, `adv_texts` (merged into `orgErrorText`), `adv_setup_page`
  (`AdvSetupView`: loading · failed · not available · off · on · busy; the Turn on sheet picks or creates the advising
  department), `adv_wiring` (Academic advising under Services for org admins and holders of `advising` rights).
- Snapshots `test/contract/api_paths.json`, `feature_keys.json`; help id fixture.

Tests: `advising_policy_unit` 56, `e2e_advising_foundation` 177 (incl. a student in two orgs, org B admin on org A,
kill switch, the review regressions), `spec_help` 10; regressions `e2e_registrar` 85, `e2e_traditional` 24,
`e2e_gov_requests` 253, `e2e_org_v2` 71, `e2e_feature_guide` 38; 0050 up / down / up on SQLite and PostgreSQL.
App: `adv_models_test` + `adv_layout_test` 19; suites org 2208, ui 1771, contract + help ids 65, export 257, auth 154, perf 29.

## Phase 1 — 2026-11-05
- Discovery of the backend and app; plan `PLAN.md` approved; decision D-289.
