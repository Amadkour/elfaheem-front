# Institutions S3: routing rules, SLA escalation, decision templates, official minutes, the API contract

Backend branch `feature/institutions-s3` (D-971 – D-974, migration 0087). Staff prefix
`/api/v1/org/orgs/{org_id}/governance`, member prefix `/api/v1/org/public/governance`. Errors are
`{"detail": {"code", "message", "message_en"?, …}}`. Times are naive UTC ISO strings. Everything is additive.
The backend snapshot `docs/api_paths.json` has the new paths; copy it into `test/contract/` with
`export_api_paths.py --front ../nextbrain-front` when the app starts calling them.

## Automatic routing rules (D-971)

`GET /entities/{dept_id}/auto-routing` (anyone who sees the department's work)

```json
{"dept_id": 7,
 "rules": [{"id": "r1", "order": 0, "category_id": 12, "kind": null, "target": "department", "dept_id": 9,
            "user_id": null, "action": "approval", "enabled": true,
            "category": {"id": 12, "key": "…", "name_ar": "…", "name_en": "…", "kind": "request"},
            "dept": {"id": 9, "name_ar": "…", …}, "user": null}],
 "targets": ["department", "person", "department_council", "faculty_council"],
 "kinds": ["request", "memo", "custom"],
 "actions": {"department": ["approval", "review", "info"], "person": ["review", "approval", "info"],
             "department_council": ["vote"], "faculty_council": ["vote"]},
 "has_chain": false, "can_edit": true}
```

`PUT /entities/{dept_id}/auto-routing` body `{"rules": [{"id"?, "category_id"? | "kind"?, "target", "dept_id"?,
"user_id"?, "action"?, "enabled"?}]}` — the WHOLE ordered list (`[]` clears). Who: org admin, the department's head,
or `workflow:update` on it (403 `item_forbidden`). A council entity: 422 `entity_kind_invalid`. Answer: the GET shape.

- Exactly one of `category_id` (a request type of THIS department, not a complaint type) or `kind`.
- `target: department` needs `dept_id` (another active, non-council department); `person` needs `user_id` (a live
  member); `department_council` takes an optional `dept_id` (a scientific department with a council; absent = this
  department's own council); `faculty_council` needs a faculty council to exist.
- `action` absent = `approval` (department), `review` (person), `vote` (councils).
- `id` is kept when it is a short unique `[A-Za-z0-9_-]{1,24}`, else `r1`, `r2`, … by position.
- Invalid: 422 `auto_rule_invalid` `{index, field}` (`field` ∈ `rules`, `target`, `category_id`, `kind`, `action`,
  `dept_id`, `user_id`).

Behaviour: on submit (member `POST /{org_id}/items` request; staff `POST /items` without `route`), when the entity
has NO approval chain, the first enabled rule that matches (request type, else item `type`) and whose target the
submitter can reach routes the item, by the system. Reach = the target department / council's `audience` (null =
everyone) contains the sender's class: `departments` (item has `source_dept_id`), `students` (a student member),
else `staff`. Skipped rules and the applied one are in the item's timeline:

```json
{"kind": "routed", "actor": null, "data": {"auto_skipped": true, "rule_id": "r1", "reason": "audience", "target": "department"}}
{"kind": "routed", "actor": null, "data": {"route_id": 5, "action": "approval", "to_dept_id": 9, "to_user_id": null,
                                          "auto": true, "rule_id": "r2", "target": "department"}}
```

`reason` ∈ `audience`, `target_invalid`, `route_not_allowed`, `not_a_member`, `route_self`. Complaints are never
auto-routed. The new owner's head re-routes by hand with the existing `POST /items/{id}/route`.

## SLA escalation (D-972)

- Request types: `POST /entities/{dept_id}/categories` and `PUT /categories/{cid}` accept `sla_hours` (1..2160,
  `null` = the priority's hours); category JSON has `sla_hours`. A new item of that type gets
  `due_at = created_at + sla_hours`.
- `GET|PUT /settings`: new `sla_escalation` (bool; PUT by the org admin). Default: `true` for a university / faculty
  created from now on, `false` (absent) for every existing organization.
- Steps: `head` at `due_at` (the existing overdue notice); `vice_dean` one more SLA period later, still open: a
  system `review` route to the fitting vice dean (education & students for a student's item; postgraduate & research
  for the Postgraduate department; community service for Community Service), else the dean, else the org admin. The
  person gets the usual "forwarded to you" notice and sees it in their routed items. Timeline:
  `{"kind": "escalated", "actor": null, "data": {"route_id": 8, "action": "review", "to_user_id": 12, "sla": true,
  "step": "vice_dean", "target_role": "vice_dean_education_students"}}` (or `{"sla": true, "step": "vice_dean",
  "target_role": null, "no_target": true}` when nobody holds any of the roles). Once per item and step.
- `GET /items/{id}` (staff who see internal notes) gains:

```json
"sla_escalations": [{"step": "head", "at": "2026-11-15T10:00:00", "target_role": "head", "user": null},
                    {"step": "vice_dean", "at": "2026-11-15T20:00:00", "target_role": "dean",
                     "user": {"id": 12, "name": "…"}, "route_id": 8}]
```

## Decision templates (D-973)

`GET /decision-templates` (any staff context)

```json
{"items": [{"key": "grade_appeal", "group": "students", "group_ar": "شئون الطلاب", "group_en": "Student affairs",
            "title_ar": "تظلم من نتيجة", "title_en": "Grade appeal", "body_ar": "تقدّم الطالب/ «الاسم» …",
            "body_en": "The student «name» …", "decision_ar": "…", "decision_en": "…"}]}
```

Keys: `medical_excuse`, `other_excuse`, `re_enrolment`, `course_equivalence`, `grade_appeal`, `study_plan_approval`,
`exam_committees`, `staff_leave`, `thesis_registration`. Groups: `students`, `academic`, `staff`, `postgraduate`.
Blanks to fill are written «…».

`POST /sessions/{sid}/agenda/write` body `{"title"?, "body"?, "template_key"?, "lang"?: "ar" | "en"}`: with a known
key, a missing title / body comes from the template in `lang` (default `ar`), and the item's `payload` gets
`suggested_decision: {"ar", "en"}`. Without a title and without a known key: 422 `title_required`. An unknown,
well-formed key is stored and pre-fills nothing (S2 behaviour).

## Official minutes data (D-974)

`GET /export/data?module=minutes&session_id=…&lang=ar|en` gains `official` (null while the results are not visible:
before the close, for non-managers):

```json
"official": {
  "session_no": 1, "year": 2026, "chair": {"user_id": 8, "name": "…"}, "secretary": {"user_id": 6, "name": "…"},
  "total_weight": 5,
  "attendance": [{"user_id": 6, "name": "…", "weight": 1, "status": "voted" | "excused_coi" | "not_responded",
                  "status_text": "صوّت", "is_chair": false, "is_secretary": true}],
  "attendance_summary": {"voted": 3, "excused_coi": 1, "not_responded": 0},
  "items": [{"n": 1, "agenda_id": 1, "item_id": 7, "ref": "W-2026-000007", "title": "…", "decision_no": "1/1/2026",
             "outcome": "approved", "result": "approved_partial", "decision_text": "قرار رقم 1/1/2026: موافقة",
             "decision_note": null, "template_key": "grade_appeal", "suggested_decision": {"ar": "…", "en": "…"},
             "counts": {"approve": 1, "reject": 1, "abstain": 0, "eligible": 3, "approve_pct": 66.7},
             "weights": {"approve_w": 2, "reject_w": 1, "abstain_w": 0, "eligible_w": 4, "voted_w": 3, "needed_w": 2},
             "voters": [{"user_id": 3, "name": "…", "vote": "approve", "weight": 2}],
             "excused_coi": [{"user_id": 5, "name": "…"}],
             "not_responded": [{"user_id": 4, "name": "…", "weight": 1}]}]}
```

- Session attendance: `voted` = cast a vote on any row; `excused_coi` = declared a conflict and voted nowhere;
  else `not_responded`. Per-row lists are the row's own.
- `chair`: the council's chair; a faculty council that names none shows the dean role holder.
- Rows without a decision number (no quorum, postponed) have `decision_no: null` and `decision_text` = the outcome.

## Also

- A council roster change (`PUT /councils/{cid}/members`) now takes effect on the new member's rights at once
  (it used to wait for the permission cache).
