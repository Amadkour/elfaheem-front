// lib/features/teacher/analysis/analytics_hub_screen.dart
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

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../shared/analytics/analytics_summary.dart';
import '../../shared/analytics/analytics_summary_ui.dart';
import '../../shared/analytics/analytics_ui.dart';
import '../../student/analysis/student_analytics_profile_screen.dart';
import '../../student/analysis/student_analytics_provider.dart';
import '../courses/teacher_courses_provider.dart';
import '../data_lab/data_lab_api.dart';
import '../data_lab/data_lab_models.dart';
import '../home/teacher_models.dart';
import 'attendance/teacher_attendance_screen.dart';
import 'flags/teacher_read_flags_screen.dart';
import 'package:flutter_education_app/design/app_charts.dart' show appCompactNumber;
import 'package:flutter_education_app/design/app_kit.dart' show showAppSheet, AppSheetHeader;
import 'package:flutter_education_app/design/app_refresh.dart';

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
      final c = ctx.colors;
      void go(Widget w) {
        Navigator.pop(ctx);
        _push(w);
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSheetHeader(title),
          if (s == null || s.enabled) ...[
            ParentComponent(
              featureKey: 'analytics_hub.data_lab',
              child: _DataLabButton(published: s?.published ?? 0, onTap: () => go(deferredDataLab(courseId: course.id, courseTitle: title))),
            ),
            const SizedBox(height: 10),
          ],
          ParentComponent(
            featureKey: 'analytics_hub.attendance',
            child: _ActionButton(
              icon: Icons.fact_check_rounded,
              label: 'analytics_btn_attendance'.tr,
              sublabel: 'analytics_btn_attendance_sub'.tr,
              color: c.success,
              onTap: () => go(TeacherAttendanceScreen(courseId: course.id, courseTitle: title)),
            ),
          ),
          const SizedBox(height: 10),
          ParentComponent(
            featureKey: 'analytics_hub.exams',
            child: _ActionButton(
              icon: Icons.quiz_rounded,
              label: 'analytics_btn_exams'.tr,
              sublabel: 'analytics_btn_exams_sub'.tr,
              color: c.primary,
              onTap: () => go(deferredTeacherExamHub(courseId: course.id, courseTitle: title, orgId: course.org?.id)),
            ),
          ),
          const SizedBox(height: 10),
          ParentComponent(
            featureKey: 'analytics_hub.read_flags',
            child: _ActionButton(
              icon: Icons.flag_rounded,
              label: 'tflag_btn'.tr,
              sublabel: 'tflag_btn_sub'.tr,
              color: c.danger,
              onTap: () => go(TeacherReadFlagsScreen(courseId: course.id, courseTitle: title)),
            ),
          ),
        ]),
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(all),
          const SizedBox(height: 24),
          AnEmpty(icon: Icons.school_outlined, title: 'no_courses_yet'.tr, sub: 'add_course_first_hint'.tr),
        ]),
      );
    } else {
      body = _summary(all);
    }

    return BasePage(
      key: const ValueKey('analytics_hub'),
      useWebCard: true,
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

  Widget _header(List<TeacherCourse> all) => AnPageHeader(
        title: anTr('an2_title', 'Analytics'),
        subtitle: anTr('an2_sub_teacher', 'How your classes are doing'),
        actions: [
          AnHeaderIcon(
            icon: Icons.refresh_rounded,
            tooltip: anTr('an_refresh', 'Refresh'),
            onTap: () => _store.load([for (final c in all) c.id], force: true),
          ),
        ],
      );

  Widget _summary(List<TeacherCourse> all) {
    final c = context.colors;
    final facts = [for (final x in all) _facts(x, _store.byCourse[x.id])];
    final totals = anTotals(facts);
    final metrics = anAvailableMetrics(facts);
    final metric = metrics.contains(_metric) ? _metric : (metrics.isEmpty ? AnMetric.progress : metrics.first);
    final risk = facts.fold<int>(0, (s, f) => s + f.atRisk);
    final passRate = anMean(facts.map((f) => f.passRate));

    final hero = ParentComponent(
      featureKey: 'analytics_hub.header',
      child: AnSummaryHero(
        headline: anHeadlineText(teacherHeadline(facts)),
        rings: [for (final m in AnMetric.values) AnRingSpec(metric: m, value: totals.value(m))],
        overall: totals.overall,
        overallLabel: anTr('an2_class_overall', 'Average'),
      ),
    );

    final tiles = AnStatTiles(tiles: [
      AnTileSpec(
        icon: Icons.menu_book_rounded,
        label: anTr('an_courses', 'Courses'),
        value: '${all.length}',
        color: anMetricColor(context, AnMetric.progress),
        onTap: _openAll,
      ),
      AnTileSpec(
        icon: Icons.people_rounded,
        label: anTr('an2_tile_students', 'Students'),
        value: appCompactNumber(all.fold<int>(0, (s, x) => s + x.studentsCount)),
        color: anSpareColor(context),
      ),
      AnTileSpec(
        icon: Icons.volunteer_activism_rounded,
        label: anTr('an2_tile_need_attention', 'Need attention'),
        value: '$risk',
        color: risk > 0 ? c.warning : c.success,
      ),
      AnTileSpec(
        icon: Icons.verified_rounded,
        label: anTr('an2_tile_pass_rate', 'Exam pass rate'),
        value: anPct(passRate),
        color: anMetricColor(context, AnMetric.exams),
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
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(anTr('an2_all_courses_title', 'All courses'), style: anText(17, w: FontWeight.w600, c: c.textDark)),
      ),
      body: AppRefresh(
        onRefresh: () => store.load([for (final x in all) x.id], force: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(child: ParentComponent(featureKey: 'analytics_hub.search', child: _tools())),
            if (list.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: AnEmpty(icon: Icons.search_off_rounded, title: 'no_search_results'.tr),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                sliver: SliverList.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (_, i) => _CourseAnalyticsCard(
                    course: list[i],
                    snapshot: store.byCourse[list[i].id],
                    loading: store.loading && store.byCourse.isEmpty,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tools() {
    final c = context.colors;
    OutlineInputBorder b(Color col, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: col, width: w));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            textDirection: pageDirection,
            style: anText(14, c: c.textDark),
            decoration: InputDecoration(
              hintText: 'search_course_hint'.tr,
              hintStyle: anText(13, c: c.textLight),
              prefixIcon: Icon(Icons.search_rounded, color: c.textMedium, size: 21),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      tooltip: 'clear'.tr,
                      icon: Icon(Icons.close_rounded, color: c.textMedium, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _search = '');
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
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        const SizedBox(width: 10),
        Tooltip(
          message: anTr('an_sort_attention', 'Needs attention'),
          child: Material(
            color: _attentionFirst ? c.warning : c.cardBg,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _attentionFirst = !_attentionFirst),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _attentionFirst ? c.warning : c.divider),
                ),
                child: Icon(Icons.volunteer_activism_rounded, color: _attentionFirst ? c.onHero : c.warning),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Course card ──────────────────────────────────────────────────────────────

class _CourseAnalyticsCard extends StatelessWidget {
  const _CourseAnalyticsCard({required this.course, required this.snapshot, required this.loading});

  final TeacherCourse course;
  final _Snapshot? snapshot;
  final bool loading;

  void _push(BuildContext context, Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = _courseTitle(course);
    final s = snapshot;
    final hasNumbers = s != null && s.enabled && (s.n('progress') != null || s.n('attendance') != null || s.n('exam_avg') != null);
    final risk = s?.atRisk ?? 0;

    Widget metric(String label, double? v, IconData icon) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Icon(icon, size: 14, color: c.textLight),
        const SizedBox(width: 6),
        SizedBox(width: 96, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(11.5, c: c.textMedium))),
        Expanded(child: AnBar(value: v, height: 6)),
        SizedBox(width: 44, child: Text(anPct(v), textAlign: TextAlign.end, style: anText(12, w: FontWeight.w600, c: anScoreColor(context, v)))),
      ]),
    );

    return AnCard(
      padding: EdgeInsets.zero,
      borderColor: risk > 0 ? c.warning.withValues(alpha: 0.45) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── title ──
        Container(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 14, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [c.primary.withValues(alpha: 0.08), Colors.transparent],
            ),
          ),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                gradient: LinearGradient(colors: [c.primary, c.primaryDark], begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd),
              ),
              child: Icon(Icons.menu_book_rounded, color: c.onHero, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: anText(15, w: FontWeight.w600, c: c.textDark, h: 1.35)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  AnTag(
                      anStudentsWord(course.studentsCount),
                      c.accent2,
                      icon: Icons.people_rounded),
                  AnTag(
                      anSessionsWord(course.sessionsCount),
                      c.purple,
                      icon: Icons.video_library_outlined),
                  if (risk > 0) AnTag(anFmt('ta_risk_n', {'n': risk}, '{n} need attention'), c.warning, icon: Icons.volunteer_activism_rounded),
                ]),
              ]),
            ),
            if (hasNumbers && s.n('exam_pass_rate') != null) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: anTr('ta_pass_rate', 'Students passing on exam average'),
                child: AnRing(value: s.n('exam_pass_rate'), size: 56, stroke: 5),
              ),
            ],
          ]),
        ),
        // ── class snapshot ──
        if (loading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(height: 8, decoration: BoxDecoration(color: c.divider.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(8))),
                ),
            ]),
          )
        else if (hasNumbers)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Column(children: [
              metric(anTr('ta_class_progress', 'Class progress'), s.n('progress'), Icons.route_rounded),
              metric('attendance_rate'.tr, s.n('attendance'), Icons.event_available_rounded),
              metric('sa_avg_score'.tr, s.n('exam_avg'), Icons.bar_chart_rounded),
            ]),
          ),
        // ── actions ──
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(children: [
            if (s == null || s.enabled)
              ParentComponent(
                featureKey: 'analytics_hub.data_lab',
                child: _DataLabButton(
                  published: s?.published ?? 0,
                  onTap: () => _push(context, deferredDataLab(courseId: course.id, courseTitle: title)),
                ),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: ParentComponent(
                  featureKey: 'analytics_hub.attendance',
                  child: _ActionButton(
                    icon: Icons.fact_check_rounded,
                    label: 'analytics_btn_attendance'.tr,
                    sublabel: 'analytics_btn_attendance_sub'.tr,
                    color: c.success,
                    onTap: () => _push(context, TeacherAttendanceScreen(courseId: course.id, courseTitle: title)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ParentComponent(
                  featureKey: 'analytics_hub.exams',
                  child: _ActionButton(
                    icon: Icons.quiz_rounded,
                    label: 'analytics_btn_exams'.tr,
                    sublabel: 'analytics_btn_exams_sub'.tr,
                    color: c.primary,
                    onTap: () => _push(context, deferredTeacherExamHub(courseId: course.id, courseTitle: title, orgId: course.org?.id)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            ParentComponent(
              featureKey: 'analytics_hub.read_flags',
              child: _ActionButton(
                icon: Icons.flag_rounded,
                label: 'tflag_btn'.tr,
                sublabel: 'tflag_btn_sub'.tr,
                color: c.danger,
                onTap: () => _push(context, TeacherReadFlagsScreen(courseId: course.id, courseTitle: title)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _DataLabButton extends StatelessWidget {
  const _DataLabButton({required this.published, required this.onTap});

  final int published;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [c.primaryDark, c.primary], begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd),
            borderRadius: BorderRadius.circular(16),
            boxShadow: c.primaryShadow,
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: c.onHero.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.science_rounded, color: c.onHero, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('dl_title'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(13.5, w: FontWeight.w600, c: c.onHero)),
                Text(
                  published > 0
                      ? anFmt('ta_dl_published', {'n': published}, '{n} columns shared with students')
                      : anTr('ta_dl_sub', 'Grades, formulas, imports and certificates — in one sheet'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: anText(10.5, c: c.onHeroMuted),
                ),
              ]),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 13, color: c.onHeroMuted),
          ]),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label, sublabel;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.sublabel, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(13, w: FontWeight.w600, c: color)),
              const SizedBox(height: 1),
              Text(sublabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(10.5, c: context.colors.textMedium)),
            ]),
          ),
          Icon(Icons.arrow_forward_ios_rounded, size: 12, color: color.withValues(alpha: 0.6)),
        ]),
      ),
    ),
  );
}
