# Student lifecycle: plan (D-1400 – D-1429 reserved)

Status: **APPROVED 2026-11-21**, the owner took the default of all 16 questions in §7. Contract: CONTRACT.md.
Branch `feature/student-lifecycle` in `_wt/sl-back` (from e2c804f) and `_wt/sl-front` (from 72c211c4).
Inputs: `INVENTORY.md` (what exists, verified in code) and `RESEARCH.md` (Egyptian rules, sources S1–S24).
Back paths are relative to `sl-back/`, front paths to `sl-front/lib/`.

**The one idea behind this plan.** Most of the owner's list already exists in four separate places: onboarding
(D-1200), the registrar, complaints and the calendar. What is missing is (a) one place that shows a student
whole, (b) one reasoned, dated, reversible status history, (c) the rules that move a student automatically, and
(d) a way to ask the student for something and get a stored answer. So this job adds a thin **student lifecycle
layer** (`features/org/students/` on the server, `features/org/students/` in the app) that reads the existing
modules and writes only what has no home today. No working page, table or endpoint is removed.

Facts re-checked in code for this plan (beyond the inventory):

- `POST …/complaints/{cid}/meeting` (`features/org/services/api/org_services_router.py:889`) creates the
  `cal_meetings` row itself and **never runs the `attendees_busy` check** that `POST /me/calendar/meetings` runs
  (`features/home/api/calendar_router.py:280`). The owner's rule is "reuse the busy rule", so this is a fix.
- `recompute` (`registrar/service.py:882`) overwrites `standing` and bumps `probations`, and writes no history
  and no notice. `promote` (`registrar/traditional.py:142`) returns the `repeat` list and stores nothing for it.
- Staff may upload a document to any case that is not rejected / withdrawn (router `:393`); the applicant may
  upload after activation only while the case is `conditional` (`:545`). So "upload it right there" on an active
  student needs no new storage, only a small rule change for non-conditional gaps.
- Every preset has the four student types `student_new`, `student_transfer`, `student_postgrad`,
  `student_international`, each with `settings.student_code_pattern: null` (never read).
- A chain step's `need` is `{module, action}` or `{org_role, scope}` only: no named person, no council.
- `org_terms.kind` is `String(8)`, `org_student_academic.standing` is `String(12)`, `cal_meetings.source_type`
  is `String(20)`: the new values below are chosen to fit, and new columns are sized with room.

---

## 1. Requirements table

Status: **Ready** = works today, at most wiring into the new Students section. **Needs modification** = exists
but lacks part of the requirement. **Missing** = nothing to build on.

| # | Requirement | Status | Existing files | What to do |
|---|---|---|---|---|
| 4.1a | Add Student by staff with permission | Ready | back `features/org/onboarding/service.py` (`create_case`, `M:insert`), front `features/org/onboarding/onboarding_wizard.dart`, `onboarding_entry.dart` | Open the same wizard from the new Students page's primary action. No rebuild. |
| 4.1b | Pick from every Egyptian student type | Needs modification | `data/onboarding_presets/*.json` (4 student types), `onboarding_types_page.dart` | Add the missing admission routes as preset types (§4.2 below: equivalent certificate, technical diploma, second degree, affiliation, directed affiliation, special programme, visiting / listener). Presets are additive (`types/from-preset` with `replace:false`). Also fix the `faculty` key that appears twice in every preset file. |
| 4.1c | Each type shows exactly its fields / documents, configurable, never hard-coded | Ready | `org_member_types.fields/documents`, `validation.py` (`when` rules), `onboarding_types_page.dart` | None. New types reuse the same field kinds. |
| 4.1d | Full entry | Ready | `onboarding_wizard.dart` (autosave drafts) | None. |
| 4.1e | Partial entry + invitation (e-mail / in-app) to finish | Ready | `onboarding/invite.py`, `POST cases/invite`, `onboarding_invite.dart`, `onboarding_applicant.dart` | Add the "Save and invite" button to the wizard's last step (today the invite is a list action). |
| 4.1f | Invitation link / code | Ready | `PUT types/{key}/intake`, `onboarding_intake.dart` (link + QR), `/onboard/:code` | None. |
| 4.1g | Self-registration if allowed | Ready | `POST /me/onboarding/intake/{code}`, always lands in review | Surface it as one of the four entry policies (4.2a). |
| 4.1h | Excel / CSV import, template per type | Ready | `onboarding/importer.py` (`template_bytes`, xlsx / csv, cp1256), `GET templates/{type}` | None. |
| 4.1i | Review screen before saving, errors shown | Ready | `POST imports` (staged 24 h), `OnbImportPreviewView`, `OnbImportRowCard` | None for showing. |
| 4.1j | Fix errors **inline** in the review | Missing | `org_import_rows` (data, state, messages) | New `PATCH imports/{b}/rows/{row_id}` re-validates one staged row; the row card becomes editable (only the failing cells open by default). Also flag duplicates **inside the same file**. |
| 4.1k | "Missing data" badge on each incomplete student, showing exactly what is missing, upload right there | Needs modification | `service.requirements()` (per case), `missing_count` on case rows, `record_quick_case` gives legacy adds an `active` case | Expose `missing` on the **student** (member) list and file, not only on cases; a `MissingDataSheet` uploads / fills in place through the existing case routes; allow completion of a non-conditional `active` case; lazily create the quick case for members older than phase E. |
| 4.2a | Entry policy: direct / review and approval by a person or body / invitation / code | Needs modification | type `chain` + `settings.auto_activate` + intake + invite; `onboarding_types_page.dart` | One plain "Entry policy" picker per type that writes those existing settings; two new step kinds: a **named person** (`need.user_ids`) and a **body** (`need.council_id`, the decision recorded with number and date; a real council vote in phase 6). |
| 4.2b | Study system: credit hours, or traditional with years, terms per year, summer | Needs modification | `organizations.study_system`, `org_programs.system_type`, levels (`academic_config.py`), `org_terms.kind` | A "Study system" settings page that sets these in one place; new term kind `makeup` (second round, RESEARCH §3.1); explicit `summer` on/off and preparatory year flag. |
| 4.2c | Pass / progression rules (pass % or minimum GPA) | Needs modification | `registrar/policy.py` `DEFAULT_RULES` (grade scale, pass letter, `traditional.max_carry`, `standing`, `retake`), Rules tab in `org_registrar_staff.dart` | Extend the rule set with the variants of RESEARCH "Configurable options implied" (§4.3 below), each an admin choice with the common default; scale presets (4-point, 5-point, traditional names). |
| 4.2d | Automatic move to next level / term, courses open for registration | Ready (move) / Needs modification (record) | `recompute` (hours), `_year_promotion` + `promote` (year), `cohort_enrol`, member `offerings` | The move works. Add: a standing / status event per student, the repeaters, a notice to the student, and a dry-run preview before the yearly run is applied by hand. |
| 4.2e | Variants: carried-course limits, repeat rules, GPA scales, … | Needs modification | as 4.2c; `org_programs.progression {max_carry}` | Per-programme overrides for every progression rule (the column exists); cohort-versioned rule sets are a question (§7 Q6). |
| 4.3a | Data arrives as requests; accept / reject / return with reason | Ready | `cases/{id}/{approve,reject,request-correction}`, `REJECT_REASONS`, `onboarding_review.dart` | None for intake. For changes to an **active** student's data by the student: a "data update" ask (4.3c) reviewed in the same inbox. |
| 4.3b | Request a meeting: time + in person / online, student notified, reuse calendar and `attendees_busy` | Needs modification | `POST complaints/{cid}/meeting`, `features/home/calendar_service.py` (`busy`, `notify`), `features/calendar/calendar_meeting.dart` | One shared server helper `meetings.create_for_source(…)` that runs the busy check (409 `attendees_busy` unless `force`); used by complaints (fix), onboarding cases, status reviews and asks. |
| 4.3c | Same mechanism asks for data or a confirmation; reviewer chooses notification / full-screen / popup | Missing | nearest: `org_must_ack.dart` + `OrgMustAckHost`, `org_forms`, `needs_correction` | New `org_student_asks` (kind meeting / data / documents / confirm; presentation notice / popup / fullscreen; stored answer). Drawn by the existing `OrgMustAckHost`, so `main.dart` is not touched. |
| 4.3d | A body must approve → staff's part ends at upload, student live only after approval; else staff confirms | Ready | approval chain + `activate`; quick-add for holders of `approve` (D-1200) | Covered by 4.2a's picker. Add the person / body step kinds. |
| 4.4a | Every status used in Egyptian universities, tied to the study system | Missing | pieces in six fields (INVENTORY §3) | §2: four dimensions, one new enrolment status, one unified standing, flags, an append-only event table. |
| 4.4b | Regular / struggling / repeating / transferred clearly distinguished | Missing | `standing` (good / probation / honours) only | §2.2. |
| 4.4c | Automatic vs manual transitions and the deciding body | Missing | `OrgDecision` + `ACTIONS` registry (registrar), unused `dismiss_after_probations` | §2.3: automatic from results; anything that removes a student is a **recommendation** a body accepts. |
| 4.4d | Complaint → meeting → status | Needs modification | `org_complaints`, `OrgComplaintThreadScreen`, meeting route | §3.9: two actions on the complaint thread; the status event carries `source = complaint`. |
| 4.5 | Append-only timeline + audit per student until graduation | Needs modification | `org_case_events`, `org_level_advances`, `org_registrations`, `org_audit_log`, `entity_timeline.dart`, `ws_person.dart` | One merged read model `GET students/{uid}/timeline` (no copy of existing data) + the new status events. |
| 4.6a | Role permissions: staff, complaints officer, manager, admin | Needs modification | `org_catalog.py` (`MODULES`, `SYSTEM_ROLES`), `org_ctx` | One new module `student_status`; four new system roles (§4.5). |
| 4.6b | Duplicate prevention by national ID or passport | Needs modification | `service.duplicates` (ID vs cases + members; passport vs cases only) | Match passports against members too; duplicates inside one import file; a warning when the person is enrolled in a sister faculty of the same university (RESEARCH §1.1, S6: not two faculties at once). |
| 4.6c | Sensitive-data protection | Ready | `helpers/pii.py` (Fernet + blind index), last-4 masking, `member_documents:view`, 60 s links | Keep. The unified file hides each sensitive section behind its own right (§3.2). |
| 4.6d | Log entry every time a student file is opened | Missing | only `onboarding.document_viewed` / `nid_viewed` | `student.file_viewed` (+ section) in `org_audit_log`, deduplicated per actor / student / section / 30 min; a "Who opened this file" list. |
| 4.6e | Full ar / en + RTL | Ready | `t(ar, en)`, `DirIcons`, `expectNoLayoutErrors` | Every new widget goes through the layout harness. |
| 4.6f | Review before any import is saved | Ready | staged batches | None (see 4.1i). |
| 4.6g | E-mail + in-app notifications | Ready | `notify_users` (push, e-mail fallback), live event `onboarding` | New notices for status changes, asks and meetings. |
| 4.6h | Automatic reminders for incomplete data | Needs modification | `onboarding/sweep.py` (only for documents with a due date) | Remind students whose file is incomplete even without a due date (cadence is a setting); remind on open asks. |
| 4.6i | Undo for any status change, who / when | Missing | — | §2.4: a compensating event. |
| Q1 | No overflow, mobile-friendly, premium | — | `test/ui/layout_harness.dart` | Each phase lists its layout test. |
| Q2 | `app_features_guide.json`, kill switch, help id per feature | — | `feature_catalog.py`, `data/help_seed.json` | §4.8. |
| Gap | Student number on activation | Missing | `settings.student_code_pattern` (unused) | Generate it in `activate` (phase 3). |
| Gap | Transfer credit (المقاصة) | Missing | — | `org_transfer_credits` (phase 6). |

---

## 2. Student statuses

### 2.1 The model: four dimensions, not one status

**Recommendation: orthogonal dimensions.** One status field cannot hold the real cases: a student can be
*repeating* and *suspended* at once, or *regular*, *transferred in* and *owing documents* at once, and a
suspended student must come back to the standing he left with. A single list would need a value for every
combination, and every rule ("may he register?", "does this year count toward the maximum?") would have to
enumerate them. With dimensions each rule reads one field.

| Dimension | Question it answers | Where it lives | Who moves it |
|---|---|---|---|
| **Intake** | Has the institution accepted this file? | `org_onboarding_cases.status` (exists) + derived "missing data" | reviewers, the approval chain |
| **Enrolment** | Is the student's registration (القيد) in force? | NEW `org_student_academic.enrol_status` | manual decisions by a body; a few automatic |
| **Academic standing** | How is he progressing? | NEW `org_student_academic.acad_standing` (the old `standing` keeps being written for installed apps) | automatic from approved results |
| **Flags** | What else must staff know? (several at once) | NEW `org_student_flags` | automatic rules or a manual decision |

Every change in the last three writes one row in the append-only `org_student_status_events` (§2.4). The
intake dimension keeps its own `org_case_events`.

What staff see is **one chip**, by precedence: enrolment if it is not `enrolled`, else intake if the file is
not active, else the standing; flags follow as small chips. So a non-technical reader sees "Suspended" or
"Repeating" first and the detail one tap away.

### 2.2 Values and sources

Sys: **T** traditional year, **C** credit hours.

**Intake** (labels over the existing case status; nothing new stored):

| Owner's term | Shown when | Sys | Source |
|---|---|---|---|
| Nominated (مرشح) | `draft` case that came from an import or coordination list | both | §7 table, S6, S15 |
| Provisionally registered (مقيد مبدئياً) | `draft` / `submitted` | both | §7 "Applicant / pending documents", S6 |
| Missing data (بيانات ناقصة) | `needs_correction`, or any case with `missing_count > 0` (also `active` + `conditional`) | both | §2 (enrolment follows completion of documents), S6 |
| Awaiting approval (بانتظار الاعتماد) | `under_review`, or `approved` not yet activated | both | §2, S6 |
| Accepted (مقبول) | `approved` / `active` | both | §7 "Enrolled", S6 |
| Rejected / withdrawn | `rejected` / `withdrawn` | both | — |

**Enrolment** (`enrol_status`, `String(24)`; the reason is on the event):

| Value | Arabic | Sys | Meaning | Source |
|---|---|---|---|---|
| `enrolled` | مقيد | both | registration in force | §2, S6 |
| `suspended` | موقوف القيد | both | frozen at the student's request; not counted toward the maximum duration | §5 suspension, S5, S6, S11 (cited as Exec. Reg. art. 69) |
| `postponed` | مؤجل | C (and conscription in both) | term postponement; compulsory during military service | §5 postponement, S9, S11; §2 conscription, S6 |
| `disc_suspended` | موقوف تأديبياً | both | art. 126 temporary penalties | §5 discipline, S9 |
| `outside` | من الخارج | T | sits failed courses without attending; counts as dismissed from the faculty, cannot be suspended | §4.1 art. 80, S3; S5 |
| `withdrawn` | منسحب / سحب ملف | both | left at own request after clearance | §5 withdrawal, S11, S12 |
| `cancelled` | ملغى القيد | both | enrolment cancelled by request or rule (postgraduate: struck) | §5, S9, S11; §1.4, S13 |
| `dismissed` | مفصول | both | reason on the event: `chances_exhausted` (T, art. 80), `gpa` / `max_duration` / `not_registered` (C), `disciplinary` | §4.1, S3, S5; §4.2 dismissal, S10, S11; §5, S9 |
| `transferred_out` | محول من الكلية | both | moved to another faculty / university | §1.3, S6 |
| `graduated` | خريج | both | degree granted (mirrors `stage = graduated`) | §6, S1 art. 172 |
| `deceased` | متوفى | both | — | §7 (judgement) |

`graduand` (all requirements met, awaiting the council) stays what it is today: a `graduation_candidates`
decision in the registrar, not a status.

**Academic standing** (`acad_standing`, `String(24)`):

| Value | Arabic | Sys | Rule (all numbers are settings) | Source |
|---|---|---|---|---|
| `regular` | منتظم / منقول | both | T: passed every course of the year. C: GPA at or above the warning line | §7 "Promoted", S7; "Good standing", S10 |
| `carrying` | منقول بمواد | T, C-hybrid | failed courses ≤ `max_carry` (default 2), result sheet "منقول بمقررين" | §4.1 carried courses, S9, S12 |
| `repeating` | باقٍ للإعادة | T | failed more than `max_carry`; stays in the year, re-sits failed courses | §4.1 repeating, S12 |
| `warning` | إنذار أكاديمي | C | CGPA (or term GPA) below 2.0; load capped (12 CH) | §4.2 warning, S10, S11, S9 |
| `final_chance` | فرصة أخيرة | both | C: extra terms before a GPA dismissal. T: outside chances for pre-final / final years | §4.2, S10, S11; §4.1 art. 80, S3 |

`honours` stays where it is (the legacy `standing` field and the degree audit): it is a distinction, not a
progression state (RESEARCH §6).

**Flags** (`org_student_flags.key`, several at once, each with a reason and an optional end date):

| Flag | Arabic | Set | Source / reason |
|---|---|---|---|
| `struggling` | متعثر | automatic by the institution's rule (default: standing `warning`, `final_chance`, or repeating the same year a second time), **or** manual by a decision | RESEARCH §4.2 last bullet: the term is informal, the mechanisms are warning → reduced load → final chance. So it is a flag with a configurable rule, not a legal status. |
| `special_case` | حالة خاصة | manual only, reason required, optional end date | judgement; the owner's complaint flow |
| `transferred_in` | محول إلى الكلية | automatic when the admission type is a transfer; permanent | §1.3, S6, S11 |
| `conscripted` | مجند | manual (military notice); the place is kept | §2 military status, S6 |
| `excuse_open` | عذر مقبول | manual, per exam session | §5 excuse, S3, S5 |
| `disciplinary_record` | جزاء تأديبي | manual with the penalty | §5 art. 126, S9 |
| `docs_owed` | مستندات ناقصة | derived from the case (not stored) | §2, S6 |
| `affiliated` | منتسب / انتساب موجه | from the admission type | §1.2, S6 |

**How the owner's four are told apart.** *Regular* and *repeating* are standing values (one at a time, set by
results). *Struggling* is a flag (rule or decision) that can sit on top of `warning`, `repeating` or
`final_chance` and drives the support actions. *Transferred* is two different things: `transferred_in` is a
permanent origin flag with credited courses, `transferred_out` is a final enrolment status.

### 2.3 Transitions

**A** automatic, **M** manual. "Recommendation" = the server opens an item for the body with the rule and
the evidence; nothing changes until someone with the right accepts. The deciding body for each manual row is a
setting (the **decision matrix**, §4.3); the table shows the default from RESEARCH §7.

Enrolment:

| From | To | How | Trigger / deciding body (default) | Reversible |
|---|---|---|---|---|
| — | `enrolled` | A | the onboarding case is activated | by withdrawing the case (existing) |
| `enrolled` | `suspended` | M | student request with papers → faculty council; beyond the limit (default 2 years) the university council. Blocked for `outside` students, level 1, during finals: each a setting (§5, S5, S12, S11) | yes: ends on its date or by "Resume enrolment" |
| `enrolled` | `postponed` | M (A for a recorded conscription) | faculty council; max terms is a setting (default 4) | yes |
| `suspended` / `postponed` | `enrolled` | A on the end date; M earlier | date reached, or staff "Resume" | yes |
| `enrolled` | `disc_suspended` | M | dean / president / disciplinary board, by penalty (art. 127) | ends on its date; undo by the same body |
| `enrolled` (T) | `outside` | A recommendation → M | two years spent in the same year + faculty council permission (art. 80) | undo |
| `enrolled` / `outside` | `dismissed` (`chances_exhausted`) | A recommendation → M | results after the last chance; faculty council | undo; later only through re-enrolment |
| `enrolled` (C) | `dismissed` (`gpa` / `max_duration` / `not_registered`) | A recommendation → M | the enabled dismissal rules; faculty council, after the final-chance check | same |
| `enrolled` | `dismissed` (`disciplinary`) | M | president / disciplinary board | undo by the same body; review after ≥ 3 years is a new decision (art. 126) |
| `enrolled` / `suspended` | `withdrawn` | M | student request + clearance; student affairs (guardian approval is a setting) | undo; later through re-enrolment |
| `enrolled` | `cancelled` | M (A recommendation when a rule fires) | faculty council | same |
| `enrolled` | `transferred_out` | M | both faculty councils + university president (recorded as decision number and date) | undo |
| `withdrawn` / `cancelled` / `dismissed` | `enrolled` (re-enrolment, إعادة قيد) | M | faculty council; max gap, minimum CGPA and "counts as a failure year" are settings (§5, S9, S11, S12) | undo |
| `enrolled` | `graduated` | M | existing `graduate()` on the graduation decision; university council on the faculty council's request (S1) | undo by `academic:approve` (new: today there is none) |
| any | `deceased` | M | student affairs | undo |

Standing (always after grades are approved; never while a grade of the period is missing):

| From | To | How | Trigger | Reversible |
|---|---|---|---|---|
| any | `regular` | A | T: `promote` with no failed course. C: `recompute` with GPA ≥ line | recomputed on the next results; manual override with a reason |
| any | `carrying` | A | T: failed ≤ `max_carry` | same |
| any | `repeating` | A | T: failed > `max_carry`, or last year with failures | same |
| `regular` | `warning` | A | C: below the line (basis CGPA / term GPA, skip first term: settings) + written notice to the student (S11) | same |
| `warning` | `regular` | A | back at or above the line; the consecutive counter resets if the setting says so (S10) | — |
| `warning` | `final_chance` | A recommendation → M | counter reached and credits ≥ the setting (75 / 80 %); faculty council | undo |
| `repeating` (T) | `final_chance` | A recommendation → M | outside chances for pre-final / final years (art. 80) | undo |
| any | any | M override | a body corrects a result-driven standing (leniency, appeal); reason required; holds until the next approved results | undo |

Flags: `struggling` A by rule and M by decision (complaints officer or manager per the matrix);
`special_case`, `conscripted`, `excuse_open`, `disciplinary_record` M; `transferred_in`, `affiliated` A from
the admission type. Every flag is removable, with a reason.

**Side effects, each a setting with a safe default.** An enrolment status other than `enrolled` blocks new
course registration (one new block code in `registrar.evaluate`). It does **not** drop current registrations
or end the membership by itself: the decision sheet asks ("also withdraw from this term's courses?", "end
access on: date"). The membership keeps using `org_members.status / ended_at / end_reason`, so installed apps
see what they see today.

### 2.4 History and undo

`org_student_status_events` is append-only (the same PostgreSQL trigger pattern as `org_audit_log`):
`dimension, key, from_value, to_value, reason_code, reason, decision_no, decision_date, body, effective_from,
effective_to, via (auto | manual | request | undo), source_type, source_id, effects, reverts_id, actor_id,
created_at`.

- The current value on `org_student_academic` / `org_student_flags` is a cache of the last event.
- **Undo = a new event** with `via = undo` and `reverts_id` pointing at the event it compensates. It restores
  `from_value` and reverses the recorded `effects` (registrations dropped, access end date). Nothing is
  edited or deleted, so the timeline shows both lines: "Suspended by X on …" and "Undone by Y on …: reason".
- Undo is allowed only for the **latest** event of that dimension (else 409 `not_latest`: undo the newer one
  first), needs the same right as the original decision (or `student_status:approve`), and needs a reason.
- An undone **automatic** event sets a hold until the next approved results, so the hourly job does not
  re-apply it five minutes later.
- An event already reverted cannot be reverted again (409 `already_reverted`); "redo" is a normal new decision.

---

## 3. Screens and flows

All pages are `OrgPageHeader` + `OrgPageBody` (`org_page_kit.dart`: one primary action, one search, one
filter, cards on phones), pushed pages are `OrgPushedPage`, sheets are `showAppSheet` / `AppSheetContent`,
loading is `AppListSkeleton`, empty is `AppEmpty`, toasts `showAppNotice`, confirmations `appConfirm`. Every
new widget has a plain-values view tested with `expectNoLayoutErrors`.

### 3.1 The Students section (`OrgStudentsPage`, People → "Students")

A new first sub-page of People (`_peopleSubs`), shown with `students:view` and kill switch `org.students`
on. Members and Admissions stay where they are; with the switch off nothing changes.

- **Top:** `AppStatCard` row that doubles as the filter: Enrolled · Missing data · Awaiting approval ·
  Warning / repeating · Suspended. Tapping a card filters the list (one tap, no filter form).
- **List:** `AppDataTable` (cards on phones). Row: photo, name, student number, programme · level, the one
  status chip (§2.1), flag chips, and the **missing-data badge** (count; tap opens the sheet, §3.5).
- **One search** (name, student number, last 4 of the ID), **one filter sheet** (programme, level, status
  dimension, flag, type), saved views through the existing `saved views` API (migration 0058).
- **Primary action:** "Add student" (§3.3). Overflow: Import, Export (`showAppExportSheet` inside
  `bilingualExport`), Settings.
- Reused: the list data starts from the existing `GET academic/students` + member rows; one new aggregate
  `GET …/students` adds the status fields and `missing` so the page is one request.

### 3.2 The unified student file (`OrgStudentFilePage`)

One page that replaces "four screens to find one student". It opens from every place a student appears
(Students list, Members row, registrar at-risk, advising, complaints, the command palette); the old screens
stay reachable from inside it.

- **Header card** (`AppCard` on the canvas, no gradient): photo, name ar / en, student number, programme ·
  level, the status chip + flag chips, the missing-data badge, and three actions: **Change status**,
  **Ask the student**, **Request a meeting**. On phones the actions fold into one "Actions" button.
- **Journey rail:** `AppRoadmap` (Applied → Accepted → Year 1 … → Graduation), the current node marked, a
  `warn` node for repeating / suspended. Reuses the roadmap widget, no new drawing.
- **Tabs** (`AppUnderlineTabs`, each lazy, each hidden without its right):

| Tab | Content | Reused | Right |
|---|---|---|---|
| Overview | key facts, open asks, next meeting, open requests, what is missing | new aggregate | `students:view` |
| Timeline | §3.2a | `entity_timeline.dart` row style | `students:view` (rows filtered per source) |
| Academic | record, GPA, registrations, level history | `OrgRecordScreen(studentId:)` body embedded | `students:view` |
| File & documents | the case's fields and documents, verify / reject / upload | `onboarding_review.dart` detail pane | type module `view`; documents need `member_documents:view` |
| Requests & complaints | the student's work items, complaints, asks | `GovApi`, complaints list rows | `workflow` / `complaints` on the item's department |
| Advising | link card into the 360 | `AdvStudentPage` | advising access (never part of a read-all role) |
| Access log | who opened this file and when | `GET audit?entity=student` | `audit:view` |

- **Opening the file writes `student.file_viewed`**; opening Documents, Advising or the ID writes its own
  section event. A quiet line under the header says "Opening this file is recorded" (once per session), so
  staff know and are not surprised.

**3.2a Timeline.** One vertical list, newest first, grouped by academic year, with filter chips
(Status · Results · Registration · Requests · Meetings · Complaints · Documents). Each row: icon, one plain
sentence ("Moved to Year 2 carrying 2 courses"), who, when (`AppTime`), and the reason or decision number
when there is one. A status row from the last event of its dimension shows **Undo** to whoever may. The list
is a merged read of existing tables (§4.4), so nothing is copied and nothing can be edited.

### 3.3 Add Student

The primary action opens a small chooser sheet (`AppSheetContent`, four `AppActionCard`s), each shown only
when the institution's entry policy and the caller's rights allow it:

1. **Enter the full file** → the existing wizard (type → identity with the national-ID parse and duplicate
   check → personal → academic → documents → review).
2. **Enter the basics and invite** → the same wizard, stops after identity + contact, then "Save and invite".
3. **Share a link or code** → the existing intake card (link, QR, capacity, validity).
4. **Import a spreadsheet** → §3.4.

The type step lists the institution's active student types as cards grouped by admission route, each with a
one-line description, so a clerk picks "Transfer from another faculty" rather than a key. The wizard's last
step states what happens next in one sentence, taken from the type's entry policy: "The student becomes
active when you confirm" or "Your part ends here: the file goes to (body) for approval".

### 3.4 Import review (extend `onboarding_import.dart`)

Setup view unchanged (type, mode, template download). The preview view gains:

- A summary strip: OK · warnings · errors, each a filter.
- **Inline fix:** an error row opens in place with only its failing cells as `AppField`s (the rest read-only,
  "Edit all" reveals them). Saving calls `PATCH imports/{b}/rows/{id}`; the row re-validates alone and turns
  green without a re-upload.
- "Fix the same error in N rows" for one repeated cause (e.g. an unknown programme name → pick once).
- Duplicates inside the file are marked on both rows with a link between them.
- Confirm stays explicit ("Save 182 valid rows, skip 6") and the error report download stays.

### 3.5 Missing-data badge and sheet

`MissingBadge(count)` is an `AppStatusBadge` (warning tone) with a count, on the list row, the file header and
the Members row. Tap opens `MissingDataSheet`:

- Three groups with plain labels: **Photos**, **Documents**, **Information**. Each line names the item, why
  it is required (the rule in words: "Required for male Egyptian students"), and its due date if any.
- A document line has **Upload** right there (camera or file; photos through `showAppImageCropper`); a field
  line has its input inline. Both use the existing case routes.
- Footer actions: **Remind the student** (notification + e-mail now) and **Ask the student** (§3.7, the
  missing items preselected), and for staff with the right, Waive / Defer with a reason (existing).
- The count drops as items are completed; at zero the badge disappears and the timeline gets one line.

### 3.6 Requests inbox (`OrgStudentRequestsPage`, People → "Student requests")

One list for everything waiting for **me** about students, in stage tabs like the Exams hub (three at most):
**To decide · Waiting for the student · Done**. Rows come from four sources, each with a type chip:

- admission files at my step (existing cases, opens the existing review page);
- status recommendations from the rules (dismissal due, final chance, outside permission);
- lifecycle requests from students (suspension, withdrawal, re-enrolment, transfer: governance items, phase 6);
- answered asks to review.

Every row offers the same three verbs with a reason: **Accept · Return for correction · Reject**, plus
**Request a meeting** and **Ask the student**. Counts feed `ShellBadge` on People through the existing
`org_onboarding` attention tab pattern (a new key `student_requests`).

### 3.7 Request a meeting / ask the student (`StudentAskSheet`)

One sheet, four steps on one screen (a `AppTabs` pill row picks the kind, the rest adapts):

1. **What:** Meeting · Information · Documents · Confirmation.
2. **Details:** meeting → date, time, length, in person (place) or online; information → pick fields from the
   student's type or write a question with an answer type (text / choice / date); documents → pick document
   requirements; confirmation → the sentence to confirm.
3. **How it appears:** Notification · Popup · Full screen (each with a one-line explanation and a tiny
   preview). Full screen is limited to holders of the right and needs a due date ≤ 7 days, the same guard
   must-ack has.
4. **Due date and reminder.**

- A meeting goes through the shared helper: if the student or the reviewer is busy the sheet shows who and
  when (the calendar's existing busy list) with "Pick another time" and "Book anyway" (`force`), exactly as
  `SchedulePage` does. It lands in both calendars (`cal_meetings`, `source_type = student_ask`).
- **Student side:** a notification with a deep link; a popup (`showAppDialog`) on the next app open; or the
  full-screen card drawn by the existing `OrgMustAckHost` with the answer form inside. The student answers
  once; documents go to the case, fields to the case data **as a pending change the reviewer accepts**.
- The ask and its answer appear on the timeline and in the inbox's "Waiting for the student" tab.

### 3.8 Institution settings (`OrgStudentSettingsPage`, an `AppSettingsPage` in Settings → "Students & study rules")

Five groups, each a page of plain questions with the common Egyptian answer preselected and an "i" that
names the bylaw idea in one line:

1. **Admission:** student types (opens the existing types page), entry policy per type (four radio cards:
   Direct · Review and approval · By invitation · By code; "Review and approval" then asks who: a role, a
   named person, or a body), student number pattern, incomplete-file reminders.
2. **Study system:** credit hours or years; number of years, preparatory year, terms per year, summer term,
   second round. Writes the existing `study_system`, levels and term kinds.
3. **Passing and progression:** grade scale (pick a preset, then edit the table), pass mark, minimum in the
   final, carried-course limit, repeat rules, warning and dismissal rules, final chance. A **"Start from a
   bylaw"** picker fills everything at once (§6 P5).
4. **Enrolment changes:** suspension limits and exclusions, postponement, re-enrolment, withdrawal clearance.
5. **Who decides:** the decision matrix, one row per decision ("Suspend enrolment", "Dismiss", "Mark as
   struggling", …), each with: who may propose, who decides, whether a decision number is required.

Every rule screen ends with a **"Try it"** box: pick a real student, see what the rules would say and why,
before saving. Programme-level overrides open from the programme form with the same widgets.

### 3.9 Complaint → meeting → status

On `OrgComplaintThreadScreen` (existing), for a complaint that names its sender:

1. The officer opens the complaint. The header gains a **student strip** (name, status chip, "Open file").
2. **Request a meeting** opens `StudentAskSheet` on Meeting (replaces the current date dialog; the thread
   still gets its automatic message; the busy rule now applies).
3. After the meeting the officer taps **Propose a status change** → `StatusChangeSheet` preselected on the
   flags (`struggling`, `special_case`), reason prefilled with the complaint reference.
   - If the matrix lets the officer decide, the flag is set at once and the student is told.
   - If not, it becomes a recommendation in the manager's inbox with the complaint and the meeting attached.
4. The status event stores `source_type = complaint`, so the student's timeline reads: complaint filed →
   meeting held → marked as struggling (by whom, why) → and later, removed.
5. Marking as struggling offers one follow-up: "Open a support plan in Advising" (existing feature, only
   when `org.advising` is on).

`StatusChangeSheet` in general: pick the change from the list the matrix allows me; the sheet then shows only
what that change needs (reason from a preset list + text, effective dates, decision number and date,
attachment, the side-effect questions) and a plain preview: "From 1 Feb the student cannot register courses.
Current courses stay." Confirm is `appConfirm(danger: true)` for anything that removes a student.

---

## 4. Data model and API

### 4.1 Tables and columns (model change **and** revision; sizes for PostgreSQL)

New file `data/student_lifecycle_models.py` (on the shared `Base`).

**`org_student_status_events`** (0110; append-only trigger on PostgreSQL, `is_postgres()` guarded):
`id`, `org_id` FK, `user_id` FK, `dimension String(12)` (`enrolment | standing | flag`), `key String(32)`
(flag key, else NULL), `from_value String(24)`, `to_value String(24)`, `reason_code String(40)`, `reason Text`,
`decision_no String(60)`, `decision_date Date`, `body String(40)`, `effective_from Date`, `effective_to Date`,
`via String(10)`, `source_type String(20)`, `source_id Integer`, `term_id Integer`, `effects JSON`,
`rules JSON` (snapshot of the rule that fired), `reverts_id Integer`, `reverted_by_id Integer` (the only
column ever set after insert; the trigger allows that one update), `actor_id`, `actor_role String(30)`,
`created_at`. Indexes `(org_id, user_id, created_at)`, `(org_id, dimension, to_value)`.

**`org_student_flags`** (0110): `org_id`, `user_id`, `key String(32)`, `active Boolean`, `since Date`,
`until Date`, `event_id`, unique `(org_id, user_id, key)`, index `(org_id, key, active)`.

**`org_student_academic`** new columns (0110): `enrol_status String(24)` default `enrolled`,
`enrol_since Date`, `enrol_until Date`, `acad_standing String(24)`, `standing_hold_until Integer` (term id),
`warnings_run Integer` (consecutive counter), `years_in_level Integer`, `outside_chances_used Integer`,
`admission_route String(40)` (the case's type key at activation), `rule_set_key String(40)` (phase 7).
Backfill in the revision: `enrol_status` from `stage = graduated`, `acad_standing` from `standing`
(`probation → warning`, else `regular`).

**`org_student_asks`** (0111): `org_id`, `user_id`, `created_by`, `kind String(12)`, `presentation String(12)`,
`title String(200)`, `body Text`, `fields JSON`, `doc_keys JSON`, `status String(12)`
(`open | answered | accepted | returned | cancelled | expired`), `answer JSON`, `answered_at`, `due_at`,
`remind_days JSON`, `meeting_id` FK SET NULL, `source_type String(20)`, `source_id`, `case_id` FK SET NULL,
`reviewed_by`, `reviewed_at`, `review_note Text`, `created_at`. Indexes `(user_id, status)`, `(org_id, status)`.

**Onboarding additions** (0112): `org_import_rows.edited_by Integer`, `edited_at DateTime`, `dup_of_row Integer`;
`org_onboarding_cases.last_reminded_at DateTime`; `org_members.student_code` is unchanged (`String(40)`).
A registry row `passport` in `identity_fields` (data, same revision) so an activated passport is matched.

**`org_terms.kind`** gains the value `makeup` (fits `String(8)`, no DDL).

**`org_transfer_credits`** (0114, phase 6): `org_id`, `user_id`, `case_id`, `source_course String(200)`,
`source_grade String(20)`, `source_credits Float`, `course_id` FK SET NULL, `decision String(12)`
(`credited | not_credited | pending`), `counts_in_gpa Boolean`, `decided_by`, `decided_at`, `note Text`.

**`org_rule_sets`** (0115, phase 7, only if Q6 says yes): `org_id`, `key String(40)`, `label_ar/en String(120)`,
`program_id`, `from_cohort String(20)`, `rules JSON`, `active`.

Migrations: `0110_student_status` (down_revision `"0101"`), `0111_student_asks`, `0112_onboarding_inline_fix`,
`0113_student_lifecycle_help` (help pages + guide rows into seeded databases, as 0100 did),
`0114_transfer_credits`, `0115_rule_sets`. All through `migrations/helpers.py` (idempotent), downgrades drop
only what the revision made.

Settings (JSON, no DDL): `organizations.settings.lifecycle` = `{decision_matrix, struggling_rule,
side_effects, reminders, file_log}`; the progression rules extend `settings.registrar` (below); entry policy
stays in each type's `chain` / `settings`.

### 4.2 Student types added to the presets

`student_equivalent` (معادلة: IGCSE / American, S14), `student_technical` (دبلومات فنية, SCU test, S17),
`student_second_degree` (حملة المؤهلات العليا, S6), `student_affiliated` (انتساب, with a field
`affiliation_kind: regular | directed`, S6), `student_special_program` (برامج خاصة بمصروفات, S10),
`student_visiting` (visiting / listener / audit, S10, S9). Existing four stay. Azhar and private presets get
the subset that applies (private / ahlia rules are unverified in RESEARCH §8, so their lists are a starting
point the institution edits). Disability route and ex-military route are **fields** on `student_new`
(`admission_basis`), not separate types: their documents differ by one or two conditional items.

### 4.3 Rule set extensions (`registrar/policy.py`, every key optional, defaults = today's behaviour)

| Block | Keys (default) | Source |
|---|---|---|
| `scale_preset` | `gpa4_default` (today's) · `gpa4_cairo_law` · `gpa5` · `traditional_names` | §4.2 scales S9, S10, S12; §4.1 grade names S7 |
| `pass` | `course_min_pct` (50), `final_min_pct` (none) | §4.1 pass mark S9, S12, S10 |
| `traditional` | `max_carry` (2), `max_carry_specialised` (none), `years_inside` (2), `outside_chances {first:0, middle:1, final:3}`, `five_year_rule` (on), `repeat_cap_letter` (pass), `second_round` (off), `promotion_basis` (`carry_limit` · `min_percent` · `min_gpa`) | §4.1 S3, S9, S12, S5 |
| `standing` | `warning_basis` (`cgpa`), `skip_first_term` (off), `reset_on_recover` (on), `warning_load_max` (12) | §4.2 warning S10, S11, S9 |
| `dismissal` | a list of rules, each on / off with its number: `consecutive_warnings` (6), `early_gpa {below:1.0, terms:3}` (off), `cgpa_after {below:1.5, term:4}` (off), `max_years` (8), `unregistered_terms {consecutive:2, total:3}` (off) | §4.2 dismissal S10, S11 |
| `final_chance` | `terms` (2 + summer), `min_credits_pct` (75) | S10, S11 |
| `retake` (extends) | `improvement_max` (5), `failed_cap_letter` (none), `improvement_count` (`best`) | §4.2 repeat S10, S11, S9, S12 |
| `suspension` | `max_years` (2), `granularity` (`year`), `request_by_week` (none), `exclusions []`, `counts_toward_duration` (no), `fees_due` (no) | §5 S5, S6, S9–S12 |
| `postponement` / `reenrolment` / `withdrawal` / `excuses` | as RESEARCH "Enrolment changes" defaults | §5 |

`dismiss_after_probations` (defined, never read) becomes an alias of `dismissal.consecutive_warnings`.
Every result of a rule is a **recommendation** unless the matrix marks that decision "automatic".

### 4.4 Endpoints

New router `features/org/students/api/org_students_router.py`, prefix `/api/v1/org/orgs/{org_id}/students`
(registered before `org_public_router`), services in `features/org/students/` (`file.py`, `status.py`,
`timeline.py`, `asks.py`, `rules_engine.py`, `access_log.py`, `meetings.py`).

| Route | Right | Notes |
|---|---|---|
| `GET /` `?q=&status=&standing=&flag=&program_id=&level=&missing=1&page=` | `students:view` | the Students list in one call: member + academic + status + `missing_count` + summary counts |
| `GET /{uid}/file` | `students:view` | header + overview; writes `student.file_viewed` |
| `GET /{uid}/timeline?kinds=&before=` | `students:view` | merged read: status events, `org_case_events`, `org_level_advances`, per-term results from `org_registrations`, complaints (`complaints:view` on the dept), meetings with a source, asks, governance items where the student is the beneficiary (`workflow`), advising rows only with advising access |
| `GET /{uid}/missing` | type module `view` | `{photos, documents, fields}` with the rule text and due dates |
| `GET /{uid}/status` · `GET /status/options?uid=` | `student_status:view` | current values + the changes the caller may make (from the matrix) |
| `POST /{uid}/status` | per matrix: `student_status:update` or `:approve` | `{dimension, to, key?, reason_code, reason, decision_no?, decision_date?, effective_from?, effective_to?, effects?, source?}` → event. 409 `bad_transition`, 422 `reason_required`, 422 `decision_no_required`, 403 `needs_body` (then use propose) |
| `POST /{uid}/status/propose` | `student_status:insert` | opens a recommendation (`OrgDecision`, kind `status_change`) for the deciding body |
| `POST /status-events/{eid}/undo` | same as the original, or `:approve` | `{reason}`; 409 `not_latest`, 409 `already_reverted` |
| `GET /requests?tab=` | any of the source rights | the inbox (§3.6), each row with its source and `can` |
| `GET /asks?status=` · `POST /{uid}/asks` · `POST /asks/{id}/{accept,return,cancel,remind}` | `students:update` (fullscreen: `student_status:update`) | a meeting ask answers 409 `attendees_busy` (with `busy`) unless `force` |
| `GET /{uid}/access-log` | `audit:view` | from `org_audit_log` |
| `GET|PUT /settings` · `POST /settings/try` | `academic:view` / `academic:update` | lifecycle settings + the "Try it" dry run for one student |
| `GET /rules/presets` | `academic:view` | bylaw presets (data files in `data/lifecycle_presets/`) |

Student side (`/api/v1/org/me/…`, added to the member router):
`GET /me/asks` (open asks across my organizations, with `presentation`), `GET /me/asks/{id}`,
`POST /me/asks/{id}/answer`, `GET /public/{org_id}/my-status` (my status, standing, flags I may see, and the
reason text of the last change). `GET /me/home` gains `asks: [...]` (always present, max 3), so the home needs
no new request.

Changed, all backward compatible (old fields and behaviour kept):

- `POST …/complaints/{cid}/meeting`: gains `force` and the busy check; **a body without `force` from an old
  app keeps working unless the student is busy**, in which case it now answers 409 `attendees_busy` with the
  same shape the calendar uses. See Q9: the alternative is to keep the old route unchecked and add a new one.
- `PATCH …/onboarding/imports/{b}/rows/{row_id}` (new) and `GET imports/{b}` rows gain `id`, `dup_of_row`.
- Onboarding chain step `need` accepts `{user_ids: [...]}` and `{council_id}`; `approve` on a council step
  requires `decision_no` + `decision_date`. Old steps unchanged.
- `service.activate` generates `student_code` from `student_code_pattern` when set (tokens `{yy}`, `{yyyy}`,
  `{program}`, `{seq:5}`), and writes `admission_route`, `enrol_status = enrolled`, the `transferred_in` /
  `affiliated` flags and the first status event.
- `POST /me/onboarding/{id}/documents` and `PATCH`: allowed on an `active` case for items still missing (not
  only `conditional`).
- `service.duplicates`: passport vs members; new soft warning `enrolled_in_sibling_org`.
- Registrar: `evaluate` adds block `enrolment_not_active`; `recompute` and `promote` call
  `rules_engine.after_results` (standing events, counters, notices, recommendations); `promote` stores
  repeaters; `graduate` writes the enrolment event. Responses unchanged; `GET students/{uid}/record` gains
  `enrol_status`, `acad_standing`, `flags`.
- `GET /orgs/{o}/members` rows gain `missing_count` and `status_chip` (extra keys only).
- Old staff reads that expose a whole student (`GET registrar/students/{uid}/record`, the advising 360 open,
  the entity page when called with an org) also write `student.file_viewed`.

Every line above goes into `sl-back/FLUTTER_API_CHANGES.md` under one heading per phase, and
`scripts/contract/export_api_paths.py --front …` is re-run by the lead after each phase.

### 4.5 Permissions

One new module in `org_catalog.MODULES`: **`student_status`** (scope org, group students), actions
`view` (see statuses, reasons and history) · `insert` (propose a change) · `update` (decide the changes the
matrix marks "officer") · `approve` (decide the changes the matrix marks "body", and undo others' decisions)
· `export`. `CONFLICT_RULES`: students are denied the whole module. Everything else reuses existing modules.

New system roles (`SYSTEM_ROLES`, backfilled by `ensure_system_roles`):

| Role key | Name | Maps to the owner's | Rights |
|---|---|---|---|
| `student_affairs_staff` | موظف شؤون الطلاب / Student affairs officer | staff | `students` view / insert / update / import / export · `onboarding` view · `member_documents` view · `student_status` view / insert · `enrollments` view |
| `registrar` | مسؤول القيد والتسجيل / Registrar | staff (senior) | the above + `students` approve · `enrollments` all · `academic` view · `student_status` update · `requests` view / approve |
| `complaints_officer` | مسؤول الشكاوى / Complaints officer | complaints officer | `complaints` all · `students` view · `student_status` view / insert / update (the matrix limits `update` to the flags by default) · `workflow` view |
| `student_affairs_head` | مدير شؤون الطلاب / Head of student affairs | manager | `registrar` + `student_status` approve · `onboarding` update · `complaints` view · `audit` view |

`dean` and `vice_dean_education_students` gain `student_status` approve; `viewer` gains `student_status`
view; org admins hold everything as today. The matrix can only narrow what a right allows, never widen it.

### 4.6 Notifications and reminders

All through `notify_users` (in-app + push, e-mail fallback) with `related_type = student_lifecycle`, live
event `student_lifecycle` (added to `live_update_service.py` and `LiveEvents`), deep link
`/org/:orgId/students/:uid` for staff and "My status" / the ask page for the student.

- To the student: every status and standing change with its reason in his language (RESEARCH §4.2, S11:
  warnings and dismissal are notified in writing); an ask; a meeting (existing calendar notice); a reminder.
- To staff: a new recommendation or request for the body (holders per the matrix); an answered ask.
- **Sweep** `features/org/students/sweep.py`, called from the existing hourly `org_onboarding_tick` (no new
  scheduler entry): incomplete files without a due date (default every 7 days, at most 4, then a staff task);
  open asks at due −3 / −1 and on expiry; suspensions ending in 14 days; `enrol_until` reached → resume.
- Attention: new org key `student_requests` → tab `org.people`; the student's open asks count on `home`.

### 4.7 Read-access logging

`access_log.viewed(db, ctx, uid, section)` writes `audit(action="student.file_viewed", entity="student",
entity_id=uid, meta={section})`, skipped when the same actor opened the same section of the same student in
the last 30 minutes (setting `lifecycle.file_log.window_minutes`, 0 = log every open). It is never
perm-affecting. Exports of student lists write `student.exported` with the count and filters.

### 4.8 Kill switches, help ids, features guide

| Kill-switch key (`feature_catalog.py`) | Hides |
|---|---|
| `org.students` | the Students section and unified file (People falls back to Members + Admissions) |
| `org.students.status` | status changes, the status chip, the timeline's undo |
| `org.students.auto` | automatic standing / recommendation rules (results still compute as today) |
| `org.students.asks` | ask the student + its student side |
| `org.students.missing` | the missing-data badge and sheet |
| `org.students.rules` | the Students & study rules settings pages |

Help ids (`data/help_seed.json` + `page_ids`, migration 0113): `org.students`, `org.students.file`,
`org.students.requests`, `org.students.status`, `org.students.rules`, `me.asks`, `me.status`. Existing
`org.onboarding.import` gains a section on inline fixes. `test/ui/help_ids_test.dart` covers them.

`data/app_features_guide.json` entries (group Organizations): Students list, Student file and timeline,
Missing data, Student statuses and undo, Ask the student / request a meeting, Student requests inbox,
Students & study rules, My status and my requests (student). Each with roles, ar + en name, place, steps and
its kill-switch keys.

---

## 5. Phased delivery

Rules for every phase: three agents at most (**B** backend, **F1**, **F2** front); nobody edits a file
outside its list; **shared files are edited only by the lead, after the wave**, with small additions:
`main.dart`, `app_navigator.dart`, `translation.json`, `feature_catalog.py`, `app_features_guide.json`,
`FLUTTER_API_CHANGES.md`, `test/contract/*.json`, `org_catalog.py`, `org_dashboard_screen.dart`,
`main.py` (router include), `scheduler_service.py`. Agents hand the lead a "shared additions" note instead.
Tests are targeted: each agent runs only the files it lists plus `flutter analyze` on its paths.

**Phase 0 — Contract (lead only).** `docs/student-lifecycle/CONTRACT.md`: the payloads of §4.4, codes,
enum values, the matrix shape; D-1400 – D-1412 drafted in `docs/DECISIONS.md`. Acceptance: the owner's
answers to §7 are folded in.

**Phase 1 — See the student whole (read only).**
- B: `data/student_lifecycle_models.py`, `migrations/versions/0110_student_status.py`,
  `features/org/students/{__init__,file,timeline,access_log}.py`, `…/api/org_students_router.py` (list, file,
  timeline, missing, access-log). Test `tests/org_v2/e2e_students_file.py`.
- F1: `features/org/students/students_models.dart`, `students_api.dart`, `students_page.dart`,
  `students_parts.dart` (status chip, missing badge). Tests `test/org/students_models_test.dart`,
  `test/ui/students_page_layout_test.dart`.
- F2: `features/org/students/student_file_page.dart`, `student_timeline.dart`, `student_file_tabs.dart`.
  Test `test/ui/student_file_layout_test.dart`.
- Lead: roles + module in `org_catalog.py`, `_peopleSubs` entry, kill switch `org.students`, router include,
  deep link, help + guide.
- Acceptance: in the local web app a registrar opens a student from the list, sees one chip, the journey and
  a merged timeline of existing history; the audit log shows one `student.file_viewed`; with `org.students`
  off the People section is exactly as before.

**Phase 2 — Statuses, decisions, undo.**
- B: `features/org/students/status.py` (transitions, matrix, effects, undo), status routes, registrar hook
  `enrolment_not_active` (one edit in `registrar/service.py`), `settings` routes. Test
  `tests/org_v2/e2e_student_status.py` (every transition row of §2.3, undo, `not_latest`, matrix denial).
- F1: `student_status_sheet.dart` (`StatusChangeSheet`), `student_status_models.dart` (pure: allowed
  changes, preview sentence, precedence chip). Tests `test/org/student_status_test.dart`,
  `test/ui/student_status_layout_test.dart`.
- F2: `student_settings_page.dart` + `student_matrix_page.dart` (group 5 of §3.8), undo row on the timeline
  (`student_timeline.dart`, owned by F2 from this phase). Test `test/ui/student_settings_layout_test.dart`.
- Acceptance: suspend a student with a reason and dates → chip changes, registration is blocked, the student
  is notified; undo → both lines on the timeline, registration works again; a complaints officer cannot
  dismiss.

**Phase 3 — Add Student completed.**
- B: presets (`data/onboarding_presets/*.json`), `onboarding/importer.py` (row patch, in-file duplicates),
  `onboarding/service.py` (student number, passport duplicates, sibling warning, completion on active,
  chain `user_ids` / `council_id`), `onboarding/api/org_onboarding_router.py`, `0112`, `students/sweep.py`.
  Tests `tests/org_v2/e2e_onboarding_inline.py`, `e2e_student_missing.py`.
- F1: `onboarding_import.dart` (inline fix), `onboarding_models.dart` / `onboarding_api.dart` additions.
  Tests `test/org/onboarding_models_test.dart` (extended), `test/ui/onboarding_layout_test.dart` (extended).
- F2: `students/missing_data_sheet.dart`, `students/add_student_sheet.dart`, the entry-policy picker in
  `onboarding_types_page.dart`, "Save and invite" in `onboarding_wizard.dart`. Test
  `test/ui/missing_data_layout_test.dart`.
- Acceptance: import a 20-row file with 3 bad rows, fix two inline, skip one, save; one saved student shows
  "3 missing", staff uploads a photo in the sheet and the count drops; a transfer type shows its documents.

**Phase 4 — Ask the student, meetings, complaints.**
- B: `0111`, `students/asks.py`, `students/meetings.py` (shared helper), ask routes, `/me/asks`, `/me/home`
  field, the complaint meeting route switched to the helper. Tests `tests/org_v2/e2e_student_asks.py`,
  extend `e2e_complaints_hub.py` (busy rule).
- F1: `students/student_ask_sheet.dart`, `students/student_asks_models.dart`, requests inbox
  `students/student_requests_page.dart`. Tests `test/org/student_asks_test.dart`,
  `test/ui/student_ask_layout_test.dart`.
- F2: student side: `org_must_ack.dart` (draw full-screen asks), `students/my_ask_page.dart`,
  `students/my_status_card.dart`; `org_services_pages.dart` (student strip + the two actions on the
  complaint thread). Tests `test/ui/my_ask_layout_test.dart`.
- Acceptance: the §3.9 flow end to end in the web app with two accounts, including a busy student and
  "Book anyway".

**Phase 5 — Rules and automatic movement.**
- B: `registrar/policy.py` (rule blocks, scale presets), `students/rules_engine.py`, hooks in
  `registrar/service.py` (`recompute`) and `registrar/traditional.py` (`promote`), `data/lifecycle_presets/`,
  `settings/try`. Tests `tests/org_v2/lifecycle_rules_unit.py` (pure, one case per RESEARCH variant),
  extend `e2e_registrar.py` and `e2e_traditional.py` by one scenario each.
- F1: settings groups 2–4 (`student_rules_pages.dart`, `student_scale_editor.dart`). Test
  `test/ui/student_rules_layout_test.dart`.
- F2: recommendations in the inbox (`student_requests_page.dart` is F1's in phase 4, moves to F2 here),
  promotion preview, "Try it" box (`student_rules_try.dart`), texts in `org_registrar.dart`. Test
  `test/org/student_rules_test.dart`.
- Acceptance: approve a term's grades for a seeded cohort → warnings are set with notices, the sixth
  consecutive one opens a dismissal recommendation, nothing is dismissed until accepted; a traditional
  cohort promotes with carriers and repeaters recorded.

**Phase 6 — Lifecycle requests and transfer credit.**
- B: governance categories `lifecycle.*` seeded per org with an action on final approval
  (`students/requests.py`), `0114`, transfer-credit routes, council step → real agenda item. Test
  `tests/org_v2/e2e_student_requests.py`.
- F1: student "My requests" entries (suspension, withdrawal, re-enrolment, excuse) in
  `students/my_requests.dart`. F2: `students/transfer_credits_sheet.dart` in the file's Academic tab.
- Acceptance: a student asks to suspend enrolment, the council approves, the status changes by itself with
  the decision number.

**Phase 7 — Finish.** Export Studio dataset for students with status columns, the report of status changes
per period, rule sets per cohort (if Q6), help pages and guide entries reviewed, real-app check of every
screen at phone and desktop widths in ar and en, PostgreSQL run of the new e2e scripts.

---

## 6. Proposals: where this plan deviates from or improves on the brief

- **P1 (D-1400) Dimensions instead of one status.** The brief lists statuses in five groups; the plan makes
  the groups real, independent fields with one chip on top. Reason: real students hold several at once, and
  a suspended student must return to the standing he had.
- **P2 (D-1401) "Struggling" is a flag with a configurable rule, not a status.** RESEARCH found no bylaw
  that defines it; the legal states are warning, repeating and final chance. As a flag it can be set by rule
  or by the complaints officer, and removed, without fighting the results.
- **P3 (D-1402) The system recommends, a person decides, for anything that removes a student.** The brief
  says transitions are "automatic from results". Standing is automatic. Dismissal, outside status and final
  chance are raised as recommendations with the rule and the evidence, because every bylaw gives that
  decision to a council (RESEARCH §7), and an automatic dismissal on a wrong grade is not reversible in
  practice. The matrix lets an institution make any of them fully automatic.
- **P4 (D-1403) No new request system.** Intake stays in onboarding cases; lifecycle requests ride on
  governance work items (chains, councils, votes, SLA, attachments already exist); rule findings ride on the
  registrar's `OrgDecision`. A fourth queue would split the reviewer's work. The inbox merges them on read.
- **P5 (D-1404) "Start from a bylaw" presets** (Law 49 traditional 2015; credit hours engineering style;
  credit hours law style; 5-point levels) fill the whole rule page, then every value is editable. Fifty
  switches with no starting point is where non-technical staff give up.
- **P6 (D-1405) "Try it" before saving a rule**, on a real student, with the reason in words.
- **P7 (D-1406) Student types = admission routes; study mode and fee class are fields.** Otherwise every
  route × mode (regular, affiliated, directed, special programme) becomes its own type and the list a clerk
  picks from grows past twenty.
- **P8 (D-1407) The timeline is a merged read, not a copied log.** Copying registrations and case events
  into a new table would drift; the only new log is the status events.
- **P9 (D-1408) File-open logging is deduplicated (30 minutes) and visible to the reader.** One row per
  click would bury the audit log; telling staff the open is recorded is fairer and deters casual browsing.
- **P10 (D-1409) A status change never silently drops courses or ends access.** The sheet asks. Undo then
  reverses exactly what was recorded.
- **P11 (D-1410) Full-screen asks reuse must-ack's guards** (who may send, due ≤ 7 days), so the strongest
  interruption cannot be used casually.
- **P12 (D-1411) A body's approval is recorded first as "decision number + date" by its secretary; the real
  council vote comes in phase 6.** It ships the gating early and matches how student affairs works on paper.
- **P13 (D-1412) Fix: the complaint meeting obeys `attendees_busy`.** Found while checking the brief's
  "reuse the busy rule".

---

## 7. Open questions for the owner (all 16 answered 2026-11-21: the default of each)

1. **Dimensions (P1).** Agree that a student has an enrolment status, an academic standing and flags, shown
   as one chip? *Default: yes.* **Answered 2026-11-21: default.**
2. **Dismissal and other removals (P3).** Recommendation that a body accepts, or fully automatic?
   *Default: recommendation; each institution can switch a rule to automatic.* **Answered 2026-11-21: default.**
3. **"Struggling" (P2).** A flag set by a rule (default: academic warning, final chance, or repeating the
   same year twice) and by hand, rather than a formal status? *Default: yes.* **Answered 2026-11-21: default.**
4. **Approval by a body.** Phase 2–3 record the body's decision number and date; the real council vote
   through Governance arrives in phase 6. Acceptable order? *Default: yes.* **Answered 2026-11-21: default.**
5. **New roles.** Add the four system roles of §4.5 (student affairs officer, registrar, complaints officer,
   head of student affairs) to every organization? *Default: yes, unassigned until an admin gives them.* **Answered 2026-11-21: default.**
6. **Rules per intake year.** Should students keep the bylaw they entered under (rule sets per cohort,
   phase 7)? *Default: not now; rules per institution with per-programme overrides, cohort versions later.* **Answered 2026-11-21: default.**
7. **Access after leaving.** When a student is dismissed, withdrawn or transferred out, keep read-only
   access to the record for a period? *Default: 90 days, an institution setting.* **Answered 2026-11-21: default.**
8. **Who sees what.** May the student see his own status, the reason and the decision number? May he see
   flags such as "struggling" and "special case"? *Default: status and reason yes; those two flags staff-only.* **Answered 2026-11-21: default.**
9. **Complaint meeting route.** Change the existing route to obey the busy rule (an old app then gets a
   clear 409 only when the student is busy), or leave it and add a new route? *Default: change it.* **Answered 2026-11-21: default.**
10. **File-open log.** One entry per staff member per student per 30 minutes, and tell staff it is recorded?
    *Default: yes to both.* **Answered 2026-11-21: default.**
11. **Duplicates across faculties.** Warn (not block) when the same national ID is enrolled in another
    faculty of the same university? *Default: warn.* **Answered 2026-11-21: default.**
12. **Incomplete-file reminders.** Every 7 days, four times, then a task for staff? *Default: yes, editable.* **Answered 2026-11-21: default.**
13. **Postgraduate thesis states** (registered, struck, defended). In this job or later? *Default: later;
    this job covers enrolment, suspension and cancellation for postgraduates, not supervision.* **Answered 2026-11-21: default.**
14. **Discipline.** Record the 13 penalties as status events and flags only (no investigation workflow)?
    *Default: yes, recording only.* **Answered 2026-11-21: default.**
15. **Fees.** Keep fees as a field (D-1204), so "fees unpaid" never blocks a status change by itself?
    *Default: yes.* **Answered 2026-11-21: default.**
16. **Private, ahlia and Azhar rules** could not be verified (RESEARCH §8). Ship their presets as editable
    starting points marked "review with your bylaw"? *Default: yes.* **Answered 2026-11-21: default.**
