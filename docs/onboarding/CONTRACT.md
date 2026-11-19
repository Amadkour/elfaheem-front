# Member onboarding: contract (D-1200 – D-1219)

This is the single source of truth for back and front. The plan is `PLAN.md` next to this file. If you must deviate, record it in §9 with a reason.

## Owner decisions (2026-11-19)

| ID | Decision |
|---|---|
| D-1200 | A case comes before the member; the member row is created on activation. |
| D-1201 | Approval activates immediately when the type's `settings.auto_activate` is true (the default). |
| D-1202 | National ID / passport number are encrypted at rest with `PII_KEY`. When `PII_KEY` is unset, a key is derived from `SECRET_KEY` and a warning is logged. Lookup uses an HMAC blind index. |
| D-1203 | People with `<module>:approve` may add and approve in one call (`approve_now`). The OLD `POST /orgs/{o}/members` and Excel import stay untouched as legacy paths (no regression risk). The new UI routes through cases. |
| D-1204 | Fees are a `fees` field (`paid / exempt / pending`) plus an optional `fee_receipt` document only. |
| D-1205 | Overdue documents only flag a case; they never auto-suspend it. |
| D-1206 | The Egyptian national-ID check digit is not enforced (the algorithm is unpublished). |
| D-1207 | Identity documents are served only by a permission-checked, audited route, never by `/org/files/<token>`. |

## 1. Tables

Migration `0099_member_onboarding`, `down_revision "0098"`. It creates every table below, so later phases add no migration unless unavoidable (that one would be `0100`).

**`org_member_types`**: `id`; `org_id` FK organizations CASCADE; `key` String(40); `label_ar` / `label_en` String(120); `base_role` String(30) (one of `ORG_MEMBER_ROLES` minus org_admin); `module` String(20) (`students | teachers | staff`); `fields` JSON; `documents` JSON; `chain` JSON; `settings` JSON; `preset_key` String(40) null; `active` Bool default true; `sort` Int; `intake_code_hash` String(64) null, indexed; `created_at` / `updated_at`. Unique `(org_id, key)`.

**`org_onboarding_cases`**:
- `id`, `org_id`, `type_id` FK, `type_key`
- `status` String(20)
- `step` Int default 0 (index into the chain)
- `source` String(12) (`manual | excel | invite | intake | self`)
- `subject_user_id` FK users null
- `full_name` String(200), `name_en` String(200) null, `name_norm` String(200) indexed
- `email` String(160) null, `phone` String(32) null
- `nid_kind` String(10) null (`national_id | passport`), `nid_enc` Text null, `nid_hash` String(64) null, `nid_last4` String(4) null
- `nationality` String(2) default "EG"
- `birth_date` Date null, `gender` String(1) null (`m | f`)
- `data` JSON (every other field value, by key)
- `dept_id`, `program_id` (null, FK SET NULL)
- `conditional` Bool default false, `due_at` DateTime null
- `decision_reason` Text null
- `created_by`, `submitted_at`, `decided_by`, `decided_at`, `activated_at`
- `member_id` FK org_members SET NULL, `invitation_id` FK org_invitations SET NULL, `batch_id` FK org_import_batches SET NULL
- `created_at`, `updated_at`
- Indexes `(org_id, status)` and `(org_id, nid_hash)`.

**`org_case_documents`**: `id`, `case_id` FK CASCADE, `org_id`, `req_key` String(40), `version` Int, `current` Bool, `status` String(12) (`uploaded | verified | rejected | deferred | waived`; a missing document has no row), `bucket`, `object_key`, `file_name`, `mime`, `size` Int, `uploaded_by`, `uploaded_at`, `verified_by`, `verified_at`, `note` Text, `due_at`.

**`org_case_events`**: `id`, `case_id` FK CASCADE, `org_id`, `actor_id`, `kind` String(30), `from_status`, `to_status`, `reason` Text, `details` JSON, `created_at`. Append-only.

**`org_import_batches`**: `id`, `org_id`, `type_key`, `created_by`, `file_name`, `mode` String(10) (`submit | invite | draft`), `status` (`staged | confirmed | expired`), `counts` JSON, `created_at`, `expires_at` (+24 h).

**`org_import_rows`**: `id`, `batch_id` FK CASCADE, `row_no`, `data` JSON, `state` (`ok | warning | error`), `messages` JSON `[{field, code, ar, en}]`, `case_id` null.

**Alter**: `org_invitations.case_id` (FK SET NULL, null) and `org_members.onboarding_case_id` (null).

## 2. Type config (JSON shapes)

```json
// field
{"key":"national_id","kind":"national_id|text|textarea|number|date|select|multiselect|checkbox|email|phone|nationality|program|department|level",
 "label_ar":"…","label_en":"…","required":"mandatory|optional|conditional",
 "when":{"gender":"m","nationality":"EG","age_min":18,"age_max":30},
 "options":[{"value":"…","label_ar":"…","label_en":"…"}],"help_ar":"…","help_en":"…",
 "group":"identity|personal|academic|appointment|guardian|other","system":true}

// document
{"key":"photo","label_ar":"…","label_en":"…","required":"mandatory|optional|conditional","when":{…},
 "accept":["jpg","png","pdf"],"max_mb":5,"photo":{"min_px":600,"aspect":"3:4"}|null,
 "original_needed":false,"allow_later":true,"default_due_days":30}

// chain step
{"key":"dept","label_ar":"مجلس القسم","label_en":"Department council",
 "need":{"module":"students","action":"approve"} | {"org_role":"dept_head","scope":"case_dept"}}

// settings
{"auto_activate":true,"student_code_pattern":null,"invite_days":14,"purge_rejected_days":180,"guardian_under":18}
```

- **System fields** are always present and map to case columns: `full_name`, `name_en`, `nid_kind`, `national_id` (or `passport_no`), `nationality`, `birth_date`, `gender`, `email`, `phone`, `dept_id`, `program_id`. All others go into `data`.
- **`when`** semantics: every key must match. `age_*` is computed from `birth_date`. `nationality: "!EG"` means not Egyptian.
- **Presets**: `back/data/onboarding_presets/{egypt_public,egypt_private,azhar,institute}.json`, each a list of types. Type keys: `student_new`, `student_transfer`, `student_postgrad`, `student_international`, `teaching_assistant`, `faculty`, `admin_staff`. Content per PLAN.md §2.2 (military forms 2 جند / 6 جند conditional on m + EG + age 18–30; passport + equivalency on `!EG`; guardian when age < 18; the azhar preset adds the Azhari secondary certificate instead of الثانوية العامة; the private preset drops the تنسيق card).
- **Default chains**: students = 1 step `{students:approve}`. Postgraduate = 2 steps: dept council `{org_role: dept_head, scope: case_dept}`, then faculty council `{students:approve}`. TA and faculty = dept head, then `{teachers|staff:approve}`. Admin staff = `{staff:approve}`.
- An org with no rows gets the `egypt_public` preset seeded lazily on the first `GET types`.

## 3. Permissions

- `org_catalog`: add `"approve"` to the actions of `students`, `teachers`, `staff`. New module `onboarding` (actions `view`, `update`; update = configure types and intake links; group people). New module `member_documents` (actions `view`).
- On a case of type T (module M):

| Operation | Needs |
|---|---|
| view list or case | `M:view` |
| create | `M:insert` |
| edit while draft / needs_correction, claim, request correction | `M:update` |
| approve the current step | the step's `need` (`org_role` = an active `OrgRoleAssignment` of that role on `case.dept_id`) |
| reject | any `M:update` (reason required) |
| documents | open the file: `member_documents:view` OR the case's own subject; verify / reject / waive / defer: `M:update` |

- `ctx.is_admin` (org_admin) passes everything; acting on a step it doesn't hold is audited as `onboarding.override`.

## 4. State machine

```
draft → submitted (submit)            submitted → under_review (claim, or the first review action)
under_review → needs_correction (request-correction, reasons)   needs_correction → submitted (resubmit)
under_review → under_review (approve a non-final step: step += 1)
under_review | submitted → approved (approve the final step; conditional = any required doc deferred or missing with allow_later)
under_review | submitted | needs_correction → rejected (reason)
approved → active (activate; automatic when settings.auto_activate)
draft | submitted | under_review | needs_correction → withdrawn (subject or M:update)
```

- `submit` validates the required fields and documents. A document whose `allow_later` is true may be missing or deferred: the case then submits, but approval makes it `conditional` with `due_at` (the earliest document due date).
- Any other transition is answered 409 `bad_transition`.
- **Activation**:
  - If there is no `subject_user_id`, create the account as `create_member` does (generated password returned ONCE in the activate / approve response as `generated_password`).
  - If there is a subject, add the membership directly (the person applied themselves, so consent is given).
  - Then: `OrgMember` with `role = base_role`, `joined_via = "onboarding"` (if `joined_via` has a length or enum limit, use `"manual"` and record it in §9), `onboarding_case_id`, the program / level / dept placement as the invitation accept does.
  - Write the national ID into `user_identity_values` (`field_key "national_id"`, the same norm).
  - Audit + events.

## 5. Validation (back `features/org/onboarding/validation.py`, mirrored in Dart `lib/features/org/onboarding/onboarding_rules.dart`)

- **`parse_egyptian_nid`**:
  - Normalise Arabic-Indic and Persian digits; strip spaces and dashes.
  - Exactly 14 digits; century digit 2 → 1900, 3 → 2000.
  - YYMMDD must be a valid date that is not in the future.
  - Governorate code ∈ {01,02,03,04,11,12,13,14,15,16,17,18,19,21,22,23,24,25,26,27,28,29,31,32,33,34,35,88}.
  - Gender = digit 13 odd → m.
  - Returns `{birth_date, gender, governorate}` or an error code `nid_format | nid_date | nid_gov`.
- If the typed `birth_date` / `gender` differ from the ID → 422 `nid_mismatch`.
- Passport: 5–20 alphanumerics.
- Phone: EG mobile `^01[0125]\d{8}$` after normalisation (+20 / 0020 prefixes accepted), else E.164 `^\+\d{8,15}$`.
- **`normalize_ar_name`**: unify أإآٱ→ا, ة→ه, ى→ي, ؤ→و, ئ→ي; strip tatweel and diacritics; collapse spaces; `عبد ال` → `عبدال`; lowercase Latin.
- **Duplicates** (create, update, import):
  - Same `nid_hash` in an open or active case, or on a live member of the org → 409 `duplicate_case` / `duplicate_member` with `{existing_id}`.
  - Soft (`warnings[]` in the response, never blocking): same email, same phone, same `name_norm` + `birth_date`, a previous rejected / withdrawn case (`reapplicant`, with its id).
- **Files**: real type sniffed with `features/org/governance/attachments.sniff` (magic bytes), checked against `accept` + `max_mb` (hard cap 20 MB). Images are re-encoded (Pillow, strips EXIF). A photo below `min_px` → warning `photo_small`, not an error.
- Error body = the existing org error shape (`_err(status, code, ar, en)`, bilingual). Codes:
  `nid_invalid, nid_mismatch, phone_invalid, email_invalid, missing_required (detail.fields / detail.documents lists), duplicate_case, duplicate_member, bad_transition, step_forbidden, doc_type, doc_too_large, type_inactive, type_not_found, case_not_found, batch_expired, intake_closed, onboarding_disabled`.

## 6. API (`/api/v1/org`, router `features/org/onboarding/api/org_onboarding_router.py`)

### Staff

| Method & path | Body / query → response |
|---|---|
| `GET /orgs/{o}/onboarding/presets` | → `[{key, label_ar, label_en, types:[key]}]` |
| `GET /orgs/{o}/onboarding/types` | → `[TypeOut]` (seeds the preset lazily) |
| `PUT /orgs/{o}/onboarding/types/{key}` | whole TypeIn (whole-object replace), `onboarding:update` |
| `POST /orgs/{o}/onboarding/types` | new custom type |
| `POST /orgs/{o}/onboarding/types/from-preset` | `{preset, replace:bool}` |
| `GET /orgs/{o}/onboarding/summary` | → `{counts:{status:n}, overdue:n, by_type:{key:{status:n}}}` |
| `GET /orgs/{o}/onboarding/cases` | `?status=&type=&q=&overdue=1&page=&page_size=` → `{items:[CaseRow], total}`; `q` matches name_norm, email, phone, nid last4 or exact full nid via hash |
| `POST /orgs/{o}/onboarding/cases` | `{type_key, fields:{…}, submit:bool, approve_now:bool}` → CaseOut + `warnings` |
| `GET /orgs/{o}/onboarding/cases/{id}` | → CaseOut (includes `events[]`) |
| `PATCH /orgs/{o}/onboarding/cases/{id}` | `{fields:{…}}` (draft / needs_correction / under_review by staff) |
| `POST /orgs/{o}/onboarding/cases/{id}/submit` | |
| `POST …/claim` | |
| `POST …/request-correction` | `{reason, fields:[{key, note}], documents:[{key, note}]}` |
| `POST …/approve` | `{note}` → CaseOut (+ `generated_password` once if activated with a new account) |
| `POST …/reject` | `{reason, reason_key}` |
| `POST …/activate` | |
| `POST …/withdraw` | |
| `POST /orgs/{o}/onboarding/cases/{id}/documents` | multipart `req_key`, `file` → DocOut (+ warnings) |
| `PATCH /orgs/{o}/onboarding/documents/{doc_id}` | `{action: verify\|reject\|waive\|defer\|reopen, note, due_at}` |
| `GET /orgs/{o}/onboarding/documents/{doc_id}/file` | → 307 to a 60 s presign (audit `onboarding.document_viewed`) |
| `GET /orgs/{o}/onboarding/cases/{id}/nid` | → `{value}` (unmask, `member_documents:view`, audited) |
| `GET /orgs/{o}/onboarding/reject-reasons` | → preset bilingual reasons |

**Phase B, import**:
- `GET /orgs/{o}/onboarding/templates/{type_key}` → xlsx (headers from the type's fields, ar + en, dropdown validation, instructions sheet).
- `POST /orgs/{o}/onboarding/imports` (multipart `file`, `type_key`, `mode`) → BatchOut `{id, type_key, mode, counts:{ok, warning, error}, rows:[{row_no, state, data, messages}], expires_at}`. Accepts xlsx and csv (utf-8, utf-8-sig, cp1256); 5000 rows, 8 MB.
- `GET /orgs/{o}/onboarding/imports/{id}` → BatchOut.
- `POST /orgs/{o}/onboarding/imports/{id}/confirm` `{include_warnings:bool}` → `{created, skipped, invited, case_ids}`.
- `GET /orgs/{o}/onboarding/imports/{id}/report` → xlsx of the error / warning rows + a "what to fix" column.

**Phase C, invitations and intake**:
- `POST /orgs/{o}/onboarding/cases/invite` `{case_ids:[…]}`: for each draft case with an email or phone, create an `OrgInvitation` (reusing `invitations.create_invitations` internals) with `case_id` set → `{invited, skipped:[{id, reason}]}`. Import mode `invite` calls the same thing.
- `PUT /orgs/{o}/onboarding/types/{key}/intake` `{enabled, valid_until, capacity}` → `{code, link}` (the code is shown once; regenerate = PUT again with `rotate:true`).
- Accepting an invitation that has `case_id` sets `case.subject_user_id = user` and creates NO membership (activation does). The accept response gains `onboarding_case_id`.

### Applicant (`/api/v1/org/me/onboarding`, signed-in subject only)

- `GET /me/onboarding` → `[CaseOut-lite + org name/logo]`.
- `GET /me/onboarding/{id}`, `PATCH /me/onboarding/{id}` `{fields}` (draft / needs_correction only; system fields set by staff are locked: `locked_fields[]` in CaseOut).
- `POST /me/onboarding/{id}/submit`, `POST /me/onboarding/{id}/withdraw`.
- `POST /me/onboarding/{id}/documents` (multipart), `GET /me/onboarding/documents/{doc_id}/file`.
- `GET /public/onboarding/intake/{code}` → `{org:{id, name, logo}, type:{key, label_ar, label_en}, open:bool}` (no auth, throttled).
- `POST /me/onboarding/intake/{code}` → creates a draft case `source=intake` for the signed-in user → CaseOut.

### Shapes

- **CaseRow**: `{id, type_key, type_label_ar, type_label_en, status, step, step_label_ar, step_label_en, source, full_name, nid_masked, email, phone, conditional, due_at, overdue, missing_count, submitted_at, updated_at}`.
- **CaseOut** = CaseRow + `{name_en, nid_kind, nationality, birth_date, gender, dept_id, program_id, data, decision_reason, corrections:{fields:[{key, note}], documents:[{key, note}]}, required:{fields:[key], documents:[key]}, missing:{fields:[key], documents:[key]}, documents:[DocOut], events:[EventOut], member_id, locked_fields:[key], can:{edit, submit, claim, approve, reject, request_correction, activate, withdraw, view_documents, unmask}, type: TypeOut}`.
- **DocOut**: `{id, req_key, status, file_name, mime, size, version, uploaded_at, verified_at, note, due_at, file_path}`, where `file_path` is the relative API path of the file route.
- **EventOut**: `{id, kind, from_status, to_status, reason, details, actor_name, created_at}`.
- **TypeOut**: `{key, label_ar, label_en, base_role, module, fields, documents, chain, settings, preset_key, active, sort, intake:{enabled, valid_until, capacity, used}}`.

Dates are ISO strings in naive UTC (front `orgParseUtc`).

## 7. Notifications, live events, kill switches, help

- `notify_users` to the subject (if any) on: `submitted` (receipt), `needs_correction`, `approved` (conditional mentions the due documents), `rejected` (reason), `activated`. To step approvers on submit and step advance (users holding the need; for org_role, the dept heads). Bilingual title and message by the user's language, the way existing org notifications do.
- **Live event** `onboarding` (add it to `live_update_service.py` names; payload `{org_id, case_id, status}`) emitted on every transition. Attention tab key `org_onboarding` (server `TABS` + front `AttentionTabs`): count of cases the viewer can act on (submitted + under_review at their step, + needs_correction for applicants).
- **Phase D sweep** `onboarding_daily` (wherever the existing daily org sweeps run): reminders at due −7 / −3 / −1 days, overdue flag + notify reviewers, expire staged batches, purge the documents of rejected / withdrawn cases older than `purge_rejected_days`.
- **Kill switches** (`feature_catalog.py`): `org.onboarding`, `org.onboarding.import`, `org.onboarding.invite`, `org.onboarding.intake`.
- **Help page ids**: `org.onboarding`, `org.onboarding.types`, `org.onboarding.import`, `me.onboarding`.
- **Features guide**: one entry per entry method + review + types editor + applicant side.
- **API docs**: `FLUTTER_API_CHANGES.md` gets a section for each phase.

## 8. Front layout

`lib/features/org/onboarding/`:

| File | Contents |
|---|---|
| `onboarding_models.dart` | plain parse classes |
| `onboarding_api.dart` | `OnboardingApi` over `ApiClient` |
| `onboarding_rules.dart` | the Dart mirror of §5 + the `when` evaluator |
| `onboarding_page.dart` | Admissions & appointments: stage tabs, search, type filter, primary "Add" |
| `onboarding_wizard.dart` | steps by field group + documents + review; autosave via PATCH; used by staff AND applicant |
| `onboarding_review.dart` | master-detail case view, document checklist with preview, timeline, actions |
| `onboarding_types_page.dart` | type list + editor + preset picker |
| `onboarding_import.dart` | phase B |
| `onboarding_applicant.dart` | phase C: "My application" card + page + intake landing |

Entry: a `DashboardItem` in the org dashboard / workspace People group (where Members and Invitations live), gated by `org.onboarding` and `M:view` for any of the three modules. Deep links `/org/<o>/onboarding/<caseId>` and `/onboard/<code>` (intake) through `AppNavigator` / `onGenerateRoute`, both stripped of `/app/` like the others.

## 9. Deviations log

(append here: date, who, what, why)

- 2026-11-19, back phase A (onb-back):
  - Preset files are objects `{key, label_ar, label_en, types:[TypeIn…]}`, not a bare list (GET presets needs the labels).
  - Back code is split in `features/org/onboarding/`: `service.py` (types, cases, state machine, activation), `documents.py`, `notify.py` (step holders, notifications, live event, attention counts), `validation.py`.
  - ORM: `org_invitations.case_id` and `org_members.onboarding_case_id` are plain Integer columns in the models (no ORM FK, avoids an import cycle); the migration gives `org_invitations.case_id` the FK (SET NULL). `joined_via = "onboarding"` fits String(10).
  - Extra error codes: `invalid_value {field}` (422, a field value of the wrong kind / unknown department or program), `field_locked {field}` (422, the applicant changed a staff-filled identity field), `type_exists` (409), `preset_not_found` (404), `bad_action` (422), `storage_unavailable` (503). `nid_invalid` carries `reason` = `nid_format | nid_date | nid_gov | passport_format`; `nid_mismatch` carries `fields:[birth_date|gender]`; `doc_too_large` is 413; a missing / refused file type is `doc_type` (422).
  - `type.settings.intake` holds the intake link state (phase C); a type PUT keeps it. TypeOut moves it to `intake`.
  - `dept_head` with `scope: case_dept` is satisfied by an assignment on the case's department or an organization-wide one (dept_id NULL). A holder of an org-role step may open / list the cases of that step even without `M:view` (`can_enter`).
  - The document file route's presigned link lives 60 s (own `documents.presign_url`, storage seam `attachments.put_bytes`); the identity-number read is `GET …/cases/{id}/nid` and is audited as `onboarding.nid_viewed`.
  - Users have no stored language: notifications carry the Arabic title and the message in both languages (Arabic line, then English line).
  - `member_documents` is left out of the read-all `viewer` system role (identity documents are sensitive).
  - A conditional approval writes `deferred` document rows (no file) with `due_at` for every outstanding `allow_later` document; the applicant (or staff) can still upload them while the case is `approved` / `active` and `conditional`.
  - Presets: `allow_later` is true only for original-needed documents, military forms, fee receipt, residence permit, security clearance, course descriptions, coordination card, research protocol and promotion decision; birth certificate, ID copy and photo block submission.
  - Not done in phase A (as scoped): invitations (`cases/invite`, `case_id` hand-over on accept), intake routes, imports / templates, `onboarding_daily` sweep, features-guide entries and help pages.


### Phase A (front), 2026-11-19

1. **List stages** (`OnbStage`): the page sends a comma list in `status=`: To review `submitted,under_review`, Needs correction `needs_correction`, Drafts `draft`, Done `approved,active,rejected,withdrawn`. Conditional sends `status=approved,active&conditional=1`: the contract's list query has no `conditional` filter, so the back end must accept a comma-separated `status` and `conditional=1` (or tell the front to change). The Conditional tab count is read from `summary.counts.conditional` when the server sends it, otherwise no number is shown.
2. **Document preview**: `GET …/documents/{id}/file` answers 307. Images are read with `getBytes` (Dio follows the redirect) and drawn in an in-app zoomable dialog; PDFs and anything else read the `Location` header (redirect not followed) and open it through `openExternalLink`. The app has no in-app PDF viewer. If the redirect carries the Authorization header to the presign host the back end must not require it to be absent (the request goes through `ApiClient`).
3. **"Will bring later"** is a client-side marker only (a document whose `allow_later` is true may be missing at submit, §4); the front never calls `defer` on a document that has no row. Staff may defer/waive a document that has been uploaded.
4. **Guardian step** appears when the type has any guardian-group field visible for the entered values (its `when` matches), not by a separate "required" test; optional guardian fields without a `when` therefore also show the step.
5. **Wizard first save** creates the case with `POST cases` (no `submit`) on the first step change that has data, then `PATCH` with only the changed keys. "Submit and approve" is `submit` then `approve` (two calls) for staff holding `<module>:approve`, not `approve_now`.
6. **National ID in edit**: the server only returns `nid_masked`; the wizard shows it and sends `national_id` only when the person typed a new one. `nid_kind` is sent as `national_id` / `passport` with it.
7. **Reject reasons** are read from `GET reject-reasons` as a list (or `{items}`) of `{key, label_ar, label_en}`.
8. **Kill switch / help ids**: `org.onboarding` (feature), help ids `org.onboarding` and `org.onboarding.types`. Test snapshots were not regenerated: `test/contract/api_paths_test.dart` (22 routes), `feature_keys_test.dart` (`org.onboarding`) and `test/ui/help_ids_test.dart` carry known-missing entries "onboarding phase A, snapshot regenerated at merge"; delete them after the regeneration (the tests fail when an entry is stale).
9. Attention tab `org_onboarding` is added to the People section's badge keys; live event name `onboarding` is in `LiveEvents.serverTypes`.
10. Not in phase A: deep links `/org/<o>/onboarding/<caseId>` and `/onboard/<code>` in `AppNavigator` / `onGenerateRoute`; Excel import and "Invite people" are shown disabled ("Coming soon") in the Add dialog.
