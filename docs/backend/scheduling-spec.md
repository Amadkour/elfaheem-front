# Backend prompt: breaking rules by priority, cross-timetable rebalancing, complete-coverage support

**For:** the Backend AI Agent working in `../back` (FastAPI + SQLAlchemy).

**Frontend counterpart (already built, uses only what exists today and degrades when a route below is missing):**
- `lib/features/org/org_schedule_coverage.dart`: "generate until complete" loop, option ladder, scope question, rollback.
- `lib/features/org/org_schedule_export.dart`: Excel / Word / PDF timetables built in the app (no server work needed).
- `lib/features/org/org_timetable_wizard.dart`: term → that term's courses; student count (subscribed or manual).
- Tests: `test/org/org_export_test.dart`, `org_versions_test.dart`, `org_planning_test.dart`.

**Status (backend v3.4, see `../back/FLUTTER_API_CHANGES.md`):** G1–G5 are implemented and tested (`tests/org_v2/e2e_coverage.py`,
`solver_break_unit.py`, `concurrency_v3.py`). G6 is not built (optional). Differences from the text below:
- `POST …/schedules/rebalance` is **synchronous**: 200 `{changeset}` (status `applied`), no run to follow.
- Staff eligibility is never broken (no `staff_eligibility` tier): the solver cannot pick another teacher.
- The `rebalance_timetables` suggestion type is not built; the app calls `…/rebalance` directly (with or without a suggestion).
- The loads route is `GET /orgs/{o}/loads` (not `…/schedules/loads`).
- A rollback restores the slots exactly; the version is a new, higher one (versions only grow).

Paths below are relative to `../back`:
- **R** is `routers/organization/org_schedule_router.py`
- **J** is `services/organization/schedule_jobs.py`
- **S** is `services/organization/org_schedule_solver.py`
- **SG** is `services/organization/schedule_suggestions.py`
- **A** is `routers/organization/org_admin_router.py`

## Working rules

- Read the cited code before changing it. Line numbers are from `HEAD` (`f6f4dec schedule copies`) and may drift.
- Reuse `jobs.bump` (409 `stale_version`), `jobs.snapshot`, `jobs.restore`, `jobs.start_run` / `jobs.execute`,
  `solver.validate`, `_check_settings`, `org_ctx(module, action)`, `audit(...)` and the `_describe` conflict shape.
- Only add response fields; never change or remove one. Without the new settings every result stays byte-identical.
- Every write that depends on a timetable version takes `expected_version` and goes through `jobs.bump`.
- Tests go in `tests/org_v2/` next to `solver_unit.py`, `e2e_versions.py` and `concurrency_v3.py`.

---

## A. Verified existing — do not rebuild

| Capability | Where |
|---|---|
| Background generation + runs, cancel; `persist_settings:false`; `trial:true` alternatives (`duplicate_of`) | R:680–760, J:143–220 |
| `settings.relaxation_priority` (6 tiers), strictly lexicographic — **soft preferences only** | S:88, S:229, FLUTTER_API_CHANGES v3.3 |
| Suggestion types `reschedule_session, add_period, add_day, add_room, reallocate_groups, reassign_staff, combined` | SG:44 |
| Accept / batch apply; config change → 202 + regeneration run; `revision_before_id` undo point per suggestion | R:1726–1870 |
| Revisions: list / get / PATCH label / DELETE / validate / restore `?expected_version=` / distribute; member copies | R:775–950 |
| Course plans batch `PUT {S}/course-plans`, `count_source` `enrolled` \| `manual` \| `history` | R:1551, `course_plans.py:108–166` |
| Org course `term_id` (planned term) and `students` (active enrollments) in `GET /orgs/{o}/courses` | A:768–826 |
| Excel export with `revision_id` and member filters | A:1054 |
| Generic PDF / DOCX table renderer (`org_doc_export.render`) — used by forms and complaints, not timetables | `services/organization/org_doc_export.py` |

## B. Verified current behaviour that blocks the new requirements

1. **Only soft preferences relax.** `_State.hard()` (S:352–375) refuses a time for `teacher_unavailable`,
   `students_unavailable`, `students_clash`, `students_busy_elsewhere`, `teacher_day_limit`, `course_already_there`;
   `pick_room()` (S:377–396) refuses `no_room_fits` (kind / capacity / capabilities). Such sessions are left
   unscheduled (S:660–667) even when breaking a lower-priority rule would place them.
2. **No cross-timetable change.** Accept / apply (R:1790–1870) touch one timetable; there is no way to rearrange the
   other draft timetables of the term together, and no grouped rollback.
3. **Stale report after a non-configuration accept.** `_apply_one` (R:~1765) moves slots and locks them, but
   `schedule.result` (unscheduled list, stats) is not recomputed, so the client shows the previous counts.
4. **No "add a member" advice.** `reassign_staff` only proposes existing eligible staff (SG:611–656); nothing tells the
   creator that a new teacher / assistant is needed, with which eligibility and times.
5. **Scheduler cannot see course terms.** `GET {o}/schedules/loads` (R:376–388) returns `course:{id,name_en,name_ar}`
   only; the term link and enrolled count are on `GET /orgs/{o}/courses`, which needs `courses.view` — a scheduler with
   only `schedule.*` cannot auto-select the term's courses.

---

## G1 (P1) — Break every rule by priority, except double bookings

**Setting** (per run, usually sent with `persist_settings:false`): `settings.relaxation_mode`
= `"soft_only"` (default, today's behaviour) | `"all_but_double_booking"`. Unknown value → 422 `bad_settings`
(`field:"relaxation_mode"`, `allowed`).

**Never broken, in any mode** (also against other ACTIVE timetables via `external`):
- `room_double_booked` / `rooms_busy` — two sessions in one exclusive room at overlapping times;
- `teacher_double_booked` / `assistant_double_booked` / `teacher_busy` — one member in two sessions at overlapping times.

**Breakable rules and their tier** (`relaxation_priority` decides the order; cheapest tier first):

| Rule (solver reason) | Tier |
|---|---|
| `students_clash`, `students_unavailable`, `students_busy_elsewhere` | `student_prefs` |
| `no_room_fits` — kind, then capabilities, then capacity (never > 10 % over capacity unless `settings.capacity_overflow_pct`) | `rooms` |
| assistant `unavailable` / `relaxable:false` cells | `assistant_prefs` |
| `teacher_day_limit`, `course_already_there` (two sessions of a course on one day), spread | `other_soft` |
| teacher `unavailable` / `relaxable:false` cells | `teacher_prefs` |
| `staff_not_eligible` — new tier `staff_eligibility`, appended LAST (most protected) | `staff_eligibility` |

`add_capacity` keeps its meaning (suggestions only). Add `staff_eligibility` to the tier list (S:88); a stored
priority without it gets it appended at the end.

**Algorithm.** In `all_but_double_booking` mode, a task that has no feasible (time, room) under the hard rules is
retried with the cheapest tier unlocked, then the next, lexicographically (one violation of a more protected tier
outweighs any number of cheaper ones). Inside a tier, minimise the number of broken rules, then the soft cost. The
double-booking checks in `hard()` / `pick_room()` stay unconditional.

**Report** (only in this mode):
- `result.relaxation_mode` — echo of the mode actually applied (the app shows "the server did not break rules" without it);
- `result.broken[]`: `{rule, tier, slot_ids, course_id, kind, group_no, user_id?, room_id?, detail}`;
- `result.broken_by_tier: {tier: count}`;
- a placed session that breaks a rule is no longer in `unscheduled`.

**Validate / publish.** `GET {S}/validate` reports each broken rule as a **warning** with `broken_by_priority:true`
and the tier. Publishing a timetable with broken rules needs `schedule.approve` (403 `approval_required`) and is audited
(`schedule.publish.broken_rules`, with counts per tier).

**Errors:** 422 `bad_settings`. No transaction change (generation already runs as a job).

**Acceptance tests (`solver_unit.py`):**
1. A teacher unavailable at every free time: `soft_only` → unscheduled `teacher_unavailable`; `all_but_double_booking`
   → placed, `broken[0].tier == "teacher_prefs"`.
2. Two candidates — break `student_prefs` or `teacher_prefs` — default priority picks `student_prefs`.
3. Only free time would double-book a room or a teacher → still unscheduled with `rooms_busy` / `teacher_busy`
   in both modes; no slot overlaps in any result (property test over 200 seeds).
4. Without `relaxation_mode`, results are identical to `HEAD` for the existing fixtures.
5. Publishing with `broken` rules: 403 without `schedule.approve`, 200 with it.

## G2 (P1) — Rearrange every draft timetable of the term together, with one rollback

**Routes** (`schedule.update`; `schedule.approve` when an active timetable would be touched — it never is, see below):

`POST /orgs/{o}/schedules/rebalance`
```json
{ "origin_schedule_id": 12, "term_id": 3, "schedule_ids": [12, 14],
  "suggestion_id": "88", "expected_versions": {"12": 7, "14": 3},
  "settings": {"relaxation_mode": "all_but_double_booking"} }
```
- Scope: `schedule_ids`, else every **draft** timetable of `term_id` (else of the origin's term), origin included.
  Active timetables are read as fixed busy time (as today) and returned in `blocked_by_active[]` with the sessions
  that block — never modified.
- `suggestion_id` (optional) is applied to the origin first (same rules as accept).
- Then every scoped timetable is regenerated **jointly**: one solver problem with all their tasks, shared rooms and
  staff, so no cross-timetable double booking can appear; `keep_locked` applies per timetable.
- Answer: 202 `{changeset, run}`; the run follows the existing run API. `changeset`:
  `{id, status: running|applied|failed|rolled_back, created_by, created_at,
    items:[{schedule_id, schedule_name, revision_before_id, revision_after_id, version_before, version_after,
            unscheduled_before, unscheduled_after}], blocked_by_active:[…]}`.

`GET /orgs/{o}/schedules/changesets/{id}` — the changeset (`schedule.view`).

`POST /orgs/{o}/schedules/changesets/{id}/rollback` — restores every item's `revision_before_id` (via `jobs.restore`),
all or nothing; 409 `changeset_stale` (+`schedule_ids`) when a timetable changed after the changeset; 409
`changeset_rolled_back` when already done.

**Transaction & concurrency.** Lock the scoped schedules in id order (`SELECT … FOR UPDATE`) before `jobs.bump`;
one transaction writes every timetable's slots, a `rebalance` revision per timetable and the changeset row. A
generation or suggestion running on any of them → 409 `generation_running` / `suggestion_running` (+`schedule_id`).
Any failure → nothing written, changeset `failed` with `error`.

**New suggestion type** `rebalance_timetables` (SG): when an unscheduled session is blocked by sessions of OTHER draft
timetables (`rooms_busy` / `teacher_busy` with blockers elsewhere), propose it with
`config.timetables:[{id, name, version}]` and `impact.unscheduled_after` from a trial joint run. Accepting it is the
same as `POST …/rebalance` with that suggestion (202 + changeset).

**Model:** `org_schedule_changesets` (id, org_id, created_by, created_at, status, error, items JSON, blocked JSON).

**Errors:** 404 `changeset_not_found`, 409 `stale_version` (+`schedule_id`), `changeset_stale`, `changeset_rolled_back`,
`generation_running`, 422 `bad_scope` (a timetable of another org / term, or not a draft).

**Acceptance tests (`e2e_versions.py` / `concurrency_v3.py`):**
1. Two drafts share a teacher; each alone leaves a session unplaced; rebalance places both, no overlap.
2. Rollback restores both timetables' slots and versions exactly; a second rollback → 409 `changeset_rolled_back`.
3. Editing one timetable after the rebalance → rollback 409 `changeset_stale`, nothing restored.
4. An active timetable in the term is listed in `blocked_by_active` and is byte-identical afterwards.
5. Concurrent rebalance + accept on the same timetable: exactly one wins, the other gets 409.

## G3 (P2) — Fresh report after every slot change

After a non-configuration accept / batch apply (R:1840–1856), a restore, a slot PUT / POST / DELETE: recompute
`schedule.result.unscheduled` and `result.stats.sessions_required / sessions_placed` from loads vs slots
(`SG.unscheduled`, SG:127) and set `result.stale_report:false`; keep `relaxed` / `broken` from the last generation but
mark `result.relaxed_from_version`. Same transaction as the slot write.

**Acceptance:** accept a `reschedule_session` that places one session → `GET {S}` shows `sessions_placed + 1` and the
session gone from `unscheduled`.

## G4 (P2) — "Add a member" advice

New advisory type `add_staff` (`applicable:false`, like an add-room advice): when sessions stay unplaced because no
eligible teacher / assistant is free (`teacher_busy`, `teacher_unavailable` with no `reassign_staff` candidate), propose
`config.staff:{role: teacher|teacher_assistant, course_ids, eligibility:{department_id?, course_ids}, windows:[{day,
period_ids}], sessions}` and `impact.unscheduled_after` from a trial run with a virtual member. Rejecting works as
today; it is never applied by the server.

**Acceptance:** one teacher, two courses at the only possible time → `add_staff` with both windows; no slot written.

## G5 (P2) — Course term and enrolled count for schedulers

Add to every `GET {o}/schedules/loads` item (R:383): `course.term_id` (OrgCourse.term_id), `course.code` and
`course.students` (active enrollments, as in A:775). Optional: `GET {o}/academic/terms/{tid}/courses` → the term's
course runs `{course_id, run_id, status, students_count}` (`schedule.view`). The app currently reads
`GET /orgs/{o}/courses` and falls back to manual selection when that is refused.

**Acceptance:** a user with only `schedule.view` gets `term_id` and `students` in loads.

## G6 (P3, optional) — Server-side Word / PDF timetables

The app builds premium Excel / Word / PDF files itself (merged cells, course colours, per-member sheets, summaries).
Only needed for e-mailing or attaching files from the server (e.g. on distribute): add `format=xlsx|docx|pdf` to
`GET /orgs/{o}/export/schedule` reusing `org_doc_export.render`, with the same filters and permissions.

---

## C. New error codes

| Code | HTTP | Gap |
|---|---|---|
| `bad_settings` (`field:"relaxation_mode"`) | 422 | G1 |
| `approval_required` (publishing with broken rules) | 403 | G1 |
| `changeset_not_found` | 404 | G2 |
| `changeset_stale` (+`schedule_ids`), `changeset_rolled_back` | 409 | G2 |
| `bad_scope` | 422 | G2 |

## D. Unconfirmed — check before relying on them

- Whether students of different groups of one course should ever be allowed to clash when `student_prefs` is broken
  (the app assumes yes, by priority).
- Whether a joint rebalance of many timetables fits the existing `time_limit_s` (S:594); a larger default for
  rebalance runs may be needed.
