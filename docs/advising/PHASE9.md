# Phase 9 — Hardening: brief

Read `PLAN.md` §3.8 (roles and privacy), §3.11 (tests), §4 row 9, and `CHANGELOG.md` for what Phases 2-8 built.
Branches `feature/academic-advising-p9` in `wt-back-adv-p9` (backend 441d454) and `wt-front-adv-p9` (app d5c062a3),
both cut from what is on `organizations` / `production`. Migrations end at `0057_advising_analytics`; a new one is
`0058_…` (down `0057`).

Tests stay minimal (owner, 2026-11-06): each side runs only its own new / touched tests, analyze or ruff, and goldens
at 390 ar light + 1440 en dark. The lead runs the full gates once at the merge.

## Backend (`wt-back-adv-p9`)
1. **Isolation e2e** `tests/org_v2/e2e_advising_isolation.py`: two orgs sharing one student. Attack every advising
   route (staff base `/api/v1/org/orgs/{org}/advising`, member base `/api/v1/org/public/{org}/advising`, analytics,
   Export Studio `adv.*` datasets, files, deep-link ids) across the other org, from the wrong role (student → staff
   routes, co-advisor → sensitive notes, advisor → another advisor's students, aggregate-tier viewer → drill-downs)
   and with foreign ids in bodies and queries. Every attempt answers 403 / 404 and leaks nothing (no counts and no
   names in error bodies). Fix whatever fails.
2. **Security review** (OWASP) of `services/organization/advising/**` and `routers/organization/org_advising*`:
   - IDOR, mass assignment (pydantic `extra=forbid` where bodies are client-built);
   - file upload type, size and name checks;
   - rate limits on writes, unbounded queries and page sizes;
   - audit coverage of sensitive reads, injection in search and sort parameters, secrets in logs.
   List each finding and its fix in `FLUTTER_API_CHANGES.md` only when the contract changes, otherwise in the commit
   message.
3. **Performance** `tests/org_v2/advising_perf_pg.py` on `nb-pg` (database `adv_mig_p9`, never `adv_mig` or
   `nbtest`):
   - seed 100 000 students, 400 advisors, and realistic flags, notes, appointments, threads and stats;
   - time p95 of the list endpoints (workspace with each filter and sort, alerts, appointments, threads, requests,
     drill-downs, director dashboard, Export Studio first page);
   - target < 300 ms. Fix slow queries, with indexes in `0058` if needed, and print the before / after table.
4. **Retention purge** (PLAN §3.8): sensitive notes purged `retention_months` (policy) after the membership ends.
   Also purge the operational tables Phase 8 documented (snapshots, outreach recipients, analytics runs) per their
   documented retention. Use the scheduler's daily job with a claim, bounded batches and an audit row with counts.
5. **Privacy export / account deletion**: `services/privacy_export_service.py` and the account-deletion path in
   `auth_service.py`.
   - The export gives a student their own advising data: advisors, appointments, their messages, student-visible
     notes, requests, plans, accommodations, surveys answered, outreach received. Never flags, risk, internal or team
     notes.
   - Deletion erases or anonymizes the student's advising rows, and keeps aggregates and staff audit with the person
     removed.
6. **Open items from earlier phases**:
   - (a) the policy's max load per scope is not applied to advisor capacity in assignment;
   - (b) the welcome e-mail goes out only in "always" digest mode — check against PLAN §3.4 and fix if wrong;
   - (c) add an `advising` block to `GET /api/v1/org/public/me/overview` per membership (`{hub: bool, unread: int}`,
     only when advising is on and the student has an advisor), so the member home can skip its extra
     `/advising/status` call. Older apps ignore it.
7. **OpenAPI**: every advising route is tagged `advising`. Commit `docs/advising/openapi.json`, generated from the
   app, with only the advising paths, plus a script `scripts/contract/export_advising_openapi.py`.
8. Feature guide and help entries for anything new; `FLUTTER_API_CHANGES.md` for contract changes; regenerate the
   contract snapshots into `../wt-front-adv-p9`.

## App (`wt-front-adv-p9`)
1. Workspace multi-select: long-press / checkbox selection, then "Message selected" opens the Phase 8 outreach
   composer with those students as the audience. Use the composer's existing explicit-list audience if there is one;
   otherwise see the backend outreach audience in `services/organization/advising/outreach.py` and ask the lead.
2. Outreach deep link for a student opens the single message sheet (`showAdvStudentMessage`), then the list.
3. Once backend item 6c lands (the lead will relay it), the member home's "My academic advisor" card reads
   `overview.advising` and skips `/advising/status` when it is present. Lower the `org-member` budget in
   `test/perf/home_requests_harness.dart` from 5 back to 4.
4. a11y: add the advising homes and pages to `test/ui/a11y_guidelines_test.dart` (workspace, 360, student hub,
   director dashboard). Fix what fails.
5. Documents: `documents/_build/build_advising.py` on top of `nbdoc.py` (follow `build_platform.py`), writing the
   Academic Advising guide as Word + PowerPoint (roles, setup, daily advisor flow, student flow, early warning,
   requests, analytics, privacy), plus a README entry.
6. A developer guide `docs/guides/advising.md` (files, flows, kill switches, deep links, tests) and a short folder
   section in `lib/features/org/CLAUDE.md` that points to it.
