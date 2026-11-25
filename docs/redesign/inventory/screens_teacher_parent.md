# Teacher and parent screens: design -> Flutter inventory

Paths are under `lib/features/` unless stated. URLs are `docs/redesign/design/<file>?<query>`. Row `#` = the number in SCREENS.md. The Flutter side was mapped from file names, classes and routes (not every file was opened); "verify" in Notes means a look is needed before building.

Entry points today: teacher = `/teacher_dashboard` (`home/teacher/dashboard/teacher_dashboard_screen.dart`, tabs: home, my_courses, my_schedule, analysis, my_profile); parent = `/parent_dashboard` (`parent/parent_dashboard_screen.dart`, tabs: today, children, reports, alerts, link, more). Both are routed in `lib/main.dart` `_router` (deferred in `core/routing/deferred_screens.dart`). Pushed pages have no named route (`Navigator.push`).

## Teacher (105 screens)

| # | Design screen | URL | Flutter file(s) today | Route / entry | Status | Notes |
|---|---|---|---|---|---|---|
| 1,3,4 | Home: live now / calm / first time (no courses) | `Tea1Home?screen=home\|calm\|first` | `home/teacher/home_screen.dart`, `teacher_home_provider.dart`, `queue_work_items.dart` (LiveNowCard), `teacher_home_extra.dart` | tab `home` | exists | restyle; home request budget test applies |
| 2 | Start a live | `Tea1Home?screen=golive` | `home/teacher/go_live.dart`, `go_live_sheet.dart` | Go-live button | exists | |
| 5, 10 | To-dos; snooze/ignore menu | `Tea1Home?screen=todo[&menu=1]` | `home/teacher/todo/teacher_todo_page.dart`, `teacher_todo_actions.dart` | home to-dos section | exists | verify snooze + ignore both exist |
| 6 | Inbox | `Tea1Home?screen=inbox` | `messaging/inbox/inbox_page.dart`, `unified_inbox.dart` | More / inbox | exists | |
| 7, 8 | Transfer payment requests; reject one | `Tea1Home?screen=transfers\|reject` | `payments/enrollment_request/teacher_transfers_screen.dart`, `teacher_transfers_provider.dart` | home / profile | exists | verify reject-reason dialog |
| 9 | Meeting links | `Tea1Home?screen=meetings` | `live/meeting_links_page.dart`, `meeting_links_parts.dart` | home / profile | exists | |
| 11, 17 | My courses; course options menu | `Tea1Courses?screen=list[&menu=1]` | `courses/teacher/courses_screen.dart`, `courses/course_list_card.dart` | tab `my_courses` | exists | |
| 12 | Quick course panel | `Tea1Courses?screen=panel` | `courses/teacher/courses_screen.dart` (`_TeacherCourseCard`), `courses/course_space/course_overview.dart` | card tap | partial | no quick-panel sheet; a tap opens the full course page |
| 13 | Delete course | `Tea1Courses?screen=del` | `courses/teacher/courses_screen.dart`, trash flow (D-260 soft delete) | card menu | exists | confirm dialog restyle |
| 14 | My students (all courses) | `Tea1Courses?screen=students` | `sessions/teacher/students/course_student_screen.dart` (one course only) | course page | partial | needs a cross-course list (translation key `md_p7_my_students` exists); verify backend list |
| 15 | Submissions | `Tea1Courses?screen=submissions` | `courses/course_profile/course_page_models.dart`, `course_space/course_overview.dart` mention submissions; `exams/` grading | per course | partial | no teacher-wide submissions inbox found |
| 16 | Reviews | `Tea1Courses?screen=reviews` | `teachers/teachers_parts.dart` (reviews on a teacher card), `teachers/teacher_review_admin.dart` (admin) | public profile | partial | no teacher-side reviews list/reply screen |
| 18-22, 24, 25 | New course wizard 1-5, 6, 7 (basics, pricing, audience, privacy, weekly schedule, video/cert/extras, review+publish) | `Tea1Wizard?screen=basics\|pricing\|audience\|privacy\|schedule\|extras\|review` | `courses/teacher/course_form_screen.dart` (one ~2000-line form), `course_form_provider.dart`, `course_privacy_card.dart`, `course_reel_field.dart`, `component/*`, `courses/course_setup.dart` | "+ new course" on courses tab | replace | design is a 7-step wizard, today one long form. Reuse providers and fields, rebuild the shell as steps |
| 23 | Add weekly slot (edit course) | `Tea1Wizard?screen=schedadd` | `calendar/recurrence/`, `sessions/teacher/components/session_form_sheet.dart` | course page | partial | weekly-slot sheet in edit mode; recurrence code exists |
| 26 | Course page: overview | `Tea1Course?screen=overview` | `courses/course_space/course_space.dart`, `course_overview.dart`, `courses/course_profile/course_profile_screen.dart` | `/course-profile` (id) | exists | one course page for all roles |
| 27 | Course page: draft | `Tea1Course?screen=draft` | `courses/course_setup.dart`, `course_setup_views.dart` | course page when draft | exists | setup checklist |
| 28, 34 | Sessions and materials; session menu | `Tea1Course?screen=sessions[&menu=1]` | `sessions/teacher/sessions_screen.dart`, `components/sessions_section.dart`, `courses/course_space/course_sessions.dart` | course page | exists | |
| 29 | New session | `Tea1Course?screen=sform` | `sessions/teacher/components/session_form_sheet.dart` | sessions | exists | |
| 30 | Add attachment | `Tea1Course?screen=material` | `sessions/material/session_material_widget.dart`, `components/` | session | exists | |
| 31 | Captions + video sharing | `Tea1Course?screen=captions` | none on the teacher side (only admin pages mention captions) | - | missing | transcript/captions and share-video link: new, backend to check |
| 32 | Guest link for live | `Tea1Course?screen=guest` | `sessions/teacher/components/guest_link_sheet.dart`, `sessions/material/material_guest_links_sheet.dart` | session menu | exists | |
| 33 | Background upload bar | `Tea1Course?screen=uploads` | `upload/upload_progress_footer.dart`, `upload_queue_manager.dart` | `BasePage` footer | exists | |
| 35-38 | Attendance: pick lecture+method; projector code; open QR; manual | `Tea1Class?screen=attendance\|attcode\|attqr\|attmanual` | `attendance/teacher_attendance_launcher.dart`, `attendance_live_screen.dart`, `teacher_attendance_controller.dart`, `attendance_ui.dart`, `attendance_widgets.dart` | session row "attendance" | exists | verify projector big-code and manual modes are separate views |
| 39 | Course: announcements | `Tea1Class?screen=announce` | `courses/course_profile/course_profile_announcements.dart` | course page | exists | design is a one-way thread (BACKEND.md section 3) |
| 40 | Course: rules and sections | `Tea1Class?screen=rules` | `courses/course_profile/course_page_sheets.dart` (`_RulesSheet`, `_SectionsSheet`), `course_page_models.dart` | course page | exists | |
| 41 | Course: team and permissions | `Tea1Class?screen=team` | `course_profile_parts.dart` (`CpTeamTab`), `course_profile_hub.dart` (`CourseTeamBlock`) | course page | exists | |
| 42 | Course: archive | `Tea1Class?screen=archive` | `course_profile_parts.dart` (`CpArchiveTab`), `course_profile_hub.dart` (`CourseArchiveSpot`) | course page | exists | |
| 43 | Course: learning path | `Tea1Class?screen=path` | `courses/roadmap/roadmap_editor.dart`, `roadmap_tab.dart` | course page "Path" | exists | personal courses only (D-120) |
| 44, 45 | Course: students and reminder; reminder message | `Tea1Class?screen=students\|nudge` | `sessions/teacher/students/course_student_screen.dart`, `course_students_nudge.dart`, `course_student_card.dart` | course page | exists | |
| 46 | Live: prejoin | `Tea1Live?screen=prejoin` | `live/room/prejoin.dart`, `prejoin_layout.dart` | `PreJoinPage` | exists | |
| 47 | Live: teacher room and host tools | `Tea1Live?screen=room` | `live/live_room.dart`, `live/room/room.dart`, `room/widgets/*`, `live_host_handover.dart`, `live_participant_controls.dart` | `LiveRoomHost.open` -> `LiveRoomLayer` | exists | hidden-students rule touches tokens (BACKEND.md section 3) |
| 48 | Live: waiting room | `Tea1Live?screen=lobby` | `live/live_lobby_sheets.dart` | in room | exists | |
| 49 | Live: ended | `Tea1Live?screen=ended` | `live/room/widgets/live_room_ended.dart`, `live_end_signal.dart` | room | exists | |
| 50, 51, 52 | Schedule: week, month, scheduled meetings | `Tea2Schedule?screen=cal\|month\|list` | `calendar/schedule_page.dart`, `schedule_parts.dart`, `calendar_views.dart`, `schedule_store.dart` | tab `my_schedule`, `/calendar` | exists | |
| 53 | New meeting with conflict check | `Tea2Schedule?screen=new` | `calendar/calendar_meeting.dart`, `calendar_api.dart` (409 `attendees_busy`) | schedule "+" | exists | |
| 54 | Meeting details | `Tea2Schedule?screen=meet` | `live/meeting_info_sheet.dart`, `calendar/calendar_meeting.dart` | meeting tap | exists | |
| 55 | Analytics hub | `Tea2Analysis?screen=hub` | `analytics/teacher/analytics_hub_screen.dart`, `teacher_stat_band.dart`, `attendance/analysis/teacher/teacher_attendance_screen.dart` | tab `analysis` | exists | |
| 56 | Hard-question bank | `Tea2Analysis?screen=flags` | `analytics/teacher/flags/teacher_read_flags_screen.dart` | analytics tool row | exists | |
| 57 | Data Lab | `Tea2Analysis?screen=lab` | `data_lab/data_lab_screen.dart`, `data_lab_widgets.dart`, `data_lab_provider.dart` | analytics "Data Lab" button | exists | |
| 58 | Data Lab: ask students | `Tea2Analysis?screen=ask` | `data_lab/data_lab_requests.dart` | Data Lab | partial | requests exist; verify they match "ask students a question" |
| 59 | Data Lab: formula column | `Tea2Analysis?screen=col` | `data_lab/data_lab_column_sheet.dart`, `data_lab_formula.dart`, `data_lab_columns_sheet.dart` | Data Lab | exists | |
| 60 | My account | `Tea2Account?screen=account` | `profile/profile_screen.dart`, `profile/profile_hero.dart` | tab `my_profile`, `/profile` | exists | |
| 61, 62 | Edit account: personal info; documents | `Tea2Account?screen=edit[&tab=docs]` | `profile/update_account_widget.dart`, `auth/teacher_document_provider.dart`, `auth/teacher_document_model.dart` | `/edit-account` | exists | verify documents tab placement |
| 63 | My public profile (owner view) | `Tea2Account?screen=public` | `profile/public_profile/public_profile_page.dart`, `public_profile_view.dart` | profile | exists | |
| 64-66 | Earnings and withdrawals; request withdrawal; add withdrawal account | `Tea2Money?screen=earn\|withdraw\|addacc` | `profile/teacher/payout/teacher_payouts_screen.dart`, `teacher_payout_provider.dart` | profile | exists | withdraw/add-account likely sheets in the same file; per-country payout methods are new (RULES.md section 3) |
| 67 | Device-change requests | `Tea2Account?screen=devices` | `profile/teacher/switch_device_requests/teacher_device_requests_screen.dart` | profile | exists | |
| 68 | Certificates: requests | `Tea2Certs?screen=requests` | `certificates/certificate_requests_screen.dart`, `certificate_requests_provider.dart` | profile / services | exists | |
| 69 | Certificates: designs | `Tea2Certs?screen=designs` | `certificates/designer/certificate_designs_screen.dart`, `studio/cert_template_gallery.dart` | profile / services | exists | |
| 70 | New certificate design | `Tea2Certs?screen=wizard` | `certificates/studio/cert_template_gallery.dart`, `cert_engine_presets.dart`, `cert_engine_studio.dart` | designs "+" | partial | gallery -> studio today; no wizard steps (verify) |
| 71 | Certificate studio | `Tea2Certs?screen=designer` | `certificates/studio/cert_engine_shell.dart`, `cert_engine_inspector.dart`, `cert_engine_panels.dart`, `designer/certificate_designer_screen.dart` | designs | exists | |
| 72-76 | Issue: method, recipients, photos, preview, issuing | `Tea2Certs?step=1..5&screen=issue` | `certificates/issue/cert_issue_flow.dart`, `cert_issue_lists.dart`, `cert_issue_photos.dart`, `cert_issue_parts.dart` | designs / data lab | exists | |
| 77 | Issue history | `Tea2Certs?screen=history` | `certificates/issue/cert_issue_history.dart` | issue flow | exists | |
| 78 | Exams hub | `Tea2Exams?screen=hub` | `exams/hub/exam_hub_screen.dart`, `hub_widgets.dart`, `hub_logic.dart`; older `exams/legacy/teacher/teacher_exam_hub_screen.dart` | profile / course | exists | |
| 79 | Paper grading | `Tea2Exams?screen=papers` | `exams/hub/grade/grade_papers_sheet.dart`, `exams/paper/scan/omr_scanner_screen.dart`, `omr_upload_screen.dart`, `exams/paper/bubble/*` | exam row | exists | |
| 80-82 | New exam: method, questions, settings | `Tea2Exams?step=how\|q\|settings&screen=wizard` | `exams/hub/create/exam_create_wizard.dart`, `exam_create_parts.dart`, `question_sources.dart`, `attributes_step.dart`, `exams/exam_generate_wizard.dart` | hub "+" | exists | |
| 83 | Paper exam: answer sheet | `Tea2Exams?step=sheet&screen=wizard` | `exams/hub/create/answer_sheet_plan.dart`, `answer_sheet_widgets.dart`, `paper_preview.dart`, `exams/paper/exam_setup_wizard.dart` | wizard | exists | |
| 84 | Prepare and deliver | `Tea2Exams?screen=deliver` | `exams/hub/deliver/exam_deliver_screen.dart`, `deliver_summary_card.dart` | exam row | exists | |
| 85 | Review grades | `Tea2Exams?screen=grade` | `exams/hub/correct/sheet_review_screen.dart`, `exams/hub/grade/essay_run_screen.dart`, `exams/exam_grading.dart`, `exam_review_screen.dart` | exam row | exists | |
| 86 | Results | `Tea2Exams?screen=results` | `exams/hub/result/exam_get_result_screen.dart`, `exam_results_screen.dart` | exam row | exists | |
| 87, 88 | My ads; new ad | `Tea2Money?screen=ads\|adnew` | `ads/ads_pages.dart` (`TeacherAdsPage`) | profile | exists | new-ad form is inside the page |
| 89 | My store items | `Tea2Money?screen=store` | `store/manage/store_manage_pages.dart`, `store_manage_views.dart` | profile | exists | |
| 90, 91 | Teaching profile and packages; rejected state | `Tea2Teach?screen=hub[&status=rejected]` | `teachers/teacher_onboarding.dart`, `teachers/teachers_parts.dart`, `auth/account_approval_page.dart`, `profile/profile_screen.dart` | profile | partial | onboarding and approval states exist; one hub of "profile + my packages" with the rejected state is new (verify) |
| 92-95 | Teacher profile wizard 1-4 (profile, subjects+qualifications, documents, review) | `Tea2Teach?step=1..4&screen=profwiz` | `teachers/teacher_onboarding.dart` (`TeacherOnboardingWizard`), `teachers_models.dart`, `auth/teacher_document_provider.dart` | teacher onboarding (`auth/teacher_onboarding_token.dart`) | exists | restyle; per-country qualifications are new (RULES.md section 3) |
| 96-98 | New package: basics, schedule, price+seats | `Tea2Teach?step=1..3&screen=package` | `teachers/package_wizard.dart` (`PackageWizardPage`) | hub | exists | group size 5-10 and gender rule: BACKEND.md section 4 |
| 99 | Quran teaching | `Tea2Teach?screen=quran` | `quran/quran_teacher_hub.dart`, `quran_teacher_page.dart` | teacher profile | exists | |
| 100 | Recitation log | `Tea2Teach?screen=record` | `quran/quran_record_sheet.dart`, `quran_progress.dart` | quran page | exists | |
| 101 | Complaints and support | `Tea2Account?screen=complaints` | `profile/compalints/complaints_hub_page.dart`, `complaints_screen.dart` | profile | exists | |
| 102 | New complaint | `Tea2Account?screen=newcomplaint` | `profile/compalints/new_complaint_screen.dart` | complaints | exists | |
| 103 | Messages | `Tea2Chat?screen=chat` | `messaging/chat/chat_page.dart`, `chat_store.dart` | `/chat` | exists | |
| 104 | Conversation | `Tea2Chat?screen=thread` | `messaging/chat/chat_page.dart`, `chat_bubble.dart` | `/chat` (conversation id) | exists | |
| 105 | New message | `Tea2Chat?screen=newmsg` | `messaging/chat/chat_new_message.dart` | `/chat` | exists | |

## Parent (39 screens)

| # | Design screen | URL | Flutter file(s) today | Route / entry | Status | Notes |
|---|---|---|---|---|---|---|
| 1, 2, 3 | Today: one child / all kids / no linked kids | `Pa2Today?screen=today\|all&kid=all\|empty` | `parent/parent_overview_page.dart`, `parent_overview.dart`, `parent_pulse.dart`, `parent_pulse_widgets.dart` | tab `today` | exists | home budget test applies |
| 4 | Message the teacher (pick teacher) | `Pa2Today?screen=msg` | `parent/parent_message_teacher.dart` | sheet | exists | |
| 5 | Kids list | `Pa2Kids?screen=list` | `parent/parent_children_page.dart` | tab `children` | exists | |
| 6 | Child details | `Pa2Kids?screen=detail` | `parent/parent_children_page.dart` (`_ChildCard`), `parent_child_marks.dart` | tab `children` | exists | |
| 7 | Child's course | `Pa2Kids?screen=course` | `parent/parent_child_marks.dart` (`_CourseMarks`), `parent_org_view.dart` | child details | partial | per-course marks exist, no per-course child page (verify) |
| 8 | Child's games | `Pa2Kids?screen=games` | `games/games_progress.dart` (`ParentChildGamesPage`) | child card | exists | |
| 9 | Quran memorization | `Pa2Kids?screen=quran` | `quran/quran_progress.dart` | child card | exists | |
| 10 | Nahw progress | `Pa2Kids?screen=nahw&kid=faisal` | `nahw/nahw_tab.dart` (`ParentChildNahwPage`) | child card | exists | |
| 11, 12, 13 | Awaiting consent; consent dialog; revoke | `Pa2Kids?screen=locked&kid=sara\|consent\|revoke` | `parent/parent_consent.dart` (`ConsentRequiredView`, `ParentConsentBody`, `ParentConsentRequired`) | child card / dialog | exists | |
| 14 | Reports: all kids | `Pa2Reports?screen=reports&kid=all` | `parent/parent_reports_page.dart`, `parent_report_widgets.dart` | tab `reports` | exists | |
| 15 | Full child report | `Pa2Reports?screen=child` | `parent/parent_reports_page.dart`, `parent_report_widgets.dart` | tab `reports` | exists | |
| 16 | How the rating is computed | `Pa2Reports?screen=how` | none dedicated | - | partial | explainer sheet is new copy; data exists |
| 17, 18 | Alerts; all clear | `Pa2Alerts?screen=alerts&kid=all\|empty&kid=sara` | `parent/parent_alerts_page.dart` | tab `alerts` | exists | |
| 19 | More | `Pa2More?screen=more` | `parent/parent_dashboard_screen.dart` (`_ParentMorePage`) | tab `more` | exists | |
| 20 | Link a child (easy) + my requests | `Pa2More?screen=link` | `parent/parent_link_screen.dart`, `parent_link_providers.dart` | tab `link` | exists | |
| 21 | Link a child (advanced) | `Pa2More?screen=linkadv` | `parent/parent_link_screen.dart`, `student_link_code_screen.dart` | tab `link` | exists | verify the advanced method is a separate mode |
| 22 | Book for your child: pick child + subject | `Pa2Pay?screen=book` | none (student booking in `courses/student/`; discovery `teachers/teacher_discovery.dart`) | - | missing | new parent booking entry, ties into BookFlow/SubjectProfile |
| 23 | Payments and invoices | `Pa2Pay?screen=payments&kid=all` | none for parent (`payments/subscription`, `payments/enrollment` are student side) | - | missing | needs a parent-scoped payments endpoint |
| 24 | Invoice | `Pa2Pay?screen=invoice&kid=all` | none | - | missing | invoice view / PDF |
| 25, 26 | Messages: chat with teacher; conversations list | `Pa2Shared?screen=chat\|chats&kid=all` | `messaging/chat/chat_page.dart` | `/chat` | exists | |
| 27 | Calendar | `Pa2Shared?screen=calendar&kid=all` | `calendar/schedule_page.dart`, `calendar_screen.dart` | `/calendar` (More tile) | exists | verify per-child filter |
| 28 | Inbox | `Pa2Shared?screen=inbox&kid=all` | `messaging/inbox/inbox_page.dart` | More | exists | |
| 29 | Notifications | `Pa2Shared?screen=notifs&kid=all` | `messaging/notification/notifications_screen.dart` | More / bell | exists | |
| 30 | Complaints and support | `Pa2Shared?screen=complaints` | `profile/compalints/complaints_hub_page.dart` | More | exists | |
| 31 | Create parent account | `Pa2Gate?screen=register` | `auth/register_screen.dart`, `onboarding/join/join_flow_screen.dart` | `/register`, join route | exists | |
| 32 | Sign-up 1: who are you | `Pa2Gate?screen=role` | `onboarding/join/join_steps.dart` | join flow | exists | |
| 33 | Sign-up 2: country and grade | `Pa2Gate?screen=grade` | `onboarding/join/join_steps.dart`, `auth/register_levels_step.dart` | join flow | exists | country list is new (RULES.md section 3) |
| 34 | Sign-up 3: study mode | `Pa2Gate?screen=mode` | `onboarding/join/join_steps.dart` | join flow | exists | |
| 35 | Sign-up 4: your data + child code | `Pa2Gate?screen=contact` | `onboarding/join/join_steps.dart`, `join_draft.dart` (`child_code`) | join flow | partial | links a child by code today; "create the child here" is new |
| 36 | Sign-up done | `Pa2Gate?screen=done` | `onboarding/join/join_flow_screen.dart`, `auth/verified_screen.dart` | join flow | exists | |
| 37 | Done: child's account ready (login code) | `Pa2Gate?screen=done&kid=new` | `parent/student_link_code_screen.dart` (code runs the other way: student shows the parent) | - | partial | parent-creates-child + 6-digit code + WhatsApp share: BACKEND.md section 1, needs a backend endpoint |
| 38 | Account activation fee | `Pa2Gate?screen=fee` | `auth/account_fee_page.dart` | after sign-up | exists | |
| 39 | Fee: receipt under review | `Pa2Gate?screen=feepending` | `auth/account_fee_page.dart`, `auth/account_approval_page.dart` | after sign-up | exists | |

## New features (no Flutter counterpart)

- Parent: book for a child (`Pa2Pay?screen=book`), payments list and invoice.
- Parent: parent creates the child's account and the one-time 6-digit login code with WhatsApp share (`Pa2Gate?screen=done&kid=new`, `Stu1Auth?screen=kidcode`); the existing code flow runs the other way.
- Parent: "how the rating is computed" explainer (`Pa2Reports?screen=how`); per-course child page (`Pa2Kids?screen=course`).
- Teacher: captions/transcript and video sharing (`Tea1Course?screen=captions`).
- Teacher: cross-course "my students", submissions inbox and reviews list; quick course panel.
- Teacher: the 7-step course wizard (replaces the single form) and the weekly-slot add sheet.
- Teacher: certificate design wizard (steps before the studio); teaching-profile hub with "my packages" and the rejected state.
- Teacher: country-aware qualifications and payout methods (RULES.md section 3).

## Per design file -> main Flutter files

- `Tea1Home.dc.html` -> `home/teacher/home_screen.dart`, `go_live_sheet.dart`, `todo/`, `payments/enrollment_request/`, `live/meeting_links_page.dart`, `messaging/inbox/`
- `Tea1Courses.dc.html` -> `courses/teacher/courses_screen.dart`, `sessions/teacher/students/`
- `Tea1Wizard.dc.html` -> `courses/teacher/course_form_screen.dart`, `course_form_provider.dart`, `calendar/recurrence/`
- `Tea1Course.dc.html` -> `courses/course_space/`, `courses/course_profile/`, `sessions/teacher/`, `sessions/material/`, `upload/`
- `Tea1Class.dc.html` -> `attendance/teacher_attendance_launcher.dart`, `courses/course_profile/` (announcements, rules, team, archive), `courses/roadmap/`, `sessions/teacher/students/`
- `Tea1Live.dc.html` -> `live/room/prejoin.dart`, `live/live_room.dart`, `live/live_lobby_sheets.dart`, `live/room/widgets/live_room_ended.dart`
- `Tea2Schedule.dc.html` -> `calendar/schedule_page.dart`, `calendar/calendar_meeting.dart`, `live/meeting_info_sheet.dart`
- `Tea2Analysis.dc.html` -> `analytics/teacher/`, `data_lab/`, `attendance/analysis/teacher/`
- `Tea2Account.dc.html` -> `profile/profile_screen.dart`, `profile/update_account_widget.dart`, `profile/public_profile/`, `profile/teacher/switch_device_requests/`, `profile/compalints/`
- `Tea2Money.dc.html` -> `profile/teacher/payout/`, `ads/ads_pages.dart`, `store/manage/`
- `Tea2Certs.dc.html` -> `certificates/` (`designer/`, `studio/`, `issue/`, `certificate_requests_screen.dart`)
- `Tea2Exams.dc.html` -> `exams/hub/`, `exams/paper/`
- `Tea2Teach.dc.html` -> `teachers/teacher_onboarding.dart`, `teachers/package_wizard.dart`, `quran/quran_teacher_*.dart`, `quran/quran_record_sheet.dart`
- `Tea2Chat.dc.html` -> `messaging/chat/`
- `Pa2Today.dc.html` -> `parent/parent_overview_page.dart`, `parent_pulse*.dart`, `parent_message_teacher.dart`
- `Pa2Kids.dc.html` -> `parent/parent_children_page.dart`, `parent_child_marks.dart`, `parent_consent.dart`, `games/games_progress.dart`, `quran/quran_progress.dart`, `nahw/nahw_tab.dart`
- `Pa2Reports.dc.html` -> `parent/parent_reports_page.dart`, `parent_report_widgets.dart`
- `Pa2Alerts.dc.html` -> `parent/parent_alerts_page.dart`
- `Pa2More.dc.html` -> `parent/parent_dashboard_screen.dart` (`_ParentMorePage`), `parent_link_screen.dart`, `student_link_code_screen.dart`
- `Pa2Pay.dc.html` -> none (new); related: `payments/`, `teachers/teacher_discovery.dart`
- `Pa2Shared.dc.html` -> `messaging/chat/`, `calendar/`, `messaging/inbox/`, `messaging/notification/`, `profile/compalints/`
- `Pa2Gate.dc.html` -> `onboarding/join/`, `auth/register_screen.dart`, `auth/account_fee_page.dart`, `auth/account_approval_page.dart`, `parent/student_link_code_screen.dart`

## Counts (by SCREENS.md row number)

- Teacher (105): exists 87, partial 9, replace 8, missing 1.
- Parent (39): exists 32, partial 4, missing 3.
