# Institutions v2: plan (2026-11-15)

Branch `feature/institutions-v2` in both repos, from production (back 4916241, front 6a7351a3). Decisions D-980 – D-999. Migrations from 0089.

## Phase 0: audit (confirmed in code)

| # | Gap | Evidence |
|---|---|---|
| G1 | Any unit can be created with no head. Catalog apply never sets one. | `org_dept_router.py:277` (`head_user_id` optional), `institutions._create:375`; app forms show "No manager" |
| G2 | A council can have no chair. A head change later does not update the council chair. | `OrgCouncil.chair_user_id` nullable; `entities.ensure_council:131` sets it once |
| G3 | When a head leaves, is suspended or loses the seat, nobody is told and nobody covers. A suspended head still counts as head. | `org_admin_router.py:929` deletes seats silently; `access.head_id:30` has no `live_team` filter |
| G4 | Core departments can be deleted. A hard delete orphans open requests. Archiving leaves open requests and the council behind. | `delete_department:367` checks only complaints, forms, files, news and courses |
| G5 | A council with open agenda items can disappear with its department. | No council check; sessions cascade |
| G6 | A complaint to an org department through the platform complaint form notifies platform admins only, never the department or its head. | `complaint_service._notify_new:229` |
| G7 | The org manager is never told about new items, even for sensitive units. Forward and reassign do not tell the previous owner. | `notify.item_received`, `routing._apply:211`, `items.assign:683` |
| G8 | If a unit has no head and no assignee, an SLA breach reaches nobody but the item is still stamped as told. | `jobs._tick_reminders:105` |
| G9 | No notification preferences exist (except chat mute). No dedupe beyond each router's own `told` sets. | `notification_service._dispatch` |
| G10 | No "Do you want councils?" choice: a department council is always created for every academic department. | `ensure_council` on create |
| G11 | No setup wizard: a dismissible checklist card only, with no step for heads or councils. | `org_setup.setup_state:51`, `home/org_setup_checklist.dart` |
| G12 | No single attention view for heads, no journey map for students, no job that flags headless units or stale requests. | 6 separate lists; `jobs.py:80` |

## Core (protected) departments: researched list

Egyptian faculty administration (executive regulations of the universities law), mapped to the existing catalog keys. These are created automatically, can be renamed, and are never deleted:

- **Always:** Student Affairs, Exams Control, Youth Care, Staff Affairs, Medical Care (student health).
- **Credit hours:** Academic Advising, Admission & Registration (the registrar).
- **With graduate programs:** Postgraduate Studies.

Change from the brief: under the traditional system, registration is part of Student Affairs, so the registrar is core only under credit hours.

## Phases (each: server + app + tests, then a short report)

1. **Data rules (D-980 – D-984), migration 0089.**
   - **Columns:** `org_departments.core` and `org_dept_members.acting`.
   - **Manager:** one `manager_ids(org)` helper (dean holders, else org admins, live only).
   - **Head lookup:** `effective_head` gives the live head, then the acting head, then the manager. `head_id` gets the live filter.
   - **Creating a unit:**
     - Create and update answer 422 `head_required`; `head_self: true` is the "Assign me as head" shortcut.
     - Catalog apply makes the caller the acting head of each new unit.
     - A council's chair follows its department's head.
   - **Head leaves:** when a head is removed, suspended or loses the seat, the manager becomes acting head and gets a notice to assign a replacement.
   - **Secretary:** if a council has no secretary, the chair acts as secretary and is reminded once.
   - **Delete:**
     - A core unit answers 409 `dept_core`.
     - `GET …/impact` returns the counts of courses, open items, councils and members.
     - Archiving needs `reassign_to` when open items exist.
     - A unit whose council has open agenda items answers 409.
     - Hard delete only for an empty unit.
   - **Existing data:** an idempotent repair gives every headless unit an acting head and marks the core units.
2. **Notification routing (D-985 – D-988).**
   - **Recipients:** one `unit_recipients(item)` builds the effective head and the chain, the handler, the manager (for sensitive units and escalations), and the sender's confirmation.
   - **Every path uses it:** create, forward, reassign, the platform complaint to a department (now mirrored into a work item), and the legacy complaint.
   - **Dedupe and grouping:** one recipient set per event, and bursts grouped through the existing `_group_push`.
   - **Preferences:** a simple per-user push setting for org requests (all / important only / off). In-app rows are always created.
   - **SLA:** the reminder goes to the effective head (never nobody), then escalates to the manager.
   - **Tests:** a new e2e script asserts a notification row on every path.
3. **Councils question (D-989 – D-990).**
   - **Setting:** `governance.councils` = none / faculty / departments / both, plus the chosen department ids.
   - **Department councils:** created only for the chosen departments.
   - **Existing orgs:** the mode is set from what they already have, so nothing changes for them.
   - **Turning it off:** refused while a council has open agenda items.
4. **Setup wizard (D-991 – D-993).**
   - **Steps:** basics and study system → departments (core ones pre-checked and locked) → heads ("me" shortcut) → councils → optional (team, routing, meeting days, deadlines) → review and launch.
   - **Resumable:** the step is stored in `settings.institution.wizard`.
   - **Readiness:** `GET …/readiness` lists anything missing.
   - **Reuse:** it reuses the S1 study-system and catalog views, and replaces the checklist card for universities and faculties.
5. **Roadmap UX (D-994 – D-997).**
   - **Shared widget:** one `RoadmapNodes` widget in `lib/design`, built from `RoadmapPathView`.
   - **Admin:** an "Institution roadmap" (Basics, Departments, Heads, Councils, Launch) with progress, warnings and the next action.
   - **Student:** a "My journey" map at the top of the member home (now, important, can wait; register a course; file a request; who to contact) with each request shown as a tracked path. The rest moves under "More".
   - **Heads and secretaries:** one "Needs my attention" page (new requests, votes waiting, overdue).
6. **Health and polish (D-998 – D-999).**
   - **Hourly health job:** repairs headless units, flags stale requests and chairless councils.
   - **Manager:** an "Institution health" card.
   - **Quality checks:** layout harness, a11y and RTL tests, and the final checklist.

**Optional, not built unless asked:** a daily digest e-mail for managers; a head's planned leave that sets up delegation automatically (delegation itself already exists).

**Defaults I chose for open questions:**
- The manager is the dean when one is assigned, otherwise the first org admin.
- Sensitive units (Advising, Medical Care, Student Affairs) tell the manager in-app on every new item; their pushes are grouped.
