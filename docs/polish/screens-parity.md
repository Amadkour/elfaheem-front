# Track C analysis — screen inventory and platform parity matrix (2026-10-28, read-only)

## A. Routes (`lib/main.dart` `_router`, ≈ L600–690)

| route | screen | roles |
|---|---|---|
| /login, /register, /otp, /forgot-password | `features/auth/*` | pre-auth |
| /home | `student/home/home_screen.dart` | student + guest |
| /dashboard | `student/dashboard/dashboard_screen.dart`: home · my_courses · my_schedule · analysis · my_profile (`student_tab_<label>` kill-switch) | student + guest |
| /teacher_dashboard | `teacher/dashboard/teacher_dashboard_screen.dart`: home · my_courses · my_schedule · analysis · my_profile | teacher |
| /parent_dashboard | `parent/parent_dashboard_screen.dart`: children · reports · alerts · link · more | parent |
| /admin_dashboard | `admin/admin_dashboard_screen.dart`: phone overview · students · courses · teachers · More; wide adds hubs people / finance / support / config (`admin_services_hub.dart`, super-admin gates L183/198/220) | admin, super-admin, developer |
| /org_dashboard | `org/org_dashboard_screen.dart` (OrgsGate): home · people · academics · timetable · services · settings; phones fold services into More | org-admin, org-staff |
| /org_member | `org/org_member_dashboard.dart` + `org_member_space.dart`: News · Departments · Requests · Complaints · Regulations · My path · Join | members |
| /subscription, /profile, /change-password, /downloads (mobile), /course-detail, /course-profile, /notifications, /calendar, /live/<token>, /c/<id>?ref= | shared / student files | see matrix |

## B. Parity matrix (only rows that differ)

| feature | web | android | ios | by nature? | note |
|---|---|---|---|---|---|
| Pull-to-refresh | partial | partial | partial | no | admin tabs get a RefreshButton only in the phone shell (`admin_dashboard_screen.dart` L404–427); see C |
| Calendar entry | student: home top bar + dashboard app bar; teacher: only via meeting cards (`schedules_screen` L255); parent / admin: none; org admin: dashboard button; member: pill | same | same | no | **gap:** teacher, parent, admin have no "My calendar" entry on any platform |
| Offline downloads | hidden | yes | yes | yes | tile hidden for teachers too (`profile_screen.dart` L154) |
| Offline exam sittings | no (`offlineExamsSupported = !kIsWeb`) | yes | yes | by design | |
| Org join QR scan | no (`joinScannerAvailable = !kIsWeb`) | yes | yes | partly | mobile_scanner supports web; code entry remains |
| Attendance check-in | only when the teacher allows web; GPS only | full + nearby relay | full + BLE relay | yes | |
| Picture-in-Picture | no | yes | no | mostly | **iOS gap unexplained**; rotation lock hidden on web |
| Live client recording | MediaRecorder canvas | native service | RPScreenRecorder | yes | |
| Pre-join mic level meter | yes | no | no | no | **gap:** stub returns 0 (`prejoin_mic_meter_stub.dart`) |
| Exam integrity signals | tab / full-screen / copy-paste | app background | app background | yes | |
| Payments | hosted iframe | WebView + Google Pay | WebView + Apple Pay | yes | |
| Phone verification | QR to scan | opens app | opens app | yes | |
| Share / pickers / exports | copy link · file picker · browser download | share sheet · camera · saved file | same | yes | |
| Keyboard shortcuts | yes | no | no | yes | |
| Push notifications | FCM web token; foreground shown as in-app snackbar (browser Notification call commented out, `notification_service.dart` L314) | local notifications | local notifications | partly | soft gap |
| Crashlytics, Remote Config live, offline banner | no | yes | yes | yes | |
| Navigation shell | WideShell ≥ 900 (student/teacher) or ≥ 1000 (parent/admin/org); RailShell 600–999 web only | MobileShell below (tablets get phone shell) | same | no | **breakpoints inconsistent** (900 vs 1000; rail web-only) |

## C. Main list screens WITHOUT pull-to-refresh

`shared/notification/notifications_screen.dart` (no refresh at all) · `shared/calendar/calendar_screen.dart` · student / teacher / parent dashboard shells (inner tabs have it) · `org/org_courses_page.dart` · `org_people_page.dart` · `org_schedule_hub.dart` · `org_schedule_pages.dart` · `org_member_today.dart` · `org_member_changes.dart` · org section hubs · `engine_exams_section.dart` · `attendance_widgets.dart` · `subscription_screen.dart` (icon only) · `rag_chat.dart` · `rag_admin_console.dart` · `admin_services_hub.dart` · `admin_mfa_page.dart`.

Have it: unified inbox, student / teacher home, my_courses, teacher courses / sessions / schedules / analytics, student exams / analytics / certificates, downloads, admin PagedList + most admin pages, all gov_* lists, org home tab, member dashboard / space, departments, announcements, registrar, join / terms / sections, course profile, exam engine screens, parent pages.

## D. Dark mode and responsiveness

- Dark theme exists (`darkTheme = tc.materialTheme(dark: true)`, `themeMode` from `ProfileProvider.darkMode`, persisted; toggles in every role's profile / More). Server palette carries dark colors; `context.colors` switches on `isDark`.
- Boot splash follows the OS brightness (`boot_splash.dart` L391), not the user's toggle → brief mismatch at launch.
- THREE breakpoint systems coexist: responsive_framework (450 / 800 / 1920) in `main.dart`, `Breakpoints` in `app_responsive.dart` (700 / 900 / 1200), and the shells' 900 / 1000.
- No web-only or mobile-only admin pages; differences are shell layout, not availability.
