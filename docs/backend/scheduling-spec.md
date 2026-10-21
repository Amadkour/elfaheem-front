# Backend prompt: timetable suggestions, scheduling horizon and safe application

**For:** the Backend AI Agent working in `../back` (FastAPI + SQLAlchemy).
**Frontend counterpart (already built):** `lib/features/org/org_schedule_optimizer.dart`, with tests in `test/org/org_optimizer_test.dart`.

## How to work

1. Read your own repository before changing anything. Every route, model and service named below was checked on 2026‑10‑22. If something changed since then, adapt to what is there now and never add a duplicate.
2. **Implement** the requirements in the order given. Do not return a plan.
3. Keep the current conventions:
   - errors as `{"detail": {"code", "message", …}}`;
   - `org_ctx(resource, action)` for permissions;
   - `audit(...)` for audit records;
   - `jobs.bump` for versioning;
   - `jobs.snapshot` for revisions;
   - `_describe` for readable conflicts;
   - `_validate` / `solver.validate` for the hard rules.
4. Don't refactor anything unrelated, don't rename anything, and don't add a second solver or a second validator.
5. Stay backward compatible. Every existing request and response keeps working unchanged.
6. Verify for real. Run the new tests and the existing schedule suites (`tests/org_v2/solver_unit.py`, `solver_groups_unit.py`, `e2e_timetable_v3.py`, `e2e_course_plans.py`, `concurrency_v3.py`). Report the actual results. Never report a test as passing unless it ran.
7. Use as few tokens and as little compute as the work allows, without skipping essential implementation or tests.

All paths below are under `/api/v1/org/orgs/{org_id}`.

---

## A. Already implemented: do not redo

These were verified in `routers/organization/org_schedule_router.py`, `services/organization/{org_schedule_solver,schedule_context,schedule_jobs,course_plans}.py`, `data/models.py` and `data/org_models.py`. The frontend uses all of them.

| Area | What exists |
|---|---|
| Set-up | Periods, rooms, facility types, availability, loads, staff candidates and staff preferences |
| Timetables | CRUD, with `version` and `expected_version` checked through `jobs.bump` (409 `stale_version`) |
| `settings` | `days`, `avoid_days`, `avoid_period_ids`, `max_periods_per_day_teacher`, `group_alignment` and `relax_order`, checked by `_check_settings` |
| Generation | `POST /schedules/{sid}/generate`, which runs in the background with `?background=true` and takes `keep_locked`, `seed` and `persist_settings` (false means a trial run). Runs can be listed, read and cancelled. |
| Report | `schedule.result` holds `status` (feasible, feasible_relaxed, partial or infeasible), `unscheduled[]` (with `kind`, `group_no`, `missing` and `reason`), `relaxed[]` (with `role` and `cells`), `suggestions[]` (with `reason`, `sessions` and `text`) and `stats` (`sessions_required`, `sessions_placed`, `soft_cost` and `weights`) |
| Validation | `GET /schedules/{sid}/validate` returns `conflicts[]` (each with `severity`, which is error, warning or soft, plus `type`, `day`, `period_ids`, `slot_ids`, `course_ids`, `text_ar`/`text_en`, `removable_slot_ids` and `elsewhere`), the counts and `version`. It covers other active timetables too. |
| Slot edits | `POST` and `PUT /schedules/{sid}/slots…` accept `?dry_run`, `force`, `strategy` (keep, replace, shift or regenerate), `group_no` and `expected_version`. A hand edit locks the slot. |
| Revisions | `GET`, `POST` (manual, with a label), get, and restore. Restore brings back the slots, `result` and `settings`. |
| Groups | `GET` and `PUT /schedules/{sid}/course-plans[/{course_id}]`, a bulk `PUT`, `history` (the last completed offering) and `count_source` (enrolled, manual or history). The solver's group rules and room capacity are checked per group. |

**Not needed:** a separate "analysis" or "quality" endpoint. The dashboard is built from `validate`, `schedule.result` and the suggestions below.

---

## B. Missing: implement in this order

### 1. Suggestion storage

Add a new model `OrgScheduleSuggestion` (`org_schedule_suggestions`) in `data/org_models.py`. `create_all` creates it, the same way `org_schedule_course_plans` was created, so no column-ensure entry is needed.

| Column | Type | Notes |
|---|---|---|
| `id` | int PK | Exposed as the string `suggestion_id` |
| `schedule_id` | FK `org_schedules.id`, `ON DELETE CASCADE`, indexed | |
| `type` | String(24) | `reschedule_session`, `add_period`, `add_day`, `add_room`, `reallocate_groups`, `reassign_staff` or `combined` |
| `status` | String(12), indexed | `pending`, `accepted`, `applied`, `rejected`, `invalidated` or `failed` |
| `base_version` | int | The `schedule.version` it was computed or last revalidated against |
| `fingerprint` | String(64), indexed | sha1 of `type` plus the sorted `changes` and `config`, used for deduplication |
| `payload` | JSON | `title_*`, `reason_*`, `affected`, `changes`, `config`, `impact`, `introduced_conflicts`, `validation` and `requires` |
| `applicable` | bool | False for advice that can only be acted on outside the timetable, such as "open a new lab". It can only be rejected. |
| `decided_by`, `decided_at`, `decision_reason` | int, datetime, String(255) | |
| `revision_before_id`, `revision_id` | FK `org_schedule_revisions.id`, `SET NULL` | Undo restores `revision_before_id` through the existing restore route |
| `error` | String(255) | Why the suggestion failed or was invalidated |
| `created_at` | datetime | |

`payload` holds references (slot ids and entity ids), never copies of the timetable.

### 2. Suggestion engine (`services/organization/schedule_suggestions.py`)

Build it on top of the existing solver. Use `Board` and `_hard()` for hard checks, `room_fits`, `elig.check` for staff, `cp` for groups, and `_validate` on the **complete** slot set, which includes `external` (the other active timetables). Every candidate must pass this sequence before it is stored:

1. Apply the candidate to a copy of the current slot dicts.
2. Run `_validate`.
3. Compute `impact` by diffing that result against the current `_validate` result. Count only severities `error` and `warning`.
4. Store the conflicts the candidate introduces as `introduced_conflicts`, run through `_describe`.

A candidate that **introduces a hard conflict** is dropped, or stored with `validation.valid = false` when it is the only way to show the user why nothing works. Removing one conflict never makes a candidate valid on its own.

Each type has these rules. The `config` fields are the frontend contract.

| Type | Proposal | Hard requirements |
|---|---|---|
| `reschedule_session` | Move one session, or one ejection chain of depth ≤ 2, to another day, period, room or staff member. Every changed slot goes in `changes[]`. | Respect availability, the room's kind, capacity, capabilities and exclusivity, group rules and other timetables. A locked slot moves only if the user asked for it; skip locked slots by default. |
| `add_period` | `config.periods = {"before": n, "after": n+1, "add": [{"label", "start_time", "end_time", "order"}]}`. Run a **trial generation** (`persist_settings=false`, `keep_locked=true`) to fill `impact.unscheduled_before/after` and `conflicts_after`. | Must respect `horizon.max_periods_per_day` and `allow_expansion`. Periods are **organization-wide**, so set `affected` to include the other draft or active timetables that would see the new period. |
| `add_day` | `config.days = {"before": [...], "after": [...]}`, with the impact measured by a trial generation as above | `horizon.min_days`, `max_days` and `allow_expansion` |
| `add_room` | Either (a) reassign to an **existing** room that satisfies kind, capacity, capabilities, availability and exclusivity (`changes[]`, `applicable=true`), or (b) advice to open a facility that doesn't exist, as `config.rooms.add=[{"name", "kind", "capacity", "capabilities"}]` with `applicable=false` | Never treat a lecture hall as a lab, or any other kind, unless its `kind` and `capabilities` match the load's `room_kind` and `required_capabilities` |
| `reallocate_groups` | `config.groups=[{"course_id", "kind", "before": n, "after": m}]`. Sizes come from `cp.split` and the planned count (`expected_students` or the number enrolled). | Groups that share students or staff must never overlap. Room capacity is checked per group. The 40-group cap is `cp.MAX_GROUPS`. |
| `reassign_staff` | Change `teacher_id` or `assistant_id` on slots or `group_staff` | `elig.check` must pass (qualification and role), plus availability, `max_periods_per_day_teacher` and live membership. **Never** assign an ineligible person. |
| `combined` | Two or more of the above with one combined `impact`. Each item in `changes[]` carries its own `reason_*`. | Validate the combination as a whole, not each part separately |

Optimization priorities, as an explicit lexicographic order:

1. no hard violations;
2. fewer unscheduled sessions;
3. fewer remaining conflicts of severity `error` or `warning`;
4. **fewer changed slots**, for stability;
5. lower `soft_cost`, using the existing `SOFT_WEIGHTS`.

Add a soft weight `stability` that penalizes moving a slot that was already placed. It applies only to suggestion trials and to the regeneration that follows an applied configuration change, and it is off for normal generation, so existing outputs stay byte-identical.

Never call a result optimal. The search is heuristic, so return the best candidates found within the time limit.

**Explanations:** `reason_ar` and `reason_en` must name the rule, using the `_CONFLICT_TEXT` and `REASON_SUGGESTION` vocabulary, along with the course, group, person, room, day and period involved. When no rule-based reason can be stated, leave `reason_*` empty rather than inventing one.

**Limits and efficiency:**
- Return at most 20 pending suggestions, within `time_limit_s` (default 10).
- Validate only the affected days and people where `_validate` makes that safe; otherwise validate the full set.
- If pending suggestions already exist for the current `version` and the same `types`, `POST` returns them and computes nothing, unless the body has `"refresh": true`.
- A fingerprint rejected at the same `base_version` is never proposed again. Once the version changes, it may be proposed again.

### 3. Endpoints

Every item in a list response uses the serialized suggestion shape. The frontend's `ScheduleSuggestion.fromJson` reads exactly these keys:

```json
{
  "suggestion_id": "123", "schedule_id": 42, "status": "pending", "type": "reschedule_session",
  "title_ar": "…", "title_en": "Move the lab session", "reason_ar": "…", "reason_en": "The assistant is already busy then",
  "base_version": 7, "applicable": true,
  "affected": [{"type": "course|group|teacher|assistant|room|period|day|students|timetable", "id": 5, "label": "CS101 · Lab G2"}],
  "changes": [{"op": "move|assign_room|assign_staff|add|remove", "slot_id": 501, "course_id": 5, "kind": "lab", "group_no": 2,
               "before": {"day": "sunday", "period_id": 3, "room_id": 10}, "after": {"day": "monday", "period_id": 4, "room_id": 12},
               "reason_ar": "…", "reason_en": "…"}],
  "config": {},
  "impact": {"resolved_conflicts": 1, "introduced_conflicts": 0, "remaining_conflicts": 2, "conflicts_before": 3, "conflicts_after": 2,
             "unscheduled_before": 1, "unscheduled_after": 0, "soft_cost_before": 12.5, "soft_cost_after": 11.0},
  "introduced_conflicts": [],
  "validation": {"valid": true, "checked_version": 7, "hard_constraint_violations": []},
  "requires": {"permission": "schedule.update", "approval": false},
  "decision": {"by": 9, "at": "2026-10-22T10:00:00", "reason": null},
  "result": {"revision_before_id": 88, "revision_id": 89, "error": null},
  "created_at": "…"
}
```

`day` uses the existing day keys (`saturday` … `friday`).

`requires.permission` is `schedule.approve` with `approval: true` for `add_period`, `add_day`, `add_room` that has `config`, `reallocate_groups`, and any `combined` suggestion that contains one of those. Otherwise it is `schedule.update`.

| Method and path | Permission | Request | 2xx response |
|---|---|---|---|
| `GET /schedules/{sid}/suggestions?status=` | `schedule.view` | — | `{"items": [S], "version": int}` sorted pending first, then by `impact` and `created_at` desc, with at most 100 items |
| `POST /schedules/{sid}/suggestions` | `schedule.update` | `{"expected_version": int\|null, "types": [str]\|null, "refresh": false}` | `200 {"items": [S], "version"}` |
| `POST /schedules/{sid}/suggestions/{id}/accept` | `schedule.update`, plus `schedule.approve` when the suggestion requires it | `{"expected_version": int\|null}` | `200 {"suggestion": S, "version", "revision": {"id", "number"}}`. When applying needs a background regeneration (a configuration change), the response is `202 {"suggestion": S(status "accepted"), "run": run_dict}` and the run's end sets `applied` or `failed`. |
| `POST /schedules/{sid}/suggestions/{id}/reject` | `schedule.update` | `{"reason": str\|null}`, at most 255 characters | `200 S` |
| `POST /schedules/{sid}/suggestions/apply` | as for accept, for every id | `{"ids": [str], "expected_version": int\|null}`, with 1–20 ids | `200 {"items": [S], "version", "revision"}`, or 202 as above |

Each step of accept and of batch apply runs in **one transaction**:

1. Lock the suggestion row or rows (`with_for_update`).
2. If any status isn't `pending`, return 409 `suggestion_already_applied` when it is `applied`, otherwise 409 `suggestion_not_pending`.
3. Check `bump(db, sid, expected_version)`. A mismatch returns 409 `stale_version` with `current_version`. This means the user's view of the timetable is out of date.
4. If `base_version` ≠ the current version, **revalidate**. If the `before` values no longer match the slots, or a slot is gone, set `status = invalidated` with an `error` and return 409 `suggestion_stale`. Otherwise re-run step 2 of the engine on the current slots. If a hard conflict is now introduced, set `invalidated` and return 422 `suggestion_invalid` with `detail.conflicts` (run through `_describe`). If it still holds, set `base_version` to the current version and continue.
5. `applicable = false` returns 422 `suggestion_not_applicable`.
6. **Undo point.** If the latest revision's `summary.version` equals the current version, use it as `revision_before_id`. Otherwise write one with `jobs.snapshot(..., "manual", summary={"label": "before suggestion <id>"})`. Don't write redundant copies.
7. Apply the changes:
   - slots through the same code paths as `PUT /slots`, marked `locked = True` and `source = "manual"`;
   - `config.days` merged into `settings.days`;
   - `config.periods.add` through the same validation as `POST /periods`, which needs `schedule.approve`;
   - groups through `cp.clean` and the save path of `PUT /course-plans`.

   Configuration changes then start a regeneration (`keep_locked = true`, stability on) through `jobs.start_run`, and the response is 202. If `horizon.auto_apply_approved` is false, the configuration change is still applied, because accepting it is the approval; the flag only matters when approval is handled outside the app.
8. Write `jobs.snapshot(db, sched, "suggest", ...)`. `source` is `String(10)`. Use `summary = {"suggestion_ids": [...], "result": sched.result}`, and store the revision in `revision_id`.
9. Write the audit entry `schedule.suggestion.apply` with the ids, revision numbers and version, set `status = applied` together with `decided_by` and `decided_at`, and commit.

**Batch apply:** apply the suggestions in order against the cumulative state. If two suggestions touch the same `slot_id`, return 409 `suggestions_overlap`. On the first failure, roll back everything, return the error code above with `"failed_id"`, and change nothing. Write one undo point and one revision for the whole batch.

**Reject:** a non-pending suggestion returns 409 `suggestion_not_pending`. Store the reason, `decided_by` and `decided_at`, and write the audit entry `schedule.suggestion.reject`.

**Generate (`POST`):**
- 409 `stale_version` when `expected_version` is out of date.
- 409 `generation_running` while a run is active.
- 409 `schedule_published` when the timetable is `active`.
- 409 `suggestion_running` when another generate call for this timetable is still computing. Use an in-process lock or a row lock on the schedule.
- 422 `bad_types` for an unknown type.
- Write the audit entry `schedule.suggestion.generate` with the count.

**Other writes:** any write to the timetable — slots, generate, restore, or a settings change through `PUT /schedules` — leaves pending suggestions as they are. They are revalidated when someone accepts them (step 4), so no extra write is needed. Deleting a timetable cascades to its suggestions.

**Undo:** the frontend calls the existing `POST /schedules/{sid}/revisions/{revision_before_id}/restore`. No new route is needed. Restore must also restore `settings` and `result`, which it already does.

### 4. Scheduling horizon (`settings.horizon`)

This is stored in the existing settings JSON and written by the existing `PUT /schedules/{sid}` with the full body:

```json
"horizon": {"mode": "flexible|forced", "min_days": 1, "max_days": 7, "max_periods_per_day": 8, "allow_expansion": true, "auto_apply_approved": false}
```

Extend `_check_settings` with these rules:
- Each value must be in range: days 1–7, periods 1–16 or null.
- `min_days` must be ≤ `max_days`, otherwise 422 `bad_horizon` with `field`.
- `len(settings.days)` must lie within [`min_days`, `max_days`], otherwise 422 `horizon_exceeded`.
- **Changing** `horizon`, or setting `mode: "forced"`, requires `schedule.approve`. Without it, return 403 `{"code": "approval_required"}`.

Effects:
- In `flexible` mode, `add_day` and `add_period` suggestions are generated only when `allow_expansion` is true, and only within the bounds. Otherwise the types are skipped silently, or rejected with 422 `expansion_not_allowed` when they were requested explicitly in `types`.
- In `forced` mode, the admin sets `days` directly. All hard rules still apply. A forced configuration never relaxes student, staff, room, capacity or availability rules, and `validate` and `publish` behave exactly as they do today.
- When there is no `horizon` key, behavior is exactly as it is today.

### 5. Small additions

- `GET /schedules/{sid}/validate` adds `"by_type": {type: count}` for severities error and warning. This is additive. The frontend computes it today and will switch to it once it exists.
- `GET /schedules/{sid}/revisions` items whose `source` is `"suggest"` expose `summary.suggestion_ids`. This is already covered if `summary` is returned as it is today.
- `FLUTTER_API_CHANGES.md` gets one section describing sections 1–4.

---

## C. Error codes the frontend already maps

`lib/features/org/org_v3.dart` already has text for these codes. Use them exactly:

`stale_version`, `suggestion_stale`, `suggestion_invalid`, `suggestion_already_applied`, `suggestion_not_pending`, `suggestion_not_found` (404), `suggestion_not_applicable` (422), `suggestions_overlap`, `suggestion_running`, `horizon_exceeded`, `expansion_not_allowed`, `bad_horizon`, `approval_required` (403), `generation_running`, `schedule_published`, `no_history`.

## D. Acceptance tests

Add `tests/org_v2/e2e_suggestions.py` in the same style as `e2e_timetable_v3.py`, plus unit cases in `solver_unit.py` for the stability weight. Every case below must pass:

1. **Detection is honest.** In a timetable where teacher T is double-booked, `POST /suggestions` returns a `reschedule_session` whose `impact.resolved_conflicts ≥ 1` and `introduced_conflicts = 0`. Applying it leaves `validate` with one fewer error.
2. **No conflict trading.** When every free cell for a session clashes with a shared-student course, no valid move suggestion is returned. Any returned suggestion has `validation.valid = false` and a non-empty `introduced_conflicts`.
3. **Other timetables count.** A move into a cell where the room is booked in another *active* timetable is never valid.
4. **Rooms:**
   - A 60-student group is never moved into a 40-seat room.
   - A lab session is never moved into a lecture hall that lacks the required capabilities.
   - When no room fits, `add_room` comes back with `applicable = false`, and accepting it returns 422 `suggestion_not_applicable`.
5. **Staff:** a `reassign_staff` suggestion never names a person for whom `elig.check` fails, or who is unavailable at that cell.
6. **Groups:** after `reallocate_groups`, two lab groups that share an assistant are not placed in parallel, and every group fits its room.
7. **Horizon:**
   - With `allow_expansion = false`, no `add_day` or `add_period` suggestions are returned.
   - With `max_days = 5` and 5 days already set, `add_day` is never proposed.
   - A PUT with 6 days and `max_days = 5` returns 422 `horizon_exceeded`.
   - Changing `horizon` without `schedule.approve` returns 403 `approval_required`.
8. **Add a period or day:** `impact.unscheduled_after` matches a trial generation with the same seed, and the timetable's stored `settings` are unchanged until the suggestion is accepted.
9. **Accept:** the response is 200, the suggestion is `applied`, `version` is +1, the revision has source `"suggest"`, the audit row exists, and `revision_before_id` is set.
10. **Duplicate:** a second accept of the same id returns 409 `suggestion_already_applied`. Two **concurrent** accepts of one id (two threads, as in `concurrency_v3.py`) produce exactly one 200 and one 409.
11. **Stale view:** accepting with an old `expected_version` returns 409 `stale_version` and changes nothing.
12. **Stale suggestion:**
    - If the slot was moved by hand after the suggestion was made, accepting it returns 409 `suggestion_stale` and its status becomes `invalidated`.
    - If an unrelated slot was changed instead, accept revalidates and succeeds.
13. **Invalid on revalidation:** if the target cell was filled after the suggestion was made, accepting it returns 422 `suggestion_invalid` with `detail.conflicts`.
14. **Reject:**
    - The reason is stored and the decision is audited.
    - With `refresh: true` at the same version, the suggestion is not proposed again.
    - After the timetable changes, it may be proposed again.
15. **Batch:**
    - Three valid suggestions apply as one revision with one version bump.
    - If one of them overlaps another on a slot, the whole batch returns 409 `suggestions_overlap` and nothing changes.
16. **Undo:** restoring `revision_before_id` gives back the exact slots, `settings` and `result` from before the apply.
17. **Permissions:**
    - A user with view rights only can list but not generate, accept or reject.
    - A user without `schedule.approve` cannot accept a suggestion with `requires.approval = true`.
18. **Published timetable:** generate and accept return 409 `schedule_published`.
19. **Regression:**
    - With no suggestions and no `horizon`, generation output is byte-identical to today's for the existing seeds.
    - All existing schedule suites still pass.
20. **Cost:** a second `POST /suggestions` at the same version, without `refresh`, returns the same ids without recomputing.

## E. Frontend references

These files are already built. Don't change them; keep the JSON compatible with them.

- `lib/features/org/org_schedule_optimizer.dart`:
  - `ScheduleSuggestion.fromJson` and `SuggestionImpact` for the shape in section 3;
  - `RemoteSuggestionApi` for the routes;
  - `ScheduleHorizon` for section 4;
  - `ScheduleHealth` for the dashboard, built from `validate` and `result`.
- On an older server, a bare FastAPI 404 `"Not Found"` or a 405 shows "needs a server update" (`orgEndpointMissing`). The development mock (`--dart-define=ORG_SCHEDULING_MOCKS=true`) is never part of a release build.
