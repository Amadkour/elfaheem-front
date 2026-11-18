# Teacher organization workspace (D-1150 – D-1159)

Tracker for the multi-session job. Branch `feature/teacher-org-dashboard` in both repos (worktrees
`D:/platform/nextbrain/_wt/tod-front`, `_wt/tod-back`). On a resume: continue the first task not `done`.

## Decisions

- **D-1150 Who gets it.** Every non-student organization role WITHOUT organization-wide admin access
  (`!OrgSession.isOrgAdmin && access != 'admin'`) opens the teacher workspace instead of the D-103 admin shell.
  Org admins keep the D-103 shell. Kill switch `org.teacher_workspace` (off → the D-103 shell, as before).
  Nothing is deleted: the org-wide pages a teacher holds a right to (People / Academics / Timetable / Services
  sub-pages) stay one tap away from the Profile tab's "Organization pages" group, and every department keeps its
  full page (`openDepartmentDashboard`) behind "Open department page".
- **D-1151 Tabs.** Overview · Management · Membership · Pinned · Alerts · Profile. Management / Membership hide
  when empty, Pinned when nothing is pinned. ONE "Pinned" tab (never one nav entry per pin: a phone bar can't hold
  them); inside it a chip strip of the pins, horizontal scroll, and from 11 pins an "All pinned" grid sheet
  with reorder.
- **D-1152 Manager vs member.** The server decides (`GET …/my-workspace`): a unit is *managed* when I head it
  (`OrgDeptMember.is_head`) or hold `departments.update` / `team.update` in it; otherwise I am a member there.
  Manager: every person's data and history, bulk actions. Member: names / avatars / kind only (no contact),
  history = my own actions only, no bulk action but Export of what I can see. Enforced on the server.
- **D-1153 Items.** A department's items are its people (team + members) — paged, filtered, searchable. Details
  = the person's data + the history from `org_audit_log` (target = the person or actor = the person, in that
  department).
- **D-1154 Bulk.** Remove from department (confirm + Undo through `op: restore` with the removed snapshot),
  Export selected. The bar sits at the bottom (thumb reach, it doesn't move the list's header).
- **D-1155 Export.** Export Studio only (`showAppExportSheet` / `AppTableExport`), scopes all · filtered ·
  selected; all / filtered fetch every page through `fetchAllRows` with the Studio's progress, which keeps
  running while the person uses the app and ends with `showAppNotice` (no new export system).
- **D-1156 Alerts.** `GET …/my-alerts` normalises the org tasks + attention rows for me with a source (department
  / organization), a severity and the person it is about; read / snooze / archive per user are stored server-side
  in an `app_settings` row `org_alert_state:<uid>:<oid>` (the teacher to-do pattern, no migration).
- **D-1157 Preferences.** Display mode, main tab, focus mode, pins, saved filters and alert view are stored on the
  device per user + organization (`SharedPreferences`, like `OrgPersonaStore`); not synced through
  `/me/ui-prefs` (a 4 KB whole-dict store other features share).
- **D-1158 Switch account.** The personal Profile gets a "Switch account" row opening the existing
  `showContextSwitcherSheet` (personal + every organization account); choosing an organization opens its
  dashboard (`openOrgDashboard`).

## API contract (base `/api/v1/org/orgs/{org_id}`)

- `GET /my-workspace` → `{managed:[Unit], member_of:[Unit], stats:{people_managed, team_managed, members_total,
  alerts_active, alerts_high, requests_open, requests_overdue, votes_waiting, next_session}, weeks:{people:[n…8],
  requests:[n…8]}}`; `Unit = {id, unit_type, name_ar, name_en, icon, color, logo_url, people, team, waiting,
  role: 'head'|'manager'|'member'}`.
- `GET /my-workspace/units/{dept_id}/people?q&kind=head|team|member&joined_from&joined_to&sort=name|-joined|joined
  &page&size≤100` → `{total, page, size, pages, can:{manage, bulk}, items:[{user_id, name, avatar_url, username,
  kind, title, joined_at, email?}]}` (403 `not_in_unit` when I'm not in it).
- `GET /my-workspace/units/{dept_id}/people/{user_id}?cursor` → `{person:{…, email?, phone?, joined_via},
  history_scope:'all'|'mine', history:{items:[{id, action, summary, actor:{id,name,avatar_url}, created_at}],
  next_cursor}}`.
- `POST /my-workspace/units/{dept_id}/people/bulk` `{op:'remove', user_ids}` → `{done, failed:[{user_id, code}],
  removed:[snapshot]}`; `{op:'restore', items:[snapshot]}` → `{done, failed}`. Manager only (403
  `not_manager`); never removes a head or me (`failed` code `is_head` / `is_self`).
- `GET /my-alerts?view=active|snoozed|archived&severity&source` → `{items:[{key, kind, source:{type, id, name_ar,
  name_en}, severity, title_ar, title_en, subtitle_ar, subtitle_en, person, dept_id, created_at, link, read,
  snoozed_until}], counts:{active, unread, high}}`.
- `POST /my-alerts/state` `{keys, state:'read'|'unread'|'snooze'|'archive'|'restore', until?}` → `{ok, counts}`.

## Tasks

| # | Task | Status |
|---|------|--------|
| B1 | Backend: routes above + e2e `tests/org_v2/e2e_teacher_workspace.py`, FLUTTER_API_CHANGES, kill switch, features guide | done (back ccb1f27, 5e2d203; help 567ddf1 + migration 0098) |
| F1 | Shell switch + tabs + prefs store + API client + Switch account row | done |
| F2 | Overview | done |
| F3 | Management / Membership: boxes · tabs · main tab · focus; people list, filters, saved filters, search, bulk, export, details + history | done |
| F4 | Alerts + Pinned + Profile tab | done |
| F5 | Contract snapshots, help ids, layout harness, analyzer, docs (CLAUDE / guide / DECISIONS), review of Overview by eye | done |

## Still owed

- A run in the real web app on the local stack (only widget tests + renders so far).
- Live reload of Alerts on LiveEvents (the header Refresh reloads today).
- A push when a large export is ready (the Export Studio has none; D-1155).
- Preferences are per device (D-1157): sync through the server if the owner wants them on every device.
