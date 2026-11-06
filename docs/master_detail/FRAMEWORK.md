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

The admin Students and Teachers lists (`admin_users_page.dart`): a row opens the panel. A teacher's control sheet stays
reachable as the panel's "Manage" quick action until the teacher detail folds it in.

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
