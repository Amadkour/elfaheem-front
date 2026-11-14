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
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/teacher/sessions/sessions_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/features/shared/attendance/attendance_course_entry.dart';
import 'package:flutter_education_app/features/courses/course_space/course_space.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart' show kRoadmapTab;
import 'package:flutter_education_app/features/courses/roadmap/roadmap_tab.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart' show AppNavigator;
import 'package:flutter_education_app/features/shared/guest/guest_state.dart';
import 'package:flutter_education_app/features/shared/profile/compalints/complaint_provider.dart';
import 'package:flutter_education_app/features/shared/profile/compalints/new_complaint_screen.dart';
import 'package:flutter_education_app/features/shared/public_profile/public_profile_page.dart' show openPersonProfile;
import 'package:flutter_education_app/features/teacher/data_lab/data_lab_api.dart';
import 'package:flutter_education_app/features/teacher/sessions/components/course_reel_player.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_course_exams_widget.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_provider.dart';
import 'package:flutter_education_app/features/student/analysis/student_analytics_profile_screen.dart';
import 'package:flutter_education_app/features/student/enrollment/enrollment_screen.dart';
import 'package:flutter_education_app/features/student/enrollment/enrollment_widgets.dart';
import 'package:flutter_education_app/features/student/enrollment/roadmap_enrollment_screen.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_education_app/features/courses/student/details/components/about.dart';
import 'package:flutter_education_app/features/courses/student/details/components/course_access_parts.dart';
import 'package:flutter_education_app/features/courses/student/details/components/course_detail_parts.dart';
import 'package:flutter_education_app/features/courses/student/details/components/session.dart';
import 'package:flutter_education_app/features/courses/student/details/components/share_link.dart';
import 'package:flutter_education_app/features/courses/student/details/course_access_sheet.dart';
import 'package:flutter_education_app/features/courses/student/details/course_detail_provider.dart';
import 'package:flutter_education_app/features/courses/student/details/course_live_join.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_hub.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_parts.dart' show CpTrackTab;
import 'package:flutter_education_app/features/courses/student/details/growth_tr.dart';

void _openRecommendedCourse(BuildContext context, CourseSummary summary) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => CourseDetailScreen(course: CourseModel.fromSummary(summary))),
  );
}

/// Opens the enrollment flow and, once the student comes back, refreshes the
/// course details (enrolled state, price, etc). Shared by the enroll button
/// and by the payment-status banner's "send it again" action.
Future<void> _openEnrollment(BuildContext context, CourseModel course) async {
  if (!GuestGuard.ensure(context, reasonKey: 'guest_reason_enroll')) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EnrollmentScreen(course: course)));
  if (context.mounted) {
    await context.read<CourseDetailProvider>().refresh();
  }
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
  const CourseDetailScreen({super.key, required this.course, this.profileHub, this.initialTab});

  final CourseModel course;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _provider.init(widget.course);
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
    if (const {kCpTabAnnouncements, kCpTabProgress, kCpTabArchive, kCpTabTeam, kCpTabClass, kRoadmapTab}.contains(id)) {
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
    final col = context.colors;
    final ar = AppConfig.lang == 'ar';
    final title = (ar ? c.titleAr : c.titleEn) ?? '';
    final courseId = int.tryParse(c.id);
    _loadDataLabConfig(c);

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
      privateLabel: 'course_hero_private'.tr,
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
          : courseBuyCta(c, onEnroll: () => _openEnrollment(context, c), status: status),
    );

    // ── spotlight ──────────────────────────────────────────────────────────
    final spotlight = <Widget>[
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

    // ── quick actions ──────────────────────────────────────────────────────
    final actions = <CourseSpaceAction>[
      if (c.isEnrolled && _studentView != false)
        CourseSpaceAction(
          icon: Icons.insights_rounded,
          label: 'dl_my_profile'.tr,
          caption: 'dl_my_profile_sub'.tr,
          color: col.purple,
          featureKey: 'course_tabs.analytics',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => StudentAnalyticsProfileScreen.forStudent(courseId: courseId)),
          ),
        ),
      // (Exams is a tab of its own — no quick action repeating it, H7)
      CourseSpaceAction(
        icon: Icons.headset_mic_rounded,
        label: gt('الدعم', 'Support'),
        caption: gt('تواصل مع فريق الدعم', 'Talk to the support team'),
        color: col.success,
        onTap: () => _openSupport(context, c),
      ),
    ];

    // ── tabs ───────────────────────────────────────────────────────────────
    final tabs = <CourseSpaceTab>[
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
        label: gt('الجلسات', 'Sessions'),
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
        label: gt('عن الكورس', 'About'),
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

    return SafeArea(
      top: false,
      child: CourseSpace(
        hero: hero,
        heroBackground: showReel
            ? CourseReelPlayer(key: ValueKey(reel), url: reel, posterUrl: c.imageUrl.isNotEmpty ? c.imageUrl : null)
            : null,
        onBack: Navigator.canPop(context) ? () => Navigator.maybePop(context) : null,
        topActions: [
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
          if (mouse)
            CourseSpaceTopAction(icon: Icons.refresh_rounded, tooltip: 'refresh'.tr, overflow: true, onTap: _refresh),
        ],
        onRefresh: _refresh,
        spotlight: spotlight,
        actions: actions,
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
            : CourseBuyBar(course: c, status: status, onEnroll: () => _openEnrollment(context, c)),
      ),
    );
  }
}
