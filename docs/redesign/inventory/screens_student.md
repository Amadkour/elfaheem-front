# Inventory: student, booking and subject screens -> Flutter today

Read-only mapping (phase 0). Source: `docs/redesign/SCREENS.md` sections "حجز المادة (booking)", "صفحة المادة (subject)", "الطالب (student)". Paths are under `lib/features/` unless they start with `lib/`. `#` is the design row number in SCREENS.md. "push" means there is no named route: the screen is opened with `Navigator.push` from a tab or a sheet. Student shell: `home/student/dashboard/dashboard_screen.dart` (`/dashboard`, guest allowed), home content `home/student/home_screen.dart` + `core/home/me_home.dart`.

Status: exists = same feature, needs restyle / partial = part exists / missing = new feature / replace = design changes behaviour.

## 1. حجز المادة (booking)

Design: `BookFlow.dc.html` (one component; `BookM*/BookW*` are phone/web artboards of its steps). Today there is NO subject-booking flow: a student opens a course (`CourseDetailScreen`) or a teacher package (`PackagePage`) and enrols/pays there.

| # | Design screen | URL | Flutter file(s) today | Route / entry | Status | Notes |
|---|---|---|---|---|---|---|
| 1-2 | 1. كيف تبي تدرس؟ (عن بعد / حضوري) M+W | `BookM1` / `BookW1` (`BookFlow step=1`) | none. Closest: `teachers/teacher_discovery.dart` (`PackagePage`, delivery filter in `teachers_api.dart` `packages(delivery:)`) | none | missing | New wizard step. Delivery value exists on packages; city/district for حضوري needs server lists (RULES §3). |
| 3-4 | 2. مجموعة ولا فردي M+W | `BookM2` / `BookW2` | none | none | missing | Group (5-10, boys/girls only) vs individual is a new product choice; today a course is one fixed thing. Needs BACKEND groups + gender. |
| 5-6 | 3. أكثر من موعد للمجموعة (grp أ/ب...) M+W | `BookM3g` / `BookW3g` | `courses/course_profile/course_page_models.dart` (course `schedules` list only displayed); `teachers/package_wizard.dart` (teacher side) | none | missing | Student picks one of several fixed weekly groups; seats fill (privacy: show seats left only, never who). |
| 7-8 | 3. موعد واحد للمجموعة M+W | `BookM3one` / `BookW3one` | same as above | none | missing | Single fixed slot: confirm screen variant. |
| 9-10 | 3. الفردي: مواعيد المعلم M+W | `BookM3s` / `BookW3s` | `calendar/calendar_api.dart` + `calendar_meeting.dart` (meetings, `attendees_busy`); org-only `org/advising/adv_appointments.dart`, `adv_availability_page.dart` | none | missing | Teacher availability slots for a personal (non-org) student; advising has the pattern but only in org. |
| 11-12 | 3. الفردي: اقترح أوقاتك M+W | `BookM3p` / `BookW3p` | none | none | missing | Student proposes times, teacher answers (confirm within 24 h); new request model. |
| 13, 15 | 4. المراجعة والدفع M+W | `BookM4` / `BookW4` | `payments/enrollment/enrollment_screen.dart`, `enrollment_widgets.dart`, `checkout_pages.dart`, `payment_flow_provider.dart`, `saved_cards/`, `transfer/`; `payments/points/points_card_checkout.dart` | `CourseDetailScreen` -> enrol; `PendingIntentKind.bookCourse` | partial | Pay methods/VAT/transfer exist. Missing: summary of delivery+group+slot, VAT per country, price ticker. |
| 14, 16 | 4ب. سجّل دخولك (guest only) M+W | `BookM4L` / `BookW4L` | `core/routing/pending_intent.dart`, `guest/guest_link_cta.dart`, `auth/login_screen.dart`, `course_detail_screen.dart` (resume of bookCourse, D-1324) | guest tap on enrol | partial | Guest-then-resume exists; the inline login/register step inside the flow is new. |
| 17-18 | 5. تم الحجز M+W | `BookM5` / `BookW5` | `payments/enrollment/enrollment_screen.dart` (ok/processing/fail states), `checkout_callback.dart` | enrol result | partial | Success state exists; confetti/ink check and "add to calendar" are new. |
| 19-20 | 6. صفحة المادة بعد الاشتراك M+W | `BookM6` / `BookW6` | `courses/course_space/course_space.dart`, `courses/course_profile/course_profile_screen.dart` | `/course-profile` | exists | Same as subject page "بعد الاشتراك" (section 2). |

## 2. صفحة المادة (subject)

Design: `SubjectProfile.dc.html` (one component; props `enrolled`, `live`, `panel=lesson|live|chat|bot|notes|cal`, `ltab=book`, `fs=video|live`, `nmode=pen|type`, `all`). Today the "subject page" is the course: `CourseSpace` (plain-values page) inside `CourseProfileScreen` (tabs: hub, sessions, announcements, path...) and `CourseDetailScreen` (pre-purchase/guest).

| # | Design screen | URL | Flutter file(s) today | Route / entry | Status | Notes |
|---|---|---|---|---|---|---|
| 1-2 | قبل الاشتراك M+W | `SubjMGuest` / `SubjWGuest` (`enrolled=0`) | `courses/student/details/course_detail_screen.dart`, `components/course_detail_parts.dart`, `about.dart`, `course_access_sheet.dart` | `/course-detail` (guest ok), `/c/<id>` share link | partial | Exists as course detail. Missing: book "اضغط على الكتاب" hint, teacher card, Book CTA that starts BookFlow. |
| 3-4 | بعد الاشتراك + حصة مباشرة الحين M+W | `SubjMMain` / `SubjWMain` (`enrolled=1 live=1`) | `courses/course_space/course_space.dart`, `course_overview.dart`, `course_sessions.dart`, `course_profile/course_profile_hub.dart`, `home/student/home_live.dart` | `/course-profile` | partial | Live banner + sessions timeline exist. Design adds subject-wide progress, next class, panel launcher (lesson/live/chat/bot/notes/cal). |
| 5-6 | ابدأ هنا: الدرس الأول M+W | `SubjMLesson` / `SubjWLesson` (`panel=lesson`) | `sessions/material/session_material_widget.dart`, `components/`, `sessions/video/video_player_screen.dart`, `learn_kit/` (lesson quiz) | push from course sessions | partial | Lesson + quiz exist (`Stu1Learn material/player` too); "start here" first-lesson guide and the in-page panel layout are new. |
| 7-8 | الدرس الأول: الكتاب M+W | `SubjMBook` / `SubjWBook` (`ltab=book`) | `sessions/material/session_material_widget.dart` (files/attachments); `store/store_reader.dart` (reader) | push | partial | Book/attachments exist as file lists; an in-lesson book view with page details is new. |
| 9-10 | داخل الحصة المباشرة M+W | `SubjMLive` / `SubjWLive` (`panel=live`) | `live/room/prejoin.dart`, `live/live_room.dart`, `live/live_room_host.dart` (`LiveRoomLayer`), `live/room/room.dart`, `live/room/widgets/*` | `LiveRoomHost.open` | replace | Privacy: student sees "أنت والمعلمة" only: no participant list, count, tiles of classmates, hands/chat authors (`live_participant_controls.dart`, `participant_info.dart`, `live_chat.dart`, `live_hands.dart`). Teacher keeps all. Server enforcement too. |
| 11-12 | راسل المعلمة M+W | `SubjMChat` / `SubjWChat` (`panel=chat`) | `messaging/chat/chat_page.dart` (private DM, `/chat` with `{peer_id, course_id}`), `courses/course_profile/course_profile_announcements.dart` | `/chat` | exists | One-to-one teacher chat exists; embed it as a panel of the subject page. |
| 13-16 | المساعد الذكي + مقفل M+W | `SubjMBot`, `SubjMBotOff`, `SubjWBot`, `SubjWBotOff` (`panel=bot`) | `rag/app_assistant.dart`, `rag/rag_chat_screen.dart`, `rag/chat/assistant_page_context.dart`, `rag/rag_learning_page.dart` | floating assistant; kill switch / quota | partial | Assistant exists (global, context-aware). Missing: per-subject panel scoped to the course, and the "locked" state (teacher/plan switched it off). |
| 17-18 | دفتر المادة M+W | `SubjMNotes` / `SubjWNotes` (`panel=notes`) | none (only `org/advising/adv_notes.dart`, org-side; `records/` is meeting recordings) | none | missing | New per-subject notebook (server storage per student/course). |
| 27-30 | الدفتر: بالقلم / بالكيبورد M+W | `SubjMNotesPen`, `SubjWNotesPen`, `SubjMNotesType`, `SubjWNotesType` | none. Reusable: `live/room/whiteboard/*`, `live/room/annotation/*` (ink canvas), `design/app_canvas.dart` | none | missing | Pen canvas with stylus/finger + text editor; reuse whiteboard stroke code. |
| 19-20 | جدول حصصي: مع حصص المواد الثانية M+W | `SubjMCal` / `SubjWCal` (`panel=cal all=1`) | `calendar/schedule_page.dart`, `schedule_store.dart`, `schedule_parts.dart`, `calendar_screen.dart` (`CalendarStore`, `GET /me/calendar`) | `/calendar` | partial | Whole schedule exists; the subject-scoped view and "all subjects" toggle are new filters. |
| 21-22 | جدول حصصي: حصص المادة بس M+W | `SubjMCal0` / `SubjWCal0` (`panel=cal`) | same as above | `/calendar` | partial | Same, filtered by course id. |
| 23-24 | فيديو الدرس بملء الشاشة M+W | `SubjMFsVideo` / `SubjWFsVideo` (`fs=video`) | `sessions/video/video_player_screen.dart`, `vod_player_parts.dart`, `vod_media_controls.dart`, `fullscreen_web.dart` | push | exists | Restyle player chrome; next-lesson countdown and audio-only (`vod_listen*`) exist. |
| 25-26 | الحصة المباشرة بملء الشاشة M+W | `SubjMFsLive` / `SubjWFsLive` (`fs=live`) | `live/room/room.dart`, `live_focus_chrome.dart`, `live_control_bar.dart` | `LiveRoomHost` | replace | Same privacy change as rows 9-10 (teacher + me only). |

## 3. الطالب (student)

Files: `Stu1Auth`, `Stu1Public`, `Stu1Discover`, `Stu1Learn`, `Stu1Comm`, `Stu2Exams`, `Stu2Store`, `Stu2Games`, `Stu2Quran`, `Stu2Nahw`, `Stu2Teachers`, `Stu2Analysis`, `Stu2Schedule`, `Stu2Money`, `Stu2Profile`, `StuHome`.

| # | Design screen | URL | Flutter file(s) today | Route / entry | Status | Notes |
|---|---|---|---|---|---|---|
| 1 | الرئيسية | `StuHome?screen=home` | `home/student/home_screen.dart`, `dashboard/dashboard_screen.dart`, `home_continue.dart`, `home_journey.dart`, `home_live.dart`, `home_event_rows.dart`, `design/home_kit.dart`, `home_a2.dart` | `/home`, `/dashboard` | exists | One `/me/home` call; home budget test applies. Redo layout to 5-second rules. |
| 2 | التعريف بالتطبيق | `Stu1Auth?screen=onboard` | `onboarding/onboarding_screen.dart`, `onboarding_store.dart`, `start_route.dart` | `/onboarding` | exists | Restyle. |
| 3-4 | وش تبي تتعلّم؟ (ضيف) + اختيار المادة | `Stu1Auth?screen=guestsearch` (+`sheet=subject`) | `onboarding/guest_search_screen.dart`, `explore_entry_page.dart`, `explore_launcher.dart` | `/guest-search`, `/explore` | exists | Subject sheet = category picker. |
| 5-7 | الانضمام 1: مين أنت؟ / 2: الصف / 3: الاسم والجوال | `Stu1Auth?screen=join` (`step=grade`, `step=contact`) | `onboarding/join/join_flow_screen.dart`, `join_steps.dart`, `join_draft.dart`, `join_route.dart` | `JoinFlowScreen` (role/lang args) | exists | Country-of-residence + phone for any country (RULES §3) and Saudi grades/tracks from server per country. |
| 8-10 | تسجيل الدخول / بيانات غلط / بالبصمة | `Stu1Auth?screen=login` (`state=error`, `state=bio`) | `auth/login_screen.dart`, `auth_shell.dart`, `biometric.dart`, `biometric_widgets.dart`, `auth_widgets.dart` | `/login` | exists | Shake-no on error (M15). |
| 11-13 | الدخول بكود ولي الأمر / هذا حسابك؟ / اختر كلمة مرور | `Stu1Auth?screen=kidcode` (`state=found`, `state=pass`) | none for child login. Related (other direction): `parent/student_link_code_screen.dart`, `parent/parent_link_screen.dart`, `parent_link_providers.dart` | none | missing | New: a child account created by the parent logs in with a code, confirms identity, sets a password. Needs BACKEND kid-code endpoints. |
| 14-15 | إنشاء حساب / الشروط باختصار | `Stu1Auth?screen=register` (`sheet=terms`) | `auth/register_screen.dart`, `register_levels_step.dart`, `auth_provider.dart`, `profile/about/about_and_terms_screen.dart` | `/register` | exists | Terms as short sheet. |
| 16 | سؤالين عن دراستك | `Stu1Auth?screen=study` | `auth/register_levels_step.dart`, `profile/study_profile/study_profile_form.dart`, `study_profile_pages.dart` | register step | exists | Restyle. |
| 17-19 | تأكيد الجوال: الرمز / واتساب / اسم المستخدم جاهز | `Stu1Auth?screen=verify` (`mode=link`, `sheet=username`) | `auth/mfa_verify_screen.dart`, `auth/verify_way.dart`, `auth/verified_screen.dart`, `auth/username_confirm.dart`, `auth/username.dart` | `/otp` | exists | WhatsApp link mode = `verify_way.dart`; must work for non-Saudi numbers. |
| 20-21 | نسيت كلمة المرور / كلمة مرور جديدة | `Stu1Auth?screen=forgot` (`step=new`) | `auth/forget_screen.dart` | `/forgot-password` | exists | |
| 22 | رمز الدخول برسالة | `Stu1Auth?screen=mfa` | `auth/mfa.dart`, `mfa_entry.dart`, `mfa_verify_screen.dart` | MFA redirect from `ApiClient` | exists | |
| 23-24 | الحساب قيد المراجعة / يحتاج تعديل | `Stu1Auth?screen=approval` (`state=rejected`) | `auth/account_approval_page.dart`, `admin/admin_account_approval.dart` (admin side) | after login when approval pending | exists | |
| 25 | رسوم تفعيل الحساب | `Stu1Auth?screen=fee` | `auth/account_fee_page.dart`, `admin/admin_account_fee_widgets.dart` | after login | exists | D-1120 sign-up fee. |
| 26-27 | الرئيسية للضيف / سجّل دخولك عشان تكمل | `Stu1Public?screen=guesthome` (`sheet=signin`) | `home/student/dashboard/dashboard_screen.dart` (guestOk), `guest/guest_state.dart`, `guest/guest_link_cta.dart`, `core/routing/pending_intent.dart` | `/dashboard` as guest | exists | Sign-in sheet = guest CTA (`guest_reason_*`). |
| 28 | ضيف: صفحة مقفلة | `Stu1Public?screen=gate` | `guest/guest_link_cta.dart`, `home/student/dashboard/dashboard_screen.dart` (locked tabs) | guest tap | exists | |
| 29 | رابط دورة مشارك | `Stu1Public?screen=share` | `share/share_link_page.dart`, `core/guest_link_visit.dart`, `utils/widget/deep_link_service.dart`, `courses/student/details/components/share_link.dart` | `/c/<id>?ref=` | exists | |
| 30-31 | رابط اجتماع للضيف / بعد الاجتماع | `Stu1Public?screen=liveguest` (`state=after`) | `guest/guest_live_page.dart`, `guest_live_api.dart`, `records/record_guest_page.dart` | guest meeting link | exists | `isGuest` must stay unauthenticated. |
| 32 | الخصوصية والشروط | `Stu1Public?screen=legal` | `profile/about/about_and_terms_screen.dart` (`TermsScreen`), `profile/legal/legal_links.dart` | `/privacy`, `/terms` | exists | |
| 33-34 | دوراتي / فاضية | `Stu1Discover?screen=mycourses` (`empty=1`) | `courses/student/my_courses/my_courses_screen.dart`, `my_courses_provider.dart`, `courses/course_list_card.dart` | student tab | exists | `CourseListCard` is the one card. |
| 35 | استكشف المواد | `Stu1Discover?screen=explore` | `courses/student/list/courses_list_screen.dart`, `home/student/component/category_row.dart`, `courses/category/categories_screen.dart` | student tab | exists | |
| 36-37 | دورات المادة / تصفية الدورات | `Stu1Discover?screen=category` (`sheet=filter`) | `courses/category/categories_screen.dart`, `courses/course_filters.dart`, `course_scope_bar.dart` | push | exists | Filter sheet = `CourseFilterBar`. |
| 38-39 | مسار تعلّمي / اهتماماتي | `Stu1Discover?screen=journey` (`sheet=interests`) | `courses/roadmap/journey_page.dart`, `roadmap_path.dart`, `roadmap_tab.dart` | push (kill switch roadmap) | exists | Interests editing is in `journey_page.dart` / `recommendations.dart`. |
| 40 | مقترح لك | `Stu1Discover?screen=recs` | `courses/roadmap/recommendations.dart` | push | exists | |
| 41 | المفضلة | `Stu1Discover?screen=favs` | `profile/student_favorite_screen.dart` | profile entry | exists | |
| 42 | دروس المادة | `Stu1Learn?screen=sessions` | `courses/course_space/course_sessions.dart`, `course_space.dart`, `courses/student/details/components/session.dart` | `/course-profile` | exists | One sessions timeline. |
| 43-44 | محتوى الدرس واختباره / جرّب مرة ثانية | `Stu1Learn?screen=material` (`exam=retry`) | `sessions/material/session_material_widget.dart`, `components/`, `learn_kit/learn_question.dart`, `learn_result.dart`, `learn_grading.dart`, `courses/student/details/session_exam_gate.dart` | push | exists | |
| 45-47 | مشغّل الدرس / الدرس الجاي بعد 5 ثواني / بالصوت بس | `Stu1Learn?screen=player` (`mode=end`, `mode=audio`) | `sessions/video/video_player_screen.dart`, `vod_listen.dart`, `vod_listen_bar.dart`, `vod_player_parts.dart` | push | exists | Auto-next countdown and listen mode exist (verify the 5 s countdown). |
| 48-49 | دورة خاصة: الكود / كود غلط | `Stu1Learn?screen=code` (`pin=wrong`) | `courses/student/details/course_access_sheet.dart`, `courses/private_flag.dart`, `courses/course_access.dart`, `core/course_access.dart` | course open | exists | M15 shake on wrong code. |
| 50-52 | حضوري / تسجيل الحضور جاري / تم | `Stu1Learn?screen=attend` (`sheet=checkin`, `state=done`) | `attendance/attendance_course_entry.dart`, `attendance_live_screen.dart`, `student_checkin_provider.dart`, `attendance_ui.dart`, `attendance_location.dart`, `offline_attendance_tab.dart`, `relay_*` | course attendance entry | exists | No "system words" (BLE/GPS) in copy. Privacy: no classmates' attendance. |
| 53-54 | قبل دخول الحصة / بانتظار المعلمة | `Stu1Learn?screen=prejoin` (`wait=1`) | `live/room/prejoin.dart`, `prejoin_layout.dart`, `live_lobby_sheets.dart`, `home/student/home_live.dart` | `PreJoinPage` -> `LiveRoomHost.open` | replace | Prejoin shows "الحصة شغّالة" + teacher avatar, no participant count. |
| 55 | تسجيلات حصصي | `Stu1Learn?screen=records` | `records/records_page.dart`, `records_parts.dart`, `records_share.dart`; `home/student/record/` | push | exists | |
| 56-57 | الرسائل / محادثة مع المعلم | `Stu1Comm?screen=chat` (`pane=thread`) | `messaging/chat/chat_page.dart`, `chat_widgets.dart`, `chat_bubble.dart`, `chat_store.dart`, `chat_api.dart` | `/chat` | partial | Restyle; students may only message teachers (not classmates) under privacy rules. |
| 58 | رسالة جديدة | `Stu1Comm?sheet=new` | `messaging/chat/chat_new_message.dart` | chat page | replace | Remove "message anyone": recipient list limited to own teachers/support. |
| 59 | حظر جهة اتصال | `Stu1Comm?sheet=block` | `messaging/chat/chat_sheets.dart`, `/chat/blocks` | `/chat/blocks` | exists | |
| 60 | إعلانات المعلم | `Stu1Comm?pane=thread&conv=ann` | `courses/course_profile/course_profile_announcements.dart`, `chat_*` (course group chat today) | course page / chat | replace | Course group chat becomes a one-way teacher announcements thread; replies go privately to the teacher. Teacher keeps the group view. |
| 61-62 | صندوق الوارد: مطلوب منك / الإشعارات | `Stu1Comm?screen=inbox` (`tab=notif`) | `messaging/inbox/inbox_page.dart`, `unified_inbox.dart`, `messaging/notification/notifications_screen.dart` | `inboxTab` routes | exists | |
| 63-64 | الدعم والشكاوى / شكوى جديدة | `Stu1Comm?screen=complaints` (`newcomplaint`) | `profile/compalints/complaints_hub_page.dart`, `complaints_screen.dart`, `new_complaint_screen.dart` | profile entry | exists | |
| 65-67 | المساعد الذكي / محادثة جديدة / محادثاتك | `Stu1Comm?screen=assistant` (`fresh=1`, `sheet=history`) | `rag/rag_chat_screen.dart`, `rag_chat_sessions.dart`, `app_assistant.dart` | floating assistant | exists | |
| 68-69 | اختباراتي / رمز الاختبار | `Stu2Exams?screen=list` (`sheet=code`) | `exams/legacy/student/student_exam_list_screen.dart`, `student_course_exams_widget.dart`, `exams/exam_open_key.dart`, `exam_open_key_widgets.dart` | student tab / course | exists | Code sheet = open key. |
| 70, 91 | قبل الاختبار: جاهز؟ / تنبيه لما يرجع للتطبيق | `Stu2Exams?screen=consent`, `?q=2&toast=1&screen=take` | `exams/exam_consent_screen.dart`, `exam_integrity.dart`, `exam_integrity_web.dart`, `core/screen_security.dart` | exam start | exists | Return-to-app toast = integrity notice (`exam_notice.dart`). |
| 71-78, 92 | أثناء الاختبار (اختر / صح-خطأ / فراغ / وصّل / رقم / مكتوب+رسم / رفع / آخر سؤال) + تأكيد التسليم | `Stu2Exams?q=0..7&screen=take` (`sheet=submit`) | `exams/exam_taking_screen.dart`, `exam_taking.dart`, `exam_media.dart`, `exams/legacy/student/student_exam_quiz_screen.dart`, `student_exam_detail_screen.dart` | exam open | partial | Question types largely exist (`exam_taking.dart`); verify match, drawing answer, upload answer, "paper" last question. Restyle. |
| 79-82 | النتيجة: نجح / عند المعلم / قرّب / خلصت المحاولات | `Stu2Exams?state=pass|pending|fail|frozen&screen=result` | `exams/exam_result_screen.dart`, `exams/legacy/student/student_exam_result_screen.dart`, `student_exam_frozen_screen.dart`, `exams/hub/result/` | after submit | exists | Pending (held results, D-198) and frozen both exist. |
| 83-84 | طلب مراجعة سؤال / المراجعة عند المعلم | `Stu2Exams?sheet=appeal`, `?appeal=sent` | `exams/exam_result_screen.dart`, `exam_notice.dart`, `exams/marks/review/grade_review_*.dart` | result page | partial | Grade-review exists (`grade_review_screen.dart`); check a per-question appeal sheet on the student result. |
| 85-87 | اختبار بدون نت: نازل / ينتظر النت / وصلت الإجابات | `Stu2Exams?screen=offline` (`state=ready|sealed|sent`) | `exams/offline/offline_exam_screen.dart`, `offline_exam_service.dart`, `offline_exam_core.dart`, `offline_exam_relay.dart` | offline sitting | exists | |
| 88-90 | المراجعة: حفظتها / غلطت فيها / فاضية | `Stu2Exams?tab=flag|wrong|empty&screen=review` | none for student (a saved/flagged and wrong-answers question bank). Related: `exams/exam_review_screen.dart` (teacher review), `self_learning/sl_review_session.dart`, `learn_kit/` | none | missing | New: student flags questions in exams and gets a "wrong answers" review; needs storage + endpoint. |
| 93-94 | المتجر / ما فيه نتائج | `Stu2Store?screen=store` (`state=empty`) | `store/store_tab.dart`, `store_widgets.dart`, `store_api.dart` | tab `student_tab_store` | exists | |
| 95-96 | تفاصيل الملخص / الشراء متوقف | `Stu2Store?screen=item` (`state=off`) | `store/store_item_page.dart`, `store_models.dart` | push | exists | |
| 97-101 | إتمام الشراء / نتأكد من الدفع / تم / ما اكتمل / ما وصل التأكيد | `Stu2Store?sheet=checkout&pay=wait|ok|fail|late` | `store/store_checkout.dart`, `payments/enrollment/checkout_*.dart` | item page | exists | |
| 102-103 | مكتبتي: ملفاتي / المشتريات | `Stu2Store?screen=library` (`tab=orders`) | `store/store_library.dart`, `store_vault.dart`, `store_vault_io.dart` | push | exists | |
| 104 | القارئ | `Stu2Store?screen=reader` | `store/store_reader.dart` | push | exists | |
| 105-106 | الألعاب: المستويات / ألعاب سريعة | `Stu2Games?screen=games` (`view=classic`) | `games/games_tab.dart`, `games/learner/games_home_v4.dart`, `level_map.dart`, `games/shell/game_tile.dart` | student tab | exists | |
| 107-108 | كم عمرك؟ / الإعدادات | `Stu2Games?sheet=age|settings` | `games/learner/games_settings_sheet.dart`, `games/core/age_theme.dart` | games home | exists | |
| 109-112 | اللعب: البحر ✓ / الليل ✗ / الحديقة / الرمل إيقاف | `Stu2Games?theme=sea|night|garden|sand&screen=play` | `games/game_play_page.dart`, `games/shell/game_shell.dart`, `game_round.dart`, `game_motion.dart`, `games/core/age_theme.dart` | play | exists | Themes via age theme; pause sheet check. |
| 113-116 | نتيجة اللعبة: 3 نجوم / نجمتين / زائر / المتصدرين | `Stu2Games?screen=result` (`state=two|guest`, `sheet=board`) | `games/learner/result_sheet.dart`, `games/game_leaderboard.dart` | after round | partial | Leaderboards must use nicknames only (O-1..O-6). Guest result needs a sign-in prompt. |
| 117 | تقدّمي وشاراتي | `Stu2Games?screen=progress` | `games/games_progress.dart` (`GamesProgressPage`) | push | exists | |
| 118-121 | لوحة الأبطال / ما فيه بطل / جائزة البطل / كيف تنحسب | `Stu2Games?screen=champions` (`state=nochamp`, `sheet=win|rules`) | `games/champions/champions_page.dart`, `winner_sheet.dart`, `trophy.dart`, `champions_strip.dart` | push | exists | Nicknames, no classmates' names. |
| 122 | التحدّيات | `Stu2Games?screen=challenges` | `games/learner/challenges.dart` | push | exists | |
| 123-124 | خزانتي / خوذة السرعة | `Stu2Games?screen=wardrobe` (`hat=helmet`) | `games/learner/wardrobe.dart` | push | exists | |
| 125-126 | القرآن / ما فيه معلمين | `Stu2Quran?screen=quran` (`state=empty`) | `quran/quran_tab.dart`, `quran_api.dart` | student tab | exists | No sound effects, no living-being images. |
| 127 | ملف المعلم | `Stu2Quran?screen=teacher` | `quran/quran_teacher_page.dart`, `quran_teacher_hub.dart` | push | exists | |
| 128-130 | تقدّمي في الحفظ / سجّل ما حفظت / سمّع للشيخ | `Stu2Quran?screen=memo` (`sheet=log|rec`) | `quran/quran_progress.dart`, `quran_record_sheet.dart` | push | exists | |
| 131-135 | الدروس اليومية / درس / جولة المراجعة / خلّصت / مو مفعّلة | `Stu2Quran?screen=daily` (`mode=lesson|review|done|off`) | `self_learning/self_learning_page.dart`, `sl_review_session.dart`, `sl_store.dart`, `sl_widgets.dart` | push (kill switch) | exists | Self-learning daily lessons + review round. |
| 136-137 | النحو / زائر | `Stu2Nahw?screen=nahw` (`state=guest`) | `nahw/nahw_tab.dart`, `nahw_api.dart` | student tab | exists | |
| 138-143 | درس النحو: الشرح / تمرين / بعد التحقق / ممتاز / بداية حلوة / جرّب مرة ثانية | `Stu2Nahw?screen=lesson` (`step=ex|result`, `state=mid|low`) | `nahw/nahw_lesson_page.dart`, `nahw_exercise_view.dart` | push | exists | Result tiers (3) to check. |
| 144-145 | المعلمين / الفلاتر | `Stu2Teachers?screen=list` (`sheet=filter`) | `teachers/teacher_discovery.dart` (list), `teachers_api.dart` (`TeacherFilters`) | tab/push | exists | Show teacher gender; gender rules. |
| 146 | ملف المعلم وباقاته | `Stu2Teachers?screen=profile` | `teachers/teacher_discovery.dart` (`TeacherProfilePage`), `profile/course_instractor_profile.dart`, `teachers_parts.dart` | push | exists | |
| 147-152 | الباقة: متاحة / مكتملة / نبّهني / مقعدك محجوز / فضى مقعد / مشترك | `Stu2Teachers?screen=pack` (`state=open|full|wait|hold|offered|active`) | `teachers/teacher_discovery.dart` (`PackagePage`; states waitlisted, 30 min hold, offered 24 h), `teachers/package_wizard.dart` (teacher side), `teachers_models.dart` | push | exists | All six states already exist server-side; restyle. |
| 153 | الباقة: الخروج منها | `Stu2Teachers?sheet=leave` | `teachers/teachers_api.dart` `leave()`, `PackagePage` | pack page | exists | |
| 154 | معلميّ | `Stu2Teachers?screen=mine` | `teachers/teacher_discovery.dart` (`MyTeachersPage`), `GET /me/teachers` | push | exists | |
| 155 | تقدّمي | `Stu2Analysis?screen=overview` | `analytics/student/student_analytics_screen.dart`, `analytics_editorial.dart`, `student_analytics_widgets.dart` | student tab | exists | |
| 156-159 | تقدّمي في الدورة: نظرة / حضوري / اختباراتي / درجاتي | `Stu2Analysis?screen=course` (`tab=att|ex|marks`) | `analytics/student/student_course_analytics_screen.dart`, `attendance/analysis/student/`, `analytics/student/flags/` | push | exists | |
| 160 | ملفي | `Stu2Analysis?screen=profile` | `analytics/student/student_analytics_profile_screen.dart`, `home/student/record/student_record_pages.dart` | push | exists | |
| 161-166 | جدولي: المواعيد / التقويم / دعوة اجتماع / اجتماع جديد / فاضي / خطأ | `Stu2Schedule?screen=list|cal` (`sheet=meet|new`, `state=empty|error`) | `calendar/schedule_page.dart`, `schedule_parts.dart`, `calendar_views.dart`, `calendar_meeting.dart`, `calendar_api.dart`, `schedule_store.dart` | `/calendar` | partial | Exists. Privacy: a meeting invite for a student must not list invitees/classmates; time-zone note when different (RULES §3). |
| 167 | روابط الاجتماعات | `Stu2Schedule?screen=links` | `live/meeting_links_page.dart`, `meeting_links_parts.dart`, `meeting_links.dart` | push | exists | |
| 168-175 | الاشتراك في الدورة: عادي / بدون رسوم / نتأكد / صارت لك / ما اكتمل / نراجع التحويل / ما قبلنا الإيصال / المجموعة اكتملت | `Stu2Money?screen=enroll` (`state=free|processing|ok|fail|review|rejected|refused`) | `payments/enrollment/enrollment_screen.dart`, `enrollment_provider.dart`, `payment_flow_provider.dart`, `checkout_pages.dart`, `enrollment_widgets.dart` | course enrol | partial | "المجموعة اكتملت" (group full) needs the new groups model; other states exist. |
| 176 | التحويل البنكي | `Stu2Money?screen=transfer` | `payments/enrollment/transfer/`, `payments/enrollment_request/teacher_transfers_*.dart`, `admin/receipt_viewer.dart` | enrol | exists | |
| 177-178 | الاشتراك في المسار / صار لك | `Stu2Money?screen=path` (`state=ok`) | `payments/enrollment/roadmap_enrollment_screen.dart`, `roadmap_enrollment_provider.dart` | roadmap | exists | |
| 179-182, 190 | محفظتي / اشحن نقاط / باقة الاجتماعات / ينقصك نقاط / وش الفرق؟ | `Stu2Money?screen=wallet` (`sheet=buy|plan|help`, `short=1`) | `payments/points/points_wallet_page.dart`, `points_card_checkout.dart`, `live_plan_sheet.dart`, `points_api.dart` | profile/wallet | exists | |
| 183-187 | اشتراك الفهيم: اختر خطتك / نراجع / ما انقبل / فعّال / الحساب ما انفتح | `Stu2Money?screen=subscribe` (`state=choose|review|rejected|active|notopen`) | `payments/subscription/subscription_screen.dart`, `subscription_provider.dart`, `admin/admin_subscriptions_page.dart` | `/subscription` | exists | |
| 188 | مكافآتي | `Stu2Money?screen=rewards` | `rewards/my_rewards_page.dart`, `rewards_api.dart`, `coupon_field.dart`, `invited_by_field.dart` | push | exists | |
| 189 | المدفوعات والاشتراكات | `Stu2Money?screen=history` | `payments/subscription/subscription_screen.dart`, `store/store_library.dart` (orders); no single history page | push | partial | Merge payments + subscriptions history in one list. |
| 191, 211 | حسابي / إعدادات متقدمة | `Stu2Profile?screen=profile` (`adv=1`) | `profile/profile_screen.dart`, `profile_hero.dart`, `profile/components/setting_group.dart`, `switch_account_tile.dart`, `personal_account_tile.dart` | `/profile` | exists | |
| 192 | حذف الحساب | `Stu2Profile?sheet=delete` | `profile/profile_screen.dart`, `profile_hero.dart` (delete-account flow, `profile.*` keys) | profile | exists | |
| 193 | تعديل الحساب | `Stu2Profile?screen=edit` | `profile/update_account_widget.dart` (`EditAccountScreen`) | `/edit-account` | exists | |
| 194 | الأمان والأجهزة | `Stu2Profile?screen=security` | `profile/change_password_widget.dart`, `profile/passcode/passcode_screen.dart`, `auth/biometric.dart`, `courses/student/security/device_blocked_dialog.dart`, `device_security_provider.dart` | `/change-password` | partial | Pieces are spread; no single "security & devices" page with device list for the student. |
| 195-196 | الدرجات / الشهادات | `Stu2Profile?screen=grades` (`tab=certs`) | `home/student/record/student_record_pages.dart`, `certificates/student/my_certificates_screen.dart`, `exams/exam_results_screen.dart` | profile | partial | Certificates exist; one grades page (all courses) to check against `student_record_pages.dart`. |
| 197 | بياناتي الدراسية | `Stu2Profile?screen=study` | `profile/study_profile/study_profile_pages.dart`, `study_profile_form.dart` | profile | exists | |
| 198 | ربط ولي الأمر | `Stu2Profile?screen=parent` | `parent/student_link_code_screen.dart` (student shows code), `profile/profile_screen.dart` | profile | exists | Add kid-code (login) linkage if BACKEND adds it. |
| 199 | العرض والقراءة | `Stu2Profile?screen=display` | `profile/display/display_settings_page.dart`, `design/app_display.dart` | profile | exists | |
| 200-201 | نسخة من بياناتي: جاهزة / نجهّزها | `Stu2Profile?screen=data` (`state=ready|wait`) | `profile/privacy_export.dart` | profile | exists | |
| 202 | ملفي العام | `Stu2Profile?screen=public` | `profile/public_profile/public_profile_page.dart`, `public_profile_view.dart` | `/@name` | exists | Privacy review needed: what a student's public profile shows. |
| 203-205 | التحميلات / بدون نت / فاضية | `Stu2Profile?screen=downloads` (`state=offline|empty`) | `downloads/downloads_screen.dart`, `core/offline/*` | `/downloads` (phone/desktop only) | exists | Web redirects home. |
| 206-207 | تحقّق من شهادة: صحيحة / ملغاة | `Stu2Profile?screen=verify` (`state=ok|revoked`) | `certificates/issue/cert_verify_page.dart`, `cert_verify_view.dart`, `cert_verify_logic.dart` | public verify link | exists | |
| 208-210 | عن الفهيم / الشروط والأحكام / سياسة الخصوصية | `Stu2Profile?screen=about` (`tab=about|terms|privacy`) | `profile/about/about_and_terms_screen.dart`, `about_terms_parts.dart` | push, `/terms`, `/privacy` | exists | |

## New features (no Flutter counterpart)

1. Subject booking flow (BookFlow): delivery (remote / in person), group vs individual, group slots with seats, teacher individual slots, "propose your times", review step, inline login step, success. Needs groups, gender rules, availability, city lists.
2. Child-code login (3 screens) for accounts a parent created.
3. دفتر المادة: per-subject notebook with pen/finger canvas and keyboard text.
4. Student question review lists: "saved" and "got wrong" (with empty state).
5. Subject-scoped assistant panel and its locked state.
6. Subject-page panel layout (lesson, live, chat, bot, notes, calendar as panels, "ابدأ هنا" first lesson, book view).
7. Single security & devices page for the student; single payments + subscriptions history.
8. Group-full refusal state on enrolment (depends on groups model).

## Replace (behaviour changes, keep teacher side)

- Live room, prejoin and full-screen live for students: "أنت والمعلمة" only, no participant list/count/tiles/hands/chat authors.
- Course group chat -> one-way teacher announcements; replies go privately to the teacher.
- New message sheet: no "message anyone" for students.
- Leaderboards, champions and meeting invites: nicknames only; no classmate names or attendance.

## Per design file -> main Flutter files

- `BookFlow.dc.html` (+ `BookM*/BookW*`): none today; will touch `payments/enrollment/*`, `courses/student/details/course_detail_screen.dart`, `teachers/teacher_discovery.dart`, `calendar/calendar_api.dart`.
- `SubjectProfile.dc.html` (+ `SubjM*/SubjW*`): `courses/course_space/*`, `courses/course_profile/*`, `courses/student/details/*`, `sessions/material/*`, `sessions/video/*`, `live/room/*`, `messaging/chat/*`, `rag/*`, `calendar/*`.
- `StuHome.dc.html`: `home/student/home_screen.dart`, `dashboard/dashboard_screen.dart`, `design/home_kit.dart`.
- `Stu1Auth.dc.html`: `onboarding/*`, `onboarding/join/*`, `auth/*` (login, register, verify, forget, mfa, approval, fee); kid code is new.
- `Stu1Public.dc.html`: `guest/*`, `share/share_link_page.dart`, `profile/about/*`, `records/record_guest_page.dart`.
- `Stu1Discover.dc.html`: `courses/student/my_courses/*`, `courses/student/list/*`, `courses/category/*`, `courses/roadmap/*`, `profile/student_favorite_screen.dart`.
- `Stu1Learn.dc.html`: `courses/course_space/*`, `sessions/material/*`, `sessions/video/*`, `learn_kit/*`, `attendance/*`, `live/room/prejoin*.dart`, `records/*`.
- `Stu1Comm.dc.html`: `messaging/chat/*`, `messaging/inbox/*`, `messaging/notification/*`, `profile/compalints/*`, `rag/*`.
- `Stu2Exams.dc.html`: `exams/exam_taking*.dart`, `exam_consent_screen.dart`, `exam_result_screen.dart`, `exams/legacy/student/*`, `exams/offline/*`; review lists are new.
- `Stu2Store.dc.html`: `store/*`.
- `Stu2Games.dc.html`: `games/*` (`learner`, `shell`, `champions`, `core`).
- `Stu2Quran.dc.html`: `quran/*`, `self_learning/*` (daily lessons).
- `Stu2Nahw.dc.html`: `nahw/*`.
- `Stu2Teachers.dc.html`: `teachers/teacher_discovery.dart`, `teachers_api.dart`, `teachers_models.dart`.
- `Stu2Analysis.dc.html`: `analytics/student/*`, `attendance/analysis/student/*`, `home/student/record/*`.
- `Stu2Schedule.dc.html`: `calendar/*`, `live/meeting_links*.dart`.
- `Stu2Money.dc.html`: `payments/enrollment/*`, `payments/points/*`, `payments/subscription/*`, `rewards/*`.
- `Stu2Profile.dc.html`: `profile/*`, `downloads/*`, `certificates/student/*`, `certificates/issue/cert_verify_*.dart`, `parent/student_link_code_screen.dart`.
