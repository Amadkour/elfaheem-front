// lib/features/student/analysis/student_course_analytics_screen.dart
// One course, everything about it — the student's (and the parent's) report:
//   Overview   overall score, KPIs, a kind summary, you vs the class, exam trend, attendance timeline
//   Attendance every session, searchable and filterable
//   Exams      every exam with its result
//   My marks   what the teacher published from the Data Lab (with the class average), progress and saved flags
// Open on a given tab with [initialTab] (0 overview · 1 attendance · 2 exams · 3 marks).
//
// Warm Editorial (system.md): the course's name on the canvas as the page title, then ONE hero block (the course's
// own tone) holding the overall score — its ring fills and the figure rolls (the page's one orchestrated entrance) —
// and the three figures that open the tabs; the tabs are the kit's pill track; everything under it is paper.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppCountUp, AppDrawIn, AppFill, AppOdometer, AppPressScale, AppTilt;
import 'package:flutter_education_app/design/chrome_button.dart' show ChromeIconButton;
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import '../../../utils/widget/base_page.dart';
import '../../teacher/analysis/attendance/attendance_model.dart';
import '../../teacher/data_lab/data_lab_models.dart';
import 'analytics_editorial.dart';
import 'attendance/student_attendance_model.dart';
import 'student_analytics_provider.dart';
import 'student_analytics_profile_screen.dart';
import 'student_analytics_widgets.dart';
import '../../shared/analytics/analytics_summary.dart' show anExamsWord, anSessionsWord;
import 'flags/student_flags_screen.dart';
import 'exam/student_exam_list_screen.dart';
import 'exam/student_exam_provider.dart';

String _level(double v) => anLevel(v);

Color _scoreColor(BuildContext c, double v) => anScoreColor(c, v);

String _fmt(String key, Map<String, Object?> params) => anFmt(key, params);

bool _isPresent(FullAttendance r) => anIsPresent(r);

/// Tabular figures: a column of numbers keeps its width while it changes.
const _tabular = [FontFeature.tabularFigures()];

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
    this.progress,
  });

  /// The enrolment's live progress (the hub has it): the figure the home and the course list show.
  final double? progress;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => StudentCourseAnalyticsProvider(courseId: courseId, initialBlock: initialBlock, enrolledProgress: progress)..loadAll(),
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
        width: AppWidth.wide,
        useWebCard: true,
        child: NestedScrollView(
          headerSliverBuilder: (ctx, _) => [
            SliverToBoxAdapter(
              child: _Hero(
                courseId: widget.courseId,
                title: widget.courseTitle,
                prov: prov,
                onOpenTab: (i) => _tab.animateTo(i),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabsDelegate(controller: _tab, background: ctx.colors.pinnedBackground),
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
// Hero: the course's name on the canvas, the score on the course's block
// ══════════════════════════════════════════════════════════════════════════════

class _Hero extends StatelessWidget {
  final int courseId;
  final String title;
  final StudentCourseAnalyticsProvider prov;
  final ValueChanged<int> onOpenTab;
  const _Hero({required this.courseId, required this.title, required this.prov, required this.onOpenTab});

  /// The score ring's diameter: smaller on a narrow phone.
  static double _ringSize(double width) => width >= 420 ? 132 : 112;

  @override
  Widget build(BuildContext context) {
    final overall = prov.overall ?? 0;
    final loading = prov.loadingAtt && prov.loadingExams;

    return SafeArea(
      bottom: false,
      child: LayoutBuilder(builder: (context, box) {
        final gutter = AppSpace.gutter(box.maxWidth);
        return Padding(
          padding: EdgeInsetsDirectional.fromSTEB(gutter, AppSpace.xs, gutter, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // ── the masthead: back · the course's name in the editorial face · refresh
            Row(children: [
              const AppBackButton(),
              AppSpace.gapSm,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(
                    header: true,
                    child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context)),
                  ),
                  Text('sa_report_title'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                ]),
              ),
              AppSpace.gapXs,
              ChromeIconButton(icon: Icons.refresh_rounded, label: 'refresh'.tr, onTap: prov.loadAll),
            ]),
            AppSpace.gapMd,
            // ── the block: the score and the three figures that open the tabs
            AppTilt(
              radius: AppRadius.block,
              glare: true,
              touchTilt: false,
              child: AppBlock(
                tone: AppBlockTone.forKey('course:$courseId'),
                hero: true,
                child: Builder(builder: (context) {
                  final b = AppBlock.colorsOf(context);
                  final ring = _ringSize(box.maxWidth);
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      _ScoreRing(value: loading ? 0 : overall, size: ring),
                      SizedBox(width: box.maxWidth >= 420 ? AppSpace.lg : AppSpace.md),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            loading ? '…' : _level(overall),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.headline(context).copyWith(color: b.ink),
                          ),
                          const SizedBox(height: AppSpace.xs),
                          Text(
                            prov.progress != null
                                ? anTr('sa_overall_hint_full', 'An average of your progress, attendance and exam results.')
                                : 'sa_overall_hint'.tr,
                            style: AppType.body(context).copyWith(color: b.muted),
                          ),
                          if (prov.progress != null) ...[
                            const SizedBox(height: AppSpace.xs),
                            Row(children: [
                              Icon(Icons.route_rounded, size: AppIconSize.sm, color: b.accentInk(context.colors.primary)),
                              const SizedBox(width: AppSpace.xs),
                              Flexible(
                                child: Text(
                                  '${anTr('an_course_progress', 'Course progress')}: ${anPct(prov.progress)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppType.label(context).copyWith(color: b.ink, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ]),
                          ],
                        ]),
                      ),
                    ]),
                    AppSpace.gapLg,
                    IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        _HeroStat(
                          onTap: () => onOpenTab(1),
                          icon: Icons.event_available_rounded,
                          value: '${prov.attendanceRate.toStringAsFixed(0)}%',
                          label: 'attendance_rate'.tr,
                        ),
                        AppSpace.gapXs,
                        _HeroStat(
                          onTap: () => onOpenTab(2),
                          icon: Icons.verified_rounded,
                          value: '${prov.passedCount}/${prov.attemptedCount}',
                          label: 'sa_passed_exams'.tr,
                        ),
                        AppSpace.gapXs,
                        _HeroStat(
                          onTap: () => onOpenTab(2),
                          icon: Icons.bar_chart_rounded,
                          value: '${prov.avgScore.toStringAsFixed(0)}%',
                          label: 'sa_avg_score'.tr,
                        ),
                      ]),
                    ),
                  ]);
                }),
              ),
            ),
          ]),
        );
      }),
    );
  }
}

/// A figure on the hero block that opens its tab: a slightly deeper well of the block's own tone.
class _HeroStat extends StatelessWidget {
  final IconData icon;
  final String value, label;
  final VoidCallback? onTap;
  const _HeroStat({required this.icon, required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final b = AppBlock.colorsOf(context);
    return Expanded(
      child: AppPressScale(
        enabled: onTap != null,
        child: Material(
          color: Color.lerp(b.surface, b.ink, 0.06),
          borderRadius: AppRadius.cardAll,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.sm, horizontal: AppSpace.xs),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, color: b.muted, size: AppIconSize.sm),
                  const SizedBox(height: AppSpace.xxs),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(value, style: AppType.figure(context).copyWith(color: b.ink, fontFeatures: _tabular)),
                  ),
                  Text(
                    label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.meta(context).copyWith(color: b.muted),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The overall score: a ring in the primary (lifted to read on the block) that fills once, the figure rolling.
class _ScoreRing extends StatelessWidget {
  final double value; // 0..100
  final double size;
  const _ScoreRing({required this.value, required this.size});

  /// The ring's stroke against its diameter.
  static const double _strokeShare = 0.085;

  @override
  Widget build(BuildContext context) {
    final b = AppBlock.colorsOf(context);
    final arc = b.accentInk(context.colors.primary);
    final track = Color.lerp(b.surface, b.ink, 0.10)!;
    final stroke = size * _strokeShare;
    return Semantics(
      label: '${'stat_total'.tr} ${value.round()}%',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          AppFill(
            value: (value / 100).clamp(0.0, 1.0),
            duration: const Duration(milliseconds: 900),
            builder: (context, v) => SizedBox.expand(
              child: CircularProgressIndicator(
                value: v,
                strokeWidth: stroke,
                strokeCap: StrokeCap.round,
                backgroundColor: track,
                color: arc,
              ),
            ),
          ),
          ExcludeSemantics(
            child: SizedBox(
              width: size - stroke * 4,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AppOdometer(
                    '${value.round()}%',
                    memoryKey: 'course_report.overall',
                    style: AppType.figureLarge(context).copyWith(color: b.ink),
                  ),
                ),
                Text('stat_total'.tr,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: b.muted)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Pinned tab bar: the kit's pill track on the canvas
// ══════════════════════════════════════════════════════════════════════════════

class _TabsDelegate extends SliverPersistentHeaderDelegate {
  final TabController controller;
  final Color background;
  _TabsDelegate({required this.controller, required this.background});

  static const double _extent = AppTouch.min + AppSpace.sm + AppSpace.xs;

  @override
  double get minExtent => _extent;
  @override
  double get maxExtent => _extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final wide = MediaQuery.sizeOf(context).width >= AppWidth.phoneMax;
    return Container(
    color: background,
    alignment: AlignmentDirectional.centerStart,
    padding: EdgeInsetsDirectional.fromSTEB(
      AppSpace.gutter(MediaQuery.sizeOf(context).width),
      AppSpace.sm,
      AppSpace.gutter(MediaQuery.sizeOf(context).width),
      AppSpace.xs,
    ),
    child: ListenableBuilder(
      // the TabController drives the page; the track follows it (a swipe moves the pill too)
      listenable: controller,
      // a phone keeps the four names only: with their icons they would not fit
      builder: (context, _) => AppTabs(
        expand: true,
        index: controller.index,
        onChanged: controller.animateTo,
        items: [
          AppTabItem('sa_tab_overview'.tr, icon: wide ? Icons.dashboard_rounded : null),
          AppTabItem('attendance'.tr, icon: wide ? Icons.fact_check_rounded : null),
          AppTabItem('exams'.tr, icon: wide ? Icons.quiz_rounded : null),
          AppTabItem(anTr('sa_tab_marks', 'My marks'), icon: wide ? Icons.workspace_premium_rounded : null),
        ],
      ),
    ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabsDelegate old) => old.controller != controller || old.background != background;
}

// ══════════════════════════════════════════════════════════════════════════════
// Tab 1 — Overview (parent-friendly summary)
// ══════════════════════════════════════════════════════════════════════════════

/// The list padding of every tab: the page gutter on the sides, room to breathe at the end.
EdgeInsets _tabPadding(BuildContext context) {
  final g = AppSpace.gutter(MediaQuery.sizeOf(context).width);
  return EdgeInsets.fromLTRB(g, AppSpace.xs, g, AppSpace.xl);
}

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
            _fmt('sa_ins_att_excellent', {'present': prov.presentCount, 'sessions': anSessionsWord(prov.totalSessions)})));
      } else if (rate >= 60) {
        list.add(_Insight(Icons.info_rounded, context.colors.warning,
            _fmt('sa_ins_att_fair', {'sessions': anSessionsWord(absent)})));
      } else {
        list.add(_Insight(Icons.warning_amber_rounded, context.colors.danger,
            _fmt('sa_ins_att_low', {'sessions': anSessionsWord(absent)})));
      }
    }

    if (prov.attemptedCount > 0) {
      final failed = prov.attemptedCount - prov.passedCount;
      list.add(_Insight(
        failed == 0 ? Icons.emoji_events_rounded : Icons.school_rounded,
        failed == 0 ? success : context.colors.warning,
        failed == 0
            ? _fmt('sa_ins_exam_all_passed', {'n': prov.passedCount})
            : _fmt('sa_ins_exam_some', {'passed': prov.passedCount, 'exams': anExamsWord(prov.attemptedCount), 'failed': failed}),
      ));

      final done = prov.exams
          .where((e) => e.attempted && e.percentage != null)
          .toList();
      if (done.isNotEmpty) {
        done.sort((a, b) => b.percentage!.compareTo(a.percentage!));
        list.add(_Insight(Icons.star_rounded, context.colors.accent2,
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
    if (prov.progress != null) {
      final p = prov.progress!;
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
      list.add(_Insight(Icons.pending_actions_rounded, context.colors.primary,
          _fmt('sa_ins_pending', {'n': pending})));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (prov.loadingAtt && prov.loadingExams) {
      return const AppListSkeleton();
    }
    final c = context.colors;
    final insights = _insights(context);

    return AppRefresh(
      onRefresh: prov.loadAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _tabPadding(context),
        children: [
          // the counts (the score itself is the hero's)
          AppKpiGrid(maxColumns: prov.progress != null ? 5 : 4, children: [
            AppKpiCard(
              icon: Icons.event_available_rounded,
              value: '${prov.presentCount}/${prov.totalSessions}',
              label: 'sa_sessions_attended'.tr,
            ),
            AppKpiCard(
              icon: Icons.event_busy_rounded,
              value: '${prov.totalSessions - prov.presentCount}',
              label: 'sa_sessions_missed'.tr,
            ),
            AppKpiCard(
              icon: Icons.workspace_premium_rounded,
              value: '${prov.passedCount}',
              label: 'sa_passed_exams'.tr,
            ),
            AppKpiCard(
              icon: Icons.insights_rounded,
              value: '${prov.avgScore.toStringAsFixed(0)}%',
              label: 'sa_avg_score'.tr,
            ),
            if (prov.progress != null)
              AppKpiCard(
                icon: Icons.route_rounded,
                value: anPct(prov.progress),
                label: anTr('an_course_progress', 'Course progress'),
              ),
          ]),

          if (insights.isNotEmpty)
            ParentComponent(
              featureKey: 'student_analytics.insights',
              child: _Section(
                title: 'sa_parent_summary'.tr,
                child: Column(children: [
                  for (var i = 0; i < insights.length; i++) ...[
                    if (i > 0) AppSpace.gapSm,
                    insights[i],
                  ],
                ]),
              ),
            ),

          // You vs the class (only what the teacher shares a class average for)
          if (prov.block != null)
            Builder(builder: (context) {
              // N5: "you" is the figure shown everywhere else, the class on the same scale (a cohort of one is level)
              final att = prov.totalSessions == 0 ? prov.block!.attendance : prov.attendanceRate;
              final ex = prov.attemptedCount == 0 ? prov.block!.examAvg : prov.avgScore;
              final rows = <(String, double?, double?)>[
                (anTr('an_course_progress', 'Course progress'), prov.progress, prov.classFor('progress', prov.progress)),
                ('attendance_rate'.tr, att, prov.classFor('attendance', att)),
                ('sa_avg_score'.tr, ex, prov.classFor('exam_avg', ex)),
              ];
              if (!rows.any((r) => r.$2 != null && r.$3 != null)) return const SizedBox.shrink();
              return _Section(
                title: anTr('an_vs_class', 'You and your class'),
                child: AnVsClassCard(rows: rows, bare: true),
              );
            }),

          // Teacher's published marks — a short preview, the full list is in "My marks"
          if ((prov.block?.extraColumns ?? const []).isNotEmpty)
            _Section(
              title: anTr('sa_tab_marks', 'My marks'),
              trailing: AppButton.ghost(
                label: anTr('an_see_all', 'See all'),
                size: AppButtonSize.sm,
                onPressed: () => onOpenTab(3),
              ),
              child: Column(children: [
                for (final (i, col) in prov.block!.extraColumns.take(3).indexed) ...[
                  if (i > 0) Divider(color: c.divider, height: AppSpace.lg, thickness: AppBorder.hairline),
                  AnMarkRow(col: col),
                ],
              ]),
            ),

          // Exam chart
          if (prov.exams.any((e) => e.attempted && e.percentage != null))
            _Section(
              title: 'sa_exam_results'.tr,
              trailing: Flexible(child: _Legend(items: [(c.success, 'sa_passed_label'.tr), (c.danger, 'failed'.tr)])),
              child: _ScoresChart(exams: prov.exams),
            ),

          // Attendance timeline
          if (prov.attendance.isNotEmpty)
            _Section(
              title: 'attendance_record'.tr,
              trailing: Flexible(child: _Legend(items: [(c.success, 'attending'.tr), (c.danger, 'did_not_attend'.tr)])),
              child: Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [for (final r in prov.attendance) _AttendanceCell(record: r)],
              ),
            ),
        ],
      ),
    );
  }
}

/// One session of the attendance timeline: a small square, emerald with a check or danger with a cross.
class _AttendanceCell extends StatelessWidget {
  const _AttendanceCell({required this.record});

  final FullAttendance record;

  static const double _size = AppSpace.lg;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final present = _isPresent(record);
    final fill = present ? c.success : c.danger;
    return Tooltip(
      message: record.sessions.name,
      child: Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(color: fill, borderRadius: AppRadius.chipAll),
        child: Icon(
          present ? Icons.check_rounded : Icons.close_rounded,
          size: AppIconSize.xs,
          color: appInkOnFill(context, fill),
        ),
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
  Widget build(BuildContext context) {
    final tint = appTintOn(context, color);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: AppTouch.min - AppSpace.sm,
        height: AppTouch.min - AppSpace.sm,
        decoration: BoxDecoration(color: tint, borderRadius: AppRadius.chipAll),
        child: Icon(icon, color: appInkOn(context, color, tint), size: AppIconSize.sm),
      ),
      AppSpace.gapSm,
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: Text(text, style: AppType.body(context).copyWith(color: context.colors.textDark)),
        ),
      ),
    ]);
  }
}

/// The exams as columns that grow once (AppDrawIn): emerald passed, danger below the mark, the score on top.
class _ScoresChart extends StatelessWidget {
  final List<StudentExamSummary> exams;
  const _ScoresChart({required this.exams});

  /// The tallest column.
  static const double _maxBar = 112;

  /// The shortest drawn column (a 0 % still shows a stub).
  static const double _minBar = 6;

  /// The two lines of the exam's name under its column.
  static const double _nameHeight = 32;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = exams
        .where((e) => e.attempted && e.percentage != null)
        .take(8)
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return AppDrawIn(
      builder: (context, t) => SizedBox(
        height: _maxBar + _nameHeight + AppSpace.xl,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final e in items)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
                  child: Builder(builder: (_) {
                    final pct = e.percentage!.clamp(0, 100).toDouble();
                    final color = e.passed == false ? c.danger : c.success;
                    final h = pct / 100 * _maxBar * t;
                    return Semantics(
                      label: '${e.examName} ${pct.round()}%',
                      child: ExcludeSemantics(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${pct.round()}',
                              style: AppType.label(context).copyWith(
                                fontWeight: FontWeight.w600,
                                color: appInkOn(context, color, c.cardBg),
                                fontFeatures: _tabular,
                              ),
                            ),
                            const SizedBox(height: AppSpace.xxs),
                            Container(
                              height: h < _minBar ? _minBar : h,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.chip)),
                              ),
                            ),
                            const SizedBox(height: AppSpace.xs),
                            SizedBox(
                              height: _nameHeight,
                              child: Text(
                                e.examName,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.meta(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
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
    if (prov.loadingAtt) return const AppListSkeleton();
    if (prov.attError != null) {
      return AppErrorState(message: prov.attError!, onRetry: prov.loadAttendance);
    }
    if (prov.attendance.isEmpty) {
      return AppEmpty(icon: Icons.event_note_rounded, title: 'sa_no_sessions_yet'.tr, tone: AppBlockTone.sky);
    }

    final q = _search.text.trim();
    final filtered = prov.attendance.where((r) {
      if (_filter == 1 && !_isPresent(r)) return false;
      if (_filter == 2 && _isPresent(r)) return false;
      if (q.isNotEmpty && !r.sessions.name.toLowerCase().contains(q.toLowerCase())) return false;
      return true;
    }).toList();

    return AppRefresh(
      onRefresh: prov.loadAttendance,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _tabPadding(context),
        children: [
          _AttendanceSummaryCard(
            present: prov.presentCount,
            total: prov.totalSessions,
            rate: prov.attendanceRate.toDouble(),
          ),
          AppSpace.gapMd,
          AppSearchField(
            controller: _search,
            hint: 'sa_search_session'.tr,
            debounce: Duration.zero,
            onChanged: (_) => setState(() {}),
          ),
          AppSpace.gapSm,
          AppTabs(
            items: [AppTabItem('filter_all'.tr), AppTabItem('attending'.tr), AppTabItem('did_not_attend'.tr)],
            index: _filter,
            onChanged: (i) => setState(() => _filter = i),
          ),
          AppSpace.gapMd,
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
              child: AppEmpty(icon: Icons.search_off_rounded, title: 'no_search_results'.tr),
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

  static const double _ring = 92;
  static const double _stroke = 9;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = _scoreColor(context, rate);
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Row(children: [
        SizedBox(
          width: _ring,
          height: _ring,
          child: Stack(alignment: Alignment.center, children: [
            AppFill(
              value: (rate / 100).clamp(0.0, 1.0),
              duration: const Duration(milliseconds: 800),
              builder: (_, v) => SizedBox.expand(
                child: CircularProgressIndicator(
                  value: v,
                  strokeWidth: _stroke,
                  strokeCap: StrokeCap.round,
                  backgroundColor: appTintOn(context, color),
                  color: color,
                ),
              ),
            ),
            AppCountUp(
              '${rate.toStringAsFixed(0)}%',
              memoryKey: 'course_report.attendance',
              style: AppType.figure(context).copyWith(fontFeatures: _tabular),
            ),
          ]),
        ),
        AppSpace.gapLg,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('sa_total_attendance'.tr, style: AppType.section(context)),
            AppSpace.gapSm,
            _BarRow('attending'.tr, present, total, c.success),
            AppSpace.gapXs,
            _BarRow('did_not_attend'.tr, total - present, total, c.danger),
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

  /// The label column's bounds (a short label stays short, a long one ellipsizes).
  static const double _labelMin = 34, _labelMax = 110;

  @override
  Widget build(BuildContext context) => Row(children: [
    ConstrainedBox(
        constraints: const BoxConstraints(minWidth: _labelMin, maxWidth: _labelMax),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
    AppSpace.gapXs,
    Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: AppFill(
          value: total == 0 ? 0 : value / total,
          builder: (_, v) => LinearProgressIndicator(
            value: v,
            backgroundColor: appTintOn(context, color),
            color: color,
            minHeight: AppSpace.xs,
          ),
        ),
      ),
    ),
    AppSpace.gapXs,
    Text('$value', style: AppType.row(context).copyWith(fontWeight: FontWeight.w600, fontFeatures: _tabular)),
  ]);
}

class _AttendanceTile extends StatelessWidget {
  final FullAttendance record;
  const _AttendanceTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final present = _isPresent(record);
    final color = present ? c.success : c.danger;
    final tint = appTintOn(context, color);
    final duration =
    record.attendance.isNotEmpty ? record.attendance.first.duration : null;

    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpace.xs),
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
      child: Row(children: [
        Container(
          width: AppTouch.min - AppSpace.xs,
          height: AppTouch.min - AppSpace.xs,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          child: Icon(
            present ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: appInkOn(context, color, tint),
            size: AppIconSize.lg,
          ),
        ),
        AppSpace.gapSm,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(record.sessions.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              if (record.sessions.scheduledAt != null) ...[
                const SizedBox(height: AppSpace.xxs),
                AnalyticsFact(icon: Icons.calendar_today_rounded, text: _fmtDate(record.sessions.scheduledAt!)),
              ],
            ],
          ),
        ),
        AppSpace.gapXs,
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AppStatusBadge(label: present ? 'present'.tr : 'absent'.tr, tone: present ? AppTone.success : AppTone.danger),
            if (duration != null) ...[
              const SizedBox(height: AppSpace.xxs),
              Text('$duration ${'minutes'.tr}', style: AppType.meta(context)),
            ],
          ],
        ),
      ]),
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
    final c = context.colors;
    if (prov.loadingExams) return const AppListSkeleton();
    if (prov.examsError != null) {
      return AppErrorState(message: prov.examsError!, onRetry: prov.loadExams);
    }
    if (prov.exams.isEmpty) {
      return AppEmpty(icon: Icons.quiz_outlined, title: 'no_exams_yet'.tr);
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

    return AppRefresh(
      onRefresh: prov.loadExams,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _tabPadding(context),
        children: [
          // Taking / retrying an exam happens in the exam list — one tap away.
          ParentComponent(
            featureKey: 'analytics.exams_chip',
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: AppCard(
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
                  Icon(Icons.play_circle_rounded, color: c.primary, size: AppIconSize.lg),
                  AppSpace.gapSm,
                  Expanded(
                    child: Text(
                      prov.pendingCount > 0
                          ? anFmt('an_exams_waiting', {'n': prov.pendingCount}, '{n} exams are waiting for you — open my exams')
                          : anTr('an_open_exams', 'Open my exams'),
                      style: AppType.bodyStrong(context),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: c.textLight),
                ]),
              ),
            ),
          ),
          AppTabs(
            items: [
              AppTabItem('filter_all'.tr),
              AppTabItem('sa_passed_label'.tr),
              AppTabItem('failed'.tr),
              AppTabItem('not_attempted'.tr),
            ],
            index: _filter,
            onChanged: (i) => setState(() => _filter = i),
          ),
          AppSpace.gapMd,
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
              child: AppEmpty(icon: Icons.search_off_rounded, title: 'no_search_results'.tr),
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

  AppTone get _tone => exam.passed == true
      ? AppTone.success
      : exam.passed == false
      ? AppTone.danger
      : AppTone.neutral;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = _tone;
    final color = appToneColor(context, tone);
    final tint = appToneTint(context, tone);
    final hasScore = exam.attempted && exam.percentage != null;

    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: AppTouch.min - AppSpace.xs,
            height: AppTouch.min - AppSpace.xs,
            decoration: BoxDecoration(color: tint, borderRadius: AppRadius.chipAll),
            child: Icon(Icons.quiz_rounded, color: appToneInk(context, tone), size: AppIconSize.md),
          ),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(exam.examName, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              const SizedBox(height: AppSpace.xxs),
              Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xxs, children: [
                AnalyticsFact(icon: Icons.timer_outlined, text: '${exam.duration ?? 0} ${'minutes'.tr}'),
                if (exam.startDate != null)
                  AnalyticsFact(icon: Icons.calendar_today_outlined, text: _fmtDate(exam.startDate!)),
              ]),
            ]),
          ),
          AppSpace.gapXs,
          Flexible(child: AppStatusBadge(label: exam.statusLabel, tone: tone)),
        ]),
        if (hasScore) ...[
          AppSpace.gapMd,
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('exam_grade'.tr, style: AppType.meta(context)),
                    Text(
                      '${exam.marksObtained?.toStringAsFixed(0) ?? '-'} / ${exam.totalMarks?.toStringAsFixed(0) ?? '-'}',
                      textDirection: TextDirection.ltr, // "18 / 20" reads the same in Arabic
                      style: AppType.figure(context).copyWith(fontFeatures: _tabular),
                    ),
                  ],
                ),
              ),
              Text(
                '${exam.percentage!.toStringAsFixed(1)}%',
                style: AppType.figureLarge(context).copyWith(color: appInkOn(context, color, c.cardBg)),
              ),
            ],
          ),
          AppSpace.gapXs,
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: AppFill(
              value: (exam.percentage! / 100).clamp(0.0, 1.0),
              builder: (_, v) => LinearProgressIndicator(
                value: v,
                backgroundColor: tint,
                color: color,
                minHeight: AppSpace.xs,
              ),
            ),
          ),
        ] else if (!exam.attempted) ...[
          AppSpace.gapSm,
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm, horizontal: AppSpace.sm),
            decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.controlAll),
            child: Text('sa_exam_not_taken_yet'.tr, textAlign: TextAlign.center, style: AppType.meta(context)),
          ),
        ],
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
    if (b == null && prov.loadingBlock) return const AppListSkeleton();
    if (b == null) {
      return AppRefresh(
        onRefresh: prov.loadBlock,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          AppEmpty(
            icon: Icons.workspace_premium_outlined,
            title: anTr('sa_marks_unavailable', 'No marks shared yet'),
            message: anTr('sa_marks_unavailable_sub', 'When your teacher shares results for this course, they will appear here with the class average.'),
          ),
        ]),
      );
    }
    final marks = b.extraColumns;
    return AppRefresh(
      onRefresh: prov.loadBlock,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _tabPadding(context),
        children: [
          // progress + attendance at a glance
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.lg, horizontal: AppSpace.xs),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              Flexible(child: AnRing(value: prov.progress, label: anTr('an_course_progress', 'Course progress'))),
              Flexible(child: AnRing(value: b.attendance, label: 'attendance_rate'.tr)),
              Flexible(child: AnRing(value: b.examAvg, label: 'sa_avg_score'.tr)),
            ]),
          ),
          if (b.held > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: AnalyticsFact(
                icon: Icons.event_available_rounded,
                text: anFmt('an2_you_attended_of', {'a': b.attended, 'sessions': anSessionsWord(b.held)}, 'You attended {a} of {sessions} so far'), // L2
              ),
            ),
          AppSection(
            title: 'dl_profile_marks'.tr,
            subtitle: 'dl_profile_marks_sub'.tr,
            child: marks.isEmpty
                ? AppCard(
                    child: Row(children: [
                      Icon(Icons.hourglass_empty_rounded, color: c.textLight, size: AppIconSize.md),
                      AppSpace.gapSm,
                      Expanded(
                        child: Text(anTr('sa_marks_none', 'Your teacher has not published any marks for this course yet.'),
                            style: AppType.body(context)),
                      ),
                    ]),
                  )
                : AppCard(
                    child: Column(children: [
                      for (var i = 0; i < marks.length; i++) ...[
                        if (i > 0) Divider(color: c.divider, height: AppSpace.lg, thickness: AppBorder.hairline),
                        AnMarkRow(col: marks[i]),
                      ],
                    ]),
                  ),
          ),
          AppSection(
            title: 'dl_flags_title'.tr,
            subtitle: 'dl_flags_sub'.tr,
            child: Row(children: [
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
              AppSpace.gapSm,
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
          ),
          AppSpace.gapLg,
          ParentComponent(
            featureKey: 'data_lab.my_profile',
            child: AppButton.secondary(
              label: anTr('an_full_profile', 'My full analytics profile'),
              icon: Icons.insights_rounded,
              expand: true,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => StudentAnalyticsProfileScreen.forStudent(courseId: courseId)),
              ),
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

/// A section of the overview: the editorial heading on the canvas (its own 32 / 12 rhythm), the content on paper.
class _Section extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;
  const _Section({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) => AppSection(
    title: title,
    trailing: trailing,
    child: AppCard(child: child),
  );
}

/// A chart's key: a dot of each colour and its word.
class _Legend extends StatelessWidget {
  const _Legend({required this.items});

  final List<(Color, String)> items;

  static const double _dot = AppSpace.xs;

  @override
  Widget build(BuildContext context) => Wrap(alignment: WrapAlignment.end, spacing: AppSpace.sm, runSpacing: AppSpace.xxs, children: [
    for (final (color, label) in items)
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: _dot, height: _dot, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: AppSpace.xxs),
        Text(label, style: AppType.meta(context)),
      ]),
  ]);
}
