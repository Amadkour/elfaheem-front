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
| 4 Advisor workspace | todo | |
| 5 Appointments + messages | todo | |
| 6 Early warning | todo | |
| 7 Requests + councils | todo | |
| 8 Analytics | todo | |
| 9 Hardening | todo | |
