// lib/features/parent/parent_reports_page.dart
// Daily / weekly / monthly reports.
//   ParentReportsPage          -> the "Reports" tab: ALL linked children
//   ParentChildReportScreen    -> one child (opened from the children list)
// The server returns the three periods of every child in ONE call (period=all), so switching
// between Daily / Weekly / Monthly is instant. Day / week boundaries are computed by the server
// (Africa/Cairo, weeks start on Saturday by default).
//
// Each report also shows "Marks from the teachers": the child's analytics profile (the same view the child has in
// the student app — published marks with the class average). With several children, chips at the top show one.
//
// Warm Editorial (D-610 – D-629): the child's report opens on ONE block in the child's own tone (parentChildTone) —
// the score ring is the page's memorable element, its figure rolls (AppOdometer) and the block leans a little under
// the pointer (AppTilt.subtle); everything after it is paper: the findings, the figures (count up once), the trend
// (the kit's AppBarChart), homework as an AppDonut, habits as bars that fill once.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppTilt;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../shared/analytics/analytics_ui.dart' show anTr;
import '../teacher/data_lab/data_lab_models.dart' show DlProfile;
import 'parent_child_marks.dart';
import 'parent_link_providers.dart';
import 'parent_report_widgets.dart';
import 'parent_widgets.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart' show EntityLink;
import 'package:flutter_education_app/design/master_detail/entity_navigator.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/design/master_detail/master_detail_scaffold.dart';

const _periods = ['daily', 'weekly', 'monthly'];

DateTime _step(DateTime d, String period, int dir) {
  switch (period) {
    case 'weekly':
      return d.add(Duration(days: 7 * dir));
    case 'monthly':
      return DateTime(d.year, d.month + dir, d.day > 28 ? 28 : d.day);
    default:
      return d.add(Duration(days: dir));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
class ParentReportsPage extends StatelessWidget {
  const ParentReportsPage({super.key});

  @override
  Widget build(BuildContext context) => const _ReportsBody(studentId: null, studentName: '');
}

class ParentChildReportScreen extends StatelessWidget {
  const ParentChildReportScreen({super.key, required this.studentId, required this.studentName});

  final int studentId;
  final String studentName;

  @override
  Widget build(BuildContext context) => BasePage(
    appBar: ScreenAppBar(title: studentName),
    child: _ReportsBody(studentId: studentId, studentName: studentName),
  );
}

class _ReportsBody extends StatefulWidget {
  const _ReportsBody({required this.studentId, required this.studentName});

  final int? studentId;
  final String studentName;

  @override
  State<_ReportsBody> createState() => _ReportsBodyState();
}

class _ReportsBodyState extends State<_ReportsBody> {
  late final ParentReportsProvider _p = ParentReportsProvider();
  // A course of the report opens in the shared panel as the child sees it, under the child's name (D-290).
  final _panel = EntityPanelController(rowKind: EntityKind.student);
  String _period = 'daily';
  int? _only; // several children: show one (null = all)

  @override
  void initState() {
    super.initState();
    widget.studentId == null ? _p.load() : _p.loadOne(widget.studentId!, widget.studentName);
  }

  @override
  void dispose() {
    _p.dispose();
    _panel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: _p,
    child: Consumer<ParentReportsProvider>(builder: (context, p, _) {
      return MasterDetailScaffold(
        controller: _panel,
        rootLabel: 'md_p7_my_children'.tr,
        list: Column(children: [
        // period + date selector ------------------------------------------------
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
          child: AppWidthBox(
            width: AppWidth.reading,
            gutters: false,
            child: Column(children: [
              AppTabs(
                expand: true,
                items: [for (final x in _periods) AppTabItem('pl_period_$x'.tr)],
                index: _periods.indexOf(_period),
                onChanged: (i) => setState(() => _period = _periods[i]),
              ),
              const SizedBox(height: AppSpace.xxs),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                AppIconButton(
                  icon: Icons.chevron_left_rounded,
                  tooltip: MaterialLocalizations.of(context).previousPageTooltip,
                  onPressed: () => p.setDate(_step(p.refDate, _period, -1)),
                ),
                Flexible(
                  child: AppButton.ghost(
                    icon: Icons.calendar_month_rounded,
                    label: plDate(p.refDate),
                    onPressed: () async {
                      final d = await showDatePicker(
                          context: context,
                          initialDate: p.refDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now());
                      if (d != null) p.setDate(d);
                    },
                  ),
                ),
                AppIconButton(
                  icon: Icons.chevron_right_rounded,
                  tooltip: MaterialLocalizations.of(context).nextPageTooltip,
                  onPressed: _step(p.refDate, _period, 1).isAfter(DateTime.now())
                      ? null
                      : () => p.setDate(_step(p.refDate, _period, 1)),
                ),
              ]),
            ]),
          ),
        ),
        if (widget.studentId == null && p.children.length > 1)
          SizedBox(
            height: AppTouch.min + AppSpace.xs,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xxs),
              children: [
                _childChip(context, null, anTr('pl_all_children', 'All children')),
                for (final ch in p.children)
                  if ((ch['student'] as Map?)?['id'] case final num id)
                    _childChip(context, id.toInt(), '${(ch['student'] as Map)['name']}'),
              ],
            ),
          ),
        Expanded(
          child: !p.loaded && p.isLoading
              ? const AppListSkeleton(items: 4)
              : !p.loaded && p.hasError
              ? ErrorRetry(message: p.errorMessage ?? '', onRetry: p.reload)
              : p.children.isEmpty
              ? AppEmpty(icon: Icons.family_restroom_rounded, title: 'pl_no_children'.tr)
              : AppRefresh(
            onRefresh: p.reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.lg),
              children: [
                for (final ch in p.children)
                  if (ch[_period] is Map && (_only == null || (ch['student'] as Map?)?['id'] == _only))
                    AppWidthBox(
                      width: AppWidth.reading,
                      gutters: false,
                      child: _ChildReportCard(
                        childId: ((ch['student'] as Map?)?['id'] as num?)?.toInt(),
                        name: '${(ch['student'] as Map)['name']}',
                        report: Map<String, dynamic>.from(ch[_period] as Map),
                        period: _period,
                        profile: p.profiles[((ch['student'] as Map?)?['id'] as num?)?.toInt()],
                      ),
                    ),
              ],
            ),
          ),
        ),
      ]),
      );
    }),
  );

  Widget _childChip(BuildContext context, int? id, String label) {
    final c = context.colors;
    final on = _only == id;
    final surface = on ? c.primary : c.cardBg;
    final ink = on ? c.onHero : c.textDark;
    final r = BorderRadius.circular(AppRadius.pill);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
      child: Semantics(
        button: true,
        selected: on,
        child: Material(
          color: surface,
          shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: on ? c.primary : c.divider, width: AppBorder.hairline)),
          child: InkWell(
            borderRadius: r,
            onTap: () => setState(() => _only = id),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xs, 0, AppSpace.md, 0),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (id == null)
                  Icon(Icons.groups_rounded, size: AppIconSize.sm, color: ink)
                else
                  AppAvatar(name: label, size: AppSpace.lg),
                const SizedBox(width: AppSpace.xs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: AppSpace.xxxl * 3),
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppType.label(context).copyWith(color: ink, fontWeight: on ? FontWeight.w600 : FontWeight.w500)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  One child, one period — the full report
// ═════════════════════════════════════════════════════════════════════════════
class _ChildReportCard extends StatelessWidget {
  const _ChildReportCard({this.childId, required this.name, required this.report, required this.period, this.profile});

  /// The child (null from an older server): a course row opens that course in the child's context.
  final int? childId;
  final String name;
  final Map<String, dynamic> report;
  final String period;

  /// The child's analytics profile (published marks + class averages) — null when not available.
  final DlProfile? profile;

  Map get _s => report['summary'] as Map;
  Map get _prev => report['previous_summary'] as Map;
  Map get _score => report['score'] as Map;
  Map get _att => report['attendance'] as Map;
  Map get _hw => report['homework'] as Map;
  Map get _beh => report['behavior'] as Map;
  Map get _trend => report['trend'] as Map;

  num _n(Map m, String k) => (m[k] as num?) ?? 0;

  String _pct(dynamic v) => v == null ? '—' : '${(v as num).round()}%';

  String _insight(Map i) {
    final params = Map<String, dynamic>.from(i['params'] as Map);
    if (params.containsKey('slot')) params['slot'] = 'pl_slot_${params['slot']}'.tr;
    return plFmt('pl_ins_${i['code']}', params);
  }

  static const double _ring = AppSpace.xxxl + AppSpace.xl;
  static const double _avatar = AppTouch.min - AppSpace.xxs;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tier = '${_score['tier']}';
    final tierColor = plTierColor(context, tier);
    final insights = plList(report['insights']);
    final courses = plList(report['courses']);
    final exams = plList(report['exams']);
    final log = plList(report['attendance_log']);
    final assignments = plList(report['assignments']);
    final range = period == 'daily' ? '${report['start']}' : '${report['start']}  –  ${report['end']}';
    final days = (report['days'] as List).length;

    // ── plain-language deltas ───────────────────────────────────────────────
    final prevStudy = _n(_prev, 'study_minutes');
    final studyDelta = prevStudy > 0 ? (_n(_s, 'study_minutes') - prevStudy) / prevStudy * 100 : null;
    final examNow = _s['exams_avg_percentage'] as num?, examOld = _prev['exams_avg_percentage'] as num?;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── HERO: the child's block, the score ring its one key figure ──────────
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: AppTilt.subtle(
          radius: AppRadius.block,
          child: AppBlock(
            tone: childId == null ? AppBlockTone.peach : parentChildTone(childId!),
            hero: true,
            child: Builder(builder: (context) {
              final ink = AppBlock.colorsOf(context);
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  AppAvatar(name: name, url: profile?.imageUrl, size: _avatar),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Semantics(
                        header: true,
                        child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.headline(context).copyWith(color: ink.ink)),
                      ),
                      Text(range, textDirection: TextDirection.ltr, style: AppType.meta(context).copyWith(color: ink.muted)),
                    ]),
                  ),
                ]),
                const SizedBox(height: AppSpace.lg),
                Row(children: [
                  PlScoreRing(value: _n(_score, 'value'), color: tierColor, size: _ring, light: true, memoryKey: 'parent.report.score.$childId.$period'),
                  const SizedBox(width: AppSpace.lg),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('pl_tier_$tier'.tr, style: AppType.section(context).copyWith(color: ink.accentInk(tierColor))),
                      const SizedBox(height: AppSpace.xxs),
                      Text('pl_tier_desc_$tier'.tr, style: AppType.body(context).copyWith(color: ink.ink, height: 1.5)),
                    ]),
                  ),
                ]),
                const SizedBox(height: AppSpace.xs),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: AppButton.ghost(
                    icon: Icons.help_outline_rounded,
                    label: 'pl_score_how'.tr,
                    size: AppButtonSize.sm,
                    onPressed: () => _scoreSheet(context),
                  ),
                ),
              ]);
            }),
          ),
        ),
      ),

      // ── WHAT STANDS OUT ─────────────────────────────────────────────────────
      if (insights.isNotEmpty)
        PlSection(
          icon: Icons.lightbulb_outline_rounded,
          title: 'pl_sec_insights'.tr,
          hint: 'pl_sec_insights_hint'.tr,
          child: Column(children: [for (final i in insights) PlInsightTile(level: '${i['level']}', text: _insight(i))]),
        ),

      // ── MARKS FROM THE TEACHERS (same view as the child's analytics profile) ─
      if (profile != null) ParentChildMarksSection(profile: profile!),

      // ── KEY NUMBERS ─────────────────────────────────────────────────────────
      AppKpiGrid(children: [
        PlKpi(
          icon: Icons.timer_rounded,
          label: 'pl_k_study'.tr,
          value: plMinutes(_s['study_minutes']),
          sub: 'pl_k_study_sub'.tr,
          delta: studyDelta,
          deltaSuffix: '%',
        ),
        PlKpi(
          icon: Icons.event_available_rounded,
          label: 'pl_k_attendance'.tr,
          value: _pct(_att['rate']),
          sub: _att['scheduled'] == 0 ? 'pl_att_none_short'.tr : plFmt('pl_k_attendance_sub', {'a': _att['attended'], 'b': _att['scheduled']}),
          color: _att['rate'] == null ? c.textLight : plPctColor(context, _att['rate'] as num),
        ),
        PlKpi(
          icon: Icons.local_fire_department_rounded,
          label: 'pl_k_active_days'.tr,
          value: '${_s['active_days']}/$days',
          sub: plFmt('pl_k_streak_sub', {'n': _beh['streak']}),
          // the streak is gold's (system.md §2)
          color: c.accent2,
          delta: _n(_s, 'active_days') - _n(_prev, 'active_days'),
        ),
        PlKpi(
          icon: Icons.quiz_rounded,
          label: 'pl_k_exams'.tr,
          value: _pct(examNow),
          sub: _n(_s, 'exams_taken') == 0 ? 'pl_k_exams_none'.tr : plFmt('pl_k_exams_sub', {'a': _s['exams_taken'], 'b': _s['exams_passed']}),
          color: examNow == null ? c.textLight : plPctColor(context, examNow),
          delta: (examNow != null && examOld != null) ? examNow - examOld : null,
          deltaSuffix: '%',
        ),
        PlKpi(
          icon: Icons.assignment_turned_in_rounded,
          label: 'pl_k_homework'.tr,
          value: _n(_hw, 'due') > 0 ? '${_hw['on_time']}/${_hw['due']}' : '${_s['assignments_submitted']}',
          sub: _n(_hw, 'due') > 0 ? 'pl_k_homework_sub'.tr : 'pl_k_homework_sent'.tr,
          color: _n(_hw, 'due') > 0 ? plPctColor(context, _n(_hw, 'on_time') / _n(_hw, 'due') * 100) : c.primary,
        ),
        PlKpi(
          icon: Icons.task_alt_rounded,
          label: 'pl_k_content'.tr,
          value: '${_n(_s, 'materials_completed') + _n(_s, 'videos_completed')}',
          sub: 'pl_k_content_sub'.tr,
          color: c.success,
          delta: _n(_s, 'materials_completed') + _n(_s, 'videos_completed') - _n(_prev, 'materials_completed') - _n(_prev, 'videos_completed'),
        ),
        if (_n(_s, 'weak_questions_open') > 0)
          PlKpi(
            icon: Icons.bookmark_rounded,
            label: 'pl_k_weak'.tr,
            value: '${_s['weak_questions_open']}',
            sub: 'pl_k_weak_sub'.tr,
            color: c.warning,
            higherIsBetter: false,
          ),
        if (_n(_s, 'certificates_earned') > 0)
          PlKpi(
            icon: Icons.workspace_premium_rounded,
            label: 'pl_k_certs'.tr,
            value: '${_s['certificates_earned']}',
            sub: 'pl_k_certs_sub'.tr,
            // an achievement: gold
            color: c.accent2,
          ),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.xxs, AppSpace.xs, AppSpace.xxs, AppSpace.md),
        child: Text('pl_vs_previous'.tr, style: AppType.meta(context).copyWith(color: c.textLight)),
      ),

      // ── TREND ───────────────────────────────────────────────────────────────
      PlSection(
        icon: Icons.show_chart_rounded,
        title: 'pl_sec_trend'.tr,
        hint: 'pl_sec_trend_hint_${_trend['unit']}'.tr,
        child: PlTrendChart(unit: '${_trend['unit']}', points: plList(_trend['points'])),
      ),

      // ── ATTENDANCE & PUNCTUALITY ────────────────────────────────────────────
      PlSection(
        icon: Icons.how_to_reg_rounded,
        title: 'pl_sec_attendance'.tr,
        hint: 'pl_sec_attendance_hint'.tr,
        child: _attendance(context),
      ),

      // ── HOMEWORK ────────────────────────────────────────────────────────────
      if (_n(_hw, 'due') > 0)
        PlSection(
          icon: Icons.assignment_outlined,
          title: 'pl_sec_homework'.tr,
          hint: 'pl_sec_homework_hint'.tr,
          child: _homework(context),
        ),

      // ── STUDY HABITS ────────────────────────────────────────────────────────
      PlSection(
        icon: Icons.psychology_outlined,
        title: 'pl_sec_habits'.tr,
        hint: 'pl_sec_habits_hint'.tr,
        child: _habits(context),
      ),

      // ── COURSES ─────────────────────────────────────────────────────────────
      if (courses.isNotEmpty)
        PlSection(
          icon: Icons.menu_book_outlined,
          title: 'pl_sec_courses'.tr,
          hint: 'pl_sec_courses_hint'.tr,
          child: Column(children: [
            for (var i = 0; i < courses.length; i++) ...[
              if (i > 0) _rule(context),
              _courseRow(context, courses[i]),
            ],
          ]),
        ),

      // ── DETAIL LISTS ────────────────────────────────────────────────────────
      if (exams.isNotEmpty)
        PlSection(
          icon: Icons.quiz_outlined,
          title: 'pl_exams_list'.tr,
          child: Column(children: [
            for (var i = 0; i < exams.length; i++) ...[
              if (i > 0) _rule(context),
              _childCourseLink(context, exams[i], 'exam', _examRow(context, exams[i])),
            ],
          ]),
        ),
      if (log.isNotEmpty)
        PlSection(
          icon: Icons.event_available_outlined,
          title: 'pl_attendance_list'.tr,
          child: Column(children: [
            for (var i = 0; i < log.length; i++) ...[
              if (i > 0) _rule(context),
              _childCourseLink(context, log[i], 'session', _detailRow(
                context,
                icon: Icons.videocam_rounded,
                tone: c.primary,
                title: '${log[i]['session']}',
                sub: '${plLabel(log[i], 'course')} · ${plDateTime(log[i]['at'])}',
                trailing: plMinutes(log[i]['minutes']),
              )),
            ],
          ]),
        ),
      if (assignments.isNotEmpty)
        PlSection(
          icon: Icons.assignment_outlined,
          title: 'pl_assignments_list'.tr,
          child: Column(children: [
            for (var i = 0; i < assignments.length; i++) ...[
              if (i > 0) _rule(context),
              _detailRow(
                context,
                icon: Icons.assignment_turned_in_rounded,
                tone: c.primary,
                title: '${assignments[i]['title']}',
                sub: plDateTime(assignments[i]['at']),
                trailing: assignments[i]['marks'] == null ? '—' : '${assignments[i]['marks']}/${assignments[i]['total'] ?? '—'}',
              ),
            ],
          ]),
        ),
      const SizedBox(height: AppSpace.xs),
    ]);
  }

  // ── pieces ────────────────────────────────────────────────────────────────

  Widget _rule(BuildContext context) => Divider(height: AppSpace.md, thickness: AppBorder.hairline, color: context.colors.divider);

  /// One line of a detail list: a tone well · title / meta · the figure at the end.
  Widget _detailRow(BuildContext context,
      {required IconData icon, required Color tone, required String title, required String sub, required String trailing, Color? trailingTone}) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.min),
      child: Row(children: [
        PlToneWell(icon: icon, tone: tone),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ]),
        ),
        const SizedBox(width: AppSpace.xs),
        Text(trailing,
            style: AppType.figure(context).copyWith(
                fontSize: AppType.row(context).fontSize,
                color: trailingTone == null ? c.textDark : appInk(context, trailingTone),
                fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }

  Widget _examRow(BuildContext context, Map<String, dynamic> x) {
    final c = context.colors;
    final pct = x['percentage'] as num?;
    final tone = pct == null ? c.textLight : plPctColor(context, pct);
    return _detailRow(
      context,
      icon: x['passed'] == true ? Icons.check_rounded : Icons.close_rounded,
      tone: tone,
      title: '${x['exam']}',
      sub: '${plLabel(x, 'course')} · ${plDateTime(x['at'])}',
      trailing: pct == null ? '—' : '${pct.round()}%',
      trailingTone: pct == null ? null : tone,
    );
  }

  /// On time · late · missing as the kit's donut (the share of each), the on-time count in its centre.
  Widget _homework(BuildContext context) {
    final c = context.colors;
    final donut = AppDonut(
      size: AppSpace.xxxl * 2,
      thickness: AppSpace.sm,
      title: 'pl_sec_homework'.tr,
      center: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${_hw['on_time']}/${_hw['due']}', textDirection: TextDirection.ltr, style: AppType.figure(context)),
        Text('pl_hw_on_time'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
      ]),
      parts: [
        AppChartPart('pl_hw_on_time'.tr, _n(_hw, 'on_time').toDouble(), color: c.success),
        AppChartPart('pl_hw_late'.tr, _n(_hw, 'late').toDouble(), color: c.warning),
        AppChartPart('pl_hw_missing'.tr, _n(_hw, 'missing').toDouble(), color: c.danger),
      ],
    );
    return Center(child: donut);
  }

  Widget _line(BuildContext context, IconData icon, Color col, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: AppIconSize.sm + AppBorder.focus, color: appInk(context, col)),
      const SizedBox(width: AppSpace.xs),
      Expanded(child: Text(text, style: AppType.row(context).copyWith(fontWeight: FontWeight.w400, height: 1.4))),
    ]),
  );

  Widget _subhead(BuildContext context, String text) =>
      Text(text, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark));

  Widget _attendance(BuildContext context) {
    final c = context.colors;
    final scheduled = _n(_att, 'scheduled').toInt();
    final missed = plList(_att['missed']);
    if (scheduled == 0 && _n(_s, 'sessions_attended') == 0) {
      return Text('pl_att_none'.tr, style: AppType.body(context));
    }
    final rate = _att['rate'] as num?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (rate != null) ...[
        Row(children: [
          Text('${rate.round()}%', style: AppType.figureLarge(context).copyWith(color: appInk(context, plPctColor(context, rate)))),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: AppProgressBar(value: rate.toDouble(), height: AppSpace.xs + AppBorder.focus, color: plPctColor(context, rate))),
        ]),
        const SizedBox(height: AppSpace.xs),
        _line(context, Icons.check_circle_rounded, c.success, plFmt('pl_att_attended', {'a': _att['attended'], 'b': scheduled})),
      ],
      if (_n(_att, 'late_count') > 0)
        _line(context, Icons.schedule_rounded, c.warning, plFmt('pl_att_late', {'n': _att['late_count'], 'm': _att['avg_late_minutes']}))
      else if (_n(_s, 'sessions_attended') > 0)
        _line(context, Icons.alarm_on_rounded, c.success, 'pl_att_on_time'.tr),
      if (_n(_att, 'short_stays') > 0)
        _line(context, Icons.directions_run_rounded, c.warning, plFmt('pl_att_short', {'n': _att['short_stays']})),
      if (_att['avg_presence_percentage'] != null)
        _line(context, Icons.hourglass_bottom_rounded, c.primary, plFmt('pl_att_presence', {'p': (_att['avg_presence_percentage'] as num).round()})),
      if (missed.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        _subhead(context, 'pl_att_missed_title'.tr),
        const SizedBox(height: AppSpace.xxs),
        for (final m in missed)
          _line(context, Icons.event_busy_rounded, c.danger, '${m['session']} · ${plLabel(m, 'course')} · ${plDateTime(m['at'])}'),
      ],
    ]);
  }

  Widget _habits(BuildContext context) {
    final c = context.colors;
    final slots = Map<String, dynamic>.from(_beh['time_of_day'] as Map);
    final maxV = slots.values.fold<int>(0, (a, b) => (b as int) > a ? b : a);
    final peak = _beh['peak_slot'] as String?;
    const icons = {
      'morning': Icons.wb_twilight_rounded,
      'afternoon': Icons.wb_sunny_rounded,
      'evening': Icons.wb_cloudy_rounded,
      'night': Icons.nightlight_round,
    };
    final since = _beh['days_since_last_activity'] as int?;
    final counts = (_beh['weekday'] as List).map((e) => e as int).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (maxV == 0)
        Text('pl_no_activity'.tr, style: AppType.body(context))
      else ...[
        _subhead(context, 'pl_habits_time'.tr),
        const SizedBox(height: AppSpace.xxs),
        for (final k in const ['morning', 'afternoon', 'evening', 'night'])
          PlBarRow(
            icon: icons[k]!,
            label: 'pl_slot_$k'.tr,
            fraction: maxV == 0 ? 0 : (slots[k] as int) / maxV,
            value: '${slots[k]}',
            highlight: k == peak,
          ),
        if (period != 'daily') ...[
          const SizedBox(height: AppSpace.md),
          _subhead(context, 'pl_habits_days'.tr),
          const SizedBox(height: AppSpace.xs),
          PlWeekdayStrip(counts: counts, weekStart: (_beh['week_start'] as num).toInt()),
        ],
      ],
      const SizedBox(height: AppSpace.md),
      Row(children: [
        // streaks are gold's (system.md §2); the last activity says whether to worry
        Expanded(child: _mini(context, Icons.local_fire_department_rounded, '${_beh['streak']}', 'pl_streak_now'.tr, c.accent2)),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: _mini(context, Icons.emoji_events_rounded, '${_beh['longest_streak']}', 'pl_streak_best'.tr, c.accent2)),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: _mini(context, Icons.history_rounded, since == null ? '—' : (since == 0 ? 'pl_today'.tr : '$since'), 'pl_last_active'.tr,
              (since ?? 99) >= 3 ? c.danger : c.success),
        ),
      ]),
    ]);
  }

  Widget _mini(BuildContext context, IconData icon, String v, String label, Color col) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm, horizontal: AppSpace.xs),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Column(children: [
        Icon(icon, color: appInkOn(context, col, c.inputBg), size: AppIconSize.md),
        const SizedBox(height: AppSpace.xxs),
        FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: AppType.figure(context))),
        Text(label, textAlign: TextAlign.center, style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  Widget _courseRow(BuildContext context, Map<String, dynamic> x) =>
      _childCourseLink(context, x, 'course', _courseRowBody(context, x), labelField: 'name');

  /// [row] as a link to its course, opened as the child sees it (an exam / session row of an older server, which
  /// sends no `course_id`, stays plain).
  Widget _childCourseLink(BuildContext context, Map<String, dynamic> x, String keyKind, Widget row,
      {String labelField = 'course'}) {
    final courseId = (x['course_id'] as num?)?.toInt();
    final childId = this.childId;
    if (courseId == null || childId == null) return row;
    final course = EntityRef(EntityKind.course, courseId, label: plLabel(x, labelField));
    final child = EntityRef(EntityKind.student, childId, label: name);
    return EntityLink(
      course,
      key: keyKind == 'course' ? ValueKey('md.parent_report.course.$courseId') : null,
      onOpen: () {
        // the child first, then their course: the course reads as the child sees it, the breadcrumb leads back
        final panel = MasterDetailScope.maybeOf(context)?.controller;
        if (panel == null) {
          EntityNavigator.openFullPage(context, course, from: child);
          return;
        }
        panel
          ..open(child)
          ..push(course);
      },
      child: row,
    );
  }

  static const double _courseRing = AppTouch.primary;

  Widget _courseRowBody(BuildContext context, Map<String, dynamic> x) {
    final c = context.colors;
    final progress = (x['progress'] as num).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
      child: Row(children: [
        PlScoreRing(value: progress, color: plPctColor(context, progress), size: _courseRing),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(plLabel(x, 'name'), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpace.xxs),
            Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs / 2, children: [
              _tag(context, Icons.videocam_rounded, '${x['sessions']}'),
              _tag(context, Icons.timer_rounded, plMinutes(x['minutes'])),
              if (x['exam_avg'] != null) _tag(context, Icons.quiz_rounded, '${(x['exam_avg'] as num).round()}%'),
              if ((x['missed'] as num) > 0) _tag(context, Icons.event_busy_rounded, '${x['missed']}', color: c.danger),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _tag(BuildContext context, IconData i, String t, {Color? color}) {
    final c = context.colors;
    final ink = color == null ? c.textMedium : appInk(context, color);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(i, size: AppIconSize.xs, color: color == null ? c.textLight : ink),
      const SizedBox(width: AppSpace.xxs),
      Text(t, style: AppType.meta(context).copyWith(color: ink)),
    ]);
  }

  void _scoreSheet(BuildContext context) {
    final comps = plList(_score['components']);
    showAppSheet(
      context,
      (ctx) => AppSheetContent(title: 'pl_score_how'.tr, children: [
            Text('pl_score_explain'.tr, style: AppType.body(ctx).copyWith(height: 1.5)),
            const SizedBox(height: AppSpace.sm),
            for (final k in comps)
              PlBarRow(
                icon: Icons.analytics_rounded,
                label: 'pl_comp_${k['key']}'.tr,
                fraction: (k['value'] as num) / 100,
                value: '${(k['value'] as num).round()}%',
                color: plPctColor(ctx, k['value'] as num),
                highlight: true,
              ),
            const SizedBox(height: AppSpace.sm),
            for (final k in comps)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs / 2),
                child: Text('${'pl_comp_${k['key']}'.tr} (${k['weight']}%): ${'pl_comp_desc_${k['key']}'.tr}',
                    style: AppType.meta(ctx).copyWith(color: ctx.colors.textDark, height: 1.4)),
              ),
            const SizedBox(height: AppSpace.xs),
            Text('pl_score_note'.tr, style: AppType.meta(ctx).copyWith(color: ctx.colors.textLight)),
          ]),
    );
  }
}
