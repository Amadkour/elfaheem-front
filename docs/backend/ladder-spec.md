# The relaxation ladder — the "perfect timetable" generator

Status: v4.0 design (2026-10-27). Backend `../back/services/organization/schedule_ladder.py`, app
`lib/features/org/org_schedule_ladder.dart`. This document records the audit, the decision and the contract.

## 1. Audit (what was there, what was wrong)

The engine itself is sound. `schedule_cpsat.py` is a complete CP-SAT model (every session a set of option
literals, people / rooms / cohorts as at-most-one constraints per clique, lexicographic objective unplaced →
broken rules per tier → soft cost) with the greedy `org_schedule_solver.py` as warm start and fallback, and
`schedule_validator.check` is an independent clean-room validator. On the realistic benchmark
(`tests/org_v2/bench_realistic.py`) CP-SAT places 180/180 sessions in 32 s and 307/307 in 63 s with zero hard
findings; the heuristic alone leaves 92 of 307 unplaced.

What produced "crashes and poor results" was the layer around it:

| Problem | Where |
|---|---|
| "Generate" was six rounds of at most 90 s total, each round at most `time_limit_s` (default 8 s). A 300-session term needs ~60 s of CP-SAT for a full placement, so most rounds ended at the time limit with sessions unplaced. | `schedule_jobs.complete` |
| The only relaxation was "strict, then every Flexible rule at once". No ladder, no order, no structural changes (rooms, periods, days, group splits) — only break literals the engine already had. | `schedule_jobs.complete`, `UNLOCKABLE` |
| The run never paused: broken rules came back as proposals after the fact; no decision could be taken mid-run. | `schedule_jobs.execute` |
| The app followed a run for at most 4 minutes, then invented a "failed" run while the server was still working; polls overlapped; a run of one timetable leaked into another; cancel used the open timetable's id, not the run's. | `OrgScheduleProvider._follow`, `cancelGeneration` |
| Rules were a hard-coded client list mirroring a server constant; no reorder, no presets; the "relaxation priority" model in the app was dead code. | `org_schedule_generate.dart`, `org_schedule_versions.dart` |
| Input errors (`no_periods`, `no_courses`, a load without a teacher) surfaced as a failed run with a raw code. | `schedule_jobs.execute` |

Decision: **keep the engines and the validator, replace the orchestration.** A rebuild of the CP-SAT model would
reproduce months of validated work for no gain; the missing pieces are all above the engine.

## 2. The ladder

A ladder is an ordered list of rungs. Each rung is one way of making room for sessions that do not fit:

| key | what it allows | engine mechanism |
|---|---|---|
| `free_moves` | nothing is broken: strict solve, then longer / reseeded solves with local search | more time, other seeds, `local_search` |
| `ta_limits` | a TA outside their available cells, over their daily or weekly cap | `break_only` assistant_unavailable + assistant_day_limit, `max_week` dropped for TAs |
| `doctor_limits` | the same for doctors (lecturers) | instructor_unavailable + instructor_day_limit, `max_week` dropped for doctors |
| `rooms` | a room outside its own available cells, a theory session in another kind of hall, missing capabilities; then **new rooms** (virtual rooms of the kind / capacity / capabilities the unplaced sessions need) | `break_only` room_*; virtual rooms with negative ids |
| `split_groups` | a group too large for every fitting room, or still unplaced, split into 2..n groups taught by the same staff | loads re-expanded with `group_no`; a course plan is written on save |
| `open_times` | a new period after the last one, then a new teaching day. Nobody's explicit availability is extended to the new time (that would bypass a locked rung): a restricted person needs their own rung too | virtual period (negative id) / a day from `SCHEDULE_DAYS` not yet used |
| `student_times` | students outside their available cells or busy in another active timetable | `break_only` students_unavailable, students_busy_elsewhere |
| `capacity` | a room over capacity, up to `overflow_pct` (default 10 %) | `capacity_overflow_pct` |
| `student_clash` | students in two sessions at once — off and locked by default | `break_student_clashes` |

Never breakable, not on the ladder: a person in two sessions, an exclusive room in two sessions, a course's own
sessions overlapping, a lab outside a lab, the doctor-or-TA rule.

A rung has a `mode`: `auto` (break and log), `ask` (pause and ask the creator first), `locked` (never). The order of
the list is the priority. `normalize()` accepts any partial list and fills the defaults. Presets are stored on the
organization (`settings.timetable_ladder_presets`), the timetable's own ladder in `OrgSchedule.settings.ladder`.

Rungs stack: rung k runs with every earlier rung's relaxation still allowed, and `relaxation_priority` is derived
from the ladder order, so the engine's lexicographic objective always prefers the cheaper rung. The run stops at the
first rung that leaves nothing unplaced.

## 3. The run

`POST …/schedules/{sid}/generate {ladder: true, auto: bool, seed}` → `jobs.execute` → `schedule_ladder.run()`:

1. `free_moves`: strict solve with a budget scaled to the problem (`solve_s = clamp(0.3 × sessions, 10, 120)`),
   a second try with another seed and local search when sessions stay unplaced.
2. For each later rung in order, skipping `locked` ones: first the **pre-check** (`relevant()`): can what the rung
   relaxes touch what the engine says blocks the unplaced sessions (`unscheduled[].blocking / core / explain`)? A
   people rung needs one of its people teaching an unplaced session or standing in its way; `rooms`, `split_groups`
   and `capacity` need a room reason; `student_times` / `student_clash` a student reason; `open_times` anything a
   new time could help (not a listed-cells availability, not "no room of that kind"). A session the engine could
   not explain keeps every rung. A rung that fails the pre-check is **set aside** (`note.skipped: not_relevant`,
   `deferred`) without a solve. Then the dry run (cumulative; the best timetable so far is handed to the engine as
   hints, so it only has to place the rest and the result stays close to what the creator saw). If `auto` → apply.
   If `ask` (or any fork in an interactive run) → write a **decision** on the run row and wait.
3. A fork is the point where the strict solve is incomplete and a rung must be stacked. The decision lists up to
   three options (the next enabled rungs that pass the pre-check, each dry-run: sessions it places, rules it
   breaks, people / groups affected), the recommended one (the cheapest that places the most), and "let the
   system decide". The options' dry runs solve at once when the host has the cores (one solve per 4 cores, the
   engine's threads split between them; never in deterministic mode; a 4-core host solves one at a time).
   `POST …/runs/{rid}/decide {decision_id, option_id | "auto"}` resumes the run at once. An unanswered decision
   is applied automatically after `decision_timeout_s` (15 min) so a run can never hang; cancel still works.
3b. When the enabled rungs are exhausted and sessions remain, the rungs set aside get a **second pass** (their dry
   run after all, stacked on everything applied): the longer chain the pre-check cannot see — a TA's session moving
   to free a room for a doctor's — is found here, so the pre-check costs completeness nothing.
4. When every enabled rung is exhausted and sessions remain, the run dry-runs each **locked** rung on its own and
   reports which one would complete the timetable (`blocked_by`) — the "exactly which locked constraint" answer.
   A `split_groups` rung hands every NEW group to the course's eligible colleague with the fewest weekly sessions
   (`staff_for` → `schedule_context.eligible_staff`: the same check as the course plan's `group_staff`; a lab
   colleague is always a TA), and only without one to the existing staff in turn.
5. Proof: `schedule_validator.check` runs twice on the final slots — against the transformed problem (must be 0
   hard findings; the run fails otherwise, nothing is saved) and against the original problem (every finding is
   a deliberate, reported break, listed in `broken` with its rung).
6. Save, in one transaction: virtual rooms become real rooms (`OrgRoom`, named "Proposed hall n"), virtual periods
   become `OrgPeriod` rows, a new day joins `settings.days`, group splits become course plans (explicit group count
   + `group_staff` for the groups handed to a colleague); slots are then written with real ids. Everything is in
   the final summary and in `result.ladder`.
7. Rejecting a proposal (`POST …/proposals/decide {accept: false}`) removes its sessions; a proposed room or period
   no session of ANY timetable uses any more is deleted again (`structural.rooms[] / periods[].removed = true`).

Run status while waiting: `waiting` (`summary.decision` holds the question). Progress, heartbeat and the step log
(`summary.steps`) keep flowing; the app's overlay shows stage, placed / remaining, conflicts, the rung being
relaxed and why, the log, and pause / resume / cancel.

## 4. Report shape (`result.ladder`)

```
{ "status": "complete" | "incomplete" | "cancelled",
  "ladder": [ {key, mode, order} … ],
  "rungs": [ {key, tried, applied, placed_before, placed_after, broken, seconds,
              note: {skipped?: nothing_to_add | not_relevant (+ reasons) | no_gain | solver_timeout | passed_over, …}} … ],
  "deferred": [ key … ]            // set aside by the pre-check and not needed after all,
  "decisions": [ {id, at, rung, chosen, by: "user" | "auto" | "timeout", options:[…]} … ],
  "broken": [ {rule, rung, course_id, kind, group_no, block_id, day, period_ids, user_id?, room_id?, detail?} … ],
  "structural": { "rooms": [{id, created_id, kind, capacity, capabilities, sessions, removed?}],
                  "periods": [{id, created_id, start, end, sessions, removed?}], "days": [{day, sessions}],
                  "splits": [{course_id, kind, from, groups, sizes, sessions, staff: [{group_no, teacher_id, new}]}] },
  "blocked_by": [ {key, would_place, placed_after} … ],
  "proof": { "hard_vs_relaxed": 0, "hard_vs_original": n, "checked_at": iso },
  "seed": 7, "elapsed_s": 123.4 }
```
