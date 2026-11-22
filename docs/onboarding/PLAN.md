# Member onboarding for organizations: plan (D-1200 – D-1219 reserved)

Status: **APPROVED 2026-11-19** (owner: "go with the best approach"), recommendations taken for all 4 questions. Contract: CONTRACT.md.
Branch when approved: `feature/member-onboarding` in both repos, cut from `origin/production`
(front `125c4ebf`, back `d508919`, last migration `0098`).

---

## 0. Inventory: what already exists (verified on origin/production)

| Area | What exists | Where (back unless noted) |
|---|---|---|
| Member roles | `org_admin, teacher, teacher_assistant, admin_assistant, student`; statuses `active, pending, rejected, suspended, expired` + derived `scheduled` | `data/models.py:2880-2886`, `features/org/core/membership.py` |
| Fine-grained rights | `OrgRole` bundles (dept_head, …), `OrgRoleAssignment` (org / dept, time-bound), `OrgUserGrant` (deny wins); modules × actions (`students`, `teachers`, `staff`, `requests`, `forms`, `audit`, … × view/insert/update/approve/export) | `data/org_models.py`, `org_catalog.MODULES`, `org_ctx(module, action)` |
| Structure | org tree (university → faculty → dept), `OrgDepartment`, `OrgProgram` (academic departments), levels, `OrgStudentAcademic` | `data/org_models.py` |
| Member profile | `OrgMember`: role, status, `student_code`, `joined_via`, window, program, level, cohort, `academic_rank`, `profile_verified_at/by` | `data/models.py` |
| Manual add | `POST /orgs/{o}/members`, one flat form, member goes straight to `active` | `org_admin_router.py`; front `org_member_form.dart` |
| Excel import | template / import / export per kind (students, teachers, staff, …), openpyxl, 5000 rows, 8 MB, per-row savepoint, `{created, linked, skipped, errors}`; **no preview, no CSV, no approval** | `features/org/services/org_excel_service.py`; front `org_people_page.dart` |
| Join codes and requests | hashed codes with limits, approval queue (`pending` member), unit-level `OrgJoinPolicy` + `OrgJoinRequest` with eligibility fields | `join_service.py`, `org_join_router.py` |
| Invitations | `OrgInvitation` (sha256 token, expiry, `member_spec`, consent for existing accounts), `/i/<token>` link, e-mail only (no SMS provider) | `features/org/core/invitations.py`, migration 0048; front `org_invitations*.dart` |
| Dynamic forms | `OrgForm` field types text…file; `file` = list of URLs, not bound to uploads; phone / date not validated | `features/org/services/forms.py`; front `org_dynamic_form.dart` |
| Identifiers | super-admin registry `identity_fields` (national_id 14 digits, academic_id), `user_identity_values` with a normalised `norm` for uniqueness | `data/identity_models.py`, `features/exams/identity_service.py` |
| Files | private MinIO bucket, magic-byte checks on work attachments, signed bearer links `/org/files/<token>` (7-day expiry, **not permission-checked**) | `org_files_router.py`, `file_links.py` |
| Audit / notify | `OrgAuditLog` append-only (DB trigger), `audit()`, `notify_users` (push + e-mail + attention event) | `org_service.py` |

**Gaps this job fills:** no per-type intake (new / transfer / postgraduate / TA / faculty), no documents per person, no review states between "pending" and "active", no Egyptian national-ID logic (birth date, gender, governorate), duplicates matched by e-mail only, no import preview, and identity documents would be readable by anyone holding a link.

---

## 1. Research summary

**New undergraduates (Egyptian public universities).** Cairo University faculties ask for the original الثانوية العامة certificate plus copies, a recent computerised birth certificate, the تنسيق nomination card (بطاقة الترشيح), personal photos (6–8, name written on the back), the national ID copy, a student data form, and **forms 2 جند and 6 جند for male students only**. Each faculty sets its own counts and whether it wants originals or copies. A medical exam at the student hospital is a separate step booked online. → *The document list is per faculty, conditional on gender and nationality, and partly "bring the original later".*
Sources: [Elwatan: required papers](https://www.elwatannews.com/news/details/4989286), [Masrawy 2026](https://www.masrawy.com/news/news_egypt/details/2026/9/7/3044496/بالأوراق-والشروط-رابط-التقديم-في-كليات-جامعة-العاصمة-), [Elwatan: Alexandria Law](https://www.elwatannews.com/news/details/7568595), [Cairo University medical exam papers](https://www.egypttelegraph.com/article/177985/).

**Transfer students (محولون).** A certified transcript (بيان درجات), an enrolment certificate (شهادة قيد), course descriptions for the **academic clearance (المقاصة العلمية)** that decides which courses are credited, and the student's and guardian's ID. If the course content is missing, transfers from abroad are cancelled after a 3-month grace period. → *Conditional acceptance with a deadline, and a per-course equivalency step.*
Sources: [Akhbar El Yom: Cairo transfer rules](https://akhbarelyom.com/news/newdetails/4669716/1/7-شروط-لتحويل-الطلبة-إلى-كليات-جامعة-الق), [Youm7: returning students](https://www.youm7.com/5700889), [study-in-egy transfer rules](https://study-in-egy.org/?p=11451).

**Postgraduates.** Application form, the original bachelor's certificate, grade statements for all four years (for pre-master's), birth certificate and national ID. The file goes to the **department council first, then the faculty council**: registration of the research plan (protocol) and supervisor nomination are approved there. → *A multi-step approval chain.*
Sources: [Mansoura Science MSc file](https://scifac.mans.edu.eg/images/files/Postgraduate/2021/MSC_supplies.pdf), [Tanta registration and supervision](https://tqac2.tanta.edu.eg/admin-cp/uploads/نوعية/mosss2025/الآليات/آلية%20التسجيل%20والاشراف.pdf), [Elbalad: Ain Shams postgraduate](https://www.elbalad.news/6123807).

**TAs and faculty.** Under Law 49/1972 and its executive regulation (decree 809/1975), the chain is: department council nominates → faculty council approves → the university president issues the appointment decision. Alexandria publishes a faculty-affairs directory of these procedures. Typical file: degrees, transcripts, CV, national ID, photos, rank, department, publications for promotion.
Sources: [Benha: selection mechanism](https://www.fnur.bu.edu.eg/images/ekhtyar.pdf), [Alexandria faculty affairs directory](https://www.alexu.edu.eg/images/pdf/Directory%20of%20Faculty%20Members%20Affairs.pdf), [Law 49/1972 text](https://manshurat.org/node/68812).

**International students (وافدون).** Passport instead of the national ID, an **equivalency certificate (معادلة)** of the foreign secondary or bachelor's degree, an authenticated birth certificate, photos, legalised documents, and a residence permit with an expiry date.
Sources: [Cairo Medicine: foreign students](https://medicine.cu.edu.eg/index.php/en/postgraduate/regulations-of-registration/118-procedures-for-egyptian-foreign-students), [Assiut: international applicants](https://aun.edu.eg/student/node/247), [Egyptian Streets 2026 guide](https://egyptianstreets.com/2026/09/08/study-in-egypt-2026-all-you-need-to-get-started/).

**International staff reference.** UK and US universities make identity / right-to-work checks a precondition before any system account is created, and route faculty hires through academic affairs before HR while staff hires skip that step. They also keep separate checklists for the administrator and the newcomer.
Sources: [Staffordshire HR checklist](https://staffs.ac.uk/onboarding/before-you-start/hr-checklist), [Marshall onboarding routing](https://www.marshall.edu/human-resources/files/Onboarding-Form-Instructions.pdf), [Yale faculty onboarding](https://facultyadmin.yale.edu/onboarding-procedures-faculty-arrivals).

**Design conclusions.**
1. Requirements differ per institution, per faculty and per year, so every list is data (presets), never code.
2. Many items are conditional (male + Egyptian → military forms; foreign → passport + equivalency).
3. Real offices accept people with documents still owed. "Conditionally approved, documents due by X" is the normal case, not an exception.
4. Approval is a chain of councils or offices, and the chain differs by member type.
5. The person usually supplies the documents themselves, so self-completion by invitation is the main path, and the admin reviews.

---

## 2. The plan

### 2.1 Roles and permissions

These reuse the existing module × action rights, with no new role model. Each member type points at the module that already guards it.

| Member type (preset key) | Base `OrgMember.role` | Module | Add (insert) | Review | Approve (final step) |
|---|---|---|---|---|---|
| `student_new` / `student_transfer` / `student_postgrad` / `student_international` | student | `students` | registrar / admissions staff | registrar | per chain (default: student affairs head; postgraduate: dept head → faculty council secretary) |
| `teaching_assistant` | teacher_assistant | `staff` | faculty affairs | dept head (OrgRole `dept_head` of the target dept) | dean / org_admin |
| `faculty` | teacher (+ `academic_rank`) | `teachers` | faculty affairs | dept head | dean / org_admin |
| `admin_staff` | admin_assistant | `staff` | HR / org_admin | — | org_admin |

- New action **`review`** on `students` / `teachers` / `staff` (catalog addition). `approve` already exists.
- New module **`onboarding`** with `configure` (edit types, fields, documents, chains) and `view_documents` (open identity documents). Viewing a case does not imply reading its documents (least privilege).
- **Approval chain per type** is an ordered list of steps. Each step is `{label, who: {module, action} | {org_role, scope: target_dept}}`. Any holder of the step's right may act, and an org_admin may act on any step (audited as an override).
- People with `approve` keep a **"quick add" fast path**: the current manual add and import create the case and approve it in one go, audited. This consolidates the old flow rather than removing it.

### 2.2 Configurable member types, fields and documents

A new table, `org_member_types`, holds one row per org and type:

- **`fields`**: the existing `forms.py` schema plus new kinds: `national_id`, `date`, `phone` (validated), `nationality`, `select_program`, `select_dept`, `select_level`, `guardian` (group). Each field has `required: mandatory | optional | conditional` with a small rule language: `{"if": {"gender": "male", "nationality": "EG"}}`.
- **`documents`**: `{key, label_ar, label_en, required (same three-way rule), accept: [pdf, jpg, png, …], max_mb, photo: {min_px, aspect, background: plain} | null, original_needed: bool, allow_later: bool, default_due_days}`.
- **`chain`**: the approval steps (§2.1).
- **`settings`**: auto-activate on approval, the student-code pattern, invitation expiry, and how many days rejected cases' documents are kept.

**Presets**, as JSON files in `back/data/onboarding_presets/`: *Egyptian public university*, *private / national (أهلية) university*, *Azhar*, *institute*. An org picks one at setup or later. The preset is **copied** into its rows and then fully editable. "Reset to preset" shows a diff. No institution rule is hard-coded.

Default document set for `student_new` (public preset):

| Document | Rule | Accepted |
|---|---|---|
| الثانوية العامة certificate | mandatory, original later | pdf / jpg, 10 MB |
| Birth certificate (computerised) | mandatory | pdf / jpg |
| National ID (front + back) | mandatory if Egyptian | jpg / pdf |
| Passport | mandatory if foreign | jpg / pdf |
| Equivalency (معادلة) | mandatory if foreign | pdf |
| تنسيق nomination card | optional (public preset only) | jpg / pdf |
| Personal photo | mandatory: 4:3 portrait, ≥ 600 px, plain background (warning only) | jpg / png, 5 MB |
| 2 جند / 6 جند | mandatory if male + Egyptian + age 18–30 | pdf / jpg |
| Medical exam result | optional, may arrive later | pdf |
| Fee receipt | optional (status field `fees: paid / exempt / pending`) | pdf / jpg |

Transfers add the transcript, enrolment certificate, course descriptions and an **equivalency table** (structured: course → credited course / not credited, set by the reviewer). Postgraduates add the bachelor's certificate, transcripts, research protocol and a supervisor (pick a faculty member). TAs and faculty add degrees, CV, rank, department, appointment decision number and date, and publications (optional).

### 2.3 Workflow and statuses

The core concept is an **onboarding case (ملف التحاق)**, not a member. The member row is created only when the case becomes active, so a half-done intake never pollutes rosters, schedules or counts.

```
draft ──submit──▶ submitted ──claim / first step──▶ under_review
under_review ──request correction (reasons per field / document)──▶ needs_correction ──resubmit──▶ under_review
under_review ──approve last step──▶ approved  (or approved_conditional: documents owed, due date)
under_review ──reject (reason required, from a preset list + free text)──▶ rejected
approved / approved_conditional ──activate (auto, or on start date / fee)──▶ active  → OrgMember created / linked
any open state ──withdraw──▶ withdrawn
approved_conditional ──deadline passed──▶ flagged "overdue" (NOT auto-suspended; the reviewer decides, D-1205)
```

- Every transition writes `OrgAuditLog` and a `case_events` timeline row with the actor, step, reason and diff.
- **Notifications** reach the applicant (push + e-mail, the existing `notify_users`) on submit, correction requested, approved / conditional, rejected and activated, and as reminders 7, 3 and 1 days before a document is due. Reviewers get an attention badge (new `AttentionTabs.onboarding` + server `TABS`) and an SSE live event `onboarding` for the queue.
- A rejection or correction always carries a reason, shown to the applicant in their language. Preset reasons are bilingual. Free text is shown as written.

### 2.4 Entry methods

1. **Guided wizard** (staff fills in for someone). Steps: type → identity (national ID first: it fills birth date and gender and runs the duplicate check) → personal and contact → academic or appointment → documents → review and submit. Each step autosaves to the draft, so it can be resumed later from the "Drafts" tab.
2. **Excel / CSV bulk import.**
   - The template is generated **per member type from its config**: Arabic and English headers, dropdown validation for selects, and an instructions sheet.
   - Upload goes to a **dry run**. Rows are staged in `org_import_batches` / `org_import_rows` (24 h). The preview shows OK, warning or error per row, with the failing cell named in plain language.
   - The admin confirms all valid rows (partial success). The error report downloads as xlsx (original row + "what to fix" column) to fix and re-upload.
   - Each confirmed row becomes a case: `submitted` (staff-complete), or `draft` + invitation (the person completes it).
   - CSV is accepted (UTF-8 / UTF-8-BOM / cp1256 detection for Excel-saved Arabic). Existing limits stay: 5000 rows, 8 MB.
3. **Invitation and self-completion** (the main path for documents). This extends `OrgInvitation` with `case_id`. The admin imports the base data (name, national ID, e-mail or phone). The person gets the `/i/<token>` link, signs in or signs up (verified contact, as today), sees **their own wizard** with the fields the admin already filled locked, uploads documents and submits. Staff only review. Phone-only invitees keep today's in-app matching. An SMS provider is out of scope.
4. **Recommended extra: intake link / QR per member type** for open admission days. A public link or code (reusing `org_join_codes`) opens a self-application that always lands in review, never straight to active. It has a capacity and a validity window.
5. **Recommended extra: "copy from last year"**. A returning or re-applying person (matched by national ID) starts from their previous case data and still-valid documents.

### 2.5 Edge cases (none of them blocks registration)

| Case | Handling |
|---|---|
| Foreign or international | `nationality ≠ EG`: passport + equivalency replace the national ID and Egyptian-only documents; residence-permit expiry is stored and reminded 30 days before |
| Military postponed / exempt | field `military_status: completed / postponed / exempt / not_applicable`; postponed or exempt requires the matching form; a missing form → conditional approval with a due date |
| Missing or late documents | documents with `allow_later` may be marked **deferred** with a due date; the case can be `approved_conditional`; overdue shows on the reviewer's queue and in reports |
| Duplicates | hard: same national ID (or passport) in the org → open the existing case or member instead; soft (warning, reviewer decides): same e-mail or phone, or same normalised name + birth date |
| Name spelling | the Arabic normaliser (أإآ→ا, ة→ه, ى→ي, tatweel / diacritics stripped, "عبد ال…" spacing) is used for matching only; the stored name is exactly what was typed; optional English name field for certificates |
| Re-applicant | a match on a rejected or withdrawn case shows its history and reasons to the reviewer; the person may reapply (configurable cool-down, default none) |
| Existing platform account | consent rule C7 stays: an invitation addressed to that account, never silent attachment |
| Minor (under 18) | guardian group becomes mandatory (computed from the national-ID birth date) |

### 2.6 Validation rules

- **Egyptian national ID**: 14 digits after Arabic-Indic → Latin digit normalisation. Digit 1 = century (2 → 1900s, 3 → 2000s). Digits 2–7 = a valid YYMMDD date in the past. Digits 8–9 = a known governorate code (01–04, 11–19, 21–35, 88 abroad). Digit 13 is the gender (odd = male).
  - The check digit is **not** enforced: its algorithm is not officially published, and a false reject costs more than a missed typo. This is an explicit decision.
  - Extracted birth date and gender prefill the form. A mismatch with typed values is an error the user must resolve.
- Phone: Egyptian mobile `01[0125]` + 8 digits, or E.164 for foreign numbers. E-mail: the existing regex.
- Dates: birth date in the past, age within the type's range (warning), certificate year ≤ the current year.
- Required documents and fields are evaluated with the conditional rules on the server (the source of truth) and mirrored on the client for instant feedback.
- Uniqueness: national ID / passport per org (hard), `student_code` per org (hard on new codes; old data left alone).
- Files: real type from magic bytes (the existing work-attachment check), size, images re-encoded (strips EXIF and GPS), PDF page count capped.

### 2.7 Document handling

The `org_case_documents` table holds `requirement_key`, a version (replace keeps history), a status (`missing / uploaded / verified / rejected / deferred / waived`), `verified_by/at`, a note, `due_at`, size and mime.

The reviewer sees side by side: an in-app preview (image / PDF) next to the data, one tap for "verify", a "reject with reason" option (sends this document back for correction), and "waive". The applicant can replace a document until it is verified. Once verified, only staff can reopen it.

### 2.8 Privacy and security

- Identity documents are **never served through the bearer `/org/files/<token>` links**. A new endpoint, `GET /orgs/{o}/onboarding/documents/{id}`, checks `onboarding:view_documents` (or ownership), writes an audit row "viewed", and redirects to a 60-second presign.
- National ID and passport number are **encrypted at rest** (Fernet, key from env `PII_KEY`), plus an HMAC blind index for duplicate lookup. Lists show them masked (`•••• 1234`). Unmasking is a logged action. Exports leave them out unless the exporter has `view_documents`.
- `user_identity_values` stays the person's identifier store for exams. On activation the national ID is written there too (the same normalised `norm`), so exams keep working.
- Least privilege: a dept head reviewing TAs sees only their department's cases. Students never reach staff routes.
- Retention: documents of rejected or withdrawn cases are purged after N days (default 180, configurable). Audit rows stay forever (append-only, existing trigger).
- Rate limits on public intake links (existing `throttle.py`). Debug log redaction: add `national_id`, `passport_no` to `logSensitiveKeys`.

### 2.9 UI / UX (front)

- A new org page, **Admissions & appointments (الالتحاق والتعيين)**, in the org dashboard: `OrgPageHeader` + `OrgPageBody`.
  - One primary action, **Add**. It opens a dialog with three choices: one person · from Excel · invite people.
  - Stage tabs: *To review · Needs correction · Conditional · Drafts · Done*, with counts. Search by name, national ID or code; filter by member type.
- Wizard: `AppStepper`-style progress ("Step 2 of 5"), autosave indicator, plain-language errors next to the field, sensible defaults (cohort, level and program from the org config), national-ID-first speed-up.
- Review: master-detail (D-290 pattern). Left: the queue. Right: the case with data, a document checklist with preview, the timeline, and step actions at the bottom (approve / request correction / reject).
- Import: three screens. Upload → preview table (on phones a card list per row, never a wide table) → done, with the error report download.
- Applicant side: "My application" card on the member home and via the invite link, showing the status, what is missing, due dates and correction reasons.
- Settings: a **Member types** editor (fields and documents lists with mandatory / optional / conditional chips, chain steps) and a preset picker with diff.
- Rules: Arabic RTL / English, every string in `translation.json`, `countText`, `AppTime`, tokens only, `expectNoLayoutErrors` on every new widget (320 px → 1400 px), help ids, kill switches `org.onboarding`, `org.onboarding.import`, `org.onboarding.invite`, `org.onboarding.intake_link`, and entries in `app_features_guide.json`.

### 2.10 Data model and API impact

**New tables** (back, one Alembic revision per phase):

| Table | Purpose |
|---|---|
| `org_member_types` | per org: key, base role, labels, fields, documents, chain, settings, `preset_key`, active |
| `org_onboarding_cases` | org, type, `subject_user_id` (null until the account exists), `data` JSON, status, current chain step, `source` (manual / excel / invite / intake / quick), `batch_id`, `invitation_id`, `member_id` once active, `due_at`, encrypted national ID + blind index, created / submitted / decided by and at |
| `org_case_documents` | §2.7 |
| `org_case_events` | timeline (status changes, reasons, per-field correction notes) |
| `org_import_batches` / `org_import_rows` | staged dry-run rows (24 h) |

**Changed**:
- `org_invitations` gains `case_id`.
- `org_catalog.MODULES` gains `onboarding` and the `review` action.
- `org_excel_service` gets dry-run, CSV and template-from-config. The old direct import stays as quick add.
- `OrgMember` gains `onboarding_case_id`, nullable.

**API**, under `/api/v1/orgs/{o}/onboarding/`:
- types: `GET / PUT types`, `POST types/from-preset`, `GET presets`
- cases: `GET / POST cases`, `GET / PATCH cases/{id}`, and the transitions `POST cases/{id}/{submit | claim | request-correction | approve | reject | activate | withdraw}`
- documents: `POST cases/{id}/documents` (multipart), `PATCH documents/{id}` (verify / reject / waive / defer), `GET documents/{id}` (view)
- import: `POST imports` (dry run), `GET imports/{b}`, `POST imports/{b}/confirm`, `GET imports/{b}/report`, `GET templates/{type}`
- invitations: `POST cases/invite`

Applicant side: `GET /me/onboarding`, plus the same submit and document routes scoped to the owner.

Each phase updates `FLUTTER_API_CHANGES.md`, regenerates the contract snapshots (`api_paths.json`, `feature_keys.json`) and payload fixtures, and adds e2e tests under `tests/org_v2/`.

### 2.11 Phased release (each phase shippable and testable on its own)

| Phase | Ships | Verify |
|---|---|---|
| **A: cases, wizard, review** | migration 0099 (types, cases, documents, events); presets; national-ID validator + Arabic name normaliser (pure, unit-tested); state machine + chain; document upload / view endpoint (permission-checked, encrypted ID); front: Admissions page, wizard with drafts, review master-detail, member-types editor (presets + mandatory / optional toggles; conditional-rule editing as raw chips); quick add re-routed through a case | back e2e: every transition, chain with 2 steps, dept scoping, duplicate hard / soft, conditional approval; front: unit tests for the validator + layout harness for every new widget; a real web run on the local stack |
| **B: Excel / CSV import** | templates from config, CSV + encoding sniff, dry run + staged rows, preview UI, partial confirm, xlsx error report | e2e with a 5000-row file, a cp1256 CSV, and rows with every error class; front preview on 320 px |
| **C: invitations and self-completion** | `case_id` on invitations, the bulk "import then invite" path, the applicant wizard with locked prefilled fields, the "My application" card, the intake link / QR (review-only) | e2e: invite → accept → complete → correction → resubmit → approve → active; consent rule for existing accounts |
| **D: polish** | due-date reminders (daily sweep), attention badge + SSE event, document retention purge, onboarding reports (funnel per type, overdue documents, per-reviewer time) through the Export Studio, help texts, features guide entries, conditional-rule editor UI | contract tests regenerated; perf budget unchanged on homes; one full gate run (analyzer + suites) before the merge |

### 2.12 Execution model (token-saving, as requested)

- Opus does the architecture and contracts for each phase: the table definitions, the state machine, the API shapes as a written contract in `docs/onboarding/CONTRACT.md`, and the final review.
- Sonnet / Haiku sub-agents, each in its own worktree (`_wt/onb-*`) with a short brief listing only the files they touch, handle:
  - back: models + migration, routes, Excel and CSV code, validators + unit tests, e2e tests
  - front: providers / API client, each screen, translations, layout-harness tests
- Per phase, the order is: back first, then front against the contract, then the lead's merge, then only the tests covering the change + the analyzer on the changed paths (owner rule). Fixes come next, then the phase is marked `verified` in `docs/onboarding/PROGRESS.md`.

### 2.13 Decisions I need from you

1. **Activation**: should approval activate the member immediately (my recommendation, configurable per type), or always wait for a separate "activate" (e.g. after fees)?
2. **Encrypting the national ID at rest** needs a new server secret `PII_KEY` in `.env.production`. OK to add it?
3. **Quick add** (today's instant add / import) stays for people with `approve`, but goes through a case and the audit log. OK, or should every addition go through review?
4. **Fees**: in scope is only a status field + receipt document. Linking to the existing account-fee / billing work (D-1120) would be a later phase. OK?
