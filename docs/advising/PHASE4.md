# Phase 4 — Advisor workspace: brief and contract

Read `PLAN.md` §3.2 (flags, notes, stats, categories), §3.8, §3.10 and `PHASE2.md` (the common rules apply unchanged:
own worktree only, `git commit --only`, never push or merge, `-j 2`, the Python venv, Arabic + English, no
placeholders, lead-owned files, report ≤ 15 lines). `PHASE3.md` "Shared rules" apply too (roles, list envelope, error
shape, audit + notices, every route: kill switch → eligibility → enabled, then the role). Brief requirements covered:
§2.3 (workspace, 360, categories and flags, notes), defaults #6 (priority + escalation for flags), #7 (alert
lifecycle), #8 (sensitive notes), #21 (risk-sorted list with reasons), #23 (offline drafts), #24 (accessibility).

## Who sees what (PLAN §3.8, decided here)
- **manage** (org admin / advising director): every student of the organization.
- **advisor**: only students they hold an ACTIVE assignment for (`access.student_scope`); any other member id → 404
  `advising_not_found` (never 403, so ids cannot be probed).
- **Students**: no route of this phase (403 `advising_forbidden`); their hub is Phase 5.
- **Sensitive** = a flag or note whose category is `sensitive`, or a note marked `sensitive`. Readable only by its
  author / owner, the student's PRIMARY advisor, and manage. Every read of sensitive content writes
  `access.log_sensitive_read` (one row per request, listing the ids, never the content). Others get no row, only a
  count: lists carry `"restricted": n`.
- **Note visibility**: `private` = the author only (manage sees the count, not the text) · `team` = the student's
  active advisors + manage · `student` = also the student (shown in the Phase 5 hub). A sensitive note can never be
  `student` (422 `advising_bad_visibility`).

## API (base `/api/v1/org/orgs/{org_id}/advising`)

### Workspace list
- `GET /workspace?q=&advisor_user_id=&cohort=&level=&program_id=&standing=&category_id=&priority=&flag=open|urgent|none&sort=risk|name|cgpa|contact&page=&size=`
  (advisor: own advisees, `advisor_user_id` ignored; manage: whole org, optional advisor filter) → items
  `{"member_id","user_id","name","code": str|null,"program": str|null,"level": str|null,"cohort": str|null,
    "standing": str|null,"cgpa": float|null,"last_term_gpa": float|null,"absence_max": float|null,
    "failed_count": int,"open_flags": {"low","normal","high","urgent"},"categories": [str],
    "risk_score": int,"risk_reasons": [{"code","value": float|int|null}],"last_contact_at": str|null,
    "primary": {"user_id","name"}|null}`;
  facets `{"open","urgent","no_contact_30d","total"}`. Default sort `risk` (score desc, then name). Reads
  `adv_student_stats` joined to members only (no per-row query). `categories` = keys of the student's open flags the
  caller may see.
- Risk score (#21): pure `score.py` (0–100, integers) from the stats row:
  grades 40 (CGPA < 2.0 → 25 scaled linearly from 2.0 to 1.0; last term GPA at least 0.30 below CGPA → 15) ·
  attendance 20 (absence_max ≥ 25 % → 20, ≥ 15 % → 10) · failed courses 15 (5 each) · open flags 15 (highest open
  priority: urgent 15, high 10, normal 5, low 2) · contact 10 (never or > 30 days → 10, 14–30 days → 5).
  Reasons = the non-zero parts as codes `cgpa_low` · `gpa_drop` · `absence_high` · `failed_courses` · `open_flags` ·
  `no_contact` with their value; the app writes the sentence. Phase 6 adds the rule engine on top; the weights stay
  in `score.py` constants.
- Stats (`stats.py`): `refresh(db, org, member_ids)` recomputes rows in bulk (one query per source per batch, never
  per student): cgpa / standing from `OrgStudentAcademic`, last term GPA + failed count + highest absence % from the
  registrar's own helpers (`services/organization/registrar*`, `P.term_gpa`; no second GPA formula), open flags by
  priority, last contact, then the score. Called after every flag / note write for that student, by the advising tick
  for missing rows and rows older than 6 h (≤ 5 000 per org per tick, claimed), and for one student when the 360
  opens and its row is older than 10 minutes.

### Student 360
- `GET /students/{member_id}/profile` →
  `{"student": {"member_id","user_id","name","code","program": {"id","name","name_en"}|null,"level","cohort",
    "standing","joined_at"},
    "advisors": [{"user_id","name","type","since","locked"}],
    "stats": {..the workspace item's numeric fields..,"risk_score","risk_reasons","meetings_term"},
    "academic": {..the registrar `record()` body..}|null,
    "gpa_trend": [{"term_id","label","term_gpa","cgpa"}],
    "counts": {"flags_open","notes","restricted","handovers"},
    "can": {"flag": bool,"note": bool,"assign": bool,"sensitive": bool}}`.
  `academic` reuses `record()` from `routers/organization/org_registrar_router.py` (move it into a service module the
  router and advising both import; the registrar routes keep the same answer); `null` when the student has no
  registrar record (organization not using the registrar). The legacy (non-credit) system: whatever `record()` /
  the registrar returns for it today, never a new calculation.

### Categories (admin-configurable, brief §2.3 + #24)
- `GET /categories` (any advising staff) → `{"items": [{"id","key","name_ar","name_en","sensitive","system","active",
  "accommodations": [{"key","label_ar","label_en"}]}]}`.
- `POST /categories` (manage) `{"name_ar","name_en","sensitive","accommodations"}` → 201 item (key generated);
  `PUT /categories/{id}` (manage) whole object `{"name_ar","name_en","sensitive","active","accommodations"}`;
  system categories: renamable, never deletable; `DELETE /categories/{id}` (manage) → soft delete, 409
  `advising_category_in_use` while open flags use it.
- Seed (existing orgs get it through the setup path / migration step): the `accessibility` category's recommended
  accommodations: extra exam time · accessible room · note-taker · recorded lectures · front seating · materials in an
  alternative format (ar + en).

### Flags (#6, #7, #24)
- `GET /students/{member_id}/flags?status=open|closed|all` → items `{"id","category": {"id","key","name_ar","name_en",
  "sensitive"},"priority","status","source","note","outcome_note","review_due_at","owner": {"user_id","name"}|null,
  "accommodations": [str],"created_by": {"user_id","name"}|null,"created_at","updated_at","resolved_at",
  "resolved_in_hours": int|null,"escalated_at": str|null,"overdue": bool}`, plus `"restricted": n`.
- `POST /students/{member_id}/flags` `{"category_id","priority","note","review_due_at","accommodations": [key]}` →
  201 item; `accommodations` only on a category that lists them (422 `advising_bad_accommodation`). Owner = caller.
  Urgent → the student's advisors AND the directors are notified at once (`notices.send`, deduped per flag).
- `PUT /flags/{id}` whole object `{"category_id","priority","note","review_due_at","accommodations"}` (owner or manage).
- `POST /flags/{id}/status` `{"status","outcome_note": str|null}`; pure state machine `flags_flow.py`:
  open → acknowledged | contacted | resolved | dismissed; acknowledged → contacted | resolved | dismissed;
  contacted → resolved | dismissed; resolved | dismissed → open (reopen; manage or owner). Anything else 409
  `advising_bad_transition`; `resolved` without an outcome note 422 `advising_outcome_required`. `contacted` also sets
  the student's last contact.
- `GET /flags/{id}/history` → `{"items": [{"at","actor","action","before","after"}]}` from `OrgAuditLog` (entity
  `adv_flag`), newest first.
- Escalation (#6): the advising tick finds flags still `open` (not acknowledged) longer than the effective policy's
  `sla_hours[priority]`, sets `escalated_at` and notifies the directors once.
- `review_due_at` passed → `overdue` true (the tick sends the owner one reminder, deduped).

### Notes (#8, #23)
- `GET /students/{member_id}/notes?page=&size=` → items `{"id","author": {"user_id","name"},"visibility","sensitive",
  "category": {..}|null,"body","contact_mode": null|"in_person"|"phone"|"video"|"chat"|"email","contact_at",
  "created_at","edited_at","mine": bool}`, plus `"restricted": n`.
- `POST /students/{member_id}/notes` `{"body","visibility","sensitive","category_id","contact_mode","contact_at",
  "client_id": str|null}` → 201 item. `client_id` (the app's offline draft id, ≤ 40 chars) makes the call idempotent:
  the same (org, author, client_id) again → 200 with the existing note. `contact_mode` set = a logged contact (sets
  last contact). Body ≤ 10 000 chars, plain text (never rendered as HTML).
- `PUT /notes/{id}` whole object (author only; sets `edited_at`; audited before / after) ·
  `DELETE /notes/{id}` (author or manage; soft).
- Write budgets through `services/organization/throttle.py` (notes + flags: 60 writes / user / 10 min → 429
  `advising_rate_limited`).

### Timeline
- `GET /students/{member_id}/timeline?before=&size=` (cursor = ISO time) → `{"items": [{"at","kind","ref_id","actor",
  "data": {..}}], "next": str|null}`; kinds `assigned` · `unassigned` · `handover` · `flag_opened` · `flag_status` ·
  `note` · `contact`; only what the caller may see (sensitive and private rules above). The app writes each line from
  `kind` + `data`.

### Advisor entry (Phase 3 open item)
- `GET /api/v1/org/mine?members=1` items gain `"advising": {"role": "director"|"advisor","advisees": int}` when
  advising is ON in that organization and the user is a director or holds active assignments (ONE grouped query for
  all of the user's organizations; nothing added otherwise). `/status` `me` gains `"flags_urgent"` (urgent open flags
  of my students) and `"flags_overdue"`.

## Migration
`0053_advising_workspace` (down `0052`; the lead re-checks the number against organizations before merging):
`adv_notes.client_id` String(40) + unique (org_id, author_id, client_id), `adv_notes.contact_mode` String(10),
`adv_notes.contact_at` DateTime; `adv_flags.accommodations` JSON, `adv_flags.escalated_at` DateTime;
`adv_flag_categories.accommodations` JSON (+ the accessibility seed for organizations already enabled). Idempotent
DDL (`migrations/helpers.py`), same RLS (tables already covered).

## Backend scope
1. `score.py` (pure), `flags_flow.py` (pure), `stats.py`, `flags.py`, `notes.py`, `categories.py`, `timeline.py`,
   `profile.py` (360), routes in a new `routers/organization/org_advising_case_router.py` registered in `main.py`.
2. `record()` moved to a service (registrar answer unchanged — rerun `e2e_registrar`).
3. `/mine` addition (rerun `e2e_org_v2` and the dashboard tests that read `/mine`).
4. Tick additions (stats refresh, SLA escalation, review reminders) inside the existing advising job.
5. `text.py` codes ar + en; `FLUTTER_API_CHANGES.md`; features guide entry (workspace, 360, flags, notes); help page
   `org.advising` sections (workspace, flags, notes, privacy) in `data/help_seed.json` AND a migration-time insert
   for already-seeded databases (the 0050 pattern) only if the page body changes.
6. Tests: `tests/org_v2/advising_flow_unit.py` (every transition, the score parts and reasons, edge values) and
   `tests/org_v2/e2e_advising_casework.py`: advisor sees only own students (other ids 404); manage sees all;
   student 403; org B admin on org A 404/403; sensitive flag / note hidden from a co-advisor (`restricted` counted)
   and audited when the primary advisor reads it; private note hidden from manage; sensitive note cannot be
   student-visible; lifecycle incl. outcome required and reopen; urgent → advisor + director notices (deduped);
   SLA escalation once; idempotent `client_id`; accommodations validation; category CRUD + in-use 409; timeline
   visibility; workspace sort / filters / facets and the score order; stats refresh after writes; `/mine` advising key;
   rate limit. Rerun `e2e_advising_assign`, `e2e_advising_foundation`, `e2e_registrar`, `e2e_org_v2`, `spec_help`, the
   migration round trip (SQLite + nb-pg db `adv_mig`, recreate it).

## App scope (`lib/features/org/advising/`)
1. `adv_models.dart` / `adv_api.dart` / `adv_texts.dart` gain the above (tolerant of missing keys); every code and
   every risk-reason code has ar + en text; `countText` for counts.
2. `adv_workspace_page.dart`: my students, risk-sorted, debounced search, ONE filter control (sheet with cohort,
   level, standing, category, priority, flag), paging; each card shows the score as a calm meter with its top reason,
   open-flag priority pill, last contact. Manage gets an advisor filter. Empty / loading (skeleton) / error / offline.
3. `adv_student_page.dart` (360): header (name, program, level, advisors, score + reasons) and sections Overview ·
   Academic (GPA trend with `AppSparkline`/`AppBarChart`, per-term courses from `academic`) · Flags · Notes ·
   Timeline. Phone: tabs; desktop: two columns. Manage also gets "Change advisor" (opens the Phase 3 student sheet).
4. `adv_flags.dart`: flag cards, add / edit sheet (category, priority, note, review date, accommodations when the
   category has them), status sheet (the allowed next states only; outcome note required for resolve), history.
5. `adv_notes.dart`: composer (visibility chips, sensitive switch, category, "log as contact" with mode), list,
   edit / delete own. `adv_draft_store.dart` (#23): a draft is saved locally per (org, member) while typing; a note
   sent offline is queued with its `client_id` and posted on reconnect (reuse the app's existing reconnect hook in
   `topRouteObserver` / the offline sync pattern — never a second connectivity listener); the composer shows
   "Saved on this device · will send when online".
6. `adv_categories_page.dart`: categories (manage) with accommodations editor.
7. Entry: `adv_wiring.dart` shows Academic advising under Services also when the `/mine` item's `advising.advisees`
   > 0; the setup page "on" state gives an advisor My students · My profile · Handovers, and manage gets Workspace
   and Categories next to the Phase 3 links. The registrar's `OrgAdvisingScreen` keeps its current entry and is linked
   from the workspace as "Registration cases" (no duplicate screen).
8. Tests: `test/org/adv_case_models_test.dart`, `test/ui/adv_case_layout_test.dart` (every presentational view,
   all states, ar / en), a draft-store test (queue, idempotent retry, restore); analyze + `test/org/` + `test/ui/`
   with `-j 2`; `test/visual/adv_case_golden_test.dart` renders (git-ignored) looked at by you before reporting.
