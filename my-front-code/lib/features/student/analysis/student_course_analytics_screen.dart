// lib/features/student/analysis/student_course_analytics_screen.dart
// One course, everything about it — the student's (and the parent's) report:
//   Overview   overall score, KPIs, a kind summary, you vs the class, exam trend, attendance timeline
//   Attendance every session, searchable and filterable
//   Exams      every exam with its result
//   My marks   what the teacher published from the Data Lab (with the class average), progress and saved flags
// Open on a given tab with [initialTab] (0 overview · 1 attendance · 2 exams · 3 marks).
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
import '../../teacher/data_lab/data_lab_models.dart';
import 'attendance/student_attendance_model.dart';
import 'student_analytics_provider.dart';
import 'student_analytics_profile_screen.dart';
import 'student_analytics_widgets.dart';
import 'flags/student_flags_screen.dart';
import 'exam/student_exam_list_screen.dart';
import 'exam/student_exam_provider.dart';

TextStyle _t(double size, {FontWeight w = FontWeight.w500, Color? c, double? h}) => anText(size, w: w, c: c, h: h);

String _level(double v) => anLevel(v);

Color _scoreColor(BuildContext c, double v) => anScoreColor(c, v);

String _fmt(String key, Map<String, Object?> params) => anFmt(key, params);

bool _isPresent(FullAttendance r) => anIsPresent(r);

// ══════════════════════════════════════════════════════════════════════════════
// Entry
// ══════════════════════════════════════════════════════════════════════════════

class StudentCourseAnalyticsScreen extends StatelessWidget {
  final int courseId;
  final String courseTitle;

  /// 0 overview · 1 attendance · 2 exams · 3 my marks
  final int initialTab;

  /// The course's analytics block when the caller already has it (the hub does): it shows at once.
  final DlCourseBlock? initialBlock;

  const StudentCourseAnalyticsScreen({
    super.key,
    required this.courseId,
    required this.courseTitle,
    this.initialTab = 0,
    this.initialBlock,
  });

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => StudentCourseAnalyticsProvider(courseId: courseId, initialBlock: initialBlock)..loadAll(),
    child: _CourseAnalyticsView(courseId: courseId, courseTitle: courseTitle, initialTab: initialTab),
  );
}

class _CourseAnalyticsView extends StatefulWidget {
  final int courseId;
  final String courseTitle;
  final int initialTab;
  const _CourseAnalyticsView({required this.courseId, required this.courseTitle, required this.initialTab});

  @override
  State<_CourseAnalyticsView> createState() => _CourseAnalyticsViewState();
}

class _CourseAnalyticsViewState extends State<_CourseAnalyticsView>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this, initialIndex: widget.initialTab.clamp(0, 3));
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
      textDirection: pageDirection, // follows the app language (it was forced to RTL)
      child: BasePage(
        maxWith: 1100,
        useWebCard: true,
        child: NestedScrollView(
          headerSliverBuilder: (ctx, _) => [
            SliverToBoxAdapter(
              child: _Hero(title: widget.courseTitle, prov: prov, onOpenTab: (i) => _tab.animateTo(i)),
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
              _OverviewTab(prov: prov, onOpenTab: (i) => _tab.animateTo(i)),
              _AttendanceTab(prov: prov),
              _ExamsTab(prov: prov),
              _MarksTab(prov: prov, courseId: widget.courseId, courseTitle: widget.courseTitle),
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
  final ValueChanged<int> onOpenTab;
  const _Hero({required this.title, required this.prov, required this.onOpenTab});

  @override
  Widget build(BuildContext context) {
    final overall = prov.overall ?? 0;
    final loading = prov.loadingAtt && prov.loadingExams;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [context.colors.primaryDark, context.colors.primary],
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
                      prov.progress != null
                          ? anTr('sa_overall_hint_full', 'An average of your progress, attendance and exam results.')
                          : 'sa_overall_hint'.tr,
                      style: _t(12, c: Colors.white70, h: 1.6),
                    ),
                    if (prov.progress != null) ...[
                      const SizedBox(height: 10),
                      Row(children: [
                        const Icon(Icons.trending_up_rounded, size: 16, color: Colors.white),
                        const SizedBox(width: 6),
                        Text('${anTr('an_course_progress', 'Course progress')}: ${anPct(prov.progress)}',
                            style: _t(12.5, w: FontWeight.w700, c: Colors.white)),
                      ]),
                    ],
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              _HeroStat(
                onTap: () => onOpenTab(1),
                icon: Icons.check_circle_rounded,
                color: Colors.white,
                value: '${prov.attendanceRate.toStringAsFixed(0)}%',
                label: 'attendance_rate'.tr,
              ),
              const SizedBox(width: 10),
              _HeroStat(
                onTap: () => onOpenTab(2),
                icon: Icons.emoji_events_rounded,
                color: Colors.white,
                value: '${prov.passedCount}/${prov.attemptedCount}',
                label: 'sa_passed_exams'.tr,
              ),
              const SizedBox(width: 10),
              _HeroStat(
                onTap: () => onOpenTab(2),
                icon: Icons.bar_chart_rounded,
                color: Colors.white,
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
  final VoidCallback? onTap;
  const _HeroStat(
      {required this.icon,
        required this.color,
        required this.value,
        required this.label,
        this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(onTap: onTap, child: Container(
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
    )),
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

  // Scales down instead of overflowing: four tabs fit on a small phone too.
  Widget _tab(IconData i, String s) => Tab(
    height: 42,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 16),
        const SizedBox(width: 6),
        Text(s),
      ]),
    ),
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
                  colors: [context.colors.primaryDark, primary]),
            ),
            labelColor: Colors.white,
            unselectedLabelColor: inactive,
            labelStyle: _t(12.5, w: FontWeight.w700),
            unselectedLabelStyle: _t(12.5),
            tabs: [
              _tab(Icons.dashboard_rounded, 'sa_tab_overview'.tr),
              _tab(Icons.fact_check_rounded, 'attendance'.tr),
              _tab(Icons.quiz_rounded, 'exams'.tr),
              _tab(Icons.workspace_premium_rounded, anTr('sa_tab_marks', 'My marks')),
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
  final ValueChanged<int> onOpenTab;
  const _OverviewTab({required this.prov, required this.onOpenTab});

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
        list.add(_Insight(Icons.info_rounded, context.colors.warning,
            _fmt('sa_ins_att_fair', {'absent': absent})));
      } else {
        list.add(_Insight(Icons.warning_amber_rounded, context.colors.danger,
            _fmt('sa_ins_att_low', {'absent': absent})));
      }
    }

    if (prov.attemptedCount > 0) {
      final failed = prov.attemptedCount - prov.passedCount;
      list.add(_Insight(
        failed == 0 ? Icons.emoji_events_rounded : Icons.school_rounded,
        failed == 0 ? success : context.colors.warning,
        failed == 0
            ? _fmt('sa_ins_exam_all_passed', {'n': prov.passedCount})
            : _fmt('sa_ins_exam_some', {'passed': prov.passedCount, 'attempted': prov.attemptedCount, 'failed': failed}),
      ));

      final done = prov.exams
          .where((e) => e.attempted && e.percentage != null)
          .toList();
      if (done.isNotEmpty) {
        done.sort((a, b) => b.percentage!.compareTo(a.percentage!));
        list.add(_Insight(Icons.star_rounded, context.colors.primary,
            _fmt('sa_ins_best', {'name': done.first.examName, 'pct': done.first.percentage!.toStringAsFixed(0)})));
      }
    }

    final tr = prov.trend;
    if (tr != null && tr.abs() >= 5) {
      list.add(_Insight(
        tr > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
        tr > 0 ? success : context.colors.warning,
        tr > 0
            ? anFmt('sa_ins_trend_up', {'n': tr.round()}, 'Your last exam is {n} points above your earlier average — keep it up!')
            : anFmt('sa_ins_trend_down', {'n': (-tr).round()}, 'Your last exam is {n} points below your earlier average — a quick review can help.'),
      ));
    }

    final b = prov.block;
    if (b != null && b.progress != null) {
      final p = b.progress!;
      list.add(_Insight(
        Icons.route_rounded,
        p >= 75 ? success : (p >= 40 ? context.colors.primary : context.colors.warning),
        p >= 100
            ? anTr('sa_ins_progress_done', 'You completed every lesson of the course 🎉')
            : anFmt('sa_ins_progress', {'n': p.round()}, 'You have completed {n}% of the course content.'),
      ));
    }
    if (b != null && b.reviewFlags > 0) {
      list.add(_Insight(Icons.bookmark_rounded, context.colors.warning,
          anFmt('sa_ins_review', {'n': b.reviewFlags}, '{n} saved questions are waiting in your review bank.')));
    }

    final pending = prov.exams.where((e) => !e.attempted).length;
    if (pending > 0) {
      list.add(_Insight(Icons.pending_actions_rounded, context.colors.accent2,
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
                color: context.colors.danger,
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
                color: context.colors.warning,
                value: '${prov.passedCount}',
                label: 'sa_passed_exams'.tr,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiCard(
                icon: Icons.insights_rounded,
                color: context.colors.primary,
                value: '${prov.avgScore.toStringAsFixed(0)}%',
                label: 'sa_avg_score'.tr,
              ),
            ),
          ]),
          if (prov.block?.progress != null) ...[
            const SizedBox(height: 12),
            _KpiCard(
              icon: Icons.route_rounded,
              color: context.colors.purple,
              value: anPct(prov.block!.progress),
              label: anTr('an_course_progress', 'Course progress'),
            ),
          ],
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

          // You vs the class (only what the teacher shares a class average for)
          if (prov.block != null)
            Builder(builder: (context) {
              final rows = <(String, double?, double?)>[
                (anTr('an_course_progress', 'Course progress'), prov.block!.progress, prov.classAvg('progress')),
                ('attendance_rate'.tr, prov.totalSessions == 0 ? prov.block!.attendance : prov.attendanceRate, prov.classAvg('attendance')),
                ('sa_avg_score'.tr, prov.attemptedCount == 0 ? prov.block!.examAvg : prov.avgScore, prov.classAvg('exam_avg')),
              ];
              if (!rows.any((r) => r.$2 != null && r.$3 != null)) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _SectionCard(
                  icon: Icons.groups_rounded,
                  title: anTr('an_vs_class', 'You and your class'),
                  child: AnVsClassCard(rows: rows, bare: true),
                ),
              );
            }),

          // Teacher's published marks — a short preview, the full list is in "My marks"
          if ((prov.block?.extraColumns ?? const []).isNotEmpty) ...[
            _SectionCard(
              icon: Icons.workspace_premium_rounded,
              title: anTr('sa_tab_marks', 'My marks'),
              trailing: TextButton(
                onPressed: () => onOpenTab(3),
                child: Text(anTr('an_see_all', 'See all'), style: _t(12, w: FontWeight.w700, c: context.colors.primary)),
              ),
              child: Column(children: [
                for (final (i, col) in prov.block!.extraColumns.take(3).indexed) ...[
                  if (i > 0) Divider(color: context.colors.divider, height: 22),
                  AnMarkRow(col: col),
                ],
              ]),
            ),
            const SizedBox(height: 16),
          ],

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
                _Dot(context.colors.danger),
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
                _Dot(context.colors.danger),
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
                              : context.colors.danger)
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
                  e.passed == false ? context.colors.danger : context.colors.success;
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
      if (q.isNotEmpty && !r.sessions.name.toLowerCase().contains(q.toLowerCase())) return false;
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
            _BarRow('did_not_attend'.tr, total - present, total, context.colors.danger),
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
    ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 34, maxWidth: 110),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
    final color = present ? context.colors.success : context.colors.danger;
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
              borderRadius: const BorderRadiusDirectional.horizontal(
                  start: Radius.circular(16)),
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
          // Taking / retrying an exam happens in the exam list — one tap away.
          ParentComponent(
            featureKey: 'analytics.exams_chip',
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AnCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                borderColor: context.colors.primary.withValues(alpha: 0.3),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider(
                      create: (_) => StudentExamProvider()..loadMyExams(),
                      child: const StudentExamListScreen(),
                    ),
                  ),
                ),
                child: Row(children: [
                  Icon(Icons.play_circle_rounded, color: context.colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      prov.pendingCount > 0
                          ? anFmt('an_exams_waiting', {'n': prov.pendingCount}, '{n} exams are waiting for you — open my exams')
                          : anTr('an_open_exams', 'Open my exams'),
                      style: _t(13, w: FontWeight.w700, c: context.colors.textDark),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: context.colors.primary),
                ]),
              ),
            ),
          ),
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
      ? c.colors.danger
      : c.colors.textMedium;

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
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
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
                  context.colors.accent2),
              if (exam.startDate != null) ...[
                const SizedBox(width: 16),
                _InfoChip(Icons.calendar_today_outlined,
                    _fmtDate(exam.startDate!), context.colors.warning),
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
                  color: context.colors.textLight.withValues(alpha: 0.10),
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
// Tab 4 — My marks (Data Lab: what the teacher published, progress, saved flags)
// ══════════════════════════════════════════════════════════════════════════════

class _MarksTab extends StatelessWidget {
  final StudentCourseAnalyticsProvider prov;
  final int courseId;
  final String courseTitle;
  const _MarksTab({required this.prov, required this.courseId, required this.courseTitle});

  void _flags(BuildContext context, int tab) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => StudentFlagsScreen(courseId: courseId, courseTitle: courseTitle, initialTab: tab)),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = prov.block;
    if (b == null && prov.loadingBlock) return const Center(child: AppLoadingIndicator());
    if (b == null) {
      return RefreshIndicator(
        onRefresh: prov.loadBlock,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          const SizedBox(height: 40),
          AnEmpty(
            icon: Icons.workspace_premium_outlined,
            title: anTr('sa_marks_unavailable', 'No marks shared yet'),
            sub: anTr('sa_marks_unavailable_sub', 'When your teacher shares results for this course, they will appear here with the class average.'),
          ),
        ]),
      );
    }
    final marks = b.extraColumns;
    return RefreshIndicator(
      onRefresh: prov.loadBlock,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // progress + attendance at a glance
          AnCard(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              AnRing(value: b.progress, label: anTr('an_course_progress', 'Course progress')),
              AnRing(value: b.attendance, label: 'attendance_rate'.tr),
              AnRing(value: b.examAvg, label: 'sa_avg_score'.tr),
            ]),
          ),
          if (b.held > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Icon(Icons.event_available_rounded, size: 16, color: c.success),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${'dl_attended'.tr} ${b.attended} ${'dl_of'.tr} ${b.held} ${'dl_sessions_held'.tr}',
                      style: _t(12, c: c.textMedium)),
                ),
              ]),
            ),
          AnSectionTitle(
            'dl_profile_marks'.tr,
            icon: Icons.workspace_premium_rounded,
            subtitle: 'dl_profile_marks_sub'.tr,
          ),
          if (marks.isEmpty)
            AnCard(
              child: Row(children: [
                Icon(Icons.hourglass_empty_rounded, color: c.textLight),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(anTr('sa_marks_none', 'Your teacher has not published any marks for this course yet.'),
                      style: _t(13, c: c.textMedium, h: 1.5)),
                ),
              ]),
            )
          else
            AnCard(
              child: Column(children: [
                for (var i = 0; i < marks.length; i++) ...[
                  if (i > 0) Divider(color: c.divider, height: 24),
                  AnMarkRow(col: marks[i]),
                ],
              ]),
            ),
          AnSectionTitle('dl_flags_title'.tr, icon: Icons.bookmarks_rounded, subtitle: 'dl_flags_sub'.tr),
          Row(children: [
            Expanded(
              child: ParentComponent(
                featureKey: 'analytics.review_chip',
                child: AnFlagTile(
                  icon: Icons.bookmark_rounded,
                  color: c.warning,
                  value: b.reviewFlags,
                  label: 'dl_review_flags'.tr,
                  onTap: () => _flags(context, 0),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ParentComponent(
                featureKey: 'analytics.read_flags_chip',
                child: AnFlagTile(
                  icon: Icons.menu_book_rounded,
                  color: c.danger,
                  value: b.readFlags,
                  label: 'dl_read_flags'.tr,
                  onTap: () => _flags(context, 1),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 18),
          ParentComponent(
            featureKey: 'data_lab.my_profile',
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                side: BorderSide(color: c.primary.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => StudentAnalyticsProfileScreen.forStudent(courseId: courseId)),
              ),
              icon: Icon(Icons.insights_rounded, color: c.primary),
              label: Text(anTr('an_full_profile', 'My full analytics profile'), style: _t(13.5, w: FontWeight.w800, c: c.primary)),
            ),
          ),
        ],
      ),
    );
  }
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
            color: context.colors.danger.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.wifi_off_rounded,
              size: 40, color: context.colors.danger.withValues(alpha: 0.7)),
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