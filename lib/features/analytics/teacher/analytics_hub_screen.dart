// lib/features/analytics/teacher/analytics_hub_screen.dart
// The instructor's analytics — the "Analysis" tab (kill switch teacher_tab_analysis). Same summary language as the
// student's (shared/analytics/analytics_summary*.dart):
//
//   • header: "Analytics" + one line, refresh for mouse users
//   • hero: class progress · attendance · exam average (averaged over the courses) as concentric rings, ONE sentence
//     ("6 students could use your attention this week.")
//   • four count tiles: courses · students · need attention · exam pass rate
//   • "For you": students at risk, weak attendance, a low pass rate, marks not shared yet, the strongest class
//   • "Your classes": one bar per course for Progress | Attendance | Exams (segmented); a bar opens the course's tools
//     (Data Lab · Attendance · Exams · Read flags); "All courses" = search + the full course cards
//   • "Needs your attention": students under 60 % attendance or 50 % in exams across every course, the first 3 +
//     Show all — tap one → their analytics profile (the same profile the student and the parent see)
// The class numbers come from GET /api/v1/data-lab/overview (one call for every course); when Data Lab is off for a
// course it simply has no figures and keeps its shortcuts.
library;

import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/analytics/analytics_summary.dart';
import 'package:flutter_education_app/features/analytics/analytics_summary_ui.dart';
import 'package:flutter_education_app/features/analytics/analytics_ui.dart';
import 'package:flutter_education_app/features/analytics/student/student_analytics_profile_screen.dart';
import 'package:flutter_education_app/features/analytics/student/analytics_editorial.dart';
import 'package:flutter_education_app/features/analytics/student/student_analytics_provider.dart';
import 'package:flutter_education_app/features/courses/teacher/teacher_courses_provider.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_api.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_models.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';
import 'package:flutter_education_app/features/attendance/analysis/teacher/teacher_attendance_screen.dart';
import 'package:flutter_education_app/features/analytics/teacher/flags/teacher_read_flags_screen.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppEase, AppPressScale, AppReveal;

String _courseTitle(TeacherCourse c) => (AppConfig.lang == 'ar' ? c.titleAr : c.titleEn) ?? c.titleAr ?? c.titleEn ?? '';

/// Class snapshot of one course (from /data-lab/overview).
class _Snapshot {
  _Snapshot(this.j);

  final Map<String, dynamic> j;

  bool get enabled => j['enabled'] != false;
  double? n(String k) => dlNum(j[k]);
  int get atRisk => (j['at_risk'] as num?)?.toInt() ?? 0;
  int get published => (j['published_columns'] as num?)?.toInt() ?? 0;
  List<Map<String, dynamic>> get risk => dlList(j['at_risk_preview']);
}

class _OverviewStore extends ChangeNotifier {
  final _api = DataLabApi();
  Map<int, _Snapshot> byCourse = {};
  bool loading = false, failed = false;
  String _sig = '';

  /// True once a load for the current course list finished (well or not).
  bool get settled => !loading && _sig.isNotEmpty;

  Future<void> load(List<int> ids, {bool force = false}) async {
    final sig = ids.join(',');
    if (!force && sig == _sig) return;
    _sig = sig;
    if (ids.isEmpty) return;
    loading = true;
    notifyListeners();
    try {
      final r = await _api.overview(courseIds: ids);
      byCourse = {for (final x in dlList(r['items'])) (x['course_id'] as num).toInt(): _Snapshot(x)};
      failed = false;
    } catch (_) {
      failed = true; // the hub still works: the courses just have no figures
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

/// A course + its class snapshot as plain numbers for the summary.
AnCourseFacts _facts(TeacherCourse c, _Snapshot? s) {
  final on = s != null && s.enabled;
  return AnCourseFacts(
    id: c.id,
    title: _courseTitle(c),
    progress: on ? s.n('progress') : null,
    attendance: on ? s.n('attendance') : null,
    exams: on ? s.n('exam_avg') : null,
    lectures: c.sessionsCount,
    students: c.studentsCount,
    atRisk: on ? s.atRisk : 0,
    passRate: on ? s.n('exam_pass_rate') : null,
    sharedMarks: on ? s.published : null,
  );
}

class TeacherAnalyticsHubScreen extends StatefulWidget {
  const TeacherAnalyticsHubScreen({super.key});

  @override
  State<TeacherAnalyticsHubScreen> createState() => _TeacherAnalyticsHubScreenState();
}

class _TeacherAnalyticsHubScreenState extends State<TeacherAnalyticsHubScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _store = _OverviewStore();
  AnMetric _metric = AnMetric.progress;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    // The Courses tab may never have been opened (lazy tabs): load the list on demand, once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TeacherCoursesProvider>().ensureLoaded();
    });
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store
      ..removeListener(_onStore)
      ..dispose();
    super.dispose();
  }

  void _push(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  /// Every exam across the courses (D-300).
  void _openAllExams() => _push(deferredExamsHome());

  TeacherCourse? _course(int? id) {
    for (final c in context.read<TeacherCoursesProvider>().allCourses) {
      if (c.id == id) return c;
    }
    return null;
  }

  void _openAll() {
    final prov = context.read<TeacherCoursesProvider>();
    _push(ChangeNotifierProvider<TeacherCoursesProvider>.value(
      value: prov,
      child: _AllClassesPage(store: _store),
    ));
  }

  /// The course's tools in a sheet (the same four shortcuts as its full card).
  void _openTools(TeacherCourse course) {
    final title = _courseTitle(course);
    final s = _store.byCourse[course.id];
    showAppSheet<void>(context, (ctx) {
      void go(Widget w) {
        Navigator.pop(ctx);
        _push(w);
      }

      return AppSheetContent(
        title: title,
        children: [
          _CourseTools(
            course: course,
            snapshot: s,
            stacked: true,
            open: go,
          ),
        ],
      );
    });
  }

  VoidCallback? _insightAction(AnInsight i) {
    final course = _course(i.courseId);
    if (course == null) return null;
    final title = _courseTitle(course);
    return switch (i.target) {
      AnTarget.attendance => () => _push(TeacherAttendanceScreen(courseId: course.id, courseTitle: title)),
      AnTarget.exams => () => _push(deferredTeacherExamHub(courseId: course.id, courseTitle: title, orgId: course.org?.id)),
      AnTarget.dataLab => () => _push(deferredDataLab(courseId: course.id, courseTitle: title)),
      AnTarget.course || AnTarget.review => () => _openTools(course),
      AnTarget.none => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final prov = context.watch<TeacherCoursesProvider>();
    final all = prov.allCourses;
    // (re)load the class numbers whenever the course list changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !prov.isLoading) _store.load([for (final c in all) c.id]);
    });

    final Widget body;
    if (((prov.isLoading || !prov.loadedOnce) && all.isEmpty) || (all.isNotEmpty && !_store.settled && _store.byCourse.isEmpty)) {
      body = const AnSummarySkeleton();
    } else if (all.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(all),
          AppSpace.gapLg,
          AppEmpty(icon: Icons.school_outlined, title: 'no_courses_yet'.tr, message: 'add_course_first_hint'.tr, tone: AppBlockTone.sky),
        ]),
      );
    } else {
      body = _summary(all);
    }

    return BasePage(
      key: const ValueKey('analytics_hub'),
      useWebCard: true,
      width: AppWidth.wide,
      enableFooterWidget: false,
      child: ColoredBox(
        color: context.colors.background,
        child: AppRefresh(
          onRefresh: () => _store.load([for (final c in all) c.id], force: true),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [SliverToBoxAdapter(child: body)],
          ),
        ),
      ),
    );
  }

  Widget _header(List<TeacherCourse> all) => AnalyticsMasthead(
        title: anTr('an2_title', 'Analytics'),
        subtitle: anTr('an2_sub_teacher', 'How your classes are doing'),
        actions: [
          ParentComponent(
            featureKey: 'exam.all_exams',
            child: AnalyticsHeaderAction(
              key: const ValueKey('analytics_hub.all_exams'),
              icon: Icons.fact_check_rounded,
              tooltip: anTr('an_all_exams', 'All exams'),
              onTap: _openAllExams,
            ),
          ),
          AnalyticsHeaderAction(
            icon: Icons.refresh_rounded,
            tooltip: anTr('an_refresh', 'Refresh'),
            onTap: () => _store.load([for (final c in all) c.id], force: true),
          ),
        ],
      );

  Widget _summary(List<TeacherCourse> all) {
    final facts = [for (final x in all) _facts(x, _store.byCourse[x.id])];
    final totals = anTotals(facts);
    final metrics = anAvailableMetrics(facts);
    final metric = metrics.contains(_metric) ? _metric : (metrics.isEmpty ? AnMetric.progress : metrics.first);
    final risk = facts.fold<int>(0, (s, f) => s + f.atRisk);
    final passRate = anMean(facts.map((f) => f.passRate));

    // the page's one memorable element: the class rings on the instructor's sky block
    final hero = ParentComponent(
      featureKey: 'analytics_hub.header',
      child: AnalyticsHeroBlock(
        headline: anHeadlineText(teacherHeadline(facts)),
        rings: [for (final m in AnMetric.values) AnRingSpec(metric: m, value: totals.value(m))],
        overall: totals.overall,
        overallLabel: anTr('an2_class_overall', 'Average'),
        tone: AppBlockTone.sky,
        memoryKey: 'analytics_hub.overall',
      ),
    );

    // the four counts; the ONE key figure is who needs you: a block whose number rolls (emerald when nobody does)
    final tiles = AppKpiGrid(children: [
      AppKpiCard(
        icon: Icons.volunteer_activism_rounded,
        label: anTr('an2_tile_need_attention', 'Need attention'),
        value: '$risk',
        highlight: true,
        tone: risk > 0 ? AppBlockTone.peach : AppBlockTone.emerald,
      ),
      AppKpiCard(
        icon: Icons.menu_book_rounded,
        label: anTr('an_courses', 'Courses'),
        value: '${all.length}',
        onTap: _openAll,
      ),
      AppKpiCard(
        icon: Icons.people_rounded,
        label: anTr('an2_tile_students', 'Students'),
        value: appCompactNumber(all.fold<int>(0, (s, x) => s + x.studentsCount)),
      ),
      AppKpiCard(
        icon: Icons.verified_rounded,
        label: anTr('an2_tile_pass_rate', 'Exam pass rate'),
        value: anPct(passRate),
        onTap: AppConfig.disableList.contains('exam.all_exams') ? null : _openAllExams,
      ),
    ]);

    final insights = teacherInsights(facts);
    final insightCard = insights.isEmpty
        ? null
        : AnInsightCard(
            title: anTr('an2_for_you', 'For you'),
            rows: [for (final i in insights) AnInsightRowData(tone: i.tone, text: anInsightText(i), onTap: _insightAction(i))],
          );

    final chart = AnCourseBars(
      title: anTr('an2_your_classes', 'Your classes'),
      metric: metric,
      metrics: metrics,
      onMetric: (m) => setState(() => _metric = m),
      rows: [
        for (final f in anRankBy(facts, metric))
          AnBarRowData(
            title: f.title,
            value: f.value(metric),
            detail: anStudentsWord(f.students),
            flag: f.atRisk > 0,
            onTap: () {
              final course = _course(f.id);
              if (course != null) _openTools(course);
            },
          ),
      ],
      onShowAll: _openAll,
      showAllLabel: anFmt('an2_all_courses', {'n': all.length}, 'All courses ({n})'),
    );

    // students who need attention, across every course — worst first
    final titles = {for (final x in all) x.id: _courseTitle(x)};
    final people = <(int, Map<String, dynamic>)>[
      for (final e in _store.byCourse.entries)
        for (final s in e.value.risk) (e.key, s),
    ]..sort((a, b) => (anAverage([dlNum(a.$2['attendance']), dlNum(a.$2['exam_avg'])]) ?? 100)
        .compareTo(anAverage([dlNum(b.$2['attendance']), dlNum(b.$2['exam_avg'])]) ?? 100));
    final attention = people.isEmpty
        ? null
        : AnCompactList(
            title: anTr('ta_attention', 'Needs your attention'),
            subtitle: anTr('an2_attention_sub', 'Under 60 % attendance or 50 % in exams'),
            rows: [
              for (final (courseId, s) in people.take(20))
                AnPersonRow(
                  name: '${s['name']}',
                  course: titles[courseId] ?? '',
                  attendance: dlNum(s['attendance']),
                  exams: dlNum(s['exam_avg']),
                  onTap: () => _push(StudentAnalyticsProfileScreen.forTeacher(
                    studentId: (s['student_id'] as num).toInt(),
                    studentName: '${s['name']}',
                    courseId: courseId,
                  )),
                ),
            ],
          );

    return AnSummaryLayout(
      header: _header(all),
      hero: hero,
      tiles: tiles,
      insights: insightCard,
      chart: metrics.isEmpty ? null : chart,
      lists: [?attention],
    );
  }
}

// ── All courses: search + the full course cards ─────────────────────────────

class _AllClassesPage extends StatefulWidget {
  const _AllClassesPage({required this.store});

  final _OverviewStore store;

  @override
  State<_AllClassesPage> createState() => _AllClassesPageState();
}

class _AllClassesPageState extends State<_AllClassesPage> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  bool _attentionFirst = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matches(TeacherCourse c, String q) {
    final s = q.toLowerCase();
    return (c.titleAr?.toLowerCase().contains(s) ?? false) ||
        (c.titleEn?.toLowerCase().contains(s) ?? false) ||
        (c.descriptionEn?.toLowerCase().contains(s) ?? false) ||
        (c.descriptionAr?.toLowerCase().contains(s) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final all = context.watch<TeacherCoursesProvider>().allCourses;
    final store = widget.store;
    var list = _search.isEmpty ? List.of(all) : all.where((x) => _matches(x, _search)).toList();
    if (_attentionFirst) {
      list.sort((a, b) => (store.byCourse[b.id]?.atRisk ?? 0).compareTo(store.byCourse[a.id]?.atRisk ?? 0));
    }
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppHeader(title: anTr('an2_all_courses_title', 'All courses')),
      body: AppRefresh(
        onRefresh: () => store.load([for (final x in all) x.id], force: true),
        child: LayoutBuilder(builder: (context, box) {
          // one reading column, centred: the cards read top to bottom like a report
          final side = (box.maxWidth - AppWidth.reading.inside(box.maxWidth)) / 2;
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(side, AppSpace.xs, side, AppSpace.md),
                sliver: SliverToBoxAdapter(
                  child: ParentComponent(featureKey: 'analytics_hub.search', child: _tools()),
                ),
              ),
              if (list.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppEmpty(icon: Icons.search_off_rounded, title: 'no_search_results'.tr),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 0, side, AppSpace.xl),
                  sliver: SliverList.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => AppSpace.gapSm,
                    itemBuilder: (_, i) => AppReveal(
                      index: i,
                      group: 'an_all_classes',
                      child: _CourseAnalyticsCard(
                        course: list[i],
                        snapshot: store.byCourse[list[i].id],
                        loading: store.loading && store.byCourse.isEmpty,
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

  Widget _tools() => Row(children: [
        Expanded(
          child: AppSearchField(
            controller: _searchCtrl,
            hint: 'search_course_hint'.tr,
            debounce: Duration.zero,
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        AppSpace.gapXs,
        _AttentionToggle(
          on: _attentionFirst,
          onChanged: () => setState(() => _attentionFirst = !_attentionFirst),
        ),
      ]);
}

/// "Needs attention first": a 48 px square toggle beside the search, warm when it is on.
class _AttentionToggle extends StatelessWidget {
  const _AttentionToggle({required this.on, required this.onChanged});

  final bool on;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = appTintOn(context, c.warning, surface: c.cardBg);
    final fill = on ? tint : c.cardBg;
    return Tooltip(
      message: anTr('an_sort_attention', 'Needs attention'),
      child: Semantics(
        button: true,
        toggled: on,
        child: AnimatedContainer(
          duration: AppMotion.of(context).fast,
          curve: AppEase.out,
          width: AppTouch.min,
          height: AppTouch.min,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: AppRadius.controlAll,
            border: Border.all(
              color: on ? Color.lerp(tint, c.warning, 0.5)! : c.divider,
              width: AppBorder.hairline,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: AppRadius.controlAll,
              onTap: onChanged,
              child: Icon(
                Icons.volunteer_activism_rounded,
                size: AppIconSize.md,
                color: on ? appInkOn(context, c.warning, tint) : c.textMedium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Course card ──────────────────────────────────────────────────────────────

class _CourseAnalyticsCard extends StatelessWidget {
  const _CourseAnalyticsCard({required this.course, required this.snapshot, required this.loading});

  final TeacherCourse course;
  final _Snapshot? snapshot;
  final bool loading;

  /// The width of a metric's label column (the bars line up under each other).
  static const double _metricLabel = 104;

  /// The width of a metric's figure column.
  static const double _metricFigure = 48;

  /// The pass-rate ring beside the title.
  static const double _ring = 56;
  static const double _ringStroke = 5;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = _courseTitle(course);
    final s = snapshot;
    final hasNumbers = s != null && s.enabled && (s.n('progress') != null || s.n('attendance') != null || s.n('exam_avg') != null);
    final risk = s?.atRisk ?? 0;

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
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── title: the course's mark, its name, who is in it ──
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.md, AppSpace.sm, AppSpace.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnalyticsCourseMark(courseId: course.id),
            AppSpace.gapSm,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                const SizedBox(height: AppSpace.xxs),
                Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, children: [
                  AnalyticsFact(icon: Icons.people_rounded, text: anStudentsWord(course.studentsCount)),
                  AnalyticsFact(icon: Icons.video_library_outlined, text: anSessionsWord(course.sessionsCount)),
                ]),
                if (risk > 0) ...[
                  const SizedBox(height: AppSpace.xs),
                  AppStatusBadge(
                    label: anFmt('ta_risk_n', {'n': risk}, '{n} need attention'),
                    tone: AppTone.warning,
                    icon: Icons.volunteer_activism_rounded,
                  ),
                ],
              ]),
            ),
            if (hasNumbers && s.n('exam_pass_rate') != null) ...[
              AppSpace.gapXs,
              Tooltip(
                message: anTr('ta_pass_rate', 'Students passing on exam average'),
                child: AnRing(value: s.n('exam_pass_rate'), size: _ring, stroke: _ringStroke),
              ),
            ],
          ]),
        ),
        // ── class snapshot ──
        if (loading)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xxs),
            child: AppShimmer(
              child: Column(children: [
                for (var i = 0; i < 3; i++)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpace.sm),
                    child: AppSkeletonBox(height: AppSpace.xs),
                  ),
              ]),
            ),
          )
        else if (hasNumbers)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xxs),
            child: Column(children: [
              metric(anTr('ta_class_progress', 'Class progress'), s.n('progress'), Icons.route_rounded),
              metric('attendance_rate'.tr, s.n('attendance'), Icons.event_available_rounded),
              metric('sa_avg_score'.tr, s.n('exam_avg'), Icons.bar_chart_rounded),
            ]),
          ),
        // ── the course's tools ──
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.sm, AppSpace.sm),
          child: _CourseTools(
            course: course,
            snapshot: s,
            open: (w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w)),
          ),
        ),
      ]),
    );
  }
}

/// The four shortcuts of a course: Data Lab (the primary one, solid emerald) and Attendance · Exams · Read flags as
/// quiet wells. [stacked] puts every row on its own line (the sheet); otherwise Attendance and Exams share one.
class _CourseTools extends StatelessWidget {
  const _CourseTools({required this.course, required this.snapshot, required this.open, this.stacked = false});

  final TeacherCourse course;
  final _Snapshot? snapshot;
  final ValueChanged<Widget> open;
  final bool stacked;

  /// From this width Attendance and Exams sit side by side.
  static const double _pairFrom = 480;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = _courseTitle(course);
    final s = snapshot;
    final attendance = ParentComponent(
      featureKey: 'analytics_hub.attendance',
      child: _ToolRow(
        icon: Icons.fact_check_rounded,
        label: 'analytics_btn_attendance'.tr,
        sublabel: 'analytics_btn_attendance_sub'.tr,
        color: c.success,
        onTap: () => open(TeacherAttendanceScreen(courseId: course.id, courseTitle: title)),
      ),
    );
    final exams = ParentComponent(
      featureKey: 'analytics_hub.exams',
      child: _ToolRow(
        icon: Icons.quiz_rounded,
        label: 'analytics_btn_exams'.tr,
        sublabel: 'analytics_btn_exams_sub'.tr,
        color: c.primary,
        onTap: () => open(deferredTeacherExamHub(courseId: course.id, courseTitle: title, orgId: course.org?.id)),
      ),
    );
    // Attendance and Exams share a line only where both names fit (a phone stacks them)
    return LayoutBuilder(builder: (context, box) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (s == null || s.enabled) ...[
        ParentComponent(
          featureKey: 'analytics_hub.data_lab',
          child: _DataLabButton(
            published: s?.published ?? 0,
            onTap: () => open(deferredDataLab(courseId: course.id, courseTitle: title)),
          ),
        ),
        AppSpace.gapXs,
      ],
      if (stacked || box.maxWidth < _pairFrom) ...[
        attendance,
        AppSpace.gapXs,
        exams,
      ] else
        Row(children: [
          Expanded(child: attendance),
          AppSpace.gapXs,
          Expanded(child: exams),
        ]),
      AppSpace.gapXs,
      ParentComponent(
        featureKey: 'analytics_hub.read_flags',
        child: _ToolRow(
          icon: Icons.flag_rounded,
          label: 'tflag_btn'.tr,
          sublabel: 'tflag_btn_sub'.tr,
          color: c.danger,
          onTap: () => open(TeacherReadFlagsScreen(courseId: course.id, courseTitle: title)),
        ),
      ),
    ]));
  }
}

/// Data Lab, the course's primary tool: solid emerald with the on-hero ink (the primary action, never a gradient).
class _DataLabButton extends StatelessWidget {
  const _DataLabButton({required this.published, required this.onTap});

  final int published;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppPressScale(
      child: Material(
        color: c.primary,
        borderRadius: AppRadius.controlAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.primary),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.sm, AppSpace.xs),
              child: Row(children: [
                Container(
                  width: AppTouch.min - AppSpace.sm,
                  height: AppTouch.min - AppSpace.sm,
                  decoration: BoxDecoration(color: c.heroGlass, borderRadius: AppRadius.chipAll),
                  child: Icon(Icons.science_rounded, color: c.onHero, size: AppIconSize.md),
                ),
                AppSpace.gapSm,
                Expanded(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('dl_title'.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.bodyStrong(context).copyWith(color: c.onHero)),
                    Text(
                      published > 0
                          ? anFmt('ta_dl_published', {'n': published}, '{n} columns shared with students')
                          : anTr('ta_dl_sub', 'Grades, formulas, imports and certificates — in one sheet'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.meta(context).copyWith(color: c.onHeroMuted),
                    ),
                  ]),
                ),
                AppSpace.gapXs,
                Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.onHeroMuted),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A secondary tool: a quiet well (the input tone, no border) with a tinted icon, the name in ink and one line.
class _ToolRow extends StatelessWidget {
  final IconData icon;
  final String label, sublabel;
  final Color color;
  final VoidCallback onTap;

  const _ToolRow({required this.icon, required this.label, required this.sublabel, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = appTintOn(context, color, surface: c.inputBg);
    return AppPressScale(
      child: Material(
        color: c.inputBg,
        borderRadius: AppRadius.controlAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.primary),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.xs, AppSpace.xs),
              child: Row(children: [
                Container(
                  width: AppTouch.min - AppSpace.sm,
                  height: AppTouch.min - AppSpace.sm,
                  decoration: BoxDecoration(color: tint, borderRadius: AppRadius.chipAll),
                  child: Icon(icon, color: appInkOn(context, color, tint), size: AppIconSize.md),
                ),
                AppSpace.gapSm,
                Expanded(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                    Text(sublabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
