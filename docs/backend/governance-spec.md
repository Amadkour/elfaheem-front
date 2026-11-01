# Governance: requests · complaints · forms · routing · delegation · councils · Export Hub

Spec of the "university requests, councils and export hub" system (2026-10-27). This is the contract every piece is
built against: backend `../back` (`data/governance_models.py`, `services/organization/governance/`,
`routers/organization/org_governance_router.py`, `org_council_router.py`, migration `0016_governance`), app
`lib/features/org/governance/` and `lib/design/export_hub/`. Decisions: D-057 (app repo), D-057 (backend).

## 0. Decisions (extend, don't rebuild)

| Spec concept | Built on | Why |
|---|---|---|
| Entity (service dept · scientific dept · council · office · custom) | `OrgDepartment` + new `kind`, `program_id`, `council_id` columns | departments already have members, heads (`OrgDeptMember.is_head`), per-department RBAC, dashboards, directory, join policies |
| Admin organization | the organization's `org_admin` (and platform admins) | already the top-level administrator |
| Heads / owners | `OrgDeptMember.is_head` (one head; co-owners = delegates with `mode: global`) | the existing team tab manages it |
| Council members | `OrgDeptMember` rows of the council entity (`kind: council`) | the team tab, titles, no second membership model |
| Roles & permissions | `org_catalog.MODULES` gains `workflow`, `councils`, `export_templates` + object-level rules in `governance/access.py` | checked on the server by `ctx.require` / `access.*`, drawn in the app from the catalog |
| Unified Item | new `org_work_items` (+ routes · events · delegations · categories · saved filters) | one list / filter / export / notification path; legacy complaints and form responses are mirrored into it (`complaint_id` / `form_response_id`) |
| Forms | existing `OrgForm` builder + new `org_form_assignments` (who must answer, reminders) | the form builder exists |
| Notifications | `org_service.notify_users` (+ `Notification`, inbox, pushes) with new `related_type`s and deep links | the notification center exists |
| Export Hub | the complaints report designer (`org_reports/report_model.dart` + `report_render.dart`) generalised into `lib/design/export_hub/` (pure design model + PDF / DOCX / XLSX writers), templates in `org_export_templates` | the app already renders Word / PDF / Excel by hand (no `excel` package, D-003); the server lists data + stores designs (same split as reports) |
| Background exports | the app fetches every page of the dataset (`export: true` → no page limit, server caps at 5 000 rows per call and pages) | consistent with the existing reports design; no file store needed |

Soft delete: `org_work_items.deleted_at`. Optimistic locking: `org_work_items.version`, `org_council_sessions.version`.
Timestamps: naive UTC like every org table. Audit: every mutation calls `audit(...)` AND writes an `org_work_events`
row (the item timeline).

## 1. Data model (`data/governance_models.py`, migration 0016)

New columns on `org_departments`:
- `kind` VARCHAR(16) NOT NULL DEFAULT 'service' — `service | scientific | council | office | custom`.
- `program_id` INTEGER NULL — the academic department (`org_programs.id`) a scientific entity stands for.
- `council_id` INTEGER NULL (FK `org_departments.id`, SET NULL) — the council entity of a scientific department.

Tables (all `org_id` FK organizations CASCADE, `created_at` / `updated_at` where noted):

- **org_work_categories**: `dept_id` (CASCADE), `key` (≤40, unique per dept), `name_ar`, `name_en`, `kind` (`complaint | request | other`), `description`, `form_id` (NULL; a request category backed by a form), `is_active`, `order`, `created_by`.
- **org_work_items**: `ref` ("W-2026-000123", unique), `type` (`complaint | request | form | memo | agenda | custom`), `category_id` (SET NULL), `title` (≤255), `body` TEXT, `payload` JSON (form answers, extra fields), `source_dept_id` (SET NULL; the entity it came from, NULL = a person), `source_user_id` (SET NULL; the submitter), `is_anonymous`, `owner_dept_id` (SET NULL; the entity it currently sits with), `assignee_user_id` (SET NULL), `status` (`draft | open | in_review | pending_approval | in_council | approved | rejected | postponed | closed | withdrawn`), `priority` (`low | medium | high | urgent`), `due_at`, `decision` JSON (`{outcome, by, at, note, via: "head|delegate|council", session_id?}`), `decided_at`, `decided_by` (SET NULL), `vote_outcome` (`approved | rejected | tied | no_quorum | postponed`, NULL; cached from the last council), `attachments` JSON `[{name,url,type,size}]`, `tags` JSON, `complaint_id` (SET NULL, unique), `form_response_id` (SET NULL, unique), `version` INT default 0, `deleted_at`, `created_by`, timestamps. Indexes: `(org_id, owner_dept_id, status)`, `(org_id, source_user_id)`, `(org_id, assignee_user_id)`, `(org_id, type, status)`.
- **org_work_routes**: `item_id` (CASCADE), `parent_route_id` (SET NULL; the chain), `from_dept_id`, `from_user_id`, `to_dept_id`, `to_user_id` (exactly one of the two `to_*`), `action` (`info | review | approval | vote`), `note`, `due_at`, `status` (`pending | answered | closed | superseded`), `answer` (`noted | reviewed | approved | rejected | voted`), `answered_by`, `answered_at`, `answer_note`, `session_id` (SET NULL; the council session that handled a `vote` route), `created_by`, `created_at`. Index `(to_dept_id, status)`, `(to_user_id, status)`, `(item_id)`.
- **org_work_events**: `item_id` (CASCADE), `kind` (`created | updated | routed | forwarded | escalated | assigned | decided | locked_out | status | comment | attachment | agenda | vote_opened | vote_closed | voted | exported | delegation | reminder | withdrawn | reopened`), `actor_id`, `body` TEXT (comments), `internal` BOOL (staff-only comment), `data` JSON, `created_at`. Index `(item_id, created_at)`.
- **org_work_delegations**: `dept_id` (CASCADE), `from_user_id`, `to_user_id`, `mode` (`global | scoped`), `scope` JSON `{types: [], category_ids: [], form_ids: [], council: bool}` (scoped only; empty lists = no restriction on that axis), `starts_at`, `ends_at` (NULL = open), `revoked_at`, `revoked_by`, `note`, `created_at`. Index `(dept_id, to_user_id)`.
- **org_work_saved_filters**: `user_id` (CASCADE), `name`, `scope` (a list id such as `items` · `council` · `my`), `query` JSON, `created_at`. Unique `(org_id, user_id, scope, name)`.
- **org_form_assignments**: `form_id` (CASCADE), `user_id` (CASCADE), `assigned_by`, `due_at`, `status` (`pending | submitted | waived`), `response_id` (SET NULL), `reminded_at`, `remind_count`, `created_at`. Unique `(form_id, user_id)`.
- **org_councils**: `dept_id` (CASCADE, unique; the council entity), `level` (`department | faculty`), `chair_user_id` (NULL = the entity head), `session_day` INT 1..28 (day of month, NULL = none scheduled), `session_time` "HH:MM" (default "10:00"), `cutoff_days` INT (default 2), `voting_deadline_hours` INT (default 72), `quorum_pct` INT (default 50), `tie_rule` (`reject | chair | postpone`, default reject), `abstain_counts` BOOL (default false), `no_vote_rule` (`ignore | abstain`, default ignore), `holidays` JSON `["2026-11-05", …]`, `holiday_rule` (`next_day | next_week`, default next_day), `auto_agenda` BOOL (default true: the regular session is created and its agenda compiled by the tick), `auto_agenda_rules` JSON `{types: [], category_ids: []}` (the head's pre-processing: items of these kinds arriving at the parent scientific department are routed to the council for voting automatically), `timezone` (NULL = org), `created_at`, `updated_at`.
- **org_council_sessions**: `council_id` (CASCADE), `kind` (`regular | extraordinary`), `title`, `scheduled_at` (UTC), `status` (`draft | published | voting | closed | cancelled`), `published_at`, `voting_opens_at`, `voting_closes_at`, `closed_at`, `eligible_count` INT, `minutes` JSON (`{generated_at, summary, items: [...]}` built at close), `notes` TEXT, `version` INT, `created_by`, timestamps. Index `(council_id, scheduled_at)`.
- **org_council_agenda_items**: `session_id` (CASCADE), `item_id` (CASCADE), `route_id` (SET NULL), `order` INT, `status` (`pending | voting | approved | rejected | tied | no_quorum | postponed | withdrawn`), `approve_count`, `reject_count`, `abstain_count`, `eligible_count`, `approve_pct` FLOAT, `decided_at`, `note`, `escalated_item_id` (SET NULL), `created_at`. Unique `(session_id, item_id)`.
- **org_council_votes**: `agenda_item_id` (CASCADE), `user_id` (CASCADE), `vote` (`approve | reject | abstain`), `note`, `created_at`, `updated_at`. Unique `(agenda_item_id, user_id)`.
- **org_export_templates**: `dept_id` (CASCADE, NULL = organization-wide), `module` (≤40: `items | complaints | requests | council | minutes | grades | table | *`), `lang` (`ar | en`), `name`, `design` JSON (the `ExportDesign` document, §6), `is_default` BOOL, `shared` BOOL (visible to every entity of the organization), `created_by`, timestamps. Index `(org_id, module, lang)`.

`ensure_governance_tables(bind)` (same pattern as `ensure_calendar_tables`) is called from `ensure_org_tables` so the
e2e harness has the schema; migration `0016_governance.py` creates the same with the idempotent helpers.

## 2. Permissions (`org_catalog.py` + `governance/access.py`)

New modules (scope `dept`, group `services`):
- `workflow` — `view insert update delete approve export` ("الطلبات والمعاملات", "Requests & workflow").
- `councils` — `view insert update approve export` ("المجالس والتصويت", "Councils & voting"); `export` = may export vote results.
- `export_templates` — `view insert update delete` ("قوالب التصدير", "Export templates").

System roles: `dept_head` gets everything of the three; `dept_staff` gets `workflow: view insert update export`,
`councils: view`, `export_templates: view insert update`; `viewer` and `admin_assistant` get `view`.
`ensure_system_roles` backfills a system role that lacks a module KEY entirely with that role's default actions for it
(a key an admin emptied on purpose is kept empty).

Object-level rules (`access.py`, every one checked on the server):
- `is_head(db, dept, user)` — `OrgDeptMember.is_head`. `is_member(db, dept, user)` — any team row.
- `active_delegations(db, dept_id, user_id, now)` — rows with `revoked_at IS NULL`, `starts_at <= now` (or NULL) and
  `ends_at > now` (or NULL). `delegation_covers(d, item)` — global, or scoped with every non-empty axis matching
  (`item.type ∈ types`, `item.category_id ∈ category_ids`, `payload.form_id ∈ form_ids`; `council` governs vote
  management).
- `can_decide(db, ctx, item)` — org admin · head of `item.owner_dept_id` · a covering delegate · a `workflow.approve`
  grant on that department (an org-level right, never the default staff role).
- `deciders(db, dept, item)` — head + covering delegates + org admins (who gets the "someone decided" notice).
- `can_view(db, ctx, item)` — `can_decide` · `workflow.view` on `owner_dept_id` or on any dept in its route chain ·
  member of such a dept · the submitter · a person it was routed to · a council member whose agenda holds it.
- `can_route(db, ctx, item)` — `can_decide` · `workflow.update` on the owner dept · the current assignee.
- `can_vote(db, user, session)` — team member of the council entity (not necessarily head) and the session is `voting`.
- `can_manage_council(db, ctx, council)` — org admin · head of the council entity · head of the parent scientific
  department (`OrgDepartment.council_id == council.dept_id`) · delegate with `scope.council` · `councils.update` grant.
- Export: `workflow.export` on the dept for items; `councils.export` for vote results (`include_votes`); otherwise
  the dataset is returned without the vote columns / blocks.
- Routing rules: `Organization.settings["governance"]["routing"]` = `{"mode": "open" | "rules", "rules": [{"from_kind": "service", "to_kind": "council", "allow": true}, …]}`. Default `open` (anything to anything inside the organization). With `rules`, a route whose `(from_kind, to_kind)` pair has no `allow: true` entry answers 422 `route_not_allowed`.

Error codes (all `{"code", "message"}`): `entity_not_found`, `entity_kind_invalid`, `category_not_found`,
`item_not_found`, `item_forbidden`, `already_decided` (409), `stale_version` (409), `item_closed` (409),
`route_target_required` (422), `route_not_allowed` (422), `route_self` (422), `not_a_decider` (403),
`delegation_invalid` (422: self, not a member, dates reversed), `delegation_not_found`, `council_not_found`,
`session_not_found`, `session_state` (409: the action does not fit the session's status), `not_a_voter` (403),
`voting_closed` (409), `quorum_not_met` (informational in results), `no_faculty_council` (422), `form_not_found`,
`assignment_exists` (409), `filter_name_taken` (409), `template_not_found`, `export_forbidden` (403, vote results).

## 3. Business rules

**Item lifecycle.** `open` on creation (a complaint, a form response, a staff memo). `in_review` once assigned or
routed `review`. `pending_approval` when a route with `action: approval` is pending at the owner entity.
`in_council` while on a published / voting agenda. `approved | rejected` by the first decision (head, delegate or
council outcome). `postponed` when a council postpones it. `closed` by the owner entity after a decision (or
directly for `info` items); `withdrawn` by the submitter while nothing was decided. `reopen` → `open` (head/admin).

**Routing / forwarding.** `POST …/items/{id}/route` creates a route row, moves `owner_dept_id` to the target entity
when the action is `approval` or `vote` (a `review` / `info` route keeps the owner and just asks the target),
sets `assignee_user_id` when routed to a person, writes a `routed` event, notifies the target (entity → its head +
delegates + team; person → that person). A pending `approval` route at the same entity is superseded by the next
one. `escalate` = route `vote` to the faculty council (`level: faculty`) of the organization (422
`no_faculty_council` when none), from a head or the council chair, and marks the previous agenda item
`escalated_item_id` when done from a session.

**First decision closes.** `decide` runs `UPDATE org_work_items SET status=…, decision=…, version=version+1
WHERE id=:id AND status IN ('open','in_review','pending_approval') AND version=:version`; rowcount 0 → 409
`already_decided` (with the current decision) or `stale_version`. Then: the pending approval route is answered,
a `decided` event, a `locked_out` event per other decider, and notifications: to the other deciders
("[Name] approved item X" — one notice per person, items grouped per minute by the tick when several), to the
submitter, to the source entity's head.

**Delegation.** `POST …/entities/{dept}/delegations` by the head (or admin): scoped (default) or global; dates
optional; `to_user_id` must be a live org member (any role), not the head. Revoke = `revoked_at`, logged. A delegate
also receives an `OrgUserGrant` `{workflow: [view]}` on the entity (`note: delegation:<id>`, `expires_at = ends_at`,
deleted on revoke) so a plain member can reach the staff routes; a delegation that is dated but not yet active lets
the person look and answers 403 `not_a_decider` on decide.
`GET /me/delegations` lists what is delegated TO me (drives the "acting for" banner).

**Forms.** `POST …/forms/{fid}/assign {user_ids?, dept_ids?, roles?, due_at?}` snapshots the audience into
`org_form_assignments` (pending), notifies each person, sets `OrgForm.mandatory` when `must: true`. A submission
marks the assignment `submitted` (+ `response_id`) and creates the work item (`type: form`, title = form title,
payload `{form_id, answers}`, owner = the form's department). `POST …/forms/{fid}/remind` notifies every pending
assignee (and the tick reminds 24 h before `due_at` and daily after it, max 5). `GET …/forms/{fid}/assignments` →
`{submitted: [...], pending: [...], waived: [...]}`.

**Legacy mirrors.** `file_complaint` and `answer_form` call `governance.items.mirror_complaint(db, c)` /
`mirror_form_response(db, r)` (no commit; idempotent on `complaint_id` / `form_response_id`). The item list
backfills missing mirrors for the organization once per call (cheap query on `complaint_id IS NULL`).
A legacy status change (`PUT /complaints/{cid}` resolved/closed, `PUT /form-responses/{rid}` approved/rejected)
is reflected onto the item (`sync_from_complaint` / `sync_from_response`), and a decision on the item is written
back to the legacy row (status + reviewer note) so both screens agree.

**Councils.**
- Creating a scientific entity (`kind: scientific`) auto-creates its council entity (`kind: council`,
  `parent_id` = the department, name "مجلس قسم …" / "… Department Council", head = the department head) and an
  `org_councils` row (`level: department`). `POST …/councils {level: faculty}` creates the Faculty Council entity
  (one per organization; 409 `council_exists`).
- The tick (`governance/jobs.py`, hourly) for every council with `session_day`: computes the next regular session
  date in the council's timezone (org timezone by default); if it falls on a holiday → `holiday_rule`; ensures ONE
  `regular` session row for that month exists (`draft`, `scheduled_at`); at `scheduled_at - cutoff_days` the agenda
  is compiled: every item with a pending `vote` route to this council and no agenda item in an open session is added
  (`pending`), later arrivals wait for the next session (an admin may still add them by hand); at `scheduled_at`
  the session is `published` + agenda delivered to members (notification + inbox) and voting opens
  (`voting`, `voting_closes_at = scheduled_at + voting_deadline_hours`); at `voting_closes_at` the session closes
  (tally) unless already closed by the chair. `auto_agenda: false` → nothing automatic beyond the session row.
- Extraordinary sessions: `POST …/councils/{cid}/sessions {kind: extraordinary, scheduled_at, item_ids}`; same flow,
  manual publish / open / close allowed at any time by `can_manage_council`.
- Voting: `POST …/agenda/{aid}/vote {vote, note}` by council members while `status: voting`; a vote can be changed
  until the close; one row per person (upsert). Results are visible live to managers and, after close, to every
  member and to the submitter (counts + percentage + outcome).
- **The submitter never votes on their own item.** `access.submitter_id(item)` = `source_user_id` else
  `created_by`; `POST …/agenda/{aid}/vote` by that person → 403 `own_item`; the row's `eligible_count` (fixed at
  open-voting, recomputed at close by `row_eligible`) is the council team minus the submitter when they sit on
  it; the row is left out of their `/me/votes` and of the `council_votes` attention count; `agenda_json` carries
  `excluded` (= the caller is that person) and `excluded_users` (managers / after close).
- Tally at close per agenda item: `eligible` = council team size at close (minus the submitter, above); `voted` = rows; quorum = `voted ≥
  ceil(eligible × quorum_pct / 100)` else `no_quorum` → item `postponed` (carried to the next regular session
  automatically). Denominator = approve + reject (+ abstain when `abstain_counts`; + non-voters as abstain when
  `no_vote_rule: abstain`). `approve_pct = approve / denominator × 100` (0 when the denominator is 0).
  approve > reject → `approved`; reject > approve → `rejected`; equal → `tie_rule`: `reject` → rejected,
  `chair` → the chair's vote decides (no chair vote → rejected), `postpone` → postponed. The work item gets
  `vote_outcome`, `decision {via: council, session_id}` and `status` approved / rejected / postponed through the
  same compare-and-set as `decide` (an item decided by a head meanwhile keeps its decision; the agenda row notes
  `decided_elsewhere`). Minutes JSON are generated (session, council, date, members present = voted, every item with
  its counts, outcome and decision text) and stored on the session; notifications go to members and submitters
  ("results published").
- Escalation: `POST …/agenda/{aid}/escalate` (chair / head / manager) creates a `vote` route to the faculty council
  and a new agenda entry there in the next open session (or none yet → the next compile picks it up); the item
  stays `in_council`.

**Notifications** (`governance/notify.py`, all through `notify_users`, `related_type` → deep link; lock-out notices ("[Name] approved item X") are GROUPED per recipient inside a `GOV_NOTICE_GROUP_SECONDS` window (default 60 s; 0 = at once, the e2e scripts set it) so a council close or a bulk decision sends one notice listing the items, with the tick as the safety net after a restart; the unified inbox `GET /me/inbox` carries one row per organization for items waiting for my decision and one for agenda items waiting for my vote):
`org_work_item` (new item received, forwarded to you, decision by someone else, comment mention, reminder, SLA
overdue, status change for the submitter), `org_delegation` (granted / revoked), `org_form_assignment` (assigned /
overdue), `org_council_session` (agenda published, voting opened, closing in 24 h, results published).
Push data: `{type, id, org_id, module: "org_work" | "org_council", dept_id?}`. Attention keys (`attention_service.ORG_KEYS`):
`work_pending` → ("org.services", "governance") items waiting for MY decision or routed to me;
`council_votes` → ("org.services", "votes") open agenda items I have not voted on.

**SLA.** `due_at` defaults from priority (urgent 24 h · high 48 h · medium 72 h · low 120 h) on open items without
one; the tick notifies the owner entity's head once when an item passes `due_at` (`reminder` event, `data.sla`).

## 4. API — staff (`/api/v1/org/orgs/{org_id}/governance`, `Depends(org_ctx())`)

Common list reply: `{items: [...], total, page, size, pages, facets: {status: {open: n, …}, type: {…}}}`.
Item JSON (`item_json(db, it, *, full=False)`):
```json
{"id": 1, "ref": "W-2026-000001", "type": "complaint", "title": "…", "body": "…", "status": "open", "priority": "medium",
 "category": {"id": 3, "key": "complaints", "name_ar": "…", "name_en": "…", "kind": "complaint"},
 "source": {"dept": {"id": 2, "name_ar": "…", "name_en": "…", "kind": "service"}, "user": {"id": 9, "name": "…"} | null, "anonymous": false},
 "owner_dept": {"id": 5, "name_ar": "…", "name_en": "…", "kind": "scientific"}, "assignee": {"id": 7, "name": "…"} | null,
 "due_at": "…", "decided_at": null, "decision": null, "vote_outcome": null, "attachments": [], "tags": [],
 "version": 0, "created_at": "…", "updated_at": "…", "overdue": false,
 "pending_route": {"id": 4, "action": "approval", "to_dept": {...} | null, "to_user": {...} | null, "created_at": "…"} | null,
 "can": {"view": true, "route": true, "decide": false, "comment": true, "edit": false, "delete": false, "withdraw": false, "export": true}}
```
`full: true` adds `payload`, `routes: [route_json…]` (chain order), `events: [event_json…]` (timeline, internal
comments only for staff who may view the owner dept), `agenda: [{session_id, council: {...}, status, counts…}]`,
`legacy: {complaint_id, form_response_id}`.
Route JSON: `{id, parent_route_id, from: {dept, user}, to: {dept, user}, action, note, due_at, status, answer,
answered_by: {...}, answered_at, answer_note, session_id, created_at, created_by: {...}}`.
Event JSON: `{id, kind, actor: {id, name} | null, body, internal, data, created_at}`.

Entities & categories:
- `GET /entities?kind=` → `{items: [entity_json…]}`: dept fields + `kind`, `program_id`, `council_id`, `head: {id, name} | null`, `members: n`, `counts: {open, pending_decision, overdue}` (for the caller's rights), `can: {manage, decide}`.
- `POST /entities` → wraps department creation (`DeptIn` + `kind`, `program_id`); scientific → council auto-created; reply `entity_json` (+ `council: entity_json`).
- `PATCH /entities/{dept_id}` → `kind`, `program_id` (+ DeptPatch fields via the existing route is fine; this one is for kind changes; changing to `scientific` creates the council).
- `GET /entities/{dept_id}/categories`, `POST` (head / `workflow.update`): `{key?, name_ar, name_en, kind, description?, form_id?, order?}`; `PUT /categories/{cid}`, `DELETE /categories/{cid}` (soft: `is_active=false`).
- `GET /settings` / `PUT /settings` (org admin) → `{routing: {...}, sla_hours: {...}, email: "fallback" | "always"}` (`email` = the optional e-mail channel: `fallback` e-mails only when no device received the push, `always` e-mails every governance notice too; `GovSettingsPage` in the app).

Items:
- `GET /items` query: `q, type (csv), status (csv), dept_id (owner), source_dept_id, source_user_id, assignee_id, category_id, outcome (vote_outcome csv), date_from, date_to, mine (bool: I submitted), to_me (bool: routed to me / waiting for my decision), overdue (bool), page, size (≤100; `export=true` → ≤5000), sort (`-created_at` default, `due_at`, `status`, `priority`)`.
- `POST /items` `{type, dept_id (owner), category_id?, title, body?, priority?, due_at?, source_dept_id?, attachments?, tags?, payload?, route?: {to_dept_id | to_user_id, action, note}}` → 201 item (staff memo or a request created on behalf of someone).
- `GET /items/{id}` (full) · `PATCH /items/{id}` `{title, body, category_id, priority, due_at, tags, attachments, version}` · `DELETE /items/{id}` (soft, head/admin).
- `POST /items/{id}/route` `{to_dept_id? | to_user_id?, action, note?, due_at?}` → item (full).
- `POST /items/{id}/escalate` `{note?}` → item.
- `POST /items/{id}/recall` `{note?}` → item: pulls an item back from the council it was sent to by mistake — the manager of the entity that sent it (or an admin), only while the vote route is pending and no agenda row of it is voting or decided (409 `nothing_to_recall` / `recall_blocked`); the route is superseded, the agenda rows removed, the item returns to its sender as `open` and the council members are told.
- `POST /items/{id}/decide` `{outcome: "approved" | "rejected", note?, version}` → item; 409 `already_decided {decision}`.
- `POST /items/{id}/routes/{rid}/answer` `{answer: "noted" | "reviewed" | "approved" | "rejected", note?}` (the person / entity the route went to) → item.
- `POST /items/{id}/assign` `{user_id | null}` · `POST /items/{id}/status` `{status: "closed" | "reopened" | "postponed" | "in_review", note?}` · `POST /items/{id}/comments` `{body, internal?, attachments?}` → event.
- `POST /items/bulk` `{ids: [], op: "route" | "close" | "assign" | "agenda", route?: {...}, user_id?, session_id?}` → `{done: n, failed: [{id, code}]}`.
- `GET /dashboard?dept_id=` → `{pending: n, pending_decision: n, overdue: n, decided_30d: n, by_status: {}, by_type: {}, sla: {on_time_pct}}`.
- `GET /saved-filters?scope=` · `POST /saved-filters {name, scope, query}` · `DELETE /saved-filters/{id}`.

Delegation:
- `GET /entities/{dept_id}/delegations?active=` → `{items: [{id, from: {...}, to: {...}, mode, scope, starts_at, ends_at, revoked_at, active, note, created_at}]}`.
- `POST /entities/{dept_id}/delegations` `{to_user_id, mode, scope?, starts_at?, ends_at?, note?}` → 201.
- `DELETE /delegations/{id}` → revoke.
- `GET /me/delegations` → what is delegated to the caller in this organization.

Forms (on top of the existing `/forms` routes):
- `POST /forms/{fid}/assign` `{user_ids?, dept_ids?, roles?, due_at?, must?}` → `{assigned: n}`.
- `GET /forms/{fid}/assignments` → `{submitted: [...], pending: [...], waived: [...], due_at}`.
- `POST /forms/{fid}/remind` → `{reminded: n}` · `POST /forms/{fid}/assignments/{uid}/waive`.

Export Hub (data + templates):
- `GET /export/data?module=items|complaints|requests|council|minutes&…(the item filters)…&session_id=&include_votes=&include_decisions=&include_notes=&include_audit=&lang=` →
  `{module, title, generated_at, lang, meta: {org, dept, period, count, …}, columns: [{id, label_ar, label_en, type}], rows: [{…}], items?: [ {item, votes?: {approve, reject, abstain, eligible, approve_pct, outcome}, decision?, notes?, audit?: [...] } ]}`.
  `include_votes` without `councils.export` → 403 `export_forbidden`.
- `GET /export/templates?module=&lang=&dept_id=` → `{items: [template_json…]}` (own dept + shared + org-wide); `POST`, `PUT /{id}`, `DELETE /{id}`, `POST /{id}/default`, `POST /{id}/share {shared}`.
  Template JSON: `{id, dept_id, module, lang, name, design, is_default, shared, created_by, updated_at}`.

## 5. API — councils (`/api/v1/org/orgs/{org_id}/governance`, same router prefix, `org_council_router.py`)

- `GET /councils` → `{items: [council_json…]}`: `{id, dept: entity_json, level, chair: {...}, members: n, session_day, session_time, next_session: {id, scheduled_at, status} | null, settings: {...}, can: {manage, vote}}`.
- `POST /councils` `{level: "faculty", name_ar?, name_en?, head_user_id?}` → 201 (faculty council entity + council).
- `GET /councils/{cid}` · `PUT /councils/{cid}/settings` (whole object: `chair_user_id, session_day, session_time, cutoff_days, voting_deadline_hours, quorum_pct, tie_rule, abstain_counts, no_vote_rule, holidays, holiday_rule, auto_agenda, auto_agenda_rules, timezone`).
- `GET /councils/{cid}/sessions?status=` · `POST /councils/{cid}/sessions` `{kind, scheduled_at, title?, item_ids?}` → 201.
- `GET /sessions/{sid}` → `{id, council: {...}, kind, title, scheduled_at, status, published_at, voting_opens_at, voting_closes_at, closed_at, eligible_count, version, agenda: [agenda_json…], my_votes: {aid: vote}, results_visible: bool, minutes: {...} | null, can: {manage, vote, export_votes}}`.
  `agenda_json`: `{id, order, item: item_json, status, approve_count, reject_count, abstain_count, eligible_count, approve_pct, outcome: status, decided_at, note, my_vote, excluded: bool, excluded_users: [user] | null, votes: [{user, vote, note, at}] (managers, or after close)}`.
- `POST /sessions/{sid}/agenda` `{item_ids: []}` · `DELETE /sessions/{sid}/agenda/{aid}` · `POST /sessions/{sid}/agenda/{aid}/postpone` · `PUT /sessions/{sid}/agenda/order {ids: []}`.
- `POST /sessions/{sid}/publish` · `POST /sessions/{sid}/open-voting` · `POST /sessions/{sid}/close {version}` · `POST /sessions/{sid}/cancel {note}` · `PATCH /sessions/{sid}` `{scheduled_at, title, notes, version}`.
- `POST /agenda/{aid}/vote` `{vote, note?}` → agenda_json · `POST /agenda/{aid}/escalate {note?}`.
- `GET /sessions/{sid}/minutes` → `{minutes, text_ar, text_en}` (generated at close; a draft preview for an open session).
- `GET /me/votes` → open agenda items waiting for my vote across the org.

## 6. API — members (`/api/v1/org/public/governance`, `get_current_user`, `_member_org`)

- `GET /{org_id}/entities` → entities that accept items from members (`kind != council`), each with `categories` (active, with `form_id`), `accepts_complaints`, `accepts_requests` and `can_submit_to_council` (a scientific department whose team — or whose council — the member sits on).
- `POST /{org_id}/items` `{dept_id, category_id?, type: "complaint" | "request", title, body, priority?, is_anonymous?, attachments?, payload?, to_council?}` → 201 `{id, ref, status, message}`; a `complaint` ALSO creates the legacy `OrgComplaint` (so the existing complaint thread keeps working) and mirrors it. `to_council: true` (requests only, 422 `council_requests_only`; 422 `no_council`; 403 unless the member is on the department's or the council's team) creates the item at the department and at once a `vote` route to its Department Council (`routing.submit_to_council`, no routing rules apply to a department's own council): status `in_council`, on the next compiled agenda, and the submitter is excluded from the vote on it (§3).
- `GET /me/items?org_id=&status=&page=` → items I submitted or that were routed to me personally (same item JSON; `can` reflects the member view).
- `GET /items/{id}` → full item for the submitter / recipient (internal comments hidden; votes only after close).
- `POST /items/{id}/comments {body}` · `POST /items/{id}/withdraw`.
- `GET /me/votes` · `POST /agenda/{aid}/vote` (council members use the app in member mode too).
- `GET /me/delegations`.
- `GET /me/assignments` → forms I must answer (pending assignments with due dates).
- **For someone else (D-140).** `POST /{org_id}/items` (and the staff `POST /items`) take `beneficiary: {kind: self |
  member | external, user_id?, name?, phone?, email?, national_id?, student_number?, relation?}`; the right is
  `workflow.on_behalf` (org admin · head of the entity · dept_head / dept_staff; never a plain member by default,
  not for the council path either), 403 `on_behalf_forbidden`, 422 `beneficiary_invalid {field}` /
  `beneficiary_not_member` / `beneficiary_anonymous`. `GET /{org_id}/people?q=&dept_id=` = the member picker (names
  only). Item JSON `beneficiary` (null = self) and `chain_step`; entities `can_submit_for_others` and `chain`.
- **Attachments (D-140).** `POST /{org_id}/attachments` (multipart `file`) → `{id, name, type, ext, size, kind: file,
  preview}` (415 `file_type` by the real type, 413 `file_too_big`); items / comments / resubmit send `[{id}]`;
  `GET /attachments/{id}?inline=` → a 10-minute link after the item's view check.
- **Approval chain (D-141).** Staff `GET|PUT /entities/{dept_id}/chain` (org admin writes); item JSON `chain`
  (`{round, current, steps: [{kind, status, by, at, note, via, label_*}], rounds}`); a rejection needs `note`
  (422 `reason_required`); `POST /items/{id}/resubmit {title?, body?, attachments?, note?}` by the submitter of a
  rejected item starts a new round. Export: `GET …/export/data?ids=1,2,3` (each id checked).

## 7. Export Hub — the design document (`lib/design/export_hub/export_design.dart`)

```json
{"version": 2, "page": {"size": "A4" | "Letter" | "A3", "orientation": "portrait" | "landscape",
                        "margins": {"top": 16, "right": 16, "bottom": 16, "left": 16}},
 "rtl": true, "font": {"family": "tajawal" | "bahij" | "plex", "size": 11, "color": "#1E293B", "line_spacing": 1.3},
 "header": {"text": "", "show_page_numbers": true, "show_date": true}, "footer": {"text": ""},
 "table": {"style": "grid" | "zebra" | "minimal", "header_color": "#0F766E", "header_text_color": "#FFFFFF",
           "font_size": 10, "columns": ["n", "ref", "title", "status"]},
 "votes": {"position": "beside" | "below" | "both", "show_counts": true, "show_percent": true, "show_outcome": true,
           "show_voters": false, "style": "bar" | "pill" | "text"},
 "blocks": [
   {"id": "b1", "kind": "logo", "x": 0.4, "y": 0, "w": 0.2, "h": 0.08, "url": "https://…", "align": "center"},
   {"id": "b2", "kind": "text", "x": 0, "y": .1, "w": 1, "h": .04, "text": "{{org}}", "font": {"family": "", "size": 14, "weight": "bold", "color": "#…"}, "align": "center"},
   {"id": "b3", "kind": "table", "x": 0, "y": .3, "w": 1, "h": .4},
   {"id": "b4", "kind": "items", "x": 0, "y": .3, "w": 1, "h": .4},
   {"id": "b5", "kind": "signature", "x": .66, "y": .8, "w": .3, "h": .12, "name": "{{signer}}", "title": "عميد الكلية", "url": "https://…", "align": "center"},
   {"id": "b6", "kind": "line", "x": 0, "y": .25, "w": 1, "h": .01, "color": "#…"}
 ]}
```
Block kinds: `text`, `logo` (many), `signature` (many: name, title, optional image), `table` (one: the dataset rows
with `table.columns`), `items` (one: the council / agenda layout — every item printed as a card with the vote
result per `votes`), `line`. Positions are fractions of the content box as in the report designer; `table` /
`items` split the page into "before" and "after" flows so long content spans pages. Placeholders: `{{org}}`,
`{{dept}}`, `{{title}}`, `{{period}}`, `{{date}}`, `{{count}}`, `{{signer}}`, `{{session}}`, `{{council}}`,
`{{session_date}}`, `{{page}}`, `{{pages}}` and `{{meta.<key>}}` from the dataset's `meta`.

Datasets (`ExportDataset`): `module`, `title`, `lang`, `meta` map, `columns` (id · label · type), `rows`, and for
council modules `items` (item + votes + decision + notes). `exportHub(context, dataset)` opens the hub sheet:
format (PDF / Word / Excel) · language (ar / en / both — "both" renders two files, each with its own template) ·
template picker (defaults per module + language, shared ones, "new design…") · content switches (vote results,
decisions, notes, audit trail; disabled when the dataset lacks them because the server refused) · column picker ·
live preview. Writers: `export_pdf.dart` (package:pdf, Tajawal / Bahij / IBM Plex Arabic bundled fonts),
`export_docx.dart`, `export_xlsx.dart` (hand-written OOXML over `archive`, like `report_render.dart`).
`AppTableExport` gains a "Design…" entry that converts the table into a dataset and opens the hub, so every
existing table export can be designed.

## 8. App file map (`lib/features/org/governance/`)

- `gov_models.dart` — pure: `WorkItem`, `WorkRoute`, `WorkEvent`, `Delegation`, `Entity`, `Category`, `Council`,
  `CouncilSession`, `AgendaItem`, `VoteTally` (+ the tally rules mirrored for previews), label maps (status / type /
  action / outcome), `govCodeText` (error codes → bilingual text; also registered in `orgErrorText`).
- `gov_api.dart` — `GovApi` over `ApiClient` (every route of §4–§6; `orgEndpointMissing` → "needs a server update").
- `gov_filter.dart` — THE shared filter: `ItemFilter` (query model ↔ query string), `ItemFilterBar` (search, chips,
  date range, pickers, vote outcome, "mine" / "to me" / "overdue"), saved filters (per user via the API), reusable
  by every list (`scope`).
- `gov_items_page.dart` — the unified list (tabs: All · Waiting for me · Mine · Overdue), bulk actions, export (hub).
- `gov_item_screen.dart` — the item: header, decision bar (Approve / Reject with first-decision lock-out), route /
  forward / escalate sheet (`gov_route_sheet.dart`), timeline, comments, attachments, agenda history.
- `gov_entities_page.dart` — entities (kinds, heads, councils, categories), `gov_delegations_page.dart`
  (scoped / global, dates, revoke, log), `gov_dashboard.dart` (pending / overdue / decided tiles per entity).
- `gov_forms_assign.dart` — assign a form to people / groups, pending vs submitted, remind.
- `gov_councils_page.dart`, `gov_council_settings.dart`, `gov_session_screen.dart` (agenda, voting, live results,
  close, minutes, escalate), `gov_my_votes.dart`.
- `gov_member_pages.dart` — member side: submit to an entity, my items, my votes, my assignments.
- Wiring: org dashboard section "Governance" (`governance` · `councils` · `entities` · `delegations`), department
  dashboard tabs (Complaints · Requests · Council), member dashboard entries, `AppNavigator` modules `org_work` /
  `org_council`, `AttentionTabs`, `orgErrorText`, `../back/data/app_features_guide.json`.

Tests: `test/org/gov_models_test.dart` (tally rules, filter ↔ query, code texts, delegation scope matching),
`test/ui/gov_layout_test.dart` (harness over every presentational widget), `test/export/export_hub_test.dart`
(design ↔ JSON, writers produce valid zips / PDF bytes, both languages, vote layouts), backend
`tests/org_v2/e2e_governance.py` (entities · categories · items · routing · delegation · first decision · forms
assignment · export data · saved filters) and `e2e_councils.py` (sessions · agenda compile by the tick · voting ·
quorum / tie / abstain rules · close · minutes · escalation).
