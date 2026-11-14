# TIMETABLE_NOTES.md — running notes for the timetable rebuild (keep short)

## Status (2026-10-24)
Done: CP-SAT engine · independent validator · pre-flight · section counts + tutorials · per-student cohorts ·
explanations (core / explain / why-here) · realistic benchmark · Flutter insights (data health, quality report,
why-here, drop preview, iCal). All backend solver suites, the timetable e2e scripts and the Flutter suites pass.

## Plan
1. ✅ Engine: `back/services/organization/schedule_cpsat.py` behind the SAME `generate(...)` contract as the heuristic
   (`org_schedule_solver.generate` dispatches; `settings.engine`, default cpsat, heuristic fallback when OR-Tools is
   missing). Lexicographic passes: unplaced → broken tiers → room-rule order → soft tiers. Warm start = 2–3 s heuristic.
2. ✅ Independent validator `schedule_validator.py` (shares no code with the engines).
3. ✅ Section counts: `course_plans.shape(…, has_tutorial)` + `sessions_to_schedule`; pre-flight `schedule_preflight.py`
   (`GET {S}/preflight`, advisory).
4. ✅ Per-student cohorts (`schedule_cohorts.py`, `schedule_context.cohorts`): registrations → exact; else clusters.
5. ✅ Tutorials: `kind = "tutorial"`, `OrgCourseLoad.tutorial_*`, plan `tutorial_group_size / tutorial_groups`.
6. ✅ Explanations: `unscheduled[].core / explain`, `GET {S}/slots/{id}/why`.
7. ✅ UI: `org_schedule_insights.dart` (DataHealthCard, QualityCard, ExplainRows, WhyHereSection), drop preview in
   `org_schedule_pages.dart`, iCal in `org_schedule_ical.dart` + export sheet, independent verdict in ConflictsPanel.
8. ✅ Benchmark `tests/org_v2/bench_realistic.py` (40 courses · 180 sessions · 25 rooms · 30 doctors · 40 TAs · 58 cohorts).
8b. ✅ Pre-flight recommendations are quick actions: each finding has a stable `key` + optional `action`
   (`split_groups`, `raise_week_cap`); `POST {S}/preflight/accept|dismiss`; the DataHealthCard shows Accept / Reject
   (Restore for rejected ones). Manual-only fixes show "Fix by hand" + Reject. Test: `e2e_preflight_actions.py`.
8c. ✅ Every issue lists its ways out, RANKED (`actions[]`: #1 recommended, score, why, automatic or by hand): the
   pre-flight findings (`schedule_preflight.py`, with the teaching roster + eligibility + inactive rooms for
   reassign / assign / activate recommendations) and every validator conflict (`schedule_remedies.py`:
   GET …/remedies — move to the nearest free time, change room, give it to a free colleague, fix the group, unpin,
   re-solve, override, …; nothing is ever left without a manual way). UI: `RankedActions` in the DataHealthCard
   (+ "Accept every recommended fix" = POST …/preflight/accept-all) and `RemediesPanel` in the Quick Actions sheet.
   Tests: `section_count_unit.py` (52), `e2e_preflight_actions.py` (46), `e2e_remedies_reassign.py` (68),
   `test/org/org_reassign_test.dart`, `test/ui/reassign_layout_test.dart`.
8d. ✅ Changing the teacher / assistant of a session asks the scope (whole course · this weekly session · one date),
   rebuilds what the change breaks (`schedule_reassign.py`: the clashing unpinned sessions are re-solved with
   `schedule_quick.solve_part(patch=…)`) and shows BEFORE / AFTER ranked (hard → unplaced → warnings → soft → moved,
   score 0..100) with the moved sessions; apply writes both as revisions. Pin / unpin lives in the slot sheet.
8e. ✅ One-date changes (`schedule_occurrences.py`, table `org_schedule_occurrences`): a substitute (scope "once"),
   or the session's own teacher / assistant switching a date online (with the link) or back in person from the
   member "Today" / "My timetable" screens; students are notified and accept / reject (`org_member_changes.dart`).
   `/public/schedule/me` (`changes`) and `/me/calendar` apply them, so daily and hourly views follow the published
   timetable.
9. ⏳ Enhancements §10 not built here: what-if sandbox, lock date / notifications, student swap requests
   (registrar already has waitlists and clash-checked registration), exam engine reuse (exams have their own
   solver, `schedule_exams.py`).

## Benchmark (realistic dataset, 30 s budget, this machine)
- CP-SAT: 180/180 placed, 0 hard findings (independent validator), 0 preferences relaxed, ~30 s (placement pass
  ≈ 2.6 s, the rest improves soft cost). Heuristic: 164/180 in 1.3 s.
- Presolve tuning mattered most: probing off + symmetry off + 2 presolve iterations (11 s → 2.6 s to full placement);
  the single giant weighted objective was replaced by sequential passes.

## Assumptions
- OR-Tools 9.15.6755 (py3.12 Windows wheel) installs cleanly; pinned in requirements.txt. No new Flutter packages.
- "Generation produces conflicts" came from two things now fixed: course-level clash sets ("every group of A against
  every group of B") made real instances infeasible, and break mode then placed sessions that break rules on purpose.
- Before registration, cluster g of a level attends section g of every course (the registrar numbers groups the same
  way in its alphabetical / by-code distribution). With registrations the cohorts are exact.
- Determinism: "auto" = reproducible single-thread search up to ~6000 placement options (most organizations),
  parallel beyond (same seed may then give an equally good but different timetable). `solver.deterministic` says which.
- A relaxation ladder is data already: `settings.relaxation_priority` (tiers) + `settings.rules` (Locked / Flexible);
  "max study days per level" is not a separate tier (the term's `days` setting + the spread cost cover it).
- Auto mode never regenerates the draft it created (one per term); manual slots are locked and kept by `keep_locked`.
- Pre-flight never blocks generation (an overcommitted doctor still gets a partial timetable with explanations).

## Decisions
- CP-SAT is the core; the heuristic report shape is the contract (`_report`), so every caller stays untouched.
- The e2e scripts run on SQLite (`DATABASE_URL=sqlite:///…`) when no Postgres is up; two legacy expectations were
  loosened (symmetric groups, `effective` subset) and one compares reports without the `solver` timing.
- Rooms are modelled as classes (identical rooms) and assigned afterwards by interval colouring: exact and small.

## Open issues
- Students' travel gaps between buildings are not modelled in CP-SAT (teachers' are). The heuristic checks both.
- `why_here` explains one session against the current timetable; a global unsat core (CP-SAT assumptions) is not
  exposed — `core` is the minimal hitting set per session, which is what admins asked for.
- Parallel mode is not reproducible across runs when the soft pass hits the time limit.

8g. ✅ Power AI schedule (D-011 / back D-053): the current / next term without a timetable is an attention item
   (`term_without_timetable`) with "Generate now" (`POST …/schedules/auto {term_id}` → draft + autopilot); the autopilot
   (`POST …/schedules/{sid}/autopilot`, `schedule_autopilot.py`) chains pre-flight fixes → complete generation → every
   hard conflict's best validated remedy → partial re-solve inside the ONE run (live panel shows `fix*` steps, result
   gets `autopilot {before, after, log}`); every remedy / quick action is previewed BEFORE / AFTER on two mini grids
   (`org_schedule_preview.dart`, `POST …/remedies/preview`). Files: `org_schedule_autopilot.dart`,
   `org_schedule_preview.dart`; tests `test/org/org_autopilot_test.dart`, `test/ui/autopilot_layout_test.dart`,
   back `tests/org_v2/e2e_schedule_autopilot.py`. Round 2: data-fix confirmation (`GET …/autopilot/plan`,
   `DataFixPicker`), "Undo everything" (`autopilot_before` revision), remedies recomputed per applied fix, one audit row
   per run, cached term blockers (`GET …/schedules/term-needs`), following an already running one-tap run, and a
   "Generate now" button on the push (untested on a device).

8f. Patience while generating: the run's `summary.steps` (schedule_jobs.Steps — data loaded · attempt n strict /
   bending the flexible rules, with its time budget · attempt result · saving) is shown by `GenerationLivePanel`
   (org_schedule_generate.dart): headline = best so far / current step, the whole-run clock ticking locally between
   polls (`elapsed_s` + time since the poll), the current attempt's own budget bar, done steps with their duration,
   a hint after 8 / 20 / 45 s in one step (`patienceText`), queued state. `GenerationVeil` dims the board and shows the
   compact panel in the middle while a new version is being generated. Tests: org_schedule_flow_test (LiveRun /
   LiveStep / liveHeadline / patienceText / liveClock), org_widgets_test, new_screens_layout_test;
   backend e2e_timetable_v3 asserts the step log of a background run.

