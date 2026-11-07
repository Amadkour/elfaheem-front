# Academic Advising — progress

Job tracker (multi-session). Plan: `PLAN.md`. Decision: D-289. Branch `feature/academic-advising` in both repos,
worktrees `D:/platform/nextbrain/wt-back-advising`, `D:/platform/nextbrain/wt-front-advising` (from origin/organizations
back 5927644, front 5b0081ee). Each phase merges into organizations → production (backup tag), never deployed by the
job (owner deploys once after all sessions).

| Phase | Status | Notes |
|---|---|---|
| 1 Discovery + plan | done | approved 2026-11-05; owner took the recommendations: university + faculty only, midterm mark added |
| 2 Foundation | done | brief `PHASE2.md`; back 4d00406 · fb66c38 · 3478985, front a117d608 · 2daa1942 · b7031cf1; security review: 3 fixes (no migration data step, live-only directors); migration renumbered 0050 at the merge |
| 3 Config + assignment | done | brief `PHASE3.md`; owner 2026-11-05: keep links to departed advisors (counted away); back 88579cd · 0909cfe (security review: 5 fixes) · 296f1ee (merge, migration renumbered 0052), front 2583d460 · 0c6dfbe1 · 9932dd14 + label fixes; **Phase 4 first task**: advisors who are not directors reach My profile / Handovers (the entry under Services is admin / director only today; PLAN §3.10 department tab + attention keys) |
| 4 Advisor workspace | done | brief `PHASE4.md`; back a282619 · 7cde087 (security review: 11 fixes) · 688d624 (merge), front a3dc2714 + docs; advisors who are not directors now reach My students through `/mine` `advising`; migration 0053 |
| 5 Appointments + messages | done | brief `PHASE5.md`; office hours, booking with notice/window/limits, no-shows, conversations with files, templates, post-meeting survey, student hub; student routes on the member base `/org/public/{org}/advising`; migration 0054 |
| 6 Early warning | done | brief `PHASE6.md`; rule engine (system + custom rules, daily run, run now), alerts with "propose a meeting", digests, graduation checks; migration 0055 (rechained after 0054 at the merge) |
| 7 Requests + councils | done | brief `PHASE7.md`; requests and referrals with an approval chain, support plans with reviews, accommodations; migration 0056 (rechained after 0055) |
| 8 Analytics | done | brief `PHASE8.md`; director dashboard + aggregate tier (small groups hidden), 27 drill-downs, six `adv.*` Export Studio datasets, compliance, daily data check, group outreach with read tracking; migration 0057; merged with Phases 5-7 and `organizations`, full gates once, PG round trip 0053 → 0057 |
| 9 Hardening | done (perf target partly met: 39 of 87 cases after the follow-up, migration 0061, see CHANGELOG) | brief `PHASE9.md`; isolation sweep (140 operations, no leak), OWASP fixes, retention purge, privacy export + deletion, scope max load, `overview.advising`, workspace multi-select, a11y, OpenAPI, guides; migration 0060 (after master-detail 0058 / 0059). Owed: director org-wide lists / dashboard / drill-downs over 300 ms p95 at 100 000 students |
