/// courses/details/course_detail_screen.dart
///
/// The student's course page, built on the shared [CourseSpace] (lib/features/courses/course_space/):
///  hero        cover / intro reel · category · private · live-or-recorded · certificate · teacher ·
///              students / lessons / hours (+ the progress ring once enrolled)
///  spotlight   live now · attendance check-in (while open) · start / continue / completed
///  actions     my analytics (Data Lab) · support
///  tabs        Live (live courses) · Sessions · Exams · Announcements · Progress · (Archive) · Path · About — the
///              course profile's parts are tabs of THIS page (D-111, course_profile_hub.dart), loaded when first
///              opened; Path is the course roadmap of a personal course (D-120, shared/roadmap/roadmap_tab.dart)
///  buy         phones: sticky price + enroll bar · desktop: the side card (enrolled: the access card)
///
/// Every fact is shown ONCE: numbers in the hero, price in the buy card / bar, the rest in About.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_education_app/design/app_tokens.dart' show AppWidth;
import 'package:flutter_education_app/design/app_states.dart' show AppNeedsConnection;
import 'package:flutter_education_app/core/offline/sync/offline_reads.dart' show offlineBlocked;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/games/breaks/play_now_card.dart';
import 'package:flutter_education_app/features/games/breaks/study_tracker.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/sessions/teacher/sessions_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/features/attendance/attendance_course_entry.dart';
import 'package:flutter_education_app/features/courses/course_space/course_space.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart' show kRoadmapTab;
import 'package:flutter_education_app/features/courses/roadmap/roadmap_tab.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart' show AppNavigator;
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'package:flutter_education_app/core/routing/pending_intent.dart';
import 'package:flutter_education_app/features/profile/compalints/complaint_provider.dart';
import 'package:flutter_education_app/features/profile/compalints/new_complaint_screen.dart';
import 'package:flutter_education_app/features/profile/public_profile/public_profile_page.dart' show openPersonProfile;
import 'package:flutter_education_app/features/data_lab/data_lab_api.dart';
import 'package:flutter_education_app/features/sessions/teacher/components/course_reel_player.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_course_exams_widget.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_provider.dart';
import 'package:flutter_education_app/features/analytics/student/student_analytics_profile_screen.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_screen.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_widgets.dart';
import 'package:flutter_education_app/features/payments/enrollment/roadmap_enrollment_screen.dart';
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_education_app/features/courses/student/details/components/about.dart';
import 'package:flutter_education_app/features/courses/student/details/components/course_access_parts.dart';
import 'package:flutter_education_app/features/courses/student/details/components/course_detail_parts.dart';
import 'package:flutter_education_app/features/courses/student/details/components/session.dart';
import 'package:flutter_education_app/features/courses/student/details/components/share_link.dart';
import 'package:flutter_education_app/features/courses/student/details/course_access_sheet.dart';
import 'package:flutter_education_app/features/courses/student/details/course_detail_provider.dart';
import 'package:flutter_education_app/features/courses/student/details/course_live_join.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_hub.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_page_sheets.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_parts.dart' show CpTrackTab;
import 'package:flutter_education_app/features/courses/student/details/growth_tr.dart';
import 'package:flutter_education_app/features/courses/student/details/subject_page_glue.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_panel.dart';
import 'package:flutter_education_app/features/courses/course_space/subject_space.dart';
import 'package:flutter_education_app/features/notebook/notebook_panel.dart';
import 'package:flutter_education_app/design/app_notice.dart' show showAppNotice;
import 'package:flutter_education_app/config/theme/kit_palette.dart' show AppAccent;
import 'package:flutter_education_app/features/courses/course_profile/course_page_models.dart' show CoursePage;
import 'package:flutter_education_app/features/quran/quran_api.dart' show QuranApi, quranOff;
import 'package:flutter_education_app/core/course_access.dart' show EnrollBarMode, enrollBarMode;
import 'package:flutter_education_app/features/booking/booking_api.dart';
import 'package:flutter_education_app/features/booking/booking_flow_controller.dart' show BkFlowController;
import 'package:flutter_education_app/features/booking/booking_flow_page.dart' show openBookFlow;
import 'package:flutter_education_app/features/booking/booking_mine_card.dart';
import 'package:flutter_education_app/features/booking/booking_models.dart';
import 'package:flutter_education_app/features/booking/booking_parts.dart' show bkFill;
import 'package:flutter_education_app/features/payments/points/points_card_checkout.dart' show openPointsPaymentPage;
import 'package:flutter_education_app/features/courses/student/details/subject_guest_space.dart';
import 'package:flutter_education_app/features/courses/student/details/subject_panels.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppButton, AppSheetContent, showAppSheet;

void _openRecommendedCourse(BuildContext context, CourseSummary summary) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => CourseDetailScreen(course: CourseModel.fromSummary(summary))),
  );
}

/// Opens the enrollment flow and, once the student comes back, refreshes the
/// course details (enrolled state, price, etc). Shared by the enroll button
/// and by the payment-status banner's "send it again" action.
Future<void> _openEnrollment(BuildContext context, CourseModel course) async {
  // a guest: the login sheet, and this course's checkout opens again right after the sign-in (D-1324)
  if (!GuestGuard.ensure(context,
      reasonKey: 'guest_reason_enroll', intent: PendingIntent(kind: PendingIntentKind.bookCourse, id: course.id))) {
    return;
  }
  if (offlineBlocked()) return; // enrolment and checkout are never queued on the device (D-1351)
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EnrollmentScreen(course: course)));
  if (context.mounted) {
    await context.read<CourseDetailProvider>().refresh();
  }
}

/// The subject and grade a course can be booked for (BookFlow): its subject and its one grade; null otherwise.
(int, int)? bkTargetOf(CourseModel c) {
  final subject = c.setup.subject?.id;
  final targets = c.setup.targets;
  final grade = targets.length == 1 && !targets.first.wholeStage ? targets.first.gradeId : null;
  if (subject == null || grade == null) return null;
  return (subject, grade);
}

void _openSupport(BuildContext context, CourseModel course) {
  if (!GuestGuard.ensure(context, reasonKey: 'guest_reason_support')) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider(
        create: (_) => ComplaintProvider(),
        child: NewComplaintScreen(
          courseTitle: (AppConfig.lang == 'ar' ? course.titleAr : course.titleEn) ?? '',
          courseId: course.id,
        ),
      ),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Screen
// ═════════════════════════════════════════════════════════════════════════════

class CourseDetailScreen extends StatefulWidget {
  const CourseDetailScreen({super.key, required this.course, this.profileHub, this.initialTab, this.openCheckout = false});

  final CourseModel course;

  /// Opens the checkout once the course has loaded (a resumed [PendingIntent], D-1324).
  final bool openCheckout;

  /// The course profile already loaded (opened from an old profile entry point); null → loaded on demand.
  final CourseProfileHub? profileHub;

  /// Open on this tab (live · lessons · exam · about · announcements · progress · archive).
  final String? initialTab;

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  late final CourseDetailProvider _provider;
  late final CourseProfileHub _hub = widget.profileHub ?? CourseProfileHub(int.tryParse(widget.course.id) ?? 0);

  @override
  void dispose() {
    _provider.removeListener(_seedHub);
    _hub.dispose();
    super.dispose();
  }

  /// The course payload's page state (closed · unread announcements, D-111) → the profile hub. The provider is
  /// app-wide: a course page opened on top of this one must not seed this page's hub.
  void _seedHub() {
    if (_provider.course.id == '${_hub.courseId}') _hub.seed(_provider.pageState);
  }

  @override
  void initState() {
    super.initState();
    _provider = context.read<CourseDetailProvider>();
    _provider.course = widget.course;
    _provider.block = null; // a block from the previous course page must not flash here
    _provider.pageState = null; // nor the previous course's unread count
    _provider.addListener(_seedHub);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _provider.init(widget.course);
      // a guest's "book this course" resumed after the sign-in (D-1324): its checkout, unless already enrolled
      final c = _provider.course;
      if (widget.openCheckout && mounted && _provider.block == null && !c.isEnrolled && c.id == widget.course.id) {
        final bk = bkTargetOf(c);
        if (bk != null && !bookingOff() && await BkFlowController.hasDraft(bk.$1, bk.$2)) {
          if (!mounted) return;
          await openBookFlow(context,
              subjectId: bk.$1, gradeId: bk.$2, subjectTitle: (AppConfig.lang == 'ar' ? c.titleAr : c.titleEn), courseId: c.id, resume: true);
          if (mounted) await _provider.refresh();
        } else {
          if (!mounted) return;
          await _openEnrollment(context, c);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseDetailProvider>();
    // Full-page skeleton only for the FIRST load. While the next page of
    // sessions loads (sessions already on screen) the page must stay put.
    final loading = provider.isLoading && provider.sessions.isEmpty;
    final block = provider.block;

    return BasePage(
      useWebCard: true,
      enableFooterWidget: false,
      width: AppWidth.wide,
      child: loading
          ? const CourseDetailSkeleton()
          : provider.offline && provider.sessions.isEmpty
          // the course could not be fetched: offline (QA_PHASE7 W-4)
          ? AppNeedsConnection(onRetry: () => provider.init(provider.course))
          : block != null
          // 404 (draft / unknown) or 403 course_locked: a calm page instead of an empty course
          ? CourseBlockedView(
              locked: block == CourseBlock.locked,
              title: (AppConfig.lang == 'ar' ? provider.course.titleAr : provider.course.titleEn) ??
                  provider.course.titleEn ??
                  provider.course.titleAr,
              onBack: Navigator.canPop(context) ? () => Navigator.maybePop(context) : null,
              onEnterCode: () => _enterCode(provider),
            )
          : _Body(hub: _hub, initialTab: widget.initialTab),
    );
  }

  Future<void> _enterCode(CourseDetailProvider p) async {
    final id = int.tryParse(p.course.id);
    if (id == null) return;
    final title = (AppConfig.lang == 'ar' ? p.course.titleAr : p.course.titleEn) ?? '';
    if (await CourseAccessSheet.show(context, courseId: id, courseName: title)) {
      await p.init(p.course);
    }
  }
}

/// First-load placeholder in the page's own shape, so nothing jumps when the course arrives.
class CourseDetailSkeleton extends StatelessWidget {
  const CourseDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const CourseSpaceSkeleton();
}

/// Provides what the tabs need (exams, the session cards), then draws the page.
class _Body extends StatelessWidget {
  const _Body({required this.hub, this.initialTab});

  final CourseProfileHub hub;
  final String? initialTab;

  @override
  Widget build(BuildContext context) {
    final course = context.read<CourseDetailProvider>().course;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => StudentExamProvider()),
        ChangeNotifierProvider(create: (_) => TeacherCourseScreenProvider(initialCourse: course.toTeacherModel)),
      ],
      child: _CoursePage(hub: hub, initialTab: initialTab),
    );
  }
}

class _CoursePage extends StatefulWidget {
  const _CoursePage({required this.hub, this.initialTab});

  final CourseProfileHub hub;
  final String? initialTab;

  @override
  State<_CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends State<_CoursePage> {
  /// Data Lab: may the student open their own analytics profile for this course? (null = not known yet → shown,
  /// as MyAnalyticsProfileCard did.)
  bool? _studentView;
  String? _configFor;

  /// A course-profile tab on screen (the provider's enum knows only its own tabs); null → the provider's tab.
  String? _profileTab;
  CourseDetailTab? _seenProviderTab;

  /// The opening tab was decided (CourseProfileHub.openingTab), or the person / a link chose one.
  late bool _openingDone = widget.initialTab != null;

  /// An enrolled student opens on the Overview (D-1090), once.
  late bool _overviewDecided = widget.initialTab != null;

  CourseProfileHub get _hub => widget.hub;

  @override
  void initState() {
    super.initState();
    final tab = widget.initialTab;
    if (tab != null) {
      if (const {'live', 'exam', 'about', 'lessons', 'sessions'}.contains(tab)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.read<CourseDetailProvider>().setTab(_tabOf(tab));
        });
      } else {
        _profileTab = tab;
      }
    }
    _hub.addListener(_onHub);
  }

  @override
  void dispose() {
    _hub.removeListener(_onHub);
    super.dispose();
  }

  void _onHub() {
    if (mounted) setState(() {});
  }

  void _openTab(CourseDetailProvider p, String id) {
    _openingDone = true;
    if (const {kCpTabOverview, kCpTabAnnouncements, kCpTabProgress, kCpTabArchive, kCpTabTeam, kCpTabClass, kRoadmapTab}.contains(id)) {
      setState(() => _profileTab = id);
    } else {
      setState(() => _profileTab = null);
      p.setTab(_tabOf(id));
    }
  }

  Future<void> _refresh() async {
    final p = context.read<CourseDetailProvider>();
    await Future.wait([p.refresh(), _hub.refresh()]);
  }

  /// A Quran program the student would be refused (gender rule): the bilingual reason replaces Enroll (QA_PHASE6
  /// 4.5). One teacher-list call, only on a Quran program's page for a signed-in student who is not enrolled.
  String? _quranRefusal;
  String? _quranCheckedFor;

  void _checkQuranBooking(CourseModel c) {
    if (_quranCheckedFor == c.id) return;
    _quranCheckedFor = c.id;
    final teacherId = c.teacher?.id;
    if (c.setup.programKind != 'quran' || c.isEnrolled || teacherId == null || GuestState.active || quranOff()) return;
    QuranApi().bookingRefusal(teacherId).then((r) {
      if (mounted && r != _quranRefusal) setState(() => _quranRefusal = r);
    });
  }

  void _loadDataLabConfig(CourseModel c) {
    if (!c.isEnrolled || _configFor == c.id) return;
    _configFor = c.id;
    DataLabApi()
        .config(courseId: int.tryParse(c.id))
        .then((cfg) {
          if (mounted) setState(() => _studentView = cfg.studentView);
        })
        .catchError((_) {});
  }

  /// The "Live now" card's Join: a locked session (prerequisites) shows the Live tab, where its card says why.
  void _joinLive(BuildContext context, CourseDetailProvider p, SessionModel s) {
    if (!GuestGuard.ensure(context, reasonKey: 'guest_reason_enroll')) return;
    if (!p.isSessionUnlockedById(s.id)) {
      p.setTab(CourseDetailTab.live);
      return;
    }
    openCourseLiveRoom(
      context,
      sessionId: s.id,
      courseId: s.courseId != 0 ? s.courseId : (int.tryParse(p.course.id) ?? 0),
      sessionName: s.name,
      hostName: p.course.teacher?.name,
    );
  }

  static String _tabId(CourseDetailTab t) => switch (t) {
    CourseDetailTab.live => 'live',
    CourseDetailTab.exam => 'exam',
    CourseDetailTab.about => 'about',
    // the old analytics tab is a quick action now
    CourseDetailTab.lessons || CourseDetailTab.analytics => 'lessons',
  };

  static CourseDetailTab _tabOf(String id) => switch (id) {
    'live' => CourseDetailTab.live,
    'exam' => CourseDetailTab.exam,
    'about' => CourseDetailTab.about,
    _ => CourseDetailTab.lessons,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CourseDetailProvider>();
    // a tab the provider switched to by itself (live card, continue …) takes over from a profile tab
    if (_seenProviderTab != null && _seenProviderTab != p.activeTab) {
      _profileTab = null;
      _openingDone = true;
    }
    _seenProviderTab = p.activeTab;
    final c = p.course;
    // the smart opening tab, once, from the course payload (D-111): a closed course's archive, unread announcements
    if (!_openingDone) {
      final open = _hub.openingTab();
      if (open != null) {
        _openingDone = true;
        if (open.isNotEmpty && (open != kCpTabAnnouncements || c.isEnrolled)) _profileTab = open;
      }
    }
    final profile = _hub.profile;
    final archived = profile != null && profile.closed && profile.isStudent;
    final courseIdEarly = int.tryParse(c.id);
    // D-1090: an enrolled student's page opens on the Overview, which reads the profile's page block
    if (c.isEnrolled && courseIdEarly != null && !archived) {
      if (!_overviewDecided) {
        _overviewDecided = true;
        _profileTab ??= kCpTabOverview;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _hub.ensure();
      });
    }
    final page = c.isEnrolled ? profile?.page : null;
    final col = context.colors;
    final ar = AppConfig.lang == 'ar';
    final title = (ar ? c.titleAr : c.titleEn) ?? '';
    final courseId = int.tryParse(c.id);
    _loadDataLabConfig(c);
    _checkQuranBooking(c);
    _loadBooking(c);

    final live = p.liveSessions;
    final showLiveTab = c.type == 'live' || live.isNotEmpty;
    final mouse = kIsWeb || MediaQuery.sizeOf(context).width >= 1000;
    final hours = c.totalHours.toStringAsFixed(c.totalHours % 1 == 0 ? 0 : 1);
    final reel = p.reelUrl;
    final showReel = reel != null && reel.isNotEmpty && !AppConfig.disableList.contains('course_hero.reel');
    final rate = c.rateSummary;
    final total = c.materialsTotal;
    final done = c.materialsCompleted;
    final learned = total > 0 ? done / total : c.progress.clamp(0, 100) / 100;
    // the next thing that can be taken (an ended live session with nothing recorded is skipped, H8)
    final next = p.nextPlayable;
    final status = ManualTransferStatusBanner(courseId: c.id, onRetry: () => _openEnrollment(context, c));
    final started = done > 0 || c.progress > 0;

    // D-941: the header carries the role's ONE action — Continue for an enrolled student, the price + Enroll for a
    // visitor (on phones the sticky bottom bar carries those, so the price shows once, D-943)
    final hero = CourseSpaceHeroData(
      title: title,
      subtitle: ar ? c.descriptionAr : c.descriptionEn,
      imageUrl: c.imageUrl,
      category: c.category == null ? null : (ar ? c.category!.nameAr : c.category!.nameEn),
      isPrivate: c.isPrivate,
      privateLabel: 'sv_course_hero_private'.tr,
      badges: [
        if (c.type == 'live')
          CourseSpaceBadge(label: gt('بث مباشر', 'Live'), icon: Icons.sensors_rounded, color: col.danger)
        else
          CourseSpaceBadge(label: gt('دروس مسجّلة', 'Recorded lessons'), icon: Icons.play_circle_outline_rounded),
        if (c.certificates.isNotEmpty)
          CourseSpaceBadge(label: gt('شهادة', 'Certificate'), icon: Icons.workspace_premium_rounded),
      ],
      teacherName: c.teacher?.name,
      teacherImageUrl: c.teacher?.imageUrl,
      onTeacher: c.teacher == null
          ? null
          : () => openPersonProfile(context, c.teacher!), // the one profile page when public (D-853)
      stats: [
        CourseSpaceStat(
          icon: Icons.groups_rounded,
          value: '${c.studentsCount}',
          label: courseStatNoun(c.studentsCount, 'course_hero_students'),
        ),
        CourseSpaceStat(
          icon: Icons.play_circle_outline_rounded,
          value: '${c.sessionsCount}',
          label: courseStatNoun(c.sessionsCount, 'course_hero_lessons'),
        ),
        CourseSpaceStat(icon: Icons.schedule_rounded, value: hours, label: courseStatNoun(c.totalHours, 'course_hero_hours')),
        if (rate != null && rate.total > 0)
          CourseSpaceStat(
            icon: Icons.star_rounded,
            tone: col.accent2,
            value: rate.average.toStringAsFixed(1),
            label: courseRatingCount(rate.total),
          ),
      ],
      progress: c.isEnrolled ? c.progress.clamp(0, 100) / 100 : null,
      progressLabel: total > 0 ? gt('تقدّمك · $done/$total', 'Your progress · $done/$total') : gt('تقدّمك', 'Your progress'),
      cta: archived
          ? null
          : c.isEnrolled
          ? (next == null || learned >= 1
                ? null
                : CourseSpaceCta(
                    primary: CourseSpaceButton(
                      label: started ? gt('تابع التعلم', 'Continue learning') : gt('ابدأ التعلم', 'Start learning'),
                      icon: Icons.play_arrow_rounded,
                      onTap: () => p.focusSession(next.id),
                    ),
                    caption: gt('التالي: ${next.name}', 'Up next: ${next.name}'),
                  ))
          : courseBuyCta(c, onEnroll: () => _openEnrollment(context, c), status: status, refusal: _quranRefusal),
    );

    // ── spotlight ──────────────────────────────────────────────────────────
    final spotlight = <Widget>[
      // Games v4 T75: a short game break (shown only when the super admin turns Play now on)
      if (c.isEnrolled && courseId != null) PlayNowCard(courseId: courseId),
      // the plan ends within a week, or has ended: one calm line (D-210)
      if (accessBannerText(c.access) != null) CourseAccessBanner(access: c.access),
      CourseArchiveSpot(hub: _hub, onOpenTab: (id) => _openTab(p, id)),
      // Join goes INTO the room (it used to switch to the Live tab only: on a wide window — the card sits in the side
      // column — with that tab already open, the click did nothing); a tap on the card opens the Live tab.
      if (live.isNotEmpty)
        courseLiveNowCard(
          sessionName: live.first.name,
          onJoin: () => _joinLive(context, p, live.first),
          onOpen: () => p.setTab(CourseDetailTab.live),
        ),
      // the next lecture or own-section session (D-1090); a running one is the Live now card above
      if (page != null && page.next != null && !page.next!.liveNow && live.isEmpty)
        CourseNextCard(
          title: page.next!.name,
          when: coursePageWhen(page.next!.at),
          caption: coursePageGroupLabel(page, page.next!.track, page.next!.groupNo),
          section: page.next!.isSection,
          actionLabel: gt('التفاصيل', 'Details'),
          actionIcon: Icons.play_lesson_rounded,
          onAction: () => p.focusSession(page.next!.id),
        ),
      if (c.isEnrolled && courseId != null)
        ParentComponent(
          featureKey: 'course_hero.attendance',
          child: AttendanceCourseEntry(courseId: courseId, title: title),
        ),
      // Continue and the progress are the hero's (D-943): the card stays for the finished course (its certificates)
      if (c.isEnrolled && p.sessions.isNotEmpty && learned >= 1)
        courseLearningCard(
          progress: learned.toDouble(),
          done: done,
          total: total,
          nextLesson: next?.name,
          hasCertificates: p.myCertificates.isNotEmpty || c.certificates.isNotEmpty,
          onContinue: next == null ? null : () => p.focusSession(next.id),
          onCertificates: () => p.setTab(CourseDetailTab.about),
        ),
    ];

    // ── quick actions: none (D-1090) — My analytics and Support moved into the ⋮ menu ──

    // ── tabs ───────────────────────────────────────────────────────────────
    final tabs = <CourseSpaceTab>[
      if (c.isEnrolled && courseId != null && !archived)
        courseOverviewTab(
          hub: _hub,
          staff: false,
          actions: (pr) => CourseOverviewActions(
            onOpenSession: p.focusSession,
            onAllSessions: () => _openTab(p, 'lessons'),
            onOpenExams: () => _openTab(p, 'exam'),
            onPickSection: pr.page?.sections.canPick == true
                ? () => showPickSectionSheet(context, courseId: courseId, groups: pr.page!.sections.groups, onChanged: _hub.load)
                : null,
            onAttendance: () => _openTab(p, kCpTabProgress),
            onTeam: () => _openTab(p, 'about'),
            onReviews: () => _openTab(p, 'about'),
            onOpenPathCourse: (id) => AppNavigator.openCourse(id),
          ),
        ),
      if (showLiveTab)
        CourseSpaceTab(
          id: 'live',
          label: 'live'.tr,
          icon: Icons.sensors_rounded,
          count: live.length,
          live: live.isNotEmpty,
          featureKey: 'live_sessions',
          builder: (_) => SessionsTab(provider: p, presented: live, title: 'live'.tr, live: true),
        ),
      CourseSpaceTab(
        id: 'lessons',
        label: 'bk_tab_lessons'.tr,
        icon: Icons.play_lesson_rounded,
        count: c.sessionsCount > 0 ? c.sessionsCount : p.sessions.length,
        featureKey: 'course_tabs.lessons',
        // an archived course the student may read: the profile's material (secured player, read-only)
        builder: (_) => archived
            ? CourseProfileTabBody(
                hub: _hub,
                builder: (pr) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CpTrackTab(profile: pr, track: 'lecture', onChanged: _hub.load),
                    if (pr.sections.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      CpTrackTab(profile: pr, track: 'section', onChanged: _hub.load),
                    ],
                  ],
                ),
              )
            : SessionsTab(provider: p, presented: p.sessions),
      ),
      CourseSpaceTab(
        id: 'exam',
        label: 'exams'.tr,
        icon: Icons.assignment_rounded,
        featureKey: 'exams',
        builder: (_) => StudentCourseExamsWidget(callback: p.refresh, courseId: c.id),
      ),
      if (courseId != null)
        ...courseProfileTabs(
          hub: _hub,
          staff: false,
          org: c.org != null,
          enrolled: c.isEnrolled,
          forced: _profileTab,
          onOpenTab: (id) => _openTab(p, id),
        ),
      // the course roadmap (D-120): personal courses of personal accounts that have one (the server empties the
      // lists for an organization account)
      if (courseId != null &&
          c.org == null &&
          (c.nextCourses.isNotEmpty || c.recentCompletedCourses.isNotEmpty || c.recommendedCourses.isNotEmpty) &&
          roadmapAllowedHere(context))
        ?courseRoadmapTab(
          courseId: courseId,
          staff: false,
          onOpenCourse: (rc) => AppNavigator.openCourse(rc.id),
          onEnrollAll: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => RoadmapEnrollmentScreen(courseId: courseId, courseName: title)),
          ),
          teacherPicks: c.recommendedCourses,
          onOpenPick: (s) => _openRecommendedCourse(context, s),
        ),
      CourseSpaceTab(
        id: 'about',
        label: 'bk_tab_about'.tr,
        icon: Icons.info_outline_rounded,
        featureKey: 'course_tabs.about',
        builder: (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AboutTab(),
            // the teaching team (assistants) of an enrolled student's course, from the profile
            if (c.isEnrolled && courseId != null) CourseTeamBlock(hub: _hub),
          ],
        ),
      ),
    ];

    final menu = <CourseSpaceTopAction>[
          CourseSpaceTopAction(
            icon: Icons.ios_share_rounded,
            tooltip: 'course_hero_share'.tr,
            onTap: () => shareCourseLink(context, c),
          ),
          CourseSpaceTopAction(
            icon: c.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: c.isFavorite ? col.danger : null,
            tooltip: 'course_hero_favourite'.tr,
            selected: c.isFavorite,
            onTap: () => GuestGuard.run(context, p.toggleFavorite, reasonKey: 'guest_reason_favorite'),
          ),
          // rarer: the ⋮ menu (refresh is pull-to-refresh on phones)
          if (c.isEnrolled && courseId != null) courseAskDocsAction(context, courseId, title),
          if (c.isEnrolled && _studentView != false && !AppConfig.disableList.contains('course_tabs.analytics'))
            CourseSpaceTopAction(
              icon: Icons.insights_rounded,
              tooltip: 'dl_my_profile'.tr,
              overflow: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => StudentAnalyticsProfileScreen.forStudent(courseId: courseId)),
              ),
            ),
          CourseSpaceTopAction(
            icon: Icons.headset_mic_rounded,
            tooltip: gt('الدعم', 'Support'),
            overflow: true,
            onTap: () => _openSupport(context, c),
          ),
          if (mouse)
            CourseSpaceTopAction(icon: Icons.refresh_rounded, tooltip: 'refresh'.tr, overflow: true, onTap: _refresh),
        ];

    // S-B: an enrolled student's course page is the subject page (SubjectProfile); a teacher, a visitor and an
    // archived course keep CourseSpace
    if (c.isEnrolled && courseId != null && !archived && !GuestState.active) {
      return StudyTracker(
        courseId: courseId,
        enabled: true,
        child: SafeArea(
          top: false,
          child: _subjectPage(context, p, c, courseId: courseId, title: title, page: page, spotlight: spotlight, tabs: tabs, menu: menu),
        ),
      );
    }

    // BK: a visitor and a student who is not enrolled get the subject page before subscribing (SubjMGuest)
    if (!c.isEnrolled && !archived) {
      return SafeArea(
        top: false,
        child: _guestPage(context, p, c, title: title, spotlight: spotlight, tabs: tabs, menu: menu, status: status, reel: showReel ? reel : null),
      );
    }

    return StudyTracker(
      courseId: courseId,
      enabled: c.isEnrolled,
      child: SafeArea(
      top: false,
      child: CourseSpace(
        hero: hero,
        heroBackground: showReel
            ? CourseReelPlayer(key: ValueKey(reel), url: reel, posterUrl: c.imageUrl.isNotEmpty ? c.imageUrl : null)
            : null,
        onBack: Navigator.canPop(context) ? () => Navigator.maybePop(context) : null,
        topActions: menu,
        onRefresh: _refresh,
        spotlight: spotlight,
        tabs: tabs,
        activeTab: _profileTab ?? _tabId(p.activeTab),
        onTab: (id) => _openTab(p, id),
        onNearEnd: () {
          if (p.activeTab == CourseDetailTab.lessons) p.loadMoreSessions();
        },
        aside: archived
            ? null
            : c.isEnrolled
            ? CourseEnrolledCard(course: c)
            : CourseBuyCard(course: c, purchase: false, onEnroll: () => _openEnrollment(context, c)),
        bottomBar: c.isEnrolled || archived
            ? null
            : CourseBuyBar(course: c, status: status, refusal: _quranRefusal, onEnroll: () => _openEnrollment(context, c)),
      ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BK: booking this subject, and the page before subscribing
  // ═══════════════════════════════════════════════════════════════════════════

  /// The booking options of this course's subject and grade (null: not bookable here, or not loaded yet).
  BkOptions? _bkOptions;
  String? _bkFor;
  List<BkBooking> _bkMine = const [];
  bool _bkPaying = false;

  void _loadBooking(CourseModel c) {
    if (_bkFor == c.id) return;
    _bkFor = c.id;
    final t = bkTargetOf(c);
    if (t == null || bookingOff()) return;
    BookingApi().options(subjectId: t.$1, gradeId: t.$2).then((o) {
      if (mounted && _bkFor == c.id) setState(() => _bkOptions = o);
    }).catchError((_) {});
    if (!GuestState.active) _loadMine(t.$1);
  }

  void _loadMine(int subjectId) {
    BookingApi().mine(subjectId: subjectId).then((m) {
      if (mounted) setState(() => _bkMine = m);
    }).catchError((_) {});
  }

  /// The lowest monthly price the subject can be booked at (null: no kind is open).
  double? get _bkFrom {
    final o = _bkOptions;
    if (o == null) return null;
    final prices = [
      for (final k in o.openKinds)
        for (final m in o.openModes)
          if (k.prices[m.key] != null) k.prices[m.key]!,
    ];
    if (prices.isEmpty) return null;
    prices.sort();
    return prices.first;
  }

  Future<void> _openBooking(CourseModel c, String title) async {
    final t = bkTargetOf(c);
    if (t == null) return;
    final booked = await openBookFlow(
      context,
      subjectId: t.$1,
      gradeId: t.$2,
      subjectTitle: _bkOptions?.subject.label ?? title,
      gradeTitle: _bkOptions?.grade.label,
      subjectKey: c.setup.subject?.nameEn ?? c.setup.subject?.nameAr,
      courseId: c.id,
    );
    if (!mounted || !booked) return;
    showAppNotice(bkFill('bk_welcome', {'subject': _bkOptions?.subject.label ?? title}));
    _loadMine(t.$1);
    await _refresh();
  }

  Future<void> _payBooking(BkBooking b) async {
    if (offlineBlocked()) return;
    setState(() => _bkPaying = true);
    try {
      final r = await BookingApi().pay(b.id);
      if (!mounted) return;
      if (r.canOpen) await openPointsPaymentPage(context, r.checkoutUrl!);
      if (!mounted) return;
      final t = bkTargetOf(context.read<CourseDetailProvider>().course);
      if (t != null) _loadMine(t.$1);
    } catch (e) {
      showAppNotice(bkErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _bkPaying = false);
    }
  }

  /// "حجزك" on the subject page: shown while the booking still asks for something.
  Widget? _bookingCard(CourseModel c) {
    final b = bkShownBooking(_bkMine);
    if (b == null || b.active) return null;
    return BkMineCard(booking: b, busy: _bkPaying, onPay: () => _payBooking(b));
  }

  /// The next class of an active booking when the course has none scheduled yet (BookM6).
  SubjectNext? _bookingNext() {
    final b = _bkMine.where((x) => x.active && x.nextClassAt != null).firstOrNull;
    if (b == null) return null;
    return SubjectNext(
      when: subjectWhen(b.nextClassAt!, minutes: b.classMinutes),
      until: b.nextClassAt,
      note: 'bk_opens_before'.tr,
    );
  }

  void _openPreview(String reel, String? poster, String title) => showAppSheet<void>(
        context,
        (_) => AppSheetContent(
          title: title,
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: CourseReelPlayer(key: ValueKey(reel), url: reel, posterUrl: poster)),
          ],
        ),
      );

  Widget _guestPage(
    BuildContext context,
    CourseDetailProvider p,
    CourseModel c, {
    required String title,
    required List<Widget> spotlight,
    required List<CourseSpaceTab> tabs,
    required List<CourseSpaceTopAction> menu,
    required Widget status,
    String? reel,
  }) {
    final teacher = c.teacher;
    final teacherName = teacher?.name ?? '';
    final rate = c.rateSummary;
    final total = _subjectTotal(p);
    final hours = c.totalHours.toStringAsFixed(c.totalHours % 1 == 0 ? 0 : 1);
    final liveMinutes =
        p.sessions.where((s) => s.isLive && s.durationMinutes > 0).map((s) => s.durationMinutes).firstOrNull;
    final mine = bkShownBooking(_bkMine);
    final from = _bkFrom;
    final bookable = from != null && !bookingOff();
    final mode = enrollBarMode(enrolled: c.isEnrolled, access: c.access);
    final canEnroll = (mode == EnrollBarMode.subscribe || mode == EnrollBarMode.renew) && _quranRefusal == null;
    final free = (c.finalPrice ?? 0) == 0;

    // the path's first steps: the first one open to look at, the rest after subscribing
    final steps = <SubjectStep>[];
    for (final (i, s) in p.sessions.take(kSubjectPathSteps).indexed) {
      final minutes = s.durationMinutes;
      steps.add(SubjectStep(
        id: 'g${s.id}',
        number: i + 1,
        title: s.name,
        meta: s.isLive
            ? (minutes > 0 ? '${'sb_subj_meta_live'.tr}${(AppConfig.lang == 'ar' ? '، ' : ', ')}${sbMinutes(minutes)}' : 'sb_subj_meta_live'.tr)
            : (minutes > 0 ? '${'sb_subj_meta_lesson'.tr}${(AppConfig.lang == 'ar' ? '، ' : ', ')}${sbMinutes(minutes)}' : 'sb_subj_meta_lesson'.tr),
        kind: s.isLive ? SubjectStepKind.live : SubjectStepKind.lesson,
        state: i == 0 ? SubjectStepState.todo : SubjectStepState.locked,
        onTap: i == 0 && reel != null ? () => _openPreview(reel, c.imageUrl.isNotEmpty ? c.imageUrl : null, title) : null,
      ));
    }

    final notes = <Widget>[
      status,
      if (_quranRefusal != null) CourseBookingRefusal(text: _quranRefusal!),
      if (mode == EnrollBarMode.pending || mode == EnrollBarMode.support) CourseAccessNote(mode: mode, access: c.access),
      // the course's own subscription stays one tap away when the subject is booked by month
      if (bookable && canEnroll && !free)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.ghost(label: 'bk_join_course_instead'.tr, onPressed: () => _openEnrollment(context, c)),
        ),
    ];

    String? primary;
    VoidCallback? onPrimary;
    if (mine == null && bookable) {
      primary = 'bk_book_cta'.tr;
      onPrimary = () => _openBooking(c, title);
    } else if (mine == null && canEnroll) {
      primary = mode == EnrollBarMode.renew ? 'course_renew_btn'.tr : 'bk_join_course'.tr;
      onPrimary = () => _openEnrollment(context, c);
    }

    return SubjectGuestSpace(
      title: title,
      subject: c.setup.subject?.nameEn ?? c.setup.subject?.nameAr ?? c.category?.nameEn ?? c.category?.nameAr,
      grade: _subjectGrade(c),
      kindLabel: c.type == 'live' ? 'bk_kind_live_recorded'.tr : 'bk_kind_recorded'.tr,
      teacher: teacherName,
      teacherImageUrl: teacher?.imageUrl,
      teacherYears: teacher?.teacherProfile?.experienceYears,
      teacherBio: teacher?.teacherProfile?.about,
      onTeacher: teacher == null ? null : () => openPersonProfile(context, teacher),
      lessonsCount: total,
      rating: rate != null && rate.total > 0 ? rate.average.toStringAsFixed(1) : null,
      facts: [
        if (total > 0)
          SubjectFact(icon: Icons.menu_book_outlined, value: sbDigits(total), label: 'sb_subj_fact_lessons'.tr, accent: AppAccent.pink),
        if (liveMinutes != null)
          SubjectFact(icon: Icons.schedule_rounded, value: sbDigits(liveMinutes), label: 'sb_subj_fact_minutes'.tr, accent: AppAccent.grape),
        if (c.totalHours > 0)
          SubjectFact(icon: Icons.hourglass_bottom_rounded, value: sbDigits(hours), label: 'sb_subj_fact_hours'.tr, accent: AppAccent.mint),
        if (rate != null && rate.total > 0)
          SubjectFact(icon: Icons.star_rounded, value: sbDigits(rate.average.toStringAsFixed(1)), label: 'sb_subj_fact_rating'.tr),
      ],
      bookNote: AppConfig.disableList.contains('course.notebook') ? null : 'bk_book_note'.tr,
      steps: steps,
      price: bookable ? bkMoney(from, _bkOptions?.currency) : null,
      priceNote: bookable ? 'bk_per_month'.tr : null,
      priceBlock: bookable || free || !canEnroll ? null : CoursePriceBlock(course: c),
      primaryLabel: primary,
      onPrimary: onPrimary,
      notes: notes,
      onPreview: reel == null ? null : () => _openPreview(reel, c.imageUrl.isNotEmpty ? c.imageUrl : null, title),
      includes: [
        'bk_inc_path'.tr,
        if (c.type == 'live') 'bk_inc_recorded'.tr,
        if (!AppConfig.disableList.contains('course.notebook')) 'bk_inc_notebook'.tr,
        if (!subjectBotOff()) 'bk_inc_bot'.tr,
      ],
      extras: [
        if (mine != null) BkMineCard(booking: mine, busy: _bkPaying, onPay: () => _payBooking(mine)),
        for (final w in spotlight)
          if (w is! CourseNextCard) w,
      ],
      more: [
        for (final t in tabs)
          if (t.id != 'live')
            CourseSpaceAction(
              icon: t.icon,
              label: t.label,
              featureKey: t.featureKey,
              onTap: () => pushSubjectTabPage(context, t),
            ),
      ],
      menu: menu,
      onBack: Navigator.canPop(context) ? () => Navigator.maybePop(context) : null,
      onRefresh: _refresh,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // S-B: the subject page of an enrolled student
  // ═══════════════════════════════════════════════════════════════════════════

  /// The provider's focus tick last acted on (an Overview row, "Continue" …), and whether a deep link's opening tab
  /// was opened.
  int? _seenFocusTick;
  bool _subjectOpened = false;

  /// The old tabs the subject page itself stands for.
  static const _subjectOwnTabs = {'live', 'lessons', 'sessions', 'overview'};

  final Map<String, CourseSpaceTab> _subjectTabs = {};

  void _openSubjectTab(String id) {
    final t = _subjectTabs[id];
    if (t != null) pushSubjectTabPage(context, t);
  }

  Future<void> _openSubjectExam(CourseDetailProvider p, int id) =>
      openSubjectExam(context, p, id, onExamsPage: () => _openSubjectTab('exam'));

  void _openSubjectLesson(CourseDetailProvider p, SessionModel s, int number) {
    if (s.isLive && !s.hasRecording && s.totalMaterial == 0) {
      // a class still to come: nothing to open yet
      showAppNotice('sb_subj_opens_before'.tr);
      return;
    }
    final i = p.sessions.indexWhere((x) => x.id == s.id);
    final after = i >= 0 && i + 1 < p.sessions.length ? p.sessions[i + 1] : null;
    openSubjectLessonPanel(
      context,
      p,
      s,
      number: number,
      onOpenExam: (id) => _openSubjectExam(p, id),
      onNext: after == null || !p.isSessionUnlockedById(after.id) || after.isLiveActive
          ? null
          : () => _openSubjectLesson(p, after, number + 1),
    );
  }

  List<SubjectStep> _subjectSteps(CourseDetailProvider p, String teacher) => subjectStepsOf(
        p,
        teacher: teacher,
        onOpenLesson: (s, n) => _openSubjectLesson(p, s, n),
        onJoinLive: (s) => _joinLive(context, p, s),
        onOpenExam: (id) => _openSubjectExam(p, id),
      );

  static String? _subjectGrade(CourseModel c) {
    final targets = c.setup.targets;
    if (targets.isEmpty) return null;
    return targets.first.wholeStage ? targets.first.stageName : targets.first.gradeName;
  }

  static int _subjectTotal(CourseDetailProvider p) => p.course.sessionsCount > 0 ? p.course.sessionsCount : p.sessions.length;

  void _openSubjectLessons(CourseDetailProvider p, String title, String teacher) {
    final grade = _subjectGrade(p.course);
    pushSubjectLessonsPage(
      context,
      teacher: teacher,
      kicker: grade == null ? title : '$title، $grade',
      steps: (_) => _subjectSteps(p, teacher),
      done: () => p.sessions.where(subjectSessionDone).length,
      total: () => _subjectTotal(p),
    );
  }

  Widget _subjectPage(
    BuildContext context,
    CourseDetailProvider p,
    CourseModel c, {
    required int courseId,
    required String title,
    required CoursePage? page,
    required List<Widget> spotlight,
    required List<CourseSpaceTab> tabs,
    required List<CourseSpaceTopAction> menu,
  }) {
    final teacher = c.teacher;
    final teacherName = teacher?.name ?? '';
    _subjectTabs
      ..clear()
      ..addEntries(tabs.map((t) => MapEntry(t.id, t)));

    // a row asked the page to open a session (the Overview's rows, a link): its lesson panel
    if (_seenFocusTick != p.focusTick) {
      final first = _seenFocusTick == null;
      _seenFocusTick = p.focusTick;
      final id = p.focusSessionId;
      final i = id == null ? -1 : p.sessions.indexWhere((s) => s.id == id);
      if (!first && i >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openSubjectLesson(p, p.sessions[i], i + 1);
        });
      }
    }
    // a deep link's opening tab (initialTab): its page, once
    final want = widget.initialTab;
    if (!_subjectOpened && want != null && p.sessions.isNotEmpty) {
      _subjectOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (want == 'lessons' || want == 'sessions') {
          _openSubjectLessons(p, title, teacherName);
        } else if (!_subjectOwnTabs.contains(want)) {
          _openSubjectTab(want);
        }
      });
    }

    final live = p.liveSessions;
    final rate = c.rateSummary;
    final liveMinutes =
        p.sessions.where((s) => s.isLive && s.durationMinutes > 0).map((s) => s.durationMinutes).firstOrNull;
    final total = _subjectTotal(p);
    final done = p.sessions.where(subjectSessionDone).length;

    // the next class: the profile's next lecture / own section, else the next scheduled live session
    final now = DateTime.now().toUtc();
    final pn = page?.next != null && !page!.next!.liveNow ? page.next : null;
    final upcoming = p.sessions
        .where((s) => s.isLive && !s.isLiveActive && s.scheduledAt != null && s.scheduledAt!.toUtc().isAfter(now))
        .firstOrNull;
    final nextAt = pn != null ? pn.at?.toUtc() : upcoming?.scheduledAt?.toUtc();
    final nextMinutes = pn != null ? pn.minutes : upcoming?.durationMinutes;
    final nextId = pn?.id ?? upcoming?.id;
    final nextOpen = nextAt != null && nextAt.subtract(const Duration(minutes: 10)).isBefore(now);
    final nextSession = nextId == null ? null : p.sessions.where((s) => s.id == nextId).firstOrNull;
    final hours = c.totalHours.toStringAsFixed(c.totalHours % 1 == 0 ? 0 : 1);

    return SubjectSpace(
      title: title,
      subject: c.setup.subject?.nameEn ?? c.setup.subject?.nameAr ?? c.category?.nameEn ?? c.category?.nameAr,
      grade: _subjectGrade(c),
      teacher: teacherName,
      teacherImageUrl: teacher?.imageUrl,
      teacherYears: teacher?.teacherProfile?.experienceYears,
      teacherBio: teacher?.teacherProfile?.about,
      onTeacher: teacher == null ? null : () => openPersonProfile(context, teacher),
      mode: c.setup.isEmpty ? null : (c.setup.inPerson ? 'sb_subj_mode_inperson'.tr : 'sb_subj_mode_remote'.tr),
      lessonsCount: total,
      rating: rate != null && rate.total > 0 ? rate.average.toStringAsFixed(1) : null,
      facts: [
        if (total > 0)
          SubjectFact(icon: Icons.menu_book_outlined, value: sbDigits(total), label: 'sb_subj_fact_lessons'.tr, accent: AppAccent.pink),
        if (liveMinutes != null)
          SubjectFact(icon: Icons.schedule_rounded, value: sbDigits(liveMinutes), label: 'sb_subj_fact_minutes'.tr, accent: AppAccent.grape),
        if (c.totalHours > 0)
          SubjectFact(icon: Icons.hourglass_bottom_rounded, value: sbDigits(hours), label: 'sb_subj_fact_hours'.tr, accent: AppAccent.mint),
        if (rate != null && rate.total > 0)
          SubjectFact(icon: Icons.star_rounded, value: sbDigits(rate.average.toStringAsFixed(1)), label: 'sb_subj_fact_rating'.tr),
      ],
      scheduleNote: nextAt == null ? null : subjectWhen(nextAt),
      live: live.isEmpty
          ? null
          : SubjectLive(
              title: live.first.name,
              startedAgo: subjectStartedAgo(live.first.scheduledAt),
              onJoin: () => _joinLive(context, p, live.first),
            ),
      next: live.isNotEmpty || nextAt == null
          ? _bookingNext()
          : SubjectNext(
              when: subjectWhen(nextAt, minutes: nextMinutes),
              title: pn?.name ?? upcoming?.name,
              until: nextAt,
              onJoin: nextOpen && nextSession != null ? () => _joinLive(context, p, nextSession) : null,
            ),
      steps: _subjectSteps(p, teacherName),
      done: done,
      total: total,
      onAllLessons: () => _openSubjectLessons(p, title, teacherName),
      onChat: teacher == null || subjectChatOff()
          ? null
          : () => openSubjectChatPanel(context, teacherId: teacher.id, teacherName: teacherName, courseId: courseId),
      onBot: subjectBotOff() ? null : () => openSubjectBotPanel(context, courseId: courseId, subjectTitle: title),
      onNotes: () => showSubjectPanel<void>(
        context,
        title: 'sb_nb_title'.tr.replaceAll('{subject}', title),
        child: (_) => NotebookPanel(courseId: courseId, subjectId: c.setup.subject?.id, subjectTitle: title),
      ),
      onSchedule: () => openSubjectSchedulePanel(
            context,
            courseId: courseId,
            subjectTitle: title,
            subjectKey: c.setup.subject?.nameEn ?? c.setup.subject?.nameAr,
          ),
      onExams: _subjectTabs.containsKey('exam') ? () => _openSubjectTab('exam') : null,
      onAttendance: _subjectTabs.containsKey(kCpTabProgress) ? () => _openSubjectTab(kCpTabProgress) : null,
      // the spotlight's next-class card is the page's own next card
      extras: [
        ?_bookingCard(c),
        for (final w in spotlight) if (w is! CourseNextCard) w,
      ],
      more: [
        for (final t in tabs)
          if (!_subjectOwnTabs.contains(t.id) && t.id != 'exam')
            CourseSpaceAction(
              icon: t.icon,
              label: t.label,
              featureKey: t.featureKey,
              badge: t.id == kCpTabAnnouncements && (t.count ?? 0) > 0 ? '${t.count}' : null,
              onTap: () => pushSubjectTabPage(context, t),
            ),
        if (tabs.any((t) => t.id == kCpTabOverview))
          CourseSpaceAction(
            icon: Icons.dashboard_outlined,
            label: 'sb_subj_overview'.tr,
            onTap: () => _openSubjectTab(kCpTabOverview),
          ),
      ],
      menu: menu,
      onBack: Navigator.canPop(context) ? () => Navigator.maybePop(context) : null,
      onRefresh: _refresh,
    );
  }
}
