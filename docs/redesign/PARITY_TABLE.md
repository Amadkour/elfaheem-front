# Parity table: lose nothing, add what is new

Phase 0.1, built as `PARITY.md` asks. One row per FEATURE (not per widget class). Sources merged:
- the 389 features of `../back/data/app_features_guide.json` (the row name carries the guide id);
- every route of `lib/main.dart` `_router` and the `AppRoutes` registry, every `AppNavigator` push module, every `DashboardItem`, every org sub-page and every `AdminService` (`inventory/front.md` sections 1, 3, 4, 4a, 4b), shown in the "Today" cell of the row that owns them;
- the 486 kill-switch keys of `../back/features/platform/feature_catalog.py` (the keys stay with their feature; the families no guide feature names are mapped at the end);
- the 570 design screens of `SCREENS.md` (one row per screen is in `SCREEN_MAP.md`; here the design cell names the file and the screen).

Decisions (`PARITY.md`): **restyle** = the design has it, rebuild the UI, keep behaviour, API and kill switch. **keep + restyle** = the design does not draw it: keep it, new tokens and components, placed in the role's More area. **new** = in the design, not in the app. **replace** = the design changes how it works (the capability stays for the roles that need it). **owner** = conflicts with RULES.md and cannot be kept: ask the owner, do not delete.

Rules that apply to every row and are not repeated: "دورة" never "كورس", "عن بعد" never "أونلاين", "فردي" never "لحالك", "دفتر" never "كشكول", حصة / درس and never "جلسة" in student UI, no "مجاني" as a selling point, no classes-per-week numbers (RULES 1); each kill switch keeps working; each new feature gets a kill switch and a features-guide entry.


## Account and sign-in

| Feature / screen | Roles | Today (file, route) | Design screen(s) | Decision | Notes |
|---|---|---|---|---|---|
| Sign in to the app (`sign_in`) | everyone | lib/features/auth/login_screen.dart. routes: `/login` | Stu1Auth?screen=login (state=error, bio) | restyle | One identifier field stays. M15 shake on error. |
| Create a new account (`register_account`) | student, teacher, parent | lib/features/auth/register_screen.dart, lib/features/onboarding/join/. routes: `/register[?role]` | Stu1Auth?screen=register, join (step=grade, contact); Pa2Gate?screen=register, role, grade, mode, contact, done; LandingW funnel | restyle | Add country of residence and any-country phone (RULES 3). Never ask nationality. |
| Study details: stage, grade and school (`study_profile`) | student | lib/features/profile/study_profile/, lib/features/auth/register_levels_step.dart | Stu1Auth?screen=study; Stu2Profile?screen=study | restyle | Grades and tracks per country from /edu/catalog. |
| Complete your teacher profile and upload the required documents (`teacher_onboarding`) | teacher | lib/features/teachers/teacher_onboarding.dart, lib/features/auth/additional_register_screen.dart | Tea2Teach?screen=profwiz (step 1-4) | restyle | Documents: passport, iqama or national ID (RULES 3). |
| Reset a forgotten password (`forgot_password`) | everyone | lib/features/auth/forget_screen.dart. routes: `/forgot-password` | Stu1Auth?screen=forgot (step=new) | restyle |  |
| Browse the app as a guest (`guest_browsing`) | student | lib/features/guest/, lib/features/home/student/dashboard/ | Stu1Public?screen=guesthome (sheet=signin), gate | restyle |  |
| Two-step verification (`two_step_verification`) | admin, super admin, org admin, org staff | lib/features/auth/mfa*.dart, lib/features/admin/admin_mfa_page.dart. items: admin service mfa | Stu1Auth?screen=mfa; AdmHome?screen=account; SupAdmins?sheet=mfa; Stu2Profile?screen=security | restyle | The design shows 2-step on the student security page; today the guide lists admin and org roles only. Verify before offering it to students. |
| Fingerprint / Face ID sign-in (`biometric_sign_in`) | everyone | lib/features/auth/biometric*.dart | Stu1Auth?screen=login&state=bio; Stu2Profile?screen=security | restyle |  |
| Display & reading (`display_reading`) | everyone | lib/features/profile/display/, lib/design/app_display.dart | Stu2Profile?screen=display | restyle |  |
| Editorial headings (`editorial_headings`) | everyone | lib/design/app_display.dart | not drawn | keep + restyle | Check against the new type scale in phase 1. |
| Motion and effects (`motion`) | everyone | lib/design/app_display.dart, lib/design/app_motion_kit.dart | Stu2Profile?screen=display | keep + restyle | The M1-M16 library obeys Reduce motion and app.animations. |
| Username (@) (`username`) | everyone | lib/features/auth/username*.dart | Stu1Auth?sheet=username | restyle |  |
| Edit your account details (`update_account`) | everyone | lib/features/profile/update_account_widget.dart. routes: `/edit-account` | Stu2Profile?screen=edit; Tea2Account?screen=edit (tab=docs) | replace | RULES 2: a student's avatar is an initial or an illustration, never a photo. Teachers and parents keep the photo and the cropper. |
| Change your password (`change_password`) | everyone | lib/features/profile/change_password_widget.dart. routes: `/change-password` | Stu2Profile?screen=security | restyle |  |
| Change the language and dark mode (`language_and_dark_mode`) | everyone | lib/features/profile/profile_screen.dart | Stu2Profile?screen=profile&adv=1; Pa2More?screen=more | restyle |  |
| Device binding and device switch requests (`device_binding`) | student | lib/features/courses/student/security/ | Stu2Profile?screen=security | restyle | The design adds a device list with sign-out per device: needs an endpoint. |
| Download a copy of my data (`download_my_data`) | everyone | lib/features/profile/privacy_export.dart | Stu2Profile?screen=data (state=ready, wait) | restyle |  |
| Log out and delete your account (`logout_delete_account`) | everyone | lib/features/profile/profile_screen.dart | Stu2Profile?sheet=delete | restyle |  |
| Parent link code (`parent_link_code`) | student | lib/features/parent/student_link_code_screen.dart | Stu2Profile?screen=parent | restyle | Keep this direction (student makes the code); the new direction is its own row. |
| Connected drives (`connected_drives`) | everyone | lib/features/profile/ (cloud drives) | not drawn | keep + restyle |  |
| Records (`records`) | everyone | lib/features/records/. push modules: records, records_shared | Stu1Learn?screen=records | restyle |  |
| Sharing recordings (`records_share`) | everyone | lib/features/records/records_share.dart | not drawn | keep + restyle |  |
| Confirm it's you before sensitive changes (`confirm_identity`) | everyone | lib/features/auth/reauth_sheet.dart | not drawn | keep + restyle |  |
| My profile and its public link (alfheemacademy.com/@yourname) (`profile_link`) | teacher, student, everyone | lib/features/profile/public_profile/. routes: `/@username` | Stu2Profile?screen=public; Tea2Account?screen=public | restyle | Student public page: initials only, no classmates. Server payload not audited yet (BACKEND_STATUS leak 11). |
| Fold the sections of your home (`home_fold_sections`) | student, teacher, org member | lib/design/home_kit.dart | not drawn | keep + restyle | The 5-second home is shorter: keep folding only where sections remain. |
| Get the app (`get_the_app`) | everyone | lib/features/get_app/ | not drawn | keep + restyle |  |
| Download the app from the website (`app_download_banner`) | everyone | landing/, lib/features/get_app/ | not drawn | keep + restyle |  |
| The Info (i) button, help panel and tour (`help_info_button`) | everyone | lib/features/help/ | not drawn | keep + restyle |  |
| Privacy policy and terms of service (`privacy_terms_pages`) | everyone | lib/features/profile/about/. routes: `/privacy`, `/terms` | Stu1Public?screen=legal; Stu2Profile?screen=about (tab=terms, privacy); Stu1Auth?sheet=terms | restyle |  |
| Personal account (`personal_account`) | org member, org staff, org admin | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Account fee for teachers and parents (`account_fee`) | teacher, parent, admin, super admin | lib/features/auth/account_fee_page.dart | Stu1Auth?screen=fee; Pa2Gate?screen=fee, feepending | restyle |  |
| How new accounts open: free, fee, or admin approval (`account_approval`) | teacher, parent, student, admin, super admin | lib/features/auth/account_approval_page.dart, lib/features/admin/admin_account_approval.dart. items: admin service svc_pending_accounts | Stu1Auth?screen=approval (state=rejected); AdmApprovals?screen=accounts; SupPlatform?screen=settings | restyle |  |
| The Downloads page (`downloads_page`) | everyone | landing/src/components/DownloadPage.astro | not drawn | keep + restyle |  |
| Inviting friends (`rewards_referral`) | student | lib/features/rewards/ | Stu2Money?screen=rewards | restyle |  |

## Discover

| Feature / screen | Roles | Today (file, route) | Design screen(s) | Decision | Notes |
|---|---|---|---|---|---|
| Find a course before creating an account (`guest_search_onboarding`) | student | lib/features/onboarding/. routes: `/explore (+ landing parsers)`, `/onboarding`, `/guest-search` | Stu1Auth?screen=onboard, guestsearch (sheet=subject) | restyle |  |
| Pin pages and colour your tabs (`dashboard_pins_colors`) | everyone | lib/design/shell_pins.dart | not drawn | keep + restyle | Must survive the new shells (phase 1). |
| Student home screen (`student_home`) | student | lib/features/home/student/home_screen.dart. routes: `/home`, `/dashboard`. items: student: home | StuHome?screen=home | restyle | One /me/home call, home budget test. One main action. |
| Browse categories and search for courses (`browse_categories`) | student | lib/features/courses/category/, lib/features/courses/student/list/ | Stu1Discover?screen=explore, category | restyle |  |
| Course details page (`course_details`) | student | lib/features/courses/student/details/. routes: `/courses/<courseId> (course)`, `/course-detail`, `/course-profile`. push modules: course, course_profile | SubjectProfile?enrolled=0 (SubjMGuest, SubjWGuest) | restyle | Drop enrolled counts for students (BACKEND_STATUS leak 5). Word is "دورة". The Book button starts BookFlow. |
| Teacher profile (`instructor_profile`) | student | lib/features/profile/course_instractor_profile.dart, lib/features/teachers/ | Stu2Teachers?screen=profile | restyle | Show the teacher's gender. Reviews: first name and grade only. |
| Favorites (`favorites`) | student | lib/features/profile/student_favorite_screen.dart | Stu1Discover?screen=favs | restyle |  |
| Learning roadmap (`learning_roadmap`) | student | lib/features/courses/roadmap/ | Stu1Discover?screen=journey (sheet=interests) | restyle | Personal accounts and personal courses only (D-120). |
| Recommended for you (`recommended_for_you`) | student | lib/features/courses/roadmap/recommendations.dart | Stu1Discover?screen=recs | restyle |  |
| Continue your journey (`home_journey`) | student | lib/features/home/student/home_journey.dart | StuHome?screen=home; Stu1Discover?screen=journey | restyle | Comes from /me/home, no request of its own. |
| Your next step is ready (`next_step_notice`) | student | lib/features/courses/roadmap/ | not drawn | keep + restyle |  |
| Open a private course with a code (`private_course_code`) | student | lib/features/courses/student/details/course_access_sheet.dart | Stu1Learn?screen=code (pin=wrong) | restyle |  |
| Keyboard on the web: Enter and shortcuts (`keyboard_shortcuts`) | everyone | lib/design/app_keyboard.dart | not drawn | keep + restyle |  |
| Live updates and pull to refresh (`live_updates_refresh`) | everyone | lib/core/live/, lib/design/app_refresh.dart | not drawn | keep + restyle |  |
| Quick search (Ctrl+K) (`entity_search`) | teacher, student, parent | lib/design/master_detail/entity_search_palette.dart | AdmHome?screen=search | keep + restyle | Ctrl+K stays for every role; only the admin palette is drawn. |
| Share links (`share_links`) | everyone | lib/features/share/share_link_page.dart. routes: `/c/<id>?ref=` | Stu1Public?screen=share | restyle |  |
| Join from the landing page (`join_flow`) | student, teacher, parent | lib/features/onboarding/join/. routes: `/join?role= (landing buttons)` | Stu1Auth?screen=join; Pa2Gate?screen=role, grade, mode, contact; LandingW funnel | restyle |  |
| Filter courses by stage and grade (`course_filters`) | student, parent | lib/features/courses/course_filters.dart | Stu1Discover?sheet=filter | restyle |  |
| Find a teacher (`teacher_discovery`) | student, parent | lib/features/teachers/teacher_discovery.dart. items: student: teachers (learn group) | Stu2Teachers?screen=list (sheet=filter), mine | restyle | Gender rules (RULES 2). |

## Learning

| Feature / screen | Roles | Today (file, route) | Design screen(s) | Decision | Notes |
|---|---|---|---|---|---|
| Enroll in a course (`course_enroll`) | student | lib/features/payments/enrollment/ | Stu2Money?screen=enroll (8 states); BookFlow step 4-5 | restyle | "مجاني" is not a selling point. The "group is full" state needs the groups model (WP6). |
| My courses (`my_courses`) | student | lib/features/courses/student/my_courses/. items: student: my_courses | Stu1Discover?screen=mycourses (empty=1) | restyle |  |
| Course lessons and materials (`course_lessons`) | student | lib/features/courses/course_space/course_sessions.dart, lib/features/sessions/material/ | Stu1Learn?screen=sessions, material; SubjectProfile?panel=lesson (ltab=book) | restyle | One sessions timeline. حصة and درس, never جلسة. |
| Lecture video player (`video_player`) | student | lib/features/sessions/video/ | Stu1Learn?screen=player (mode=end); SubjectProfile?fs=video | restyle | One player; ScreenSecurity stays. |
| Download lectures to watch offline (`offline_downloads`) | student | lib/features/downloads/, lib/core/offline/. routes: `/downloads` | Stu2Profile?screen=downloads (state=offline, empty) | restyle | Phone and desktop only. |
| My certificates and requesting one (`my_certificates`) | student | lib/features/certificates/student/ | Stu2Profile?screen=grades&tab=certs | restyle |  |
| My performance analytics (`student_analytics`) | student | lib/features/analytics/student/. items: student: analysis | Stu2Analysis?screen=overview, course (4 tabs), profile | restyle |  |
| Course profile in an organization (`org_course_profile`) | org member, org staff | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Follow your children (`parent_children`) | parent | lib/features/parent/parent_children_page.dart. items: parent: pl_tab_children | Pa2Kids?screen=list, detail, course | restyle |  |
| Parent consent for a child under the legal age (`parent_child_consent`) | parent | lib/features/parent/parent_consent.dart | Pa2Kids?screen=locked, consent, revoke | restyle |  |
| Link a parent account to a child (`parent_link_child`) | parent | lib/features/parent/parent_link_screen.dart. items: parent: pl_tab_link | Pa2More?screen=link, linkadv; Pa2Gate?screen=contact | restyle |  |
| Children's reports (`parent_reports`) | parent | lib/features/parent/parent_reports_page.dart. items: parent: pl_tab_reports. push modules: parent_grades, parent_child | Pa2Reports?screen=reports, child, how | restyle |  |
| The parent's Today tab (`parent_today`) | parent | lib/features/parent/parent_overview_page.dart. routes: `/parent_dashboard`. items: parent: pl_tab_today | Pa2Today?screen=today, all, empty | restyle | Home budget test. |
| Your personal courses apart from your organization's (`courses_by_side`) | student, teacher | lib/features/courses/course_scope*.dart | not drawn | keep + restyle |  |
| Audio only (recorded lessons) (`vod_listen_only`) | student, teacher | lib/features/sessions/video/vod_listen*.dart | Stu1Learn?screen=player&mode=audio | restyle |  |
| Your progress in a course (`student_course_story`) | student | lib/features/courses/course_space/ | Stu1Discover?screen=mycourses; SubjectProfile?enrolled=1 | restyle |  |
| My grades and payments (`student_grades_money`) | student | lib/features/home/student/record/student_record_pages.dart | Stu2Profile?screen=grades; Stu2Money?screen=history | restyle | StudentGradesPage and StudentMoneyPage exist. |
| Verify a certificate (`certificate_verify`) | everyone | lib/features/certificates/issue/cert_verify_*.dart. routes: `/verify, /verify/<token>` | Stu2Profile?screen=verify (state=ok, revoked) | restyle |  |
| Quran memorization and progress (`quran`) | student, parent, teacher | lib/features/quran/. routes: `/quran/progress`, `/quran/teachers/<teacherId>`. items: student: quran (learn group) | Stu2Quran?screen=quran, teacher, memo (sheet=log, rec); Pa2Kids?screen=quran | restyle | No sound effects, no images of living beings (RULES 2). |
| Learning Arabic grammar (nahw) with exercises (`nahw`) | student, parent | lib/features/nahw/. routes: `/nahw/lessons/<lessonId>`. items: student: nahw (learn group) | Stu2Nahw?screen=nahw, lesson; Pa2Kids?screen=nahw | restyle |  |
| Learning games and badges (`games`) | student | lib/features/games/. routes: `/games/progress`, `/games/<gameId>`. items: student: games (learn group) | Stu2Games?screen=games, play, result, progress (sheet=age, settings) | restyle |  |
| Reviewing your mistakes in games (`games_review`) | student | lib/features/games/ | not drawn | keep + restyle |  |
| Coins and the wardrobe (`games_wardrobe`) | student | lib/features/games/learner/wardrobe.dart | Stu2Games?screen=wardrobe | restyle |  |
| Friend challenges and the class board (`games_challenges`) | student | lib/features/games/learner/challenges.dart. routes: `/games/c/<code>`. push modules: games_challenge, games_champions, rewards | Stu2Games?screen=challenges | replace | Challenge by code stays, with nicknames (O-3). The per-class board is its own row (owner). |
| Download a level to play offline (`games_offline`) | student | lib/features/games/ | not drawn | keep + restyle |  |
| Reciter and calm mode in Quran games (`games_quran_reciter`) | student | lib/features/games/learner/games_settings_sheet.dart | Stu2Games?sheet=settings | keep + restyle |  |
| Game breaks while studying (`games_play_breaks`) | student | lib/features/games/ | not drawn | keep + restyle |  |
| The daily champion's trophy and locked coupon (`games_winner_coupon`) | student | lib/features/games/champions/, lib/features/rewards/ | Stu2Games?sheet=win; Stu2Money?screen=rewards | restyle |  |
| Your child's games summary (`parent_games_summary`) | parent | lib/features/games/games_progress.dart | Pa2Kids?screen=games | restyle |  |
| Work offline, synced later (`offline_sync`) | student | lib/core/offline/, lib/design/sync_status_chip.dart | not drawn | keep + restyle |  |
| Self-learning: a short lesson and a review every day (`self_learning`) | student | lib/features/self_learning/. routes: `/learn/daily (self_learning)`. push modules: self_learning, sl_lesson, sl_review | Stu2Quran?screen=daily (mode=lesson, review, done, off) | restyle | The design puts the daily lessons inside the Quran area; today they are their own page. Placement to confirm. |
| Teacher packages (`packages`) | student, teacher | lib/features/teachers/teacher_discovery.dart, lib/features/teachers/package_wizard.dart | Stu2Teachers?screen=pack (6 states, sheet=leave); Tea2Teach?screen=package (step 1-3) | restyle | RULES 1.4: never show classes per week or month. Students see seats left only (leak 6). Group 5-10 and gender: WP6. |
| Games leaderboard (`games_leaderboard`) | student | lib/features/games/game_leaderboard.dart | Stu2Games?sheet=board | replace | RULES 1.9 and O-3: nicknames, platform or grade wide. Needs WP4. |
| Daily and weekly games champions (`games_champions`) | student, parent | lib/features/games/champions/ | Stu2Games?screen=champions (state=nochamp, sheet=win, rules) | replace | O-3: nicknames only. Needs WP4. |

## Live

| Feature / screen | Roles | Today (file, route) | Design screen(s) | Decision | Notes |
|---|---|---|---|---|---|
| Join a live session (`live_join`) | student | lib/features/live/room/prejoin.dart | Stu1Learn?screen=prejoin (wait=1); SubjectProfile?panel=live | replace | RULES 1.7: no participant count; shows "الحصة شغّالة" and the teacher only. Server: WP1. |
| Live room tools: chat, raise hand and reactions (`live_room_tools`) | student, teacher | lib/features/live/room/ | SubjectProfile?panel=live, fs=live; Tea1Live?screen=room | replace | RULES 1.7: a student sees "أنت والمعلم" only. Chat, hands and reactions reach the teacher only. The teacher keeps every tool. Server: WP1. |
| Start and run a live session (`live_start_teacher`) | teacher | lib/features/live/live_room.dart | Tea1Live?screen=prejoin, room, ended; Tea1Home?screen=golive | restyle | The room is not a route (LiveRoomHost). |
| Share your screen in a live session (`live_screen_share`) | teacher | lib/features/live/live_share_*.dart | Tea1Live?screen=room | restyle |  |
| Record a live session (`live_recording`) | teacher | lib/features/live/meeting_recording*.dart | Tea1Live?screen=room | restyle |  |
| Guest link for a live session (`live_guest_link`) | teacher | lib/features/guest/guest_live_page.dart. routes: `/live/<token>` | Tea1Course?screen=guest; Stu1Public?screen=liveguest (state=after) | restyle | A guest never calls an authenticated API. |
| Share a live room link (session or meeting) (`live_share_link`) | teacher, org admin, org staff, student | lib/features/live/ | not drawn | keep + restyle | For students this applies to their own meetings only (O-2). |
| Lobby: admit people before they enter (`live_lobby`) | teacher, org admin, org staff, student | lib/features/live/live_lobby_sheets.dart. push modules: live_lobby | Tea1Live?screen=lobby | restyle |  |
| Host controls over participants (`live_teacher_controls`) | teacher, org admin, org staff, student | lib/features/live/live_participant_controls.dart | Tea1Live?screen=room | restyle | In a class only the teacher has the participants list. |
| Lock the room to new joins (`live_room_lock`) | teacher, org admin, org staff, student | lib/features/live/ | not drawn | keep + restyle |  |
| Use your phone as the camera, microphone or speaker of a live room (`live_companion_device`) | student, teacher, parent, org admin, org staff, admin | lib/features/live/. push modules: live_companion | not drawn | keep + restyle |  |
| End or leave a meeting, and hand the host controls over (`live_host_handover`) | teacher, org admin, org staff, student | lib/features/live/ | not drawn | keep + restyle |  |
| Annotate a shared screen (`live_annotation`) | teacher, org admin, org staff, student | lib/features/live/ | not drawn | keep + restyle |  |
| Whiteboard in a live room (`live_whiteboard`) | teacher, org admin, org staff, student | lib/features/live/ | not drawn | keep + restyle |  |
| One screen share at a time, and asking to share (`live_share_requests`) | teacher, org admin, org staff, student | lib/features/live/ | not drawn | keep + restyle |  |
| Quick meeting (Meet now) (`live_quick_meeting`) | everyone | lib/design/quick_meeting_entry.dart, lib/features/calendar/ | Stu2Schedule (menu "ابدأ اجتماع الحين"); Tea2Schedule?screen=new | replace | O-2: kept. A student invites by username or phone only, the app never suggests classmates, guests do not see each other. Needs WP11. |
| Go live from the home (`teacher_quick_live`) | teacher | lib/features/home/teacher/go_live*.dart | Tea1Home?screen=golive | restyle |  |
| Direct guest link (no waiting) (`live_direct_guest_link`) | teacher, student, org staff, org admin | lib/features/live/ | not drawn | keep + restyle |  |
| "Live now" on the home screen (`home_live_now`) | student, teacher, org member | lib/features/home/student/home_live.dart, lib/features/home/teacher/queue_work_items.dart | StuHome?screen=home; Tea1Home?screen=home | restyle | M8 halo. No counts for students. |
| Meeting links (`meeting_links`) | student, teacher, org admin, org staff | lib/features/live/meeting_links*.dart. routes: `/meeting-links (meetings.links)` | Stu2Schedule?screen=links; Tea1Home?screen=meetings | restyle |  |

## Exams

| Feature / screen | Roles | Today (file, route) | Design screen(s) | Decision | Notes |
|---|---|---|---|---|---|
| Take a course exam (`exam_take`) | student | lib/features/exams/exam_taking*.dart, lib/features/exams/legacy/student/. push modules: exam, exam_notice, omr_batch, mark_session, exam_appeal, exam_result(s), exam_identifiers | Stu2Exams?screen=list (sheet=code), consent, take (q=0..7, sheet=submit) | restyle | ScreenSecurity stays. No "قواعد الاختبار" card: 3 icon rows. |
| Exam results and asking for a regrade (`exam_result_appeal`) | student | lib/features/exams/exam_result_screen.dart | Stu2Exams?screen=result (4 states, sheet=appeal, appeal=sent) | restyle |  |
| Take an exam without internet (`exam_offline_student`) | student | lib/features/exams/offline/ | Stu2Exams?screen=offline (3 states) | restyle | No system words. |
| Create a quick exam (`exam_quick_create`) | teacher, admin, super admin | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Generate exam questions from the course documents (`exam_generate_from_documents`) | teacher | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Question bank (`exam_question_bank`) | teacher | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Full exam editor and proctoring (`exam_full_editor`) | teacher | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Review marking and publish results (`exam_review_marking`) | teacher | lib/features/exams/exam_review_screen.dart | Tea2Exams?screen=grade | restyle |  |
| Mark paper exams from scanned sheets (`exam_paper_scans`) | teacher | lib/features/exams/paper/scan/ | Tea2Exams?screen=papers | restyle |  |
| Exam appeals and analytics (`exam_appeals_analytics`) | teacher | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Printable exam paper (`exam_printable_paper`) | teacher, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Exam paper and cover designer (`exam_paper_designer`) | teacher, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Lock the next lessons until the exam is passed (`exam_session_lock`) | teacher, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Import questions from Excel and export results (`exam_excel_import`) | teacher, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Hand out and collect an exam in the hall without internet (`exam_offline_sitting`) | teacher | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Set up a paper exam (student ID, type, sheet, models) (`exam_paper_setup`) | teacher, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Enter the ID your teacher needs for an exam (`exam_identifier_request`) | student | lib/features/exams/identity/. push modules: identity_requests | (removed from the student exam list) | replace | O-4 and RULES 2: a national ID or iqama is asked only through the parent. A school seat or student number may stay. Owner to confirm what "identifier" may be. |
| Bubble sheet types and teaching the platform a new sheet (`omr_sheet_types`) | super admin | lib/features/exams/paper/. items: admin service svc_omr_templates | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Add your own bubble sheet from one photo (`omr_custom_layout`) | teacher, org staff | lib/features/exams/paper/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Print bubble sheets (`omr_print_sheets`) | teacher, org staff | lib/features/exams/paper/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Scan bubble sheets with the camera or upload them (`omr_scan_sheets`) | teacher, org staff | lib/features/exams/paper/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Review scanned papers (`omr_review_queue`) | teacher, org staff | lib/features/exams/paper/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Paper exam results and publishing (`omr_paper_results`) | teacher, org staff | lib/features/exams/paper/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Exam questions written by AI agents (`exam_generate_agents`) | teacher, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| What students see of their result, and publishing or unpublishing results (`exam_results_visibility`) | teacher, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Cancel a question (`exam_question_void`) | teacher, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Grade log (`exam_grade_log`) | teacher, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Register your own mark sheet (`exam_mark_templates`) | teacher, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Grade review by camera (`exam_grade_review`) | teacher, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Mark import from paper (`exam_mark_import`) | teacher, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Scan issues list (`exam_scan_issues`) | teacher, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| What parents see of exam grades (`grades_parent_visibility`) | super admin, org admin | lib/features/exams/parent_grade_visibility.dart. items: admin service svc_parent_grades | SupSystems?screen=exams (parents tab) | restyle |  |
| Import an exam from Google Forms (`exam_import_google_forms`) | teacher, org admin, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| All exams (`exam_all_exams`) | teacher, org admin, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Question generation in the background: fast or best quality, and from a topic when there are no files (`exam_generate_background`) | teacher, org admin, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Mark papers on your own sheet (any bubble sheet or a written answer table) (`exam_own_sheet`) | teacher, org admin, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Use any answer sheet, even one printed outside the platform (`bubble_import_sheet`) | teacher, org staff | lib/features/exams/paper/bubble/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Correct a whole class from photos or a PDF (`bubble_correct_class`) | teacher, org staff | lib/features/exams/paper/bubble/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Write the marks into a Data Lab column or download Excel (`bubble_marks_datalab`) | teacher, org staff | lib/features/exams/paper/bubble/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Exams (`exam_hub`) | teacher, org staff, admin | lib/features/exams/hub/. items: admin service svc_exam_hub | Tea2Exams?screen=hub | restyle |  |
| New exam wizard (`exam_create_wizard`) | teacher, org staff, admin | lib/features/exams/hub/create/ | Tea2Exams?screen=wizard (step=how, q, settings, sheet) | restyle |  |
| Grade papers (`exam_grade_papers`) | teacher, org staff | lib/features/exams/hub/grade/ | Tea2Exams?screen=papers | restyle |  |
| Bubble correction from the model answer (`exam_bubble_from_key`) | teacher, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Correct papers of students in no course (`exam_bubble_no_course`) | teacher, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Corrected sheets (`exam_bubble_corrected_sheets`) | teacher, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Grade written papers without an exam (`exam_essay_run`) | teacher, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Automatic grading of written answers (word, short answer, essay) (`exam_auto_grade`) | teacher, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Answer booklet (`exam_answer_booklet`) | teacher, org staff, admin | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Fix a question's key (`exam_key_fix`) | teacher, org staff, admin | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Duplicate an exam (`exam_duplicate`) | teacher, org staff, admin | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Print and deliver an exam (`exam_deliver`) | teacher, org staff, admin | lib/features/exams/hub/deliver/ | Tea2Exams?screen=deliver | restyle |  |
| Correct the exam (`exam_correct`) | teacher, org staff, admin | lib/features/exams/hub/correct/ | Tea2Exams?screen=grade | restyle |  |
| Exam results (`exam_results_hub`) | teacher, org staff, admin | lib/features/exams/hub/result/ | Tea2Exams?screen=results | restyle |  |
| Grade revision (`exam_revision`) | teacher, org staff, admin | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Machine-read answer sheet (`exam_answer_sheet`) | teacher, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Paper exam answer layout and printed student details (`exam_offline_layout`) | teacher, org staff | lib/features/exams/ | not drawn | keep + restyle | Kept as is (paper exams, OMR and teacher tools are on the PARITY keep list). |
| Exam settings for the platform (`exam_policy`) | super admin | lib/features/admin/admin_exam_policy_page.dart. items: admin service svc_exam_policy | SupSystems?screen=exams | restyle |  |

## Teaching

| Feature / screen | Roles | Today (file, route) | Design screen(s) | Decision | Notes |
|---|---|---|---|---|---|
| Course path (teacher) (`course_roadmap_manage`) | teacher | lib/features/courses/roadmap/roadmap_editor.dart | Tea1Class?screen=path | restyle |  |
| Teacher home screen (`teacher_home`) | teacher | lib/features/home/teacher/home_screen.dart. routes: `/teacher_dashboard`. items: teacher: home | Tea1Home?screen=home, calm, first | restyle | Home budget test. |
| Create a new course (`course_create`) | teacher | lib/features/courses/teacher/course_form_screen.dart | Tea1Wizard?screen=basics, pricing, audience, privacy, schedule, extras, review | replace | One 2012-line form becomes a 7-step wizard. Keep the provider and fields. A personal course never sends next_course_ids. |
| Edit, publish and delete a course (`course_manage_publish`) | teacher | lib/features/courses/teacher/courses_screen.dart. items: teacher: my_courses | Tea1Courses?screen=list (menu=1), del | restyle |  |
| Your course page (`teacher_course_page`) | teacher | lib/features/courses/course_space/, lib/features/courses/course_profile/ | Tea1Course?screen=overview, draft; Tea1Courses?screen=panel | restyle | CourseSpace is the one course page for every role. |
| Private course and discount (`course_privacy_discount`) | teacher | lib/features/courses/teacher/course_privacy_card.dart | Tea1Wizard?screen=privacy, pricing | restyle |  |
| Add lessons (live or pre-recorded) (`lessons_add`) | teacher | lib/features/sessions/teacher/ | Tea1Course?screen=sessions (menu=1), sform | restyle |  |
| Upload materials and videos to a lesson (`materials_upload`) | teacher | lib/features/sessions/material/, lib/features/upload/ | Tea1Course?screen=material, uploads | restyle |  |
| Studio on session videos (`materials_studio`) | teacher, org staff, org admin, super admin | lib/design/studio/ | not drawn | keep + restyle |  |
| Guest links: a video or a meeting that opens straight away, no account (`guest_share_links`) | teacher, org staff, org admin, super admin, student, parent | lib/features/sessions/material/material_guest_links_sheet.dart, lib/features/records/. routes: `/s/<kind>/<id>, /s/page/<id>` | Tea1Course?screen=captions, guest | restyle |  |
| Download a video from the Studio, before or after editing (`studio_download`) | teacher, org staff, org admin, super admin | lib/design/studio/ | not drawn | keep + restyle |  |
| Captions for lecture videos (`video_captions`) | teacher | lib/features/sessions/material/components/session_material_grid.dart | Tea1Course?screen=captions | restyle | Exists (upload .vtt or generate). |
| Open attendance with a rotating code (`attendance_start_teacher`) | teacher | lib/features/attendance/ | Tea1Class?screen=attendance, attcode, attqr, attmanual | restyle |  |
| Attendance record and manual edits (`attendance_record_teacher`) | teacher | lib/features/attendance/analysis/teacher/ | Tea1Class?screen=attmanual | restyle |  |
| Manage and send course certificates (`certificates_manage`) | teacher | lib/features/certificates/certificate_requests_screen.dart | Tea2Certs?screen=requests | restyle |  |
| Certificate designs (`certificate_designer`) | teacher, org admin | lib/features/certificates/designer/ | Tea2Certs?screen=designs, wizard | restyle | The wizard before the studio is new. |
| Certificate studio (the shared design engine) (`certificate_studio`) | teacher, org admin | lib/features/certificates/studio/ | Tea2Certs?screen=designer | restyle |  |
| Background colours of certificate templates (`certificate_template_colours`) | teacher, org admin | lib/features/certificates/ | not drawn | keep + restyle |  |
| Ready wordings for the certificate text (`certificate_preambles`) | teacher, org admin | lib/features/certificates/ | not drawn | keep + restyle |  |
| Issue certificates without a course (`certificate_issue_standalone`) | teacher, org admin, org staff | lib/features/certificates/issue/ | Tea2Certs?screen=issue (step 1-5) | restyle |  |
| Issued certificates history and verification (`certificate_history_verify`) | teacher, org admin, org staff | lib/features/certificates/issue/cert_issue_history.dart | Tea2Certs?screen=history | restyle |  |
| Teacher analytics (`teacher_analytics_hub`) | teacher | lib/features/analytics/teacher/. items: teacher: analysis | Tea2Analysis?screen=hub, flags | restyle | The "اسأل عن فصولك" box in the hub has no counterpart found: verify. |
| Data Lab (`data_lab`) | teacher, student | lib/features/data_lab/. items: admin service dl_admin_title | Tea2Analysis?screen=lab, ask, col | restyle |  |
| Approve device switch requests (`device_switch_approve`) | teacher | lib/features/profile/teacher/switch_device_requests/ | Tea2Account?screen=devices; AdmApprovals?screen=devices | restyle |  |
| Teacher ads (`teacher_ads`) | teacher | lib/features/ads/ads_pages.dart | Tea2Money?screen=ads, adnew | restyle |  |
| My students, submissions and reviews (`teacher_my_students`) | teacher | lib/features/home/teacher/classroom/teacher_classroom.dart | Tea1Courses?screen=students, submissions, reviews | restyle | Exists (D-290). |
| Saved views and bulk actions (`list_views_bulk`) | teacher, admin | lib/design/master_detail/, lib/features/admin/admin_bulk.dart | AdmStudents?screen=list, filters | restyle |  |
| Your automatic to-do list (`teacher_todo`) | teacher | lib/features/home/teacher/todo/. push modules: teacher_todo | Tea1Home?screen=todo (menu=1) | restyle |  |
| Remove an image's background (`image_background_removal`) | student, teacher, parent, org admin, org staff, org member, admin, super admin | lib/design/app_image_background.dart | not drawn | keep + restyle |  |
| Course students and nudging low-progress students (`course_students_nudge`) | teacher, org staff, admin | lib/features/sessions/teacher/students/ | Tea1Class?screen=students, nudge | restyle |  |
| Course rules (`course_rules`) | teacher, org staff, student, org member | lib/features/courses/course_profile/course_page_sheets.dart | Tea1Class?screen=rules | restyle | For students: at most 3 icon rows. |
| Course sections (`course_sections`) | teacher, org staff, org admin, student, org member | lib/features/courses/course_profile/course_page_sheets.dart. items: org academics > sections | Tea1Class?screen=rules | restyle | A student sees only his own section, never its members. |
| Turn attendance on or off (`course_attendance_flag`) | teacher, org staff | lib/features/courses/course_profile/ | not drawn | keep + restyle |  |
| The Quran teacher's profile and record sheet (`quran_teacher`) | teacher, super admin | lib/features/quran/quran_teacher_hub.dart | Tea2Teach?screen=quran, record | restyle |  |
| Teacher profile and approval (`teacher_card`) | teacher | lib/features/teachers/teacher_onboarding.dart, lib/features/teachers/teacher_review_admin.dart. items: admin service admin_teacher_review | Tea2Teach?screen=hub (status=rejected); AdmTeachers?screen=review | restyle | TeacherHubPage exists with the status card and My packages. |

## Schedule and attendance

| Feature / screen | Roles | Today (file, route) | Design screen(s) | Decision | Notes |
|---|---|---|---|---|---|
| Teacher weekly schedule (`teacher_weekly_schedule`) | teacher | lib/features/calendar/schedule_page.dart, lib/features/home/teacher/schedules/. items: teacher: my_schedule | Tea2Schedule?screen=cal, month, list; Tea1Wizard?screen=schedule, schedadd | restyle |  |
| Student schedule (`student_schedule`) | student | lib/features/calendar/schedule_page.dart. items: student: my_schedule | Stu2Schedule?screen=list, cal (state=empty, error); SubjectProfile?panel=cal | restyle | Sunday to Thursday. Say the time zone when it differs (RULES 3). |
| My schedule: agenda, day, week and month (`calendar_views`) | student, teacher, parent, org member, org staff, org admin, admin, super admin | lib/features/calendar/. routes: `/calendar`. push modules: calendar | Stu2Schedule; Tea2Schedule; Pa2Shared?screen=calendar | restyle | One GET /me/calendar per range. |
| Create a meeting and invite people (`meetings_create`) | teacher, org member, org staff, org admin | lib/features/calendar/calendar_meeting.dart | Tea2Schedule?screen=new; Stu2Schedule?sheet=new | restyle | 409 attendees_busy stays. Student host: see the O-2 row. |
| Answer meeting invitations (`meetings_respond`) | teacher, org member, org staff, org admin | lib/features/calendar/calendar_meeting.dart | Tea2Schedule?screen=meet; Stu2Schedule?sheet=meet | replace | RULES 1.7: a student invitee must not see the other invitees (leak 9). Staff keep the list. |
| Record a meeting to your drive (`meeting_recording_cloud`) | teacher, org member, org staff, org admin | lib/features/live/meeting_recording*.dart | not drawn | keep + restyle |  |
| Check in with the attendance code (`attendance_check_in`) | student | lib/features/attendance/ | Stu1Learn?screen=attend (sheet=checkin, state=done) | restyle | No system words (GPS, Bluetooth). Own row only. |
| Check in without internet through a classmate (`attendance_offline_relay`) | student | lib/features/attendance/relay_*.dart, offline_attendance_tab.dart | (not drawn: invisible to the student) | replace | O-6 and RULES 1.7: the mechanism stays, the student never sees "عبر زميل" or named witnesses (leak 10). |
| My timetable in the organization (`org_my_timetable`) | org member | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Session changes: online, cancelled or substitute (`org_session_changes`) | org member | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| My exams in the organization (`org_my_exams`) | org member | lib/features/org/. push modules: org_exams | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Recurring meetings (`calendar_recurring_meetings`) | student, teacher, org member, org staff, org admin, admin, super admin | lib/features/calendar/recurrence/ | not drawn | keep + restyle |  |
| Course online meetings and the one guest link (`course_online_meetings`) | teacher | lib/features/sessions/teacher/ | not drawn | keep + restyle |  |

## Communication

| Feature / screen | Roles | Today (file, route) | Design screen(s) | Decision | Notes |
|---|---|---|---|---|---|
| Notifications (`notifications`) | everyone | lib/features/messaging/notification/. push modules: notifications | Stu1Comm?screen=inbox&tab=notif; Pa2Shared?screen=notifs | restyle | Push texts not audited for classmates' names (leak 11). |
| Help Center: complaints and support (`help_center_complaints`) | everyone | lib/features/profile/compalints/. push modules: support | Stu1Comm?screen=complaints, newcomplaint; Tea2Account?screen=complaints, newcomplaint; Pa2Shared?screen=complaints | restyle |  |
| Handle incoming complaints (`complaints_handle`) | teacher, org admin, org staff, admin, super admin | lib/features/profile/compalints/complaints_screen.dart. items: admin service help_center | AdmSupport?screen=tickets | restyle |  |
| Unified inbox (`unified_inbox`) | student, teacher, org member, org staff | lib/features/messaging/inbox/. routes: `/inbox, /notifications`. push modules: inbox (kind todo / announcement / offer) | Stu1Comm?screen=inbox; Tea1Home?screen=inbox; Pa2Shared?screen=inbox | restyle |  |
| Course announcements (`course_announcements`) | teacher, org staff, org member | lib/features/courses/course_profile/course_profile_announcements.dart | Stu1Comm?pane=thread&conv=ann; Tea1Class?screen=announce | restyle | One-way thread. A student's reply goes privately to the teacher. |
| Organization news and announcements (`org_announcements`) | org admin, org staff, org member | lib/features/org/. items: org services > announcements | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Mention someone by typing @ (`mentions`) | everyone | lib/design/app_mentions.dart | not drawn | keep + restyle |  |
| Complaints and questions inside the organization (`org_complaints_member`) | org member, org staff, org admin | lib/features/org/. items: org services > complaints | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Parent alerts (`parent_alerts`) | parent | lib/features/parent/parent_alerts_page.dart. items: parent: pl_tab_alerts | Pa2Alerts?screen=alerts, empty | restyle |  |
| Broadcast a message (`admin_broadcast_message`) | admin, super admin | lib/features/admin/admin_send_message_page.dart. items: admin service send_message | AdmPeople?screen=message; SupAds?screen=broadcast (confirm) | restyle | The "all users" audience and the confirm step are new. |
| Message the organization's students: normal, with a push, or must-acknowledge (`org_messages`) | org admin, org staff, teacher | lib/features/org/. items: org services > messages subs. push modules: org_message | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| A must-acknowledge message from your organization (`org_must_ack`) | student, org member | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Submit a complaint or a request to an entity and follow it (`org_gov_submit`) | org member, student, teacher, org staff | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| File a request or complaint for a member or for someone outside the system (`org_gov_for_others`) | org admin, org staff, teacher | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Request attachments: upload, preview and download (`org_gov_attachments`) | org member, student, teacher, org staff, org admin | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Message your child's teacher (`parent_message_teacher`) | parent | lib/features/parent/parent_message_teacher.dart | Pa2Today?screen=msg; Pa2Shared?screen=chat | restyle |  |
| Messages (`chat_messages`) | student, teacher, parent, org admin, org staff, admin, super admin | lib/features/messaging/chat/. routes: `/chat`. push modules: chat | Stu1Comm?screen=chat (pane=thread, sheet=new); Tea2Chat?screen=chat, thread, newmsg; Pa2Shared?screen=chats | replace | RULES 1.7: a student may message only his own teachers and support. No "message anyone", no suggested people, no student to student links (leak 4). Teachers, parents and staff keep today's chat. |
| Course group (`chat_course_groups`) | student, teacher | lib/features/messaging/chat/ | Stu1Comm?pane=thread&conv=ann | replace | O-5 and RULES 1.7: the course group chat becomes the teacher's announcements thread; the members list is hidden from students. Needs WP3. |
| Blocking and reporting in chats (`chat_blocking`) | student, teacher, parent, org admin, org staff | lib/features/messaging/chat/chat_sheets.dart. routes: `/chat/blocks`, `/chat/reports`. push modules: chat_reports | Stu1Comm?sheet=block | restyle |  |
| Message a department of your organization (`org_message_department`) | org member, student, teacher | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Organization notifications on your phone: all, important only, or off (`org_notify_settings`) | org member, org staff, org admin, teacher | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |

## Payments

| Feature / screen | Roles | Today (file, route) | Design screen(s) | Decision | Notes |
|---|---|---|---|---|---|
| Pay by card (`pay_by_card`) | student | lib/features/payments/enrollment/checkout_*.dart, saved_cards/ | Stu2Money?screen=enroll; BookFlow step 4; Stu2Store?sheet=checkout | restyle | Methods by country: مدى and STC Pay in KSA only (RULES 3, WP8). VAT only where it applies. |
| Pay by bank transfer or InstaPay (`pay_by_transfer`) | student | lib/features/payments/enrollment/transfer/ | Stu2Money?screen=transfer (state=review, rejected) | restyle | InstaPay is an Egypt method: show it by country. |
| Platform subscription (`platform_subscription`) | student | lib/features/payments/subscription/. routes: `/subscription`. push modules: subscription | Stu2Money?screen=subscribe (5 states) | restyle |  |
| Points wallet and the live-meeting plan (`points_wallet`) | everyone | lib/features/payments/points/. push modules: points, live_plan, live_plan_expiring, live_plan_renewed, live_plan_renew_failed | Stu2Money?screen=wallet (sheet=buy, plan, help; short=1) | restyle |  |
| Points and top-up requests (admin) (`admin_points`) | admin, super admin | lib/features/admin/admin_points_page.dart. items: admin service admin_points | SupPricing?screen=rewards (points tab) | restyle |  |
| Review transfer payment requests (`transfer_requests_review`) | teacher, admin, super admin | lib/features/payments/enrollment_request/. items: admin service enrollment_requests | Tea1Home?screen=transfers, reject; AdmApprovals?screen=transfer, reject; SupFinance?screen=payments | restyle |  |
| Teacher earnings and withdrawals (`teacher_payouts`) | teacher | lib/features/profile/teacher/payout/ | Tea2Money?screen=earn, withdraw, addacc | restyle | IBAN of any country (RULES 3, WP8). |
| Manage teacher payouts (`admin_payouts`) | admin, super admin | lib/features/admin/admin_payouts_page.dart. items: admin service payout | SupFinance?screen=payouts | restyle |  |
| Payments history and refunds (`admin_payments_refunds`) | admin, super admin | lib/features/admin/admin_finance_page.dart. items: admin service admin_payments | SupFinance?screen=money | restyle |  |
| Payment methods and subscription settings (`admin_payment_settings`) | admin, super admin | lib/features/admin/admin_payment_page.dart, admin_subscriptions_page.dart. items: admin service subscriptions; admin service apm_title | SupPricing?screen=methods, tab=subs | restyle |  |
| The digital store and My Library (`store`) | student, parent | lib/features/store/. routes: `/store/library (store.library)`, `/store/<itemId> (store.item)`. items: student: store (learn group) | Stu2Store (store, item, checkout states, library, reader) | restyle |  |
| Package refunds due (`admin_package_refunds_due`) | admin, super admin | lib/features/admin/ | not drawn | keep + restyle |  |
| My rewards and discount coupons (`rewards_coupons`) | student | lib/features/rewards/ | Stu2Money?screen=rewards | restyle |  |

## Assistant

| Feature / screen | Roles | Today (file, route) | Design screen(s) | Decision | Notes |
|---|---|---|---|---|---|
| Ask about the app (`app_assistant`) | everyone | lib/features/rag/ | Stu1Comm?screen=assistant | restyle |  |
| Documents assistant (`documents_assistant`) | org member, org staff, student | lib/features/rag/ | SubjectProfile?panel=bot (SubjMBot, SubjMBotOff) | restyle | The per-subject scope and the locked state are new (WP11). |
| Documents library for the assistant (`documents_library`) | org admin, org staff, teacher | lib/features/rag/. items: org services > materials (Library) | not drawn | keep + restyle | Kept (the app assistant is on the PARITY keep list). |
| App assistant dashboard and library quotas (`app_assistant_admin`) | admin, super admin | lib/features/rag/ | not drawn | keep + restyle | Kept (the app assistant is on the PARITY keep list). |
| The AI app assistant (`app_assistant_chat`) | everyone | lib/features/rag/app_assistant.dart | Stu1Comm?screen=assistant; Bot | restyle | AppAssistantHost stays in the MaterialApp.builder stack. |
| Curated Q&A for the assistant (`rag_qa_admin`) | super admin, admin, org admin | lib/features/rag/ | not drawn | keep + restyle | Kept (the app assistant is on the PARITY keep list). |
| Learning from feedback: the assistant and the question generator improve with use (`rag_learning`) | super admin, admin, org admin | lib/features/rag/ | not drawn | keep + restyle | Kept (the app assistant is on the PARITY keep list). |
| Assistant chats: New chat and chat history (`assistant_chat_sessions`) | everyone | lib/features/rag/rag_chat_sessions.dart | Stu1Comm?screen=assistant (fresh=1, sheet=history) | restyle |  |
| Rate the assistant's answers (`assistant_answer_feedback`) | everyone | lib/features/rag/ | not drawn | keep + restyle | Kept (the app assistant is on the PARITY keep list). |
| Personal questions to the assistant (`assistant_personal_questions`) | student | lib/features/rag/ | not drawn | keep + restyle | Kept (the app assistant is on the PARITY keep list). |
| Answers with buttons that open the page (`assistant_action_buttons`) | everyone | lib/features/rag/ | not drawn | keep + restyle | Kept (the app assistant is on the PARITY keep list). |
| Answer mode and streaming (`assistant_answer_modes`) | everyone | lib/features/rag/ | not drawn | keep + restyle | Kept (the app assistant is on the PARITY keep list). |
| Feedback review and verified answers (`assistant_feedback_review`) | super admin, admin, org admin | lib/features/rag/ | not drawn | keep + restyle | Kept (the app assistant is on the PARITY keep list). |
| Upload scopes and scan warnings (`documents_upload_scopes`) | super admin, admin, org admin, org staff, teacher | lib/features/rag/ | not drawn | keep + restyle | Kept (the app assistant is on the PARITY keep list). |

## Administration

| Feature / screen | Roles | Today (file, route) | Design screen(s) | Decision | Notes |
|---|---|---|---|---|---|
| Student study details settings (`study_profile_settings`) | super admin | lib/features/admin/admin_study_profile_settings_page.dart. items: admin service svc_study_profile | SupPlatform?tab=study | restyle |  |
| Live performance (`admin_live_settings`) | super admin | lib/features/admin/live_settings/. items: admin service admin_live_settings | SupSystems?screen=live | restyle |  |
| App versions (`admin_app_releases`) | super admin | lib/features/admin/app_releases/. items: admin service svc_app_releases. push modules: app_release, app_releases | SupReleases?screen=versions, build, detail | restyle |  |
| Landing page (`admin_landing`) | super admin | lib/features/admin/landing/. items: admin service admin_landing | SupSite?screen=landing | restyle | Must know the three landing pages. |
| Recommendations (super admin) (`admin_recommendations`) | super admin | lib/features/admin/admin_recs_page.dart. items: admin service admin_recommendations | SupHome?sheet=recs | restyle |  |
| Username numbers (`admin_username_stats`) | admin, super admin | lib/features/admin/. items: admin service admin_username_stats | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| Manage students, teachers and admins (`admin_users`) | admin, super admin | lib/features/admin/admin_users_page.dart, lib/design/master_detail/. items: admin service admin_admins | AdmStudents; AdmTeachers?screen=list, detail; SupAdmins?screen=admins | restyle |  |
| Manage courses and categories (`admin_courses_categories`) | admin, super admin | lib/features/admin/admin_courses_page.dart, admin_categories_page.dart. items: admin service categories | AdmCourses?screen=list, detail, form; AdmContent?screen=cats | restyle |  |
| Connected teacher and category details (`admin_teacher_category_details`) | admin, super admin | lib/features/admin/admin_entity_manage.dart | AdmTeachers?screen=detail | restyle |  |
| Approve and manage organizations (`admin_organizations`) | admin, super admin | lib/features/admin/. items: admin service svc_organizations | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| View the app as a user (`admin_view_as`) | super admin | lib/features/admin/admin_view_as_page.dart | SupAdmins?screen=viewas | restyle |  |
| App configuration: features, theme and versions (`admin_app_configuration`) | admin, super admin | lib/features/admin/admin_features_page.dart, admin_theme_page.dart, admin_versions_page.dart. items: admin service theme; admin service features | SupPlatform?screen=modules&tab=feats, tab=kill; SupSite?screen=landing (theme); SupReleases?screen=versions | restyle | The new palette goes in the theme defaults and the backend theme seed. |
| Platform settings (`admin_platform_settings`) | super admin | lib/features/admin/admin_platform_settings_page.dart, admin_auth_settings_page.dart. items: admin service auth_settings_title; admin service svc_platform_settings | SupPlatform?screen=settings (tab=region, dev), auth | restyle |  |
| Device limits and teacher documents (`admin_devices_documents`) | admin, super admin | lib/features/admin/admin_devices_page.dart, admin_required_documents_page.dart. items: admin service admin_devices; admin service required_documents_title | AdmSupport?screen=sessions; AdmApprovals?screen=devices; AdmTeachers?screen=docs | restyle |  |
| Data Center and platform requirements (`admin_data_center`) | admin, super admin | lib/features/admin/admin_datacenter_page.dart. items: org services > datacenter; admin service svc_datacenter; admin service svc_requirements | AdmData?screen=datacenter, import; AdmPeople?screen=notices; SupData?screen=datacenter | restyle |  |
| Parent link requests and settings (`admin_parent_links`) | admin, super admin | lib/features/admin/admin_parent_linking_page.dart, admin_parent_requests_page.dart. items: admin service admin_parent_linking | AdmPeople?screen=parents, parent, links; SupPlatform?tab=parents | restyle |  |
| AI assistant console (`rag_admin_console`) | super admin, admin | lib/features/rag/. items: admin service svc_app_assistant | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| AI Models (`admin_ai_models`) | super admin | lib/features/admin/models/. items: admin service svc_ai_models | SupSystems?screen=ai | restyle |  |
| Splash screen footer line and logo (`admin_splash_footer`) | super admin | lib/features/admin/ | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| Platform admin home (Overview) (`admin_home`) | super admin, admin | lib/features/admin/admin_overview_page.dart. routes: `/admin_dashboard`. items: admin phone (5): admin_overview_2, admin_students, courses, teachers, More | AdmHome?screen=overview; SupHome?screen=home | restyle | One /me/home call. |
| Export Studio (Excel, Word and PDF) (`export_studio`) | teacher, org admin, org staff, admin, super admin | lib/features/exports/, lib/design/export*/. routes: `/exports`. items: admin service exs_center_title | AdmData?screen=export; SupData?screen=datacenter (export design) | restyle |  |
| Export list designer (list, table and cards) with page preview (`export_layout_designer`) | teacher, org admin, org staff, admin, super admin | lib/features/exports/, lib/design/export*/ | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| Computed columns in exports (no code) (`export_computed_columns`) | teacher, org admin, org staff, admin, super admin | lib/features/exports/, lib/design/export*/ | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| Scheduled exports and expiring links (`export_schedules_links`) | teacher, org admin, org staff, admin, super admin | lib/features/exports/. routes: `/e/<token>`, `/exports/schedules`, `/exports/links` | AdmData?screen=exports; SupData?screen=exports | restyle |  |
| Export log (`export_log`) | org admin, admin, super admin | lib/features/exports/export_log_page.dart. routes: `/exports/log` | AdmData?screen=exports; SupData?screen=exports | restyle |  |
| Course students (`course_students`) | super admin | lib/features/courses/admin/course_students/. items: admin service admin_course_students | AdmStudents?screen=enroll; AdmCourses?screen=detail (students tab) | restyle |  |
| Deleted courses (`course_trash`) | super admin | lib/features/courses/admin/course_trash/. items: admin service admin_course_trash | SupData?screen=trash | restyle |  |
| Help management and exports (`help_admin`) | super admin | lib/features/admin/help/ | AdmContent?screen=help | restyle |  |
| Assistant controls: cache, search training, scanned files (`rag_console_controls`) | super admin | lib/features/rag/ | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| Models per task (`models_per_task`) | super admin | lib/features/admin/models/ | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| Model benchmarks and the best model per role (`model_benchmarks`) | super admin | lib/features/admin/models/ | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| Manage organizations: edit, delete, restore, transfer admin (`admin_org_manage`) | admin, super admin | lib/features/admin/ | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| Edit the privacy policy and terms (`admin_legal_editor`) | super admin, admin | lib/features/admin/admin_legal_page.dart. items: admin service terms_and_conditions | SupSite?screen=legal | restyle |  |
| App update policy (`admin_update_policy`) | admin, super admin | lib/features/admin/admin_update_policy.dart | SupReleases?screen=prompt | restyle |  |
| AI controls (`admin_ai_controls`) | super admin | lib/features/admin/admin_ai_controls.dart | SupPlatform?tab=ai | restyle |  |
| Managing and reviewing store items (`store_manage`) | admin, super admin, teacher | lib/features/store/manage/. items: admin service admin_store | Tea2Money?screen=store; AdmContent?screen=store; SupFinance?screen=store | restyle |  |
| Module settings per country and organization (`module_settings`) | super admin | lib/features/admin/modules/. items: admin service admin_modules | SupPlatform?screen=modules | restyle |  |
| Verify and review Quran teachers (`quran_teacher_review`) | super admin | lib/features/quran/. items: admin service admin_quran | AdmContent?screen=quran | restyle |  |
| Editing the grammar (nahw) content (`nahw_content`) | super admin | lib/features/nahw/ (admin page). items: admin service admin_nahw | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| Self-learning content and settings (`self_learning_content`) | super admin | lib/features/self_learning/admin/. items: admin service admin_self_learning | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| Classic games and badges editor (`games_editor`) | super admin | lib/features/games/admin/. items: admin service admin_games | AdmContent?screen=games | restyle |  |
| Games hub: templates and subjects (`admin_games_hub`) | super admin | lib/features/games/admin/v4/. items: admin service admin_games_hub | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| Games question bank and import (`admin_games_bank`) | super admin | lib/features/games/admin/v4/ | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| Religious review of game questions (`admin_games_review`) | super admin | lib/features/games/admin/v4/ | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| Game levels (`admin_games_levels`) | super admin | lib/features/games/admin/v4/ | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| Games analytics (`admin_games_analytics`) | super admin | lib/features/games/admin/v4/ | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| Game break and parent summary settings (`admin_games_breaks`) | super admin | lib/features/games/admin/v4/ | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| Player outfits (`admin_games_outfits`) | super admin | lib/features/games/admin/v4/ | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| Ready-made game questions (`admin_games_seed`) | super admin | lib/features/games/admin/v4/ | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| Quran game reciters (`admin_games_reciters`) | super admin | lib/features/games/admin/v4/ | not drawn | keep + restyle | Every admin tool that exists today stays, in the services hub. |
| Managing rewards, champions and coupons (`admin_rewards`) | super admin, admin | lib/features/admin/rewards/. items: admin service admin_rewards | SupPricing?screen=rewards | restyle | Two pages today, one page with tabs in the design. |

## Organizations (out of the design scope: keep, tokens only)

| Feature / screen | Roles | Today (file, route) | Design screen(s) | Decision | Notes |
|---|---|---|---|---|---|
| Join an educational organization (`org_join`) | student, teacher, org member | lib/features/org/. routes: `/j/<code> (link.org_join)` | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Switch between your personal account and organizations (`org_switch_context`) | student, teacher, org member, org staff, org admin | lib/features/org/. routes: `/my-organizations (org.memberships)` | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Register a new institution (`org_register_institution`) | org admin | lib/features/org/. routes: `/start/institution` | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Organization dashboard: what needs you, departments and people (`org_dashboard_people`) | org admin, org staff, org member, teacher | lib/features/org/. routes: `/org/<orgId> (org.member)`, `/org_member`, `/org_dashboard`. items: org: home; org: people; org people > members. push modules: org_work, org_department, org_institution_health, org_council | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Organization insights (`org_insights`) | org admin, org staff | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Quick search in the organization (`org_search`) | org admin, org staff, org member, teacher | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Set up joining methods and codes (`org_joining_settings`) | org admin | lib/features/org/. items: org people > join_requests | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Departments, roles and privileges (`org_departments_roles`) | org admin | lib/features/org/. items: org people > departments | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Courses and academic structure (`org_courses_academics`) | org admin, org staff | lib/features/org/. items: org: academics; org academics > courses; org academics > structure | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Set up and generate the timetable (`org_timetable_generate`) | org admin, org staff | lib/features/org/. items: org: timetable. push modules: org_timetable | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| The relaxation ladder: a complete, conflict-free timetable (`org_timetable_ladder`) | org admin, org staff | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Fix clashes, adjust and publish the timetable (`org_timetable_fix_publish`) | org admin, org staff | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| One-tap timetable and automatic fixing (`org_timetable_autopilot`) | org admin, org staff | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Midterm and final exam timetable (`org_exam_timetable`) | org admin, org staff | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Forms, requests and regulations (`org_forms_regulations`) | org admin, org staff, org member | lib/features/org/. items: org: services (phones fold it into More); org services > forms | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Complaints and requests reports (`org_reports`) | org admin, org staff | lib/features/org/. push modules: org_reports | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Organization settings: time, features and data sharing (`org_settings_sharing`) | org admin | lib/features/org/. items: org: settings / More | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Course registration (credit hours) (`registrar_course_registration`) | org member | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Academic record and GPA (`registrar_academic_record`) | org member | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Grade entry and timetable consents (`registrar_grade_entry`) | org member, org staff | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Registrar for staff: decisions and rules (`registrar_staff`) | org admin, org staff | lib/features/org/. items: org academics > registrar | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Exam risk and exam feedback (`org_exam_risk_feedback`) | org admin | lib/features/org/. items: org services > exam_risk; org services > exam_feedback | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Entities: service departments, scientific departments, councils and offices (`org_gov_entities`) | org admin | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| The institution's study system: traditional or credit hours (`org_study_system`) | org admin | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Department catalog: academic and service departments with their request types (`org_dept_catalog`) | org admin | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Approval chain: manager → another entity → council, reasoned rejection and resubmit (`org_gov_chain`) | org admin, org staff, org member, student, teacher | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| The unified item list with one saved filter (`org_gov_items`) | org admin, org staff | lib/features/org/. items: org services > governance subs | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Routing, forwarding, escalation and the first decision (`org_gov_routing`) | org admin, org staff | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Delegating the decision authority (scoped or global, with dates) (`org_gov_delegation`) | org admin, org staff | lib/features/org/. push modules: org_delegation(s), org_form_assignment, org_assignments | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Forwarding an approved request: to a higher council, an outside party or a person with a required action (`org_gov_forward`) | org admin, org staff, teacher, org member | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Requests from outside the institution go to the council automatically (`org_gov_external`) | org admin, org staff | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Monthly council sessions and voting on agenda items (`org_gov_councils`) | org admin, org staff, teacher | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| The Export Hub: designed PDF, Word and Excel for any list (`org_gov_export_hub`) | org admin, org staff | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Your child's organization: timetable, announcements, grades (`parent_org_view`) | parent | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Invite people to the organization (`org_invitations`) | org admin, org staff | lib/features/org/. routes: `/i/<token> (link.org_invitation)`. push modules: org_invitation(s) | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Switch on academic advising (`org_academic_advising`) | org admin | lib/features/org/. items: org services > advising subs | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Advising settings and distributing students to advisors (`org_advising_assignment`) | org admin, org staff | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| My academic advisor profile and student handovers (`org_advising_my_profile_handovers`) | teacher, org staff | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| The academic advisor's workspace and the student 360 (`org_advising_workspace`) | org admin, org staff, teacher | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Student alerts and advising notes (`org_advising_flags_notes`) | org admin, org staff, teacher | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Academic advising appointments and office hours (`org_advising_appointments`) | org admin, org staff, teacher, org member | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Academic advising messages and complaints (`org_advising_messages`) | org admin, org staff, teacher, org member | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Early warning and graduation delay risk (`org_advising_early_warning`) | org admin, org staff, teacher | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Support requests, department and faculty councils, and referrals (`org_advising_requests`) | org admin, org staff, teacher, student | lib/features/org/. push modules: org_adv_request, org_adv_plan, advising, org_adv_appointment, org_adv_thread, org_adv_survey | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Advising analytics, compliance report and data check (`org_advising_analytics`) | org admin, org staff | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Group messages to students with read tracking (`org_advising_outreach`) | org admin, org staff, teacher, student | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Individual support plans and accommodations (`org_advising_plans`) | org admin, org staff, teacher, student | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Membership fees in the organization (view only) (`org_billing_view`) | org admin | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Organization setup checklist (`org_setup_checklist`) | org admin | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Councils: secretary, weights, reminders, results and decision numbers (`org_gov_council_s2`) | org admin, org staff | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Automatic routing, SLA escalation, decision templates and official minutes (`org_gov_routing_sla_s3`) | org admin, org staff | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Faculty overview: requests and councils across every department (`org_gov_faculty_overview_s5`) | org admin, org staff | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Institution setup wizard: from the study system to launch (`org_institution_wizard`) | org admin | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Institution health: what needs fixing now (`org_institution_health`) | org admin | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Choose the councils: faculty council, department councils, both or none (`org_councils_setup`) | org admin | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Archive or delete a department safely (`org_archive_department`) | org admin | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| My journey: what to do now and next (`org_my_journey`) | student, org member | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Needs my attention: requests, votes and overdue items on one page (`org_needs_my_attention`) | org staff, org admin | lib/features/org/. push modules: action_inbox | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Teacher organization workspace (`org_teacher_workspace`) | teacher, org staff | lib/features/org/. items: org workspace (ws_shell.dart): overview; org workspace: management; org workspace: membership; org workspace: pinned; org workspace: alerts; org workspace: profile | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| The Organization tab for organization admins (`org_admin_organization_tab`) | org admin | lib/features/org/. items: org workspace: organization | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Admissions & appointments: reviewing files (`org_onboarding_review`) | org admin, org member | lib/features/org/. routes: `/org/<orgId>/onboarding/<caseId>`. items: org people > onboarding. push modules: org_onboarding, onboard_intake | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Add one person wizard (`org_onboarding_add_one`) | org admin, org member | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Excel import of member files (`org_onboarding_import`) | org admin | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Invite to complete (`org_onboarding_invite`) | org admin, org member | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Intake link (`org_onboarding_intake`) | org admin | lib/features/org/. routes: `/onboard/<code> (link.onboard)` | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Member types editor (`org_onboarding_types`) | org admin | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| My application (applicant) (`me_onboarding`) | student, teacher, org member | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Students: the student list (`org_students_list`) | org admin, org member | lib/features/org/. items: org people > students | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Students: the unified student file (`org_student_file`) | org admin, org member | lib/features/org/. push modules: org_student | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Students: change a student's status (`org_student_status`) | org admin, org member | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| My study status (`student_my_status`) | student | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Students: missing data and reminders (`org_student_missing_data`) | org admin, org member | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Students: ask for data or a meeting (`org_student_ask`) | org admin, org member | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Students: the requests inbox (`org_student_requests`) | org admin, org member | lib/features/org/. items: org people > student requests | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Students: study rules (`org_student_rules`) | org admin | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Requests from my organization (`student_my_asks`) | student | lib/features/org/. push modules: student_ask | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| My requests: suspend, postpone, withdraw (`student_my_requests`) | student | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |
| Students: transfer credit (`org_student_transfer_credits`) | org admin, org member | lib/features/org/ | not drawn | keep + restyle | Org module: tokens and colours from the shared kit only, no layout rebuild. |

## Existing features with no guide entry

| Feature / screen | Roles | Today (file, route) | Design screen(s) | Decision | Notes |
|---|---|---|---|---|---|
| Role shells and tab URLs (sidebar on web, bottom nav on phone) (`x_shells`) | everyone | lib/design/app_shell.dart, app_shell_nav.dart. routes: `/<home>/<tab> e.g. /dashboard/my-courses`. push modules: profile, my_courses | every role file (k-shell, k-side, k-bnav) | restyle | Phase 1. DashboardItem, LazyTabStack, ShellBadge and pins stay. |
| Profile / My account page (`x_profile_page`) | everyone | lib/features/profile/profile_screen.dart. routes: `/profile`. items: student: my_profile; teacher: my_profile | Stu2Profile?screen=profile; Tea2Account?screen=account; AdmHome?screen=account; SupAccount?screen=account | restyle | AppSettingsPage rows keep their kill switches (profile.*). |
| Parent More page (`x_parent_more`) | parent | lib/features/parent/parent_dashboard_screen.dart. items: parent: pl_tab_more | Pa2More?screen=more | restyle |  |
| Admin services hub and More (`x_admin_services`) | admin, super admin | lib/features/admin/admin_services_hub.dart. items: admin web (10): the same 4, then admin_group_people, finance, admin_group_learning, support, admin_group_config, admin_my_account | AdmHome?screen=more; SupAccount?screen=more; AdmPeople?screen=hub; AdmContent?screen=hub; AdmSupport?screen=hub | restyle | Every AdminService stays, also the ones the design does not draw. |
| Phone verification: code, WhatsApp link (`x_phone_verify`) | everyone | lib/features/auth/mfa_verify_screen.dart, verify_way.dart, verified_screen.dart. routes: `/otp` | Stu1Auth?screen=verify (mode=link) | restyle | Must work for non-Saudi numbers (RULES 3). |
| About the app, contact, features (`x_about`) | everyone | lib/features/profile/about/ | Stu2Profile?screen=about | restyle |  |
| Entity pages and panels (student, course, teacher, category; D-290) (`x_entity_view`) | teacher, admin, super admin | lib/design/master_detail/. routes: `/view/<kind>/<id> (entity.view)` | AdmStudents?screen=detail; AdmTeachers?screen=detail; AdmCourses?screen=detail; Tea1Courses?screen=panel | restyle |  |
| Not found page (`x_not_found`) | everyone | lib/main.dart. routes: `default`. push modules: default | not drawn | keep + restyle |  |
| Ads: home slider, teacher-ad approval and settings (`x_admin_ads`) | super admin | lib/features/ads/ads_pages.dart. items: admin service svc_ads | SupAds?screen=ads, editor | restyle |  |
| Fees: rates, gateway fee, policy, VAT (`x_admin_fees`) | super admin | lib/features/admin/admin_fees_page.dart, admin_fee_rates.dart, admin_money_p8.dart. items: admin service admin_fees | SupPricing?screen=fees | restyle |  |
| Education levels: countries, stages, grades, subjects, areas, currency and tax (`x_admin_edu`) | super admin | lib/features/admin/edu/. items: admin service admin_edu_levels | SupPlatform?screen=levels | restyle | Seed the Saudi curriculum and the full country list (WP5). |
| Grading feedback store (`x_admin_feedback`) | super admin | lib/features/admin/admin_feedback_settings.dart. items: admin service admin_feedback_settings | SupSystems?screen=exams | keep + restyle |  |
| Student review and read-flag limits (`x_admin_flags`) | super admin | lib/features/admin/admin_flags_settings_page.dart. items: admin service admin_flags_title | SupSystems?screen=exams (limits tab) | keep + restyle |  |
| Student question review: saved and got wrong (`x_student_review`) | student | lib/features/analytics/student/flags/student_flags_screen.dart | Stu2Exams?screen=review (tab=flag, wrong, empty) | restyle | Exists per course (review bank and read flags). The design shows it across courses inside Exams. |

## New in the design

| Feature / screen | Roles | Today (file, route) | Design screen(s) | Decision | Notes |
|---|---|---|---|---|---|
| Subject booking flow: remote or in person, group or فردي, slots, propose times, review and pay, done (`n_booking`) | student, parent, guest | none (closest: lib/features/teachers/teacher_discovery.dart PackagePage, lib/features/payments/enrollment/) | BookFlow (BookM1..BookM6, BookW1..BookW6) | new | RULES 1.1-1.4 wording. Needs WP6 (groups 5-10, gender, 50 minutes, individual bookings, UTC) and WP12 (centres). Kill switch and guide entry. |
| Subject page with panels: lesson, book, live, chat, bot, دفتر, schedule (`n_subject_page`) | student | lib/features/courses/course_space/ (CourseSpace) | SubjectProfile (SubjM*, SubjW*) | new | A new layout of the one course page for students. "اضغط على الكتاب لمعرفة التفاصيل" (RULES 1.5). |
| دفتر المادة: typed and pen notes (`n_notebook`) | student | none (reuse lib/features/live/room/whiteboard/, lib/design/app_canvas.dart) | SubjectProfile?panel=notes (nmode=pen, type) | new | RULES 1.6: "دفتر", never "كشكول". Needs WP10. |
| Child signs in with the parent's code (`n_kid_code`) | student | none | Stu1Auth?screen=kidcode (state=found, pass) | new | BACKEND 1, WP7. Rate limit and lock. |
| Parent creates the child's account and shares the code by WhatsApp (`n_parent_creates_child`) | parent | none (other direction: lib/features/parent/student_link_code_screen.dart) | Pa2Gate?screen=contact, done&kid=new | new | BACKEND 1, WP7. |
| Parent books for a child (`n_parent_book`) | parent | none | Pa2Pay?screen=book | new | Enters BookFlow with the child chosen. |
| Parent payments and invoices (`n_parent_payments`) | parent | none | Pa2Pay?screen=payments, invoice | new | Needs a parent-scoped payments endpoint (not in BACKEND_STATUS: add a work package). |
| Parent: the child's course page and the rating explainer (`n_parent_course`) | parent | lib/features/parent/parent_child_marks.dart (marks only) | Pa2Kids?screen=course; Pa2Reports?screen=how | new |  |
| Security and devices page with sign-out per device (`n_student_security`) | student | pieces: change_password_widget.dart, passcode/, biometric.dart | Stu2Profile?screen=security | new | A device or session list for the student needs an endpoint. |
| Certificate design wizard before the studio (`n_cert_wizard`) | teacher | lib/features/certificates/studio/cert_template_gallery.dart | Tea2Certs?screen=wizard | new |  |
| Requests and approvals inbox (one page) (`n_approvals_inbox`) | admin | none (queues: accounts, transfers, devices, certificates) | AdmApprovals?screen=inbox, certs | new | Counts from /me/attention. |
| Courses waiting for publish approval (`n_publish_queue`) | admin | none | AdmApprovals?screen=courses | new | Changes how a teacher publishes: owner to confirm (backend, not in BACKEND_STATUS). |
| Audit log (`n_audit_log`) | admin | none | AdmSupport?screen=audit | new | Needs an endpoint. |
| Active sessions list with revoke (`n_sessions_revoke`) | admin | lib/features/admin/admin_devices_page.dart (devices only) | AdmSupport?screen=sessions | new |  |
| Roles and permissions editor (`n_roles`) | super admin | none | SupAdmins?screen=roles (sheet=roleed) | new | Backend work, not in BACKEND_STATUS. Owner to confirm the scope. |
| Platform analytics: growth, money, usage (`n_super_analytics`) | super admin | lib/features/admin/admin_overview_page.dart (parts) | SupHome?screen=analytics (3 tabs) | new |  |
| Emergency stop tab with confirm (`n_emergency_stop`) | super admin | lib/features/admin/admin_features_page.dart (plain list) | SupPlatform?tab=kill | new |  |
| Landing: students page (`n_landing_student`) | public | landing/src/components/Landing.astro | LandingStudentM, LandingStudentW | replace | Today one audience-neutral page. Keep the course finder and testimonials data. |
| Landing: parents page with the sign-up funnel (`n_landing_parent`) | public | none | LandingM, LandingW | new | LandingW is one component with the three personas (student, parent, teacher) and the sign-up steps. |
| Landing: teachers page and the demand card (`n_landing_teacher`) | public | none | LandingTeacherM, LandingTeacherW, LandingW (أنا معلم) | new | Demand card needs WP9; remove the card if the endpoint is not ready. |
| Nicknames and stickers for games (`n_nicknames`) | student | none | Stu2Games (board, champions, wardrobe) | new | WP4, WP11. |
| International sign-up and profile: country of residence, any-country phone, time zone, methods and currency by country (`n_international`) | everyone | parts: lib/design/edu_pickers.dart, lib/core/app_time.dart | Stu1Auth?screen=join; Pa2Gate?screen=grade; BookFlow step 4 | new | RULES 3, phase 8, WP5 and WP8. |

## Owner decisions (conflict with RULES.md, cannot be kept as they are)

| Feature / screen | Roles | Today (file, route) | Design screen(s) | Decision | Notes |
|---|---|---|---|---|---|
| Games per-class board (`o_class_board`) | student | lib/features/games/learner/challenges.dart (GET /games/class-board) | not drawn | owner | RULES 1.9 and BACKEND 3: boards are never per class, so this cannot be kept. Ask the owner before removing it. |

## Rows that change because of RULES.md

| Row | Decision | Rule |
|---|---|---|
| Edit your account details (`update_account`) | replace | RULES 2: a student's avatar is an initial or an illustration, never a photo. Teachers and parents keep the photo and the cropper. |
| Join a live session (`live_join`) | replace | RULES 1.7: no participant count; shows "الحصة شغّالة" and the teacher only. Server: WP1. |
| Live room tools: chat, raise hand and reactions (`live_room_tools`) | replace | RULES 1.7: a student sees "أنت والمعلم" only. Chat, hands and reactions reach the teacher only. The teacher keeps every tool. Server: WP1. |
| Quick meeting (Meet now) (`live_quick_meeting`) | replace | O-2: kept. A student invites by username or phone only, the app never suggests classmates, guests do not see each other. Needs WP11. |
| Enter the ID your teacher needs for an exam (`exam_identifier_request`) | replace | O-4 and RULES 2: a national ID or iqama is asked only through the parent. A school seat or student number may stay. Owner to confirm what "identifier" may be. |
| Create a new course (`course_create`) | replace | One 2012-line form becomes a 7-step wizard. Keep the provider and fields. A personal course never sends next_course_ids. |
| Answer meeting invitations (`meetings_respond`) | replace | RULES 1.7: a student invitee must not see the other invitees (leak 9). Staff keep the list. |
| Check in without internet through a classmate (`attendance_offline_relay`) | replace | O-6 and RULES 1.7: the mechanism stays, the student never sees "عبر زميل" or named witnesses (leak 10). |
| Messages (`chat_messages`) | replace | RULES 1.7: a student may message only his own teachers and support. No "message anyone", no suggested people, no student to student links (leak 4). Teachers, parents and staff keep today's chat. |
| Course group (`chat_course_groups`) | replace | O-5 and RULES 1.7: the course group chat becomes the teacher's announcements thread; the members list is hidden from students. Needs WP3. |
| Friend challenges and the class board (`games_challenges`) | replace | Challenge by code stays, with nicknames (O-3). The per-class board is its own row (owner). |
| Games leaderboard (`games_leaderboard`) | replace | RULES 1.9 and O-3: nicknames, platform or grade wide. Needs WP4. |
| Daily and weekly games champions (`games_champions`) | replace | O-3: nicknames only. Needs WP4. |
| Landing: students page (`n_landing_student`) | replace | Today one audience-neutral page. Keep the course finder and testimonials data. |
| Games per-class board (`o_class_board`) | owner | RULES 1.9 and BACKEND 3: boards are never per class, so this cannot be kept. Ask the owner before removing it. |

Owner decisions O-1 to O-6 are taken (`DESIGN_SYSTEM.md`, last section), so their rows are `replace`, not `owner`. Still for the owner: the per-class games board (`o_class_board`); what an exam "identifier" may be (`exam_identifier_request`); whether the privacy contract also applies inside organizations (org classes, org messages and the org people directory are kept as they are); 2-step verification for students; the daily lessons inside the Quran area; the publish-approval queue and the roles editor (new backend work the design implies).


## Coverage check

Computed by the generator from the inventories; "not covered" must be zero in every line.

| Source | Count | Covered by a row | Not covered |
|---|---|---|---|
| Guide features (`app_features_guide.json`) | 389 | 389 | 0 |
| Routes (`_router` plain switch, `AppRoutes` registry and link parsers, `front.md` section 1) | 60 | 60 | 0 |
| `AppNavigator` push modules (`front.md` section 3) | 33 | 33 | 0 |
| Dashboard items: role shells 36, org sub-pages 20, admin services 53 | 109 | 109 | 0 |
| Kill-switch keys in the catalog | 486 | 262 named by a guide feature + 224 by family (below) | 0 |
| Design files of `SCREENS.md` (BookM*/BookW* = BookFlow, SubjM*/SubjW* = SubjectProfile) | 66 | 66 | 0 |
| Design screens (`SCREEN_MAP.md`, one row each) | 570 | 570 | 0 |

Rows: 426 (guide features 389, existing with no guide entry 14, new-in-the-design section 22, owner section 1).

| Decision | Rows |
|---|---|
| restyle | 181 |
| keep + restyle | 209 |
| new | 21 |
| replace | 14 |
| owner | 1 |

The front inventory section 7 (926 page-like classes) is not listed class by class: each class belongs to the feature folder named in the "Today" cell of its row. A pull request that deletes a class checks the owning row first.

### Kill-switch key families that no guide feature names

224 catalog keys are sub-keys (a button, a tab, a card). Each family stays with the row below; the redesigned widget keeps the same `featureKey`.

| Key family | Keys | Row |
|---|---|---|
| `about` | 7 | `x_about` |
| `additional_register` | 6 | `teacher_onboarding` |
| `admin` | 2 | `admin_home` |
| `analytics` | 7 | `student_analytics` |
| `analytics_hub` | 6 | `teacher_analytics_hub` |
| `attendance` | 1 | `attendance_check_in` |
| `categories` | 5 | `browse_categories` |
| `certificates` | 2 | `my_certificates` |
| `complaint_detail` | 3 | `complaints_handle` |
| `complaints` | 3 | `help_center_complaints` |
| `course` | 3 | `course_details` |
| `course_card` | 14 | `course_details` |
| `course_details` | 4 | `course_details` |
| `course_form` | 13 | `course_create` |
| `course_hero` | 9 | `course_details` |
| `course_row` | 1 | `course_details` |
| `course_stats` | 6 | `course_details` |
| `course_tabs` | 2 | `course_lessons` |
| `courses_list` | 3 | `browse_categories` |
| `data_lab` | 2 | `data_lab` |
| `device_requests` | 3 | `device_switch_approve` |
| `exam` | 1 | `exam_take` |
| `exam_frozen` | 2 | `exam_result_appeal` |
| `favorites` | 2 | `favorites` |
| `games` | 1 | `games` |
| `google_auth` | 1 | `sign_in` |
| `guest_mode` | 1 | `guest_browsing` |
| `instructor` | 9 | `instructor_profile` |
| `live_room` | 8 | `live_room_tools` |
| `my_courses` | 4 | `my_courses` |
| `new_complaint` | 4 | `help_center_complaints` |
| `notifications` | 3 | `notifications` |
| `org` | 1 | `org_dashboard_people` |
| `payment_callback` | 1 | `pay_by_card` |
| `prejoin` | 2 | `live_join` |
| `profile` | 10 | `x_profile_page` |
| `register` | 6 | `register_account` |
| `rewards` | 1 | `rewards_coupons` |
| `roadmap` | 5 | `learning_roadmap` |
| `roadmap_enroll` | 3 | `learning_roadmap` |
| `session_form` | 3 | `lessons_add` |
| `sessions` | 2 | `course_lessons` |
| `student_analytics` | 1 | `student_analytics` |
| `student_home` | 6 | `student_home` |
| `student_tab_my_profile` | 1 | `x_profile_page` |
| `subscription` | 5 | `platform_subscription` |
| `teacher_attendance` | 4 | `attendance_record_teacher` |
| `teacher_courses` | 5 | `course_manage_publish` |
| `teacher_home_add_course` | 1 | `teacher_home` |
| `teacher_home_courses_header` | 1 | `teacher_home` |
| `teacher_home_courses_row` | 1 | `teacher_home` |
| `teacher_home_schedule` | 1 | `teacher_home` |
| `teacher_home_stats` | 1 | `teacher_home` |
| `teacher_home_topbar` | 1 | `teacher_home` |
| `teacher_payouts` | 4 | `teacher_payouts` |
| `teacher_schedules` | 2 | `teacher_weekly_schedule` |
| `teacher_sessions` | 8 | `lessons_add` |
| `teacher_tab_my_profile` | 1 | `x_profile_page` |
| `terms` | 4 | `privacy_terms_pages` |
| `transfer_requests` | 4 | `transfer_requests_review` |
| `upload_queue` | 1 | `materials_upload` |

### Progress per phase

Each phase ends by marking its rows here (`PARITY.md`, "While building"). Nothing is marked yet: phase 0 changes no UI.

