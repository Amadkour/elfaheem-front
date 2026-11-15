# Institutions module: requirement checklist (2026-11-15)

Server paths are in `nextbrain-back`, app paths in `nextbrain-front`. Branch `feature/institutions` in both.
Decisions D-960 – D-979. Migrations 0085 – 0088.

| Spec | Requirement | Server | App | Decision |
|---|---|---|---|---|
| 3.1 | Study system: traditional or credit hours; programs inherit it | `features/org/core/institutions.py`, `GET\|PUT …/study-system` | `lib/features/org/org_institutions.dart` (Settings → Study system) | D-960, D-961 |
| 3.2 | Catalog of academic and service departments; one-click creation; suggested request types; minimum set at setup; custom departments | `institutions.py` (catalog, `apply`, `_insert_org` hook) | `org_institutions.dart` (Settings → Department catalog) | D-962 |
| 3.2 | Courses only in academic departments | `institutions.check_course_dept` (plain legacy departments still allowed) | `org_courses_page.dart` department picker | D-963 |
| 3.3 | Head and team | existing team endpoints, `entities._grant_head_role` | existing team tab | D-057 |
| 3.3 | Audience | `org_departments.audience` | `org_departments_page.dart` ("Who can send it requests?") | D-963 |
| 3.3 | Requests and complaints in every department | existing `OrgWorkItem`, routing | existing governance pages | D-057 |
| 3.3 | Manual routing to a department, person, department council or faculty council | `governance/routing.py`, `forwarding.py` | `gov_route_sheet.dart` | D-057, D-890 |
| 3.3 | Automatic routing rules | `routing.py` + `…/entities/{id}/auto-routing` | `gov_institutions_s3.dart` (department tab) | D-971 |
| 3.4 | A department council per academic department; optional faculty council | `entities.ensure_council`, `create_faculty_council` | `gov_councils_page.dart` | D-057 |
| 3.4 | Chair, secretary with the chair's powers, members | `councils.py`, `access.can_manage_council` | `gov_council_s2.dart` (roster card) | D-965 |
| 3.4 | Meeting day, online or in person, place or link, review deadline | `council_meetings.py`, `OrgCouncil` meeting fields | meeting step, session header | D-966 |
| 3.5 | Agenda items written by the chair or forwarded from requests; skip to the faculty council | `agenda/write`, `escalate_agenda`, forwarding | "Write an item", template picker | D-967, D-973 |
| 3.5 | Approve or reject with a comment before the deadline | `cast_vote` | existing vote UI | D-057 |
| 3.5 | Automatic reminders before the deadline (once each, every tick) | `jobs._tick_council`, `org_council_reminders` (48 h, 24 h, 2 h) | — | D-968 |
| 3.5 | Manual reminder, also after the deadline | `POST …/remind`, once an hour, until the session closes | "Remind non-voters" | D-968 |
| 3.5 | Results: status, who voted what and when, who has not answered | `council_views.agenda_json` | status chip, "Who voted?" sheet | D-969 |
| 3.5 | Weighted voting, quorum, full or partial approval | `councils.tally` (weights 1–3, 40 % cap) | weights on the roster card | D-969 |
| 3.5 | Audit trail; minutes as a PDF | `OrgWorkEvent`, `audit()`, `export_data` minutes `official` block | Export Hub minutes | D-974 |
| 3.6 | Staff → any student; department → complainant | `features/org/core/messaging.py`, `org_messages_router.py` | `org_messages.dart`, "Message the submitter" | D-975, D-976 |
| 3.6 | Normal, push or must-acknowledge (freeze screen), with guardrails | `messaging.py` (who may send, reason, expiry ≤ 7 days, 3 a day, one at a time) | `org_must_ack.dart` (`OrgMustAckHost`), `lib/core/live_focus.dart` | D-977, D-978 |
| 4.2 | Dean, vice deans, council secretary | `org_catalog.SYSTEM_ROLES` | role titles in access / member forms | D-964 |
| 4.4 | Role-based permissions | `access.py`, `can` flags in payloads | buttons follow `can` | all |
| 4.5 | Sensitive data | complaint-linked messages: department team and submitter only; audit | — | D-976 |
| 4.7 | Tests | `tests/org_v2/e2e_institutions_s1 … s5.py` | `test/org/institutions_s1 … s5_test.dart` | — |
| 4.8 | Reliable scheduled jobs | unique rows for reminders and escalations | — | D-968, D-972 |
| 5 | Decision numbers | numbered when a session closes (session/item/year) | on items and minutes | D-970 |
| 5 | Quorum rules | `quorum_pct` with weights | council settings | D-893, D-969 |
| 5 | Conflict of interest | `coi_user_ids`, declare route | "I have a conflict of interest" | D-969 |
| 5 | Delegation while away | existing `OrgWorkDelegation` | `gov_delegations_page.dart` | D-057 |
| 5 | Deadlines and escalation for requests | `org_work_escalations`, `sla_hours` per request type | SLA field, escalation switch | D-972 |
| 5 | Request status visible to the student | existing "my items" | `gov_member_pages.dart` | D-057 |
| 5 | Decision templates | 9 templates, `GET /decision-templates` | template picker | D-973 |
| 5 | Dashboards for heads and deans | `governance/faculty.py` (`scope=faculty`) | "Faculty overview" card and page | D-979 |

## Not done

- **Help pages:** the new pages reuse `org.settings` and `org.departments`; new help ids need server help rows first.
- **"My votes":** does not show conflict-of-interest declarations.
- **Not run:** a PostgreSQL run of migrations 0085 – 0088, and a check in the real web app.
- **Legal rules:** quorum, majority and meeting frequency are configurable conventions; the legal text was not found.
