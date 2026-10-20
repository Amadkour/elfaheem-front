// lib/features/teacher/analysis/analytics_hub_screen.dart
// The teacher's analytics hub — same design system as the student and parent analytics (shared/analytics).
//
//   • header: courses, students, sessions and how many students need attention right now
//   • "Needs attention" strip: students below 60 % attendance or 50 % exam average, across every course —
//     tap one → their analytics profile (the same profile the student and the parent see)
//   • one card per course: class snapshot (progress / attendance / exam average + pass rate), then
//     Data Lab (the full sheet) · Attendance · Exams · Read flags
// The class numbers come from GET /api/v1/data-lab/overview; when Data Lab is off for a course the card simply
// shows the shortcuts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../shared/analytics/analytics_ui.dart';
import '../../student/analysis/student_analytics_profile_screen.dart';
import '../../student/analysis/student_analytics_provider.dart';
import '../courses/teacher_courses_provider.dart';
import '../data_lab/data_lab_api.dart';
import '../data_lab/data_lab_models.dart';
import '../data_lab/data_lab_screen.dart';
import '../home/teacher_models.dart';
import 'attendance/teacher_attendance_screen.dart';
import 'exam/teacher_exam_hub_screen.dart';
import 'flags/teacher_read_flags_screen.dart';

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
      failed = true; // the hub still works: the cards just show their shortcuts
    } finally {
      loading = false;
      notifyListeners();
    }
  }
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
  final _searchCtrl = TextEditingController();
  String _search = '';
  bool _attentionFirst = false;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store
      ..removeListener(_onStore)
      ..dispose();
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
    super.build(context);
    final prov = context.watch<TeacherCoursesProvider>();
    final all = prov.allCourses;
    // (re)load the class numbers whenever the course list changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !prov.isLoading) _store.load([for (final c in all) c.id]);
    });

    var list = _search.isEmpty ? List.of(all) : all.where((c) => _matches(c, _search)).toList();
    if (_attentionFirst) {
      list.sort((a, b) => (_store.byCourse[b.id]?.atRisk ?? 0).compareTo(_store.byCourse[a.id]?.atRisk ?? 0));
    }

    return BasePage(
      key: const ValueKey('analytics_hub'),
      useWebCard: true,
      enableFooterWidget: false,
      child: ColoredBox(
        color: context.colors.background,
        child: prov.isLoading && all.isEmpty
            ? const Center(child: AppLoadingIndicator())
            : RefreshIndicator(
          onRefresh: () => _store.load([for (final c in all) c.id], force: true),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(child: ParentComponent(featureKey: 'analytics_hub.header', child: _hero(all))),
              if (all.isNotEmpty) SliverToBoxAdapter(child: _attentionStrip(all)),
              if (all.isNotEmpty) SliverToBoxAdapter(child: ParentComponent(featureKey: 'analytics_hub.search', child: _tools())),
              if (list.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AnEmpty(
                    icon: Icons.school_outlined,
                    title: all.isEmpty ? 'no_courses_yet'.tr : 'no_search_results'.tr,
                    sub: all.isEmpty ? 'add_course_first_hint'.tr : null,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                  sliver: SliverList.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (_, i) => _CourseAnalyticsCard(
                      course: list[i],
                      snapshot: _store.byCourse[list[i].id],
                      loading: _store.loading && _store.byCourse.isEmpty,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Hero ────────────────────────────────────────────────────────────────────
  Widget _hero(List<TeacherCourse> all) {
    final students = all.fold<int>(0, (s, c) => s + c.studentsCount);
    final sessions = all.fold<int>(0, (s, c) => s + c.sessionsCount);
    final risk = _store.byCourse.values.fold<int>(0, (s, x) => s + x.atRisk);
    final att = anAverage(_store.byCourse.values.map((x) => x.n('attendance')));
    final ex = anAverage(_store.byCourse.values.map((x) => x.n('exam_avg')));
    return Container(
      decoration: anHeroDecoration(context),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('analytics_hub_title'.tr, style: anText(21, w: FontWeight.w800, c: Colors.white)),
                  const SizedBox(height: 3),
                  Text(
                    risk > 0
                        ? anFmt('ta_hero_risk', {'n': risk}, '{n} students could use your attention this week.')
                        : (_store.byCourse.isEmpty ? 'analytics_hub_subtitle'.tr : anTr('ta_hero_ok', 'Every class is on track — nice work!')),
                    style: anText(12.5, c: Colors.white70, h: 1.5),
                  ),
                ]),
              ),
              AnGlassIcon(
                icon: Icons.refresh_rounded,
                tooltip: anTr('an_refresh', 'Refresh'),
                onTap: () => _store.load([for (final c in all) c.id], force: true),
              ),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              AnHeroStat(icon: Icons.menu_book_rounded, value: '${all.length}', label: 'courses'.tr),
              const SizedBox(width: 8),
              AnHeroStat(icon: Icons.people_rounded, value: '$students', label: 'total_students'.tr),
              const SizedBox(width: 8),
              if (att != null || ex != null) ...[
                AnHeroStat(icon: Icons.event_available_rounded, value: anPct(att), label: 'attendance_rate'.tr),
                const SizedBox(width: 8),
                AnHeroStat(icon: Icons.bar_chart_rounded, value: anPct(ex), label: 'sa_avg_score'.tr),
              ] else
                AnHeroStat(icon: Icons.video_library_rounded, value: '$sessions', label: 'sessions'.tr),
            ]),
          ]),
        ),
      ),
    );
  }

  // ── students who need attention, across every course ───────────────────────
  Widget _attentionStrip(List<TeacherCourse> all) {
    final titles = {for (final x in all) x.id: _courseTitle(x)};
    final items = <(int, Map<String, dynamic>)>[
      for (final e in _store.byCourse.entries)
        for (final s in e.value.risk) (e.key, s),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    items.sort((a, b) => (anAverage([dlNum(a.$2['attendance']), dlNum(a.$2['exam_avg'])]) ?? 100)
        .compareTo(anAverage([dlNum(b.$2['attendance']), dlNum(b.$2['exam_avg'])]) ?? 100));
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AnSectionTitle(
            anTr('ta_attention', 'Needs your attention'),
            icon: Icons.volunteer_activism_rounded,
            subtitle: anTr('ta_attention_sub', 'Attendance under 60 % or exams under 50 % — tap a student for the full picture.'),
          ),
        ),
        SizedBox(
          height: 74,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: items.length > 20 ? 20 : items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final (courseId, s) = items[i];
              return AnAttentionChip(
                name: '${s['name']}',
                subtitle: titles[courseId],
                attendance: dlNum(s['attendance']),
                exams: dlNum(s['exam_avg']),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentAnalyticsProfileScreen.forTeacher(
                      studentId: (s['student_id'] as num).toInt(),
                      studentName: '${s['name']}',
                      courseId: courseId,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
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
                child: Icon(Icons.volunteer_activism_rounded, color: _attentionFirst ? Colors.white : c.warning),
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
        SizedBox(width: 44, child: Text(anPct(v), textAlign: TextAlign.end, style: anText(12, w: FontWeight.w800, c: anScoreColor(context, v)))),
      ]),
    );

    return AnCard(
      padding: EdgeInsets.zero,
      borderColor: risk > 0 ? c.warning.withValues(alpha: 0.45) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── title ──
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
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
              child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: anText(15, w: FontWeight.w800, c: c.textDark, h: 1.35)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  AnTag('${course.studentsCount} ${'student'.tr}', c.accent2, icon: Icons.people_rounded),
                  AnTag('${course.sessionsCount} ${'session'.tr}', c.purple, icon: Icons.video_library_outlined),
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
                  onTap: () => _push(context, DataLabScreen(courseId: course.id, courseTitle: title)),
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
                    onTap: () => _push(context, TeacherExamHubScreen(courseId: course.id, courseTitle: title)),
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
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.science_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('dl_title'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(13.5, w: FontWeight.w800, c: Colors.white)),
                Text(
                  published > 0
                      ? anFmt('ta_dl_published', {'n': published}, '{n} columns shared with students')
                      : anTr('ta_dl_sub', 'Grades, formulas, imports and certificates — in one sheet'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: anText(10.5, c: Colors.white70),
                ),
              ]),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Colors.white70),
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
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: anText(13, w: FontWeight.w800, c: color)),
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
