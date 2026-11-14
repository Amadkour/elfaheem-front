import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:flutter_education_app/utils/widget/search_text_field.dart';
import '../../../utils/widget/base_page.dart';
import '../../teacher/analysis/attendance/attendance_model.dart';
import 'attendance/student_attendance_model.dart';
import 'student_analytics_provider.dart';

const _font = 'bahji';

TextStyle _t(double size,
    {FontWeight w = FontWeight.w500, Color? c, double? h}) =>
    TextStyle(fontFamily: _font, fontSize: size, fontWeight: w, color: c, height: h);

/// Overall performance = average of attendance and exam average
/// (attendance only when no exam has been taken yet).
double _overall(StudentCourseAnalyticsProvider p) {
  final att = p.attendanceRate.toDouble();
  if (p.attemptedCount == 0) return att;
  return (att + p.avgScore.toDouble()) / 2;
}

String _level(double v) => v >= 85
    ? 'sa_level_excellent'.tr
    : v >= 70
    ? 'sa_level_very_good'.tr
    : v >= 50
    ? 'sa_level_good'.tr
    : 'sa_level_needs_follow_up'.tr;

Color _scoreColor(BuildContext c, double v) => v >= 75
    ? c.colors.success
    : v >= 50
    ? const Color(0xFFF59E0B)
    : const Color(0xFFEF4444);

const _danger = Color(0xFFEF4444);

/// Translates [key] and fills `{name}` placeholders.
String _fmt(String key, Map<String, Object?> params) {
  var out = key.tr;
  params.forEach((k, v) => out = out.replaceAll('{$k}', '$v'));
  return out;
}

// ══════════════════════════════════════════════════════════════════════════════
// Entry
// ══════════════════════════════════════════════════════════════════════════════

class StudentCourseAnalyticsScreen extends StatelessWidget {
  final int courseId;
  final String courseTitle;

  const StudentCourseAnalyticsScreen({
    super.key,
    required this.courseId,
    required this.courseTitle,
  });

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) =>
    StudentCourseAnalyticsProvider(courseId: courseId)..loadAll(),
    child: _CourseAnalyticsView(courseTitle: courseTitle),
  );
}

class _CourseAnalyticsView extends StatefulWidget {
  final String courseTitle;
  const _CourseAnalyticsView({required this.courseTitle});

  @override
  State<_CourseAnalyticsView> createState() => _CourseAnalyticsViewState();
}

class _CourseAnalyticsViewState extends State<_CourseAnalyticsView>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<StudentCourseAnalyticsProvider>();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: BasePage(
        maxWith: 1100,
        useWebCard: true,
        child: NestedScrollView(
          headerSliverBuilder: (ctx, _) => [
            SliverToBoxAdapter(
              child: _Hero(title: widget.courseTitle, prov: prov),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabsDelegate(
                controller: _tab,
                background: ctx.colors.background,
                surface: ctx.colors.cardBg,
                primary: ctx.colors.primary,
                inactive: ctx.colors.textMedium,
              ),
            ),
          ],
          body: TabBarView(
            controller: _tab,
            children: [
              _OverviewTab(prov: prov),
              _AttendanceTab(prov: prov),
              _ExamsTab(prov: prov),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Hero header
// ══════════════════════════════════════════════════════════════════════════════

class _Hero extends StatelessWidget {
  final String title;
  final StudentCourseAnalyticsProvider prov;
  const _Hero({required this.title, required this.prov});

  @override
  Widget build(BuildContext context) {
    final overall = _overall(prov);
    final loading = prov.loadingAtt && prov.loadingExams;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [const Color(0xFF0D47A1), context.colors.primary],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: context.colors.primary.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
          child: Column(children: [
            Row(children: [
              _GlassIcon(
                icon: Icons.arrow_back_ios_rounded,
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _t(18, w: FontWeight.w800, c: Colors.white)),
                    const SizedBox(height: 2),
                    Text('sa_report_title'.tr,
                        style: _t(12, c: Colors.white70)),
                  ],
                ),
              ),
              _GlassIcon(icon: Icons.refresh_rounded, onTap: prov.loadAll),
            ]),
            const SizedBox(height: 22),
            Row(children: [
              _ScoreRing(value: loading ? 0 : overall, size: 118),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(loading ? '...' : _level(overall),
                          style:
                          _t(13, w: FontWeight.w700, c: Colors.white)),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'sa_overall_hint'.tr,
                      style: _t(12, c: Colors.white70, h: 1.6),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              _HeroStat(
                icon: Icons.check_circle_rounded,
                color: const Color(0xFF69F0AE),
                value: '${prov.attendanceRate.toStringAsFixed(0)}%',
                label: 'attendance_rate'.tr,
              ),
              const SizedBox(width: 10),
              _HeroStat(
                icon: Icons.emoji_events_rounded,
                color: const Color(0xFFFFD740),
                value: '${prov.passedCount}/${prov.attemptedCount}',
                label: 'sa_passed_exams'.tr,
              ),
              const SizedBox(width: 10),
              _HeroStat(
                icon: Icons.bar_chart_rounded,
                color: const Color(0xFF80D8FF),
                value: '${prov.avgScore.toStringAsFixed(0)}%',
                label: 'sa_avg_score'.tr,
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _GlassIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: 0.16),
    shape: const CircleBorder(side: BorderSide(color: Colors.white24)),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(icon, color: Colors.white, size: 19),
      ),
    ),
  );
}

class _HeroStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value, label;
  const _HeroStat(
      {required this.icon,
        required this.color,
        required this.value,
        required this.label});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(value, style: _t(16, w: FontWeight.w800, c: Colors.white)),
        const SizedBox(height: 2),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _t(10, c: Colors.white70)),
      ]),
    ),
  );
}

class _ScoreRing extends StatelessWidget {
  final double value; // 0..100
  final double size;
  const _ScoreRing({required this.value, required this.size});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: (value / 100).clamp(0.0, 1.0)),
    duration: const Duration(milliseconds: 900),
    curve: Curves.easeOutCubic,
    builder: (_, v, __) => SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: 1,
            strokeWidth: 10,
            color: Colors.white.withValues(alpha: 0.16),
          ),
        ),
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: v,
            strokeWidth: 10,
            strokeCap: StrokeCap.round,
            color: Colors.white,
          ),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${(v * 100).round()}%',
              style: _t(size * 0.24, w: FontWeight.w800, c: Colors.white)),
          Text('stat_total'.tr, style: _t(10, c: Colors.white70)),
        ]),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Pinned tab bar
// ══════════════════════════════════════════════════════════════════════════════

class _TabsDelegate extends SliverPersistentHeaderDelegate {
  final TabController controller;
  final Color background, surface, primary, inactive;
  _TabsDelegate({
    required this.controller,
    required this.background,
    required this.surface,
    required this.primary,
    required this.inactive,
  });

  @override
  double get minExtent => 66;
  @override
  double get maxExtent => 66;

  Widget _tab(IconData i, String s) => Tab(
    height: 42,
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(i, size: 16),
      const SizedBox(width: 6),
      Text(s),
    ]),
  );

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      Container(
        color: background,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3))
            ],
          ),
          padding: const EdgeInsets.all(4),
          child: TabBar(
            controller: controller,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            splashBorderRadius: BorderRadius.circular(12),
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                  colors: [const Color(0xFF0D47A1), primary]),
            ),
            labelColor: Colors.white,
            unselectedLabelColor: inactive,
            labelStyle: _t(12.5, w: FontWeight.w700),
            unselectedLabelStyle: _t(12.5),
            tabs: [
              _tab(Icons.dashboard_rounded, 'sa_tab_overview'.tr),
              _tab(Icons.fact_check_rounded, 'attendance'.tr),
              _tab(Icons.quiz_rounded, 'exams'.tr),
            ],
          ),
        ),
      );

  @override
  bool shouldRebuild(covariant _TabsDelegate old) => true;
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 1 — Overview (parent-friendly summary)
// ══════════════════════════════════════════════════════════════════════════════

class _OverviewTab extends StatelessWidget {
  final StudentCourseAnalyticsProvider prov;
  const _OverviewTab({required this.prov});

  List<_Insight> _insights(BuildContext context) {
    final list = <_Insight>[];
    final success = context.colors.success;

    if (prov.totalSessions > 0) {
      final absent = prov.totalSessions - prov.presentCount;
      final rate = prov.attendanceRate.toDouble();
      if (rate >= 85) {
        list.add(_Insight(Icons.verified_rounded, success,
            _fmt('sa_ins_att_excellent', {'present': prov.presentCount, 'total': prov.totalSessions})));
      } else if (rate >= 60) {
        list.add(_Insight(Icons.info_rounded, const Color(0xFFF59E0B),
            _fmt('sa_ins_att_fair', {'absent': absent})));
      } else {
        list.add(_Insight(Icons.warning_amber_rounded, _danger,
            _fmt('sa_ins_att_low', {'absent': absent})));
      }
    }

    if (prov.attemptedCount > 0) {
      final failed = prov.attemptedCount - prov.passedCount;
      list.add(_Insight(
        failed == 0 ? Icons.emoji_events_rounded : Icons.school_rounded,
        failed == 0 ? success : const Color(0xFFF59E0B),
        failed == 0
            ? _fmt('sa_ins_exam_all_passed', {'n': prov.passedCount})
            : _fmt('sa_ins_exam_some', {'passed': prov.passedCount, 'attempted': prov.attemptedCount, 'failed': failed}),
      ));

      final done = prov.exams
          .where((e) => e.attempted && e.percentage != null)
          .toList();
      if (done.isNotEmpty) {
        done.sort((a, b) => b.percentage!.compareTo(a.percentage!));
        list.add(_Insight(Icons.star_rounded, const Color(0xFF3B82F6),
            _fmt('sa_ins_best', {'name': done.first.examName, 'pct': done.first.percentage!.toStringAsFixed(0)})));
      }
    }

    final pending = prov.exams.where((e) => !e.attempted).length;
    if (pending > 0) {
      list.add(_Insight(Icons.pending_actions_rounded, Colors.teal,
          _fmt('sa_ins_pending', {'n': pending})));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (prov.loadingAtt && prov.loadingExams) {
      return const Center(child: AppLoadingIndicator());
    }
    final insights = _insights(context);

    return RefreshIndicator(
      onRefresh: prov.loadAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // KPI grid
          Row(children: [
            Expanded(
              child: _KpiCard(
                icon: Icons.event_available_rounded,
                color: context.colors.success,
                value: '${prov.presentCount}/${prov.totalSessions}',
                label: 'sa_sessions_attended'.tr,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiCard(
                icon: Icons.event_busy_rounded,
                color: _danger,
                value: '${prov.totalSessions - prov.presentCount}',
                label: 'sa_sessions_missed'.tr,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _KpiCard(
                icon: Icons.workspace_premium_rounded,
                color: const Color(0xFFF59E0B),
                value: '${prov.passedCount}',
                label: 'sa_passed_exams'.tr,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiCard(
                icon: Icons.insights_rounded,
                color: const Color(0xFF3B82F6),
                value: '${prov.avgScore.toStringAsFixed(0)}%',
                label: 'sa_avg_score'.tr,
              ),
            ),
          ]),
          const SizedBox(height: 16),

          if (insights.isNotEmpty)
            ParentComponent(
              featureKey: 'student_analytics.insights',
              child: _SectionCard(
                icon: Icons.auto_awesome_rounded,
                title: 'sa_parent_summary'.tr,
                child: Column(children: [
                  for (var i = 0; i < insights.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    insights[i],
                  ],
                ]),
              ),
            ),
          if (insights.isNotEmpty) const SizedBox(height: 16),

          // Exam chart
          if (prov.exams.any((e) => e.attempted && e.percentage != null)) ...[
            _SectionCard(
              icon: Icons.bar_chart_rounded,
              title: 'sa_exam_results'.tr,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                _Dot(context.colors.success),
                const SizedBox(width: 4),
                Text('sa_passed_label'.tr,
                    style: _t(11, c: context.colors.textMedium)),
                const SizedBox(width: 10),
                const _Dot(_danger),
                const SizedBox(width: 4),
                Text('failed'.tr,
                    style: _t(11, c: context.colors.textMedium)),
              ]),
              child: _ScoresChart(exams: prov.exams),
            ),
            const SizedBox(height: 16),
          ],

          // Attendance timeline
          if (prov.attendance.isNotEmpty)
            _SectionCard(
              icon: Icons.timeline_rounded,
              title: 'attendance_record'.tr,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                _Dot(context.colors.success),
                const SizedBox(width: 4),
                Text('attending'.tr, style: _t(11, c: context.colors.textMedium)),
                const SizedBox(width: 10),
                const _Dot(_danger),
                const SizedBox(width: 4),
                Text('did_not_attend'.tr, style: _t(11, c: context.colors.textMedium)),
              ]),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in prov.attendance)
                    Tooltip(
                      message: r.sessions.name,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: (_isPresent(r)
                              ? context.colors.success
                              : _danger)
                              .withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(
                          _isPresent(r)
                              ? Icons.check_rounded
                              : Icons.close_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

bool _isPresent(FullAttendance r) =>
    r.attendance.isNotEmpty && r.attendance.first.isPresent;

class _Insight extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Insight(this.icon, this.color, this.text);

  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(text,
                style: _t(13, c: context.colors.textDark, h: 1.6)),
          ),
        ),
      ]);
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value, label;
  const _KpiCard(
      {required this.icon,
        required this.color,
        required this.value,
        required this.label});

  @override
  Widget build(BuildContext context) => _Card(
    padding: const EdgeInsets.all(14),
    child: Row(children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.08)],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: _t(20,
                      w: FontWeight.w800, c: context.colors.textDark)),
            ),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _t(11, c: context.colors.textMedium)),
          ],
        ),
      ),
    ]),
  );
}

class _ScoresChart extends StatelessWidget {
  final List<StudentExamSummary> exams;
  const _ScoresChart({required this.exams});

  @override
  Widget build(BuildContext context) {
    final items = exams
        .where((e) => e.attempted && e.percentage != null)
        .take(8)
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();
    const maxBar = 110.0;

    return SizedBox(
      height: maxBar + 56,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final e in items)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Builder(builder: (_) {
                  final pct = e.percentage!.clamp(0, 100).toDouble();
                  final color =
                  e.passed == false ? _danger : context.colors.success;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('${pct.round()}',
                          style: _t(11, w: FontWeight.w800, c: color)),
                      const SizedBox(height: 4),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: pct / 100 * maxBar),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOutCubic,
                        builder: (_, h, __) => Container(
                          height: h < 6 ? 6 : h,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [color, color.withValues(alpha: 0.55)],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 26,
                        child: Text(e.examName,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: _t(9, c: context.colors.textMedium, h: 1.3)),
                      ),
                    ],
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 2 — Attendance
// ══════════════════════════════════════════════════════════════════════════════

class _AttendanceTab extends StatefulWidget {
  final StudentCourseAnalyticsProvider prov;
  const _AttendanceTab({required this.prov});

  @override
  State<_AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<_AttendanceTab> {
  final _search = TextEditingController();
  int _filter = 0; // 0 all, 1 present, 2 absent

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = widget.prov;
    if (prov.loadingAtt) return const Center(child: AppLoadingIndicator());
    if (prov.attError != null) {
      return _ErrorRetry(message: prov.attError!, onRetry: prov.loadAttendance);
    }
    if (prov.attendance.isEmpty) {
      return _Empty(
          icon: Icons.event_note_rounded, text: 'sa_no_sessions_yet'.tr);
    }

    final q = _search.text.trim();
    final filtered = prov.attendance.where((r) {
      if (_filter == 1 && !_isPresent(r)) return false;
      if (_filter == 2 && _isPresent(r)) return false;
      if (q.isNotEmpty && !r.sessions.name.contains(q)) return false;
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: prov.loadAttendance,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _AttendanceSummaryCard(
            present: prov.presentCount,
            total: prov.totalSessions,
            rate: prov.attendanceRate.toDouble(),
          ),
          MySearchBar(
            controller: _search,
            hint: 'sa_search_session',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          _FilterChips(
            labels: ['filter_all'.tr, 'attending'.tr, 'did_not_attend'.tr],
            selected: _filter,
            onSelect: (i) => setState(() => _filter = i),
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: _Empty(
                  icon: Icons.search_off_rounded, text: 'no_search_results'.tr),
            )
          else
            for (final r in filtered) _AttendanceTile(record: r),
        ],
      ),
    );
  }
}

class _AttendanceSummaryCard extends StatelessWidget {
  final int present, total;
  final double rate;
  const _AttendanceSummaryCard(
      {required this.present, required this.total, required this.rate});

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(context, rate);
    return _Card(
      padding: const EdgeInsets.all(18),
      child: Row(children: [
        SizedBox(
          width: 92,
          height: 92,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (rate / 100).clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 92,
                height: 92,
                child: CircularProgressIndicator(
                  value: v,
                  strokeWidth: 9,
                  strokeCap: StrokeCap.round,
                  backgroundColor: color.withValues(alpha: 0.12),
                  color: color,
                ),
              ),
              Text('${rate.toStringAsFixed(0)}%',
                  style: _t(18, w: FontWeight.w800, c: color)),
            ]),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('sa_total_attendance'.tr,
                style: _t(13, w: FontWeight.w700, c: context.colors.textDark)),
            const SizedBox(height: 10),
            _BarRow('attending'.tr, present, total, context.colors.success),
            const SizedBox(height: 8),
            _BarRow('did_not_attend'.tr, total - present, total, _danger),
          ]),
        ),
      ]),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final int value, total;
  final Color color;
  const _BarRow(this.label, this.value, this.total, this.color);

  @override
  Widget build(BuildContext context) => Row(children: [
    SizedBox(
        width: 34,
        child: Text(label,
            style: _t(12, c: context.colors.textMedium))),
    const SizedBox(width: 8),
    Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: total == 0 ? 0 : value / total,
          backgroundColor: color.withValues(alpha: 0.1),
          color: color,
          minHeight: 8,
        ),
      ),
    ),
    const SizedBox(width: 8),
    Text('$value', style: _t(13, w: FontWeight.w800, c: color)),
  ]);
}

class _AttendanceTile extends StatelessWidget {
  final FullAttendance record;
  const _AttendanceTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final present = _isPresent(record);
    final color = present ? context.colors.success : _danger;
    final duration =
    record.attendance.isNotEmpty ? record.attendance.first.duration : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: IntrinsicHeight(
        child: Row(children: [
          Container(
            width: 5,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(16)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    present
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    color: color,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(record.sessions.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _t(14,
                              w: FontWeight.w700,
                              c: context.colors.textDark)),
                      if (record.sessions.scheduledAt != null) ...[
                        const SizedBox(height: 3),
                        Row(children: [
                          Icon(Icons.calendar_today_rounded,
                              size: 12, color: context.colors.textMedium),
                          const SizedBox(width: 4),
                          Text(_fmtDate(record.sessions.scheduledAt!),
                              style:
                              _t(11.5, c: context.colors.textMedium)),
                        ]),
                      ],
                    ],
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _Badge(present ? 'present'.tr : 'absent'.tr, color),
                    if (duration != null) ...[
                      const SizedBox(height: 4),
                      Text('$duration ${'minutes'.tr}',
                          style: _t(11, c: context.colors.textMedium)),
                    ],
                  ],
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${_weekday(d.weekday)}  ${d.day}/${d.month}/${d.year}';

  String _weekday(int w) => [
    '',
    'day_monday'.tr,
    'day_tuesday'.tr,
    'day_wednesday'.tr,
    'day_thursday'.tr,
    'day_friday'.tr,
    'day_saturday'.tr,
    'day_sunday'.tr,
  ][w];
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 3 — Exams
// ══════════════════════════════════════════════════════════════════════════════

class _ExamsTab extends StatefulWidget {
  final StudentCourseAnalyticsProvider prov;
  const _ExamsTab({required this.prov});

  @override
  State<_ExamsTab> createState() => _ExamsTabState();
}

class _ExamsTabState extends State<_ExamsTab> {
  int _filter = 0; // 0 all, 1 passed, 2 failed, 3 pending

  @override
  Widget build(BuildContext context) {
    final prov = widget.prov;
    if (prov.loadingExams) return const Center(child: AppLoadingIndicator());
    if (prov.examsError != null) {
      return _ErrorRetry(message: prov.examsError!, onRetry: prov.loadExams);
    }
    if (prov.exams.isEmpty) {
      return _Empty(
          icon: Icons.quiz_outlined, text: 'no_exams_yet'.tr);
    }

    final filtered = prov.exams.where((e) {
      switch (_filter) {
        case 1:
          return e.attempted && e.passed == true;
        case 2:
          return e.attempted && e.passed == false;
        case 3:
          return !e.attempted;
        default:
          return true;
      }
    }).toList();

    return RefreshIndicator(
      onRefresh: prov.loadExams,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _FilterChips(
            labels: ['filter_all'.tr, 'sa_passed_label'.tr, 'failed'.tr, 'not_attempted'.tr],
            selected: _filter,
            onSelect: (i) => setState(() => _filter = i),
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: _Empty(
                  icon: Icons.search_off_rounded, text: 'no_search_results'.tr),
            )
          else
            for (final e in filtered) _ExamTile(exam: e),
        ],
      ),
    );
  }
}

class _ExamTile extends StatelessWidget {
  final StudentExamSummary exam;
  const _ExamTile({required this.exam});

  Color _color(BuildContext c) => exam.passed == true
      ? c.colors.success
      : exam.passed == false
      ? _danger
      : Colors.blueGrey;

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    final hasScore = exam.attempted && exam.percentage != null;

    return _Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                color.withValues(alpha: 0.10),
                color.withValues(alpha: 0.03)
              ],
            ),
            borderRadius:
            const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.quiz_rounded, color: color, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(exam.examName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _t(14.5,
                      w: FontWeight.w700, c: context.colors.textDark)),
            ),
            const SizedBox(width: 8),
            _Badge(exam.statusLabel, color),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(children: [
            Row(children: [
              _InfoChip(Icons.timer_outlined, '${exam.duration ?? 0} ${'minutes'.tr}',
                  Colors.teal),
              if (exam.startDate != null) ...[
                const SizedBox(width: 16),
                _InfoChip(Icons.calendar_today_outlined,
                    _fmtDate(exam.startDate!), Colors.orange),
              ],
            ]),
            if (hasScore) ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('exam_grade'.tr,
                          style: _t(11, c: context.colors.textMedium)),
                      const SizedBox(height: 2),
                      Text(
                          '${exam.marksObtained?.toStringAsFixed(0) ?? '-'} / ${exam.totalMarks?.toStringAsFixed(0) ?? '-'}',
                          style: _t(15,
                              w: FontWeight.w700,
                              c: context.colors.textDark)),
                    ],
                  ),
                  Text('${exam.percentage!.toStringAsFixed(1)}%',
                      style: _t(22, w: FontWeight.w800, c: color)),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(
                      begin: 0,
                      end: (exam.percentage! / 100).clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => LinearProgressIndicator(
                    value: v,
                    backgroundColor: color.withValues(alpha: 0.1),
                    color: color,
                    minHeight: 9,
                  ),
                ),
              ),
            ] else if (!exam.attempted) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('sa_exam_not_taken_yet'.tr,
                    textAlign: TextAlign.center,
                    style: _t(12, c: context.colors.textMedium)),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

// ══════════════════════════════════════════════════════════════════════════════
// Shared widgets
// ══════════════════════════════════════════════════════════════════════════════

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  const _Card({required this.child, this.padding, this.margin});

  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    padding: padding,
    decoration: BoxDecoration(
      color: context.colors.cardBg,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
          color: context.colors.divider.withValues(alpha: 0.5), width: 0.6),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4))
      ],
    ),
    child: child,
  );
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final Widget child;
  const _SectionCard(
      {required this.icon,
        required this.title,
        required this.child,
        this.trailing});

  @override
  Widget build(BuildContext context) => _Card(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 19, color: context.colors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title,
              style: _t(14.5,
                  w: FontWeight.w800, c: context.colors.textDark)),
        ),
        if (trailing != null) trailing!,
      ]),
      const SizedBox(height: 16),
      child,
    ]),
  );
}

class _FilterChips extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  const _FilterChips(
      {required this.labels, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(children: [
      for (var i = 0; i < labels.length; i++)
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: i == selected
                    ? context.colors.primary
                    : context.colors.cardBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: i == selected
                      ? context.colors.primary
                      : context.colors.divider,
                  width: 0.8,
                ),
              ),
              child: Text(labels[i],
                  style: _t(12.5,
                      w: i == selected ? FontWeight.w700 : FontWeight.w500,
                      c: i == selected
                          ? Colors.white
                          : context.colors.textMedium)),
            ),
          ),
        ),
    ]),
  );
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot(this.color);

  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
    decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: _t(11, w: FontWeight.w700, c: color)),
  );
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Text(label, style: _t(12, c: context.colors.textMedium)),
      ]);
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Empty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: context.colors.primary.withValues(alpha: 0.08),
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            size: 42, color: context.colors.primary.withValues(alpha: 0.5)),
      ),
      const SizedBox(height: 14),
      Text(text, style: _t(14, c: context.colors.textMedium)),
    ]),
  );
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: _danger.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.wifi_off_rounded,
              size: 40, color: _danger.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 14),
        Text(message,
            textAlign: TextAlign.center,
            style: _t(13.5, c: context.colors.textMedium, h: 1.6)),
        const SizedBox(height: 18),
        SizedBox(
          width: 200,
          child: PrimaryButton(
            isLoading: false,
            label: 'retry_btn'.tr,
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
        ),
      ]),
    ),
  );
}