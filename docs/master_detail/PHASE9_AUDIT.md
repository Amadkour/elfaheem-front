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
| teacher | 2 | 4 | 3 | 7 | 16 |
| student | 3 | 1 | 2 | 3 | 9 |
| parent | 2 | 1 | 2 | 2 | 7 |
| org staff | 3 | 2 | 3 | 4 | 12 |
| admin | 4 | 0 | 3 | 1 | 8 |
| shared | 2 | 0 | 1 | 2 | 5 |
| **total** | **16** | **8** | **14** | **19** | **57** |

## Teacher

| screen | file | lists | status |
|---|---|---|---|
| My courses | `teacher/courses/courses_screen.dart` | course cards | on (P7: panel, Open course primary) |
| My students · Submissions · Reviews | `teacher/classroom/teacher_classroom.dart` | 3 paged lists | on (`EntityListPage`) |
| A course's enrolled students | `teacher/sessions/students/course_student_screen.dart` | student cards / grid | **P9**: `MasterDetailScaffold` over the existing sliver list; a card opens the student (selected card outlined, `siblings` for prev / next); panel actions = `entityViewerActions` (Message) + Certificates (opens the old dialog, which loses its now-redundant chip); the grid counts its columns on the list's own width (`SliverLayoutBuilder`) and its row height follows the text size |
| Certificate requests | `teacher/certificates/certificate_requests_screen.dart` | request cards | **P9**: `MasterDetailScaffold`; the student and the course are `EntityChip`s (avatar card keeps approve / reject) |
| Device switch requests | `teacher/profile/switch_device_requests/teacher_device_requests_screen.dart` | request cards | **P9**: `EntityGuardedChip` for the student and the course (`student_id` / `course_id` were already in the payload, now parsed, null-safe for an older server) |
| Grade review (paper marks) | `shared/exam_engine/marks/review/grade_review_rows.dart` | its own list + detail | **P9**: the matched student is an `EntityGuardedChip` in the row detail (the screen keeps its own review master-detail) |
| Attendance roll call | `teacher/analysis/attendance/teacher_attendance_screen.dart` | sessions, students | gap: the student rows are present / absent toggles; a chip beside the name would need a second tap target per row |
| Exam hub | `teacher/analysis/exam/teacher_exam_hub_screen.dart` | exams, submissions | gap: submission rows name students in plain text |
| Read flags | `teacher/analysis/flags/teacher_read_flags_screen.dart` | flagged items → students | gap (low): a student opens the analytics profile on purpose; a chip could sit beside it |
| Data Lab | `teacher/data_lab/*` | spreadsheet grid | out (an editor) |
| Analytics hub | `teacher/analysis/analytics_hub_screen.dart` | course tool cards | out (navigation hub) |
| Schedules, sessions section | `teacher/schedules/`, `teacher/sessions/components/` | sessions | out |
| Live chat / hands | `teacher/sessions/live/widgets/` | live room | out |
| Certificate designer / designs / manager | `teacher/certificates/designer/`, `courses/component/certificate_manager_sheet.dart` | designs | out |
| Course form, next / recommended course pickers | `teacher/courses/course_form_screen.dart`, `component/*_courses_field.dart` | pickers | out |
| Payouts | `teacher/profile/payout/teacher_payouts_screen.dart` | money rows | out |

## Student

| screen | file | lists | status |
|---|---|---|---|
| My courses (+ Left) | `student/courses/my_courses/my_courses_screen.dart` | course cards | on (P7) |
| Grades, Payments, Subscriptions | `student/record/student_record_pages.dart` | paged lists | on (`EntityListPage`) |
| My certificates | `student/certificates/my_certificates_screen.dart` | certificates | on (course chip, P7) |
| My exams | `student/analysis/exam/student_exam_list_screen.dart` | exam cards in 4 tabs | **P9**: `MasterDetailScaffold` around the tabs; the course of each exam is an `EntityChip` (opens the course panel: progress, what is due, Continue learning); the card still opens the exam |
| Dashboard exam tab | `student/dashboard/component/student_exam_tab.dart` | exam cards | gap: the same course mention as My exams |
| Analytics | `student/analysis/student_analytics_screen.dart` | course cards → analytics | gap (low): a course chip in the card header; the card keeps its analytics destination |
| Home teachers row | `student/home/component/instractor_roe.dart` | teacher avatars | out: opens the public teacher profile (`/@name`, D-074) on purpose |
| Home categories, Categories | `student/home/component/category_row.dart`, `shared/category/categories_screen.dart` | catalogue | out: catalogue browsing opens the course page |
| Rewards, flags, exam quiz / result | `student/reward/`, `analysis/flags/`, `analysis/exam/*_quiz/result*` | | out |

## Parent

| screen | file | lists | status |
|---|---|---|---|
| Children | `parent/parent_children_page.dart` | child cards | on (P7 panel) |
| Alerts | `parent/parent_alerts_page.dart` | alerts | on (child chip, P7) |
| Reports (tab + one child's report) | `parent/parent_reports_page.dart` | courses, exams, attendance log | **P9**: `MasterDetailScaffold` around the report; a course row is an `EntityLink` that opens the CHILD then pushes the course (`open(child)..push(course)`), so the server answers as the child (`?student_id=` through `contextStudentId`) and the breadcrumb leads back; outside a scaffold the full page gets `?from=student:<id>` |
| Report exams / attendance rows | same file | exam and session rows | gap: the course in the subtitle is plain text (the payload names it, `course_id` not checked there) |
| Organization view | `parent/parent_org_view.dart` | schedule, grades | gap: course names in plain text (no ids in the payload; needs `course_id` from the server) |
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
| Form responses, complaints | `org/org_services_pages.dart` | responses, threads | gap: the sender is plain text; the payload does not say whether the person is a student or a teacher (server needs a `kind`) |
| Received reports | `org/org_reports/report_page.dart` | reports | gap (low): reporter / subject names |
| Advising (students, alerts, appointments, …) | `org/advising/*` | advisee lists | gap: the advisee hub (D-289) is its own detail; a guarded student chip in its header would link the record |
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
| Teacher transfers | `admin/enrollment_request/teacher_transfers_screen.dart` | requests | gap: student / teacher / course in plain text |
| Parent link requests | `admin/admin_parent_requests_page.dart` | requests | gap: student name in plain text |
| Organizations | `admin/admin_organizations_page.dart` | organizations | gap (low): owner / teacher mentions |
| Admins, content, features, feature guide, datacenter, platform settings, send message, required documents, view-as, app releases, landing, money p8, filters, table export | `admin/*` | | out |

## Shared

| screen | file | lists | status |
|---|---|---|---|
| Notifications | `shared/notification/notifications_screen.dart` | notifications | on (entities with `can_open`, P7) |
| Schedule | `shared/calendar/schedule_page.dart` | events | on (`EntityNavigator`) |
| Certificate issue lists | `shared/certificates_issue/cert_issue_lists.dart` | students to issue to | gap: student names in plain text |
| Course profile, course list card / row / home list | `shared/course_profile/`, `shared/course/` | the course page itself, catalogue cards | out |
| Complaints, RAG console / chat, about, attendance offline tab, OMR audience picker, material grid, VOD parts | `shared/*` | | out |

## Remains (in order)

1. Teacher exam hub submissions and attendance roll call: a student chip beside the name.
2. Student dashboard exam tab: the course chip, as in My exams.
3. Admin teacher transfers and parent link requests: `adminEntityCell` for the student / teacher / course.
4. Shared certificate issue lists: student chips.
5. Parent report exam / attendance rows and the organization view: course chips (the org view needs `course_id`
   from the server).
6. Org form responses / complaints: the server should send the person's kind so the app can draw a guarded chip.
7. Advising hub header: a guarded student chip to the connected record.
8. The low items: read flags, analytics course cards, received reports, organizations.

## Tests

`test/ui/master_detail/phase9_lists_test.dart` (FakeApi, the role routes of `md_roles_support.dart`): a course's
enrolled student, a certificate request's student chip and an exam's course chip each open the panel and wait for the
server's summary (Message / Continue learning drawn). The parent report has no widget test yet: its payload has no
fixture (`parent_reports` is not in `test/fixtures/payloads/`).
