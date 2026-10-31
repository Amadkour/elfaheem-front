// lib/features/student/analysis/student_analytics_screen.dart
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
import 'package:flutter_education_app/design/app_charts.dart' show appChartPalette;
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart' show AppNavigator;
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../shared/analytics/analytics_summary.dart';
import '../../shared/analytics/analytics_summary_ui.dart';
import '../../teacher/data_lab/data_lab_models.dart';
import 'attendance/student_attendance_model.dart';
import 'flags/student_flags_screen.dart';
import 'student_analytics_profile_screen.dart';
import 'student_analytics_provider.dart';
import 'student_analytics_widgets.dart';
import 'student_course_analytics_screen.dart';

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
      body = _withHeader(prov, AnErrorRetry(message: prov.error!, onRetry: prov.loadCourses));
    } else if (prov.courses.isEmpty) {
      body = _withHeader(
        prov,
        AnEmpty(
          icon: Icons.school_outlined,
          title: 'an_no_courses'.tr,
          sub: 'an_go_enroll'.tr,
          // the dashboard listens: the "My courses" tab opens (nothing happens when that tab is switched off)
          action: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: c.primary,
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => AppNavigator.requestedTab.value = 'my_courses',
            icon: Icon(Icons.menu_book_rounded, color: c.onHero, size: 20),
            label: Text('my_courses'.tr, style: anText(14, w: FontWeight.w700, c: c.onHero)),
          ),
        ),
      );
    } else {
      body = _summary(prov);
    }

    return BasePage(
      key: const ValueKey('analytics'),
      useWebCard: true,
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
    return AnPageHeader(
      title: anTr('an2_title', 'Analytics'),
      subtitle: first.isEmpty
          ? anTr('an2_sub_student', 'How your learning is going')
          : anFmt('an2_sub_student_name', {'name': first}, 'Hi {name}, here is how your learning is going.'),
      actions: [AnHeaderIcon(icon: Icons.refresh_rounded, tooltip: anTr('an_refresh', 'Refresh'), onTap: prov.loadCourses)],
    );
  }

  Widget _withHeader(StudentAnalyticsProvider prov, Widget child) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(prov),
          const SizedBox(height: 24),
          child,
        ]),
      );

  Widget _summary(StudentAnalyticsProvider prov) {
    final c = context.colors;
    final facts = studentCourseFacts(prov);
    final totals = anTotals(facts);
    final p = prov.profile;
    final metrics = p == null ? const [AnMetric.progress] : anAvailableMetrics(facts);
    final metric = metrics.contains(_metric) ? _metric : (metrics.isEmpty ? AnMetric.progress : metrics.first);

    // ── hero
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
      child: AnSummaryHero(
        headline: anHeadlineText(studentHeadline(facts)),
        rings: rings,
        overall: p == null ? totals.progress : totals.overall,
        overallLabel: p == null ? anMetricLabel(AnMetric.progress) : null,
        footer: p == null
            ? null
            : ParentComponent(
                featureKey: 'data_lab.my_profile',
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Divider(height: 1, thickness: 0.7, color: c.divider.withValues(alpha: 0.7)),
                  const SizedBox(height: 4),
                  AnShowAllRow(
                    label: anTr('an_full_profile', 'My full analytics profile'),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudentAnalyticsProfileScreen.forStudent())),
                  ),
                ]),
              ),
      ),
    );

    // ── tiles
    final allExams = <(EnrolledCourse, DlExam)>[
      for (final course in prov.courses)
        for (final e in prov.blockOf(course.id)?.exams ?? const <DlExam>[])
          if (e.best != null) (course, e),
    ];
    final passed = allExams.where((x) => x.$2.passed ?? (x.$2.best! >= 50)).length;
    final tiles = AnStatTiles(tiles: [
      AnTileSpec(
        icon: Icons.menu_book_rounded,
        label: anTr('an_courses', 'Courses'),
        value: '${prov.courses.length}',
        color: anMetricColor(context, AnMetric.progress),
        onTap: _openAll,
      ),
      if (p != null) ...[
        AnTileSpec(
          icon: Icons.event_available_rounded,
          label: anTr('an2_tile_attended', 'Sessions attended'),
          value: totals.held == 0 ? '–' : '${totals.attended}/${totals.held}',
          color: anMetricColor(context, AnMetric.attendance),
        ),
        AnTileSpec(
          icon: Icons.verified_rounded,
          label: anTr('an2_tile_passed', 'Exams passed'),
          value: allExams.isEmpty ? '–' : '$passed/${allExams.length}',
          color: anMetricColor(context, AnMetric.exams),
        ),
        AnTileSpec(
          icon: Icons.bookmark_rounded,
          label: anTr('an2_tile_saved', 'Saved to review'),
          value: '${p.reviewFlags}',
          color: anSpareColor(context),
        ),
      ] else ...[
        AnTileSpec(
          icon: Icons.video_library_rounded,
          label: anTr('an2_tile_lectures', 'Lectures'),
          value: '${prov.courses.fold<int>(0, (s, x) => s + x.sessionsCount)}',
          color: appChartPalette(context)[1],
        ),
        AnTileSpec(
          icon: Icons.play_circle_rounded,
          label: anTr('an2_tile_in_progress', 'In progress'),
          value: '${facts.where((x) => (x.progress ?? 0) > 0 && (x.progress ?? 0) < 100).length}',
          color: appChartPalette(context)[2],
        ),
        AnTileSpec(
          icon: Icons.task_alt_rounded,
          label: anTr('an2_tile_completed', 'Completed'),
          value: '${facts.where((x) => (x.progress ?? 0) >= 100).length}',
          color: appChartPalette(context)[3],
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
    final c = context.colors;
    final list = prov.filtered;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(anTr('an2_all_courses_title', 'All courses'), style: anText(17, w: FontWeight.w800, c: c.textDark)),
      ),
      body: AppRefresh(
        onRefresh: prov.loadCourses,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(child: ParentComponent(featureKey: 'analytics.search', child: _tools(prov))),
            if (prov.attentionCount > 0 && prov.search.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
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
                child: AnEmpty(icon: Icons.search_off_rounded, title: 'an_no_results'.tr),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                sliver: SliverList.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (_, i) => _CourseCard(
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
          ],
        ),
      ),
    );
  }

  Widget _tools(StudentAnalyticsProvider prov) {
    final c = context.colors;
    OutlineInputBorder b(Color col, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: col, width: w));
    Widget sortChip(AnSort s, IconData icon, String label) {
      final on = prov.sort == s;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: ChoiceChip(
          selected: on,
          showCheckmark: false,
          avatar: Icon(icon, size: 16, color: on ? c.onHero : c.textMedium),
          label: Text(label, style: anText(12, w: FontWeight.w700, c: on ? c.onHero : c.textDark)),
          selectedColor: c.primary,
          backgroundColor: c.cardBg,
          side: BorderSide(color: on ? c.primary : c.divider),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (_) => prov.setSort(s),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Column(children: [
        TextField(
          controller: _searchCtrl,
          onChanged: prov.setSearch,
          textInputAction: TextInputAction.search,
          style: anText(14, c: c.textDark),
          decoration: InputDecoration(
            hintText: 'an_search_hint'.tr,
            hintStyle: anText(13, c: c.textLight),
            prefixIcon: Icon(Icons.search_rounded, color: c.textMedium, size: 20),
            suffixIcon: prov.search.isNotEmpty
                ? IconButton(
                    tooltip: MaterialLocalizations.of(context).clearButtonTooltip,
                    icon: Icon(Icons.close_rounded, color: c.textMedium, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      prov.setSearch('');
                    },
                  )
                : null,
            filled: true,
            fillColor: c.cardBg,
            border: b(c.divider),
            enabledBorder: b(c.divider),
            focusedBorder: b(c.primary, 1.6),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 38,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            sortChip(AnSort.name, Icons.sort_by_alpha_rounded, anTr('an_sort_name', 'A–Z')),
            if (prov.profile != null)
              sortChip(AnSort.attention, Icons.volunteer_activism_rounded, anTr('an_sort_attention', 'Needs attention')),
            sortChip(AnSort.progress, Icons.trending_up_rounded, anTr('an_sort_progress', 'Progress')),
          ]),
        ),
      ]),
    );
  }
}

class _AttentionBanner extends StatelessWidget {
  const _AttentionBanner({required this.count, required this.active, required this.onTap});

  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.warning.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: active ? null : onTap,
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 11, 10, 11),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: c.warning.withValues(alpha: 0.3))),
          child: Row(children: [
            Icon(Icons.volunteer_activism_rounded, color: c.warning, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                anFmt('an_attention', {'n': count}, '{n} of your courses could use a little extra attention.'),
                style: anText(12.5, w: FontWeight.w600, c: c.textDark, h: 1.4),
              ),
            ),
            if (!active) Text(anTr('an_show_first', 'Show first'), style: anText(12, w: FontWeight.w800, c: c.warning)),
          ]),
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = block;
    Widget metric(String label, double? v, IconData icon) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Icon(icon, size: 14, color: c.textLight),
        const SizedBox(width: 6),
        SizedBox(width: 92, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(11.5, c: c.textMedium))),
        Expanded(child: AnBar(value: v, height: 6)),
        SizedBox(
          width: 44,
          child: Text(anPct(v), textAlign: TextAlign.end, style: anText(12, w: FontWeight.w800, c: anScoreColor(context, v))),
        ),
      ]),
    );

    return AnCard(
      padding: EdgeInsets.zero,
      borderColor: needsAttention ? c.warning.withValues(alpha: 0.45) : null,
      onTap: () => onOpen(0),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [c.primary.withValues(alpha: 0.07), Colors.transparent],
            ),
          ),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: course.imageUrl != null && course.imageUrl!.isNotEmpty
                  ? Image.network(course.imageUrl!, width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, _, _) => _placeholder(context))
                  : _placeholder(context),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(course.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(15, w: FontWeight.w800, c: c.textDark)),
                if (course.teacherName != null && course.teacherName!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.person_outline_rounded, size: 13, color: c.textLight),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(course.teacherName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(12, c: c.textMedium)),
                    ),
                  ]),
                ],
                if (needsAttention) ...[
                  const SizedBox(height: 5),
                  AnTag(anTr('an_needs_attention', 'Needs attention'), c.warning, icon: Icons.volunteer_activism_rounded),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            if (overall != null)
              Tooltip(
                message: anTr('sa_overall_hint_full', 'An average of your progress, attendance and exam results.'),
                child: AnRing(value: overall, size: 54, stroke: 5),
              )
            else
              Icon(Icons.arrow_forward_ios_rounded, size: 16, color: c.textLight),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Column(children: [
            metric(anTr('an_course_progress', 'Course progress'), progress, Icons.route_rounded),
            if (b != null) ...[
              metric('attendance_rate'.tr, b.attendance, Icons.event_available_rounded),
              metric('sa_avg_score'.tr, b.examAvg, Icons.bar_chart_rounded),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                ParentComponent(
                  featureKey: 'analytics.attendance_chip',
                  child: AnChip(icon: Icons.fact_check_rounded, label: 'an_attendance'.tr, color: c.success, onTap: () => onOpen(1)),
                ),
                ParentComponent(
                  featureKey: 'analytics.exams_chip',
                  child: AnChip(icon: Icons.quiz_rounded, label: 'an_exams'.tr, color: c.primary, onTap: () => onOpen(2)),
                ),
                if (profileOn)
                  ParentComponent(
                    featureKey: 'analytics.marks_chip',
                    child: AnChip(
                      icon: Icons.workspace_premium_rounded,
                      label: anTr('sa_tab_marks', 'My marks'),
                      color: c.purple,
                      badge: b?.extraColumns.length,
                      onTap: () => onOpen(3),
                    ),
                  ),
                ParentComponent(
                  featureKey: 'analytics.review_chip',
                  child: AnChip(
                    icon: Icons.bookmark_rounded,
                    label: 'flag_review_bank'.tr,
                    color: c.warning,
                    badge: b?.reviewFlags,
                    onTap: () => _flags(context, 0),
                  ),
                ),
                ParentComponent(
                  featureKey: 'analytics.read_flags_chip',
                  child: AnChip(
                    icon: Icons.menu_book_rounded,
                    label: 'flag_read_bank'.tr,
                    color: c.danger,
                    badge: b?.readFlags,
                    onTap: () => _flags(context, 1),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.video_library_outlined, size: 13, color: c.textLight),
              const SizedBox(width: 3),
              Text('${course.sessionsCount} ${'an_lectures'.tr}', style: anText(11.5, c: c.textLight)),
            ]),
          ]),
        ),
      ]),
    );
  }

  void _flags(BuildContext context, int tab) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => StudentFlagsScreen(courseId: course.id, courseTitle: course.title, initialTab: tab)),
  );

  Widget _placeholder(BuildContext context) => Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(color: context.colors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
    child: Icon(Icons.menu_book_rounded, color: context.colors.primary, size: 24),
  );
}
