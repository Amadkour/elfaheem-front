# Institutions v2: requirement checklist (2026-11-15)

Branch `feature/institutions-v2` in both repos. Decisions D-980 – D-999. Migrations 0089 (core, acting) and 0090 (notification preferences). Server tests are in `tests/org_v2/e2e_institutions_v2_p1 … p6.py`; app tests in `test/org/institutions_v2_p1 … p6_test.dart`.

| Spec | Requirement | Server | App | Decision |
|---|---|---|---|---|
| 4.1 | Every unit has a head; saving is blocked without one; "Assign me as head" | `org_dept_router` + governance entity + council create → 422 `head_required`, `head_self` | `org_unit_rules.dart` head picker + `AssignMeChip` in all four forms | D-982 |
| 4.1 | A head who leaves is replaced by an acting head (the manager), who is told | `institutions.cover_headless`, `access.effective_head`, live-only `head_id` | Acting chip, "N units have no head — Fix now" | D-981, D-983 |
| 4.1 | No secretary: the chair acts as secretary, reminded once | `secretary_acting`, one-time reminder | roster hint | D-983 |
| 4.2 | Protected core departments | `core` column; 409 `dept_core`; core set by study system | lock badge, no archive action | D-980 |
| 4.2 | Safe removal: impact, reassignment, archive before delete | `GET …/impact`, `reassign_to`, 409 `dept_has_open_items` / `dept_has_content` | archive sheet with impact cards and "Move open requests to" | D-984 |
| 4.2 | Councils with open agenda items are protected | 409 `council_has_open_agenda` | disabled with the reason | D-984, D-990 |
| 4.3 | "Do you want councils?" → faculty, departments or both; department picker | `governance/councils_setup.py`, `GET/PUT …/councils-setup` | `gov_councils_setup.dart` (`CouncilsChoiceView`) | D-989, D-990 |
| 4.4 | Head notified on every request, complaint and message; handler, manager for sensitive units, sender's confirmation | `notify.unit_recipients` on every path; platform complaint to an org unit → work item; `POST …/units/{id}/message` | "Message this department" | D-985, D-986 |
| 4.4 | Fallback chain: head → acting head → manager | `effective_head` | — | D-981 |
| 4.4 | In-app and push, dedupe, grouped bursts, preferences | flush dedupe, `_group_push`, `org_notify_prefs` (all / important / off) | `OrgNotifyPrefsPage` | D-987 |
| 4.4 | SLA: remind the head, then escalate to the manager | `jobs._tick_reminders`, `escalation.tick` (on by default) | — | D-988 |
| 4.4 | Tests prove a notice on every path | `e2e_institutions_v2_p2.py` (114 checks) | — | — |
| 5 | Guided, resumable setup wizard, core ones locked, heads step, councils, optional, review and launch with readiness | `…/institution/wizard`, `/readiness`, `/heads`, `/launch` | `org_institution_wizard.dart` | D-991 – D-993 |
| 5 | Academic units have courses, service units never do | `check_course_dept` | catalog explanation | D-963 |
| 6 | Admin institution roadmap with progress, warnings, next action | wizard `stages` | `org_institution_roadmap.dart`, `AppRoadmap` | D-994 |
| 6 | Student "My journey": now, important, can wait, register, file a request, who to contact, request status path | `GET …/me/journey` | `org_my_journey.dart`, `AppStatusPath` | D-995 |
| 6 | Heads and secretaries: what needs my attention | `GET …/me/attention-flow` | `org_attention_flow.dart` | D-996 |
| 6 | Premium, RTL, accessible, extends the design system | — | `lib/design/app_roadmap.dart`; a11y, RTL and layout harness tests | D-997 |
| 7 | Carry-over: voting, reminders, minutes, forwarding, freeze-screen messages, permissions | unchanged from v1 (D-960 – D-979), all v1 tests still pass | — | — |
| 8 | Background health check, orphan sweep, institution-health dashboard | `institutions.health`, `health_all` (hourly sweep, daily notice) | Institution health page and card | D-998, D-999 |
| 8 | Delegation while a head is away | existing `OrgWorkDelegation` | `gov_delegations_page.dart` | D-057 |
| 9 | Safe migrations, idempotent jobs | 0089/0090 add columns and a table only; repair, sweep and notice are idempotent | — | — |

## Not done

- **PostgreSQL:** migrations 0089 – 0090 have only been checked on SQLite (Docker was not running).
- **Real web app:** the screens have not been checked in the real web app with real data.
- **Complaint threads:** a platform complaint's own thread is not synced with the department item it creates.
- **Optional, not built:** a daily digest e-mail for managers, and automatic delegation for a head's planned leave.
