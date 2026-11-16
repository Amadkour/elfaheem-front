# Institutions module: plan (2026-11-15)

Branch `feature/institutions` in both repos (from origin/production). Decisions D-960 – D-979, migrations from 0085.
The module extends what exists (governance D-057, D-890 – D-893, advising D-289). It adds no second model.

## What already exists (reused as-is)

- Request and complaint work items, their timeline and audit trail (`OrgWorkItem`, `OrgWorkEvent`).
- Manual routing to a department, a person or a council, escalation, recall and the approval chain (D-141).
- Department presets with one-click creation, but only for service departments.
- A department council is created with every scientific department, and a faculty council can be created on demand.
- Council settings: session day and time, cutoff, vote deadline hours, quorum %, majority %, tie rule (D-893).
- Agenda, voting with a note and time, minutes export.
- Dated delegations, and the submitter never votes on their own item.
- SLA hours with one notice to the head.
- The member's "my items" page and the governance dashboard.

## Gaps and the changes I will make (my improvements are marked +)

1. **Study system per institution.** A setting on the organization: *traditional* or *credit hours*. Programs inherit it and may still override it, since some faculties run both. It drives terms and labels:
   - credit hours: GPA, add/drop, hours, advisor sign-off;
   - traditional: grade labels (تقدير), academic year, second-round exams.
2. **Department catalog.** Two groups, Academic and Service, each template with suggested request types ("elements"):
   - **Minimum set**, created on setup: Student Affairs, Exam Control, Youth Care, Staff Affairs. Academic Advising is added when the system is credit hours, and Postgraduate Studies when the org runs graduate programs.
   - **Optional set:** Medical Unit, Library, Quality Assurance, IT, Graduates, International Relations, Training, Admissions & Registration, Scholarships & Aid, Community Service.
   - Ticking a template creates it with its request types. Custom departments of either type remain.
   - Courses may only belong to an academic department, checked on the server. Existing courses are left alone.
3. **Audience per department:** students, staff, other departments, or a mix. It filters where the "New request" entry appears.
4. **Roles.** Add Dean (عميد), Vice Dean (وكيل) with three portfolios, and Council Secretary (أمين المجلس). The secretary has the chair's powers on that council.
   - The admin sets the faculty council's chair, secretary and members; the head sets the department council's.
5. **Meeting setup:** mode (online or in person), location or link (an online meeting creates the calendar meeting), and a review deadline per session that defaults from the council setting.
6. **Agenda:** the chair can write an item directly (+ from a decision template), alongside items forwarded from requests. Forwarding straight to the faculty council stays.
7. **Reminders.**
   - Automatic notices at 48 h, 24 h and 2 h before the deadline, to non-voters only. Each fires once (one row per item, member and step).
   - A manual "Remind non-voters" before or after the deadline, limited to once an hour.
8. **Results:** a status chip per item. Tapping an item lists approve, reject and not responded, each name with its time, plus weights.
9. **Weighted voting.** Weights run 1 – 3 (default 1). No member may hold more than 40 % of the council's total weight (+ guardrail).
   - Quorum is the weight of members who responded, divided by the weight of all eligible members, compared with `quorum_pct`. The default is 50 %, a configurable convention: the law's text was not found.
   - An item passes when approving weight > `majority_pct` of the weight cast. It is **fully approved** when every vote cast approves, and **partially approved (بالأغلبية)** otherwise.
   - A tie follows `tie_rule`, which defaults to the chair's side.
10. **Official decisions (+).** Each decision gets a number, session no. / item no. / year (e.g. 3/7/2026). Decision templates cover:
    - medical or other excuse, re-enrolment, course equivalence (مقاصة), grade appeal;
    - study-plan approval, exam committees, staff leave, thesis registration.
    Minutes are exported as an official PDF with the numbers.
11. **Conflict of interest (+):** a member can declare one per item, which removes them from the vote and the quorum count and is logged. Delegation when a member is away already exists and is reused.
12. **SLA escalation (+).** A request past its SLA goes up automatically to the head, then to the vice dean, once per step. The student keeps seeing its status on "my requests", which exists.
13. **Messaging.**
    - Staff can message any student of their org; a department can message a complainant.
    - Delivery is normal, push, or **must-acknowledge** (the freeze screen).
    - Guardrails on must-acknowledge:
      - only the dean, vice deans, admin or department heads may send it, and a head only to their own audience;
      - it needs an expiry of at most 7 days, and each person sees at most one at a time;
      - it never appears inside a live exam or a live room;
      - the sender must type a reason, everything is audited, and a sender may send at most 3 a day.
14. **Dashboards (+):** a dean view across departments (open requests, overdue, council items pending). Head view = the existing dashboard.

## Data model (migration 0085, additive only)

- `organizations.study_system`.
- `org_departments`: `audience` JSON, `template_key`.
- `org_councils`: `secretary_user_id`, `meeting_mode`, `meeting_location`, `meeting_link`.
- `org_council_sessions.review_deadline`.
- `org_council_members`: `weight`, defaulting to 1.
- Agenda items: `coi_user_ids` (conflict of interest), `decision_no`, `template_key`.
- New table `org_council_reminders`, unique on (item, user, step).
- New table `org_messages` with `org_message_acks`.
- Roles added to `SYSTEM_ROLES`.

## Screens (all on the existing org page kit)

- Settings → Study system (two cards).
- Settings → Departments catalog (two tabs, a tick list, a request-type tick list per template).
- The department wizard gains Head, Team and Audience steps.
- Council settings gain the Meeting step and member weights.
- The session screen gains Remind, per-item results and a Write item action.
- Item detail shows the vote list.
- A Dean dashboard card.
- Message composer (recipient, delivery type) and the student's must-acknowledge overlay.

## Slices (each ships with tests: backend e2e under tests/org_v2, app tests under test/org)

| Slice | Content |
|---|---|
| S1 | Study system + department catalog + minimum set + audience + roles + course check |
| S2 | Councils: secretary, meeting setup, chair-written items, reminders, named results, weights, partial approval, decision numbers |
| S3 | Routing rules by category, SLA escalation, decision templates, conflict of interest, minutes PDF |
| S4 | Messaging + must-acknowledge |
| S5 | Dean dashboard, features guide, help pages, final checklist |

Every new feature is added to `../back/data/app_features_guide.json` and its kill-switch keys to `feature_catalog.py`. I will not deploy: the work is merged to organizations and production after you say so.
