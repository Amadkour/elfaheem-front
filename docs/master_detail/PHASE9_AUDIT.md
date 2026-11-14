# Master-detail phase 9: the hardening audit (D-290)

Every list / table screen of every role in `lib/features`, found by `ListView.builder` / `.separated`, `SliverList`,
`GridView.builder`, `AppDataTable`, `PagedList` and card lists of courses / students / teachers, then read by hand.

Status:

- **on** — already on the shared pattern (`EntityListPage` / `EntityListConfig`, or a `MasterDetailScaffold` panel
  over the existing list; mentions are `EntityChip` / `EntityGuardedChip` / `adminEntityCell`).
- **P9** — converted in this phase (how: in the row).
- **gap** — should be on the pattern, not done yet (the "Remains" list at the end, in order).
- **out** — out of scope: not a list of students / courses / teachers / categories (settings, chat, editors, pickers,
  forms, catalogue browsing that already opens the course page, a dashboard of tiles).

## Counts

Rows of the tables below (an "out" row may group several small screens of one area).

| role | on | P9 | gap | out | rows |
|---|---|---|---|---|---|
| teacher | 2 | 5 | 0 | 9 | 16 |
| student | 3 | 2 | 0 | 4 | 9 |
| parent | 2 | 3 | 0 | 2 | 7 |
| org staff | 3 | 4 | 1 | 4 | 12 |
| admin | 4 | 2 | 1 | 1 | 8 |
| shared | 2 | 1 | 0 | 2 | 5 |
| **total** | **16** | **17** | **2** | **22** | **57** |

## Teacher

| screen | file | lists | status |
|---|---|---|---|
| My courses | `features/courses/teacher/courses_screen.dart` | course cards | on (P7: panel, Open course primary) |
| My students · Submissions · Reviews | `teacher/classroom/teacher_classroom.dart` | 3 paged lists | on (`EntityListPage`) |
| A course's enrolled students | `features/sessions/teacher/students/course_student_screen.dart` | student cards / grid | **P9**: `MasterDetailScaffold` over the existing sliver list; a card opens the student (selected card outlined, `siblings` for prev / next); panel actions = `entityViewerActions` (Message) + Certificates (opens the old dialog, which loses its now-redundant chip); the grid counts its columns on the list's own width (`SliverLayoutBuilder`) and its row height follows the text size |
| Certificate requests | `features/certificates/certificate_requests_screen.dart` | request cards | **P9**: `MasterDetailScaffold`; the student and the course are `EntityChip`s (avatar card keeps approve / reject) |
| Device switch requests | `teacher/profile/switch_device_requests/teacher_device_requests_screen.dart` | request cards | **P9**: `EntityGuardedChip` for the student and the course (`student_id` / `course_id` were already in the payload, now parsed, null-safe for an older server) |
| Grade review (paper marks) | `features/exams/marks/review/grade_review_rows.dart` | its own list + detail | **P9**: the matched student is an `EntityGuardedChip` in the row detail (the screen keeps its own review master-detail) |
| Attendance roll call | `features/attendance/analysis/teacher/teacher_attendance_screen.dart` | sessions, students | out (decided, gaps A): a row is already two targets, the name opens the course's analytics profile (on purpose, the one parents see) and the switch marks presence; the avatar as a record link would give one person two "open" destinations side by side |
| Exam hub | `features/exams/legacy/teacher/teacher_exam_hub_screen.dart` | exams, submissions | **P9** (gaps A): `MasterDetailScaffold` around the hub; a result's student name is an `EntityGuardedChip` (`md.exam_result.student.<id>`), the card still opens the answers |
| Read flags | `teacher/analysis/flags/teacher_read_flags_screen.dart` | flagged items → students | out (decided, gaps A): each student row is one link to the analytics profile; a chip inside it would be a link in a link (`EntityLink` rule: one row, one link) |
| Data Lab | `features/data_lab/*` | spreadsheet grid | out (an editor) |
| Analytics hub | `teacher/analysis/analytics_hub_screen.dart` | course tool cards | out (navigation hub) |
| Schedules, sessions section | `teacher/schedules/`, `features/sessions/teacher/components/` | sessions | out |
| Live chat / hands | `features/live/room/widgets/` | live room | out |
| Certificate designer / designs / manager | `features/certificates/designer/`, `courses/component/certificate_manager_sheet.dart` | designs | out |
| Course form, next / recommended course pickers | `features/courses/teacher/course_form_screen.dart`, `component/*_courses_field.dart` | pickers | out |
| Payouts | `teacher/profile/payout/teacher_payouts_screen.dart` | money rows | out |

## Student

| screen | file | lists | status |
|---|---|---|---|
| My courses (+ Left) | `features/courses/student/my_courses/my_courses_screen.dart` | course cards | on (P7) |
| Grades, Payments, Subscriptions | `student/record/student_record_pages.dart` | paged lists | on (`EntityListPage`) |
| My certificates | `features/certificates/student/my_certificates_screen.dart` | certificates | on (course chip, P7) |
| My exams | `features/exams/legacy/student/student_exam_list_screen.dart` | exam cards in 4 tabs | **P9**: `MasterDetailScaffold` around the tabs; the course of each exam is an `EntityChip` (opens the course panel: progress, what is due, Continue learning); the card still opens the exam |
| Dashboard exam tab | `student/dashboard/component/student_exam_tab.dart` | exam cards | **P9** (gaps A): the course is an `EntityChip` (`md.exam_tab.course.<id>`), as in My exams. The widget has no importer today (dead code, see `docs/polish/screen-audit-learning.md`); no scaffold of its own, so a chip opens the full page unless a host wraps it |
| Analytics | `student/analysis/student_analytics_screen.dart` | course cards → analytics | out (decided, gaps A): the whole card opens the course's analytics; a chip in its header would be a second link inside it, and My courses already opens the course panel |
| Home teachers row | `student/home/component/instractor_roe.dart` | teacher avatars | out: opens the public teacher profile (`/@name`, D-074) on purpose |
| Home categories, Categories | `student/home/component/category_row.dart`, `features/courses/category/categories_screen.dart` | catalogue | out: catalogue browsing opens the course page |
| Rewards, flags, exam quiz / result | `student/reward/`, `analysis/flags/`, `analysis/exam/*_quiz/result*` | | out |

## Parent

| screen | file | lists | status |
|---|---|---|---|
| Children | `parent/parent_children_page.dart` | child cards | on (P7 panel) |
| Alerts | `parent/parent_alerts_page.dart` | alerts | on (child chip, P7) |
| Reports (tab + one child's report) | `parent/parent_reports_page.dart` | courses, exams, attendance log | **P9**: `MasterDetailScaffold` around the report; a course row is an `EntityLink` that opens the CHILD then pushes the course (`open(child)..push(course)`), so the server answers as the child (`?student_id=` through `contextStudentId`) and the breadcrumb leads back; outside a scaffold the full page gets `?from=student:<id>` |
| Report exams / attendance rows | same file | exam and session rows | **P9**: the server now sends `course_id` on `exams[]` and `attendance_log[]` (additive); each row is the same child-then-course `EntityLink` as the course rows; an older server's row stays plain |
| Organization view | `parent/parent_org_view.dart` | schedule, grades | **P9** (gaps B): the server now sends `course_id` on each session and grade (additive); the course is an `EntityGuardedChip` (a session's chip sits in its tags and leaves the subtitle; a grade's replaces the name); an older server keeps the plain name |
| Overview | `parent/parent_overview_page.dart` | child tiles → report | out (dashboard) |
| Link screens | `parent/parent_link_screen.dart`, `student_link_code_screen.dart` | link requests | out |

## Org staff

| screen | file | lists | status |
|---|---|---|---|
| People (students, teachers) | `org/org_people_page.dart` | paged people | on (P7 panel) |
| Courses | `org/org_courses_page.dart` | course cards | on (P7 panel) |
| Governance item | `org/governance/gov_item_screen.dart` | request source | on (guarded chip, P7) |
| Academic paths: department students | `org/org_academic_pages.dart` | `PagedList` | **P9**: the student's name is an `EntityGuardedChip` (a link only where the server says this staff member may open the record) |
| Academic paths: archive requests | `org/org_academic_pages.dart` | `PagedList` | **P9**: student and course are `EntityGuardedChip`s |
| Form responses, complaints | `org/org_services_pages.dart` | responses, threads | **P9** (gaps B): the server adds `user.person_kind` (`student` / `teacher` / null; null for a hidden identity) to form responses and complaints; "From" in the response sheet and the complaint thread is `OrgPersonFrom`, an `EntityGuardedChip` when a kind is named. The list cards keep the name as text (one row, one link) |
| Received reports | `org/org_reports/report_page.dart` | reports | gap (low): reporter / subject names |
| Advising (students, alerts, appointments, …) | `org/advising/*` | advisee lists | **P9** (gaps B): the student 360's header (`AdvStudentHeader`) has an `EntityGuardedChip` to the student's platform record (`student.user_id`); the advisee lists keep opening the 360 |
| Joining requests | `org/org_access_joining_requests.dart` | applicants | out: not members yet (the server would 404 every one) |
| Access, activity | `org/org_access_page.dart` | roles, audit log | out |
| Announcements, billing, levels, schedule ladder, program form, join pages, page kit | `org/*` | | out |
| Governance lists / member pages / session | `org/governance/*` | items, councils | out (items, not entities; the item screen links its source) |

## Admin

| screen | file | lists | status |
|---|---|---|---|
| Students, Teachers | `admin/admin_users_page.dart` | `AppDataTable` | on (P3 / P6 / P8) |
| Courses | `admin/admin_courses_page.dart` | `AppDataTable` | on (P5) |
| Categories | `admin/admin_categories_page.dart` | table | on (P6) |
| Finance, Payouts, Subscriptions | `admin/admin_finance_page.dart`, `admin_payouts_page.dart`, `admin_subscriptions_page.dart` | tables | on (`adminEntityCell`) |
| Teacher transfers | `features/payments/enrollment_request/teacher_transfers_screen.dart` | requests | **P9** (gaps B): the student and the course are `EntityGuardedChip`s, not `adminEntityCell`: the same queue serves teachers (`GET /payments/transfers/pending` is teacher / admin), so the server answers per mention |
| Parent link requests | `admin/admin_parent_requests_page.dart` | requests | **P9** (gaps B): the table's Request cell is the parent's name → `adminEntityCell` (student, from `student_id`); the detail's student block names the student the same way (the row still opens the request) |
| Organizations | `admin/admin_organizations_page.dart` | organizations | gap (low): owner / teacher mentions |
| Admins, content, features, feature guide, datacenter, platform settings, send message, required documents, view-as, app releases, landing, money p8, filters, table export | `admin/*` | | out |

## Shared

| screen | file | lists | status |
|---|---|---|---|
| Notifications | `shared/notification/notifications_screen.dart` | notifications | on (entities with `can_open`, P7) |
| Schedule | `shared/calendar/schedule_page.dart` | events | on (`EntityNavigator`) |
| Certificate issue lists | `features/certificates/issue/cert_issue_lists.dart` | students to issue to | **P9** (gaps B): a person with a `student_id` (on the platform) is an `EntityGuardedChip` (teachers, admins and org staff issue); a newcomer stays plain text |
| Course profile, course list card / row / home list | `features/courses/course_profile/`, `features/courses/` | the course page itself, catalogue cards | out |
| Complaints, RAG console / chat, about, attendance offline tab, OMR audience picker, material grid, VOD parts | `shared/*` | | out |

## Remains (in order)

Closed in gaps A: the teacher exam hub results (guarded student chip), the student dashboard exam tab (course chip),
the parent report exam / attendance rows (`course_id` added). Left out on purpose: the attendance roll call (the name
already opens the course analytics profile, the switch marks presence), read flags and the analytics course cards
(the whole row / card is already a link: a chip inside would be a link in a link).

Closed in gaps B: admin teacher transfers, parent link requests, certificate issue lists, the parent organization
view (`course_id` added), org form responses / complaints (`person_kind` added), the advising 360 header.

Still open (low): received reports (their "from" is free text, no ids), admin organizations (the list names no
owner / teacher: nothing to link without a payload change).

## Tests

`test/ui/master_detail/md_gaps_b_test.dart` (gaps B, `EntityAccess.debugAsk`): the transfer queue asks once for the
student and the course, the certificate list chips only a person on the platform, the parent org view chips a grade
with `course_id` and keeps an older server's name, `OrgPersonFrom` chips a named kind and keeps a hidden identity as
text, and the advising 360 header links the record.

`test/ui/master_detail/phase9_lists_test.dart` (FakeApi, the role routes of `md_roles_support.dart`): a course's
enrolled student, a certificate request's student chip and an exam's course chip each open the panel and wait for the
server's summary (Message / Continue learning drawn). The parent report has no widget test yet: its payload has no
fixture (`parent_reports` is not in `test/fixtures/payloads/`).

`test/ui/master_detail/gaps_a_lists_test.dart` (gaps A): the exam hub result's student chip and the exam tab's course
chip each open the panel loaded.
