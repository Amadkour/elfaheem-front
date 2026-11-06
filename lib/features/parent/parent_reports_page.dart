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
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../shared/analytics/analytics_ui.dart';
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [for (final x in _periods) ButtonSegment(value: x, label: Text('pl_period_$x'.tr))],
                selected: {_period},
                onSelectionChanged: (s) => setState(() => _period = s.first),
              ),
            ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () => p.setDate(_step(p.refDate, _period, -1))),
              TextButton.icon(
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                label: Text(plDate(p.refDate)),
                onPressed: () async {
                  final d = await showDatePicker(
                      context: context,
                      initialDate: p.refDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now());
                  if (d != null) p.setDate(d);
                },
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: _step(p.refDate, _period, 1).isAfter(DateTime.now())
                    ? null
                    : () => p.setDate(_step(p.refDate, _period, 1)),
              ),
            ]),
          ]),
        ),
        if (widget.studentId == null && p.children.length > 1)
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                for (final ch in p.children)
                  if (ch[_period] is Map && (_only == null || (ch['student'] as Map?)?['id'] == _only))
                    _ChildReportCard(
                      childId: ((ch['student'] as Map?)?['id'] as num?)?.toInt(),
                      name: '${(ch['student'] as Map)['name']}',
                      report: Map<String, dynamic>.from(ch[_period] as Map),
                      period: _period,
                      profile: p.profiles[((ch['student'] as Map?)?['id'] as num?)?.toInt()],
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
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        selected: on,
        showCheckmark: false,
        avatar: id == null ? Icon(Icons.groups_rounded, size: 16, color: on ? Colors.white : c.textMedium) : AnAvatar(name: label, size: 22),
        label: Text(label, style: anText(12.5, w: FontWeight.w700, c: on ? Colors.white : c.textDark)),
        selectedColor: c.primary,
        backgroundColor: c.cardBg,
        side: BorderSide(color: on ? c.primary : c.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onSelected: (_) => setState(() => _only = id),
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
    final range = period == 'daily' ? '${report['start']}' : '${report['start']}  →  ${report['end']}';
    final days = (report['days'] as List).length;

    // ── plain-language deltas ───────────────────────────────────────────────
    final prevStudy = _n(_prev, 'study_minutes');
    final studyDelta = prevStudy > 0 ? (_n(_s, 'study_minutes') - prevStudy) / prevStudy * 100 : null;
    final examNow = _s['exams_avg_percentage'] as num?, examOld = _prev['exams_avg_percentage'] as num?;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── HERO ────────────────────────────────────────────────────────────────
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [tierColor, tierColor.withAlpha(185)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: tierColor.withAlpha(70), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white24),
              child: AnAvatar(name: name, url: profile?.imageUrl, size: 34, color: tierColor, onColor: true),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
          ]),
          Text(range, style: TextStyle(color: context.colors.onHeroMuted, fontSize: 12)),
          const SizedBox(height: 14),
          Row(children: [
            PlScoreRing(value: _n(_score, 'value'), color: Colors.white, size: 96, light: true),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('pl_tier_$tier'.tr, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('pl_tier_desc_$tier'.tr, style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.4)),
              ]),
            ),
          ]),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.help_outline_rounded, size: 16),
              label: Text('pl_score_how'.tr, style: const TextStyle(fontSize: 12)),
              onPressed: () => _scoreSheet(context),
            ),
          ),
        ]),
      ),

      // ── WHAT STANDS OUT ─────────────────────────────────────────────────────
      if (insights.isNotEmpty)
        PlSection(
          icon: Icons.lightbulb_rounded,
          title: 'pl_sec_insights'.tr,
          hint: 'pl_sec_insights_hint'.tr,
          child: Column(children: [for (final i in insights) PlInsightTile(level: '${i['level']}', text: _insight(i))]),
        ),

      // ── MARKS FROM THE TEACHERS (same view as the child's analytics profile) ─
      if (profile != null) ParentChildMarksSection(profile: profile!),

      // ── KEY NUMBERS ─────────────────────────────────────────────────────────
      LayoutBuilder(builder: (context, box) {
        final w = (box.maxWidth - 10) / 2;
        Widget cell(Widget k) => SizedBox(width: w, child: k);
        final kpis = <Widget>[
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
            color: _att['rate'] == null ? context.colors.textLight : plPctColor(context, _att['rate'] as num),
          ),
          PlKpi(
            icon: Icons.local_fire_department_rounded,
            label: 'pl_k_active_days'.tr,
            value: '${_s['active_days']}/$days',
            sub: plFmt('pl_k_streak_sub', {'n': _beh['streak']}),
            color: const Color(0xFFFF7A00),
            delta: _n(_s, 'active_days') - _n(_prev, 'active_days'),
          ),
          PlKpi(
            icon: Icons.quiz_rounded,
            label: 'pl_k_exams'.tr,
            value: _pct(examNow),
            sub: _n(_s, 'exams_taken') == 0 ? 'pl_k_exams_none'.tr : plFmt('pl_k_exams_sub', {'a': _s['exams_taken'], 'b': _s['exams_passed']}),
            color: examNow == null ? context.colors.textLight : plPctColor(context, examNow),
            delta: (examNow != null && examOld != null) ? examNow - examOld : null,
            deltaSuffix: '%',
          ),
          PlKpi(
            icon: Icons.assignment_turned_in_rounded,
            label: 'pl_k_homework'.tr,
            value: _n(_hw, 'due') > 0 ? '${_hw['on_time']}/${_hw['due']}' : '${_s['assignments_submitted']}',
            sub: _n(_hw, 'due') > 0 ? 'pl_k_homework_sub'.tr : 'pl_k_homework_sent'.tr,
            color: _n(_hw, 'due') > 0 ? plPctColor(context, _n(_hw, 'on_time') / _n(_hw, 'due') * 100) : c.accent,
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
              color: const Color(0xFFE0A800),
            ),
        ];
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 10, runSpacing: 10, children: [for (final k in kpis) cell(k)]),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
              child: Text('pl_vs_previous'.tr, style: c.caption.copyWith(fontSize: 11)),
            ),
          ]),
        );
      }),

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
          icon: Icons.assignment_rounded,
          title: 'pl_sec_homework'.tr,
          hint: 'pl_sec_homework_hint'.tr,
          child: Row(children: [
            _pill(context, '${_hw['on_time']}', 'pl_hw_on_time'.tr, c.success),
            const SizedBox(width: 8),
            _pill(context, '${_hw['late']}', 'pl_hw_late'.tr, c.warning),
            const SizedBox(width: 8),
            _pill(context, '${_hw['missing']}', 'pl_hw_missing'.tr, c.danger),
          ]),
        ),

      // ── STUDY HABITS ────────────────────────────────────────────────────────
      PlSection(
        icon: Icons.psychology_rounded,
        title: 'pl_sec_habits'.tr,
        hint: 'pl_sec_habits_hint'.tr,
        child: _habits(context),
      ),

      // ── COURSES ─────────────────────────────────────────────────────────────
      if (courses.isNotEmpty)
        PlSection(
          icon: Icons.menu_book_rounded,
          title: 'pl_sec_courses'.tr,
          hint: 'pl_sec_courses_hint'.tr,
          child: Column(children: [for (final x in courses) _courseRow(context, x)]),
        ),

      // ── DETAIL LISTS ────────────────────────────────────────────────────────
      if (exams.isNotEmpty)
        PlSection(
          icon: Icons.quiz_rounded,
          title: 'pl_exams_list'.tr,
          child: Column(children: [
            for (final x in exams)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: (x['percentage'] == null ? context.colors.textLight : plPctColor(context, x['percentage'] as num)).withAlpha(30),
                  child: Icon(x['passed'] == true ? Icons.check_rounded : Icons.close_rounded,
                      color: x['percentage'] == null ? context.colors.textLight : plPctColor(context, x['percentage'] as num)),
                ),
                title: Text('${x['exam']}'),
                subtitle: Text('${plLabel(x, 'course')} · ${plDateTime(x['at'])}'),
                trailing: Text(x['percentage'] == null ? '—' : '${(x['percentage'] as num).round()}%',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: x['percentage'] == null ? null : plPctColor(context, x['percentage'] as num))),
              ),
          ]),
        ),
      if (log.isNotEmpty)
        PlSection(
          icon: Icons.event_available_rounded,
          title: 'pl_attendance_list'.tr,
          child: Column(children: [
            for (final x in log)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.videocam_rounded, color: c.primary),
                title: Text('${x['session']}'),
                subtitle: Text('${plLabel(x, 'course')} · ${plDateTime(x['at'])}'),
                trailing: Text(plMinutes(x['minutes'])),
              ),
          ]),
        ),
      if (assignments.isNotEmpty)
        PlSection(
          icon: Icons.assignment_rounded,
          title: 'pl_assignments_list'.tr,
          child: Column(children: [
            for (final x in assignments)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.assignment_turned_in_rounded, color: c.primary),
                title: Text('${x['title']}'),
                subtitle: Text(plDateTime(x['at'])),
                trailing: Text(x['marks'] == null ? '—' : '${x['marks']}/${x['total'] ?? '—'}'),
              ),
          ]),
        ),
      const SizedBox(height: 8),
    ]);
  }

  // ── pieces ────────────────────────────────────────────────────────────────

  Widget _pill(BuildContext context, String v, String label, Color col) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: col.withAlpha(24), borderRadius: BorderRadius.circular(14), border: Border.all(color: col.withAlpha(60))),
      child: Column(children: [
        Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: col)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]),
    ),
  );

  Widget _line(BuildContext context, IconData icon, Color col, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: col),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35))),
    ]),
  );

  Widget _attendance(BuildContext context) {
    final c = context.colors;
    final scheduled = _n(_att, 'scheduled').toInt();
    final missed = plList(_att['missed']);
    if (scheduled == 0 && _n(_s, 'sessions_attended') == 0) {
      return Text('pl_att_none'.tr, style: c.caption);
    }
    final rate = _att['rate'] as num?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (rate != null) ...[
        Row(children: [
          Text('${rate.round()}%', style: c.h2.copyWith(fontSize: 26, color: plPctColor(context, rate))),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: (rate / 100).toDouble().clamp(0.0, 1.0), minHeight: 12, color: plPctColor(context, rate), backgroundColor: plPctColor(context, rate).withAlpha(30)),
            ),
          ),
        ]),
        const SizedBox(height: 8),
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
        const SizedBox(height: 6),
        Text('pl_att_missed_title'.tr, style: c.h2.copyWith(fontSize: 13)),
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
        Text('pl_no_activity'.tr, style: c.caption)
      else ...[
        Text('pl_habits_time'.tr, style: c.h2.copyWith(fontSize: 13)),
        const SizedBox(height: 4),
        for (final k in const ['morning', 'afternoon', 'evening', 'night'])
          PlBarRow(
            icon: icons[k]!,
            label: 'pl_slot_$k'.tr,
            fraction: maxV == 0 ? 0 : (slots[k] as int) / maxV,
            value: '${slots[k]}',
            highlight: k == peak,
          ),
        if (period != 'daily') ...[
          const SizedBox(height: 12),
          Text('pl_habits_days'.tr, style: c.h2.copyWith(fontSize: 13)),
          const SizedBox(height: 8),
          PlWeekdayStrip(counts: counts, weekStart: (_beh['week_start'] as num).toInt()),
        ],
      ],
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _mini(context, Icons.local_fire_department_rounded, '${_beh['streak']}', 'pl_streak_now'.tr, const Color(0xFFFF7A00))),
        const SizedBox(width: 8),
        Expanded(child: _mini(context, Icons.emoji_events_rounded, '${_beh['longest_streak']}', 'pl_streak_best'.tr, c.accent)),
        const SizedBox(width: 8),
        Expanded(
          child: _mini(context, Icons.history_rounded, since == null ? '—' : (since == 0 ? 'pl_today'.tr : '$since'), 'pl_last_active'.tr,
              (since ?? 99) >= 3 ? c.danger : c.success),
        ),
      ]),
    ]);
  }

  Widget _mini(BuildContext context, IconData icon, String v, String label, Color col) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
    decoration: BoxDecoration(color: col.withAlpha(22), borderRadius: BorderRadius.circular(14)),
    child: Column(children: [
      Icon(icon, color: col, size: 20),
      const SizedBox(height: 2),
      Text(v, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: col)),
      Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5), maxLines: 2),
    ]),
  );

  Widget _courseRow(BuildContext context, Map<String, dynamic> x) {
    final row = _courseRowBody(context, x);
    final courseId = (x['course_id'] as num?)?.toInt();
    final childId = this.childId;
    if (courseId == null || childId == null) return row;
    final course = EntityRef(EntityKind.course, courseId, label: plLabel(x, 'name'));
    final child = EntityRef(EntityKind.student, childId, label: name);
    return EntityLink(
      course,
      key: ValueKey('md.parent_report.course.$courseId'),
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

  Widget _courseRowBody(BuildContext context, Map<String, dynamic> x) {
    final c = context.colors;
    final progress = (x['progress'] as num).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        PlScoreRing(value: progress, color: plPctColor(context, progress), size: 54),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(plLabel(x, 'name'), style: c.h2.copyWith(fontSize: 14)),
            const SizedBox(height: 4),
            Wrap(spacing: 10, runSpacing: 2, children: [
              _tag(Icons.videocam_rounded, '${x['sessions']}'),
              _tag(Icons.timer_rounded, plMinutes(x['minutes'])),
              if (x['exam_avg'] != null) _tag(Icons.quiz_rounded, '${(x['exam_avg'] as num).round()}%'),
              if ((x['missed'] as num) > 0) _tag(Icons.event_busy_rounded, '${x['missed']}', color: c.danger),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _tag(IconData i, String t, {Color? color}) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(i, size: 14, color: color ?? Colors.grey),
    const SizedBox(width: 3),
    Text(t, style: TextStyle(fontSize: 12, color: color)),
  ]);

  void _scoreSheet(BuildContext context) {
    final comps = plList(_score['components']);
    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('pl_score_how'.tr, style: ctx.colors.h2.copyWith(fontSize: 17)),
            const SizedBox(height: 6),
            Text('pl_score_explain'.tr, style: ctx.colors.caption.copyWith(height: 1.4)),
            const SizedBox(height: 12),
            for (final k in comps)
              PlBarRow(
                icon: Icons.analytics_rounded,
                label: 'pl_comp_${k['key']}'.tr,
                fraction: (k['value'] as num) / 100,
                value: '${(k['value'] as num).round()}%',
                color: plPctColor(ctx, k['value'] as num),
                highlight: true,
              ),
            const SizedBox(height: 6),
            for (final k in comps)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• ${'pl_comp_${k['key']}'.tr} (${k['weight']}%): ${'pl_comp_desc_${k['key']}'.tr}', style: const TextStyle(fontSize: 12, height: 1.35)),
              ),
            const SizedBox(height: 8),
            Text('pl_score_note'.tr, style: ctx.colors.caption.copyWith(fontSize: 11)),
          ]),
        ),
      ),
    );
  }
}