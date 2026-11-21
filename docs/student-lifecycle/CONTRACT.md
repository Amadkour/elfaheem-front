# Student lifecycle: contract (D-1400 – D-1415)

Frozen 2026-11-21 from the approved `PLAN.md` (all 16 questions answered with the default). Phase 1 is exact.
Phases 2–7 fix names, tables, routes and codes; an agent may add optional response keys there, never rename.
A change to anything in this file goes through the lead and is noted in §14.

Back paths are relative to `_wt/sl-back/`, front paths to `_wt/sl-front/lib/`.

## 0. Conventions (all checked in code)

- **Routers.** Staff router `features/org/students/api/org_students_router.py`,
  `APIRouter(prefix="/api/v1/org/orgs/{org_id}/students", tags=["Organization · Students"])`. Member router in
  the same module, `member_router = APIRouter(prefix="/api/v1/org", …)` (the onboarding `/me/onboarding` routes
  use the same prefix). Both are included in `main.py` **before** `org_public_router` (line 532). No existing
  route starts with `/orgs/{org_id}/students` (checked in `test/contract/api_paths.json`).
- **Permission.** `ctx: OrgCtx = Depends(org_ctx("<module>", "<action>"))` from
  `features.org.core.org_service`; extra checks inside the route with `ctx.require(module, action[, dept_id])`.
- **Errors.** `HTTPException(status, {"code": "<code>", "message": "<Arabic>", "message_en": "<English>", …})`
  through one helper `err(status, code, ar, en, **extra)` in `features/org/students/errors.py` (same shape as
  `onboarding.service.err`). The app maps every code in `students_errors.dart` and merges it into
  `orgErrorText`.
- **Kill switch on the server.** `require_feature(db, org, "<key>")` reusing
  `features.org.onboarding.service.feature_off_quiet(db, org, key)`; off → 409 `students_disabled`.
- **Audit.** `audit(db, org_id, actor, action, summary, *, entity=, entity_id=, dept_id=, meta=, before=, after=)`.
  Every action name here starts with `student.` (never `member.`, `role.`, `grant.`, `team.`, `dept.`: those are
  `PERM_AFFECTING_PREFIXES` and bump `perm_version`). `entity="student"`, `entity_id=<user id>`. Summary in
  Arabic, ≤ 500 characters.
- **Notifications.** `run_sync(notify_users, db, ids, title_ar, f"{msg_ar}\n{msg_en}", related_type="student_lifecycle",
  related_id=<uid or ask id>, org_id=org.id, data={…strings…, "title_en": …}, important=True, link={…})`,
  wrapped in try / except (a failed notice never breaks the request), as `onboarding/notify.py:send` does.
- **Live event.** `features.notifications.live_events.emit(db, user_ids, "student_lifecycle", {…}, fcm=False)`.
  Constant `EVENT_STUDENT_LIFECYCLE = "student_lifecycle"` in `features/notifications/live_update_service.py`
  (next to `EVENT_ONBOARDING`), `LiveEvents.studentLifecycle = 'student_lifecycle'` in `utils/live_events.dart`.
- **Times.** Naive UTC in the database; ISO strings out (`.isoformat()`), dates as `YYYY-MM-DD`. The app reads
  with `orgParseUtc()`, sends `orgUtc()`, shows with `AppTime`.
- **Bilingual data.** Server rows carry `*_ar` and `*_en`; the app picks by `AppConfig.lang`. Org screens use
  `t(ar, en)` (`admin_common.dart`), so `assets/translation.json` gets **no** keys from this job except the
  ones in §11.
- **Schema.** Model change AND revision. Revisions use `migrations/helpers.py` (`has_table`, `has_column`,
  `add_column_if_missing`, `drop_column_if_present`, `create_table_if_missing`, `drop_table_if_present`,
  `is_postgres`). The e2e scripts build the schema from the models, so every column must be on the model.
- **Python for tests.** `_wt/sl-back` has no `.venv312` and `py -3.12` has no FastAPI. Use
  `D:/platform/nextbrain/back/.venv312/Scripts/python` (written `$PY` below) with `PYTHONUTF8=1` and a
  per-run `DATABASE_URL=sqlite:///C:/…/<name>.db`.

## 1. Enums

| Name | Values |
|---|---|
| `ENROL_STATUSES` | `enrolled`, `suspended`, `postponed`, `disc_suspended`, `outside`, `withdrawn`, `cancelled`, `dismissed`, `transferred_out`, `graduated`, `deceased` |
| `ENROL_ACTIVE` (may register courses) | `enrolled` |
| `ENROL_PAUSED` (comes back by date) | `suspended`, `postponed`, `disc_suspended` |
| `ENROL_FINAL` (left) | `withdrawn`, `cancelled`, `dismissed`, `transferred_out`, `graduated`, `deceased` |
| `STANDINGS` | `regular`, `carrying`, `repeating`, `warning`, `final_chance` |
| `FLAG_KEYS` (stored) | `struggling`, `special_case`, `transferred_in`, `conscripted`, `excuse_open`, `disciplinary_record`, `affiliated` |
| derived flag (never stored) | `docs_owed` |
| `STAFF_ONLY_FLAGS` (hidden from the student, Q8) | `struggling`, `special_case`, `disciplinary_record` |
| `DIMENSIONS` | `enrolment`, `standing`, `flag` |
| `VIA` | `auto`, `manual`, `request`, `undo`, `system` (backfill / activation) |
| `DISMISS_REASONS` | `chances_exhausted`, `gpa`, `max_duration`, `not_registered`, `disciplinary` |
| `REASON_CODES` (others, `String(40)`) | `military`, `illness`, `abroad_work`, `abroad_spouse`, `child_care`, `parent_care`, `detention`, `own_request`, `fees`, `transfer_same_univ`, `transfer_other_univ`, `penalty`, `complaint`, `appeal`, `leniency`, `data_error`, `other` |
| `BODIES` (`String(40)`) | `student_affairs`, `education_committee`, `faculty_council`, `university_council`, `dean`, `university_president`, `disciplinary_board`, `department_council` |
| `SOURCE_TYPES` (`String(20)`) | `complaint`, `case`, `ask`, `decision`, `work_item`, `results`, `promotion`, `sweep` |
| `ASK_KINDS` | `meeting`, `data`, `documents`, `confirm` |
| `ASK_PRESENTATIONS` | `notice`, `popup`, `fullscreen` |
| `ASK_STATUSES` | `open`, `answered`, `accepted`, `returned`, `cancelled`, `expired` |
| `INTAKE_LABELS` (derived, §3.1) | `nominated`, `provisional`, `missing`, `awaiting`, `accepted`, `rejected`, `withdrawn` |
| `TIMELINE_KINDS` | `status`, `intake`, `documents`, `level`, `results`, `registration`, `requests`, `meetings`, `complaints`, `asks`, `record` |
| `FILE_SECTIONS` (access log) | `file`, `academic`, `documents`, `nid`, `advising`, `requests`, `access_log`, `export` |
| `org_terms.kind` | existing `term1`, `term2`, `summer` + new `makeup` (phase 5; fits `String(8)`) |
| `cal_meetings.source_type` | existing `complaint`, `advising` + new `student_ask` (fits `String(20)`) |
| `org_decisions.kind` (new, `String(40)`) | `status_change`, `dismissal_due`, `final_chance_due`, `outside_permission_due`, `suspension_ending` |

Legacy mapping kept for installed apps: `org_student_academic.standing` (`good | probation | honours`) is still
written by `recompute` exactly as today. `acad_standing` is the new field: `probation → warning`, otherwise
`regular`, plus the traditional values.

## 2. Tables and migrations

New model file `data/student_lifecycle_models.py` (imports `Base` from `data.models`, `_ORG_FK`,
`_USER_FK_NULL`, `_USER_FK_CASCADE`, `_utc` from `data.org_models`). Every e2e script of this job imports it
before `Base.metadata.create_all(engine)`.

Chain: `0110` (down `"0101"`) → `0111` (down `"0110"`) → `0112` (down `"0111"`) → `0113` → `0114` → `0115`.
`0102`–`0107` belong to another job; never use them.

### 2.1 `0110_student_status.py` (phase 1 creates everything phases 1–2 need)

**`org_student_status_events`** (append-only):

| Column | Type | Null | Notes |
|---|---|---|---|
| `id` | Integer PK | | |
| `org_id` | Integer FK `organizations.id` CASCADE | no | index |
| `user_id` | Integer FK `users.id` CASCADE | no | index |
| `dimension` | String(12) | no | `DIMENSIONS` |
| `key` | String(32) | yes | flag key; NULL for enrolment / standing |
| `from_value` | String(24) | yes | flags: `on` / `off` |
| `to_value` | String(24) | no | |
| `reason_code` | String(40) | yes | |
| `reason` | Text | yes | |
| `decision_no` | String(60) | yes | |
| `decision_date` | Date | yes | |
| `body` | String(40) | yes | `BODIES` |
| `effective_from` | Date | yes | |
| `effective_to` | Date | yes | |
| `via` | String(10) | no | default `manual` |
| `source_type` | String(20) | yes | |
| `source_id` | Integer | yes | |
| `term_id` | Integer | yes | no FK (history outlives a term) |
| `effects` | JSON | yes | `{dropped_registration_ids: [], access_until: "YYYY-MM-DD", prev: {enrol_since, enrol_until, standing_hold_until}}` |
| `rules` | JSON | yes | snapshot of the rule that fired |
| `reverts_id` | Integer | yes | the event this one undoes |
| `reverted_by_id` | Integer | yes | set once on the undone event |
| `actor_id` | Integer FK `users.id` SET NULL | yes | NULL = the system |
| `actor_role` | String(30) | yes | |
| `created_at` | DateTime | no | `_utc` |

Indexes `ix_stu_evt_org_user_time (org_id, user_id, created_at)`, `ix_stu_evt_org_dim_value (org_id, dimension, to_value)`.
PostgreSQL only (`is_postgres()`): trigger `org_student_status_events_guard` refuses DELETE, and refuses any
UPDATE that changes a column other than `reverted_by_id` or sets it when it is already non-NULL (pattern of
migration 0004). Downgrade drops the trigger, then the table.

**`org_student_flags`**: `id` PK · `org_id` FK CASCADE not null · `user_id` FK CASCADE not null ·
`key String(32)` not null · `active Boolean` not null default true · `since Date` · `until Date` ·
`event_id Integer` · `updated_at DateTime`. Unique `uq_org_student_flag (org_id, user_id, key)`, index
`ix_org_student_flag_key (org_id, key, active)`.

**`org_student_academic`** new columns (all nullable unless said):

| Column | Type | Notes |
|---|---|---|
| `enrol_status` | String(24) not null, server default `'enrolled'` | |
| `enrol_since` | Date | |
| `enrol_until` | Date | paused statuses: the day enrolment resumes |
| `acad_standing` | String(24) | |
| `standing_hold_until` | Integer | term id; automatic standing is not re-applied before it |
| `warnings_run` | Integer | consecutive warnings |
| `years_in_level` | Integer | traditional: years spent in the current year |
| `outside_chances_used` | Integer | |
| `admission_route` | String(40) | the case's `type_key` at activation |
| `rule_set_key` | String(40) | phase 7 |

Backfill in the revision (plain SQL, idempotent): `enrol_status = 'graduated'` where `stage = 'graduated'`;
`acad_standing = 'warning'` where `standing = 'probation'`, `'regular'` where `standing in ('good','honours')`;
`admission_route` from `org_onboarding_cases.type_key` through `org_members.onboarding_case_id` where present.
No status events are written by the backfill (the timeline starts from real history).

### 2.2 Later revisions

| Revision | Phase | Content |
|---|---|---|
| `0111_student_asks` | 4 | table `org_student_asks` (§7.1) |
| `0112_onboarding_inline_fix` | 3 | `org_import_rows.edited_by Integer`, `edited_at DateTime`, `dup_of_row Integer`; `org_onboarding_cases.last_reminded_at DateTime`, `reminders_sent Integer`; a `passport` row in `identity_fields` if the table exists |
| `0113_student_lifecycle_help` | 1 (written by the lead after phase 1, extended by later phases only through new revisions) | copies the new help pages and `page_ids` into an already seeded database, as `0100_onboarding_help` does |
| `0114_transfer_credits` | 6 | table `org_transfer_credits` (§9) |
| `0115_rule_sets` | 7 | not built now (Q6: default "later"); number reserved |

Because 0113 is written by the lead after the phase-1 wave and 0111 / 0112 by later phases, the lead keeps the
chain linear: a revision's `down_revision` is the highest number already on the branch when it is written, and
this table's order is the intended order.

Settings (JSON, no DDL): `organizations.settings["lifecycle"]` (§6.4); rule blocks under
`organizations.settings["registrar"]` (§8).

## 3. Shared shapes

### 3.1 Intake label (pure, server `status.intake_label`, app `intakeLabel`)

From the student's onboarding case (`org_members.onboarding_case_id`); no case → `accepted`.

| Case status | Other condition | Label |
|---|---|---|
| `draft` | `source in ('excel','intake')` and never submitted | `nominated` |
| `draft`, `submitted` | | `provisional` |
| `needs_correction` | | `missing` |
| `under_review` | | `awaiting` |
| `approved` | | `awaiting` |
| `active` | `missing_count > 0` | `missing` |
| `active` | | `accepted` |
| `rejected` / `withdrawn` | | same word |

### 3.2 The one chip (pure, server `status.chip`, app `studentChip`)

1. `enrol_status != 'enrolled'` → `{dimension: "enrolment", value: enrol_status}`
2. else member `status != 'active'` → `{dimension: "member", value: status}` (`pending`, `suspended`, `expired`, `rejected`)
3. else intake label not `accepted` → `{dimension: "intake", value: label}`
4. else `{dimension: "standing", value: acad_standing or "regular"}`

Tone (app): `regular`, `accepted` success · `carrying`, `missing`, `awaiting`, `provisional`, `nominated`,
`postponed` warning · `repeating`, `warning`, `final_chance`, `suspended`, `disc_suspended`, `outside` danger ·
final statuses neutral · `graduated` gold. Labels ar / en live in `students_models.dart`
(`enrolText`, `standingText`, `flagText`, `intakeText`) and must cover every enum value (a unit test checks).

### 3.3 `StudentRow`

```json
{
  "user": {"id": 812, "name": "أحمد محمد علي", "name_en": "Ahmed Mohamed Ali", "image_url": null, "username": "ahmed.m"},
  "member_id": 5531,
  "member_status": "active",
  "student_code": "20261234",
  "program": {"id": 7, "code": "CS", "name_ar": "علوم الحاسب", "name_en": "Computer Science"},
  "level": "2",
  "cohort": "current",
  "type_key": "student_new",
  "nid_last4": "4821",
  "enrol_status": "enrolled",
  "enrol_until": null,
  "acad_standing": "carrying",
  "flags": ["transferred_in"],
  "intake": {"case_id": 3310, "status": "active", "label": "missing", "conditional": true, "due_at": "2026-12-15T00:00:00"},
  "missing_count": 3,
  "chip": {"dimension": "intake", "value": "missing"}
}
```

`program`, `level`, `student_code`, `type_key`, `nid_last4`, `intake`, `missing_count` may be `null` (a member
without a case has `intake: null`, `missing_count: null`). `flags` lists active stored flags only.
`nid_last4` is sent only to a caller who may view the case's type module.

### 3.4 `TimelineItem`

```json
{
  "id": "case_event:9912",
  "kind": "documents",
  "at": "2026-10-02T09:14:00",
  "actor": {"id": 44, "name": "منى السيد"},
  "title_ar": "تم التحقق من مستند: شهادة الميلاد",
  "title_en": "Document verified: birth certificate",
  "detail_ar": null,
  "detail_en": null,
  "reason": null,
  "decision_no": null,
  "source": {"type": "case", "id": 3310},
  "can_undo": false,
  "undone": false
}
```

`id` is `"<source>:<row id>"`, unique and stable (the app uses it as the key). `actor` is `null` for the system.

## 4. Phase 1 endpoints (exact)

All staff routes: kill switch `org.students` (409 `students_disabled`), the caller must not be a student
(the existing `student_forbidden` rule of the dashboard applies through `CONFLICT_RULES` on the modules).
"Student" = a user with an `OrgMember` row in this organization with `role == "student"`, any status; anything
else → 404 `student_not_found`.

### 4.1 `GET /api/v1/org/orgs/{org_id}/students`

`org_ctx("students", "view")`.

Query: `q` (name, `student_code`, exactly 4 digits = `nid_last4`), `chip` (`enrolled | missing | attention | suspended`),
`enrol`, `standing`, `flag`, `program_id`, `level`, `type_key`, `member_status`, `sort` (`name | code | recent`,
default `name`), `page` (≥ 1, default 1), `size` (1–100, default 30).

- `chip=enrolled` → `enrol_status = enrolled` and member active; `missing` → `missing_count > 0`;
  `attention` → `acad_standing in (warning, repeating, final_chance)` or flag `struggling`;
  `suspended` → `enrol_status in ENROL_PAUSED`.
- Unknown filter value → 422 `bad_filter` with `field`.

Response 200:

```json
{
  "total": 1840, "page": 1, "size": 30, "pages": 62,
  "summary": {"enrolled": 1712, "missing": 96, "awaiting": 41, "attention": 58, "suspended": 12},
  "can": {"add": true, "import": true, "export": true, "settings": false},
  "items": [ { "…": "StudentRow" } ]
}
```

- `summary` counts the whole organization (not the filtered list). `awaiting` = open onboarding cases of
  types with `module = "students"` in `submitted, under_review, approved`; the app's card opens the existing
  Admissions page (`OnboardingPage`) instead of filtering this list.
- `can.add` = `students:insert` and `org.onboarding` on; `import` = `students:import` and
  `org.onboarding.import` on; `export` = `students:export`; `settings` = `academic:update`.
- Cost rule: no query per row. One query each for members + users, academic rows, flags, cases, current
  documents; `missing_count` from `onboarding.service.requirements` in memory with the types cached per request.

### 4.2 `GET /api/v1/org/orgs/{org_id}/students/{uid}/file`

`org_ctx("students", "view")`. Writes the access log (`section = "file"`, §4.6) and commits.

```json
{
  "student": { "…": "StudentRow", "email": "a@example.com", "phone": "+2010…", "joined_at": "2026-09-20T08:00:00",
               "birth_date": "2008-03-11", "gender": "m", "nationality": "EG" },
  "academic": {"stage": "program", "cgpa": 2.41, "earned_credits": 36.0, "attempted_credits": 42.0,
               "legacy_standing": "good", "probations": 0, "study_system": "credit_hours",
               "advisor": {"id": 90, "name": "د. سارة"}, "graduated_at": null},
  "intake": {"case_id": 3310, "type_key": "student_new", "type_label_ar": "طالب مستجد", "type_label_en": "New student",
             "status": "active", "label": "missing", "conditional": true, "due_at": "2026-12-15T00:00:00",
             "missing_count": 3, "activated_at": "2026-09-20T08:00:00"},
  "journey": [
    {"key": "applied", "label_ar": "تقديم الملف", "label_en": "Applied", "state": "done", "at": "2026-09-01T10:00:00"},
    {"key": "accepted", "label_ar": "القبول", "label_en": "Accepted", "state": "done", "at": "2026-09-20T08:00:00"},
    {"key": "level:1", "label_ar": "الفرقة الأولى", "label_en": "Year 1", "state": "done", "at": null},
    {"key": "level:2", "label_ar": "الفرقة الثانية", "label_en": "Year 2", "state": "current", "at": "2027-07-01T00:00:00"},
    {"key": "graduated", "label_ar": "التخرج", "label_en": "Graduation", "state": "todo", "at": null}
  ],
  "open": {"asks": 0, "requests": 0, "complaints": 1, "next_meeting": null},
  "can": {"academic": true, "documents": true, "case": true, "requests": true, "complaints": true,
          "advising": false, "access_log": false, "status_view": true, "status_change": false, "ask": false,
          "meeting": false},
  "logged": true
}
```

- `journey.state` ∈ `done | current | todo | warn` (maps 1:1 to `AppRoadmapState`); `warn` on the current
  level when the chip is danger-toned. Level nodes come from `academic_config.levels_of`; with no levels the
  list is `applied, accepted, graduated` only.
- `can.*`: `academic` = `students:view`; `case` = the case type's module `view`; `documents` =
  `member_documents:view`; `requests` = `workflow` view on any department; `complaints` = `complaints` view
  on any department; `advising` = the advising access rule (`advising/access.py`), false when `org.advising`
  is off; `access_log` = `audit:view`; `status_view` = `student_status:view`; `status_change`, `ask`,
  `meeting` = **always false in phase 1**.
- `open.complaints` is `null` without the complaints right (never 0, so the app can hide the line);
  `open.asks` / `requests` are 0 until phases 4 / 6. `next_meeting` = `{id, starts_at, mode, title}` of the
  next `cal_meetings` row with this student as an attendee and a non-null `source_type`, else `null`.
- The sensitive values `email`, `phone`, `birth_date`, `nationality` need the case type's module `view`,
  otherwise `null`.

### 4.3 `GET /api/v1/org/orgs/{org_id}/students/{uid}/timeline`

`org_ctx("students", "view")`. Query: `kinds` (comma list of `TIMELINE_KINDS`, default all the caller may
see), `before` (ISO, exclusive), `limit` (1–100, default 30). No access-log row (the file open covers it).

```json
{"items": [ { "…": "TimelineItem" } ], "next_before": "2026-09-20T08:00:00", "hidden_kinds": ["complaints"]}
```

Sources in phase 1 (each read with its own right; a kind the caller may not see goes to `hidden_kinds`):

| Kind | Source | `id` prefix | Right | Sentence |
|---|---|---|---|---|
| `intake` | `org_case_events` with a `to_status`, or kind in `created`, `step_approved`, `approved`, `activated`, `quick_add`, `invited` (the transition kinds are the op names `submit`, `claim`, `request_correction`, `reject`, `withdraw`) | `case_event` | case type module `view` | one sentence per kind in `timeline.py`; an unknown kind shows its `from → to` |
| `documents` | every other `org_case_events` row (`document_uploaded` and the other document kinds, `edited`, `reminder`, `overdue_notified`, `documents_purged`) | `case_event` | same | |
| `level` | `org_level_advances` | `level` | `students:view` | "Moved from {from} to {to}" + via |
| `registration` | `org_registrations` grouped by term: one item per term, `at` = the term's `start_date` | `reg_term` | `students:view` | "Registered {n} courses ({credits} CH)" |
| `results` | `org_registrations` with `grade_state = 'approved'` grouped by term, `at` = the term's `end_date` | `res_term` | `students:view` | "Results of {term}: passed {p} of {n}, term GPA {g}" |
| `status` | `org_student_status_events` (empty until phase 2) | `status` | `student_status:view` | §6.5 |
| `complaints` | `org_complaints` where `user_id = uid` and not anonymous | `complaint` | `complaints` view on the complaint's `dept_id` | ref + subject + status |
| `meetings` | `cal_meetings` with a `source_type` and this student in `cal_meeting_attendees` | `meeting` | `students:view` | title, mode, status |
| `record` | `org_audit_log` rows with (`entity = 'member'` and `entity_id = member.id`) or (`entity in ('user','student')` and `entity_id = uid`), actions starting `member.`, `academic.`, `registrar.graduate`, `student.` **except** `student.file_viewed` and `student.exported` | `audit` | `students:view` | the row's `summary` |
| `asks`, `requests` | phases 4, 6 | `ask`, `work` | | |

Merge: each source is read newest first with `created_at < before` and `limit + 1` rows, merged by `at`
descending, cut at `limit`; `next_before` = the last item's `at` or `null`. Ties are ordered by `id`.

### 4.4 `GET /api/v1/org/orgs/{org_id}/students/{uid}/missing`

`org_ctx("students", "view")` + the case type's module `view` (else 403 `org_forbidden`).

```json
{
  "case_id": 3310, "can_upload": true, "can_edit": true, "can_waive": false, "due_at": "2026-12-15T00:00:00",
  "photos": [ {"key": "photo", "label_ar": "صورة شخصية", "label_en": "Personal photo", "why_ar": "مطلوبة لكل الطلاب",
               "why_en": "Required for every student", "due_at": null, "status": null} ],
  "documents": [ {"key": "military_2", "label_ar": "نموذج 2 جند", "label_en": "Military form 2",
                  "why_ar": "مطلوب للطلاب المصريين الذكور", "why_en": "Required for male Egyptian students",
                  "due_at": "2026-12-15T00:00:00", "status": "deferred"} ],
  "fields": [ {"key": "guardian_phone", "label_ar": "هاتف ولي الأمر", "label_en": "Guardian's phone", "kind": "phone",
               "why_ar": "مطلوب لمن هم دون 18 سنة", "why_en": "Required under 18"} ]
}
```

- Built from `onboarding.service.requirements(case, type, current_docs)["missing"]`. A document requirement
  whose definition has a `photo` block goes to `photos`. `why_*` is a sentence rendered from the item's
  `required` / `when` rule by one pure function (`students/missing.py:why`) covering: always, gender,
  nationality, age below / above, a field equals; anything else → "مطلوب حسب إعدادات المؤسسة" /
  "Required by the institution's settings".
- No case → 200 with `case_id: null` and three empty lists. Phase 1 is read only: the app shows the sheet
  with the lists and an "Open the file" button to the existing review page; in-place upload is phase 3.
- `can_upload` = type module `update`; `can_edit` the same; `can_waive` = type module `approve`.

### 4.5 `GET /api/v1/org/orgs/{org_id}/students/{uid}/access-log`

`org_ctx("audit", "view")`. Query `page`, `size` (default 30). Writes `section = "access_log"`.

```json
{"total": 14, "page": 1, "size": 30, "pages": 1,
 "items": [ {"at": "2026-11-21T10:02:11", "actor": {"id": 44, "name": "منى السيد"}, "actor_role": "org-staff",
             "section": "file", "ip": "196.2.x.x"} ]}
```

Rows = `org_audit_log` where `org_id`, `entity = 'student'`, `entity_id = uid`,
`action in ('student.file_viewed', 'student.exported')`, newest first.

### 4.6 Access log rule (`features/org/students/access_log.py`)

`viewed(db, ctx, uid, section) -> bool`: writes
`audit(db, ctx.org.id, ctx.user, "student.file_viewed", f"فتح ملف الطالب #{uid} ({section})", entity="student", entity_id=uid, meta={"section": section})`
unless the same actor has a `student.file_viewed` row for the same student and section in the last
`settings.lifecycle.file_log.window_minutes` (default 30; 0 = always). The caller commits. Sections written
by: `GET file` → `file`; the app's Academic tab calls the existing `GET registrar/students/{uid}/record`,
which now also calls `viewed(…, "academic")`; `GET onboarding/documents/{id}/file` and `GET cases/{id}/nid`
keep their own audit actions and add nothing. The advising 360 open (`advising` section) is wired in phase 2.

### 4.7 Errors (phase 1)

| HTTP | code | When |
|---|---|---|
| 409 | `students_disabled` | kill switch `org.students` off |
| 404 | `student_not_found` | `uid` is not a student member of this organization |
| 403 | `org_forbidden` | existing: the right is missing |
| 422 | `bad_filter` | unknown filter value (`field` names it) |

### 4.8 Catalog additions the lead commits BEFORE the phase-1 wave

- `features/org/core/org_catalog.py`: module
  `"student_status": {"actions": ["view", "insert", "update", "approve", "export"], "scope": "org", "group": "people", "label": ("حالات الطلاب وقراراتها", "Student statuses and decisions")}`;
  `CONFLICT_RULES` student rule denies all five; the four system roles of §10; `dean`,
  `vice_dean_education_students` gain `student_status` all five; `viewer` gets it through its
  "every module: view" rule automatically.
- `features/platform/feature_catalog.py`: the six keys of §12.
- `main.py`: `from features.org.students.api import org_students_router` + the two `include_router` lines
  before `org_public_router` (agent B creates the module first as an empty router in its first commit, or the
  lead adds the include after the wave; the lead decides at wave start and tells B).

## 5. Phase 1 front contract

Folder `features/org/students/` (new). Every page loads over a plain-values view; the view is what the
layout tests pump.

| File | Owner | Contents |
|---|---|---|
| `students_models.dart` | F1 | pure: `StudentRow`, `StudentChip`, `StudentsPageData`, `StudentsSummary`, `StudentsQuery` (`toQuery()`), `intakeLabel`, `studentChip`, `chipTone`, text maps `enrolText`, `standingText`, `flagText`, `intakeText`, `memberStatusText` (each `(String ar, String en)` per enum value), `kStudentsFeatureKey = 'org.students'`, `kStudentsMissingKey = 'org.students.missing'` |
| `students_api.dart` | F1 | `StudentsApi(orgId)`: `list(StudentsQuery)`, `file(uid)`, `timeline(uid, {kinds, before, limit})`, `missing(uid)`, `accessLog(uid, page)`; all through `orgCall` |
| `students_errors.dart` | F1 | `studentsCodeTexts` (`students_disabled`, `student_not_found`, `bad_filter` + later phases' codes), merged into `orgErrorText` by the lead (`org_v3.dart` is a shared file) |
| `students_parts.dart` | F1 | `StudentStatusChip(chip)`, `StudentFlagChips(flags)`, `MissingBadge(count, onTap)`, `StudentAvatar` |
| `students_page.dart` | F1 | `OrgStudentsPage(orgId)` (loads) + `StudentsPageView` (plain values): `OrgPageHeader(helpPageId: 'org.students')`, `OrgPageBody`, summary cards as the filter, `AppDataTable` (cards on phones), `AppSearchField`, one filter sheet, `AppPagination`, primary action "Add student" → existing `onboarding_entry.dart` entry |
| `students_missing_sheet.dart` | F1 | `showMissingDataSheet(context, orgId, uid)` + `MissingDataView` (read only in phase 1) |
| `student_file_models.dart` | F2 | pure: `StudentFile`, `JourneyNode` (→ `AppRoadmapNode`), `StudentCan`, `TimelineItem`, `TimelineGroup`, `groupTimelineByYear`, `timelineKindText`, `timelineIcon` |
| `student_file_page.dart` | F2 | `OrgStudentFilePage(orgId, uid)` + `StudentFileView`: `OrgPushedPage(helpPageId: 'org.students.file')`, header card, `AppRoadmap`, `AppUnderlineTabs` (lazy) |
| `student_file_tabs.dart` | F2 | Overview, Academic (embeds the body of `OrgRecordScreen(studentId:)`), File & documents (a card that opens `OnbReviewPage` for `intake.case_id`), Requests & complaints (links into the existing pages), Advising (link card to `AdvStudentPage`), Access log |
| `student_timeline.dart` | F2 | `StudentTimeline` (paged with `before`), filter chips, year groups, `StudentTimelineView` |
| `students_wiring.dart` | F2 | `openStudentFile(context, orgId, uid)`, `studentsSub(OrgSession)` (the `OrgSub` tuple for `_peopleSubs`), deep-link handler `openStudentFromLink(orgId, uid)`; **the only file other code calls** |

F2 depends on F1's `students_models.dart` / `students_api.dart`: F1 commits those two files first (models and
API signatures exactly as above) before either agent builds pages; until then F2 codes against this contract.

Lead after the wave (shared files, small additions): `_peopleSubs` in `org_dashboard_screen.dart` gets
`studentsSub(s)` first when `s.can('students')` and `'org.students'` is not in `AppConfig.disableList`;
`OrgPeoplePage` row tap opens `openStudentFile` when the switch is on (else the entity page as today);
`app_navigator.dart` module `org_student` (`{org_id, id}`); the start-URL parser route
`/org/:orgId/students/:uid` in `main.dart`; `orgErrorText` merge; `LiveEvents.studentLifecycle`.

Rules that are easy to break: the header card and tabs never use `Colors.*`; every time through `AppTime`;
counts through `countText`; arrows through `DirIcons`; no pixel `maxWidth` (`AppWidth.content`); lists show
`AppListSkeleton`, errors `AppErrorState` with `ApiException.from(e).message`.

## 6. Phase 2: statuses, decisions, undo

### 6.1 Decision keys and the default matrix

`settings.lifecycle.decision_matrix[<key>] = {"decide": "update" | "approve" | "auto", "body": <BODIES> | null, "decision_no": bool}`.
`propose` is always `student_status:insert`. `auto` is allowed only for the keys marked (auto ok).

| Decision key | Writes | Default decide | Default body | Decision no. | RESEARCH |
|---|---|---|---|---|---|
| `suspend` | enrolment → `suspended` | approve | `faculty_council` | yes | §5, S5, S6 |
| `suspend_extend` (beyond `suspension.max_years`) | same | approve | `university_council` | yes | §5, S5 |
| `postpone` | → `postponed` | approve | `faculty_council` | yes | §5, S11 |
| `resume` | paused → `enrolled` | update | `student_affairs` | no | §5 |
| `disc_suspend` | → `disc_suspended` | approve | `dean` | yes | §5 arts. 126–127, S9 |
| `outside` | → `outside` | approve | `faculty_council` | yes | §4.1 art. 80, S3 |
| `dismiss_academic` (auto ok) | → `dismissed` (`chances_exhausted`, `gpa`, `max_duration`, `not_registered`) | approve | `faculty_council` | yes | §4.1, §4.2, S3, S10, S11 |
| `dismiss_disciplinary` | → `dismissed` (`disciplinary`) | approve | `disciplinary_board` | yes | §5 art. 126, S9 |
| `withdraw` | → `withdrawn` | update | `student_affairs` | no | §5, S11, S12 |
| `cancel` | → `cancelled` | approve | `faculty_council` | yes | §5, S9, S11 |
| `transfer_out` | → `transferred_out` | approve | `university_president` | yes | §1.3, S6 |
| `reenrol` | final → `enrolled` | approve | `faculty_council` | yes | §5, S9, S11, S12 |
| `graduate_undo` | `graduated` → `enrolled` | approve | `faculty_council` | yes | §6, S1 |
| `deceased` | → `deceased` | update | `student_affairs` | no | §7 |
| `standing_override` | standing → any | approve | `faculty_council` | no | §4.1 leniency, S12 |
| `final_chance` (auto ok) | standing → `final_chance` | approve | `faculty_council` | yes | §4.2, S10, S11; §4.1, S3 |
| `flag.struggling` | flag on / off | update | `null` | no | §4.2 last bullet |
| `flag.special_case` | flag on / off | update | `null` | no | — |
| `flag.conscripted` | flag on / off | update | `student_affairs` | no | §2, S6 |
| `flag.excuse_open` | flag on / off | approve | `faculty_council` | no | §5 excuse, S3, S5 |
| `flag.disciplinary_record` | flag on / off | approve | `dean` | yes | §5 art. 126, S9 |

Allowed enrolment transitions (anything else 409 `bad_transition`):
`enrolled → suspended | postponed | disc_suspended | outside | dismissed | withdrawn | cancelled | transferred_out | deceased`;
`suspended | postponed | disc_suspended → enrolled | withdrawn | cancelled | dismissed | deceased`;
`outside → enrolled | dismissed | deceased`; `withdrawn | cancelled | dismissed → enrolled` (key `reenrol`);
`graduated → enrolled` (key `graduate_undo`); `enrolled → graduated` only through the existing
`registrar.service.graduate`, which now also writes the event. Guards from the rules (`suspension.exclusions`,
`max_years`): 409 `rule_blocks` with `rule` and bilingual text; a holder of `approve` may pass `override: true`
with a reason (recorded in `rules`).

### 6.2 Routes

| Method, path (under `/api/v1/org/orgs/{org_id}/students`) | `org_ctx` | Body → answer |
|---|---|---|
| `GET /{uid}/status` | `student_status:view` | → `{enrol_status, enrol_since, enrol_until, acad_standing, standing_hold_until, flags: [{key, since, until, reason, event_id}], last: {enrolment: Event|null, standing: Event|null}, options: [Option]}` |
| `POST /{uid}/status` | `student_status:insert`, then per matrix inside | `StatusIn` → `{event: Event, status: <GET status>}` |
| `POST /{uid}/status/propose` | `student_status:insert` | `StatusIn` → 201 `{decision_id}` (an `OrgDecision`, kind `status_change`, `entity="student"`, `entity_id=uid`, `recommendation={"action": "student_status", "params": StatusIn + {student_id}}`) |
| `POST /status-events/{eid}/undo` | `student_status:insert`, then the original key's right or `approve` | `{reason}` → `{event, status}` |
| `GET /{uid}/status/events?dimension=&page=` | `student_status:view` | → `{items: [Event], total, …}` |
| `GET /settings` | `academic:view` | → `{lifecycle: Lifecycle, defaults: Lifecycle}` |
| `PUT /settings` | `academic:update` | `{lifecycle}` (whole object, every key sent) → same as GET |

`StatusIn`: `{"decision": "suspend", "to": "suspended", "flag_on": null, "reason_code": "illness", "reason": "…",
"decision_no": "م ك 12/2026", "decision_date": "2026-11-18", "effective_from": "2026-11-21",
"effective_to": "2027-09-01", "effects": {"drop_current": false, "access_until": null},
"source": {"type": "complaint", "id": 77}, "override": false, "attachment_ids": []}`.
`to` is required for `standing_override`; for flags `flag_on: true | false`.

`Option`: `{"decision": "suspend", "label_ar", "label_en", "mode": "decide" | "propose", "needs": ["reason", "decision_no", "effective_to"], "body", "danger": false, "blocked": null | {"rule", "text_ar", "text_en"}}`.

`Event`: every column of §2.1 by name + `actor: {id, name}`, `title_ar`, `title_en`, `can_undo`, `undone`.

The registrar's `ACTIONS` registry gains `"student_status"` (applies the params through `status.apply`), so
accepting the decision in the existing Decisions inbox (`academic:approve`) or in the phase-4 inbox sets it.

### 6.3 Errors

| HTTP | code | When |
|---|---|---|
| 409 | `bad_transition` | not in the allow-list (`from`, `to`) |
| 409 | `rule_blocks` | a rule guard (`rule`) |
| 403 | `needs_body` | the caller holds `insert` only or the matrix needs `approve`: use propose (`decision`, `body`) |
| 422 | `reason_required` · `decision_no_required` · `dates_required` · `bad_dates` | |
| 409 | `not_latest` | undo of an event that is not the newest of its dimension (flags: of its key) |
| 409 | `already_reverted` | |
| 409 | `status_disabled` | kill switch `org.students.status` off |

### 6.4 `settings.lifecycle` shape (defaults in `students/settings.py:DEFAULTS`)

```json
{
  "decision_matrix": {"…": "§6.1"},
  "struggling_rule": {"auto": true, "standings": ["warning", "final_chance"], "repeat_same_level_times": 2},
  "side_effects": {"block_registration": true, "ask_drop_current": true, "access_after_leaving_days": 90},
  "student_sees": {"status": true, "reason": true, "decision_no": true},
  "reminders": {"incomplete_every_days": 7, "incomplete_max": 4, "ask_before_days": [3, 1], "suspension_ending_days": 14},
  "file_log": {"window_minutes": 30, "tell_staff": true},
  "sibling_duplicate": "warn"
}
```

### 6.5 Side effects, audit, notices

- `registrar.service.evaluate` gains block code `enrolment_not_active` when `enrol_status` is not `enrolled`
  (text in `org_registrar.dart` `blockText`). Old apps show the server's message.
- Audit actions: `student.status_changed`, `student.standing_changed`, `student.flag_set`,
  `student.flag_cleared`, `student.status_undone`, `student.status_proposed`, `student.settings_updated`
  (with `before` / `after`).
- Notice kinds (in push `data.kind`): `status_changed`, `standing_changed`, `status_undone` to the student
  (staff-only flags send nothing); `status_proposed` to holders of the deciding right. Live event payload
  `{org_id, student_id, kind}` to the student and to the actor's organization staff who have the file open
  (the app listens and refreshes the file).
- Membership: a final status with `effects.access_until` sets `org_members.expires_at` to that date (default
  today + 90 days); the membership row is otherwise untouched. Undo restores the previous `expires_at` from
  `effects.prev`.
- `GET /api/v1/org/public/{org_id}/my-status` (member router, the student himself):
  `{enrol_status, enrol_until, acad_standing, flags (minus STAFF_ONLY_FLAGS), last: {title_ar, title_en, reason, decision_no, at}}`
  filtered by `student_sees`.

Front files (phase 2): `student_status_models.dart` (pure), `student_status_sheet.dart`
(`showStatusChangeSheet`), `student_settings_page.dart`, `student_matrix_page.dart`, `my_status_card.dart`.

## 7. Phases 3–4

### 7.1 `org_student_asks` (0111)

`id` PK · `org_id` FK CASCADE not null (index) · `user_id` FK CASCADE not null (index) · `created_by` FK SET
NULL · `kind String(12)` not null · `presentation String(12)` not null default `notice` · `title String(200)`
not null · `body Text` · `fields JSON` (`[{key, label_ar, label_en, kind, options?, case_field?: bool}]`) ·
`doc_keys JSON` · `status String(12)` not null default `open` · `answer JSON` · `answered_at DateTime` ·
`due_at DateTime` · `remind_days JSON` · `reminded JSON` · `meeting_id` FK `cal_meetings.id` SET NULL ·
`source_type String(20)` · `source_id Integer` · `case_id` FK `org_onboarding_cases.id` SET NULL ·
`reviewed_by` FK SET NULL · `reviewed_at DateTime` · `review_note Text` · `created_at`, `updated_at`.
Indexes `(user_id, status)`, `(org_id, status)`.

### 7.2 Phase 3 routes (onboarding router, all additive)

| Route | Right | Notes |
|---|---|---|
| `PATCH /orgs/{o}/onboarding/imports/{batch_id}/rows/{row_id}` | type module `insert`, switch `org.onboarding.import` | `{fields: {key: value}}` → `{row: {id, row_no, state, messages, data, dup_of_row}, counts}`; 409 `batch_not_staged`, 404 `row_not_found` |
| `GET …/imports/{batch_id}` | unchanged | each row gains `id`, `dup_of_row`, `edited` |
| `POST …/imports/{batch_id}/rows/fix` | same as PATCH | `{field, from, to}` → applies one replacement to every row whose value is `from`; → `{changed, counts}` |
| `POST /orgs/{o}/students/{uid}/missing/remind` | type module `update` | → `{sent: true}`; 429 `reminded_recently` (once per 24 h) |
| chain step `need` | `onboarding:update` | accepts `{"user_ids": [int]}` and `{"council_id": int}`; `approve` on a council step needs `{decision_no, decision_date}` (422 `decision_no_required`) |
| type `settings` | | new keys `entry_policy` (`direct | review | invitation | code`, a label over the existing chain / intake / invite settings), `student_code_pattern` now used |

- Student number: tokens `{yy}`, `{yyyy}`, `{program}`, `{level}`, `{seq:N}`; the sequence is per org +
  rendered prefix, taken with a conditional `UPDATE` on a counter in `organizations.settings["lifecycle_seq"]`
  under the org row lock; an existing `student_code` is never overwritten; uniqueness checked in the org.
- New duplicate codes: hard `duplicate_member` for a passport matched through `user_identity_values`
  (`field_key = 'passport'`); soft warnings `duplicate_in_file` (import) and `enrolled_in_sibling_org`.
- Applicant upload / patch allowed when `case.status == 'active'` and the item is in `missing`.
- New preset type keys: `student_equivalent`, `student_technical`, `student_second_degree`,
  `student_affiliated`, `student_special_program`, `student_visiting`; `student_new` gains the field
  `admission_basis`. The duplicated `faculty` key in each preset file is removed.
- `service.activate` writes `admission_route`, `enrol_status`, `enrol_since`, flags `transferred_in`
  (type `student_transfer`) / `affiliated` (type `student_affiliated`) and one event (`via = system`).
- Sweep `features/org/students/sweep.py:run(db, now)` called at the end of `_onboarding_tick`; case events
  `incomplete_reminder` `{n}` and one staff task after `incomplete_max`.
- `GET /orgs/{o}/members` rows gain `missing_count`, `chip` (extra keys).

### 7.3 Phase 4 routes

| Route | Right | Body → answer |
|---|---|---|
| `GET /orgs/{o}/students/asks?status=&uid=&page=` | `students:view` | → `{items: [Ask], …}` |
| `POST /orgs/{o}/students/{uid}/asks` | `students:update`; `presentation = fullscreen` also needs `student_status:update` and `due_at` ≤ 7 days (422 `fullscreen_needs_due`) | `AskIn` → 201 `Ask`; a meeting: 409 `attendees_busy` with `busy` (the calendar's shape) unless `force: true` |
| `POST /orgs/{o}/students/asks/{id}/accept` · `/return` `{note}` · `/cancel` · `/remind` | `students:update` | → `Ask`; 409 `ask_not_answered`, 409 `ask_closed` |
| `GET /orgs/{o}/students/requests?tab=decide|waiting|done&page=` | any source right | → `{counts: {decide, waiting, done}, items: [{id, source: "case"|"decision"|"ask"|"work_item", source_id, student: {id, name, image_url}, title_ar, title_en, at, status, can: {accept, return, reject, meeting, ask}}]}` |
| `GET /api/v1/org/me/asks` | signed in | → `{items: [Ask], fullscreen: Ask|null, popup: Ask|null}` (open asks across my organizations; `fullscreen` oldest first) |
| `GET /api/v1/org/me/asks/{id}` · `POST …/{id}/answer` `{values: {}, confirm: bool}` · `POST …/{id}/documents` (multipart, as the case route) | owner of the ask | → `Ask`; 409 `ask_closed`, 422 `answer_incomplete` |
| `POST /orgs/{o}/complaints/{cid}/meeting` | unchanged right | gains `force`; now 409 `attendees_busy` when the sender is busy and `force` is not set (Q9) |

`AskIn`: `{"kind": "meeting", "presentation": "notice", "title": "…", "body": "…", "fields": [], "doc_keys": [],
"due_at": null, "remind_days": [3, 1], "meeting": {"starts_at", "ends_at", "mode": "online" | "offline", "location"},
"source": {"type": "complaint", "id": 77}, "force": false}`.
`Ask`: the table's columns + `org: {id, name, logo}`, `created_by: {id, name}`, `meeting: {id, starts_at, ends_at, mode, location}`,
`can: {answer, cancel, accept}`.

- Shared helper `features/org/students/meetings.py:create_for_source(db, actor, org, attendee_ids, *, title, notes, starts_at, ends_at, mode, location, dept_id, source_type, source_id, force)`:
  `cal.busy(db, ids, s, e)` → 409 `attendees_busy`, then the same row / attendee / room logic the complaint
  route has today and `cal.notify`.
- A `data` answer whose field has `case_field: true` is stored in `answer` and applied to the case only on
  `accept` (through `onboarding.service.patch_case`); `documents` go straight to the case as `uploaded`.
- `GET /me/home` gains `asks: [{id, org_id, org_name, kind, title, due_at, presentation}]` (always present, max 3).
- Notice kinds: `ask_new`, `ask_reminder`, `ask_answered`, `ask_returned`, `ask_accepted`. Audit:
  `student.ask_created`, `student.ask_answered`, `student.ask_reviewed`, `student.ask_cancelled`.
- Attention: `ORG_KEYS["student_requests"] = ("org.people", "student_requests", "طلبات طلاب تنتظر قرارك", "Student requests waiting for you")`;
  the student's open asks as one `home` item `asks:mine`.
- Kill switch `org.students.asks` → 409 `asks_disabled`; `GET /me/asks` then answers empty lists.
- Front: `student_ask_sheet.dart`, `student_asks_models.dart`, `student_requests_page.dart`, `my_ask_page.dart`;
  `org_must_ack.dart` gains a second source (`GET /me/asks` → `fullscreen`) drawn after must-ack messages;
  `org_services_pages.dart` gains the student strip and two actions on the complaint thread.

## 8. Phase 5: rules

Rule blocks added to `registrar/policy.py:DEFAULT_RULES` (defaults reproduce today's behaviour unless the
RESEARCH default differs and is marked *new default off*). `clean_rules` validates each; unknown keys dropped.

```json
{
  "scale_preset": "gpa4_default",
  "pass": {"course_min_pct": 50, "final_min_pct": null},
  "traditional": {"max_carry": 2, "max_carry_specialised": null, "years_inside": 2,
                  "outside_chances": {"first": 0, "middle": 1, "final": 3}, "five_year_rule": true,
                  "repeat_cap_letter": null, "second_round": false, "promotion_basis": "carry_limit",
                  "promotion_min": null},
  "standing": {"warning_basis": "cgpa", "skip_first_term": false, "reset_on_recover": true, "warning_load_max": 12},
  "dismissal": {"consecutive_warnings": 0, "early_gpa": null, "cgpa_after": null, "max_years": null,
                "unregistered_terms": null},
  "final_chance": {"terms": 2, "summer": true, "min_credits_pct": 75},
  "retake": {"improvement_max": 5, "improvement_count": "best", "failed_cap_letter": null},
  "suspension": {"max_years": 2, "granularity": "year", "request_by_week": null, "exclusions": [],
                 "counts_toward_duration": false, "fees_due": false},
  "postponement": {"max_terms": 4, "not_first_year": true, "auto_conscription": true},
  "reenrolment": {"max_gap_years": 2, "min_cgpa": null, "min_wait_years": null, "counts_as_failure_year": false},
  "withdrawal": {"clearance_required": true, "proxy_allowed": true, "guardian_approval": false},
  "excuses": {"max_accepted": null, "file_within_days": 2}
}
```

Existing keys (`standing.probation_below`, `probation_after_credits`, `retake.allowed_below`, `max_attempts`,
`count`, `traditional.max_carry`, `graduation.min_cgpa`) keep their names and meaning;
`standing.dismiss_after_probations` is read as `dismissal.consecutive_warnings` when the new key is 0.
`suspension.exclusions` values: `level_1`, `repeating`, `outside`, `scholarship_international`,
`unexcused_last_year`, `during_finals`. Sources per key: PLAN §4.3.

- `features/org/students/rules_engine.py`: pure `evaluate(student_facts, rules) -> [Finding]` +
  `after_results(db, org, uids, term)` called at the end of `recompute`'s caller (`approve_grades`) and of
  `promote` (not `dry_run`). A finding is `{decision, to, reason_code, why_ar, why_en, rule}`; standing
  findings are applied (`via = auto`); `dismiss_academic`, `final_chance`, `outside` open an `OrgDecision`
  (kinds of §1, `dedupe = f"{kind}:{uid}:{term_id}"`) unless the matrix says `auto`. Kill switch
  `org.students.auto` off → nothing is applied or opened.
- `promote` result keeps its keys; each `repeat` student gets `acad_standing = repeating`,
  `years_in_level += 1` and an event; `carry` → `carrying`; `promoted` → `regular`, `years_in_level = 1`.
- Routes: `GET /students/rules/presets` (`academic:view`) → `[{key, label_ar, label_en, system, rules}]` from
  `data/lifecycle_presets/*.json` (`law49_traditional_2015`, `credit_engineering`, `credit_law`, `levels_5point`);
  `POST /students/settings/try` (`academic:view`) `{student_id, rules?}` →
  `{facts, findings: [Finding], current: {enrol_status, acad_standing}}` (never writes).
  Rules themselves stay on the existing `GET|PUT registrar/rules`.
- Audit `student.rule_applied` (one row per run with counts, not per student); notice kinds `warning_issued`,
  `standing_changed`, `decision_due` (to the body's holders).

## 9. Phases 6–7

- **Governance categories** seeded per organization on first use (`students/requests.py:ensure_categories`):
  keys `lifecycle.suspend`, `lifecycle.postpone`, `lifecycle.withdraw`, `lifecycle.reenrol`,
  `lifecycle.transfer_out`, `lifecycle.excuse`. A final approval of such an item calls
  `status.apply(…, via="request", source_type="work_item", source_id=item.id)`; the hook is one call from the
  governance "item approved" path, located by the phase-6 backend agent and recorded in §14 before coding.
- **`org_transfer_credits`** (0114): `id` · `org_id` FK CASCADE · `user_id` FK CASCADE · `case_id` FK SET NULL ·
  `source_course String(200)` · `source_code String(40)` · `source_grade String(20)` · `source_credits Float` ·
  `course_id` FK `courses.id` SET NULL · `decision String(12)` (`pending | credited | not_credited`) ·
  `counts_in_gpa Boolean` default false · `decided_by` · `decided_at` · `note Text` · `created_at`.
  Routes `GET|POST /students/{uid}/transfer-credits`, `PATCH|DELETE /students/transfer-credits/{id}`
  (`students:update`; deciding needs `academic:approve`). Audit `student.transfer_credit_*`.
- **Phase 7:** export dataset `org_students` registered in `features/exports/export_datasets.py` (columns
  gated by the same rights as §4.1), `GET /students/status-report?from=&to=` (`student_status:export`).

## 10. Roles (added to `SYSTEM_ROLES`; `ensure_system_roles` creates them on the root organization)

| key | name (ar, en) | permissions |
|---|---|---|
| `student_affairs_staff` | موظف شؤون الطلاب · Student affairs officer | `students`: view, insert, update, import, export · `onboarding`: view · `member_documents`: view · `student_status`: view, insert · `enrollments`: view |
| `registrar` | مسؤول القيد والتسجيل · Registrar | the row above + `students`: approve · `enrollments`: all its actions · `academic`: view · `student_status`: update · `requests`: view, approve |
| `complaints_officer` | مسؤول الشكاوى · Complaints officer | `complaints`: all its actions · `students`: view · `student_status`: view, insert, update · `workflow`: view |
| `student_affairs_head` | مدير شؤون الطلاب · Head of student affairs | `registrar` + `student_status`: approve, export · `onboarding`: update · `complaints`: view · `audit`: view |

The default matrix limits what `update` decides to `resume`, `withdraw`, `deceased` and three flags, so a
complaints officer cannot dismiss or suspend.

## 11. Shared-file additions (lead only)

| File | Addition |
|---|---|
| `sl-back/features/org/core/org_catalog.py` | module + roles (§4.8, §10) |
| `sl-back/features/platform/feature_catalog.py` | §12 keys |
| `sl-back/main.py` | two `include_router` lines |
| `sl-back/features/notifications/live_update_service.py` | `EVENT_STUDENT_LIFECYCLE` |
| `sl-back/features/notifications/attention_service.py` | phase 4 keys |
| `sl-back/features/platform/scheduler_service.py` | phase 3: one call inside `_onboarding_tick` |
| `sl-back/data/help_seed.json`, `data/app_features_guide.json`, `FLUTTER_API_CHANGES.md`, `docs/feature_keys.json` (generated) | §12, §13 |
| `sl-front/lib/main.dart`, `utils/widget/app_navigator.dart`, `utils/live_events.dart` | route, module `org_student`, event name |
| `sl-front/lib/features/org/org_dashboard_screen.dart`, `org_people_page.dart`, `org_v3.dart` | sub-page entry, row tap, error-text merge |
| `sl-front/assets/translation.json` | only the push-facing keys `student_lifecycle_title`, `student_ask_title` (ar + en), if the navigator needs a label |
| `sl-front/test/contract/*.json` | regenerated from `sl-back`: `$PY scripts/contract/export_api_paths.py --front ../sl-front` |
| `sl-front/assets/help/help_index.json` | `dart run tool/gen_help_index.dart ../sl-back/data/help_seed.json` |

## 12. Kill switches and help ids

`feature_catalog.py` `_BASE_FEATURES` rows (key, title_ar, title_en):

| key | title_ar | title_en | server code when off |
|---|---|---|---|
| `org.students` | قسم الطلاب وملف الطالب الموحد | Students section and the unified student file | `students_disabled` |
| `org.students.status` | حالات الطلاب وتغييرها والتراجع عنها | Student statuses, changes and undo | `status_disabled` |
| `org.students.auto` | تطبيق قواعد الحالة تلقائياً من النتائج | Automatic status rules from results | (silent) |
| `org.students.asks` | طلب بيانات أو اجتماع من الطالب | Asking the student for data or a meeting | `asks_disabled` |
| `org.students.missing` | شارة البيانات الناقصة | Missing-data badge | (the app hides the badge) |
| `org.students.rules` | إعدادات الطلاب وقواعد الدراسة | Students and study rules settings | `rules_disabled` |

Help pages (`data/help_seed.json`: one `page_ids` row `{id, file, has_url: false}` and `pages` rows per role
`{page_id, role, title{ar,en}, summary{ar,en}, sections[{key, title, body}]}`):

| id | file | roles | phase |
|---|---|---|---|
| `org.students` | `lib/features/org/students/students_page.dart` | `org_admin`, `org_member` | 1 |
| `org.students.file` | `lib/features/org/students/student_file_page.dart` | `org_admin`, `org_member` | 1 |
| `org.students.status` | `lib/features/org/students/student_status_sheet.dart` | `org_admin`, `org_member` | 2 |
| `org.students.rules` | `lib/features/org/students/student_settings_page.dart` | `org_admin` | 2 |
| `org.students.requests` | `lib/features/org/students/student_requests_page.dart` | `org_admin`, `org_member` | 4 |
| `me.asks` | `lib/features/org/students/my_ask_page.dart` | `student` | 4 |
| `me.status` | `lib/features/org/students/my_status_card.dart` | `student` | 2 |

Features guide keys (`data/app_features_guide.json` `features[]`: `key, group, roles, title_ar, title_en,
summary_ar, summary_en, where_ar, where_en, steps_ar, steps_en` + the kill-switch list, copying the shape of
an existing org entry): `org_students_list` (1), `org_student_file` (1), `org_student_missing_data` (3),
`org_student_status` (2), `org_student_ask` (4), `org_student_requests` (4), `org_student_rules` (5),
`student_my_status` (2), `student_my_asks` (4). `tests/org_v2/e2e_feature_guide.py` must pass.

## 13. `FLUTTER_API_CHANGES.md`

One heading per phase, "## Student lifecycle, phase N (…)", listing each route of this file with its payload
keys and codes in the existing compact style. Written by the lead from this contract after each wave.

## 14. Ownership and test commands per phase

`$PY = D:/platform/nextbrain/back/.venv312/Scripts/python`; back commands run in `_wt/sl-back` with
`PYTHONUTF8=1 DATABASE_URL="sqlite:///C:/Users/ahmed/AppData/Local/Temp/<name>.db"`; front commands in
`_wt/sl-front`. Agents run only their own lines. Nobody runs `dart format`.

**Phase 1**

| Agent | Owns (creates unless marked) | Tests |
|---|---|---|
| B | `data/student_lifecycle_models.py`, `migrations/versions/0110_student_status.py`, `data/org_models.py` (EDIT: the ten columns on `OrgStudentAcademic` only), `features/org/students/__init__.py`, `errors.py`, `file.py`, `timeline.py`, `missing.py`, `status.py` (only `intake_label`, `chip`, enums), `access_log.py`, `api/__init__.py`, `api/org_students_router.py`, `features/org/academic/api/org_registrar_router.py` (EDIT: one `viewed(…, "academic")` call in `students/{uid}/record`), `tests/org_v2/e2e_students_file.py` | `$PY tests/org_v2/e2e_students_file.py` · `$PY tests/org_v2/e2e_onboarding_a.py` · `$PY tests/org_v2/e2e_registrar.py` · `ruff check features/org/students data/student_lifecycle_models.py` |
| F1 | `students_models.dart`, `students_api.dart`, `students_errors.dart`, `students_parts.dart`, `students_page.dart`, `students_missing_sheet.dart`, `test/org/students_models_test.dart`, `test/ui/students_page_layout_test.dart` | `flutter test test/org/students_models_test.dart test/ui/students_page_layout_test.dart` · `flutter analyze --no-fatal-infos --fatal-warnings lib/features/org/students test/org/students_models_test.dart test/ui/students_page_layout_test.dart` |
| F2 | `student_file_models.dart`, `student_file_page.dart`, `student_file_tabs.dart`, `student_timeline.dart`, `students_wiring.dart`, `test/org/student_file_models_test.dart`, `test/ui/student_file_layout_test.dart` | `flutter test test/org/student_file_models_test.dart test/ui/student_file_layout_test.dart` · the same analyze line on its files |
| Lead | §11 files, `0113`, help + guide, `FLUTTER_API_CHANGES.md` | `$PY scripts/contract/export_api_paths.py --front ../sl-front` · `$PY tests/org_v2/e2e_feature_guide.py` · `flutter test test/contract/ test/ui/help_ids_test.dart test/ui/help_index_test.dart test/ui/rtl_icons_test.dart` · the CI analyze command · one PostgreSQL run of `e2e_students_file.py` and of the migration (`nb-pg`, localhost:55432) |

`e2e_students_file.py` must prove: list filters and `summary`; `chip` precedence for one student of each
kind; `missing` groups and `why` for a male Egyptian under 18; timeline order, `before` paging and
`hidden_kinds` for a caller without `complaints`; one `student.file_viewed` row for two opens inside the
window and two rows with `window_minutes = 0`; 404 for a teacher's id; 409 with the switch off; a student
caller is refused; no `perm_version` bump from the access log.

Layout tests use `expectNoLayoutErrors` (320×640 and 1400×900, ar / en, text × 1.3) on `StudentsPageView`
with 0, 1 and 30 rows and long names, `MissingDataView`, `StudentFileView` with every tab, and
`StudentTimelineView` with one item of every kind.

**Phase 2**

| Agent | Owns | Tests |
|---|---|---|
| B | `features/org/students/status.py`, `settings.py`, `notify.py`, router status + settings routes, `features/org/academic/registrar/service.py` (EDIT: `evaluate` block, `ACTIONS["student_status"]`, `graduate` event), `tests/org_v2/e2e_student_status.py` | `$PY tests/org_v2/e2e_student_status.py` · `$PY tests/org_v2/e2e_registrar.py` |
| F1 | `student_status_models.dart`, `student_status_sheet.dart`, `my_status_card.dart`, `students_api.dart` (status methods), `test/org/student_status_test.dart`, `test/ui/student_status_layout_test.dart` | `flutter test` on its two files |
| F2 | `student_settings_page.dart`, `student_matrix_page.dart`, `student_timeline.dart` (undo row), `student_file_page.dart` (header actions), `test/ui/student_settings_layout_test.dart` | `flutter test` on its file + `test/ui/student_file_layout_test.dart` |

**Phase 3**

| Agent | Owns | Tests |
|---|---|---|
| B | `data/onboarding_presets/*.json`, `data/onboarding_models.py`, `0112`, `features/org/onboarding/{importer,service,validation,invite}.py`, `onboarding/api/org_onboarding_router.py`, `features/org/students/sweep.py`, `missing.py` (remind), `tests/org_v2/e2e_onboarding_inline.py`, `e2e_student_missing.py` | those two + `e2e_onboarding_a.py`, `e2e_onboarding_bc.py`, `e2e_onboarding_d.py` |
| F1 | `onboarding_import.dart`, `onboarding_models.dart`, `onboarding_api.dart`, `onboarding_errors.dart`, `test/org/onboarding_models_test.dart`, `test/ui/onboarding_layout_test.dart` | `flutter test` on its two test files |
| F2 | `students_missing_sheet.dart` (in-place upload / edit), `add_student_sheet.dart`, `onboarding_types_page.dart` (entry-policy picker, person / body step), `onboarding_wizard.dart` ("Save and invite"), `test/ui/missing_data_layout_test.dart` | `flutter test test/ui/missing_data_layout_test.dart test/ui/onboarding_layout_test.dart` (after F1 has merged) |

**Phase 4**

| Agent | Owns | Tests |
|---|---|---|
| B | `0111`, `data/student_lifecycle_models.py` (EDIT: `OrgStudentAsk`), `features/org/students/{asks,meetings,requests_inbox}.py`, router ask + inbox + `me` routes, `features/org/services/api/org_services_router.py` (EDIT: the meeting route), `features/home/home_service.py` (EDIT: `asks`), `tests/org_v2/e2e_student_asks.py` | that file + `e2e_complaints_hub.py`, `e2e_calendar.py` |
| F1 | `student_ask_sheet.dart`, `student_asks_models.dart`, `student_requests_page.dart`, `test/org/student_asks_test.dart`, `test/ui/student_ask_layout_test.dart` | its two test files |
| F2 | `org_must_ack.dart`, `my_ask_page.dart`, `features/org/org_services_pages.dart`, `features/home/home_application_card.dart` (asks row), `test/ui/my_ask_layout_test.dart` | its file (there is no must-ack test today: add `test/org/must_ack_asks_test.dart` for the host's second source) |

**Phase 5**

| Agent | Owns | Tests |
|---|---|---|
| B | `features/org/academic/registrar/{policy,service,traditional}.py`, `features/org/students/rules_engine.py`, `data/lifecycle_presets/*.json`, router `rules/presets` + `settings/try`, `tests/org_v2/lifecycle_rules_unit.py` | that file + `e2e_registrar.py`, `e2e_traditional.py` |
| F1 | `student_rules_pages.dart`, `student_scale_editor.dart`, `test/ui/student_rules_layout_test.dart` | its file |
| F2 | `student_requests_page.dart` (recommendation rows; handed over from F1), `student_rules_try.dart`, `features/org/org_registrar.dart` (new code texts), `test/org/student_rules_test.dart` | its file + `test/org/org_registrar_test.dart` |

**Phase 6:** B `features/org/students/requests.py`, `0114`, transfer-credit routes, one governance hook,
`tests/org_v2/e2e_student_requests.py` (+ `e2e_governance.py`); F1 `my_requests.dart`; F2
`transfer_credits_sheet.dart`. **Phase 7:** lead + one agent per remaining item.

Changes to this contract after 2026-11-21: none yet.
