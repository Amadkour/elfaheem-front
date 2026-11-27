# Backend feature inventory (read-only)

Generated from `D:\platform\nextbrain\_wt\rd-back` by a script, not typed by hand.
Sources: `data/app_features_guide.json` (guide, version 1) and `features/platform/feature_catalog.py` (`FEATURE_CATALOG`).

## Counts

- Guide features: 389 (groups: 12)
- Guide features with no kill-switch key: 70
- Distinct kill-switch keys named by the guide: 262 (pairs: 469)
- Catalog keys (kill-switch keys in the catalog): 486
- Catalog keys in no guide feature: 224
- Guide kill-switch keys missing from the catalog: 0

## 1. Guide features

Columns: id/key | group | roles | Arabic name | English name | place (where in the app, English) | kill-switch keys (`switch_keys`).

| id/key | group | roles | Arabic name | English name | place | kill-switch keys |
|---|---|---|---|---|---|---|
| sign_in | account | everyone | تسجيل الدخول إلى التطبيق | Sign in to the app | The Login screen when you open the app |  |
| register_account | account | student, teacher, parent | إنشاء حساب جديد | Create a new account | Login screen › Register | register |
| study_profile | account | student | بيانات الدراسة: المرحلة والصف والمدرسة | Study details: stage, grade and school | Register › Study step, and Profile › Account › Study details | profile.study |
| study_profile_settings | administration | super_admin | إعدادات بيانات الدراسة للطلاب | Student study details settings | Admin dashboard › Settings › Study details | profile.study |
| teacher_onboarding | account | teacher | إكمال ملف المعلم ورفع المستندات المطلوبة | Complete your teacher profile and upload the required documents | The Complete profile screen opens by itself after a teacher signs up | additional_register, additional_register.documents |
| forgot_password | account | everyone | استعادة كلمة المرور المنسية | Reset a forgotten password | Login screen › Forget Your password |  |
| guest_browsing | account | student | تصفح التطبيق كزائر | Browse the app as a guest | Login screen › Continue as guest |  |
| guest_search_onboarding | discover | student | ابحث عن كورس قبل إنشاء حساب | Find a course before creating an account | First app start › Onboarding › Find a course — or the website's home page |  |
| two_step_verification | account | admin, super_admin, org_admin, org_staff | التحقق بخطوتين | Two-step verification | Profile › Security › Two-step verification; in an organization: Settings › Security; platform admins: Admin dashboard › Support & security | profile.mfa |
| biometric_sign_in | account | everyone | الدخول بالبصمة أو Face ID | Fingerprint / Face ID sign-in | Sign-in screen › fingerprint button; Profile › Security › Fingerprint sign-in | auth.biometric |
| display_reading | account | everyone | العرض والقراءة | Display & reading | Profile › Settings › Display & reading (also under More for parents and admins, and in organization settings) | profile.display |
| dashboard_pins_colors | discover | everyone | تثبيت الصفحات وألوان التبويبات | Pin pages and colour your tabs | Any page inside your dashboard › the pin button at its top; long-press any tab › Customize tabs |  |
| editorial_headings | account | everyone | العناوين التحريرية | Editorial headings | Profile › Settings › Display & reading › Headings (also under More for parents and admins, and in organization settings) |  |
| motion | account | everyone | الحركة والمؤثرات | Motion and effects | Profile › Settings › Display & reading › Reduce motion; for the Super Admin: Feature switches › Profile › "Animations and 3D effects (all accounts)" | app.animations |
| username | account | everyone | اسم المستخدم (@) | Username (@) | Create account screen; Profile › Account › Update Account; Sign-in screen | auth.username |
| update_account | account | everyone | تعديل بيانات الحساب | Edit your account details | Profile › Account › Update Account | profile.update_account |
| change_password | account | everyone | تغيير كلمة المرور | Change your password | Profile › Account › Change Password | profile.change_password |
| language_and_dark_mode | account | everyone | تغيير اللغة والوضع الليلي | Change the language and dark mode | Profile › Settings › Change Language / Dark Mode | profile.change_language, profile.dark_mode |
| device_binding | account | student | ربط الحساب بجهاز وطلب تغيير الجهاز | Device binding and device switch requests | The "Device not allowed" dialog appears when you open a course on a new device | profile.device_requests |
| download_my_data | account | everyone | تنزيل نسخة من بياناتي | Download a copy of my data | Profile › Help › Download my data | profile.data_export |
| logout_delete_account | account | everyone | تسجيل الخروج وحذف الحساب | Log out and delete your account | Profile › Exit › Logout / Delete Account | profile.logout, profile.delete_account |
| parent_link_code | account | student | كود ربط ولي الأمر | Parent link code | Profile › Account › Parent link code | profile.parent_link |
| connected_drives | account | everyone | الحسابات السحابية المرتبطة | Connected drives | Settings › Connected drives | profile.cloud_drives |
| records | account | everyone | التسجيلات | Records | My profile › Records | profile.records |
| records_share | account | everyone | مشاركة التسجيلات | Sharing recordings | My profile › Records › play a recording › Share | records.share, profile.records |
| student_home | discover | student | الصفحة الرئيسية للطالب | Student home screen | The Home tab | student_home, student_tab_home |
| browse_categories | discover | student | تصفح الأقسام والبحث عن الكورسات | Browse categories and search for courses | Home › search bar or the Categories shortcut | categories, student_home.search |
| course_details | discover | student | صفحة تفاصيل الكورس | Course details page | Tap any course from Home, Categories or My Courses | course_details |
| instructor_profile | discover | student | ملف المعلم | Teacher profile | Course page › the teacher's name, or the Best Teacher row on Home | course_instructor |
| favorites | discover | student | المفضلة | Favorites | Profile › Account › Favorite | profile.my_favorite, favorites, course_card.favorite |
| learning_roadmap | discover | student | خارطة الطريق التعليمية | Learning roadmap | Course page › Path tab | roadmap, roadmap.path, course.enroll_roadmap |
| course_roadmap_manage | teaching | teacher | مسار الكورس (للمعلم) | Course path (teacher) | Course studio › Path tab › Edit | roadmap, roadmap.path |
| recommended_for_you | discover | student | مقترح لك | Recommended for you | Profile › Recommended for you | roadmap, roadmap.recommendations |
| home_journey | discover | student | واصل رحلتك | Continue your journey | Home › Continue your journey card | roadmap, roadmap.journey |
| next_step_notice | discover | student | خطوتك التالية جاهزة | Your next step is ready | Notifications | roadmap.next_notice |
| private_course_code | discover | student | فتح كورس خاص بكود | Open a private course with a code | The Private course sheet appears when you open the course link |  |
| keyboard_shortcuts | discover | everyone | لوحة المفاتيح على الويب: Enter والاختصارات | Keyboard on the web: Enter and shortcuts | Any screen with text fields on the web or desktop |  |
| course_enroll | learning | student | الاشتراك في كورس | Enroll in a course | Course page › the enroll button | enrollment |
| my_courses | learning | student | كورساتي | My courses | The My Courses tab | student_tab_my_courses, my_courses |
| course_lessons | learning | student | دروس الكورس والمرفقات | Course lessons and materials | Course page › Sessions tab | course_tabs.lessons, sessions.exam_banner |
| video_player | learning | student | مشغّل فيديو المحاضرات | Lecture video player | Course page › Sessions › tap a video |  |
| offline_downloads | learning | student | تحميل المحاضرات للمشاهدة بدون إنترنت | Download lectures to watch offline | Download button in the video player; downloads are in Profile › Downloads | profile.downloads |
| my_certificates | learning | student | شهاداتي وطلب الشهادة | My certificates and requesting one | Profile › Account › My certificates | certificates |
| student_analytics | learning | student | تحليلات أدائي | My performance analytics | The Analysis tab | student_tab_analysis, analytics |
| org_course_profile | learning | org_member, org_staff | ملف المقرر في المؤسسة | Course profile in an organization | My organization › Courses › the course |  |
| parent_children | learning | parent | متابعة الأبناء | Follow your children | Parent dashboard › Children tab |  |
| parent_child_consent | learning | parent | موافقة ولي الأمر على متابعة ابن قاصر | Parent consent for a child under the legal age | Parent dashboard › Children tab › the child's card |  |
| parent_link_child | learning | parent | ربط ولي الأمر بحساب الابن | Link a parent account to a child | Parent dashboard › Link tab | profile.parent_link |
| parent_reports | learning | parent | تقارير الأبناء | Children's reports | Parent dashboard › Reports tab |  |
| live_join | live | student | الانضمام إلى حصة مباشرة | Join a live session | Course page › Live tab, or the Live now card on Home | live_sessions, prejoin |
| live_room_tools | live | student, teacher | أدوات غرفة البث: الدردشة ورفع اليد والتفاعلات | Live room tools: chat, raise hand and reactions | The control bar at the bottom of the live room | live_sessions, live_room.quiz |
| live_start_teacher | live | teacher | بدء حصة مباشرة وإدارتها | Start and run a live session | Session page › Live Now, or Home › Today's sessions › Start now | live_sessions |
| live_screen_share | live | teacher | مشاركة الشاشة في الحصة المباشرة | Share your screen in a live session | Live room › control bar › Share | screen_share |
| live_recording | live | teacher | تسجيل الحصة المباشرة | Record a live session | Lesson form › Record this session; during the stream: control bar › Pause | session_recording, live_room.pause_recording |
| live_guest_link | live | teacher | رابط الضيوف للحصة المباشرة | Guest link for a live session | Session page › Guest link | live.guest_link |
| live_share_link | live | teacher, org_admin, org_staff, student | مشاركة رابط الغرفة المباشرة (حصة أو اجتماع) | Share a live room link (session or meeting) | Live room › Share, or the session / meeting page › Share link | live.share_link |
| live_lobby | live | teacher, org_admin, org_staff, student | غرفة الانتظار: قبول المنضمين قبل الدخول | Lobby: admit people before they enter | Live room › the Lobby button in the control bar (shows the waiting count) | live.lobby |
| live_teacher_controls | live | teacher, org_admin, org_staff, student | تحكم المضيف بالمشاركين داخل الغرفة | Host controls over participants | Live room › the participants list › tap a participant (mute · remove · permissions) · control bar › Mute all / End for all | live.teacher_controls |
| live_room_lock | live | teacher, org_admin, org_staff, student | قفل الغرفة أمام المنضمين الجدد | Lock the room to new joins | Live room › control bar › Lock room | live.room_lock |
| live_companion_device | live | student, teacher, parent, org_admin, org_staff, admin | استخدام الهاتف ككاميرا أو ميكروفون أو سماعة أثناء الجلسة | Use your phone as the camera, microphone or speaker of a live room | Pre-join page, or the room's control bar › Your phone | live.companion |
| live_host_handover | live | teacher, org_admin, org_staff, student | إنهاء الاجتماع أو مغادرته وتسليم إدارته لمشارك آخر | End or leave a meeting, and hand the host controls over | Meeting room › End button | live.host_handover |
| live_annotation | live | teacher, org_admin, org_staff, student | الرسم على الشاشة المشتركة (التعليق التوضيحي) | Annotate a shared screen | Live room › while a screen is shared › control bar › Annotate | live.annotation |
| live_whiteboard | live | teacher, org_admin, org_staff, student | السبورة البيضاء في البث المباشر | Whiteboard in a live room | Live room › Share › Whiteboard | live.whiteboard |
| live_share_requests | live | teacher, org_admin, org_staff, student | مشاركة شاشة واحدة في كل مرة وطلب المشاركة | One screen share at a time, and asking to share | Live room › control bar › Share / Ask to share | live.share_requests |
| live_quick_meeting | live | everyone | اجتماع سريع («اجتمع الآن») | Quick meeting (Meet now) | Calendar › Meet now next to New meeting, or the upcoming meetings card in My schedule | live.quick_meeting, calendar.entry |
| teacher_quick_live | live | teacher | ابدأ بثًا مباشرًا من الرئيسية | Go live from the home | Teacher home › Go live button under the greeting | teacher.quick_live |
| live_direct_guest_link | live | teacher, student, org_staff, org_admin | رابط الضيوف المباشر (دخول بلا انتظار) | Direct guest link (no waiting) | Live room or meeting › waiting button › Quick guest link card | live.share_link, live.lobby, live.guest_link |
| exam_take | exams | student | أداء اختبار في الكورس | Take a course exam | Course page › Exams tab › Course exams | exams |
| exam_result_appeal | exams | student | نتيجة الاختبار وطلب إعادة التصحيح | Exam results and asking for a regrade | Exams tab › the exam › View result | exams, exam_frozen |
| exam_offline_student | exams | student | أداء الاختبار بدون إنترنت | Take an exam without internet | Profile › Downloads › Exams (Offline exams) | exams |
| exam_quick_create | exams | teacher, admin, super_admin | إنشاء اختبار سريع | Create a quick exam | Analysis › the course › Exams › New exam; for admins: Courses › the course › Course exams › New exam | exams, teacher_exams_hub |
| exam_generate_from_documents | exams | teacher | توليد أسئلة الاختبار من مستندات الكورس | Generate exam questions from the course documents | Quick exam › Generate the questions for me from the course documents | exams, exam.auto_create |
| exam_question_bank | exams | teacher | بنك الأسئلة | Question bank | Course Exams page › Course exams › Question bank icon | teacher_exams_hub |
| exam_full_editor | exams | teacher | محرر الاختبار الكامل والمراقبة | Full exam editor and proctoring | Quick exam › Full editor, or Course exams › + New exam | exams, teacher_exams_hub |
| exam_review_marking | exams | teacher | مراجعة التصحيح ونشر النتائج | Review marking and publish results | Tap a published exam › Review marking | teacher_exams_hub |
| exam_paper_scans | exams | teacher | تصحيح الاختبار الورقي من الصور الممسوحة | Mark paper exams from scanned sheets | Review marking › Scanned pages icon | teacher_exams_hub |
| exam_appeals_analytics | exams | teacher | التظلمات وتحليلات الاختبار | Exam appeals and analytics | Review marking › Appeals icon / Analytics icon | teacher_exams_hub |
| exam_printable_paper | exams | teacher, org_staff | ورقة الاختبار القابلة للطباعة | Printable exam paper | The exam › Printable exam paper (from the editor, results, or right after creating an offline exam) | exams |
| exam_paper_designer | exams | teacher, org_staff | تصميم ورقة الاختبار والغلاف | Exam paper and cover designer | The exam › Printable exam paper › Do you have a template? (the cover also in the exam wizard's paper design step and in Print and deliver › Cover page) | exams, exam.paper_designer |
| exam_session_lock | exams | teacher, org_staff | قفل الدروس التالية حتى اجتياز الاختبار | Lock the next lessons until the exam is passed | The course › Exams › New exam › Advanced › Lock the lessons after… (or the lesson's menu › New exam) | exams |
| exam_excel_import | exams | teacher, org_staff | استيراد الأسئلة من Excel وتصدير النتائج | Import questions from Excel and export results | The exam editor › Import from Excel · The exam results › Export results | exams |
| exam_offline_sitting | exams | teacher | توزيع الاختبار وجمعه في القاعة بدون إنترنت | Hand out and collect an exam in the hall without internet | Exam page › Offline sitting | exams |
| exam_paper_setup | exams | teacher, org_staff | إعداد الاختبار الورقي (تحديد الطالب، النوع، الورقة، النماذج) | Set up a paper exam (student ID, type, sheet, models) | The exam editor › Paper exam setup icon, or it opens by itself after you create an Offline quick exam for a course | exams, teacher_exams_hub |
| exam_identifier_request | exams | student | إدخال الرقم الذي يحتاجه معلمك للاختبار | Enter the ID your teacher needs for an exam | A dialog when you open the app, or when you tap the notification | exam.identifiers |
| omr_sheet_types | exams | super_admin | أنواع أوراق التظليل وتعليم المنصة ورقة جديدة | Bubble sheet types and teaching the platform a new sheet | Admin dashboard › App configuration › Bubble sheet types | exam.omr |
| omr_custom_layout | exams | teacher, org_staff | إضافة ورقة تظليل خاصة بك من صورة واحدة | Add your own bubble sheet from one photo | Paper exam setup or New exam › Bubble sheet step › Add your own sheet from one photo | exam.omr |
| omr_print_sheets | exams | teacher, org_staff | طباعة أوراق التظليل | Print bubble sheets | the exam (editor or its results page) › Paper exam card › Print bubble sheets | exam.omr |
| omr_scan_sheets | exams | teacher, org_staff | تصوير أوراق التظليل بالكاميرا أو رفعها | Scan bubble sheets with the camera or upload them | the exam (editor or its results page) › Paper exam card › Scan or upload | exam.omr, exam.auto_correct |
| omr_review_queue | exams | teacher, org_staff | مراجعة الأوراق الممسوحة | Review scanned papers | the exam (editor or its results page) › Paper exam card › Review | exam.omr |
| omr_paper_results | exams | teacher, org_staff | نتائج الاختبار الورقي ونشرها | Paper exam results and publishing | the exam (editor or its results page) › Paper exam card › Results | exam.omr |
| teacher_home | teaching | teacher | الصفحة الرئيسية للمعلم | Teacher home screen | The teacher's Home tab | teacher_home, teacher_tab_home |
| course_create | teaching | teacher | إنشاء كورس جديد | Create a new course | My Courses tab › Add New Course | course_form, teacher_courses.add, course_form.reel |
| course_manage_publish | teaching | teacher | تعديل الكورس ونشره وحذفه | Edit, publish and delete a course | My Courses tab › the course card | teacher_courses, teacher_courses.edit, teacher_courses.publish, teacher_courses.delete |
| teacher_course_page | teaching | teacher | صفحة الكورس للمعلم | Your course page | My Courses tab › tap a course | teacher_courses |
| course_privacy_discount | teaching | teacher | الكورس الخاص والخصم | Private course and discount | Course form › Advanced settings | course.discount_badge |
| lessons_add | teaching | teacher | إضافة الحصص (مباشرة أو مسجّلة) | Add lessons (live or pre-recorded) | My Courses › the course › Sessions › Add Lesson | teacher_sessions, session_form |
| materials_upload | teaching | teacher | رفع المرفقات والفيديوهات للحصة | Upload materials and videos to a lesson | Session page › Add Material |  |
| materials_studio | teaching | teacher, org_staff, org_admin, super_admin | الاستوديو على فيديوهات الحصص | Studio on session videos | My courses › the course › Sessions › a video material › Studio | materials.studio |
| guest_share_links | teaching | teacher, org_staff, org_admin, super_admin, student, parent | روابط الضيوف: فيديو أو اجتماع يفتح مباشرة دون حساب | Guest links: a video or a meeting that opens straight away, no account | Session › a video material › ⋯ › Share with guests · Records › Share › Guest link · Meeting › Share link | materials.guest_link, records.share, live.share_link |
| studio_download | teaching | teacher, org_staff, org_admin, super_admin | تنزيل الفيديو من الاستوديو قبل التعديل وبعده | Download a video from the Studio, before or after editing | Studio › the Download button at the top · the save card › Download · Studio drafts › Download | materials.studio |
| video_captions | teaching | teacher | ترجمة نصية لفيديوهات المحاضرات | Captions for lecture videos | Session page › the video › Captions |  |
| attendance_start_teacher | teaching | teacher | فتح تسجيل الحضور بكود متغير | Open attendance with a rotating code | Session or course page › Attendance › Start attendance |  |
| attendance_record_teacher | teaching | teacher | سجل الحضور وتعديله يدوياً | Attendance record and manual edits | Analysis › the course › Attendance (Record & Edit) | teacher_attendance |
| certificates_manage | teaching | teacher | إدارة شهادات الكورس وإرسالها | Manage and send course certificates | Course page › Certificates › Manage / send; requests in Profile › Certificate requests | certificates |
| certificate_designer | teaching | teacher, org_admin | تصميمات الشهادات | Certificate designs | Profile › My certificate designs; in an organization: Settings › Certificate designs | profile.certificate_designs |
| certificate_studio | teaching | teacher, org_admin | استوديو الشهادات (محرّك التصميم الموحّد) | Certificate studio (the shared design engine) | Profile › My certificate designs › open a design; in an organization: Settings › Certificate designs | profile.certificate_designs, certificates.engine |
| certificate_template_colours | teaching | teacher, org_admin | ألوان خلفية قوالب الشهادات | Background colours of certificate templates | Certificate studio › Templates, then Page in the properties panel | profile.certificate_designs, certificates.engine |
| certificate_preambles | teaching | teacher, org_admin | صيغ جاهزة لنص الشهادة | Ready wordings for the certificate text | Certificate studio › Wordings | profile.certificate_designs, certificates.engine |
| certificate_issue_standalone | teaching | teacher, org_admin, org_staff | إصدار شهادات بدون كورس | Issue certificates without a course | Profile › My certificate designs › Issue certificates on a design; Saved lists and Issued history at the top | certificates.standalone |
| certificate_history_verify | teaching | teacher, org_admin, org_staff | سجل الشهادات الصادرة والتحقق منها | Issued certificates history and verification | Profile › My certificate designs › Issued history; verification page: nextbrain.site/verify/… | certificates.standalone |
| teacher_analytics_hub | teaching | teacher | تحليلات المعلم | Teacher analytics | The Analysis tab | teacher_tab_analysis |
| data_lab | teaching | teacher, student | معمل البيانات | Data Lab | Analysis › Data Lab; students: Analysis › My analytics | data_lab.entry |
| device_switch_approve | teaching | teacher | الموافقة على طلبات تغيير الجهاز | Approve device switch requests | Profile › Account › Device Switch Requests | profile.device_requests, device_requests |
| teacher_ads | teaching | teacher | إعلانات المعلم | Teacher ads | Profile › My ads | profile.my_ads |
| teacher_weekly_schedule | schedule | teacher | جدول المعلم الأسبوعي | Teacher weekly schedule | Schedule tab; appointments from the course page › Add Schedule | teacher_tab_my_schedule, teacher_schedules.add |
| student_schedule | schedule | student | جدول الطالب | Student schedule | The Schedule tab | student_tab_my_schedule, schedule.week_strip, schedule.next_banner |
| calendar_views | schedule | student, teacher, parent, org_member, org_staff, org_admin, admin, super_admin | جدولي: أجندة ويوم وأسبوع وشهر | My schedule: agenda, day, week and month | The My calendar icon at the top of Home (students, teachers, parents and platform admins); or My calendar in Profile › Account (parents: More › Account, platform admins: More › Settings); or the Calendar button of the organization dashboard and space | calendar.entry |
| meetings_create | schedule | teacher, org_member, org_staff, org_admin | إنشاء اجتماع ودعوة الآخرين | Create a meeting and invite people | Calendar › tap a free time or New meeting |  |
| meetings_respond | schedule | teacher, org_member, org_staff, org_admin | الرد على دعوات الاجتماعات | Answer meeting invitations | Calendar or Inbox › the meeting |  |
| meeting_recording_cloud | schedule | teacher, org_member, org_staff, org_admin | تسجيل الاجتماع إلى حسابك السحابي | Record a meeting to your drive | The meeting room › Record button, then the meeting page in the calendar | live.meeting_recording |
| attendance_check_in | schedule | student | تسجيل الحضور بالكود | Check in with the attendance code | Course page › Check in now button | attendance, attendance.action |
| attendance_offline_relay | schedule | student | تسجيل الحضور بدون إنترنت عبر زميل | Check in without internet through a classmate | Profile › Downloads › Attendance tab, or the course attendance button with the Bluetooth icon | attendance |
| org_my_timetable | schedule | org_member | جدولي الدراسي في المؤسسة | My timetable in the organization | My organization › My timetable, or Home › Today › Full timetable |  |
| org_session_changes | schedule | org_member | تغييرات الحصص: أونلاين أو إلغاء أو معلم بديل | Session changes: online, cancelled or substitute | My organization › My timetable or Today › the change card |  |
| org_my_exams | schedule | org_member | امتحاناتي في المؤسسة | My exams in the organization | My organization › My exams |  |
| notifications | communication | everyone | الإشعارات | Notifications | The bell icon at the top of Home; the switch in Profile › Settings › Notifications | notifications, profile.notifications |
| help_center_complaints | communication | everyone | مركز المساعدة: الشكاوى والدعم | Help Center: complaints and support | Profile › Help › Help Center | profile.help_center, complaints, new_complaint |
| complaints_handle | communication | teacher, org_admin, org_staff, admin, super_admin | معالجة الشكاوى الواردة | Handle incoming complaints | Profile › Help Center › To resolve; Admin dashboard › Support & security › Help Center | complaints, complaint_detail |
| unified_inbox | communication | student, teacher, org_member, org_staff | صندوق الوارد الموحّد | Unified inbox | Home › Inbox card, or My organization › Inbox | student_home.inbox |
| course_announcements | communication | teacher, org_staff, org_member | إعلانات المقرر | Course announcements | Course page › Announcements tab › New announcement |  |
| org_announcements | communication | org_admin, org_staff, org_member | أخبار المؤسسة وإعلاناتها | Organization news and announcements | Org dashboard › Services › News; members: My organization › News |  |
| mentions | communication | everyone | الإشارة إلى شخص بكتابة @ | Mention someone by typing @ | Organization announcement editor · new complaint and complaint replies · meeting notes in the calendar | mentions |
| org_complaints_member | communication | org_member, org_staff, org_admin | الشكاوى والاستفسارات داخل المؤسسة | Complaints and questions inside the organization | My organization › Complaint / question; staff: Org dashboard › Services › Complaints |  |
| parent_alerts | communication | parent | تنبيهات ولي الأمر | Parent alerts | Parent dashboard › Alerts tab |  |
| admin_broadcast_message | communication | admin, super_admin | إرسال رسالة جماعية | Broadcast a message | Admin dashboard › People & messages › Send Message |  |
| pay_by_card | payments | student | الدفع بالبطاقة | Pay by card | Course page › Enroll in course › payment method › Card | payments, payments.card, payment_callback |
| pay_by_transfer | payments | student | الدفع بالتحويل البنكي أو إنستاباي | Pay by bank transfer or InstaPay | Course page › Enroll in course › Bank Transfer or InstaPay | payments, payments.transfer |
| platform_subscription | payments | student | اشتراك المنصة | Platform subscription | The Subscription screen appears by itself when needed | subscription.plans |
| points_wallet | payments | everyone | محفظة النقاط وباقة الاجتماعات المباشرة | Points wallet and the live-meeting plan | Settings › Points wallet, or Upgrade in the meeting room when the free time is nearly over | profile.points |
| admin_points | payments | admin, super_admin | إدارة النقاط وطلبات الشحن | Points and top-up requests (admin) | Admin dashboard › Points | admin.points |
| admin_live_settings | administration | super_admin | أداء البث المباشر | Live performance | Admin dashboard › Live performance | admin.live_settings |
| admin_app_releases | administration | super_admin | إصدارات التطبيق | App versions | Admin dashboard › App versions | admin.app_releases |
| admin_landing | administration | super_admin | صفحة الهبوط | Landing page | Admin dashboard › Landing page | admin.landing |
| admin_recommendations | administration | super_admin | التوصيات (لمدير المنصة) | Recommendations (super admin) | Admin dashboard › Services › Recommendations | admin.recommendations |
| admin_username_stats | administration | admin, super_admin | إحصاءات أسماء المستخدمين | Username numbers | Admin dashboard › Support & security › Usernames | admin.username_stats |
| transfer_requests_review | payments | teacher, admin, super_admin | مراجعة طلبات الدفع بالتحويل | Review transfer payment requests | Teacher: Home › Needs you › Enrollment requests; admins: Finance & requests › Enrollment Requests | profile.enrollment_request |
| teacher_payouts | payments | teacher | أرباح المعلم وطلبات السحب | Teacher earnings and withdrawals | Profile › Account › Payout Requests | profile.payout, teacher_payouts.request |
| admin_payouts | payments | admin, super_admin | إدارة سحوبات المعلمين | Manage teacher payouts | Admin dashboard › Finance & requests › Payout Requests | admin.payouts |
| admin_payments_refunds | payments | admin, super_admin | سجل المدفوعات والاسترداد | Payments history and refunds | Admin dashboard › Finance & requests › Payments | profile.historical_payment |
| admin_payment_settings | payments | admin, super_admin | إعدادات طرق الدفع والاشتراكات | Payment methods and subscription settings | Admin dashboard › Finance & requests › Payment methods / Subscriptions | profile.payment |
| org_join | organizations | student, teacher, org_member | الانضمام إلى مؤسسة تعليمية | Join an educational organization | Home › account switcher › Join another organization | student_home.org, teacher_home_org |
| org_switch_context | organizations | student, teacher, org_member, org_staff, org_admin | التبديل بين حسابي الشخصي والمؤسسات | Switch between your personal account and organizations | Home › the account switcher at the top | home.org_tab |
| org_register_institution | organizations | org_admin | تسجيل مؤسسة جديدة | Register a new institution | Login screen › Register an institution | register.organization |
| org_dashboard_people | organizations | org_admin, org_staff, org_member, teacher | لوحة المؤسسة: يحتاج انتباهك والأقسام والأعضاء | Organization dashboard: what needs you, departments and people | Org dashboard › Home and People |  |
| org_insights | organizations | org_admin, org_staff | مؤشرات المؤسسة | Organization insights | Org dashboard › Home › Insights | org.insights |
| org_search | organizations | org_admin, org_staff, org_member, teacher | البحث السريع في المؤسسة | Quick search in the organization | Org dashboard › the search bar on Home (phone), the Search button at the top, or Ctrl+K | org.search |
| org_joining_settings | organizations | org_admin | إعداد طرق الانضمام وأكواده | Set up joining methods and codes | Org dashboard › Settings › Join code / How people join |  |
| org_departments_roles | organizations | org_admin | الإدارات والأقسام والأدوار والصلاحيات | Departments, roles and privileges | Org dashboard › People › Departments; Settings › Roles & privileges |  |
| org_courses_academics | organizations | org_admin, org_staff | المقررات والهيكل الأكاديمي | Courses and academic structure | Org dashboard › Academics › Courses / Academic structure |  |
| org_timetable_generate | organizations | org_admin, org_staff | إعداد الجدول الدراسي وتوليده تلقائياً | Set up and generate the timetable | Org dashboard › Timetable › Next step |  |
| org_timetable_ladder | organizations | org_admin, org_staff | سلّم التخفيف: جدول مكتمل بلا تعارض | The relaxation ladder: a complete, conflict-free timetable | Org dashboard › Timetable › the studio › Generate the timetable, and the ladder icon |  |
| org_timetable_fix_publish | organizations | org_admin, org_staff | مراجعة التعارضات وتعديل الجدول ونشره | Fix clashes, adjust and publish the timetable | Org dashboard › Timetable › the studio |  |
| org_timetable_autopilot | organizations | org_admin, org_staff | الجدول بضغطة واحدة والإصلاح التلقائي | One-tap timetable and automatic fixing | Org dashboard › Needs your attention · Timetable › the term card · the studio › Fix automatically |  |
| org_exam_timetable | organizations | org_admin, org_staff | جدول الامتحانات النصفية والنهائية | Midterm and final exam timetable | Org dashboard › Timetable › Exam timetables |  |
| org_forms_regulations | organizations | org_admin, org_staff, org_member | النماذج والطلبات واللوائح | Forms, requests and regulations | Org dashboard › Services › Forms & requests; Settings › Terms & regulations; members: My requests and Regulations |  |
| org_reports | organizations | org_admin, org_staff | تقارير الشكاوى والطلبات | Complaints and requests reports | Org or department dashboard › Reports |  |
| org_settings_sharing | organizations | org_admin | إعدادات المؤسسة: الوقت والميزات ومشاركة البيانات | Organization settings: time, features and data sharing | Org dashboard › Settings › Time & features / Sharing with other organizations |  |
| registrar_course_registration | organizations | org_member | تسجيل المقررات في نظام الساعات المعتمدة | Course registration (credit hours) | My organization › Course registration |  |
| registrar_academic_record | organizations | org_member | السجل الأكاديمي والمعدل التراكمي | Academic record and GPA | My organization › My academic record |  |
| registrar_grade_entry | organizations | org_member, org_staff | رصد الدرجات وموافقات الجدول | Grade entry and timetable consents | My organization › Grade entry / Timetable consents |  |
| registrar_staff | organizations | org_admin, org_staff | شؤون التسجيل للموظفين: القرارات والقواعد | Registrar for staff: decisions and rules | Org dashboard › Academics › Registrar |  |
| org_exam_risk_feedback | organizations | org_admin | مخاطر الامتحانات وملاحظاتها | Exam risk and exam feedback | Org dashboard › Services › Exam risk / Exam feedback |  |
| app_assistant | assistant | everyone | اسأل عن التطبيق | Ask about the app | Profile › Help › Ask about the app | rag.app_assistant |
| documents_assistant | assistant | org_member, org_staff, student | مساعد المستندات | Documents assistant | My organization › book icon, Documents assistant; or Course page › ⋮ › Ask the course documents | rag.assistant |
| documents_library | assistant | org_admin, org_staff, teacher | مكتبة المستندات للمساعد | Documents library for the assistant | Documents assistant › Documents library |  |
| app_assistant_admin | assistant | admin, super_admin | لوحة مساعد التطبيق ومكتبة كل مؤسسة | App assistant dashboard and library quotas | Admin dashboard › App configuration › App assistant dashboard; People & messages › Organizations › the organization › Assistant library quota | rag.admin |
| admin_users | administration | admin, super_admin | إدارة الطلاب والمعلمين والمشرفين | Manage students, teachers and admins | Admin dashboard › Students / Teachers / People & messages › Admins |  |
| admin_courses_categories | administration | admin, super_admin | إدارة الكورسات والأقسام | Manage courses and categories | Admin dashboard › Courses; People & messages › Categories |  |
| admin_teacher_category_details | administration | admin, super_admin | تفاصيل المعلم والقسم المترابطة | Connected teacher and category details | Admin dashboard › Teachers; People & messages › Categories |  |
| admin_organizations | administration | admin, super_admin | اعتماد المؤسسات وإدارتها | Approve and manage organizations | Admin dashboard › People & messages › Organizations |  |
| admin_view_as | administration | super_admin | عرض التطبيق كمستخدم | View the app as a user | Admin dashboard › People & messages › View as User |  |
| admin_app_configuration | administration | admin, super_admin | إعدادات التطبيق: الميزات والمظهر والإصدارات | App configuration: features, theme and versions | Admin dashboard › App configuration › Features / Theme / Versions / Terms & Conditions | admin_versions, admin_versions.publish |
| admin_platform_settings | administration | super_admin | إعدادات المنصة | Platform settings | Admin dashboard › App configuration › Platform settings; Support & security › Verification & login |  |
| admin_devices_documents | administration | admin, super_admin | حدود الأجهزة ومستندات المعلمين | Device limits and teacher documents | Admin dashboard › Support & security › Devices / Teacher required documents |  |
| admin_data_center | administration | admin, super_admin | مركز البيانات ومطالب المنصة | Data Center and platform requirements | Admin dashboard › People & messages › Data Center / Platform requirements |  |
| admin_parent_links | administration | admin, super_admin | طلبات ربط أولياء الأمور وإعداداتها | Parent link requests and settings | Admin dashboard › People & messages › Parent link requests / Parent link settings |  |
| app_assistant_chat | assistant | everyone | مساعد التطبيق الذكي | The AI app assistant | The floating button on every screen, or Profile › Help › Ask about the app | rag.app_assistant |
| exam_generate_agents | exams | teacher, org_staff | توليد أسئلة الامتحان بالوكلاء الأذكياء | Exam questions written by AI agents | The quick exam builder → "Generate the questions for me from the course documents" | rag.assistant, exam.auto_create |
| rag_admin_console | administration | super_admin, admin | لوحة المساعد الذكي | AI assistant console | Admin dashboard › App configuration › AI assistant console, or the AI assistant card › Open the console on the Overview | rag.admin |
| admin_ai_models | administration | super_admin | نماذج الذكاء الاصطناعي | AI Models | Admin dashboard › App configuration › AI Models | models.admin |
| rag_qa_admin | assistant | super_admin, admin, org_admin | الإجابات المعتمدة للمساعد (أسئلة وأجوبة) | Curated Q&A for the assistant | AI assistant console → Q&A tab; for an organization: Documents library → Curated Q&A button | rag.qa_admin |
| rag_learning | assistant | super_admin, admin, org_admin | التعلم من الملاحظات: المساعد ومولّد الأسئلة يتحسنان بالاستخدام | Learning from feedback: the assistant and the question generator improve with use | AI assistant console › Learning tab (platform admins); the organization's Documents library › Learning from feedback button (its library managers) | rag.learning |
| admin_splash_footer | administration | super_admin | سطر وشعار أسفل شاشة البداية | Splash screen footer line and logo | Admin dashboard → Content → About us → Identity card → “Splash screen footer” |  |
| org_gov_entities | organizations | org_admin | الجهات: الإدارات الخدمية والأقسام العلمية والمجالس والمكاتب | Entities: service departments, scientific departments, councils and offices | Organization dashboard → Requests & councils → “Entities” | org.governance |
| org_study_system | organizations | org_admin | نظام الدراسة في المؤسسة: تقليدي أو ساعات معتمدة | The institution's study system: traditional or credit hours | Organization dashboard → Settings → “Study system” | org.institution |
| org_dept_catalog | organizations | org_admin | دليل الإدارات: الأقسام العلمية والإدارات الخدمية مع أنواع طلباتها | Department catalog: academic and service departments with their request types | Organization dashboard → Settings → “Department catalog” | org.institution |
| org_messages | communication | org_admin, org_staff, teacher | مراسلة طلاب المؤسسة: رسالة عادية أو مع إشعار أو بإقرار إلزامي | Message the organization's students: normal, with a push, or must-acknowledge | Organization dashboard → “Messages” → “New message”; on a complaint or request: “Message the submitter” | org.messages |
| org_must_ack | communication | student, org_member | رسالة الإقرار الإلزامي من المؤسسة | A must-acknowledge message from your organization | Appears by itself in the app; every message is under “Organization messages” | org.messages, org.messages.must_ack |
| org_gov_submit | communication | org_member, student, teacher, org_staff | تقديم شكوى أو طلب إلى جهة ومتابعته | Submit a complaint or a request to an entity and follow it | My organization → “Requests & complaints” → “Submit” · “My items” | org.governance |
| org_gov_for_others | communication | org_admin, org_staff, teacher | تقديم طلب أو شكوى نيابةً عن عضو أو عن شخص من خارج النظام | File a request or complaint for a member or for someone outside the system | My organization → “Requests & complaints” → “Submit” → “For” | org.governance |
| org_gov_attachments | communication | org_member, student, teacher, org_staff, org_admin | مرفقات الطلبات: رفع ومعاينة وتنزيل | Request attachments: upload, preview and download | Submit form → “Attachments” · the item page → “Attachments” | org.governance |
| org_gov_chain | organizations | org_admin, org_staff, org_member, student, teacher | سلسلة الاعتماد: المدير ← جهة أخرى ← المجلس، والرفض المسبّب وإعادة التقديم | Approval chain: manager → another entity → council, reasoned rejection and resubmit | Organization dashboard → Requests & councils → “Entities” → the entity → “Approval chain” · the item page | org.governance |
| org_gov_items | organizations | org_admin, org_staff | قائمة المعاملات الموحدة مع فلتر واحد قابل للحفظ | The unified item list with one saved filter | Organization dashboard → Requests & councils → “Items” · inside every entity | org.governance |
| org_gov_routing | organizations | org_admin, org_staff | الإحالة والتوجيه والتصعيد والقرار الأول | Routing, forwarding, escalation and the first decision | Item screen → “Route” · “Approve / Reject” · “Escalate” | org.governance |
| org_gov_delegation | organizations | org_admin, org_staff | تفويض صلاحية القرار (محدد أو كامل، بتاريخ بداية ونهاية) | Delegating the decision authority (scoped or global, with dates) | Entity → “Delegations” | org.governance |
| org_gov_forward | organizations | org_admin, org_staff, teacher, org_member | إحالة الطلب المعتمد: إلى مجلس أعلى أو جهة خارجية أو شخص بإجراء مطلوب | Forwarding an approved request: to a higher council, an outside party or a person with a required action | The approved item's page → “Forward after approval” · for the recipient: the item page → “Respond” | org.governance |
| org_gov_external | organizations | org_admin, org_staff | الطلبات الواردة من خارج المؤسسة تُحال تلقائياً إلى المجلس | Requests from outside the institution go to the council automatically | Organization dashboard → Requests & councils → “Items” → “New item” → “Received from outside the institution” · Settings → “Outside requests” | org.governance |
| org_gov_councils | organizations | org_admin, org_staff, teacher | جلسات المجالس الشهرية والتصويت على البنود | Monthly council sessions and voting on agenda items | Organization dashboard → Requests & councils → “Councils” · “My votes” | org.governance |
| org_gov_export_hub | organizations | org_admin, org_staff | مركز التصدير: تصميم PDF و Word و Excel لأي قائمة | The Export Hub: designed PDF, Word and Excel for any list | The Export button of any list → “Design…” | org.governance, org.governance.export_hub |
| confirm_identity | account | everyone | تأكيد الهوية قبل التغييرات الحساسة | Confirm it's you before sensitive changes | The Confirm it's you sheet opens by itself when you delete your account or change your phone number |  |
| live_updates_refresh | discover | everyone | تحديث تلقائي وسحب للتحديث | Live updates and pull to refresh | Every screen: Home, notifications, the calendar and lists |  |
| parent_today | learning | parent | تبويب «اليوم» لولي الأمر | The parent's Today tab | Parent dashboard › Today tab | parent.insights |
| admin_home | administration | super_admin, admin | الصفحة الرئيسية لمدير المنصة (نظرة عامة) | Platform admin home (Overview) | Admin dashboard › Overview tab |  |
| assistant_chat_sessions | assistant | everyone | محادثات المساعد: محادثة جديدة وسجل المحادثات | Assistant chats: New chat and chat history | The top of the floating assistant or of the assistant screen: the New chat and Chats buttons | rag.app_assistant, rag.assistant |
| assistant_answer_feedback | assistant | everyone | تقييم إجابات المساعد | Rate the assistant's answers | Under every answer in the floating assistant or the assistant screen | rag.app_assistant, rag.assistant |
| profile_link | account | teacher, student, everyone | ملفي الشخصي ورابطه العام (nextbrain.site/@اسمك) | My profile and its public link (nextbrain.site/@yourname) | Profile › My profile (and Share in the header) | profile.public_link, auth.username, profile.public_stats, profile.my_profile |
| home_live_now | live | student, teacher, org_member | «مباشر الآن» على الصفحة الرئيسية | "Live now" on the home screen | The top of the home screen (student, instructor, organization member) | live_sessions |
| home_fold_sections | account | student, teacher, org_member | طيّ أقسام الصفحة الرئيسية | Fold the sections of your home | The home screen — any section's title |  |
| courses_by_side | learning | student, teacher | كورسات حسابك الشخصي منفصلة عن كورسات المؤسسة | Your personal courses apart from your organization's | The My courses page (students and teachers) |  |
| vod_listen_only | learning | student, teacher | الصوت فقط (الدروس المسجّلة) | Audio only (recorded lessons) | Video player → quality menu → Audio only, or Listen at the top |  |
| export_studio | administration | teacher, org_admin, org_staff, admin, super_admin | استوديو التصدير (Excel وWord وPDF) | Export Studio (Excel, Word and PDF) | The Export button on any table (members, payments, attendance, timetables…) | export.studio |
| export_layout_designer | administration | teacher, org_admin, org_staff, admin, super_admin | مصمم قوائم التصدير (قائمة وجدول وبطاقات) مع معاينة الصفحات | Export list designer (list, table and cards) with page preview | The Export button on any table › Design the list | export.layout_v3, export.studio |
| export_computed_columns | administration | teacher, org_admin, org_staff, admin, super_admin | الأعمدة المحسوبة في التصدير (بدون كتابة أكواد) | Computed columns in exports (no code) | The Export button on any table › Design the list › Computed columns | export.layout_v3, export.studio |
| export_schedules_links | administration | teacher, org_admin, org_staff, admin, super_admin | التصدير المجدول والروابط المؤقتة | Scheduled exports and expiring links | Admin › Services › Exports; in an organization: Settings › Exports; or Share link after any export | export.schedules, export.share_links |
| export_log | administration | org_admin, admin, super_admin | سجل التصدير | Export log | Admin › Services › Exports › Export log; in an organization: Settings › Exports | admin.export_log |
| course_students | administration | super_admin | مشتركو الكورسات | Course students | Admin › Course students | admin.course_students |
| course_trash | administration | super_admin | الكورسات المحذوفة | Deleted courses | Admin services → Deleted courses | admin.course_trash |
| get_the_app | account | everyone | تحميل التطبيق | Get the app | The "Get the app" banner at the top of the web app, or Profile / More → Get the app | get_app.banner, get_app.entry, app.update_prompt |
| app_download_banner | account | everyone | تنزيل التطبيق من الموقع | Download the app from the website | The top of the platform's website pages | app.download_banner |
| help_info_button | account | everyone | زر المعلومات (i) والمساعدة والجولة | The Info (i) button, help panel and tour | The (i) button in any page header | help.info |
| help_admin | administration | super_admin | إدارة المساعدة والأدلة والتصدير | Help management and exports | Admin dashboard › App configuration › Help | admin.help |
| assistant_personal_questions | assistant | student | أسئلة شخصية للمساعد | Personal questions to the assistant | The floating assistant button or the assistant screen | rag.app_assistant, rag.assistant |
| assistant_action_buttons | assistant | everyone | إجابات بأزرار تفتح الصفحة | Answers with buttons that open the page | Under an assistant answer | rag.app_assistant, rag.assistant |
| assistant_answer_modes | assistant | everyone | نمط الإجابة والبث المباشر | Answer mode and streaming | The assistant screen | rag.app_assistant, rag.assistant |
| assistant_feedback_review | assistant | super_admin, admin, org_admin | مراجعة الملاحظات والإجابات المعتمدة | Feedback review and verified answers | AI assistant console › Feedback; for an organization: Documents library › Feedback | rag.learning, rag.qa_admin |
| rag_console_controls | administration | super_admin | ضبط المساعد: الذاكرة المؤقتة والتدريب والملفات الممسوحة | Assistant controls: cache, search training, scanned files | Admin dashboard › App configuration › AI assistant console | rag.admin, rag.learning |
| models_per_task | administration | super_admin | نموذج لكل مهمة | Models per task | Admin dashboard › App configuration › AI Models | models.admin |
| model_benchmarks | administration | super_admin | قياس النماذج واختيار الأفضل لكل دور | Model benchmarks and the best model per role | Admin dashboard › App configuration › AI Models › Benchmarks | models.admin, models.benchmarks |
| documents_upload_scopes | assistant | super_admin, admin, org_admin, org_staff, teacher | نطاق رفع المستندات والتنبيهات | Upload scopes and scan warnings | Documents library › Upload | rag.assistant, rag.admin |
| exam_results_visibility | exams | teacher, org_staff | ما يراه الطالب من نتيجته، ونشر النتائج وإلغاء نشرها | What students see of their result, and publishing or unpublishing results | The exam › Results › Publish results, and What students see in the exam settings | exam.results_view |
| exam_question_void | exams | teacher, org_staff | إلغاء سؤال من الاختبار | Cancel a question | The exam › Results › a question › Cancel question | exam.question_void |
| exam_grade_log | exams | teacher, org_staff | سجل الدرجات | Grade log | The exam › Results › Grade log | exam.results_view |
| exam_mark_templates | exams | teacher, org_staff | قوالب أوراق الدرجات الخاصة بك | Register your own mark sheet | Exam management › Mark-sheet templates | exam.mark_templates |
| exam_grade_review | exams | teacher, org_staff | مراجعة الدرجات بالكاميرا | Grade review by camera | The course gradebook (Data Lab) › a grade column › Review by camera | exam.grade_review, exam.auto_correct |
| exam_mark_import | exams | teacher, org_staff | استيراد الدرجات من الورق | Mark import from paper | The course gradebook (Data Lab) › a grade column › Import from paper | exam.grade_review |
| exam_scan_issues | exams | teacher, org_staff | قائمة مشاكل المسح | Scan issues list | The exam › Paper exam › Scan issues | exam.omr, exam.auto_correct |
| grades_parent_visibility | exams | super_admin, org_admin | ما يراه ولي الأمر من درجات الاختبارات | What parents see of exam grades | Admin dashboard › App configuration › Parents' grades; for an organization: Organization settings › Parents' grades | grades.parent_visibility |
| parent_org_view | organizations | parent | مؤسسة ابني: الجدول والإعلانات والدرجات | Your child's organization: timetable, announcements, grades | Parent dashboard › Children › the child's organization | parent.org_view |
| org_invitations | organizations | org_admin, org_staff | دعوة أشخاص إلى المؤسسة | Invite people to the organization | Org dashboard › People › Invitations | org.invitations |
| org_academic_advising | organizations | org_admin | تفعيل الإرشاد الأكاديمي في المؤسسة | Switch on academic advising | Org dashboard › Services › Academic Advising | org.advising |
| org_advising_assignment | organizations | org_admin, org_staff | إعدادات الإرشاد وتوزيع الطلاب على المرشدين | Advising settings and distributing students to advisors | Org dashboard › Services › Academic Advising › Settings · Advisors · Distribute · Students | org.advising |
| org_advising_my_profile_handovers | organizations | teacher, org_staff | ملفي كمرشد أكاديمي وتسليمات الطلاب | My academic advisor profile and student handovers | Org dashboard › Services › Academic Advising › My profile · Handovers | org.advising |
| org_advising_workspace | organizations | org_admin, org_staff, teacher | مساحة عمل المرشد الأكاديمي وملف الطالب الشامل | The academic advisor's workspace and the student 360 | Org dashboard › Services › Academic Advising › My students · Workspace | org.advising |
| org_advising_flags_notes | organizations | org_admin, org_staff, teacher | إنذارات الطلاب وملاحظات الإرشاد | Student alerts and advising notes | Org dashboard › Services › Academic Advising › Student profile › Alerts · Notes · Categories | org.advising |
| org_advising_appointments | organizations | org_admin, org_staff, teacher, org_member | مواعيد الإرشاد الأكاديمي وساعات المكتب | Academic advising appointments and office hours | Academic Advising › My hours · Appointments — for students: My organization › My advisor | org.advising |
| org_advising_messages | organizations | org_admin, org_staff, teacher, org_member | رسائل وشكاوى الإرشاد الأكاديمي | Academic advising messages and complaints | Academic Advising › Messages — for students: My advisor › Messages | org.advising |
| org_advising_early_warning | organizations | org_admin, org_staff, teacher | الإنذار المبكر وخطر تأخر التخرج | Early warning and graduation delay risk | Org dashboard › Services › Academic Advising › Rules · Alerts · Student profile › Early warning | org.advising, org.advising.warning |
| org_advising_requests | organizations | org_admin, org_staff, teacher, student | طلبات الدعم ومجالس الأقسام والكلية والإحالات | Support requests, department and faculty councils, and referrals | Org dashboard › Services › Academic Advising › Requests · Student 360 › Support · for the student: My advisor | org.advising |
| org_advising_analytics | organizations | org_admin, org_staff | تحليلات الإرشاد وتقرير الالتزام وفحص البيانات | Advising analytics, compliance report and data check | Org dashboard › Services › Academic Advising › Analytics | org.advising, org.advising.analytics |
| org_advising_outreach | organizations | org_admin, org_staff, teacher, student | رسائل جماعية للطلاب مع تتبع القراءة | Group messages to students with read tracking | Academic Advising › Group messages · for the student: My advisor › Messages | org.advising, org.advising.outreach |
| org_advising_plans | organizations | org_admin, org_staff, teacher, student | خطط الدعم الفردية والترتيبات الخاصة | Individual support plans and accommodations | Student 360 › Support › Support plans · Accommodations · for the student: My advisor | org.advising |
| org_billing_view | organizations | org_admin | رسوم العضوية في المؤسسة (عرض فقط) | Membership fees in the organization (view only) | Org dashboard › Settings › Fees | org.billing_view |
| org_setup_checklist | organizations | org_admin | قائمة إعداد المؤسسة | Organization setup checklist | Org dashboard › Home › Set up your organization | org.setup_checklist |
| admin_org_manage | administration | admin, super_admin | إدارة المؤسسات: تعديل وحذف واستعادة ونقل الإدارة | Manage organizations: edit, delete, restore, transfer admin | Admin dashboard › Organizations › open an organization | admin.org_manage |
| teacher_my_students | teaching | teacher | طلابي والتسليمات والتقييمات | My students, submissions and reviews | My courses › My students, Submissions, Reviews | teacher_tab_my_courses, teacher_courses.classroom |
| student_course_story | learning | student | تقدمك في الدورة | Your progress in a course | My courses › tap any course | student_tab_my_courses |
| student_grades_money | learning | student | درجاتي ومدفوعاتي | My grades and payments | Profile › Grades and certificates, Payments and subscriptions | profile.my_certificates, profile.my_payments |
| entity_search | discover | teacher, student, parent | البحث السريع (Ctrl+K) | Quick search (Ctrl+K) | Anywhere in your dashboard: press Ctrl+K (or ⌘+K) |  |
| list_views_bulk | teaching | teacher, admin | العروض المحفوظة والإجراءات الجماعية | Saved views and bulk actions | My students, Submissions, Reviews, and the admin Students, Teachers and Courses lists |  |
| exam_import_google_forms | exams | teacher, org_admin, org_staff | استيراد اختبار من Google Forms | Import an exam from Google Forms | New exam › Import from Google Forms, or Exam editor › Sections and questions › Import from Google Forms | exam.google_forms_import |
| privacy_terms_pages | account | everyone | سياسة الخصوصية وشروط الاستخدام | Privacy policy and terms of service | Settings › Privacy policy / Terms of service, or the links under the sign-in and sign-up screens | profile.privacy, profile.terms, terms.privacy, terms.links |
| admin_legal_editor | administration | super_admin, admin | تحرير سياسة الخصوصية والشروط | Edit the privacy policy and terms | Dashboard › Services › About & terms › Privacy & terms |  |
| admin_update_policy | administration | admin, super_admin | سياسة تحديث التطبيق | App update policy | Admin dashboard › App versions | app.update_prompt |
| exam_all_exams | exams | teacher, org_admin, org_staff | كل الاختبارات | All exams | Teacher analytics › All exams, or a course's exams page › All exams | exam.all_exams |
| teacher_todo | teaching | teacher | قائمة مهامك التلقائية | Your automatic to-do list | Home (teacher) › Your to-do › See all | teacher_home.todo |
| parent_message_teacher | communication | parent | مراسلة مدرّس الابن | Message your child's teacher | Parent dashboard › Today › Needs your attention or Subjects › Message the teacher | parent.message_teacher |
| meeting_links | live | student, teacher, org_admin, org_staff | روابط الاجتماعات | Meeting links | Schedule page › Meeting links, or the teacher home (link icon), or the organization home | live.meeting_links |
| share_links | discover | everyone | مشاركة الروابط | Share links | The Share button on the course page, the path, a meeting, the session menu and a lesson row | share.links |
| exam_generate_background | exams | teacher, org_admin, org_staff | توليد الأسئلة في الخلفية: سريع أو أعلى جودة، ومن موضوع عند عدم وجود ملفات | Question generation in the background: fast or best quality, and from a topic when there are no files | Quick exam › Generate for me › the Language step (speed) and the Generate step | exam.auto_create |
| exam_own_sheet | exams | teacher, org_admin, org_staff | التصحيح على ورقتك الخاصة (أي ورقة تظليل أو جدول إجابات مكتوبة) | Mark papers on your own sheet (any bubble sheet or a written answer table) | The exam › Paper exam setup › the Sheet step › Use your own sheet | exam.omr, exam.auto_correct |
| chat_messages | communication | student, teacher, parent, org_admin, org_staff, admin, super_admin | الرسائل | Messages | My profile › Messages, or the Messages icon at the top | chat, chat.direct, chat.requests, chat.attachments, chat.presence, chat.push |
| chat_course_groups | communication | student, teacher | مجموعة المقرر | Course group | Messages › Groups | chat, chat.course_groups |
| chat_blocking | communication | student, teacher, parent, org_admin, org_staff | حظر المحادثات والإبلاغ | Blocking and reporting in chats | A chat › Menu › Block or Report · Messages › Blocked people | chat, chat.blocking, chat.report |
| bubble_import_sheet | exams | teacher, org_staff | استخدام أي ورقة إجابة مطبوعة خارج المنصة | Use any answer sheet, even one printed outside the platform | Exams › Correct bubble sheets › Import a new sheet | exam.bubble, exam.bubble.teach |
| bubble_correct_class | exams | teacher, org_staff | تصحيح أوراق فصل كامل من الصور أو ملفات PDF | Correct a whole class from photos or a PDF | Exams › Correct bubble sheets | exam.bubble, exam.auto_correct |
| bubble_marks_datalab | exams | teacher, org_staff | كتابة الدرجات في عمود Data Lab أو تنزيلها Excel | Write the marks into a Data Lab column or download Excel | Correct bubble sheets › Results | exam.bubble, exam.bubble.datalab |
| exam_hub | exams | teacher, org_staff, admin | الاختبارات | Exams | Profile tab › Exams (or organization Settings, or the admin services hub) | exam.hub |
| exam_create_wizard | exams | teacher, org_staff, admin | معالج الاختبار الجديد | New exam wizard | Exams › New exam | exam.hub, exam.omr, exam.identifiers |
| exam_grade_papers | exams | teacher, org_staff | تصحيح أوراق | Grade papers | Exams › Grade papers | exam.hub, exam.bubble, exam.auto_correct, exam.essay_run |
| exam_bubble_from_key | exams | teacher, org_staff | تصحيح التظليل من الإجابة النموذجية | Bubble correction from the model answer | Exams › Grade papers › Bubble sheets › Start from the model answer | exam.bubble, exam.bubble.from_key, exam.auto_correct |
| exam_bubble_no_course | exams | teacher, org_staff | تصحيح أوراق طلاب بلا مقرر | Correct papers of students in no course | Exams › Grade papers › Bubble sheets › No course | exam.bubble, exam.auto_correct |
| exam_bubble_corrected_sheets | exams | teacher, org_staff | أوراق الطلاب المصححة | Corrected sheets | Exams › Grade papers › Bubble sheets › the correction › Corrected sheets | exam.bubble |
| exam_essay_run | exams | teacher, org_staff | تصحيح الأوراق المكتوبة بدون اختبار | Grade written papers without an exam | Exams › Grade papers › Written papers | exam.essay_run, exam.auto_correct |
| exam_auto_grade | exams | teacher, org_staff | التصحيح التلقائي للإجابات المكتوبة (كلمة، إجابة قصيرة، مقال) | Automatic grading of written answers (word, short answer, essay) | Exams › Question › Model answer › Advanced | exam.auto_grade |
| exam_answer_booklet | exams | teacher, org_staff, admin | دفتر الإجابة | Answer booklet | Exams › Print and deliver | exam.hub |
| exam_key_fix | exams | teacher, org_staff, admin | تصحيح مفتاح سؤال | Fix a question's key | Exams › Results › Check these keys | exam.hub |
| exam_duplicate | exams | teacher, org_staff, admin | نسخ اختبار | Duplicate an exam | Exams › Creation › ⋮ › Duplicate | exam.hub |
| exam_deliver | exams | teacher, org_staff, admin | تجهيز الاختبار وتسليمه | Print and deliver an exam | Exams › Creation › Print and deliver | exam.hub, exam.identifiers, exam.deliver_email, exam.paper_designer, exam.omr |
| exam_correct | exams | teacher, org_staff, admin | تصحيح الاختبار | Correct the exam | Exams › Results & Correction › Correct | exam.hub, exam.omr, exam.auto_correct |
| exam_results_hub | exams | teacher, org_staff, admin | نتائج الاختبار | Exam results | Exams › Results & Correction | exam.hub, exam.results.datalab, exam.results.import, export.studio |
| exam_revision | exams | teacher, org_staff, admin | مراجعة الدرجات | Grade revision | Exams › Results & Correction, the Data Lab menu, or an exam's review | exam.grade_review, exam.auto_correct |
| image_background_removal | teaching | student, teacher, parent, org_admin, org_staff, org_member, admin, super_admin | إزالة خلفية الصور | Remove an image's background | Image crop screen › Background tab | image.background |
| certificate_verify | learning | everyone | التحقق من شهادة | Verify a certificate | My certificates, Profile, Certificate designs, the sign-in page, or the /verify link | certificates.verify |
| exam_answer_sheet | exams | teacher, org_staff | ورقة الإجابة المقروءة آليًا | Machine-read answer sheet | Exams › Paper exam › Answer sheet | exam.hub, exam.answer_sheet, exam.auto_correct |
| exam_offline_layout | exams | teacher, org_staff | طريقة الإجابة في الاختبار الورقي وبيانات الطالب المطبوعة | Paper exam answer layout and printed student details | Exams › New exam › Paper › Answer sheets | exam.hub, exam.answer_sheet |
| admin_ai_controls | administration | super_admin | التحكم في ميزات الذكاء الاصطناعي | AI controls | Admin dashboard › App configuration › Features › AI controls |  |
| course_students_nudge | teaching | teacher, org_staff, admin | طلاب المقرر وتذكير المتأخرين | Course students and nudging low-progress students | Course › Students | course_students.nudge |
| org_gov_council_s2 | organizations | org_admin, org_staff | المجالس: الأمين والأوزان والتذكير والنتائج وأرقام القرارات | Councils: secretary, weights, reminders, results and decision numbers | Organization dashboard → Requests & councils → the council → Members, Settings and Sessions | org.governance |
| org_gov_routing_sla_s3 | organizations | org_admin, org_staff | الإحالة التلقائية والتصعيد عند تجاوز المهلة وقوالب القرارات والمحضر الرسمي | Automatic routing, SLA escalation, decision templates and official minutes | Organization dashboard → Requests & councils → the department → Automatic routing · Settings → SLA escalation · the session → Write an item → From a template · Export Hub → Session minutes | org.governance |
| org_gov_faculty_overview_s5 | organizations | org_admin, org_staff | نظرة على الكلية: الطلبات والمجالس في كل الإدارات | Faculty overview: requests and councils across every department | Organization dashboard → Home → Faculty overview | org.governance |
| org_institution_wizard | organizations | org_admin | معالج إعداد المؤسسة التعليمية: من نظام الدراسة إلى التشغيل | Institution setup wizard: from the study system to launch | Organization dashboard → “Institution setup” | org.institution |
| org_institution_health | organizations | org_admin | صحة المؤسسة: ما يحتاج إصلاحاً الآن | Institution health: what needs fixing now | Organization dashboard → “Institution health” | org.institution |
| org_councils_setup | organizations | org_admin | اختيار المجالس: مجلس الكلية ومجالس الأقسام أو لا شيء | Choose the councils: faculty council, department councils, both or none | Organization dashboard → Requests & councils → “Councils” → “Councils setup”; or the Councils step of the setup wizard | org.governance |
| org_message_department | communication | org_member, student, teacher | مراسلة إدارة في مؤسستك | Message a department of your organization | My organization → Departments → the department → “Message the department” | org.governance |
| org_notify_settings | communication | org_member, org_staff, org_admin, teacher | إشعارات المؤسسة على هاتفك: الكل أو المهم فقط أو إيقاف | Organization notifications on your phone: all, important only, or off | My organization → Settings → “Organization notifications” | org.governance |
| org_archive_department | organizations | org_admin | أرشفة إدارة أو حذفها بأمان | Archive or delete a department safely | Organization dashboard → Departments → the department → “Archive” |  |
| org_my_journey | organizations | student, org_member | رحلتي في المؤسسة: ما أفعله الآن وبعد ذلك | My journey: what to do now and next | The member home in the organization → “My journey” | org.governance |
| org_needs_my_attention | organizations | org_staff, org_admin | يحتاج انتباهي: الطلبات والتصويت والمتأخر في صفحة واحدة | Needs my attention: requests, votes and overdue items on one page | Organization dashboard → “Needs my attention” | org.governance |
| personal_account | account | org_member, org_staff, org_admin | الحساب الشخصي | Personal account | Settings → Organization, or Account → Account & security |  |
| course_rules | teaching | teacher, org_staff, student, org_member | قواعد الكورس | Course rules | Course page → Overview → Course rules | course.rules |
| course_sections | teaching | teacher, org_staff, org_admin, student, org_member | سكاشن الكورس | Course sections | Course page → Appointments → Sections | course.sections |
| course_attendance_flag | teaching | teacher, org_staff | تشغيل الحضور وإيقافه | Turn attendance on or off | Course page → ⋮ → Course attendance; and each session's ⋮ menu | course.attendance_flag |
| account_fee | account | teacher, parent, admin, super_admin | رسوم فتح حساب المعلم أو ولي الأمر | Account fee for teachers and parents | After signing in, the Account fee page appears when it is due · Admin: Platform settings → Account fees |  |
| account_approval | account | teacher, parent, student, admin, super_admin | طريقة فتح الحسابات الجديدة: مجاني أو رسوم أو موافقة الإدارة | How new accounts open: free, fee, or admin approval | Admin: Platform settings → New accounts · Users → Accounts waiting for approval |  |
| exam_policy | exams | super_admin | إعدادات الاختبارات على المنصة | Exam settings for the platform | Admin: Services → Exam settings |  |
| org_teacher_workspace | organizations | teacher, org_staff | مساحة عمل المعلم في المؤسسة | Teacher organization workspace | Organization dashboard (teachers and staff) › Management / Membership / Alerts | org.teacher_workspace |
| org_admin_organization_tab | organizations | org_admin | تبويب «المؤسسة» لمدير المؤسسة | The Organization tab for organization admins | Organization dashboard (admin) › Organization | org.teacher_workspace |
| org_onboarding_review | organizations | org_admin, org_member | القبول والتعيين: مراجعة الملفات | Admissions & appointments: reviewing files | Organization dashboard > People > Admissions & appointments | org.onboarding |
| org_onboarding_add_one | organizations | org_admin, org_member | إضافة شخص بمعالج الإضافة | Add one person wizard | Admissions & appointments > Add | org.onboarding |
| org_onboarding_import | organizations | org_admin | استيراد ملفات الأعضاء من Excel | Excel import of member files | Admissions & appointments > More > Import from Excel | org.onboarding, org.onboarding.import |
| org_onboarding_invite | organizations | org_admin, org_member | دعوة لإكمال البيانات | Invite to complete | Admissions & appointments > More > Invite to complete | org.onboarding, org.onboarding.invite |
| org_onboarding_intake | organizations | org_admin | رابط التسجيل الذاتي | Intake link | Member types > the type > Intake link | org.onboarding, org.onboarding.intake |
| org_onboarding_types | organizations | org_admin | محرر أنواع الأعضاء | Member types editor | Admissions & appointments > Member types | org.onboarding |
| me_onboarding | organizations | student, teacher, org_member | طلبي (جهة المتقدم) | My application (applicant) | Home > My application card | org.onboarding |
| join_flow | discover | student, teacher, parent | الانضمام من الصفحة الرئيسية | Join from the landing page | Website home › Join as a student / teacher / parent | join.flow |
| course_filters | discover | student, parent | فلترة الكورسات بالمرحلة والصف | Filter courses by stage and grade | Home > Filter, and Explore courses > Filter | courses.filters |
| store | payments | student, parent | المتجر الرقمي ومكتبتي | The digital store and My Library | Store tab > an item > Buy, and Store > My Library | student_tab_store, store.buy, store.points |
| store_manage | administration | admin, super_admin, teacher | إدارة عناصر المتجر ومراجعتها | Managing and reviewing store items | Store > Manage items, and Admin > Store | store.manage, admin.store |
| quran | learning | student, parent, teacher | تحفيظ القرآن ومتابعة الحفظ | Quran memorization and progress | Quran tab > Teachers, and Quran tab > My progress | student_tab_quran |
| quran_teacher | teaching | teacher, super_admin | ملف معلم القرآن وسجل الطلاب | The Quran teacher's profile and record sheet | Quran > My teacher profile, and Quran > Record sheet | quran.teacher_apply |
| nahw | learning | student, parent | تعلم النحو بالتمارين | Learning Arabic grammar (nahw) with exercises | Nahw tab > a level > a lesson | student_tab_nahw |
| games | learning | student | الألعاب التعليمية والشارات | Learning games and badges | Games tab > a subject > the level map, and Games tab > My progress | student_tab_games, games.templates_v4, games.rewards |
| games_review | learning | student | مراجعة أخطائك في الألعاب | Reviewing your mistakes in games | Games tab > Review | student_tab_games, games.templates_v4 |
| games_wardrobe | learning | student | العملات وخزانة الشخصية | Coins and the wardrobe | Games tab > coins > Wardrobe | student_tab_games, games.templates_v4, games.cosmetics |
| games_challenges | learning | student | تحدّي الأصدقاء ولوحة الصف | Friend challenges and the class board | Games tab > Challenges, or a level > Challenge a friend | student_tab_games, games.templates_v4, games.challenges |
| games_offline | learning | student | تنزيل المستوى للعب دون إنترنت | Download a level to play offline | A level > the Download for offline button | student_tab_games, games.templates_v4 |
| games_quran_reciter | learning | student | القارئ والوضع الهادئ في ألعاب القرآن | Reciter and calm mode in Quran games | Games tab > Games settings > Reciter | student_tab_games, games.templates_v4 |
| games_play_breaks | learning | student | استراحة اللعب أثناء المذاكرة | Game breaks while studying | Course page > Play now | student_tab_games, games.breaks |
| games_winner_coupon | learning | student | كأس بطل اليوم وقسيمته المقفلة | The daily champion's trophy and locked coupon | Home > the champion line, and Profile > My rewards | student_tab_games, games.champions, rewards.coupons, rewards.referral |
| parent_games_summary | learning | parent | ملخص ألعاب الابن | Your child's games summary | Children > a child > Games | parent.games_summary |
| module_settings | administration | super_admin | إعدادات الوحدات حسب الدولة والمؤسسة | Module settings per country and organization | Admin > Module settings; to hide a tab in a country: Education levels > the country > Features | admin.modules |
| quran_teacher_review | administration | super_admin | توثيق ومراجعة معلمي القرآن | Verify and review Quran teachers | Admin > Quran teachers, or Module settings > Quran memorization > Verify and review Quran teachers | admin.modules, student_tab_quran |
| nahw_content | administration | super_admin | تحرير محتوى النحو | Editing the grammar (nahw) content | Admin > Grammar content | admin.nahw |
| offline_sync | learning | student | العمل دون اتصال ومزامنة التقدّم | Work offline, synced later | The badge at the top of the page (shown only while offline or with changes waiting) | sync.offline |
| downloads_page | account | everyone | صفحة التنزيلات | The Downloads page | The the app website › Downloads |  |
| org_students_list | organizations | org_admin, org_member | الطلاب: قائمة الطلاب | Students: the student list | Organization dashboard > People > Students | org.students |
| org_student_file | organizations | org_admin, org_member | الطلاب: ملف الطالب الموحد | Students: the unified student file | Organization dashboard > People > Students > pick a student | org.students |
| org_student_status | organizations | org_admin, org_member | الطلاب: تغيير حالة الطالب | Students: change a student's status | Organization dashboard > People > Students > pick a student > Status | org.students.status |
| student_my_status | organizations | student | حالتي الدراسية | My study status | Organization home > My status | org.students.status |
| org_student_missing_data | organizations | org_admin, org_member | الطلاب: البيانات الناقصة والتذكير | Students: missing data and reminders | Organization dashboard > People > Students > Missing data | org.students.missing |
| org_student_ask | organizations | org_admin, org_member | الطلاب: اطلب بيانات أو اجتماعاً | Students: ask for data or a meeting | Organization dashboard > People > Students > pick a student > Ask | org.students.asks |
| org_student_requests | organizations | org_admin, org_member | الطلاب: صندوق الطلبات | Students: the requests inbox | Organization dashboard > People > Student requests | org.students.asks |
| org_student_rules | organizations | org_admin | الطلاب: قواعد الدراسة | Students: study rules | Organization dashboard > People > Students > Settings > Study rules | org.students.rules |
| student_my_asks | organizations | student | طلبات من المؤسسة لي | Requests from my organization | Home > Requests from the organization | org.students.asks |
| student_my_requests | organizations | student | طلباتي: إيقاف القيد والتأجيل والانسحاب | My requests: suspend, postpone, withdraw | Organization home > My requests | org.students.status |
| org_student_transfer_credits | organizations | org_admin, org_member | الطلاب: معادلة مقررات المحوّلين | Students: transfer credit | Organization dashboard > People > Students > pick a student > Transfer credit | org.students.status |
| calendar_recurring_meetings | schedule | student, teacher, org_member, org_staff, org_admin, admin, super_admin | الاجتماعات المتكررة | Recurring meetings | My schedule > New meeting > Repeat | calendar.recurring, calendar.entry |
| course_online_meetings | schedule | teacher | اجتماعات المقرر المباشرة ورابط الضيوف الثابت | Course online meetings and the one guest link | My Courses > the course > Sessions > Online meetings | live.quick_meeting, calendar.recurring, live.share_link, live.guest_link |
| self_learning | learning | student | التعلم الذاتي: درس قصير ومراجعة كل يوم | Self-learning: a short lesson and a review every day | Self-learning tab | student_tab_self_learning |
| self_learning_content | administration | super_admin | محتوى التعلم الذاتي وإعداداته | Self-learning content and settings | Admin > Self-learning; settings: Module settings > Self-learning | admin.self_learning, admin.modules |
| games_editor | administration | super_admin | محرر الألعاب الكلاسيكية والشارات | Classic games and badges editor | Admin > Games, or Games hub > Classic games, and Admin > Badges | admin.games |
| admin_games_hub | administration | super_admin | مركز الألعاب: القوالب والمواد | Games hub: templates and subjects | Admin dashboard > Services > Games hub | admin.games_content |
| admin_games_bank | administration | super_admin | بنك أسئلة الألعاب والاستيراد | Games question bank and import | Admin dashboard > Services > Games hub > Question bank / Import questions | admin.games_content |
| admin_games_review | administration | super_admin | مراجعة أسئلة الألعاب الشرعية | Religious review of game questions | Admin dashboard > Services > Games hub > Religious review | admin.games_content |
| admin_games_levels | administration | super_admin | مستويات الألعاب | Game levels | Admin dashboard > Services > Games hub > Levels | admin.games_content |
| admin_games_analytics | administration | super_admin | إحصاءات الألعاب | Games analytics | Admin dashboard > Services > Games hub > Games analytics | admin.games_content |
| admin_games_breaks | administration | super_admin | إعدادات استراحة اللعب وملخص ولي الأمر | Game break and parent summary settings | Admin dashboard > Services > Games hub > Breaks & parents | admin.games_content, games.breaks, parent.games_summary |
| admin_games_outfits | administration | super_admin | ملابس اللاعب | Player outfits | Admin dashboard > Services > Games hub > Outfits | admin.games_content, games.cosmetics |
| admin_games_seed | administration | super_admin | الأسئلة الجاهزة للألعاب | Ready-made game questions | Admin dashboard > Services > Games hub > Ready-made questions | admin.games_content |
| admin_games_reciters | administration | super_admin | قرّاء ألعاب القرآن | Quran game reciters | Admin dashboard > Services > Games hub > Reciters | admin.games_content |
| teacher_card | teaching | teacher | ملف المعلم واعتماده | Teacher profile and approval | Profile > Teacher profile | teacher_onboarding |
| teacher_discovery | discover | student, parent | البحث عن معلم | Find a teacher | Home > Teachers | teacher_discovery |
| packages | learning | student, teacher | باقات المعلمين | Teacher packages | Teacher profile > Packages, and Profile > My packages | packages |
| games_leaderboard | learning | student | لوحة المتصدرين في الألعاب | Games leaderboard | Games tab > a game > Leaderboard | student_tab_games, games.leaderboard |
| admin_package_refunds_due | payments | admin, super_admin | مبالغ الباقات المستحقة للردّ | Package refunds due | Admin dashboard > Teacher review > Refunds due | teacher_onboarding |
| games_champions | learning | student, parent | أبطال الألعاب اليوميون والأسبوعيون | Daily and weekly games champions | Games tab > the champions strip > Hall of Champions | student_tab_games, games.champions |
| rewards_coupons | payments | student | مكافآتي وقسائم الخصم | My rewards and discount coupons | Profile > My rewards | rewards.coupons |
| rewards_referral | account | student | دعوة الأصدقاء | Inviting friends | Profile > My rewards > the invite card | rewards.referral |
| admin_rewards | administration | super_admin, admin | إدارة المكافآت والأبطال والقسائم | Managing rewards, champions and coupons | Admin dashboard > Rewards, or Games hub > Game rewards | admin.rewards |

## 2. Kill-switch catalog

Columns: kill-switch key | label (English / Arabic, from `title_en` / `title_ar`) | group (tab id, tab English name).

| kill-switch key | label (English) | label (Arabic) | group | group name (English) |
|---|---|---|---|---|
| register | Register | التسجيل | auth | Auth & registration |
| additional_register | Additional registration | إكمال بيانات التسجيل | auth | Auth & registration |
| categories | Categories | التصنيفات | home | Home & browsing |
| notifications | Notifications | الإشعارات | support | Support & info |
| course_details | Course details | تفاصيل الكورس | courses | Courses |
| course_instructor | Instructor profile | ملف المحاضر | courses | Courses |
| roadmap | Roadmap | خارطة الطريق | courses | Courses |
| course.enroll_roadmap | Enroll in whole roadmap | الاشتراك في المسار كامل | payments | Payments & subscriptions |
| course.discount_badge | Discount badge & countdown | شارة الخصم والعد التنازلي | courses | Courses |
| profile | Profile screen | الملف الشخصي | profile | Profile |
| profile.account | Account section | قسم الحساب | profile | Profile |
| profile.settings | Settings section | قسم الإعدادات | profile | Profile |
| profile.help_group | Help section | قسم المساعدة | profile | Profile |
| profile.exit_group | Exit section | قسم الخروج | profile | Profile |
| profile.update_account | Update account | تعديل الحساب | profile | Profile |
| profile.change_password | Change password | تغيير كلمة المرور | profile | Profile |
| profile.study | Study details (stage, grade, school) | بيانات الدراسة (المرحلة والصف والمدرسة) | profile | Profile |
| profile.teacher_profile | Teacher profile | ملف المعلم | teacher | Teacher tools |
| profile.payout | Payout | سحب الأرباح | payments | Payments & subscriptions |
| profile.enrollment_request | Enrollment requests | طلبات الاشتراك | payments | Payments & subscriptions |
| profile.device_requests | Device switch requests | طلبات تغيير الجهاز | teacher | Teacher tools |
| profile.my_favorite | My favorites | المفضلة | profile | Profile |
| profile.notifications | Notifications toggle | تفعيل الإشعارات | profile | Profile |
| profile.change_language | Change language | تغيير اللغة | profile | Profile |
| profile.dark_mode | Dark mode | الوضع الليلي | profile | Profile |
| profile.help_center | Help center | مركز المساعدة | profile | Profile |
| profile.privacy | Privacy | الخصوصية | profile | Profile |
| profile.terms | Terms of service | شروط الاستخدام | profile | Profile |
| profile.data_export | Download my data | تنزيل بياناتي | profile | Profile |
| profile.about | About | عن التطبيق | profile | Profile |
| profile.logout | Logout | تسجيل الخروج | profile | Profile |
| profile.delete_account | Delete account | حذف الحساب | profile | Profile |
| additional_register.experience | Experience years | سنوات الخبرة | auth | Auth & registration |
| additional_register.specialization | Specialization | التخصص | auth | Auth & registration |
| additional_register.payment_method | Payment type | طريقة الدفع | auth | Auth & registration |
| additional_register.teaching_style | Teaching style | نمط التدريس | auth | Auth & registration |
| additional_register.bio | Bio | نبذة تعريفية | auth | Auth & registration |
| additional_register.documents | Required documents | المستندات المطلوبة | auth | Auth & registration |
| additional_register.add_document | Add another document | إضافة مستند آخر | auth | Auth & registration |
| register.phone | Phone field | رقم الهاتف | auth | Auth & registration |
| register.dob | Date of birth | تاريخ الميلاد | auth | Auth & registration |
| register.role | Role picker | اختيار الدور | auth | Auth & registration |
| register.password_strength | Password strength | قوة كلمة المرور | auth | Auth & registration |
| register.password_requirements | Password requirements | متطلبات كلمة المرور | auth | Auth & registration |
| register.login_link | Login link | رابط تسجيل الدخول | auth | Auth & registration |
| categories.search | Categories search | بحث التصنيفات | home | Home & browsing |
| categories.chips | Category chips | شريط التصنيفات | home | Home & browsing |
| categories.section_header | Section header | عنوان القسم | home | Home & browsing |
| categories.side_list | Category side list | قائمة الأقسام الجانبية | home | Home & browsing |
| categories.courses | Category courses | كورسات التصنيف | home | Home & browsing |
| course_row | Courses row | صف الكورسات | courses | Courses |
| course_card | Course card | بطاقة الكورس | courses | Courses |
| course_card.thumbnail | Card thumbnail | صورة الكورس | courses | Courses |
| course_card.rating | Card rating | تقييم الكورس | courses | Courses |
| course_card.meta | Lectures & hours | المحاضرات والساعات | courses | Courses |
| course_card.students | Students & certificates | الطلاب والشهادات | courses | Courses |
| course_card.progress | Progress bar | شريط التقدم | courses | Courses |
| course_card.description | Short description | وصف مختصر | courses | Courses |
| course_card.instructor | Card instructor | المحاضر في البطاقة | courses | Courses |
| course_card.category | Category tag | تصنيف الكورس | courses | Courses |
| course_card.publish_status | Publish status | حالة النشر | courses | Courses |
| course_card.type_badge | Course type badge | نوع الكورس | courses | Courses |
| course_card.favorite | Favorite button | زر المفضلة | courses | Courses |
| course_card.discount | Card discount ribbon & countdown | الخصم في البطاقة | courses | Courses |
| course_card.private_flag | Private flag | كورس خاص | courses | Courses |
| course_card.price | Card price badge | سعر البطاقة | courses | Courses |
| course.price | Course price | سعر الكورس | courses | Courses |
| course.discount_ribbon | Discount ribbon | شريط الخصم | courses | Courses |
| course.discount_countdown | Discount end text | نص انتهاء الخصم | courses | Courses |
| course_details.schedule | Weekly schedule | الجدول الأسبوعي | courses | Courses |
| course_details.prerequisites | Prerequisites | المتطلبات السابقة | courses | Courses |
| course_details.tools | Required tools | الأدوات المطلوبة | courses | Courses |
| course_details.certificates | Course certificates | شهادات الكورس | courses | Courses |
| course.rules | Course rules | قواعد الكورس | courses | Courses |
| course.sections | Course sections (groups) | سكاشن الكورس (المجموعات) | courses | Courses |
| course.attendance_flag | Attendance on/off for a course and its sessions | تشغيل الحضور وإيقافه للكورس والجلسات | courses | Courses |
| roadmap.next_steps | Next steps | الخطوات التالية | courses | Courses |
| roadmap.teacher_picks | Teacher picks | ترشيحات المعلم | courses | Courses |
| roadmap.similar | Similar courses | كورسات مشابهة | courses | Courses |
| roadmap.course_card | Roadmap course card | بطاقة كورس المسار | courses | Courses |
| roadmap.path | Learning path | مسار التعلم | courses | Courses |
| roadmap.explore_more | Explore more | استكشف المزيد | courses | Courses |
| roadmap.recommendations | Recommended for you | مقترح لك (التوصيات) | courses | Courses |
| roadmap.journey | Home journey card | بطاقة رحلتك في الرئيسية | courses | Courses |
| roadmap.next_notice | "Your next step is ready" notice | إشعار «خطوتك التالية جاهزة» | courses | Courses |
| admin.recommendations | Recommendations settings & numbers | إعدادات التوصيات وأرقامها | admin | Administration & custom keys |
| notifications.today | Today notifications | إشعارات اليوم | support | Support & info |
| notifications.yesterday | Yesterday notifications | إشعارات الأمس | support | Support & info |
| notifications.mark_all_read | Mark all as read | تعليم الكل كمقروء | support | Support & info |
| about | About screen | من نحن | support | Support & info |
| about.hero | About hero banner | بانر التعريف | support | Support & info |
| about.mission | Our mission | رسالتنا | support | Support & info |
| about.stats | About stats | إحصائيات | support | Support & info |
| about.features | Features | ما يميزنا | support | Support & info |
| about.team | Team | فريقنا | support | Support & info |
| about.contact | Contact us | تواصل معنا | support | Support & info |
| terms | Terms screen | الشروط والأحكام | support | Support & info |
| terms.header | Terms header | عنوان الشروط | support | Support & info |
| terms.sections | Terms sections | أقسام الشروط | support | Support & info |
| terms.footer | Terms footer | تذييل الشروط | support | Support & info |
| terms.privacy | Privacy policy page | صفحة سياسة الخصوصية | support | Support & info |
| terms.links | Privacy & terms links on the sign-in screens | روابط الخصوصية والشروط في شاشات الدخول | support | Support & info |
| complaints.stats | Complaints stats | إحصائيات الشكاوى | support | Support & info |
| complaints.filters | Complaints search & filters | بحث وفلاتر الشكاوى | support | Support & info |
| complaints.attachments | Complaint attachments | مرفقات الشكاوى | support | Support & info |
| complaint_detail | Complaint details screen | تفاصيل الشكوى | support | Support & info |
| complaint_detail.info | Complaint info card | بيانات الشكوى | support | Support & info |
| complaint_detail.replies | Complaint replies | ردود الشكوى | support | Support & info |
| complaint_detail.reply_input | Reply input | كتابة رد | support | Support & info |
| new_complaint.category | Complaint category | تصنيف الشكوى | support | Support & info |
| new_complaint.priority | Complaint priority | أولوية الشكوى | support | Support & info |
| new_complaint.attachments | New complaint attachments | مرفقات الشكوى الجديدة | support | Support & info |
| new_complaint.suggested_solution | Suggested solution | الحل المقترح | support | Support & info |
| instructor.avatar | Instructor avatar | صورة المحاضر | courses | Courses |
| instructor.profile_card | Instructor card | بطاقة المحاضر | courses | Courses |
| instructor.stats | Instructor stats | إحصائيات المحاضر | courses | Courses |
| instructor.badges | Instructor badges | شارات المحاضر | courses | Courses |
| instructor.about | Instructor about | نبذة عن المحاضر | courses | Courses |
| instructor.documents | Instructor documents | مستندات المحاضر | courses | Courses |
| instructor.rating | Instructor rating | تقييم المحاضر | courses | Courses |
| instructor.contact | Instructor contact | تواصل مع المحاضر | courses | Courses |
| instructor.teacher_stats | Teaching stats | إحصائيات التدريس | courses | Courses |
| profile.header | Profile header | رأس الملف الشخصي | profile | Profile |
| complaints | Complaints | الشكاوى | support | Support & info |
| new_complaint | New complaint | شكوى جديدة | support | Support & info |
| live_sessions | Live sessions | الحصص المباشرة | live | Live sessions |
| screen_share | Screen sharing | مشاركة الشاشة | live | Live sessions |
| session_recording | Session recording | تسجيل الحصص | live | Live sessions |
| exams | Exams | الامتحانات | learning | Learning & assessment |
| certificates | Certificates | الشهادات | learning | Learning & assessment |
| rewards | Rewards | المكافآت | learning | Learning & assessment |
| analytics | Analytics | التحليلات | learning | Learning & assessment |
| enrollment | Enrollment | الاشتراك في الكورسات | payments | Payments & subscriptions |
| payments | Payments | المدفوعات | payments | Payments & subscriptions |
| payments.card | Card payment | الدفع بالبطاقة | payments | Payments & subscriptions |
| payments.transfer | Manual transfer | التحويل اليدوي | payments | Payments & subscriptions |
| admin.payouts | Payouts | سحب الأرباح | payments | Payments & subscriptions |
| admin.fee_policy | Fee policy (admin) | سياسة الرسوم (للإدارة) | payments | Payments & subscriptions |
| course_form.privacy | Course privacy (public/private + code) | خصوصية الكورس (عام/خاص) | courses | Courses |
| course_form.currency | Course currency selector | اختيار عملة الكورس | courses | Courses |
| course_form.audience | Who the course is for / where (levels, delivery, place) | لمن هذا الكورس وأين (المراحل والحضور والمكان) | courses | Courses |
| course_form.recommended_courses | Recommended courses field | كورسات مقترحة | courses | Courses |
| course_form.progress_status | Course progress status (in progress / completed) | حالة تقدم الكورس | courses | Courses |
| course_form.next_courses | Roadmap next courses field | الكورسات التالية في المسار | courses | Courses |
| course_form.reel | Course intro reel upload | فيديو تعريفي للكورس | courses | Courses |
| analytics_hub.header | Teacher analytics header | رأس تحليلات المعلم | learning | Learning & assessment |
| analytics_hub.search | Teacher analytics search | بحث تحليلات المعلم | learning | Learning & assessment |
| analytics_hub.attendance | Teacher analytics: attendance button | زر الحضور في تحليلات المعلم | learning | Learning & assessment |
| analytics_hub.exams | Teacher analytics: exams button | زر الاختبارات في تحليلات المعلم | learning | Learning & assessment |
| teacher_home | Teacher home screen | الشاشة الرئيسية للمعلم | teacher | Teacher tools |
| teacher_home_topbar | Teacher home top bar | الشريط العلوي للمعلم | teacher | Teacher tools |
| teacher_home_stats | Teacher home stats | إحصائيات الرئيسية (معلم) | teacher | Teacher tools |
| teacher_home_add_course | Teacher home add-course button | زر إضافة دورة | teacher | Teacher tools |
| teacher_home_courses_header | Teacher home courses header | عنوان كورسات المعلم | teacher | Teacher tools |
| teacher_home_courses_row | Teacher home courses row | صف كورسات المعلم | teacher | Teacher tools |
| teacher_home_schedule | Teacher home schedule | جدول المعلم في الرئيسية | teacher | Teacher tools |
| teacher_tab_home | Teacher tab: Home | تبويب الرئيسية (المعلم) | teacher | Teacher tools |
| teacher_tab_my_courses | Teacher tab: My courses | تبويب كورساتي (المعلم) | teacher | Teacher tools |
| teacher_tab_my_schedule | Teacher tab: Schedule | تبويب الجدول (المعلم) | teacher | Teacher tools |
| teacher_tab_analysis | Teacher tab: Analysis | تبويب التحليل (المعلم) | teacher | Teacher tools |
| teacher_tab_my_profile | Teacher tab: Profile | تبويب الملف الشخصي (المعلم) | teacher | Teacher tools |
| student_tab_home | Student tab: Home | تبويب الرئيسية (الطالب) | home | Home & browsing |
| student_tab_my_courses | Student tab: My courses | تبويب كورساتي (الطالب) | home | Home & browsing |
| student_tab_my_schedule | Student tab: Schedule | تبويب الجدول (الطالب) | home | Home & browsing |
| student_tab_analysis | Student tab: Analysis | تبويب التحليل (الطالب) | home | Home & browsing |
| student_tab_my_profile | Student tab: Profile | تبويب الملف الشخصي (الطالب) | home | Home & browsing |
| student_tab_store | Student tab: Store | تبويب المتجر (الطالب) | home | Home & browsing |
| student_tab_games | Student tab: Games | تبويب الألعاب التعليمية (الطالب) | home | Home & browsing |
| student_tab_quran | Student tab: Quran | تبويب القرآن والتحفيظ (الطالب) | home | Home & browsing |
| student_tab_nahw | Student tab: Grammar (nahw) | تبويب النحو (الطالب) | home | Home & browsing |
| teacher_courses | Teacher courses screen | شاشة كورسات المعلم | teacher | Teacher tools |
| teacher_courses.add | Add course button | زر إضافة كورس | teacher | Teacher tools |
| teacher_courses.classroom | My students, submissions and reviews | طلابي والتسليمات والتقييمات | teacher | Teacher tools |
| teacher_courses.search | Teacher courses search | بحث كورسات المعلم | teacher | Teacher tools |
| teacher_courses.filters | Teacher courses filters | فلاتر كورسات المعلم | teacher | Teacher tools |
| teacher_courses.pagination | Teacher courses pagination | ترقيم صفحات الكورسات | teacher | Teacher tools |
| teacher_courses.card_stats | Course card stats | إحصائيات بطاقة الكورس | teacher | Teacher tools |
| teacher_courses.card_details | Course card details toggle | تفاصيل بطاقة الكورس | teacher | Teacher tools |
| teacher_courses.edit | Course edit button | زر تعديل الكورس | teacher | Teacher tools |
| teacher_courses.publish | Course publish button | زر نشر الكورس | teacher | Teacher tools |
| teacher_courses.delete | Course delete button | زر حذف الكورس | teacher | Teacher tools |
| teacher_attendance | Teacher attendance screen | شاشة حضور الطلاب | teacher | Teacher tools |
| teacher_attendance.session_flag | Attendance session flag bar | شريط حالة الجلسة | teacher | Teacher tools |
| teacher_attendance.stats | Attendance stats | إحصائيات الحضور | teacher | Teacher tools |
| teacher_attendance.search | Attendance student search | بحث الطلاب في الحضور | teacher | Teacher tools |
| teacher_attendance.save_bar | Attendance save bar | شريط حفظ الحضور | teacher | Teacher tools |
| certificates.template | Certificate template pane | قالب الشهادة | learning | Learning & assessment |
| certificates.students | Certificate students pane | طلاب الشهادة | learning | Learning & assessment |
| certificates.engine | New certificate studio (unified design engine) | استوديو الشهادات الجديد (محرك التصميم الموحد) | learning | Learning & assessment |
| certificates.standalone | Standalone certificate issuing (list or sheet) | إصدار شهادات بدون كورس (قائمة أو ملف) | learning | Learning & assessment |
| certificates.verify | Certificate verification (the in-app entry points) | التحقق من الشهادات (زر الدخول داخل التطبيق) | learning | Learning & assessment |
| teacher_exams_hub | Teacher exams hub screen | شاشة اختبارات المعلم | teacher | Teacher tools |
| course_form | Course add/edit screen | شاشة إضافة/تعديل الكورس | courses | Courses |
| course_form.basic_info | Course basic info card | بطاقة المعلومات الأساسية للكورس | courses | Courses |
| course_form.publish_status | Course publish status card | بطاقة حالة نشر الكورس | courses | Courses |
| course_form.advanced | Course form: advanced settings | الإعدادات المتقدمة للكورس | courses | Courses |
| course_form.relations | Course roadmap & recommendations | مسار الكورس والترشيحات | courses | Courses |
| course_form.optional | Course form: optional extras | إضافات الكورس الاختيارية | courses | Courses |
| course_form.certificate_template | Course certificate template card | بطاقة قالب شهادة الكورس | courses | Courses |
| course_form.course_type | Course type selector (live/recorded) | نوع الكورس (مباشر/مسجل) | courses | Courses |
| favorites | Favorites screen | شاشة المفضلة | home | Home & browsing |
| favorites.search | Favorites search | بحث المفضلة | home | Home & browsing |
| favorites.list | Favorites list | قائمة المفضلة | home | Home & browsing |
| subscription.plans | Subscription plans | خطط الاشتراك | payments | Payments & subscriptions |
| subscription.payment_method | Subscription payment method | طريقة دفع الاشتراك | payments | Payments & subscriptions |
| subscription.transfer_details | Subscription transfer details | بيانات تحويل الاشتراك | payments | Payments & subscriptions |
| subscription.sender_info | Subscription sender info | بيانات مرسل التحويل | payments | Payments & subscriptions |
| subscription.receipt | Subscription receipt upload | إرفاق إيصال الاشتراك | payments | Payments & subscriptions |
| subscription.logout | Subscription logout button | زر تسجيل الخروج في الاشتراك | payments | Payments & subscriptions |
| upload_queue | Upload progress footer | شريط تقدم الرفع | teacher | Teacher tools |
| analytics.header | Analytics header | رأس صفحة التحليلات | learning | Learning & assessment |
| analytics.search | Analytics course search | بحث كورسات التحليلات | learning | Learning & assessment |
| analytics.attendance_chip | Attendance shortcut | اختصار الحضور | learning | Learning & assessment |
| analytics.exams_chip | Exams shortcut | اختصار الاختبارات | learning | Learning & assessment |
| attendance | Attendance widget | ودجت الحضور | learning | Learning & assessment |
| attendance.record | Attendance record details | تفاصيل سجل الحضور | learning | Learning & assessment |
| attendance.action | Check-in / check-out button | زر تسجيل الحضور والمغادرة | learning | Learning & assessment |
| exam_frozen | Frozen exam screen | شاشة الاختبار المجمّد | learning | Learning & assessment |
| exam_frozen.score | Frozen exam score summary | ملخص نتيجة الاختبار المجمّد | learning | Learning & assessment |
| exam_frozen.meta | Frozen exam details | تفاصيل الاختبار المجمّد | learning | Learning & assessment |
| sessions.progress | Sessions progress banner | شريط تقدم الدروس | learning | Learning & assessment |
| sessions.card | Session card | بطاقة الدرس | learning | Learning & assessment |
| sessions.exam_banner | Session exam banner | شريط اختبار الدرس | learning | Learning & assessment |
| course_hero.topbar | Course hero top bar | الشريط العلوي لغلاف الكورس | courses | Courses |
| course_hero.category | Course hero category | تصنيف غلاف الكورس | courses | Courses |
| course_hero.private | Course hero private flag | علامة الكورس الخاص | courses | Courses |
| course_hero.description | Course hero description | وصف غلاف الكورس | courses | Courses |
| course_hero.teacher | Course hero teacher chip | المحاضر في غلاف الكورس | courses | Courses |
| course_hero.stats | Course hero stats strip | إحصائيات غلاف الكورس | courses | Courses |
| course_hero.progress | Course hero progress ring | دائرة تقدم الكورس | courses | Courses |
| course_hero.reel | Course reel video | فيديو تعريفي بالكورس | courses | Courses |
| course_tabs.about | Course About tab | تبويب نبذة الكورس | courses | Courses |
| course_tabs.lessons | Course Lessons tab | تبويب الدروس | courses | Courses |
| courses_list | Courses list screen | شاشة قائمة الكورسات | courses | Courses |
| courses_list.search | Courses list search | بحث قائمة الكورسات | courses | Courses |
| courses_list.list | Courses list | قائمة الكورسات | courses | Courses |
| my_courses | My courses screen | شاشة كورساتي | courses | Courses |
| my_courses.stats | My courses stats | إحصائيات كورساتي | courses | Courses |
| my_courses.search | My courses search | بحث كورساتي | courses | Courses |
| my_courses.filters | My courses filter tabs | فلاتر كورساتي | courses | Courses |
| my_courses.list | My courses list | قائمة كورساتي | courses | Courses |
| payment_callback | Payment result screen | شاشة نتيجة الدفع | payments | Payments & subscriptions |
| payment_callback.try_again | Payment retry button | زر إعادة محاولة الدفع | payments | Payments & subscriptions |
| roadmap_enroll.intro | Roadmap enrollment summary | ملخص الاشتراك في المسار | payments | Payments & subscriptions |
| roadmap_enroll.items | Roadmap enrollment courses | كورسات الاشتراك في المسار | payments | Payments & subscriptions |
| roadmap_enroll.fees | Roadmap enrollment fees | رسوم الاشتراك في المسار | payments | Payments & subscriptions |
| student_home | Student home screen | الشاشة الرئيسية للطالب | home | Home & browsing |
| student_home.top_bar | Student home top bar | الشريط العلوي (الطالب) | home | Home & browsing |
| student_home.search | Student home search | البحث في الرئيسية (الطالب) | home | Home & browsing |
| student_home.upcoming_banner | Upcoming session banner | بانر الحصة القادمة | home | Home & browsing |
| student_home.category | Upcoming session banner | الفئات عند الطالب | home | Home & browsing |
| student_home.courses | Courses in student Home | دوات الطالب في الصفحة الرئسية | home | Home & browsing |
| student_home.other_courses | Other Courses in student Home | الدورات الاخري في الصفحة الرئسية | home | Home & browsing |
| student_home.best_teachers | Best teachers row | أفضل المعلمين | home | Home & browsing |
| transfer_requests | Transfer payment requests screen | شاشة طلبات الدفع بالتحويل | payments | Payments & subscriptions |
| transfer_requests.hint | Swipe hint banner | تلميح السحب للقبول/الرفض | payments | Payments & subscriptions |
| transfer_requests.proof_image | Transfer proof image | صورة إيصال التحويل | payments | Payments & subscriptions |
| transfer_requests.actions | Transfer accept/reject buttons | أزرار قبول/رفض التحويل | payments | Payments & subscriptions |
| teacher_payouts | Teacher earnings & payouts screen | شاشة أرباح وسحوبات المعلم | payments | Payments & subscriptions |
| teacher_payouts.balance | Balance card | بطاقة الرصيد | payments | Payments & subscriptions |
| teacher_payouts.request | Request withdrawal button | زر طلب سحب | payments | Payments & subscriptions |
| teacher_payouts.accounts | Payout accounts section | حسابات السحب | payments | Payments & subscriptions |
| teacher_payouts.withdrawals | Withdrawals history | سجل عمليات السحب | payments | Payments & subscriptions |
| device_requests | Device switch requests screen | شاشة طلبات تغيير الجهاز | teacher | Teacher tools |
| device_requests.hint | Device requests swipe hint | تلميح السحب (الأجهزة) | teacher | Teacher tools |
| device_requests.limit_note | Monthly limit note | ملاحظة الحد الشهري | teacher | Teacher tools |
| device_requests.actions | Device approve/reject buttons | أزرار موافقة/رفض الجهاز | teacher | Teacher tools |
| schedule.week_strip | Schedule week strip | شريط أيام الأسبوع | learning | Learning & assessment |
| schedule.next_banner | Schedule next-lesson banner | بانر المحاضرة القادمة | learning | Learning & assessment |
| teacher_schedules | Teacher course schedules screen | شاشة مواعيد الكورس (المعلم) | teacher | Teacher tools |
| teacher_schedules.info_banner | Schedules repeat info banner | بانر تكرار المواعيد | teacher | Teacher tools |
| teacher_schedules.add | Add schedule button | زر إضافة موعد | teacher | Teacher tools |
| course_stats | Teacher course stats bar | شريط إحصائيات الكورس (المعلم) | courses | Courses |
| course_stats.students | Stats: students | عدد الطلاب | courses | Courses |
| course_stats.sessions | Stats: sessions | عدد الحصص | courses | Courses |
| course_stats.price | Stats: price | سعر الكورس (إحصائيات) | courses | Courses |
| course_stats.duration | Stats: duration | مدة الكورس (إحصائيات) | courses | Courses |
| course_stats.rating | Stats: rating | تقييم الكورس (إحصائيات) | courses | Courses |
| teacher_sessions | Teacher course sessions screen | شاشة حصص الكورس (المعلم) | teacher | Teacher tools |
| teacher_sessions.hero | Teacher course hero | غلاف الكورس (المعلم) | teacher | Teacher tools |
| teacher_sessions.rating | Teacher course rating | تقييم الكورس (المعلم) | teacher | Teacher tools |
| teacher_sessions.progress | Teacher course progress | تقدم الكورس (المعلم) | teacher | Teacher tools |
| teacher_sessions.header | Sessions list header | عنوان قائمة الحصص | teacher | Teacher tools |
| teacher_sessions.add_button | Add session button | زر إضافة حصة | teacher | Teacher tools |
| teacher_sessions.list | Sessions list | قائمة الحصص | teacher | Teacher tools |
| teacher_sessions.empty | No-sessions empty state | حالة عدم وجود حصص | teacher | Teacher tools |
| teacher_sessions.recommendations | Teacher course recommendations | ترشيحات الكورس (المعلم) | teacher | Teacher tools |
| session_form | Session add/edit form | نموذج إضافة/تعديل حصة | teacher | Teacher tools |
| session_form.description | Session description field | وصف الحصة | teacher | Teacher tools |
| session_form.type | Session type selector | نوع الحصة (مباشر/مسجل) | teacher | Teacher tools |
| session_form.live_date | Live session date/time | موعد الحصة المباشرة | teacher | Teacher tools |
| prejoin | Pre-join screen | شاشة ما قبل الانضمام | live | Live sessions |
| prejoin.camera | Pre-join camera card | بطاقة الكاميرا (قبل الانضمام) | live | Live sessions |
| prejoin.mic | Pre-join microphone card | بطاقة الميكروفون (قبل الانضمام) | live | Live sessions |
| live_room.status_badges | Session clock & recording badges | شارات الوقت والتسجيل | live | Live sessions |
| live_room.participants_badge | Participants count badge | عداد المشاركين | live | Live sessions |
| live_room.pip | Picture-in-picture camera | نافذة الكاميرا الصغيرة | live | Live sessions |
| live_room.quiz | Live quiz overlay | الاختبار السريع المباشر | live | Live sessions |
| live_room.mic | Mic button | زر الميكروفون | live | Live sessions |
| live_room.camera | Camera button | زر الكاميرا | live | Live sessions |
| live_room.flip_camera | Flip camera button | زر قلب الكاميرا | live | Live sessions |
| live_room.speaker | Speakerphone button | زر السماعة | live | Live sessions |
| live_room.audio_output | Audio output picker | اختيار مخرج الصوت | live | Live sessions |
| live_room.pause_recording | Pause/resume recording button | زر إيقاف/استئناف التسجيل | live | Live sessions |
| live.guest_link | Live session guest link | رابط انضمام الضيوف للبث المباشر | live | Live sessions |
| live.share_link | Live room share link (session or meeting) | مشاركة رابط الغرفة المباشرة (حصة أو اجتماع) | live | Live sessions |
| live.lobby | Live room lobby (admit people before they enter) | غرفة الانتظار: قبول المنضمين قبل الدخول | live | Live sessions |
| live.meeting_recording | Record a meeting to a cloud drive (Google Drive / OneDrive) | تسجيل الاجتماع إلى السحابة (Google Drive / OneDrive) | live | Live sessions |
| live.quick_meeting | Quick meeting (Meet now) | اجتماع سريع («اجتمع الآن») | live | Live sessions |
| live.meeting_links | Meeting links (every session and meeting link on one page) | روابط الاجتماعات (كل روابط الحصص والاجتماعات في صفحة واحدة) | live | Live sessions |
| share.links | Share links (course · lesson · session · meeting · path · page) | مشاركة الروابط (كورس · درس · حصة · اجتماع · مسار · صفحة) | admin | Administration & custom keys |
| teacher.quick_live | Teacher home: Go live button | زر «ابدأ البث» في رئيسية المعلم | admin | Administration & custom keys |
| live.teacher_controls | Host controls over participants (mute · remove · allow screen share) | تحكم المضيف بالمشاركين (كتم · إخراج · السماح بمشاركة الشاشة) | live | Live sessions |
| live.room_lock | Lock the live room to new joins | قفل الغرفة المباشرة أمام المنضمين الجدد | live | Live sessions |
| live.companion | Use a phone as camera, microphone or speaker in a live room | استخدام الهاتف ككاميرا أو ميكروفون أو سماعة أثناء الجلسة | live | Live sessions |
| live.host_handover | Hand a meeting's host controls to someone when leaving | تسليم إدارة الاجتماع لمشارك آخر عند المغادرة | live | Live sessions |
| live.annotation | Annotation (draw) on a shared screen | التعليق التوضيحي (الرسم) على الشاشة المشتركة | live | Live sessions |
| live.whiteboard | Whiteboard | السبورة البيضاء | live | Live sessions |
| live.share_requests | Ask to share the screen in a live room (the host accepts or declines) | طلب مشاركة الشاشة في البث المباشر (يوافق المضيف أو يرفض) | live | Live sessions |
| profile.points | Points wallet and the live-meeting plan | محفظة النقاط وباقة الاجتماعات المباشرة | payments | Payments & subscriptions |
| admin.edu_levels | Education levels, subjects and areas (admin) | المراحل والصفوف والمواد والمناطق (للإدارة) | admin | Administration & custom keys |
| admin.points | Points and top-up requests (admin) | إدارة النقاط وطلبات الشحن | payments | Payments & subscriptions |
| store.buy | Buying from the store | الشراء من المتجر | admin | Administration & custom keys |
| store.points | Paying with points in the store | الشراء من المتجر بالنقاط | admin | Administration & custom keys |
| store.manage | Managing store items | إدارة عناصر المتجر | admin | Administration & custom keys |
| admin.store | Store review and orders (admin) | مراجعة المتجر وطلباته (للإدارة) | admin | Administration & custom keys |
| games.rewards | Points rewards for games | نقاط مكافآت الألعاب | learning | Learning & assessment |
| quran.teacher_apply | Quran teachers applying (profile) | تقديم معلم القرآن لملفه | learning | Learning & assessment |
| admin.nahw | Grammar (nahw) content editor (admin) | محرر محتوى النحو (للإدارة) | admin | Administration & custom keys |
| admin.modules | Module settings per country and organization (admin) | إعدادات الوحدات حسب الدولة والمؤسسة (للإدارة) | admin | Administration & custom keys |
| sync.offline | Offline work, synced later | العمل دون اتصال ومزامنة التقدّم لاحقاً | learning | Learning & assessment |
| calendar.entry | Calendar entry | مدخل التقويم | learning | Learning & assessment |
| calendar.recurring | Recurring meetings | الاجتماعات المتكررة | learning | Learning & assessment |
| profile.cloud_drives | Connected drives (settings) | الحسابات السحابية المرتبطة (الإعدادات) | profile | Profile |
| profile.records | Records: my meeting recordings and their edits (profile) | التسجيلات: تسجيلات اجتماعاتي وتعديلها (حسابي) | profile | Profile |
| records.share | Share recordings (people, a link or guests by e-mail) | مشاركة التسجيلات مع أشخاص أو برابط أو ضيوف بالبريد | admin | Administration & custom keys |
| materials.studio | Studio on session video materials (teacher) | الاستوديو على فيديوهات مواد الحصص (المعلم) | admin | Administration & custom keys |
| course_students.nudge | Nudge low-progress course students (and their parents) | تذكير الطلاب المتأخرين في المقرر (وأولياء أمورهم) | admin | Administration & custom keys |
| materials.guest_link | Share a lesson video with guests by link (no account) | مشاركة فيديو الدرس مع ضيوف برابط (بلا حساب) | admin | Administration & custom keys |
| admin_versions | App versions screen | شاشة إصدارات التطبيق | admin | Administration & custom keys |
| admin_versions.publish | Publish version button | زر نشر إصدار | admin | Administration & custom keys |
| get_app.banner | "Get the app" banner (web) | شريط «تحميل التطبيق» على الويب | support | Support & info |
| get_app.entry | "Get the app" row in profile / settings | خيار «تحميل التطبيق» في الملف الشخصي والإعدادات | support | Support & info |
| app.update_prompt | "New version available" prompt on launch | تنبيه «يتوفر إصدار جديد» عند فتح التطبيق | support | Support & info |
| google_auth | Sign in with Google | الدخول بحساب Google | auth | Auth & registration |
| guest_mode | Explore as a guest (sign-in screen) | التصفح كضيف من شاشة الدخول | auth | Auth & registration |
| join.flow | Landing join flow | مسار الانضمام من الصفحة الرئيسية | home | Home & browsing |
| courses.filters | Course search filters | فلاتر البحث عن الكورسات | home | Home & browsing |
| auth.username | Username (@) at sign-up, in the profile and at sign-in | اسم المستخدم (@) في التسجيل والملف الشخصي والدخول | auth | Auth & registration |
| admin.username_stats | Username numbers (admin) | إحصاءات أسماء المستخدمين (للإدارة) | admin | Administration & custom keys |
| admin.live_settings | Live performance (admin) | أداء البث المباشر (للإدارة) | admin | Administration & custom keys |
| admin.app_releases | App versions (admin) | إصدارات التطبيق (للإدارة) | admin | Administration & custom keys |
| app.download_banner | App download strip at the top of the website (the current version's files) | شريط تنزيل التطبيق أعلى الموقع (ملفات الإصدار الحالي) | support | Support & info |
| export.studio | Export Studio (design and templates) | استوديو التصدير (تصميم وقوالب) | admin | Administration & custom keys |
| export.schedules | Scheduled exports | التصدير المجدول | admin | Administration & custom keys |
| image.background | Image background removal (on the device) | إزالة خلفية الصور على الجهاز | support | Support & info |
| export.layout_v3 | Export list designer (list, table and cards) with page preview | مصمم قوائم التصدير (قائمة وجدول وبطاقات) مع معاينة الصفحات | admin | Administration & custom keys |
| export.share_links | Expiring export download links | روابط تنزيل مؤقتة للتصدير | admin | Administration & custom keys |
| admin.export_log | Export log (admin) | سجل التصدير (للإدارة) | admin | Administration & custom keys |
| admin.course_students | Course students (admin) | مشتركو الكورسات (للإدارة) | admin | Administration & custom keys |
| admin.landing | Landing page (rate limit and testimonials) | صفحة الهبوط (حدّ الطلبات وآراء الطلاب) | admin | Administration & custom keys |
| admin.course_trash | Deleted courses (admin) | سلة الكورسات المحذوفة (للإدارة) | admin | Administration & custom keys |
| register.organization | Register an institution | تسجيل مؤسسة | auth | Auth & registration |
| home.org_tab | "My organization" tab | تبويب «مؤسستي» | home | Home & browsing |
| mentions | @mentions in announcements, complaints and meetings | الإشارة إلى الأشخاص (@) في الإعلانات والشكاوى والاجتماعات | support | Support & info |
| org.governance | Requests & councils (items, delegation, voting) | الطلبات والمجالس (المعاملات والتفويض والتصويت) | admin | Administration & custom keys |
| org.governance.export_hub | Export Hub (designed PDF / Word / Excel) | مركز التصدير (تصميم PDF / Word / Excel) | admin | Administration & custom keys |
| org.institution | Study system and department catalog (organizations) | نظام الدراسة ودليل الإدارات في المؤسسة | admin | Administration & custom keys |
| org.messages | Organization messages to students | رسائل المؤسسة إلى الطلاب | admin | Administration & custom keys |
| org.messages.must_ack | Must-acknowledge messages (the acknowledge screen) | رسائل الإقرار الإلزامي (شاشة الإقرار) | admin | Administration & custom keys |
| org.insights | Organization insights (attendance, enrollment, completion) | مؤشرات المؤسسة (الحضور والتسجيل والإنجاز) | admin | Administration & custom keys |
| org.search | Quick search in the organization dashboard (Ctrl+K) | البحث السريع في لوحة المؤسسة (Ctrl+K) | admin | Administration & custom keys |
| org.teacher_workspace | Teacher organization workspace (my units and alerts) | مساحة عمل المعلم في المؤسسة (أقسامي وتنبيهاتي) | admin | Administration & custom keys |
| parent.org_view | Child's organization (parent dashboard) | مؤسسة الابن في لوحة ولي الأمر | admin | Administration & custom keys |
| org.invitations | Organization invitations | دعوة الأشخاص إلى المؤسسة | admin | Administration & custom keys |
| org.onboarding | Admissions and appointments (new member files) | القبول والتعيين (ملفات الأعضاء الجدد) | admin | Administration & custom keys |
| org.onboarding.import | Importing member files from Excel | استيراد ملفات الأعضاء من Excel | admin | Administration & custom keys |
| org.onboarding.invite | Inviting applicants to complete their file | دعوة أصحاب الملفات لإكمال بياناتهم | admin | Administration & custom keys |
| org.onboarding.intake | Self-registration link for applicants | رابط التسجيل الذاتي للمتقدمين | admin | Administration & custom keys |
| org.students | Students section and the unified student file | قسم الطلاب وملف الطالب الموحد | admin | Administration & custom keys |
| org.students.status | Student statuses, changes and undo | حالات الطلاب وتغييرها والتراجع عنها | admin | Administration & custom keys |
| org.students.auto | Automatic status rules from results | تطبيق قواعد الحالة تلقائياً من النتائج | admin | Administration & custom keys |
| org.students.asks | Asking the student for data or a meeting | طلب بيانات أو اجتماع من الطالب | admin | Administration & custom keys |
| org.students.missing | Missing-data badge | شارة البيانات الناقصة | admin | Administration & custom keys |
| org.students.rules | Students and study rules settings | إعدادات الطلاب وقواعد الدراسة | admin | Administration & custom keys |
| org.billing_view | Membership fees view (org admin) | رسوم العضوية في المؤسسة (عرض) | admin | Administration & custom keys |
| org.setup_checklist | Organization setup checklist | قائمة إعداد المؤسسة | admin | Administration & custom keys |
| org.advising | Academic advising (organizations) | الإرشاد الأكاديمي في المؤسسة | admin | Administration & custom keys |
| org.advising.warning | Early warning (academic advising) | الإنذار المبكر في الإرشاد الأكاديمي | admin | Administration & custom keys |
| org.advising.analytics | Academic advising analytics and reports | تحليلات الإرشاد الأكاديمي وتقاريره | admin | Administration & custom keys |
| org.advising.outreach | Group messages (academic advising) | الرسائل الجماعية في الإرشاد الأكاديمي | admin | Administration & custom keys |
| admin.org_manage | Edit / delete / transfer organizations (admin) | تعديل المؤسسات وحذفها ونقل إدارتها (للإدارة) | admin | Administration & custom keys |
| student_home.org | Organizations card (student home) | بطاقة المؤسسات في رئيسية الطالب | home | Home & browsing |
| teacher_home_org | Organizations card (teacher home) | بطاقة المؤسسات في رئيسية المعلم | teacher | Teacher tools |
| student_home.inbox | Inbox card (home) | صندوق الوارد في الرئيسية | home | Home & browsing |
| profile.downloads | Downloads | التنزيلات | profile | Profile |
| profile.mfa | Two-step verification | التحقق بخطوتين | profile | Profile |
| auth.biometric | Fingerprint / Face ID sign-in | الدخول بالبصمة / Face ID | auth | Auth & registration |
| profile.public_link | Public profile link (@username) | رابط الملف الشخصي العام (@اسم_المستخدم) | profile | Profile |
| profile.public_stats | Teacher figures on the public profile | إحصاءات المعلم في الملف الشخصي العام | profile | Profile |
| profile.my_profile | My profile (view, edit, who sees what) | ملفي الشخصي (عرض وتعديل ومن يرى ماذا) | profile | Profile |
| profile.display | Display & reading (font, size, zoom) | العرض والقراءة (الخط، الحجم، التكبير) | profile | Profile |
| app.animations | Animations and 3D effects (all accounts) | الحركة والمؤثرات ثلاثية الأبعاد (لكل الحسابات) | profile | Profile |
| profile.parent_link | Parent link | ربط ولي الأمر | profile | Profile |
| profile.my_certificates | Grades and certificates | الدرجات والشهادات | profile | Profile |
| profile.my_payments | Payments and subscriptions | المدفوعات والاشتراكات | profile | Profile |
| profile.certificate_designs | Certificate designs | تصاميم الشهادات | profile | Profile |
| profile.certificate_requests | Certificate requests | طلبات الشهادات | profile | Profile |
| profile.my_ads | My ads | إعلاناتي | profile | Profile |
| profile.payment | Payment methods (admin) | طرق الدفع (الإدارة) | profile | Profile |
| profile.historical_payment | Payments history (admin) | سجل المدفوعات (الإدارة) | profile | Profile |
| profile.app_assistant | App assistant (profile) | مساعد التطبيق في الملف الشخصي | profile | Profile |
| rag.app_assistant | Floating app assistant | زر مساعد التطبيق العائم | support | Support & info |
| rag.assistant | AI assistant (courses & organizations) | المساعد الذكي للمقررات والمؤسسات | support | Support & info |
| rag.qa_admin | Assistant curated Q&A management | إدارة الأسئلة والأجوبة المعتمدة للمساعد | support | Support & info |
| rag.admin | App assistant dashboard | لوحة مساعد التطبيق | support | Support & info |
| rag.learning | Learning from feedback (assistant & question generator) | التعلم من الملاحظات (المساعد ومولّد الأسئلة) | support | Support & info |
| help.info | The Info (i) button on every page | زر المعلومات (i) في كل صفحة | admin | Administration & custom keys |
| admin.help | Help management, guides and exports | إدارة المساعدة والأدلة والتصدير | admin | Administration & custom keys |
| exam.omr | Paper exams with bubble sheets (OMR) | الاختبارات الورقية بالتظليل (OMR) | learning | Learning & assessment |
| exam.identifiers | Exam identifier step and the student's entry dialog | معرّف الطالب في الاختبار وطلب إدخاله | learning | Learning & assessment |
| exam.grade_review | Grade review by camera and mark import from paper | مراجعة الدرجات بالكاميرا واستيراد الدرجات من الورق | learning | Learning & assessment |
| exam.mark_templates | Teacher mark-sheet templates | قوالب أوراق الدرجات الخاصة بالمعلم | learning | Learning & assessment |
| exam.hub | Exams hub (the Exams item in the profile) | مركز الاختبارات (عنصر الاختبارات في الملف الشخصي) | learning | Learning & assessment |
| exam.deliver_email | Send the exam paper by email | إرسال ورقة الاختبار بالبريد الإلكتروني | learning | Learning & assessment |
| exam.results_view | What students see of their result, publish and unpublish | ما يراه الطالب من نتيجته ونشر النتائج وإلغاء نشرها | learning | Learning & assessment |
| exam.paper_designer | Exam paper and cover designer | تصميم ورقة الاختبار والغلاف | learning | Learning & assessment |
| exam.google_forms_import | Import questions from Google Forms | استيراد الأسئلة من Google Forms | learning | Learning & assessment |
| exam.all_exams | All exams page | صفحة كل الاختبارات | learning | Learning & assessment |
| exam.question_void | Cancel a question and recalculate the scores | إلغاء سؤال من الاختبار وإعادة حساب الدرجات | learning | Learning & assessment |
| exam.auto_create | Automatic exam question generation from the course documents | إنشاء أسئلة الاختبار تلقائياً من مستندات المقرر | learning | Learning & assessment |
| exam.bubble | Correct bubble sheets (any sheet) | تصحيح أوراق التظليل (أي ورقة) | learning | Learning & assessment |
| exam.bubble.teach | Teach the platform a new sheet | تعليم المنصة ورقة جديدة | learning | Learning & assessment |
| exam.bubble.key_sheet | Upload a marked sheet as the answer key | رفع ورقة مظللة كمفتاح إجابة | learning | Learning & assessment |
| exam.bubble.from_key | Start a bubble correction from the model answer | بدء تصحيح التظليل من الإجابة النموذجية | learning | Learning & assessment |
| exam.bubble.datalab | Write the marks into Data Lab | كتابة الدرجات في Data Lab | learning | Learning & assessment |
| exam.essay_run | Grade written papers without creating an exam (model answer or rubric) | تصحيح الأوراق المكتوبة دون إنشاء اختبار (إجابة نموذجية أو معايير) | learning | Learning & assessment |
| exam.results.datalab | Write exam results into a Data Lab column | كتابة نتائج الاختبار في عمود من Data Lab | learning | Learning & assessment |
| exam.results.import | Import exam totals from Excel | استيراد درجات الاختبار من Excel | learning | Learning & assessment |
| exam.auto_grade | Automatic grading of written answers (word, short, essay) and remembered teacher decisions | التصحيح التلقائي للإجابات المكتوبة (كلمة، قصيرة، مقال) وحفظ قرارات المعلم | learning | Learning & assessment |
| exam.answer_sheet | Machine-read answer sheet (character boxes and ruled areas) and class lists from a file | ورقة الإجابة المقروءة آليًا (مربعات الحروف والأسطر) وقوائم الطلاب من ملف | learning | Learning & assessment |
| exam.auto_correct | Automatic correction (bubble sheets, scanned sheets, camera marking) | التصحيح التلقائي (أوراق التظليل والأوراق الممسوحة والتصحيح بالكاميرا) | learning | Learning & assessment |
| grades.parent_visibility | What parents see of exam grades | ما يراه ولي الأمر من درجات الاختبارات | learning | Learning & assessment |
| models.admin | AI Models page | صفحة نماذج الذكاء الاصطناعي | admin | Administration & custom keys |
| models.benchmarks | Model benchmarks and the model choice per role | قياس دقة النماذج واختيار نموذج كل دور | admin | Administration & custom keys |
| course_hero.attendance | Attendance in the course header | الحضور في رأس الكورس | courses | Courses |
| course_tabs.analytics | Course "My analytics" tab | تبويب تحليلاتي في الكورس | courses | Courses |
| analytics.marks_chip | Marks chip | شريحة الدرجات | learning | Learning & assessment |
| analytics.review_chip | Review chip | شريحة المراجعة | learning | Learning & assessment |
| analytics.read_flags_chip | Read flags chip | شريحة علامات القراءة | learning | Learning & assessment |
| analytics_hub.read_flags | Read flags (analytics hub) | علامات القراءة في التحليلات | learning | Learning & assessment |
| analytics_hub.data_lab | Data Lab (analytics hub) | مختبر البيانات في التحليلات | learning | Learning & assessment |
| student_analytics.insights | Student analytics insights | رؤى تحليلات الطالب | learning | Learning & assessment |
| data_lab.entry | Data Lab entry | مدخل مختبر البيانات | learning | Learning & assessment |
| data_lab.my_profile | My Data Lab profile | ملفي في مختبر البيانات | learning | Learning & assessment |
| data_lab.admin | Data Lab (admin) | مختبر البيانات (الإدارة) | learning | Learning & assessment |
| teacher_home.todo | Teacher's automatic to-do list | قائمة مهام المعلم التلقائية | teacher | Teacher tools |
| parent.insights | "How is my child doing" (parent home) | لمحة «كيف حال ابني» لولي الأمر | admin | Administration & custom keys |
| parent.message_teacher | Parent messages the child's teacher | مراسلة مدرّس الابن من ولي الأمر | admin | Administration & custom keys |
| chat | Messages (the whole product) | الرسائل (المحادثات كلها) | support | Support & info |
| chat.direct | 1-to-1 chats | المحادثات الفردية | support | Support & info |
| chat.requests | Message requests from people you have no link with | طلبات المحادثة من غير المعارف | support | Support & info |
| chat.course_groups | Course groups | مجموعات المقررات | support | Support & info |
| chat.attachments | Images and files in chats | الصور والملفات في المحادثات | support | Support & info |
| chat.presence | Typing and online status | الكتابة الآن والمتصلون | support | Support & info |
| chat.blocking | Blocking in chats | حظر المحادثات | support | Support & info |
| chat.report | Reporting in chats | الإبلاغ عن المحادثات | support | Support & info |
| chat.push | Push notifications for messages | إشعارات الرسائل | support | Support & info |
| admin.games | Learning games and badges editor (admin) | محرر الألعاب التعليمية والشارات (للإدارة) | admin | Administration & custom keys |
| student_tab_self_learning | Student tab: Self-learning | تبويب التعلم الذاتي (الطالب) | home | Home & browsing |
| admin.self_learning | Self-learning content (admin) | محتوى التعلم الذاتي (للإدارة) | admin | Administration & custom keys |
| games.leaderboard | Games leaderboard | لوحة أوائل الألعاب | learning | Learning & assessment |
| games.champions | Daily and weekly games champions | أبطال الألعاب اليوميون والأسبوعيون | learning | Learning & assessment |
| games.sounds | Game sounds | أصوات الألعاب | learning | Learning & assessment |
| games.templates_v4 | Game templates (levels) | قوالب الألعاب الجديدة (المستويات) | learning | Learning & assessment |
| games.challenges | Friend challenges and class board | تحدّيات الأصدقاء ولوحة الفصل | learning | Learning & assessment |
| games.breaks | Play breaks and study timer | استراحة اللعب ومؤقت المذاكرة | learning | Learning & assessment |
| games.cosmetics | Coins and the character wardrobe | العملات وخزانة الشخصية | learning | Learning & assessment |
| admin.games_content | Games content hub (admin) | مركز محتوى الألعاب (للإدارة) | admin | Administration & custom keys |
| parent.games_summary | Parent's child games summary | ملخص ألعاب الابن لولي الأمر | admin | Administration & custom keys |
| rewards.coupons | Reward discount coupons | قسائم الخصم من المكافآت | learning | Learning & assessment |
| rewards.referral | Inviting friends and its rewards | دعوة الأصدقاء ومكافآتها | learning | Learning & assessment |
| admin.rewards | Rewards, champions and coupons (admin) | إدارة المكافآت والأبطال والقسائم (للإدارة) | admin | Administration & custom keys |
| teacher_onboarding | Teacher profile and approval (documents and review) | ملف المعلم واعتماده (المستندات والمراجعة) | teacher | Teacher tools |
| teacher_discovery | Find a teacher (students) | البحث عن معلم (للطلاب) | teacher | Teacher tools |
| packages | Teacher packages and enrolment | باقات المعلمين والتسجيل فيها | admin | Administration & custom keys |

## 3. Gaps

### 3a. Catalog kill-switch keys in no guide feature (224)

| kill-switch key | label (English) | group |
|---|---|---|
| about | About screen | support |
| about.contact | Contact us | support |
| about.features | Features | support |
| about.hero | About hero banner | support |
| about.mission | Our mission | support |
| about.stats | About stats | support |
| about.team | Team | support |
| additional_register.add_document | Add another document | auth |
| additional_register.bio | Bio | auth |
| additional_register.experience | Experience years | auth |
| additional_register.payment_method | Payment type | auth |
| additional_register.specialization | Specialization | auth |
| additional_register.teaching_style | Teaching style | auth |
| admin.edu_levels | Education levels, subjects and areas (admin) | admin |
| admin.fee_policy | Fee policy (admin) | payments |
| analytics.attendance_chip | Attendance shortcut | learning |
| analytics.exams_chip | Exams shortcut | learning |
| analytics.header | Analytics header | learning |
| analytics.marks_chip | Marks chip | learning |
| analytics.read_flags_chip | Read flags chip | learning |
| analytics.review_chip | Review chip | learning |
| analytics.search | Analytics course search | learning |
| analytics_hub.attendance | Teacher analytics: attendance button | learning |
| analytics_hub.data_lab | Data Lab (analytics hub) | learning |
| analytics_hub.exams | Teacher analytics: exams button | learning |
| analytics_hub.header | Teacher analytics header | learning |
| analytics_hub.read_flags | Read flags (analytics hub) | learning |
| analytics_hub.search | Teacher analytics search | learning |
| attendance.record | Attendance record details | learning |
| categories.chips | Category chips | home |
| categories.courses | Category courses | home |
| categories.search | Categories search | home |
| categories.section_header | Section header | home |
| categories.side_list | Category side list | home |
| certificates.students | Certificate students pane | learning |
| certificates.template | Certificate template pane | learning |
| complaint_detail.info | Complaint info card | support |
| complaint_detail.replies | Complaint replies | support |
| complaint_detail.reply_input | Reply input | support |
| complaints.attachments | Complaint attachments | support |
| complaints.filters | Complaints search & filters | support |
| complaints.stats | Complaints stats | support |
| course.discount_countdown | Discount end text | courses |
| course.discount_ribbon | Discount ribbon | courses |
| course.price | Course price | courses |
| course_card | Course card | courses |
| course_card.category | Category tag | courses |
| course_card.description | Short description | courses |
| course_card.discount | Card discount ribbon & countdown | courses |
| course_card.instructor | Card instructor | courses |
| course_card.meta | Lectures & hours | courses |
| course_card.price | Card price badge | courses |
| course_card.private_flag | Private flag | courses |
| course_card.progress | Progress bar | courses |
| course_card.publish_status | Publish status | courses |
| course_card.rating | Card rating | courses |
| course_card.students | Students & certificates | courses |
| course_card.thumbnail | Card thumbnail | courses |
| course_card.type_badge | Course type badge | courses |
| course_details.certificates | Course certificates | courses |
| course_details.prerequisites | Prerequisites | courses |
| course_details.schedule | Weekly schedule | courses |
| course_details.tools | Required tools | courses |
| course_form.advanced | Course form: advanced settings | courses |
| course_form.audience | Who the course is for / where (levels, delivery, place) | courses |
| course_form.basic_info | Course basic info card | courses |
| course_form.certificate_template | Course certificate template card | courses |
| course_form.course_type | Course type selector (live/recorded) | courses |
| course_form.currency | Course currency selector | courses |
| course_form.next_courses | Roadmap next courses field | courses |
| course_form.optional | Course form: optional extras | courses |
| course_form.privacy | Course privacy (public/private + code) | courses |
| course_form.progress_status | Course progress status (in progress / completed) | courses |
| course_form.publish_status | Course publish status card | courses |
| course_form.recommended_courses | Recommended courses field | courses |
| course_form.relations | Course roadmap & recommendations | courses |
| course_hero.attendance | Attendance in the course header | courses |
| course_hero.category | Course hero category | courses |
| course_hero.description | Course hero description | courses |
| course_hero.private | Course hero private flag | courses |
| course_hero.progress | Course hero progress ring | courses |
| course_hero.reel | Course reel video | courses |
| course_hero.stats | Course hero stats strip | courses |
| course_hero.teacher | Course hero teacher chip | courses |
| course_hero.topbar | Course hero top bar | courses |
| course_row | Courses row | courses |
| course_stats | Teacher course stats bar | courses |
| course_stats.duration | Stats: duration | courses |
| course_stats.price | Stats: price | courses |
| course_stats.rating | Stats: rating | courses |
| course_stats.sessions | Stats: sessions | courses |
| course_stats.students | Stats: students | courses |
| course_tabs.about | Course About tab | courses |
| course_tabs.analytics | Course "My analytics" tab | courses |
| courses_list | Courses list screen | courses |
| courses_list.list | Courses list | courses |
| courses_list.search | Courses list search | courses |
| data_lab.admin | Data Lab (admin) | learning |
| data_lab.my_profile | My Data Lab profile | learning |
| device_requests.actions | Device approve/reject buttons | teacher |
| device_requests.hint | Device requests swipe hint | teacher |
| device_requests.limit_note | Monthly limit note | teacher |
| exam.bubble.key_sheet | Upload a marked sheet as the answer key | learning |
| exam_frozen.meta | Frozen exam details | learning |
| exam_frozen.score | Frozen exam score summary | learning |
| favorites.list | Favorites list | home |
| favorites.search | Favorites search | home |
| games.sounds | Game sounds | learning |
| google_auth | Sign in with Google | auth |
| guest_mode | Explore as a guest (sign-in screen) | auth |
| instructor.about | Instructor about | courses |
| instructor.avatar | Instructor avatar | courses |
| instructor.badges | Instructor badges | courses |
| instructor.contact | Instructor contact | courses |
| instructor.documents | Instructor documents | courses |
| instructor.profile_card | Instructor card | courses |
| instructor.rating | Instructor rating | courses |
| instructor.stats | Instructor stats | courses |
| instructor.teacher_stats | Teaching stats | courses |
| live_room.audio_output | Audio output picker | live |
| live_room.camera | Camera button | live |
| live_room.flip_camera | Flip camera button | live |
| live_room.mic | Mic button | live |
| live_room.participants_badge | Participants count badge | live |
| live_room.pip | Picture-in-picture camera | live |
| live_room.speaker | Speakerphone button | live |
| live_room.status_badges | Session clock & recording badges | live |
| my_courses.filters | My courses filter tabs | courses |
| my_courses.list | My courses list | courses |
| my_courses.search | My courses search | courses |
| my_courses.stats | My courses stats | courses |
| new_complaint.attachments | New complaint attachments | support |
| new_complaint.category | Complaint category | support |
| new_complaint.priority | Complaint priority | support |
| new_complaint.suggested_solution | Suggested solution | support |
| notifications.mark_all_read | Mark all as read | support |
| notifications.today | Today notifications | support |
| notifications.yesterday | Yesterday notifications | support |
| org.students.auto | Automatic status rules from results | admin |
| payment_callback.try_again | Payment retry button | payments |
| prejoin.camera | Pre-join camera card | live |
| prejoin.mic | Pre-join microphone card | live |
| profile | Profile screen | profile |
| profile.about | About | profile |
| profile.account | Account section | profile |
| profile.app_assistant | App assistant (profile) | profile |
| profile.certificate_requests | Certificate requests | profile |
| profile.exit_group | Exit section | profile |
| profile.header | Profile header | profile |
| profile.help_group | Help section | profile |
| profile.settings | Settings section | profile |
| profile.teacher_profile | Teacher profile | teacher |
| register.dob | Date of birth | auth |
| register.login_link | Login link | auth |
| register.password_requirements | Password requirements | auth |
| register.password_strength | Password strength | auth |
| register.phone | Phone field | auth |
| register.role | Role picker | auth |
| rewards | Rewards | learning |
| roadmap.course_card | Roadmap course card | courses |
| roadmap.explore_more | Explore more | courses |
| roadmap.next_steps | Next steps | courses |
| roadmap.similar | Similar courses | courses |
| roadmap.teacher_picks | Teacher picks | courses |
| roadmap_enroll.fees | Roadmap enrollment fees | payments |
| roadmap_enroll.intro | Roadmap enrollment summary | payments |
| roadmap_enroll.items | Roadmap enrollment courses | payments |
| session_form.description | Session description field | teacher |
| session_form.live_date | Live session date/time | teacher |
| session_form.type | Session type selector | teacher |
| sessions.card | Session card | learning |
| sessions.progress | Sessions progress banner | learning |
| student_analytics.insights | Student analytics insights | learning |
| student_home.best_teachers | Best teachers row | home |
| student_home.category | Upcoming session banner | home |
| student_home.courses | Courses in student Home | home |
| student_home.other_courses | Other Courses in student Home | home |
| student_home.top_bar | Student home top bar | home |
| student_home.upcoming_banner | Upcoming session banner | home |
| student_tab_my_profile | Student tab: Profile | home |
| subscription.logout | Subscription logout button | payments |
| subscription.payment_method | Subscription payment method | payments |
| subscription.receipt | Subscription receipt upload | payments |
| subscription.sender_info | Subscription sender info | payments |
| subscription.transfer_details | Subscription transfer details | payments |
| teacher_attendance.save_bar | Attendance save bar | teacher |
| teacher_attendance.search | Attendance student search | teacher |
| teacher_attendance.session_flag | Attendance session flag bar | teacher |
| teacher_attendance.stats | Attendance stats | teacher |
| teacher_courses.card_details | Course card details toggle | teacher |
| teacher_courses.card_stats | Course card stats | teacher |
| teacher_courses.filters | Teacher courses filters | teacher |
| teacher_courses.pagination | Teacher courses pagination | teacher |
| teacher_courses.search | Teacher courses search | teacher |
| teacher_home_add_course | Teacher home add-course button | teacher |
| teacher_home_courses_header | Teacher home courses header | teacher |
| teacher_home_courses_row | Teacher home courses row | teacher |
| teacher_home_schedule | Teacher home schedule | teacher |
| teacher_home_stats | Teacher home stats | teacher |
| teacher_home_topbar | Teacher home top bar | teacher |
| teacher_payouts | Teacher earnings & payouts screen | payments |
| teacher_payouts.accounts | Payout accounts section | payments |
| teacher_payouts.balance | Balance card | payments |
| teacher_payouts.withdrawals | Withdrawals history | payments |
| teacher_schedules | Teacher course schedules screen | teacher |
| teacher_schedules.info_banner | Schedules repeat info banner | teacher |
| teacher_sessions.add_button | Add session button | teacher |
| teacher_sessions.empty | No-sessions empty state | teacher |
| teacher_sessions.header | Sessions list header | teacher |
| teacher_sessions.hero | Teacher course hero | teacher |
| teacher_sessions.list | Sessions list | teacher |
| teacher_sessions.progress | Teacher course progress | teacher |
| teacher_sessions.rating | Teacher course rating | teacher |
| teacher_sessions.recommendations | Teacher course recommendations | teacher |
| teacher_tab_my_profile | Teacher tab: Profile | teacher |
| terms | Terms screen | support |
| terms.footer | Terms footer | support |
| terms.header | Terms header | support |
| terms.sections | Terms sections | support |
| transfer_requests | Transfer payment requests screen | payments |
| transfer_requests.actions | Transfer accept/reject buttons | payments |
| transfer_requests.hint | Swipe hint banner | payments |
| transfer_requests.proof_image | Transfer proof image | payments |
| upload_queue | Upload progress footer | teacher |

### 3b. Guide kill-switch keys missing from the catalog (0)

None.

### 3c. Guide features with no kill-switch key (70)

`sign_in`, `forgot_password`, `guest_browsing`, `guest_search_onboarding`, `dashboard_pins_colors`, `editorial_headings`, `private_course_code`, `keyboard_shortcuts`, `video_player`, `org_course_profile`, `parent_children`, `parent_child_consent`, `parent_reports`, `materials_upload`, `video_captions`, `attendance_start_teacher`, `meetings_create`, `meetings_respond`, `org_my_timetable`, `org_session_changes`, `org_my_exams`, `course_announcements`, `org_announcements`, `org_complaints_member`, `parent_alerts`, `admin_broadcast_message`, `org_dashboard_people`, `org_joining_settings`, `org_departments_roles`, `org_courses_academics`, `org_timetable_generate`, `org_timetable_ladder`, `org_timetable_fix_publish`, `org_timetable_autopilot`, `org_exam_timetable`, `org_forms_regulations`, `org_reports`, `org_settings_sharing`, `registrar_course_registration`, `registrar_academic_record`, `registrar_grade_entry`, `registrar_staff`, `org_exam_risk_feedback`, `documents_library`, `admin_users`, `admin_courses_categories`, `admin_teacher_category_details`, `admin_organizations`, `admin_view_as`, `admin_platform_settings`, `admin_devices_documents`, `admin_data_center`, `admin_parent_links`, `admin_splash_footer`, `confirm_identity`, `live_updates_refresh`, `admin_home`, `home_fold_sections`, `courses_by_side`, `vod_listen_only`, `entity_search`, `list_views_bulk`, `admin_legal_editor`, `admin_ai_controls`, `org_archive_department`, `personal_account`, `account_fee`, `account_approval`, `exam_policy`, `downloads_page`

