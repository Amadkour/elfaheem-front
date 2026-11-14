// teacher_sessions_screen.dart
//
// The teacher's course studio, drawn by the shared course page (CourseSpace, the same component as the student's
// course details): hero · spotlight (archived · live now · attendance · setup checklist) · quick actions · tabs Sessions ·
// Announcements · Class · Team · Archive · Path · About (the course profile's parts are tabs of THIS page, D-111,
// course_profile_hub.dart, loaded when first opened; Path = the roadmap editor of a personal course, D-120,
// shared/roadmap/roadmap_tab.dart). The header carries New session · Edit course · Share and the price / rating figures
// (D-941, D-943: no side card repeats them). The server's caps decide Edit (course_settings) once the profile is known; a TA opening the
// page from an old profile entry point has it loaded.
//
// REBUILD SCOPING
// ─────────────────────────────────────────────────────────────────────────
// TeacherCourseScreenProvider is a "mega provider" (course header, sessions, per-session materials, upload flags,
// live state) and notifies for all of it. Nothing at the top watches it:
//   • the page is built from a `Selector` over a record of only what the hero / actions / spotlight / side card
//     need (course, reel, session count, the running live session, first-load flag). Records compare
//     structurally, so material uploads and live-flag churn on other sessions never rebuild the hero;
//   • the Sessions tab body (`TeacherSessionsBody`) does its own `watch` — it is the one part that legitimately
//     reacts to almost everything;
//   • the attendance spotlight selects (type, session count) on its own.
// ─────────────────────────────────────────────────────────────────────────

import 'dart:async' show unawaited;
import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_education_app/features/help/help_info_button.dart' show helpAvailableForMenu, showHelpForPage;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/sessions/teacher/sessions_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_responsive.dart';
import 'package:flutter_education_app/design/app_tokens.dart' show AppWidth;
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/rating_widget.dart';
import 'package:flutter_education_app/features/attendance/attendance_course_entry.dart';
import 'package:flutter_education_app/features/attendance/teacher_attendance_controller.dart';
import 'package:flutter_education_app/features/attendance/teacher_attendance_launcher.dart';
import 'package:flutter_education_app/features/courses/course_space/course_space.dart';
import 'package:flutter_education_app/features/courses/course_price_tag.dart' show coursePriceLabel;
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart' show RmCourse;
import 'package:flutter_education_app/features/courses/roadmap/roadmap_tab.dart';
import 'package:flutter_education_app/features/sessions/teacher/components/session_form_sheet.dart';
import 'package:flutter_education_app/features/courses/teacher/component/certificate_manager_sheet.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_api.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_models.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';
import 'package:flutter_education_app/features/home/teacher/schedules/schedules_screen.dart';
import 'package:flutter_education_app/features/courses/student/details/components/share_link.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_hub.dart';
import 'package:flutter_education_app/features/sessions/teacher/components/course_reel_player.dart';
import 'package:flutter_education_app/features/sessions/teacher/components/sessions_section.dart';
import 'package:flutter_education_app/features/sessions/teacher/components/teacher_course_parts.dart';
import 'package:flutter_education_app/features/sessions/teacher/students/course_student_screen.dart';
import 'package:flutter_education_app/design/app_icons.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

const _tabSessions = 'sessions';
const _tabDetails = 'details';

/// Opens one of the teacher's OWN courses (a course on this course's path — the backend guarantees it is
/// this teacher's) in the normal course-management screen. Deliberately does NOT reuse the student-facing
/// CourseDetailScreen, which shows an "Enroll" CTA that makes no sense for a teacher looking at their own course.
void _openOwnCoursePreview(BuildContext context, RmCourse course) {
  final stub = TeacherCourse(
    id: course.id,
    titleAr: course.nameAr ?? course.name,
    titleEn: course.nameEn ?? course.name,
    imageUrl: course.imageUrl ?? '',
    totalHours: 0,
    type: 'recorded',
    price: course.finalPrice,
    currency: course.currency,
    expectedHours: 0,
    progress: 0,
  );
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider(
        create: (_) => TeacherCourseScreenProvider(initialCourse: stub),
        child: const TeacherSessionsScreen(),
      ),
    ),
  );
}


/// What the page (everything but the Sessions tab body) depends on.
typedef _PageData = ({
  TeacherCourse course,
  String? reelUrl,
  int sessionCount,
  int liveId,
  String liveName,
  bool loadingAll,
});

_PageData _select(TeacherCourseScreenProvider p) {
  final live = p.sessions.where((s) => s.isLiveActive).firstOrNull;
  return (
    course: p.course,
    reelUrl: p.reelUrl,
    sessionCount: p.sessionCount,
    liveId: live?.id ?? -1,
    liveName: live?.name ?? '',
    loadingAll: p.loadingAllPage,
  );
}

class TeacherSessionsScreen extends StatefulWidget {
  const TeacherSessionsScreen({super.key, this.expandDetails, this.profileHub, this.initialTab});

  /// Open on the Details tab.
  final bool? expandDetails;

  /// The course profile already loaded (an old profile entry point); null → loaded on demand.
  final CourseProfileHub? profileHub;

  /// Open on this tab (sessions · details · announcements · class · team · archive).
  final String? initialTab;

  @override
  State<TeacherSessionsScreen> createState() => _TeacherSessionsScreenState();
}

class _TeacherSessionsScreenState extends State<TeacherSessionsScreen> {
  late String _tab = widget.initialTab ?? (widget.expandDetails == true ? _tabDetails : _tabSessions);

  /// The opening tab was decided (CourseProfileHub.openingTab), or the person / a link chose one.
  late bool _openingDone = widget.initialTab != null || widget.expandDetails == true;

  /// The course profile's parts (announcements · class · team · archive), loaded when one of them opens.
  CourseProfileHub? _hubOrNull;
  CourseProfileHub get _hub => _hubOrNull ??= (widget.profileHub ?? CourseProfileHub(_provider.course.id))
    ..addListener(_onHub);

  void _onHub() {
    if (!mounted) return;
    setState(() {
      // the smart opening tab, once, from the course payload (D-111): unread announcements
      if (_openingDone) return;
      final open = _hubOrNull?.openingTab();
      if (open == null) return;
      _openingDone = true;
      if (open.isNotEmpty) _tab = open;
    });
  }

  /// The course payload's page state (closed · unread announcements) → the profile hub.
  void _seedHub() => _hub.seed(_provider.pageState);

  @override
  void dispose() {
    _hubOrNull?.removeListener(_onHub);
    if (widget.profileHub == null) _hubOrNull?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await Future.wait([_provider.refresh(), _hub.refresh()]);
    if (mounted) _seedHub();
  }

  /// First load finished (later refreshes keep the page on screen).
  bool _loaded = false;

  /// Data Lab switched on for this course (DlConfig.enabled); unknown until loaded.
  bool _dataLab = false;

  TeacherCourseScreenProvider get _provider => context.read<TeacherCourseScreenProvider>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = _provider;
      provider.refresh().whenComplete(() {
        if (!mounted) return;
        setState(() => _loaded = true);
        _seedHub();
      });
      DataLabApi()
          .config(courseId: provider.course.id)
          .catchError((_) => const DlConfig())
          .then((cfg) {
        if (mounted) setState(() => _dataLab = cfg.enabled);
      });
    });
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _setTab(String id) => setState(() {
    _tab = id;
    _openingDone = true;
  });

  void _openAddSheet() => showSessionFormSheet(context);

  Future<void> _openEditCourse() async {
    final provider = _provider;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => deferredCourseForm(course: provider.course)),
    );
    // Refresh header + sessions after editing
    await provider.refresh();
  }

  Future<void> _openSchedules() async {
    final provider = _provider;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TeacherSchedulesScreen(course: provider.course)),
    );
    if (mounted) await provider.refreshCourse();
  }

  void _openStudents() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => EnrolledStudentsScreen(course: _provider.course)),
  );

  void _openCertificate(CourseCertificate cert) => showCertificateManagerSheet(
    context,
    courseId: _provider.course.id,
    certificateId: cert.id,
    certificateTitle: cert.title,
    templateUrl: cert.templateUrl,
  );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BasePage(
      key: const ValueKey('teacher_sessions'),
      useWebCard: true,
      width: AppWidth.wide,
      child: SafeArea(
        top: false,
        child: Selector<TeacherCourseScreenProvider, _PageData>(
          selector: (_, p) => _select(p),
          builder: (context, d, _) =>
              !_loaded && d.loadingAll ? const CourseSpaceSkeleton() : _page(context, d),
        ),
      ),
    );
  }

  Widget _page(BuildContext context, _PageData d) {
    final course = d.course;
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    final title = (ar ? course.titleAr : course.titleEn) ?? course.titleEn ?? course.titleAr ?? '';
    final description = (ar ? course.descriptionAr : course.descriptionEn) ?? '';
    final reel = d.reelUrl;
    final hasReel = reel != null && reel.isNotEmpty && !AppConfig.disableList.contains('course_hero.reel');
    final live = course.type == 'live';
    final rate = course.rateSummary;
    final me = context.read<MyAuthProvider>().currentUser;
    final hub = _hub;
    // Edit: the server's course_settings once the profile is known; the course's own teacher before that
    final canEdit = hub.profile?.caps.courseSettings ?? true;

    // D-941: the header carries the page's ONE New session, its ONE Edit course and Share; the price and the rating are
    // figures of its stats (the side card that repeated them is gone, D-943)
    final hero = CourseSpaceHeroData(
      title: title,
      subtitle: description,
      imageUrl: course.imageUrl,
      category: course.category == null ? null : (ar ? course.category!.nameAr : course.category!.nameEn),
      isPrivate: course.isPrivate,
      privateLabel: 'course_hero_private'.tr,
      // the teacher sees the course as students do: their own name and picture under the title (D-945)
      teacherName: me?.name,
      teacherImageUrl: me?.imageUrl,
      badges: [
        course.isPublished
            ? CourseSpaceBadge(label: _t('منشور', 'Published'), icon: Icons.public_rounded)
            : CourseSpaceBadge(label: _t('مسودة', 'Draft'), icon: Icons.edit_note_rounded, color: c.warning),
        if (live)
          CourseSpaceBadge(label: _t('بث مباشر', 'Live'), icon: Icons.sensors_rounded)
        else if (course.type == 'recorded')
          CourseSpaceBadge(label: _t('دروس مسجّلة', 'Recorded lessons'), icon: Icons.play_circle_outline_rounded),
      ],
      stats: [
        CourseSpaceStat(
          featureKey: 'course_stats.students',
          icon: Icons.groups_rounded,
          value: '${course.studentsCount}',
          label: courseStatNoun(course.studentsCount, 'course_hero_students'),
          onTap: _openStudents,
        ),
        CourseSpaceStat(
          featureKey: 'course_stats.sessions',
          icon: Icons.play_lesson_rounded,
          value: '${d.sessionCount}',
          label: _t('الجلسات', 'Sessions'),
        ),
        CourseSpaceStat(
          featureKey: 'course_stats.duration',
          icon: Icons.schedule_rounded,
          value: courseHoursLabel(course.totalHours),
          label: 'duration'.tr,
        ),
        CourseSpaceStat(
          featureKey: 'course_stats.price',
          icon: Icons.sell_rounded,
          value: coursePriceLabel(course.currency, course.finalPrice ?? 0),
          label: 'cost'.tr,
        ),
        if (rate != null && rate.total > 0)
          CourseSpaceStat(
            featureKey: 'course_stats.rating',
            icon: Icons.star_rounded,
            tone: c.accent2,
            value: rate.average.toStringAsFixed(1),
            label: courseRatingCount(rate.total),
          ),
      ],
      cta: CourseSpaceCta(
        primary: CourseSpaceButton(label: 'add_session_btn'.tr, icon: Icons.add_rounded, onTap: _openAddSheet),
        secondary: canEdit
            ? CourseSpaceButton(label: _t('تعديل الكورس', 'Edit course'), icon: Icons.edit_rounded, onTap: _openEditCourse)
            : null,
        icons: [
          CourseSpaceTopAction(
            icon: Icons.ios_share_rounded,
            tooltip: 'course_hero_share'.tr,
            onTap: () => shareCourseLink(context, course.toCourseModel),
          ),
        ],
        // a draft says once why nobody sees it yet
        caption: course.isPublished
            ? null
            : _t('الطلاب لا يرون الكورس حتى تنشره.', 'Students cannot see the course until you publish it.'),
      ),
    );

    final showRefresh = kIsWeb || MediaQuery.sizeOf(context).width >= Breakpoints.desktop;

    return CourseSpace(
      hero: hero,
      heroBackground: hasReel
          ? CourseReelPlayer(
              key: ValueKey(reel),
              url: reel,
              posterUrl: course.imageUrl.isNotEmpty ? course.imageUrl : null,
            )
          : null,
      onBack: Navigator.of(context).canPop() ? () => Navigator.maybePop(context) : null,
      onRefresh: _refresh,
      topActions: [
        if (helpAvailableForMenu(context, 'teacher.session'))
          CourseSpaceTopAction(
            icon: Icons.info_outline_rounded,
            tooltip: _t('معلومات عن هذه الصفحة', 'About this page'),
            onTap: () => unawaited(showHelpForPage(context, 'teacher.session')),
          ),
        // rarer: the ⋮ menu (refresh is pull-to-refresh on phones)
        courseAskDocsAction(context, course.id, title),
        if (showRefresh)
          CourseSpaceTopAction(icon: Icons.refresh_rounded, tooltip: 'refresh'.tr, overflow: true, onTap: _refresh),
      ],
      spotlight: [
        CourseArchiveSpot(hub: hub, onOpenTab: _setTab),
        if (d.liveId != -1)
          CourseSpotlightCard(
            icon: Icons.sensors_rounded,
            title: '${_t('بث مباشر الآن', 'Live now')}: ${d.liveName}',
            subtitle: _t('الجلسة تعمل الآن — ادخل الغرفة لإدارة البث', 'The session is running — enter the room to manage the stream'),
            color: c.danger,
            filled: true,
            live: true,
            actionLabel: _t('دخول الغرفة', 'Enter room'),
            actionIcon: DirIcons.login,
            // The same call the session row's join button makes for a running session.
            onAction: () => _provider.joinLive(context, d.liveId, course.id, 100, true),
            onTap: () => _setTab(_tabSessions),
          ),
        const _AttendanceSpot(),
        if (_loaded)
          CourseReadinessCard(
            items: [
              CourseReadinessItem(
                label: _t('صورة الغلاف', 'Cover image'),
                done: course.imageUrl.isNotEmpty,
                icon: Icons.image_rounded,
                onTap: _openEditCourse,
              ),
              CourseReadinessItem(
                label: _t('وصف الكورس', 'Description'),
                done: (course.descriptionAr ?? '').trim().isNotEmpty || (course.descriptionEn ?? '').trim().isNotEmpty,
                icon: Icons.notes_rounded,
                onTap: _openEditCourse,
              ),
              if (live)
                CourseReadinessItem(
                  label: 'weekly_schedule'.tr,
                  done: course.schedules.isNotEmpty,
                  icon: Icons.calendar_month_rounded,
                  onTap: _openSchedules,
                ),
              CourseReadinessItem(
                label: _t('أضف أول جلسة', 'Add the first session'),
                done: d.sessionCount > 0,
                icon: Icons.add_circle_outline_rounded,
                onTap: _openAddSheet,
              ),
              CourseReadinessItem(
                label: _t('انشر الكورس', 'Publish the course'),
                done: course.isPublished,
                icon: Icons.public_rounded,
                onTap: _openEditCourse,
              ),
            ],
          ),
      ],
      // the shortcuts: where the header's actions do not go (New session and Edit course are the header's, D-943)
      actions: [
        CourseSpaceAction(
          icon: Icons.groups_rounded,
          label: _t('الطلاب', 'Students'),
          caption: _t('المسجّلون وتقدّمهم', 'Enrolled students and progress'),
          color: c.textMedium,
          onTap: _openStudents,
        ),
        CourseSpaceAction(                                   // the course's exams hub (online + paper / OMR)
          icon: Icons.quiz_rounded,
          label: _t('الاختبارات', 'Exams'),
          caption: _t('أنشئ واطبع وصحّح', 'Create, print and grade'),
          color: c.textMedium,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => deferredTeacherExamHub(courseId: course.id, courseTitle: title, orgId: course.org?.id)),
          ),
        ),
        if (_dataLab)
          CourseSpaceAction(
            featureKey: 'data_lab.entry',
            icon: Icons.science_rounded,
            label: 'dl_title'.tr,
            caption: 'dl_entry_sub'.tr,
            color: c.textMedium,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => deferredDataLab(courseId: course.id, courseTitle: title)),
            ),
          ),
        if (course.type != 'recorded')
          CourseSpaceAction(
            icon: Icons.calendar_month_rounded,
            label: 'weekly_schedule'.tr,
            caption: course.schedules.isEmpty
                ? _t('لم تُضف مواعيد بعد', 'No times yet')
                : _t('${course.schedules.length} مواعيد', '${course.schedules.length} times a week'),
            color: c.textMedium,
            onTap: _openSchedules,
          ),
        if (course.certificates.isNotEmpty)
          CourseSpaceAction(
            icon: Icons.workspace_premium_rounded,
            label: 'certificates'.tr,
            caption: 'manage_certificate_btn'.tr,
            color: c.accent2,
            onTap: () => course.certificates.length == 1
                ? _openCertificate(course.certificates.first)
                : _setTab(_tabDetails),
          ),
      ],
      tabs: [
        CourseSpaceTab(
          id: _tabSessions,
          label: _t('الجلسات', 'Sessions'),
          icon: Icons.play_lesson_rounded,
          count: d.sessionCount,
          live: d.liveId != -1,
          builder: (_) => TeacherSessionsBody(onAdd: _openAddSheet),
        ),
        ...courseProfileTabs(
          hub: hub,
          staff: true,
          org: course.org != null,
          enrolled: false,
          forced: _tab,
          onOpenTab: (id) => _setTab(id == 'sessions' ? _tabSessions : id),
        ),
        // the course roadmap of a personal course of a personal account (D-120): next courses, prerequisites, level
        if (course.org == null && roadmapAllowedHere(context))
          ?courseRoadmapTab(courseId: course.id, staff: true, onOpenCourse: (rc) => _openOwnCoursePreview(context, rc)),
        CourseSpaceTab(
          id: _tabDetails,
          label: _t('عن الكورس', 'About'),
          icon: Icons.info_outline_rounded,
          builder: (_) => TeacherCourseDetails(
            course: course,
            rating: RatingWidget(
              type: RateType.course,
              sourceId: course.id.toString(),
              canEdit: false,
              compact: false,
            ),
            onManageSchedule: _openSchedules,
            onManageCertificate: _openCertificate,
          ),
        ),
      ],
      activeTab: _tab,
      onTab: _setTab,
    );
  }
}

/// ONE attendance entry for the whole course: hidden for recorded / empty courses — unless a web session is
/// waiting for this phone's location, then the entry (with its "share location" card) must always be reachable.
class _AttendanceSpot extends StatelessWidget {
  const _AttendanceSpot();

  @override
  Widget build(BuildContext context) {
    final p = context.select<TeacherCourseScreenProvider, (String?, int)>(
      (p) => (p.course.type, p.sessions.length),
    );
    return ListenableBuilder(
      listenable: TeacherAttendanceController.instance,
      builder: (ctx, _) {
        final waiting = TeacherAttendanceController.instance.webLocationRequested;
        if (!waiting && (p.$1 == 'recorded' || p.$2 == 0)) return const SizedBox.shrink();
        final sessions = ctx.read<TeacherCourseScreenProvider>().sessions;
        return TeacherAttendanceCourseEntry(
          padding: EdgeInsets.zero,
          sessions: [
            for (var i = 0; i < sessions.length; i++)
              LauncherSession(id: sessions[i].id, number: i + 1, name: sessions[i].name, date: sessions[i].scheduledAt),
          ],
        );
      },
    );
  }
}
