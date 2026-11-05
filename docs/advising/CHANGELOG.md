# Academic Advising — changelog

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
