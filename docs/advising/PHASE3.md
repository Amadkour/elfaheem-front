# Phase 3 — Settings and assignment: brief and contract

Read `PLAN.md` §3.2 (policies, profiles, conflicts, assignments, runs, handovers), §3.4, §3.8 and `PHASE2.md` (the
common rules there apply unchanged: own worktree only, `git commit --only`, never push or merge, `-j 2`, the Python
venv, Arabic + English, no placeholders, lead-owned files, report ≤ 15 lines). Brief requirements covered: §2.1
(configuration), §2.2 (automatic assignment and welcome), defaults #2 (notifications), #5 (caseload), #17 (handover),
#22 (conflicts and continuity).

Owner decision after Phase 2: **an existing advisor link is kept** when advising is switched on, even when that
advisor is no longer active staff. `import_legacy` imports it as a locked `legacy` primary (no clearing of
`advisor_id`); such students count as assigned AND as `advisor_away` so the director reassigns them deliberately.
Only when the advisor's user row no longer exists is nothing imported (the `advisor_id` stays as it is).

## Shared rules for this phase
- Who: **manage** = org admin or advising director (`access.roles`); **advisor** = holds an active assignment or is
  eligible by policy; students never reach these routes (403 `advising_forbidden`). Every route: kill switch →
  eligibility → enabled (`require_enabled`), then the role check.
- Lists: `page` (1-based), `size` ≤ 100 (default 25), envelope `{"items","total","page","size","pages","facets"}`.
- Errors `{"code","message","message_en"}`; new codes get ar + en in `text.py`.
- Every write audited (`OrgAuditLog`, before / after); notices through `notices.send` (dedupe + delivery log).
- "Away" advisor = profile status `leave` · `sabbatical` · `left` (inside its dates) OR no live staff membership in the
  organization's chain. Away advisors never receive new students.
- Capacity: `max_load` = profile override or the effective policy's; load = active `primary` assignments;
  `warn` when load ≥ `warn_pct` % of max; nobody goes above max unless the caller sends `force_over_capacity: true`
  with a `reason` (manage only; audited).
- Continuity (#22): an assigned student keeps their advisor across terms; distribution never touches an assigned
  student except in `rebalance` / `reassign` mode, and never a `locked` or `manual` assignment.
- Conflicts (#22): an active conflict (advisor, student) blocks that pairing everywhere (auto and manual: 409
  `advising_conflict`).

## API (base `/api/v1/org/orgs/{org_id}/advising`)

### Settings
- `GET /policy` (manage) →
  `{"effective": Policy, "defaults": Policy, "org": {"id": int|null, "settings": {..partial..}, "updated_at"},
    "scopes": [{"id", "scope_type": "dept"|"program"|"level"|"cohort", "scope_ref": str, "label", "settings": {..},
                "updated_at"}],
    "options": {"roles": [{"key","label_ar","label_en"}], "ranks": [...same...], "strategies": [...same...],
                "depts": [{"id","name"}], "programs": [{"id","name"}], "levels": [str], "cohorts": [str]}}`
  `Policy` = every field of `policy.AdvisingPolicy` (`eligible_roles`, `eligible_ranks`, `mode`, `max_load`,
  `warn_pct`, `strategy`, `auto_assign`, `digest`, `sla_hours{low,normal,high,urgent}`, `nudge_days`,
  `retention_months`, `survey`, `workflow_steps`).
- `PUT /policy` (manage) body `{"scope_type": "org"|"dept"|"program"|"level"|"cohort", "scope_ref": str|null,
  "settings": {..partial..}}` → replaces that scope row's settings (an empty `{}` = inherit everything); 422
  `advising_bad_policy` / `advising_bad_scope`. Returns the GET body.
- `DELETE /policy/{policy_id}` (manage) → removes a scope row (not the org row: 422 `advising_bad_scope`); GET body.

### Advisors and their profiles
- `GET /advisors?q=&status=available|away|over|all&page=&size=&sort=load|name` (manage) → items
  `{"user_id","name","rank": str|null,"role","dept": str|null,"status": "available"|"leave"|"sabbatical"|"left",
    "status_from","status_until","away": bool,"eligible": bool,"max_load": int,"max_load_override": int|null,
    "load": int,"co_load": int,"load_pct": int,"warn": bool,"over": bool,"office_location","contact_note"}`;
  facets `{"available","away","warn","over"}` counts. The list = staff eligible by the effective policy plus anyone
  holding an active assignment.
- `GET /advisors/me` (any staff) → the same item for the caller (`eligible` false + zero loads when not an advisor).
- `PUT /advisors/{user_id}` → whole object `{"status","status_from","status_until","max_load_override",
  "office_location","contact_note","bio"}`. Manage: everything. The advisor themself: only `office_location`,
  `contact_note`, `bio` (a change to another field → 403 `advising_forbidden`). Returns the item.
  `status` `left` / `leave` does NOT move students by itself; the app offers "Reassign their students".

### Conflicts of interest
- `GET /conflicts?advisor_user_id=&page=&size=` (manage) → items `{"id","advisor": {"user_id","name"},
  "student": {"member_id","user_id","name"},"reason": "relative"|"disciplinary"|"other","note","created_at",
  "assigned_now": bool}`.
- `POST /conflicts` (manage) `{"advisor_user_id","member_id","reason","note"}` → 201 item (`assigned_now` true when
  that advisor currently advises the student: the app then offers to reassign); 409 `advising_conflict_exists`.
- `DELETE /conflicts/{id}` (manage) → 204 (soft: `active=false`).

### Students and manual assignment
- `GET /students?q=&filter=all|unassigned|away|locked&dept_id=&program_id=&level=&cohort=&advisor_user_id=&page=&size=`
  (manage: whole org; an advisor: own advisees only via `student_scope`) → items
  `{"member_id","user_id","name","code": str|null,"program": str|null,"level": str|null,"cohort": str|null,
    "primary": {"user_id","name","away": bool,"locked": bool,"source","since"}|null,
    "others": [{"user_id","name","type": "co"|"support"}]}`; facets `{"unassigned","away","locked"}`.
- `PUT /students/{member_id}/advisors` (manage) whole object
  `{"primary": user_id|null,"locked": bool,"others": [{"user_id","type"}],"reason": str|null,
    "force_over_capacity": bool}` → item. `others` non-empty in single mode → 422 `advising_single_mode`; not
  eligible / away → 422 `advising_bad_advisor`; conflict → 409 `advising_conflict`; over max without force → 409
  `advising_over_capacity`. A changed primary ends the old row (history), writes a handover, notifies (student:
  "your advisor is now X"; new advisor: grouped notice).
- `GET /students/{member_id}/history` (manage, or the student's current advisor) → `{"items": [{"user_id","name",
  "type","status","source","locked","started_at","ended_at","end_reason","actor": str|null}]}` newest first.

### Distribution (one engine for distribute · rebalance · reassign)
- `POST /assign/preview` (manage) body
  `{"mode": "distribute"|"rebalance"|"reassign","strategy": null|"balanced"|"round_robin"|"department"|"continuity",
    "scope": {"dept_id","program_id","level","cohort"}|null,
    "from_advisor_user_id": int|null, "to_advisor_user_id": int|null, "member_ids": [int]|null}`
  - distribute: students without an active primary (in scope) get one.
  - rebalance: non-locked, non-manual assignments of over-capacity advisors move to advisors with room.
  - reassign: the `from` advisor's students (or `member_ids` of them) move to `to` (or by strategy when null).
  → `{"plan_hash","mode","strategy","counts": {"students","assign","move","unchanged","locked_kept",
      "skipped_conflict","skipped_capacity"},
      "advisors": [{"user_id","name","before","after","max","warn","over"}],
      "moves": [{"member_id","name","from": {"user_id","name"}|null,"to": {"user_id","name"}}],
      "moves_total", "warnings": [{"code","count"}]}` (`moves` = first 200). Pure: nothing written except the run row.
- `POST /assign/apply` (manage) `{"plan_hash","force_over_capacity": false,"reason": str|null}` → recomputes the
  plan; different hash → 409 `plan_stale`; the same hash applied before → 200 with the stored result (idempotent);
  else applies in ONE transaction (bulk insert, audit summary) →
  `{"run_id","assigned","moved","handovers","notified_students","notified_advisors"}`.
- `GET /assign/runs?page=&size=` (manage) → items `{"id","mode","strategy","status","counts","actor","created_at",
  "applied_at"}`.
- The registrar's `POST …/registrar/advisors/auto` keeps working as today (write-through).

### Handovers (#17)
- `GET /handovers?mine=1&pending=1&page=&size=` (manage: all; an advisor: theirs) → items `{"id","member_id",
  "student": str,"from": {"user_id","name"}|null,"to": {"user_id","name"},"reason",
  "summary": {"flags_open","plans_active","requests_open","notes","last_meetings": [{"at","mode"}]},
  "created_at","acknowledged_at"}` (summary from the casework tables; zeros until later phases fill them).
- `POST /handovers/{id}/ack` (the receiving advisor) → item.

### Status additions (Phase 2 `GET /status`)
`counts` gains `"away"` (students whose primary is away) and `"over"` (advisors over max); `me` gains
`"handovers_pending"`. Member `GET /public/{org}/advising/status` advisor items gain `"office_location"`,
`"contact_note"` (never e-mail or phone unless the advisor wrote them there).

## Automatic assignment of new students (#2.2)
- A job tick (existing APScheduler + `live_claims.claim` per org, every 10 minutes) for every org with advising on
  and `auto_assign` true: `distribute` for students without an active primary, by the effective policy per student
  scope. The join-approval path (student membership becomes active) runs the same for that one student right after
  commit (best effort; the tick is the safety net).
- Welcome (#2): the student gets "Your academic advisor is X" with office location / contact note (in-app + push
  through `notify_users`; e-mail too when the platform's existing e-mail helper is available — check
  `services/` for it and reuse; never a new provider). Each advisor gets ONE grouped notice per run ("N new
  students were assigned to you"). Dedupe key per (member, advisor) so a re-run never re-sends.

## Backend scope
1. The `import_legacy` change above (+ e2e check: a departed advisor's link is kept and counted away).
2. `assign_algo.py` (pure, no DB): inputs = students (member_id, current primary, locked, source, scope keys,
   previous advisors, conflicts), advisors (user_id, dept ids, load, max, away, eligible), mode, strategy, force →
   moves + counts + per-advisor before/after + warnings. Deterministic (stable ordering), so the plan hash is stable.
   Strategies: balanced (lowest load % first), round_robin (stable cycle, skip full), department (advisors of the
   student's department/program first, then balanced), continuity (a previous advisor with room first, then
   balanced). Unit tests `tests/org_v2/advising_algo_unit.py` (each strategy, capacity, conflicts, locks, away,
   determinism, 10 000 students under 1 s).
3. `assignments.py`: plan/apply (hash check, idempotent apply, bulk writes, handovers, notices), manual PUT, history.
   `profiles.py`, `conflicts.py`, `handovers.py`, policy routes on top of `policy.py`, the job + join hook.
   A new revision `0052_advising_assign` (down `0051`; written as 0051, renumbered at the merge because
   organizations took `0051_enrollment_history`) only if a column is missing (e.g. run `mode` / `result`);
   same RLS rules.
4. Routes in `org_advising_router.py` (or a second router file registered in `main.py`) exactly as above;
   `FLUTTER_API_CHANGES.md`; kill switch unchanged (`org.advising`); features guide entry updated (settings,
   distribution, handovers); help page `org.advising` sections updated in `data/help_seed.json` (and the 0050
   insert keeps reading it).
5. `tests/org_v2/e2e_advising_assign.py`: settings PUT / inheritance per scope; advisors list loads + facets; away
   advisors excluded; preview → apply → re-apply idempotent; data change → 409 `plan_stale`; capacity + force;
   conflicts block auto and manual; locked / manual never moved; continuity across a new term; rebalance; reassign
   with handovers; new-student tick + join hook + welcome notices deduped; advisor sees only own students / handovers;
   student 403 everywhere; org B admin 403 on org A; single vs multi mode. Rerun `e2e_advising_foundation`,
   `e2e_registrar`, `e2e_gov_requests`, `e2e_org_v2`, `spec_help`, the migration round trip (SQLite + nb-pg db
   `adv_mig`, recreate it) if a revision was added.

## App scope (`lib/features/org/advising/`)
1. `adv_models.dart` gains the models above (tolerant of missing keys); `adv_api.dart` the calls.
2. `adv_config_page.dart`: Settings — the org's settings (eligible roles + ranks as chips, single / multi, max load,
   warn %, strategy, auto-assign switch) with "inherited from …" hints, and scope overrides (add / edit / remove);
   whole-object PUT; leave-page guard for unsaved changes.
3. `adv_advisors_page.dart`: advisors with load bars (warn / over colours from tokens), status chips, facet filter,
   search; edit sheet (status + dates, max override, office, contact note, bio); "Reassign their students" →
   distribution preview in reassign mode. An advisor opening it sees only their own profile card (edit contact).
4. `adv_distribute_page.dart`: mode + strategy + scope → preview (per-advisor before → after bars, counts, warnings,
   first moves) → Apply (`appConfirm`; `plan_stale` → "Data changed, preview again"); run history.
5. `adv_students_page.dart`: students with filters (unassigned / away / locked) and search; edit sheet (primary,
   others in multi mode, lock, reason, force with reason when over capacity) and history; conflicts managed from the
   student sheet and the advisor sheet (add / remove).
6. `adv_handovers_page.dart`: handovers with their summary, Acknowledge.
7. The setup page's "on" state links to these (manage: Settings · Advisors · Distribute · Students; advisor: My
   profile · Handovers with the pending count). Error codes in `adv_texts.dart`.
8. Tests: `test/org/adv_assign_models_test.dart`, `test/ui/adv_assign_layout_test.dart` (every new presentational
   view, all states, ar / en); analyze + `test/org/` + `test/ui/` with `-j 2`.
