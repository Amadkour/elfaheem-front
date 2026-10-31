# Organization Dashboard — one dashboard for every non-student org role (D-103)

Status: done (2026-10-31). Branch `feature/live-hardening` in both repos.

## What and why

ONE organization dashboard (the existing `OrgDashboardScreen` shell, refitted in place — no second dashboard, no v2
route) for every person in an organization who is not a student there: org admin, sub-admin (admin_assistant /
granted roles), staff (teacher, teacher_assistant, department team) and members without any right. Students are
blocked from the dashboard and its APIs (403 `student_forbidden`, owner's choice "dashboard only": grants a student
already holds keep working on the other staff routes).

Home has three sections, ordered by role:
- **admin / sub-admin** (`layout: insights_first`): Insights · Needs your attention · Departments
- **staff / member** (`layout: actions_first`): Needs your attention · Departments · Insights (when allowed)

Phones stack the sections in that order; desktop puts them in two balanced columns.

## Server (back) — all under `/api/v1/org`

### 1. `GET /mine?members=1` (additive)
Without the parameter: unchanged (older apps). With `members=1` the list ALSO holds every approved org where the
caller is a live, non-student member without any right (`OrgMember.role` in teacher · teacher_assistant ·
admin_assistant), with empty `permissions` / `dept_permissions`, and every item gains:
- `member_role`: the `OrgMember.role` there (`null` when the access is only inherited / a grant without membership)
- `access`: `admin` | `staff` | `member` (`admin` = org admin or platform admin; `staff` = any right; `member` = none)

Orgs where the caller's `member_role` is `student` are left out of the `members=1` list (dashboard block).

### 2. `GET /orgs/{id}/dashboard` (additive)
- Accepts members without rights (`access: member`) — today `resolve_ctx` answers them 403 `org_forbidden`. They
  get the org, their departments (team membership), their tasks and no org-wide KPIs (`kpis: null`,
  `recent_activity: []`, `series: null`).
- 403 `{"code": "student_forbidden"}` when the caller's live `OrgMember.role` in this org is `student` (even with
  grants).
- New keys: `access`, `member_role`, `layout` (`insights_first` | `actions_first`), `can_insights` (bool),
  `departments[].tabs[]`, `tasks` (first 8, same shape as §3) and `tasks_total`.
- `departments[].tabs[]` = the department-scoped modules the caller may VIEW there, in this order and only when the
  department has the matching feature switched on (`team` ↔ `members`; `courses`, `enrollments`, `councils`,
  `export_templates` need no feature):
  `{ "key": "courses", "levels": {"view": true, "insert": false, "update": true}, "label_ar": "…", "label_en": "…" }`
  keys: courses · enrollments · team · announcements · forms · complaints · materials · workflow · councils ·
  data_lab · certificates. Org admins get every tab with every level.

### 3. Tasks ("Needs your attention", one-tap actions)
`GET /orgs/{id}/tasks?limit=20&cursor=` → `{ items: [Task], total, next_cursor }`, sorted by urgency (high → low)
then oldest first. Only what the caller may decide or must do.

```
Task = {
  "id": "org_join:123",            // <kind>:<source id>, stable
  "kind": "org_join" | "unit_join" | "program_choice" | "form_response" | "work_item" | "registrar_decision"
        | "council_vote" | "complaint" | "consent",
  "title_ar", "title_en",           // "Ahmed Ali wants to join" / "طلب انضمام من أحمد علي"
  "subtitle_ar", "subtitle_en",     // department / form / course, one line
  "person": {"id", "name", "avatar_url"} | null,
  "dept_id": int | null,
  "created_at": iso, "due_at": iso | null,
  "urgency": "high" | "medium" | "low",   // high: SLA breached / due ≤ 24 h / waiting > 3 days
  "actions": [ {"id": "approve", "style": "primary"}, {"id": "reject", "style": "danger", "reason": "optional"} ],
  "version": int | null,            // work items: optimistic concurrency, echo it back
  "link": {"section": "people", "sub": "join_requests", "dept_id": null, "kind": "org_work", "id": 55}
}
```
One-tap actions exist for org_join, unit_join, program_choice, form_response, work_item (approve / reject);
the other kinds carry `actions: []` and open their `link`.

`POST /orgs/{id}/tasks/{task_id}/{action}` body `{ "reason": str?, "version": int? }` → `{ "ok": true, "task_id",
"status" }`. Dispatches to the existing service (never a second implementation), re-checks the caller's right for
that item (403 `org_forbidden`), 409 `already_decided` when someone else decided first, 404 `task_not_found`.
Every decision writes an `OrgAuditLog` row with `meta.via = "quick_actions"` (program choices were not audited at
all — fixed for both paths). Emits the same live events as the existing route (so `/me/attention` badges refresh).

### 4. Insights
`GET /orgs/{id}/insights?term_id=&date_from=&date_to=` (default: the current term, else the last 30 days) — only
when `can_insights` (org admin, or `students.view` / `academic.view` / `courses.view` org-wide or in a
department; department-scoped viewers get their departments only). Aggregates only — never a student's name or
row (student privacy).

```
{ "period": {"term_id", "label_ar", "label_en", "from", "to"},
  "terms": [{"id", "label_ar", "label_en", "status"}],
  "metrics": [ { "key": "attendance" | "enrollment" | "completion" | "grades" | "pending",
                 "available": bool, "value": number|null, "unit": "percent" | "count" | "score",
                 "previous": number|null, "series": [{"date", "value"}] } ],
  "suggestions": [ { "key": "attendance_drop" | "unplaced_sessions" | "pending_backlog" | "low_completion"
                     | "grades_missing" | …, "severity": "risk" | "watch", "metric": "attendance", "value": number,
                     "link": {"section", "sub", "dept_id", "kind", "id"} } ] }
```
The app writes the plain-language summary line and the suggestion text from these numbers (pure, translated in the
app). A metric without a data source returns `available: false` (drawn as nothing, not as zero).

### 5. Search (command palette)
`GET /orgs/{id}/search?q=&limit=20` (q ≥ 2 chars) → `{ "departments": [{id, unit_type, name_ar, name_en}],
"people": [{user_id, name, avatar_url, member_role, dept_id}] }`. Departments: those the caller can open. People:
students only with `students.view` (org-wide, or enrolled in a department where the caller has it), teachers with
`teachers.view`, staff with `staff.view`; a member without rights gets no people. Students get 403
`student_forbidden`. The app adds its own tabs / pages to the results.

### 6. Access changes while the page is open
Assigning / revoking a role or grant, adding / removing a team member and changing a membership role emit the live
event `org_access_changed` `{org_id}` to the affected user (SSE + silent push, `live_update_service.py`). The app
reloads `/mine?members=1` + the dashboard on it, and on any 403 `org_forbidden` / `student_forbidden` from an org
call.

### 7. Kill switches (feature_catalog.py)
`org.insights` (the Insights section + `/insights`), `org.search` (the command palette). Existing keys untouched.

## App (front)

- Tokens: `lib/design/app_tokens.dart` (AppSpace · AppRadius · AppMotion · AppTouch · AppShadow · AppType).
- Shell (`org_dashboard_screen.dart`): every page has the same header — title · Refresh with "Updated 2 min ago" ·
  calendar · notifications with the unread badge · the context switcher (all orgs + Personal, the shared
  `context_switcher.dart` sheet; switching org stays in place via `OrgSession.select`, Personal → `leaveToPersonal`;
  the last choice is remembered by `AppModeController`). Phones get the same header (no shell bar there).
- Routing: every non-student org user lands on `/org_dashboard` (the "manages nothing" → `/org_member` hop goes);
  `/org_member` stays the student's org page. Choosing an org where I am not a student in the switcher from the
  personal home opens `/org_dashboard` on it. A student who reaches `/org_dashboard` sees a calm "This dashboard is
  for staff" page with "Back to my home".
- Departments: cards → the department page with ONLY the server's `tabs` (levels hide Add / Edit buttons). Any
  department tab is two taps from Home.
- Command palette: Ctrl+K / ⌘K and a search button in the header; departments, tabs, pages, people.

## Tests
back: `tests/org_v2/e2e_org_dashboard_v3.py` (members list, student block, tabs/levels, tasks + audit + 409,
insights privacy, search privacy, access-changed event). front: `test/org/org_dashboard_v3_test.dart` (pure
parsers, summaries, suggestion texts, task sorting / optimistic state), `test/ui/org_dashboard_v3_layout_test.dart`
(layout harness), perf budget in `home_requests_org_*`.

## Stages (one commit each, both repos)

| # | Stage | Status |
|---|---|---|
| 0 | Tokens | done |
| 1 | Shell, header, switcher, routing, student block (server §1, §2 access/student, §6) | done (back a0b31ed, front 8e7b943) |
| 2 | Departments with tabs + levels (server §2 tabs) | done (same commits) |
| 3 | Needs your attention: tasks + one-tap + audit (server §3) | done (same commits) |
| 4 | Insights (server §4, kill switch) | done (back a0b31ed; app: lazy, fetched in parallel with the dashboard, org-admin open budget 5 → 6) |
| 5 | Command palette (server §5) + remaining screens on the shared page anatomy (`org_page_kit.dart`) | done |
| 6 | UX review + QA in the real web app | done: every role walked in a real web build (390 / 1440, ar / en, light / dark); the department page and pages pushed from More on the shared header (`OrgPushedPage`), switcher pill degrades, sidebar chip contrast, copy; QA of the 7 criteria on the live API, server hardening (int4-safe ids, `date_out_of_range`, audit `meta`, English registrar task titles) |

Still on the old app bar: about 60 detail / editor screens under `lib/features/org` (complaint detail, form editor, governance item and session screens, registrar member pages): move them to `OrgPushedPage` as they are touched.
