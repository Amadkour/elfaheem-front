# Backend prompt: relaxation priority, trial alternatives, version management and member copies

**For:** the Backend AI Agent working in `../back` (FastAPI + SQLAlchemy).

**Frontend counterpart (already built):**
- `lib/features/org/org_schedule_versions.dart`: relaxation policy, ranking, diffs, member copies and CSV.
- `org_schedule_alternatives.dart`
- `org_schedule_copies.dart`
- `org_schedule_optimizer.dart`
- `org_schedule_planning.dart`
- Tests: `test/org/org_versions_test.dart`, `org_optimizer_test.dart` and `org_planning_test.dart`.

Paths below are relative to `../back`:
- **R** is `routers/organization/org_schedule_router.py`
- **J** is `services/organization/schedule_jobs.py`
- **S** is `services/organization/org_schedule_solver.py`
- **SG** is `services/organization/schedule_suggestions.py`

## Working rules

- Read the cited code before changing it. Line numbers are from the current `HEAD` and may drift.
- Reuse the existing pieces:
  - `jobs.bump` (409 `stale_version`), `jobs.snapshot`, `jobs.start_run` and `jobs.execute`;
  - `solver.validate`, `_check_settings`, `org_ctx(module, action)`, `audit(...)`;
  - the `_describe` conflict shape.
- Do not change any existing response field. Only add fields.
- Every write that depends on the timetable version accepts `expected_version` and goes through `jobs.bump`.
- Add tests under `tests/org_v2/`, next to `e2e_timetable_v3.py`, `solver_unit.py` and `concurrency_v3.py`.

---

## A. Already verified: do not rebuild

| Capability | Evidence |
|---|---|
| Suggestions: storage, list, generate, accept, reject and batch apply. Apply is one transaction with a pending→applied compare-and-set, an undo revision, revalidation, `stale`/`invalid` handling, overlap refusal, and a 202 regeneration run for configuration changes. | R:1385-1690, SG |
| Scheduling horizon (`settings.horizon`): validation, approval required to change it, enforcement on accept | R:420-455, SG:69-76, SG:801-809 |
| Stability weight when regenerating after an accepted suggestion | R:1684 (`"stability": True`), SG `trial` |
| Generation with a settings override that is not stored (`persist_settings=false`). Each successful run stores a `generate` revision with its settings. | R:650-687, J:149-164 |
| Revisions: list, create (manual, with label and `expected_version`), get (slots plus summary), restore (slots, result and settings; bumps the version) | R:731-795, J:198-240 |
| Slot edits (room, staff, time, group), with `dry_run` and `expected_version` | R:814-870 |
| Periods CRUD (start < end checked); adding days through `settings.days` | R:68-116, R:620-633 |
| Course plans: expected students, group sizes and counts, per-group staff, `count_source` | R:1287-1390, `services/organization/course_plans.py` |
| Excel export of a timetable's live slots | `routers/organization/org_admin_router.py:1055`, `org_excel_service.py:341` |
| A member's own sessions from ACTIVE timetables, and a notification to every member on publish | `org_public_router.py:132-161`, R:1055-1065 |
| Permissions: `schedule.view`, `insert`, `update`, `delete`, `approve` | `org_ctx` across R |

---

## B. Confirmed gaps (by priority)

### G1 (P1): Relaxation priority by tier

**Evidence**
- The only relaxation setting is `relax_order ∈ {none, role_then_experience}` (R:413).
- The solver applies it as a weight factor on two soft costs only (`avoid`, `not_preferred`), with `ROLE_TIER = {teacher_assistant: 1, admin_assistant: 2, teacher: 3}` (S:66, S:197-198, S:242-248).
- Student preferences, rooms and the other soft costs have no tiers.
- `result.relaxed` is filled only for the teacher and the assistant (S:579), with no tier or constraint name.
- Suggestion ranking (SG header) does not consider which tier a change relaxes.

**Frontend behaviour today**
- Admins order six tiers. The order is stored in `settings.relaxation_priority` (unknown keys are kept by `_check_settings`). The frontend also sets `relax_order` to `role_then_experience` when assistants come before teachers.
- The order is used only to rank alternatives on the client (`compareVersions`). The UI tells the user that the server applies only the assistant-versus-teacher part.

**Required**
1. **Validation:** `settings.relaxation_priority` is an ordered list. Each item is one of `student_prefs`, `add_capacity`, `rooms`, `assistant_prefs`, `other_soft`, `teacher_prefs`, with no duplicates. Missing tiers are appended in that default order. Anything else returns 422 `bad_settings` with `field: "relaxation_priority"`. Changing it requires `schedule.update`.
2. **Solver weights:** the multiplier for each tier grows with its position. The first tier is cheapest to relax; the last (default: `teacher_prefs`) is the most expensive. It must stay strictly lexicographic: a violation of a later tier must cost more than any total of earlier-tier violations the instance can produce, for example base^rank with base > max count × max weight.
   - Hard rules are never weighted: double booking, availability, capacity, facilities, eligibility, the teacher's daily maximum.
   - When `relaxation_priority` is absent, the current `relax_order` behaviour stays unchanged.
3. **Relaxable flag:** a preference relaxes only if its policy allows it. Add `relaxable: bool` (default `true` for preferences, `false` for unavailability) to the stored availability/preference rows, and never relax a row with `relaxable=false`.
4. **Report:** each `result.relaxed[]` entry gets:
   - `tier` (one of the six);
   - `constraint` (`avoid` or `not_preferred`);
   - `severity` (its weighted cost).
   
   Add `result.relaxed_by_tier: {tier: severity}`.
5. **Suggestion ranking:** in SG, rank by (hard violation, unscheduled, remaining conflicts, the relaxation vector from the most protected tier down, changed slots, soft cost). Each suggestion gets `relaxes: [{tier, constraint, user_id?, slot_ids}]` and `preserves: ["eligibility", "capacity", "facilities", "no_double_booking", "availability"]`.

**Acceptance tests**
- With an order that ends in teacher_prefs, an instance that can be solved by relaxing either one teacher preference or three assistant preferences relaxes the assistant's.
- Reversing the order flips the choice.
- A `relaxable=false` preference is never used, and the session stays unscheduled with a reason instead.
- `bad_settings` is returned for an unknown tier or a duplicate.
- No `relaxation_priority` gives results identical to today's (regression).

### G2 (P1): Trial alternatives that do not touch the live timetable

**Evidence:** on success, `execute` deletes the unlocked slots, inserts the new ones, sets `sched.result` and bumps the version (J:149-164). No generation mode leaves the live slots alone. The frontend generates each alternative on the live draft and then restores the original revision (`org_schedule_alternatives.dart`). That works only for drafts and creates several restore revisions.

**Required**
- `POST /schedules/{sid}/generate` accepts `trial: bool = false` (body). With `trial=true`, `execute`:
  - runs the solver;
  - writes only a revision with `source="alternative"` and `summary = {label?, version: <current>, result, settings: <effective>, seed, trial: true}`;
  - does not change slots, `result`, settings or the version.
  
  It is allowed on active timetables, needs `schedule.update`, and writes an audit entry.
- The run's `revision_id` points to that revision. Restoring it is the explicit "apply". The existing restore already bumps the version, so add `?expected_version` checking there (see G3).
- Duplicate detection: if a trial produces exactly the same slot multiset as an existing alternative revision for the same base version, return that revision's id with `duplicate_of` and write nothing.

**Acceptance tests**
- A trial on an active timetable leaves its slots, version and settings byte-identical.
- The new revision has `source=alternative` and the effective settings.
- Two different seeds give two revisions; the same seed twice gives `duplicate_of`.
- Restoring with a stale `expected_version` returns 409.

### G3 (P2): Version management (rename, delete, validate a stored revision)

**Evidence**
- Revision routes are list, create, get and restore only (R:731-795). There is no PATCH or DELETE.
- `GET …/validate` (R:795) validates the live slots only, so alternatives cannot be compared on hard conflicts before applying. The frontend shows "not validated".
- Restore does not check `expected_version` (R:779).

**Required**
- `PATCH /schedules/{sid}/revisions/{rev}` with `{label (≤80)}`, requiring `schedule.update`. Only the label changes, never the slots. Audit it.
- `DELETE /schedules/{sid}/revisions/{rev}`, only for `source in ("alternative", "manual")` and never for the revision linked to the latest publish. It requires `schedule.delete`. Otherwise return 409 `revision_protected`.
- `GET /schedules/{sid}/revisions/{rev}/validate` returns the same shape as `GET …/validate` (`conflicts` with severity and `version`), run on the revision's slots and its stored settings against the other active timetables. It is read-only.
- `POST …/revisions/{rev}/restore?expected_version=` returns 409 `stale_version` when the version is out of date.
- The revision list gets `version` (from `summary.version`) and `settings_hash`, so clients can tell copies apart without a get.

**Acceptance tests**
- Renaming keeps the slots.
- Deleting a publish revision returns `revision_protected`.
- Validating a revision with a double booking reports it, and the live timetable's validate is unchanged.
- A stale restore returns 409.

### G4 (P2): Export of a revision or a member copy

**Evidence:** `export_sheet(..., schedule_id)` (`org_excel_service.py:341-387`) exports only the live slots of one timetable. There is no `revision_id` or member filter. The frontend exports those as CSV on the client.

**Required**
- `GET /orgs/{org_id}/export/schedule` adds `revision_id?` and `member_type? ∈ {teacher, assistant, group, room}` with `member_id?` (and `group_no?` / `kind?` for groups).
- The sheet header names the timetable, the revision number and label, the timetable version and the creation time.
- Use the existing export permission (`_need(ctx, kind, "export")`), plus `schedule.view`.
- A revision from another schedule or organization returns 404.

**Acceptance tests**
- A teacher filter returns exactly the rows where `teacher_id` matches.
- An assistant filter matches `assistant_id` or `admin_assistant_id`.
- The header carries the revision number and version.

### G5 (P2): Distributing a selected version's member copies

**Evidence**
- Members see only ACTIVE timetables through `GET /org/public/schedule/me` (`org_public_router.py:132-161`).
- The only distribution is the publish notification (R:1055-1065).
- No route sends a chosen version to its members, and nothing records which version a member received or whether it has since changed.

**Required**
1. **Table** `org_schedule_member_copies`: `id`, `schedule_id`, `revision_id`, `version`, `member_type`, `member_id`, `group_no?`, `kind?`, `slots_hash`, `created_by`, `created_at`, `superseded_by?`. Unique on (`revision_id`, `member_type`, `member_id`, `group_no`, `kind`).
2. **`POST /schedules/{sid}/revisions/{rev}/distribute`** with `{member_types: [...], notify: bool, expected_version?}`, requiring `schedule.approve`:
   - Creates one row per member present in the revision.
   - Never rewrites a row. A redistribution of a newer revision sets `superseded_by` on the older rows.
   - Notifies each member with their own sessions only.
   - Idempotent: repeating it for the same revision returns the existing rows.
3. **`GET /org/public/schedule/copies/me`** returns the caller's copies: `{revision_id, version, schedule_name, outdated: bool, items: [own slots only]}`. A copy is `outdated` when it is superseded or the live version is newer. The caller must be that member: a teacher or assistant by user id, a student through active enrollment in the course and group. It never returns other members' slots.
4. **`GET /schedules/{sid}/member-copies`** lists, for admins (`schedule.view`), who received which version and which copies are outdated.

**Acceptance tests**
- Each member's copy equals the revision filtered for them.
- A student cannot read another group's copy (403/404).
- After the live timetable changes, `outdated=true`.
- Distributing a newer revision supersedes and never deletes.
- Distributing the same revision twice creates no duplicates.

### G6 (P3): Period overlap check

**Evidence:** `POST /periods` and `PUT /periods/{pid}` check only `start < end` (R:83, R:98). Overlapping periods are accepted, and so are `add_period` suggestions whose new period overlaps an existing one, since they use the same `_new_period` (R:82).

**Required:** in `_new_period` and in the update route, refuse with 422 `period_overlap` and `{conflicts_with: [period ids]}` when the interval overlaps another active period of the organization.

**Acceptance tests**
- 08:00-09:00 plus 08:30-09:30 returns 422.
- Back-to-back periods (09:00-10:00) are accepted.
- An `add_period` suggestion that would overlap is invalidated instead of applied.

### G7 (P3): Staff eligibility in validate

**Evidence:**
- `solver.validate` has no eligibility conflict type (S:654-759).
- `not_eligible` is checked only when loads or staff are set (R:385) and in suggestion checks (SG:823).
- A slot later edited by hand (`PUT /slots`, R:836) to an ineligible teacher is never reported.

**Required:** validate reports `staff_not_eligible` (severity `error`, with `slot_id`, `user_id`, the reason from `staff_eligibility`) for every slot whose teacher or assistant is not eligible for its course and kind. `PUT /slots` refuses it unless the caller sends `override_reason` with `schedule.approve`, as with unavailability.

**Acceptance test:** a hand-assigned ineligible teacher shows `staff_not_eligible`, and publishing is refused.

---

## C. New error codes

| Code | HTTP | Where |
|---|---|---|
| `bad_settings` (`field: relaxation_priority`) | 422 | G1 |
| `revision_protected` | 409 | G3 |
| `period_overlap` | 422 | G6 |
| `staff_not_eligible` | 409 conflict / validate type | G7 |

The frontend already shows `stale_version`, `approval_required` and the suggestion codes.

## D. Not confirmed (check before building)

- Whether `relax_order=role_then_experience` should keep turning on seniority (S:198) when `relaxation_priority` is present. Product decision.
- Whether students should be able to see a version that is not published (G5 assumes only distributed copies, never drafts).
