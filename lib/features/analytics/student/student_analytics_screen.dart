// lib/features/analytics/student/student_analytics_screen.dart
// The student's analytics — the "Analysis" tab of the dashboard. A calm summary first, the details one tap away:
//
//   • header: "Analytics" + a hello, refresh for mouse users
//   • hero: progress · attendance · exams as concentric rings around the overall figure, ONE sentence
//     ("You're ahead of the class average in 3 of 5 courses."), "+6 vs class" per ring, → my full analytics profile
//   • four count tiles: courses · sessions attended · exams passed · questions saved to review
//   • "For you": up to three plain-language nudges, each opening the course / its attendance / exams / review bank
//   • "Your courses": one bar per course for Progress | Attendance | Exams (segmented), the class average as a tick,
//     → "All courses": search, sorting and every per-course shortcut (attendance · exams · my marks · banks)
//   • "Exam results": the first 3 + Show all
// The words and the ranking are pure (shared/analytics/analytics_summary.dart), the widgets take plain values
// (analytics_summary_ui.dart). Data: the enrolments + the Data Lab profile the provider already loads — no request
// of its own; without the profile (Data Lab off) the page shows progress only.
//
// Uses the dashboard's StudentAnalyticsProvider when there is one (so the dashboard's refresh button refreshes what
// you see), otherwise creates its own.
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart' show AppNavigator;
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import 'package:flutter_education_app/features/analytics/analytics_summary.dart';
import 'package:flutter_education_app/features/analytics/analytics_summary_ui.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_models.dart';
import 'package:flutter_education_app/features/attendance/analysis/student/student_attendance_model.dart';
import 'package:flutter_education_app/features/analytics/student/flags/student_flags_screen.dart';
import 'package:flutter_education_app/features/analytics/student/student_analytics_profile_screen.dart';
import 'package:flutter_education_app/features/analytics/student/student_analytics_provider.dart';
import 'package:flutter_education_app/features/analytics/student/analytics_editorial.dart';
import 'package:flutter_education_app/features/analytics/student/student_analytics_widgets.dart';
import 'package:flutter_education_app/features/analytics/student/student_course_analytics_screen.dart';

class StudentAnalyticsScreen extends StatelessWidget {
  const StudentAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    StudentAnalyticsProvider? ambient;
    try {
      ambient = Provider.of<StudentAnalyticsProvider>(context, listen: false);
    } on ProviderNotFoundException {
      ambient = null;
    }
    if (ambient != null) return const _StudentAnalyticsView();
    return ChangeNotifierProvider(create: (_) => StudentAnalyticsProvider(), child: const _StudentAnalyticsView());
  }
}

/// A Data Lab column's class average ('progress', 'attendance', 'exam_avg'), when the teacher shares it.
double? _classAvg(DlCourseBlock? b, String key) {
  for (final c in b?.columns ?? const <DlProfileColumn>[]) {
    if (c.key == key) return c.classAvg;
  }
  return null;
}

/// The provider's courses as plain numbers for the summary.
List<AnCourseFacts> studentCourseFacts(StudentAnalyticsProvider prov) => [
      for (final c in prov.courses)
        () {
          final b = prov.blockOf(c.id);
          final progress = prov.progressOf(c);
          return AnCourseFacts(
            id: c.id,
            title: c.title,
            subtitle: c.teacherName,
            progress: progress,
            attendance: b?.attendance,
            exams: b?.examAvg,
            // N5: the class on the scale of the enrolment's progress (a cohort of one is level, never "11 below")
            classProgress: anClassOnScale(shown: progress, mine: b?.progress, cls: _classAvg(b, 'progress')),
            classAttendance: _classAvg(b, 'attendance'),
            classExams: _classAvg(b, 'exam_avg'),
            attended: b?.attended ?? 0,
            held: b?.held ?? 0,
            lectures: c.sessionsCount,
            reviewFlags: b?.reviewFlags ?? 0,
          );
        }(),
    ];

// ── Summary view ─────────────────────────────────────────────────────────────

class _StudentAnalyticsView extends StatefulWidget {
  const _StudentAnalyticsView();

  @override
  State<_StudentAnalyticsView> createState() => _StudentAnalyticsViewState();
}

class _StudentAnalyticsViewState extends State<_StudentAnalyticsView> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  AnMetric _metric = AnMetric.progress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = context.read<StudentAnalyticsProvider>();
      if (!p.loadedOnce && !p.loading) p.loadCourses();
    });
  }

  EnrolledCourse? _course(int? id) {
    for (final c in context.read<StudentAnalyticsProvider>().courses) {
      if (c.id == id) return c;
    }
    return null;
  }

  void _openCourse(int? id, int tab) {
    final course = _course(id);
    if (course == null) return;
    final prov = context.read<StudentAnalyticsProvider>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentCourseAnalyticsScreen(
          courseId: course.id,
          courseTitle: course.title,
          initialTab: tab,
          initialBlock: prov.blockOf(course.id),
          progress: prov.progressOf(course),
        ),
      ),
    );
  }

  void _openFlags(int? id) {
    final course = _course(id);
    if (course == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StudentFlagsScreen(courseId: course.id, courseTitle: course.title, initialTab: 0)),
    );
  }

  void _openAll() {
    final prov = context.read<StudentAnalyticsProvider>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider<StudentAnalyticsProvider>.value(value: prov, child: const _AllCoursesPage()),
      ),
    );
  }

  VoidCallback? _insightAction(AnInsight i) => switch (i.target) {
        AnTarget.course => () => _openCourse(i.courseId, 0),
        AnTarget.attendance => () => _openCourse(i.courseId, 1),
        AnTarget.exams => () => _openCourse(i.courseId, 2),
        AnTarget.review => () => _openFlags(i.courseId),
        AnTarget.dataLab || AnTarget.none => null,
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final prov = context.watch<StudentAnalyticsProvider>();
    final c = context.colors;

    final Widget body;
    if (prov.loading && !prov.loadedOnce) {
      body = const AnSummarySkeleton();
    } else if (prov.error != null && prov.courses.isEmpty) {
      body = _withHeader(prov, AppErrorState(message: prov.error!, onRetry: prov.loadCourses));
    } else if (prov.courses.isEmpty) {
      body = _withHeader(
        prov,
        AppEmpty(
          icon: Icons.school_outlined,
          title: 'an_no_courses'.tr,
          message: 'an_go_enroll'.tr,
          // the dashboard listens: the "My courses" tab opens (nothing happens when that tab is switched off)
          actionLabel: 'my_courses'.tr,
          onAction: () => AppNavigator.requestedTab.value = 'my_courses',
        ),
      );
    } else {
      body = _summary(prov);
    }

    return BasePage(
      key: const ValueKey('analytics'),
      useWebCard: true,
      width: AppWidth.wide,
      child: ColoredBox(
        color: c.background,
        child: AppRefresh(
          onRefresh: prov.loadCourses,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [SliverToBoxAdapter(child: body)],
          ),
        ),
      ),
    );
  }

  Widget _header(StudentAnalyticsProvider prov) {
    final first = (prov.profile?.name ?? '').trim().split(RegExp(r'\s+')).first;
    return AnalyticsMasthead(
      title: anTr('an2_title', 'Analytics'),
      subtitle: first.isEmpty
          ? anTr('an2_sub_student', 'How your learning is going')
          : anFmt('an2_sub_student_name', {'name': first}, 'Hi {name}, here is how your learning is going.'),
      actions: [AnalyticsHeaderAction(icon: Icons.refresh_rounded, tooltip: anTr('an_refresh', 'Refresh'), onTap: prov.loadCourses)],
    );
  }

  Widget _withHeader(StudentAnalyticsProvider prov, Widget child) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(prov),
          AppSpace.gapLg,
          child,
        ]),
      );

  Widget _summary(StudentAnalyticsProvider prov) {
    final facts = studentCourseFacts(prov);
    final totals = anTotals(facts);
    final p = prov.profile;
    final metrics = p == null ? const [AnMetric.progress] : anAvailableMetrics(facts);
    final metric = metrics.contains(_metric) ? _metric : (metrics.isEmpty ? AnMetric.progress : metrics.first);

    // ── hero: the page's one memorable element, the learner's rings on the peach block
    final rings = [
      for (final m in p == null ? const [AnMetric.progress] : AnMetric.values)
        AnRingSpec(
          metric: m,
          value: totals.value(m),
          delta: totals.delta(m),
          detail: m == AnMetric.attendance && totals.held > 0
              ? anFmt('an2_sessions_of', {'a': totals.attended, 'sessions': anSessionsWord(totals.held)}, '{a} of {sessions}')
              : null,
        ),
    ];
    final hero = ParentComponent(
      featureKey: 'analytics.header',
      child: AnalyticsHeroBlock(
        headline: anHeadlineText(studentHeadline(facts)),
        rings: rings,
        overall: p == null ? totals.progress : totals.overall,
        overallLabel: p == null ? anMetricLabel(AnMetric.progress) : null,
        memoryKey: 'analytics.overall',
        footer: p == null
            ? null
            : ParentComponent(
                featureKey: 'data_lab.my_profile',
                child: AnShowAllRow(
                  label: anTr('an_full_profile', 'My full analytics profile'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudentAnalyticsProfileScreen.forStudent())),
                ),
              ),
      ),
    );

    // ── tiles: four counts; the key one (exams passed, or what is finished without the profile) is a block that rolls
    final allExams = <(EnrolledCourse, DlExam)>[
      for (final course in prov.courses)
        for (final e in prov.blockOf(course.id)?.exams ?? const <DlExam>[])
          if (e.best != null) (course, e),
    ];
    final passed = allExams.where((x) => x.$2.passed ?? (x.$2.best! >= 50)).length;
    final completed = facts.where((x) => (x.progress ?? 0) >= 100).length;
    final tiles = AppKpiGrid(children: [
      if (p != null) ...[
        AppKpiCard(
          icon: Icons.verified_rounded,
          label: anTr('an2_tile_passed', 'Exams passed'),
          value: allExams.isEmpty ? '–' : '$passed/${allExams.length}',
          highlight: true,
          // every exam passed is an achievement: the gold block
          tone: allExams.isNotEmpty && passed == allExams.length ? AppBlockTone.gold : AppBlockTone.peach,
        ),
        AppKpiCard(
          icon: Icons.menu_book_rounded,
          label: anTr('an_courses', 'Courses'),
          value: '${prov.courses.length}',
          onTap: _openAll,
        ),
        AppKpiCard(
          icon: Icons.event_available_rounded,
          label: anTr('an2_tile_attended', 'Sessions attended'),
          value: totals.held == 0 ? '–' : '${totals.attended}/${totals.held}',
        ),
        AppKpiCard(
          icon: Icons.bookmark_rounded,
          label: anTr('an2_tile_saved', 'Saved to review'),
          value: '${p.reviewFlags}',
        ),
      ] else ...[
        AppKpiCard(
          icon: Icons.task_alt_rounded,
          label: anTr('an2_tile_completed', 'Completed'),
          value: '$completed',
          highlight: true,
          tone: completed > 0 ? AppBlockTone.emerald : AppBlockTone.peach,
        ),
        AppKpiCard(
          icon: Icons.menu_book_rounded,
          label: anTr('an_courses', 'Courses'),
          value: '${prov.courses.length}',
          onTap: _openAll,
        ),
        AppKpiCard(
          icon: Icons.video_library_rounded,
          label: anTr('an2_tile_lectures', 'Lectures'),
          value: '${prov.courses.fold<int>(0, (s, x) => s + x.sessionsCount)}',
        ),
        AppKpiCard(
          icon: Icons.play_circle_rounded,
          label: anTr('an2_tile_in_progress', 'In progress'),
          value: '${facts.where((x) => (x.progress ?? 0) > 0 && (x.progress ?? 0) < 100).length}',
        ),
      ],
    ]);

    // ── for you
    final insights = studentInsights(facts);
    final insightCard = insights.isEmpty
        ? null
        : AnInsightCard(
            title: anTr('an2_for_you', 'For you'),
            rows: [for (final i in insights) AnInsightRowData(tone: i.tone, text: anInsightText(i), onTap: _insightAction(i))],
          );

    // ── courses chart
    final tab = switch (metric) {
      AnMetric.progress => 0,
      AnMetric.attendance => 1,
      AnMetric.exams => 2,
    };
    final chart = AnCourseBars(
      title: anTr('an2_your_courses', 'Your courses'),
      metric: metric,
      metrics: metrics,
      onMetric: (m) => setState(() => _metric = m),
      rows: [
        for (final f in anRankBy(facts, metric))
          AnBarRowData(
            title: f.title,
            value: f.value(metric),
            classValue: f.classValue(metric),
            detail: metric == AnMetric.attendance && f.held > 0 ? '${f.attended}/${f.held}' : null,
            flag: anCourseNeedsAttention(f),
            onTap: () => _openCourse(f.id, tab),
          ),
      ],
      onShowAll: _openAll,
      showAllLabel: anFmt('an2_all_courses', {'n': facts.length}, 'All courses ({n})'),
    );

    // ── exam results: the ones below the pass mark first (they need you), then the best
    allExams.sort((a, b) {
      final pa = (a.$2.passed ?? a.$2.best! >= 50) ? 1 : 0, pb = (b.$2.passed ?? b.$2.best! >= 50) ? 1 : 0;
      if (pa != pb) return pa.compareTo(pb);
      return b.$2.best!.compareTo(a.$2.best!);
    });
    final exams = p == null || allExams.isEmpty
        ? null
        : AnCompactList(
            title: anTr('an2_exam_results', 'Exam results'),
            subtitle: anFmt('an2_passed_of', {'n': passed, 'm': allExams.length}, '{n} of {m} passed'),
            rows: [
              for (final (course, e) in allExams)
                AnExamRow(
                  name: e.name,
                  course: course.title,
                  score: e.best,
                  passed: e.passed,
                  onTap: () => _openCourse(course.id, 2),
                ),
            ],
          );

    return AnSummaryLayout(
      header: _header(prov),
      hero: hero,
      tiles: tiles,
      insights: insightCard,
      chart: chart,
      lists: [?exams],
    );
  }
}

// ── All courses (search · sort · every per-course shortcut) ─────────────────

class _AllCoursesPage extends StatefulWidget {
  const _AllCoursesPage();

  @override
  State<_AllCoursesPage> createState() => _AllCoursesPageState();
}

class _AllCoursesPageState extends State<_AllCoursesPage> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openCourse(EnrolledCourse course, int tab) {
    final prov = context.read<StudentAnalyticsProvider>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentCourseAnalyticsScreen(
          courseId: course.id,
          courseTitle: course.title,
          initialTab: tab,
          initialBlock: prov.blockOf(course.id),
          progress: prov.progressOf(course),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<StudentAnalyticsProvider>();
    final list = prov.filtered;
    return BasePage(
      useWebCard: true,
      width: AppWidth.wide,
      appBar: AppHeader(title: anTr('an2_all_courses_title', 'All courses')),
      child: AppRefresh(
        onRefresh: prov.loadCourses,
        child: LayoutBuilder(builder: (context, box) {
          // one reading column, centred: the cards read top to bottom like a report
          final side = (box.maxWidth - AppWidth.reading.inside(box.maxWidth)) / 2;
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(side, AppSpace.xs, side, AppSpace.sm),
                sliver: SliverToBoxAdapter(child: ParentComponent(featureKey: 'analytics.search', child: _tools(prov))),
              ),
              if (prov.attentionCount > 0 && prov.search.isEmpty)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 0, side, AppSpace.sm),
                  sliver: SliverToBoxAdapter(
                    child: _AttentionBanner(
                      count: prov.attentionCount,
                      active: prov.sort == AnSort.attention,
                      onTap: () => prov.setSort(AnSort.attention),
                    ),
                  ),
                ),
              if (list.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppEmpty(icon: Icons.search_off_rounded, title: 'an_no_results'.tr),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, AppSpace.xxs, side, AppSpace.xl),
                  sliver: SliverList.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => AppSpace.gapSm,
                    itemBuilder: (_, i) => AppReveal(
                      index: i,
                      group: 'an_all_courses',
                      child: _CourseCard(
                        course: list[i],
                        block: prov.blockOf(list[i].id),
                        progress: prov.progressOf(list[i]),
                        overall: prov.overallOf(list[i]),
                        needsAttention: prov.needsAttention(list[i]),
                        profileOn: prov.profile != null,
                        onOpen: (tab) => _openCourse(list[i], tab),
                      ),
                    ),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _tools(StudentAnalyticsProvider prov) {
    // the sorts as one pill track, in the order they are read
    final sorts = [
      (AnSort.name, Icons.sort_by_alpha_rounded, anTr('an_sort_name', 'A–Z')),
      if (prov.profile != null) (AnSort.attention, Icons.volunteer_activism_rounded, anTr('an_sort_attention', 'Needs attention')),
      (AnSort.progress, Icons.trending_up_rounded, anTr('an_sort_progress', 'Progress')),
    ];
    final at = sorts.indexWhere((s) => s.$1 == prov.sort);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSearchField(
        controller: _searchCtrl,
        hint: 'an_search_hint'.tr,
        debounce: Duration.zero,
        onChanged: prov.setSearch,
      ),
      AppSpace.gapSm,
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppTabs(
          items: [for (final s in sorts) AppTabItem(s.$3, icon: s.$2)],
          index: at < 0 ? 0 : at,
          onChanged: (i) => prov.setSort(sorts[i].$1),
        ),
      ),
    ]);
  }
}

/// "N of your courses could use a little extra attention" — a warm note that sorts them first.
class _AttentionBanner extends StatelessWidget {
  const _AttentionBanner({required this.count, required this.active, required this.onTap});

  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = appTintOn(context, c.warning, surface: c.background);
    final ink = appInkOn(context, c.warning, tint);
    return Material(
      color: tint,
      borderRadius: AppRadius.cardAll,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: active ? null : onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
            child: Row(children: [
              Icon(Icons.volunteer_activism_rounded, color: ink, size: AppIconSize.md),
              AppSpace.gapSm,
              Expanded(
                child: Text(
                  anFmt('an_attention', {'n': count}, '{n} of your courses could use a little extra attention.'),
                  style: AppType.bodyStrong(context),
                ),
              ),
              if (!active) ...[
                AppSpace.gapSm,
                Text(anTr('an_show_first', 'Show first'), style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Course card ───────────────────────────────────────────────────────────────

class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.course,
    required this.block,
    required this.progress,
    required this.overall,
    required this.needsAttention,
    required this.profileOn,
    required this.onOpen,
  });

  final EnrolledCourse course;
  final DlCourseBlock? block;
  final double progress;
  final double? overall;
  final bool needsAttention, profileOn;
  final ValueChanged<int> onOpen;

  /// The width of a metric's label column (the bars line up under each other).
  static const double _metricLabel = 104;

  /// The width of a metric's figure column.
  static const double _metricFigure = 48;

  /// The overall ring beside the title.
  static const double _ring = 56;
  static const double _ringStroke = 5;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = block;
    Widget metric(String label, double? v, IconData icon) => Padding(
      padding: const EdgeInsets.only(top: AppSpace.xs),
      child: Row(children: [
        Icon(icon, size: AppIconSize.xs, color: c.textLight),
        const SizedBox(width: AppSpace.xs),
        SizedBox(
          width: _metricLabel,
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
        ),
        Expanded(child: AnBar(value: v, height: AppSpace.xs - 2)),
        SizedBox(
          width: _metricFigure,
          child: Text(
            anPct(v),
            textAlign: TextAlign.end,
            style: AppType.row(context).copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ]),
    );

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => onOpen(0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.md, AppSpace.sm, AppSpace.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnalyticsCourseMark(courseId: course.id, imageUrl: course.imageUrl, size: AppTouch.primary),
            AppSpace.gapSm,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(course.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                if (course.teacherName != null && course.teacherName!.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xxs),
                  AnalyticsFact(icon: Icons.person_outline_rounded, text: course.teacherName!),
                ],
                if (needsAttention) ...[
                  const SizedBox(height: AppSpace.xs),
                  AppStatusBadge(
                    label: anTr('an_needs_attention', 'Needs attention'),
                    tone: AppTone.warning,
                    icon: Icons.volunteer_activism_rounded,
                  ),
                ],
              ]),
            ),
            AppSpace.gapXs,
            if (overall != null)
              Tooltip(
                message: anTr('sa_overall_hint_full', 'An average of your progress, attendance and exam results.'),
                child: AnRing(value: overall, size: _ring, stroke: _ringStroke),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xxs),
          child: Column(children: [
            metric(anTr('an_course_progress', 'Course progress'), progress, Icons.route_rounded),
            if (b != null) ...[
              metric('attendance_rate'.tr, b.attendance, Icons.event_available_rounded),
              metric('sa_avg_score'.tr, b.examAvg, Icons.bar_chart_rounded),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.sm, AppSpace.sm),
          child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ParentComponent(
              featureKey: 'analytics.attendance_chip',
              child: AnalyticsShortcut(icon: Icons.fact_check_rounded, label: 'an_attendance'.tr, color: c.success, onTap: () => onOpen(1)),
            ),
            ParentComponent(
              featureKey: 'analytics.exams_chip',
              child: AnalyticsShortcut(icon: Icons.quiz_rounded, label: 'an_exams'.tr, color: c.primary, onTap: () => onOpen(2)),
            ),
            if (profileOn)
              ParentComponent(
                featureKey: 'analytics.marks_chip',
                child: AnalyticsShortcut(
                  icon: Icons.workspace_premium_rounded,
                  label: anTr('sa_tab_marks', 'My marks'),
                  color: c.purple,
                  badge: b?.extraColumns.length,
                  onTap: () => onOpen(3),
                ),
              ),
            ParentComponent(
              featureKey: 'analytics.review_chip',
              child: AnalyticsShortcut(
                icon: Icons.bookmark_rounded,
                label: 'flag_review_bank'.tr,
                color: c.warning,
                badge: b?.reviewFlags,
                onTap: () => _flags(context, 0),
              ),
            ),
            ParentComponent(
              featureKey: 'analytics.read_flags_chip',
              child: AnalyticsShortcut(
                icon: Icons.menu_book_rounded,
                label: 'flag_read_bank'.tr,
                color: c.danger,
                badge: b?.readFlags,
                onTap: () => _flags(context, 1),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs),
              child: AnalyticsFact(icon: Icons.video_library_outlined, text: '${course.sessionsCount} ${'an_lectures'.tr}'),
            ),
          ]),
        ),
      ]),
    );
  }

  void _flags(BuildContext context, int tab) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => StudentFlagsScreen(courseId: course.id, courseTitle: course.title, initialTab: tab)),
  );
}
