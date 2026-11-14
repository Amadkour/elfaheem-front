# Phase 7 — Support requests, councils, referrals, support plans, accommodations: brief and contract

Read `PLAN.md` §3.2 (`adv_case_links`, `adv_plans`, `adv_plan_items`, `adv_templates`), §3.7, §3.8 and `PHASE2.md`
(common rules unchanged: own worktree only, `git commit --only`, never push or merge, `-j 2`, the Python venv, Arabic +
English, no placeholders, lead-owned files, report ≤ 15 lines). `PHASE3.md` "Shared rules" and `PHASE4.md` "Who sees
what" apply (manage = org admin / advising director; an advisor reaches only students with an ACTIVE assignment, any
other member id → 404 `advising_not_found`; list envelope `{items,total,page,size,pages}`; errors
`{"code","message","message_en"}`; every write audited; notices through `notices.send`; every route: kill switch →
eligibility → enabled, then the role). Brief requirements covered: support requests filed by the advisor for the
student, a configurable approval chain (advising director review → the student's department council → the faculty
council), stages visible to the student and the advisor, final decision → student + advisor + timeline, SLA reminders
and escalation, referrals to service departments with the outcome back to the advisor, support plans, accommodations;
defaults #6 (request priority + SLA), #12, #14, #24 as assigned to this phase in PLAN §4.

Branches / worktrees: backend `wt-back-adv-p7`, app `wt-front-adv-p7`, branch `feature/academic-advising-p7` (Phases 5
and 6 run in parallel elsewhere; the lead merges and rechains the migrations).

## Decisions (made here)
- **One workflow engine.** A submitted request or referral IS a governance `OrgWorkItem` (`type="request"`), the student
  its beneficiary (`OrgWorkBeneficiary` kind `member`), the advisor its submitter (`source_user_id`); councils, voting,
  CAS decisions, attachments and resubmit rounds are governance's. Advising keeps its own row (`adv_requests`: drafts,
  the "needs more info" loop, stage, SLA, outcome) and the `adv_case_links` row (kind `support_request` / `referral`,
  so the Phase 3 handover summary's `requests_open` counts them). The advisor files for the student through advising
  (advising's role check), not through governance's "create for others" right.
- **Drafts never reach governance**: a draft is only an `adv_requests` row (no work item), visible to its author only.
  Submitting creates the work item.
- **New governance chain step kind `student_department_council`** (label "مجلس قسم الطالب" / "Student's department
  council"): at chain start it resolves to the council of the beneficiary's (else the submitter's) department — the
  person's program (`OrgStudentAcademic.program_id`, else `OrgMember.program_id`) → the organization's active
  scientific department of that program → its `council_id`; the step stores that council entity as `dept_id`, is
  entered as a `vote` route (exactly like `council`) and is tallied by the council's close. Not resolvable (no program,
  no department, no council) → the step is `skipped` with note `no_department_council` and the chain moves on.
  Governance's own chain editor accepts the kind too (`PUT /governance/entities/{id}/chain`).
- **The advising chain** lives in the advising policy (`workflow_steps`, per scope like every setting, so a program can
  differ from the organization): values `director_review` · `student_department_council` · `faculty_council` ·
  `entity:<dept_id>` (e.g. a Student Affairs committee); default `["director_review", "student_department_council",
  "faculty_council"]`; 1–6 steps, `director_review` only first, no two identical steps in a row. At submit the
  student's effective chain is snapshotted onto the item (governance `chain`): `director_review` → governance
  `manager` (the item sits at the Advising department; advising directors decide through advising, the department
  head may also decide in governance — first decision wins), `entity:<id>` → `entity`, the councils as above. A
  `faculty_council` step in an organization without a faculty council (e.g. a department sub-org: councils are per
  organization) is skipped with note `no_faculty_council`. Items already submitted keep their snapshot.
- **Needs more info** only at the `director_review` step (a director returns it to the advisor with a note; the item
  stays `open` at the Advising department, the step's SLA clock pauses). At entity / council steps the deciders use
  governance's tools (comment, reject with a reason); after a rejection the advisor may resubmit (governance's new
  round from the first step).
- **Stages** (derived server-side, stored on the row for the outbox below):
  support `draft · submitted · needs_info · in_review · at_department_council · at_faculty_council · approved ·
  rejected · closed` (`submitted` = at `director_review`; `in_review` = at an `entity` step; a council postponement
  keeps the council stage with `postponed: true`); referral `draft · sent · in_progress · handled · declined · closed`.
  Outcome: support `approved · rejected · withdrawn · closed`; referral `handled` (the entity approved) · `declined`
  (rejected) · `withdrawn` · `closed` (the entity closed it without a decision). After a decision the advisor may
  close the case with a follow-up note → stage `closed`, `outcome` kept.
- **Outbox sync.** Decisions also happen outside advising (council close in the governance tick, the head in the
  governance UI), so `request_sync` compares each open request's derived stage with the stored one (compare-and-set
  on the row: only one writer wins) and on a change writes the timeline event, applies the outcome (accommodations)
  and sends the advising notices. It runs right after every advising mutation, on every advising read of the request
  / list page, and in the advising tick (10 min) for every open request. Governance's own "mine" notices
  (`notify.item_update` to submitter / beneficiary, the council-close "decision" notice to submitters) are skipped for
  items whose payload carries `advising` — the student and advisor hear it once, from advising, with the advising deep
  link; managers and council members keep governance's notices.
- **SLA (#6) is advising's, per step.** The work item's `due_at` is cleared (governance's single 72 h clock does not fit
  a monthly council). Window per step: `director_review` / `entity` / referrals → `request_sla_hours[priority]`
  (defaults urgent 24 · high 48 · normal 72 · low 120); council steps → `council_sla_days` (35); a pending info
  request → `info_sla_days` (5) for the advisor. Clock = step entered (`chain.steps[i].at`), or the info answer when
  later. Reminder once when ≤ min(24 h, window / 2) is left → the step's deciders (directors · the entity head · the
  council chair and the council entity head); overdue once → directors + the advisor (escalation, `escalated: true`);
  2 × window once → org admins. Dedupe keys per (request, round, step, kind).
- **Visibility.** A request / referral concerns the student, who is its governance beneficiary and therefore already
  sees the governance item: in advising the student always sees their submitted requests and referrals (never drafts)
  — title, type, body, stage history, step labels, outcome + note; never the info note, deciders' names, votes or
  internal comments. Staff: the student's active advisors + manage; a request whose category is `sensitive` follows
  Phase 4 (author, primary advisor, manage; others get `restricted: n`; reads audited).
- **Support types** are a server catalogue (no new table): `academic_load · course_withdrawal · exam_excuse ·
  study_postponement · program_transfer · readmission · accommodation · financial_support · other`, each with ar/en
  labels and a default category key (`accommodation` → `accessibility`, `financial_support` → `financial`, others →
  `academic`, `other` → none). Bodies may start from the seeded `adv_templates` rows of kind `support_request` (table
  of 0050, read here; Phase 5 adds their CRUD — the lead unifies at merge), placeholders filled by the app.
- **Referrals** go to an active `service` / `office` entity of the organization (never a council, a scientific
  department or the Advising department itself); presets `healthcare`, `student_activities`, `student_affairs` are
  offered first. No chain: one decision by the target entity (its head / delegates in governance, or a `close`).
- **Accommodations**: an approved `accommodation` request grants one `adv_accommodations` row per requested key
  (labels from the request's category, `source="request"`); manage may also grant / end directly. The student sees
  labels and dates, staff also the note. Ended automatically after `ends_on`.
- **Support plans** reuse `adv_plans` / `adv_plan_items` (0050) with a few columns. Owners: `student · advisor ·
  other` (+ `owner_note`, e.g. "Student Affairs office"). The student sees `student_visible` plans that are `active` or
  `completed` and may tick their own (`owner=student`) items done / open. Completing a plan needs an outcome note and
  records the measure's result from the stats row.
- **Notices** registered from the new modules into `notices.TEMPLATES` and error texts into `text.MSG` (no edit of the
  shared dicts' bodies: fewer merge conflicts).
- **Rate limit**: request / plan / accommodation writes spend the Phase 4 casework budget (`adv_write`, 60 / 10 min →
  429 `advising_rate_limited`).

## API (base `/api/v1/org/orgs/{org_id}/advising`, staff)

### Options and the chain (#12)
- `GET /request-options` (advisor · manage) → `{"support_types":[{"key","label_ar","label_en","category_key":str|null,
  "needs_accommodations":bool}],"referral_targets":[{"id","name","name_en","preset":str|null,"suggested":bool}],
  "categories":[{"id","key","name_ar","name_en","sensitive","accommodations":[{"key","label_ar","label_en"}]}],
  "templates":[{"id","name_ar","name_en","body_ar","body_en"}],"priorities":["low","normal","high","urgent"]}`.
- `GET /request-chain` (manage) → `{"org":{"steps":[Step],"inherited":bool},"defaults":[Step],
  "scopes":[{"policy_id","scope_type","scope_ref","label","label_en","steps":[Step]}],
  "options":{"kinds":[{"key","label_ar","label_en","needs_dept":bool}],"entities":[{"id","name","name_en","preset",
  "kind"}],"faculty_council":bool,"department_councils":int,"advising_dept":{"id","name","name_en"}|null}}`;
  `Step = {"kind":"director_review"|"student_department_council"|"faculty_council"|"entity","dept_id":int|null,
  "label_ar","label_en"}` (`scopes` = only the scope rows that set `workflow_steps`).
- `PUT /request-chain` (manage) `{"scope_type":"org"|"dept"|"program"|"level"|"cohort","scope_ref":str|null,
  "steps":[{"kind","dept_id"}]|null}` (null = remove the key: inherit) → the GET body. 422 `advising_chain_invalid`
  `{"index","reason": "empty"|"too_many"|"unknown_kind"|"director_first"|"duplicate"|"entity_invalid"|
  "no_faculty_council"}`; 422 `advising_bad_scope`. Stored in that scope's `adv_policies.settings.workflow_steps`
  (the Phase 3 `PUT /policy` also accepts the new string forms and checks the entity ids).
- `GET /request-chain/preview?member_id=` (advisor of the student · manage) → `{"steps":[{...Step,"resolved":bool,
  "reason":null|"no_department_council"|"no_faculty_council"|"target_missing"}],"advising_dept":{...}|null}`.

### Requests and referrals
`Request` (staff JSON):
`{"id","kind":"support"|"referral","member_id","student":{"member_id","user_id","name","code"},
  "support_type":str|null,"target_dept":{"id","name","name_en","preset"}|null,
  "category":{"id","key","name_ar","name_en","sensitive"}|null,"title","body","priority",
  "accommodations":[{"key","label_ar","label_en"}],"accommodation_until":"YYYY-MM-DD"|null,
  "attachments":[{"id","name","type","ext","size","preview"}],"template_id":int|null,"flag_id":int|null,
  "stage","stage_at","postponed":bool,"outcome":str|null,"outcome_note":str|null,"outcome_at":str|null,
  "info":{"requested_at","note","by":{"user_id","name"},"answered_at":str|null,"answer":str|null}|null,
  "step":{"index","count","kind","label_ar","label_en","due_at":str|null,"overdue":bool}|null,"escalated":bool,
  "work_item":{"id","ref","status","version"}|null,"created_by":{"user_id","name"},"created_at","submitted_at",
  "updated_at","closed_at","close_note","version",
  "can":{"edit","submit","delete","review","answer_info","resubmit","cancel","close"}}`.
Detail adds `"chain":{"round","current","steps":[{"kind","dept_id","label_ar","label_en","status":"waiting"|"current"|
"approved"|"rejected"|"skipped","at","by":{"user_id","name"}|null,"note","skip_reason":str|null}],"rounds":[...]}|null`,
`"history":[{"stage","at","label_ar","label_en"}]` (oldest first) and `"agenda":[{"council":{"dept_id","name",
"name_en","level"},"scheduled_at","status","approve_count","reject_count","abstain_count","eligible_count"}]`.

- `GET /requests?member_id=&kind=&stage=&queue=review|needs_info|overdue&mine=1&q=&page=&size=` (advisor: own
  advisees' submitted requests + own drafts; manage: all; `queue=review` = at `director_review` without a pending info
  request, manage only) → envelope + `"restricted": n` + `"facets":{"review","needs_info","overdue","open"}`.
- `POST /students/{member_id}/requests` (an active advisor of the student · manage) `{"kind","support_type",
  "target_dept_id","category_id","title" ≤ 200,"body" ≤ 10000,"priority","accommodations":[key],
  "accommodation_until","attachments":[{"id"}],"template_id","flag_id","client_id" ≤ 40,"submit":bool}` → 201 Request
  (a repeated `client_id` → 200 with the stored row; used for another student → 409 `advising_client_id_conflict`).
  Attachments are uploaded first through governance `POST /api/v1/org/public/governance/{org_id}/attachments`
  (≤ 10, real-type checked) and read through `GET /api/v1/org/public/governance/attachments/{aid}`.
- `GET /requests/{id}` · `PUT /requests/{id}` (author, draft only, whole object + `version`; 409 `advising_stale`) ·
  `DELETE /requests/{id}` (author, draft only) → 204.
- `POST /requests/{id}/submit` `{"version"}` (author, draft) → Request. Support: work item owned by the Advising
  department + chain snapshot; referral: owned by the target entity (its team notified by governance).
- `POST /requests/{id}/review` (manage, at `director_review`) `{"decision":"approve"|"reject"|"needs_info","note",
  "version": work_item.version}` → Request; reject / needs_info need a note ≥ 3 chars (422 `advising_note_required`);
  approve moves to the next step or is final; governance 409 `already_decided` / `stale_version` pass through.
- `POST /requests/{id}/info` (the submitting advisor, or manage) `{"answer","attachments"}` → Request (the answer
  becomes a governance comment, the attachments the item's).
- `POST /requests/{id}/resubmit` (the submitter, after `rejected`) `{"title","body","attachments","note"}` → Request.
- `POST /requests/{id}/cancel` (the submitter · manage, before a decision) `{"reason"}` → outcome `withdrawn`.
- `POST /requests/{id}/close` (the submitter · the primary advisor · manage, after a decision) `{"note"}` → `closed`.
- Errors: 409 `advising_request_not_draft`, `advising_request_closed`, `advising_request_stage` (+ `stage`),
  `advising_no_department` (no active Advising department), `advising_stale`; 422 `advising_bad_support_type`,
  `advising_bad_target`, `advising_bad_category`, `advising_accommodations_required`, `advising_bad_accommodation`,
  `advising_note_required`; governance `attachment_invalid` / `too_many_attachments` pass through.

### Support plans (#14)
`Plan`: `{"id","member_id","title","status":"draft"|"active"|"completed"|"cancelled","measure":{"kind":"term_gpa"|
"cgpa"|"absence_max"|"custom","target":float|null,"text":str|null}|null,"result":{"value":float|null,"met":bool|null,
"at"}|null,"follow_up_at","student_visible","flag_id","request_id","outcome_note","closed_at",
"created_by":{"user_id","name"},"created_at","updated_at","version","progress":{"done","total"},
"items":[{"id","goal","action","owner":"student"|"advisor"|"other","owner_note","due_at","status":"open"|"done"|
"dropped","done_at","note","order","overdue"}],"can":{"edit","status","delete"}}`.
- `GET /students/{member_id}/plans?status=` → `{"items":[Plan]}`.
- `POST /students/{member_id}/plans` `{"title","status":"draft"|"active","measure","follow_up_at","student_visible",
  "flag_id","request_id","items":[{"goal" ≤ 500,"action" ≤ 2000,"owner","owner_note" ≤ 120,"due_at"}] ≤ 30}` → 201.
- `PUT /plans/{id}` whole object + `version` (the student's active advisors · manage; items with `id` are kept, without
  are new, missing are removed) · `DELETE /plans/{id}` (draft only).
- `POST /plans/{id}/status` `{"status","outcome_note"}`: draft → active | cancelled; active → completed | cancelled;
  completed | cancelled → active (author · manage). Else 409 `advising_plan_transition`; completed without a note 422
  `advising_outcome_required`; 422 `advising_bad_measure`.
- `POST /plans/{id}/items/{item_id}/status` `{"status","note"}` → Plan.

### Accommodations (#24)
`Accommodation`: `{"id","member_id","student_name","key","label_ar","label_en","category":{..}|null,"status":"active"|
"ended","starts_on","ends_on","source":"request"|"manual","request_id","note","granted_by":{"user_id","name"},
"granted_at","ended_at","end_reason"}`.
- `GET /students/{member_id}/accommodations?status=` (the student's advisors · manage) → `{"items":[…]}`.
- `POST /students/{member_id}/accommodations` (manage) `{"category_id","keys":[…],"starts_on","ends_on","note"}` →
  `{"items":[…]}`; an active key again → 409 `advising_accommodation_active`.
- `POST /accommodations/{id}/end` (manage) `{"reason"}` → the row.
- `GET /accommodations?status=active&q=&program_id=&page=&size=` (manage) → envelope (exam / teaching follow-up).

### 360 and status
- `GET /students/{member_id}/support` → `{"requests":{"open","needs_info","total","latest":[Request ≤ 5]},
  "referrals":{"open","total","latest":[…≤ 5]},"plans":{"active":[Plan],"completed":int},
  "accommodations":[active Accommodation],"restricted":int,"can":{"request","refer","plan","accommodate"}}`.
- Timeline kinds (`GET /students/{mid}/timeline`): `request_submitted {request_id,kind,support_type,title,priority}` ·
  `request_stage {request_id,stage,label_ar,label_en}` · `request_decided {request_id,outcome}` · `request_closed
  {request_id,outcome}` · `referral_sent {request_id,target:{name,name_en}}` · `referral_outcome {request_id,outcome}`
  · `plan_created {plan_id,title}` · `plan_status {plan_id,from,to}` · `accommodation_granted {accommodation_id,key,
  label_ar,label_en}` · `accommodation_ended {…}`; sensitive ones only for viewers with sensitive access.
- `GET /status` `me` gains `requests_review` (manage), `requests_needs_info` (the caller's own), `requests_overdue`
  (manage).

## API (member base `/api/v1/org/public/{org_id}/advising`, the student — own membership only)
- `GET /support` → `{"requests":[StudentRequest ≤ 50, newest first, no drafts],"plans":[visible active + completed
  ≤ 20],"accommodations":[active, no note]}`; `StudentRequest = {"id","kind","support_type","target_dept":{"name",
  "name_en"}|null,"title","body","priority","stage","stage_at","postponed","outcome","outcome_note","outcome_at",
  "steps":[{"label_ar","label_en","status","at"}],"history":[{"stage","at"}],"accommodations":[…],"created_at",
  "submitted_at","advisor_name"}`.
- `GET /requests/{id}` → StudentRequest (another student's id → 404 `advising_not_found`).
- `POST /plans/{plan_id}/items/{item_id}/status` `{"status":"done"|"open"}` (an `owner=student` item of a visible
  active plan) → the plan.

## Notices, push data, deep links
Templates (Arabic title, Arabic then English body; never the request body or the category on a lock screen):
`request_for_student` (submitted on your behalf) · `request_to_review` (directors) · `request_needs_info` (advisor) ·
`request_info_answered` (directors) · `request_stage` (student + advisor: entered a council / review entity) ·
`request_decided` (student + advisor, outcome + note) · `request_due_soon` (step deciders) · `request_overdue`
(directors + advisor) · `request_overdue_admins` · `request_info_overdue` (advisor, then directors) ·
`referral_outcome` (advisor + student) · `plan_shared` (student, a visible plan becomes active) · `plan_follow_up`
(author) · `plan_item_due` (the owner: student / advisor) · `accommodation_granted` · `accommodation_ended` (student
+ advisors). Push data (`notices.send` extra, related_type `org_advising`): `kind` = `request` | `plan` |
`accommodation`, `request_id` | `plan_id` | `accommodation_id`, `member_id`, `audience` = `staff` | `student`.
App deep links: `org_adv_request` (staff → request page; student → student request page), `org_adv_plan`.

## Migration `0056_advising_requests` (revision "0056", down "0053"; the lead rechains)
New tables (module `data/advising_request_models.py`, RLS `tenant_isolation` like 0050, org_id-first indexes):
- `adv_requests`: org_id, member_id, kind, support_type, target_dept_id, category_id, title, body, priority,
  accommodations JSON, accommodation_until Date, attachments JSON, template_id, flag_id, work_item_id (unique, SET NULL),
  stage, stage_at, postponed, outcome, outcome_note, outcome_at, info_requested_at, info_note, info_by,
  info_answered_at, info_answer, escalation JSON (sent keys), closed_at, closed_by, close_note, client_id (+ unique
  org_id, created_by, client_id), version, created_by, created_at, updated_at, submitted_at, deleted_at.
- `adv_accommodations`: org_id, member_id, key, label_ar, label_en, category_id, status, starts_on, ends_on, source,
  request_id, note, granted_by, granted_at, ended_at, ended_by, end_reason; partial unique active (org_id, member_id,
  key).
- `adv_case_events`: org_id, member_id, entity (request · plan · accommodation), entity_id, kind, at, actor_id, data
  JSON, sensitive; index (org_id, member_id, at).
Columns: `adv_plans` flag_id, request_id, outcome_note, closed_at, result JSON, version; `adv_plan_items` owner_note,
note, done_by, created_at, updated_at. Help: `org.advising` gains sections `requests`, `plans` (0053 pattern).

## Backend files (`wt-back-adv-p7`)
New: `data/advising_request_models.py` (imported next to `advising_models` in `data/models.py`) ·
`services/organization/advising/request_flow.py` (pure: stages, SLA windows, step mapping, plan transitions, measure) ·
`request_chain.py` (policy steps, validation, resolution, preview) · `requests.py` · `request_sync.py` (outbox, SLA,
outcome effects, tick) · `plans.py` · `accommodations.py` · `case_events.py` · `request_texts.py` (codes + notice
templates) · router `routers/organization/org_advising_request_router.py` (staff + member). Small edits: `main.py`
(register) · governance `chain.py` (kind, resolution, `start(steps=…)`), `councils.py` (close treats the kind as a
council step; no submitter notice for advising items), `notify.py` (stakeholders; "mine" skipped for advising items),
`org_governance_router.py` (`ChainStepIn` literal) · advising `policy.py` (`workflow_steps` forms, `request_sla_hours`,
`council_sla_days`, `info_sla_days`), `policy_store.py` (entity check), `jobs.py` (`run_casework` runs the request tick),
`timeline.py` (kinds), `setup.py` (status counts) · `FLUTTER_API_CHANGES.md`, `data/app_features_guide.json` (entries
`org_advising_requests`, `org_advising_plans`), `data/help_seed.json`. Tests: `tests/org_v2/advising_request_unit.py`
(pure flow) and `tests/org_v2/e2e_advising_requests.py` (chain incl. `student_department_council` resolution and skip,
director review, council vote → decision → notices + timeline, needs-info loop, reject → resubmit round, SLA reminder /
overdue / admins once, referral to a healthcare entity and outcome back, plans incl. student visibility and student
item ticks, accommodations granted on approval, cross-org and cross-advisor attacks, students see only their own
stages and never info notes / votes); rerun advising_flow_unit, advising_policy_unit, e2e_advising_foundation,
e2e_advising_assign, e2e_advising_casework, spec_help, e2e_org_v2, e2e_gov_requests, e2e_governance, e2e_registrar;
PG round trip on `nb-pg` db `adv_mig_p7`.

## App (`wt-front-adv-p7`, `lib/features/org/advising/`) — new files, so the three phases merge cleanly
- `adv_support_models.dart` (pure, tolerant of missing keys): `AdvRequest`, `AdvStudentRequest`, `AdvRequestStep`,
  `AdvRequestOptions`, `AdvChainConfig` / `AdvChainStep`, `AdvSupportPlan` / `AdvSupportPlanItem` (NOT `AdvPlan`: that
  name is the Phase 3 distribution plan), `AdvAccommodation`, `AdvSupportSummary`; stage / outcome / type labels ar + en.
- `adv_support_api.dart`: `AdvSupportApi(orgId, {client})` for the staff routes; static member calls `memberSupport`,
  `memberRequest`, `tickPlanItem`.
- `adv_support_texts.dart`: every new code (ar + en), merged into `orgErrorText` where `advCodeTexts()` is.
- `adv_requests.dart`: requests page (filters stage / kind / mine; manage: Review queue · Needs info · Overdue facets),
  composer sheet (Support request | Referral; type, category, accommodations chips when the type needs them, until-date,
  template picker, attachments through the governance upload, chain preview with skipped steps explained), request
  page (`AdvStageTrack` presentational stepper over `steps` + `history`, outcome card, info card, agenda tallies,
  actions: Submit · Review (approve / reject / needs info sheet) · Answer info · Resubmit · Cancel · Close), offline
  draft (reuse `adv_draft_store` with `client_id`).
- `adv_request_chain_page.dart`: the chain editor per scope (reorderable steps, entity picker, warnings when no
  faculty council / no department councils, Inherit).
- `adv_plan.dart`: plan cards with progress, editor sheet (title, measure, follow-up, student visible, items with owner
  and due date), status sheet (outcome note), item ticks.
- `adv_accommodations.dart`: accommodation list / grant sheet (manage) / end sheet; org-wide list for manage.
- 360 (`adv_student_page.dart`): a "Support" section — requests, referrals, plans, accommodations from
  `GET /students/{mid}/support`, with New request / Refer / New plan.
- Student hub sections as standalone widgets (the lead places them in the Phase 5 hub): `AdvHubRequestsSection`,
  `AdvHubPlansSection`, `AdvHubAccommodationsSection` (`adv_support_hub.dart`) + `AdvStudentRequestPage`.
- Wiring (`adv_wiring.dart` + `app_navigator.dart`): push `kind` `request` / `plan` → the pages above by `audience`;
  setup page links "Requests" (badge `requests_review` / `requests_needs_info`) and "Request chain" (manage).
- Success / failure texts (`showAppNotice`, ar + en): saved draft · submitted · approved step · rejected · returned for
  information · information sent · resubmitted · cancelled · closed · plan saved / activated / completed · item done ·
  accommodation granted / ended · chain saved; failures through `orgErrorText` + the codes above.
- Tests: `test/org/adv_support_models_test.dart`, `test/ui/adv_support_layout_test.dart` (every presentational view,
  all states, 320 / 1400, ar / en, textScaler 1.3), `test/visual/adv_support_golden_test.dart` (390 / 1440, ar / en,
  light / dark, `displayTheme(theme.materialTheme(dark: …), const DisplayPrefs())`; scenes: requests, composer,
  request at department council, needs info, decided, chain editor, plan, plan editor, accommodations, hub sections,
  student request).
