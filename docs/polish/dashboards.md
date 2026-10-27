# Track B analysis — current dashboards (2026-10-28, read-only)

## Super Admin — `admin/admin_dashboard_screen.dart`, `admin_overview_page.dart`, `admin_services_hub.dart`

- Structure: wide 9 tabs (Overview · Students · Courses · Teachers · People · Finance · Support · Config · My account); phone 5 (+ More = ~30 `SettingsTile`s). Overview = HomeHeader → HomeHeroCard "pulse" → "Needs you" HomeActionGrid → HomeShortcuts → hand-rolled gradient banner → `GridView.count` of 14 hand-rolled stat cards.
- Data: `GET /admin/overview` (skeleton + ErrorRetry) plus fire-and-forget `/payments/transfers/pending`, `/admin/withdrawals`, `/complaints/unread-count`, `/me/attention`. Backend `admin_panel.py:222` is ONE aggregate but runs `expire_due()` + ~75 queries per open and returns no org / health / alert / trend data.
- Weak: no organizations count / pending org approvals, no growth over time, no alerts, no charts (no chart package); same number drawn 3× (hero, action grid, stat grid); 5 hard-coded `Colors.white`; key actions (organizations, Data Lab, RAG console) 2–3 taps deep; phone More is the old widget set.
- Perf: attention listener `setState`s the whole shell; 3 separate badge providers; no cache between visits (epoch reload).

## Org Admin — `org/org_dashboard_screen.dart` (1371 lines) + `org_department_dashboard.dart`

- Structure: Home · People · Academics · Timetable · Services · Settings, each a `_SectionHub` with chip sub-tabs over an IndexedStack. Home = `_OrgHero` (4 stats, 6 glass buttons) → attention cards → `_KpiRow` → GovDashboardCard → units strip → recent activity.
- Data: sequential `GET /org/mine` → `GET /org/orgs/{id}/dashboard` (`dashboards.py:org_dashboard_summary`, 23 queries) + `/me/attention?org_id` + governance dashboard. No cache; org switch reloads all.
- Weak: no members KPI, no trends, 13 hard-coded colors (department: 11 more), sub-pages 2–3 taps behind chip rows, mixed kits (`org_ui` + `utils/widget` + `app_kit`).
- Perf: whole-shell `setState` every 60 s; unit strip refetches the whole dashboard after each department visit; IndexedStack keeps every visited sub-page alive.

## Org Member — `org/org_member_dashboard.dart` (also embedded in student / teacher home in Organization mode)

- Structure: OrgHero (+ picker) → status banner → 3–4 AppStatTile → OrgTodayAgenda → UnifiedInbox(5) → decisions → "What you manage" → 10–25 quick-action pills → news (3).
- Data: `GET /org/public/me/overview` then `/org/public/schedule/me`, `/me/inbox?org_id`, `/org/public/me/feed`, governance, `/me/attention` (4–5 calls, each its own skeleton); no error state for the overview.
- Weak: the pill wrap is the main navigation (> 20 pills for a teacher-admin, no grouping); inbox and decision list duplicate the tiles; no upcoming-week view; 4 app-bar icons in 190 px.

## Student — `student/dashboard/dashboard_screen.dart` + `home/home_screen.dart`

- Structure: Home · My courses · My schedule · Analysis · Profile. Home = HomeHeader → `_NextUpHero` → "Needs you" grid → HomeAgenda (today) → HomeShortcuts → inbox preview, courses strip, featured, ads, org mix, other courses, categories, best teachers.
- Data: `GET /teacher/student-dashboard` + `/student/schedules` + `/me/calendar` + `/notifications` + `/me/attention` + `/me/inbox` + `/ads/feed` + `/home/mix` + `/org/public/me/overview` ≈ 9 calls from separate widgets, uncoordinated, no cache (except `fetchOnce` on schedule).
- Weak: no aggregate; no upcoming beyond the next slot; notification count only in the header; shells (`WideShell` / `RailShell` / `MobileShell`, 25 hard-coded colors) + old widgets frame the new home; guest mode gates 4 of 5 tabs.
- Perf: 4 `context.watch` at the top of HomeScreen → whole home rebuilds on any change; shell `setState` on attention.

## Teacher — `teacher/dashboard/teacher_dashboard_screen.dart` + `home/home_screen.dart`

- Structure: same 5 tabs. Home = HomeHeader → `_TeachingDayHero` → "Needs you" (todo, attendance missing, grading, material missing, enrollment requests) → HomeAgenda → HomeShortcuts → live queue → course strip → inbox preview, ads, org mix.
- Data: `GET /teacher/dashboard` (real aggregate) + `Future.wait(/notifications, /devices/teacher/switch-requests, /complaints/unread-count)` + attention + inbox + ads + mix. Hero shimmer only; **no error state** (zeros + "free today" on failure, pull-to-refresh only).
- Weak: no earnings figure; Schedule tab refetches `/teacher/schedules`; two shimmer implementations; 3 hard-coded colors.

## Parent — `parent/parent_dashboard_screen.dart`

- Structure: Children · Reports · Alerts · Link · More. Children = inbox preview + one `_ChildCard` per child.
- Data: `/parent/link/config` → `/parent/link/requests` → `/parent/children` SEQUENTIALLY, then `/parent/children/{id}/profile` per child (N+1) + `/parent/alerts` + inbox + attention. **No skeleton** (an empty state titled "loading"); no aggregate endpoint.
- Weak: no overview (no "today for my children", no cross-child summary); local `PlEmpty` / `AnEmpty` / `PlError` widgets instead of app_kit; badge on the wrong tab.

## Backend feeds

`/admin/overview` · `/teacher/dashboard`, `/teacher/student-dashboard` · `/org/orgs/{id}/dashboard`, `/units/{t}/{id}/dashboard` (`services/organization/dashboards.py`) · `/org/public/me/overview` · `/me/attention` (`attention_service.build_attention`, `_org()` per membership) · `/me/inbox` · `/home/mix`. One aggregate exists for admin, teacher, org-admin, org-unit and org-member; the student one lacks schedule / notifications / attention; the parent has none; nothing returns time series.

## Shared problems (ranked)

1. Every shell `setState`s the whole tree on each attention tick instead of `AttentionBadge` / `ListenableBuilder` at the leaf.
2. Homes are 5–9 self-fetching widgets with no shared loader, cache or coordinated skeleton: sections pop in piecewise.
3. Shells live in the student file (`WideShell` / `RailShell` / `MobileShell`, 25 hard-coded colors); every role imports `DashboardItem` from the teacher file; old `lib/utils/widget` pieces frame all home_kit content.
4. Hard-coded `Colors.white/black` on every gradient hero and glass tag (org 13, dept 11, admin 5, teacher 3).
5. No charts or trends anywhere (no chart package).
6. Same count drawn 2–3 times per screen.
7. More / Settings pages are long flat lists (admin ≈ 30) with no grouping; key actions 2–3 taps deep.
8. Error handling uneven (teacher none, parent loader-as-empty, member no overview error).
9. Phone layouts fold sections so badges land on the wrong tab.
10. Three duplicate badge providers per shell beside the attention feed that already carries those keys.

## What a redesign builds on

- `home_kit`: HomeHeader, HomeEntrance, HomeHeroCard / Tag / Figure, HomeActionCard / Grid, HomeTodoCard, HomeAgenda, HomeShortcuts, HomeDayRibbon, HomeSectionTitle; rhythm 8·16·24·32; `context.colors` only.
- `app_kit`: AppHero / AppHeroStat, AppCard, AppStatTile + AppGrid, AppEmpty, AppListSkeleton / AppShimmer, AppBanner, AppPill, AttentionBadge, AppTime, showAppSheet / appConfirm, AppHScroll, showAppExportSheet.
- Server: one aggregate per role already exists (extend, do not add calls); the attention feed carries per-tab keys for every role.
- `OrgSession` / `AppModeController` / `AttentionService` give scoping, mode and refresh; `ContextSwitcher` / `ContextExitButton` the org ↔ personal switch.
- Presentational bodies (`StudentHomeBody`, `TeacherHomeBody`, `OrgMemberHome`) take plain values → testable with the layout harness.
- The shells are the one place to fix sidebar colors and badge wiring for all five roles at once.
