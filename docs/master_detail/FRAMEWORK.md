# Master-detail framework (D-290, phase 3)

ONE pattern for every list of every role: a row opens the connected detail of a student, course, teacher or
category; inside a detail every related entity is a link that swaps the panel (with a breadcrumb trail). The server
contract is `../back/docs/master_detail/CONTRACT.md` (`/api/v1/entities/...`); the server decides what a viewer may
see and lists the `sections` the app may open: the app never decides permissions, it only draws what it is given.

## Files

| file | what |
|---|---|
| `lib/core/entities/entity_ref.dart` | `EntityKind {student, course, teacher, category}`, `EntityRef(kind, id, {label, imageUrl})`, token `student:12` (`toToken` / `EntityRef.tryParse`) |
| `lib/core/entities/entities_api.dart` | `EntitiesApi.instance`: `summary(ref, {studentId})`, `page(ref, section, {query})`, `timeline(studentId, courseId, {page})`; an LRU cache of summaries (50, 2 min) so a re-open is instant; `prefetch(ref)` (hover); `invalidate(ref)` |
| `lib/core/entities/entity_models.dart` | `EntitySummary` (kind, id, header, stats, badges, sections, can), `EntityBadge`, `EntityCan`, `EntityPage` (items, total, page, size, pages), `EntityListQuery` (search, sort, filter, page, size); plain parsers over the contract's JSON, tolerant of missing keys (an older server) |
| `lib/design/master_detail/entity_panel_controller.dart` | `EntityPanelController` (ChangeNotifier): the open trail (`List<EntityRef>`), `current`, `open(ref)` (new trail), `push(ref)` (drill in: trail grows), `back()`, `forward()`, `jumpTo(index)` (breadcrumb), `close()`, `siblings` + `next()` / `previous()` (the list's rows), `selectedId` (row highlight), `focusCourseId` (a student opened from a course scrolls to that course) |
| `lib/design/master_detail/master_detail_scaffold.dart` | `MasterDetailScaffold(controller:, list:)`: the adaptive host (below) |
| `lib/design/master_detail/entity_panel.dart` | the panel chrome: breadcrumbs, back / forward, previous / next, quick actions, Open full page, close; body = `EntityDetailView` |
| `lib/design/master_detail/entity_detail_view.dart` | loads the summary (cache → skeleton → hydrate; error + Retry), draws header, badges, stats and the sections the server listed, through the per-kind spec |
| `lib/design/master_detail/entity_specs.dart` | per kind: header layout, stat tiles, how each section draws (a sub-list with search / filter / sort / paging, or a block), which badges read how |
| `lib/design/master_detail/entity_chip.dart` | `EntityChip(ref)` / `EntityLink(ref, child)`: THE way to mention a student / course / teacher / category anywhere; opens through `EntityNavigator.open(context, ref)` |
| `lib/design/master_detail/entity_timeline.dart` | `EntityTimelineList(studentId, courseId, pageSize)`: one student's history in one course, newest first, paged, under month labels; `groupTimeline` folds the lessons of one sitting into one line; `showEntityTimelineSheet` |
| `lib/design/master_detail/student_detail.dart` | the student's own parts: `StudentOverviewCard`, `StudentCourseRow` (unfolds the enrollment's facts and timeline in place), `StudentInCourseBlock` (a course opened from a student), `EntityFactGrid`, and `StudentManage`, the interface of the management part |
| `lib/design/master_detail/entity_navigator.dart` | `EntityNavigator.open(context, ref)`: the nearest `MasterDetailScaffold` swaps / opens its panel; with none (a notification, a mention on any page) the full page `/view/<kind>/<id>` is pushed |
| `lib/design/master_detail/entity_detail_page.dart` | the full page (route `entity.view`, `/view/:kind/:id`, refresh-safe, every role) |

## Adaptive behaviour

Measured on the scaffold's own width (a page inside the shell is narrower than the window):

| width | list | detail |
|---|---|---|
| ≥ 1000 | stays visible, scrollable, the open row highlighted | an inline panel at the END side (left in Arabic), resizable by a drag handle (360 – 60 % of the width, remembered per device), closable, "Open full page" |
| 700 – 999 | stays under a scrim | an end-side overlay panel over the list (same chrome) |
| < 700 | — | a draggable bottom sheet (half → full height) with the same chrome; "Open full page" pushes `/view/<kind>/<id>` |

- Navigation inside the panel swaps its content; the trail shows as breadcrumbs (`Students / Sara Ali / Python
  Basics`); back / forward walk the trail. A course opened from a student keeps that student as context: its students
  section starts at that student, and the student's timeline for that course is one tap away.
- Previous / next step through the list's rows (the page hands `siblings`) without closing the panel.
- Deep links: an open panel writes `?open=<kind>:<id>` on the list's URL (replace, not push: Back closes the panel
  first); a list page opened with `?open=` opens that panel. The full page has its own URL.
- Instant open: the cached summary (or the row's own label / image as a header) draws at once, a skeleton for the
  rest, then the server's summary; hovering a row on web prefetches it.
- Keyboard (web / desktop): ↑ / ↓ move between rows (the panel follows when open), Enter opens, Esc closes,
  Alt+← / Alt+→ walk the trail.
- Screen readers: opening / closing / swapping the panel is announced; the panel is a labelled region.
- Motion through `AppMotion` (zero under Reduce motion).

## Tables

`AppDataTable` gains (all optional, older pages unchanged):

- `tableId`: the key under which this device remembers column visibility / order and density.
- `columnMenu: true`: a "Columns" menu (show / hide, move up / down; a `primary` column cannot be hidden).
- `density`: comfortable / compact toggle in the toolbar (row height and paddings from `AppSpace`).
- `selectedRowId`: the row drawn as selected (the open detail).
- `onRowHover`: called once per row hover (prefetch).
- `AppPagination` page-size choices (20 / 50 / 100) when the page passes `onPageSize`.
- `columnResize`: drag a column's edge in the header (double tap: its default); remembered with the layout. A `primary`
  column takes the room left; widths shrink to fit when the table narrows.
- `hideBelow` (column): left out of the wide table under that table width, e.g. while a side panel is open.
- `maxInlineActions`: 0 = each row has one menu instead of inline buttons.
- `AppDataTable.compactOf(context)`: a cell's density, so a thumbnail or chip follows the toggle.
- With a `mobileCard`, a phone drops the Columns and density buttons (the card is not made of columns).

`AdminPagedProvider` gains numbered paging next to `loadMore`: `goToPage`, `setPageSize`, `reloadPage` (after an action
a numbered table stays where it was; a page a delete emptied falls back); `allLoaded` tells an export whether the rows
on screen are every row.

## Going back

`EntityPanelController.storage` is a `PageStorageBucket` for the trail (a new trail starts clean). The detail's scroll
offset and each `EntitySubList`'s query and rows live there, so Back draws the course as it was, without asking the
server again. `learn(ref)` gives a trail entry the name its summary brought (a deep link's ref has none).

## First users (phase 3)

The admin Students and Teachers lists (`admin_users_page.dart`): a row opens the panel; both are managed inside
the detail (phase 4 for students, phase 6 for teachers).

## The student detail (phase 4)

Header (status, organizations, contact, join date) · badges · `StudentOverviewCard` · Courses and history (the
`courses` section: `EntitySubList` with `rowBuilder`; the server's `timeline` section has no block of its own, each
course's history unfolds under its row, fetched on the first open) · payments · subscription history, then for
`can.manage` the management part.

- **Context.** The trail gives it: a student opened from a course opens that course's row and scrolls to it (`pinned`
  draws it first when it is not on the first page, through `?course_id=`); a course opened from a student shows
  `StudentInCourseBlock`. The context survives the other two hosts: the full page is `/view/student/12?from=course:5`
  (`EntityPanelController.contextRef`) and a list's URL `?open=course:5,student:12`.
- **Management.** `features/admin/admin_student_manage.dart` implements `StudentManage` and loads as its own deferred
  part, only for `can.manage`, so the detail is managed in every host and a learner never downloads it. It adds the
  header's actions (`EntityDetailView`, before the host's own), Enrol, each course's Remove / Allow resubscribe, and
  the Subscription, Account, Devices and Controls cards. A change calls `EntityPanelController.entityChanged()`: the
  detail and its sub-lists reload in place (`EntitySubList.revision`) and the list hears of it (`onEntityChanged`).
  Remove asks for the withdrawal reason and sends it (`reason_code`, `reason`).
- A deep link names only kinds and ids: `EntityDetailView` tells the controller the names it learns (`learn`), and fetches the summary of any unnamed trail entry, so breadcrumbs and the student context draw names.
- A hit on a student in the admin's global search opens the full page; `showAdminUserDetail` with role `student` too.

## Admin courses (phase 5)

`admin_courses_page.dart`: the table of section 4 (numbered server pages, both directions of every sortable column,
`?open=course:<id>`), one card per course on a phone. The panel's quick actions and the row's menu act directly (Edit,
Publish, Mark completed, Move to trash); Manage is the sheet for what needs a form (payment provider, methods, fee,
private access code, resubscribe, plans and income in full, recent payments, exams). A course opened from a student
starts with that student's history, folded with one tap.

## Management inside the detail (phase 6)

What an admin does on a teacher or a category lives in the detail itself, so every host has it (any list's panel, a
drilled trail, the full page): `EntityDetailView` asks for `deferredAdminEntityManage(summary, onChanged:, onRemoved:)`
when `can.manage` is true, a deferred library (`lib/features/admin/admin_entity_manage.dart`) that only such viewers
download, and draws it under the header's quick actions. A teacher's block is Message · View as · Manage, which unfolds
the old management sheet embedded (`_UserDetailSheet(embedded: true)`); a category's is Edit · Delete. A save calls
`onChanged` (the detail reloads through `EntityPanelController.reload`); the list behind reads the controller's
`revision` in its listener and reloads its rows. A delete calls `onRemoved`: the panel steps back or closes, a full page
goes back.

A category's connected lists are tabs with their counts (`EntityConnectedTabs`): a tab loads on its first visit and
keeps its search, filter and rows; the open tab is remembered in the route's `PageStorage`, so coming back from a
student shows the same tab.

`adminEntityCell(context, kind, json)` (`admin_common.dart`) is the link to a student / teacher / course in an admin
row: it needs the row's `id`, and shows a dash without one.

## Every role (phase 7)

A role never writes a list. `lib/design/master_detail/entity_list_page.dart` is ONE paged list: an `EntityListConfig`
says what to load, the columns, the phone card, the sorts and the filter, and `EntityListPage` gives the same table,
cards, panel, states and keyboard everywhere (the server pages, searches, filters and sorts).

| role | configurations | where |
|---|---|---|
| teacher | `teacherStudentsList`, `teacherSubmissionsList`, `teacherReviewsList` (`features/home/teacher/classroom/`) | the strip on My courses: Courses · My students · Submissions · Reviews (`?view=`) |
| student | `studentGradesList`, `studentPaymentsList`, `studentSubscriptionsList`, `studentLeftCoursesList` (`features/home/student/record/`) | Profile: Grades and certificates, Payments and subscriptions; My courses: Left |
| parent | the panel over the children cards (the child's own record); the alerts' child chip | Children, Alerts |
| org staff | the panel over People (students, teachers) and Courses; a guarded chip on a request's source | `org_people_page`, `org_courses_page`, `gov_item_screen` |

- A course card (teacher, student, org) opens the panel; the page is its primary action (`EntityPanelAction.primary`):
  Continue learning, Open course. `entityViewerActions` is the default of a panel without actions of its own, and adds
  Message where `can.message`.
- `EntityLearnerCard` tops a learner's course (ring + one sentence, the dates, the withdrawal date and reason);
  `deadlines`, `lessons`, `grades`, `timeline` are ordinary sections.
- `EntityChip(ref, enabled: false)` is the same name without a link. `EntityGuardedChip(ref)` is for a mention that is
  not the viewer's by construction: `EntityAccess` asks `POST /entities/access` once per frame for a whole list.
  Notifications carry their answer in `entities[].can_open`.
- Logout clears the summary cache and the access answers.

## Search, saved views, bulk, exports (phase 8)

| file | what |
|---|---|
| `lib/core/entities/entity_search.dart` | `EntitySearchResult` (GET `/entities/search`), `EntitySavedView`, the list's query on its URL: `entityListToken` / `entityListParams` / `entityQueryFromParams` (`?list=q%3D…%26f.attention%3Dtrue`; unknown sorts / filters ignored) |
| `lib/design/master_detail/entity_search_palette.dart` | `EntitySearchScope` around the teacher, student and parent shells: Ctrl+K / ⌘+K opens `showEntitySearch` (dialog ≥ 720, else a sheet); 2 letters, 300 ms, stale answers dropped, ↑ / ↓ + Enter; a pick opens the full page. Admin and org keep their own palettes |
| `lib/design/master_detail/entity_list_tools.dart` | `EntityListExport` (Export Studio, or a CSV with a BOM and formula-looking text neutralised), `EntityBulkAction`, `entityMessageBulk`, `showEntityViewsSheet` (saved views: apply, save, delete; "Copy link" on the web) |
| `lib/design/master_detail/entity_exports.dart` | one export per row kind: `entityPersonExport`, `entityGradeExport` (a held result stays held), `entityReviewExport`, `entityPaymentExport` |
| `lib/features/admin/admin_bulk.dart` | `runAdminBulk`: the row's own call for every selected id, 4 at a time, then ONE refresh and ONE notice |

- `EntityListConfig` gains `export:`, `bulk:` and `savedViews` (default on). With an export or a bulk action the
  table shows its checkboxes and bulk bar; "Export selected" is always in the bar. The export menu offers every row
  (fetched in pages of 100, up to `maxRows`) or, in the studio, the selected ones.
- Where: teacher My students (export, Message), Submissions (export, Message), Reviews (export); student Grades and
  Payments (export); admin Students (Message, Activate, Deactivate, Export selected), Teachers (Activate, Deactivate,
  Export selected), Courses (Publish, Unpublish, Export selected).
- Saved views are per person and per list id on the server (`saved_views`, migration 0058, 20 per list); a shared
  link is only the URL, so whoever opens it still sees only what the server lets them see.
- The table's row checkboxes are labelled for screen readers (`ds_select_row`).

## Quality pass (phase 9)

- Fonts: an Arabic name in the English UI (and the reverse) draws through the theme's `fontFamilyFallback`, which
  `AppDisplayScope` sets in the app. A test host without it draws such names blank (no system fonts in tests): the
  visual hosts (`test/visual/master_detail*_visual_test.dart`, `student_detail_visual_test.dart`) wrap the app in
  `AppDisplayApply(prefs: const DisplayPrefs())`; `md_arabic_in_en` is the check render.
- Accessibility: `master_detail_a11y_test.dart` also covers the saved views sheet, the search palette with hits and a
  table with rows ticked (bulk bar); `expectA11y(…, act:)` runs a step before the guidelines are checked.
  `AppButton.tonal` keeps its ink readable on its own tint (and on a tinted bar); the bulk bar's "Select all" is
  `textDark`.
- Rebuilds: `EntityListBody` redraws its table only when the highlighted row changes (not on every panel move) and
  hands `siblings` when its rows change, not on every build. `EntitiesApi.invalidate` also drops the requests already
  running for that entity (a forced reload never receives, or caches, an answer that predates the change);
  `EntityAccess` keeps at most 1000 answers.
Phase 9 (the hardening audit, every role's lists classified, what was converted and what remains): `PHASE9_AUDIT.md`.
