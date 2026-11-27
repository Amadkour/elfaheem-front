// lib/features/parent/parent_reports_page.dart
// Daily / weekly / monthly reports, redrawn for the redesign (Pa2Reports `screen=reports|child|how`, phase 4).
//   ParentReportsPage          -> the "Reports" tab: one summary card per child (the score ring, the tier, one sentence,
//                                 attendance / exams / homework with the change, two findings, Full report); the top
//                                 bar's switcher narrows it to one child
//   ParentChildReportScreen    -> one child: the hero carries the score ring, the tier, the sentence, "How is the score
//                                 made?" (a sheet: the four parts, their weights and values) and what changed; then the
//                                 findings, the teachers' marks, the figures, the trend, attendance, homework, habits,
//                                 courses and the detail lists
// The server returns the three periods of every child in ONE call (period=all), so switching between Daily / Weekly /
// Monthly is instant. Day / week boundaries are computed by the server.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_models.dart' show DlProfile;
import 'pa_kit.dart';
import 'parent_child_marks.dart';
import 'parent_link_providers.dart';
import 'parent_report_widgets.dart';
import 'parent_widgets.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart' show EntityLink;
import 'package:flutter_education_app/design/master_detail/entity_navigator.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppOdometer;

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

num _n(Map m, String k) => (m[k] as num?) ?? 0;

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
  Widget build(BuildContext context) => paRole(BasePage(
        appBar: ScreenAppBar(title: 'pa_report_of'.tr.replaceAll('{name}', studentName.split(' ').first)),
        child: Column(children: [
          PaSwitcherBand(
            showAll: false,
            selectedId: studentId,
            onSelect: (id) {
              if (id == null || id == studentId) return;
              final kid = PaKids.maybeOf(context, listen: false)?.kids.where((k) => k.id == id).firstOrNull;
              Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                builder: (_) => ParentChildReportScreen(studentId: id, studentName: kid?.name ?? ''),
              ));
            },
          ),
          Expanded(child: _ReportsBody(studentId: studentId, studentName: studentName)),
        ]),
      ));
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
  String _period = 'weekly';

  @override
  void initState() {
    super.initState();
    widget.studentId == null ? _p.load() : _p.loadOne(widget.studentId!, widget.studentName);
  }

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  /// Daily / weekly / monthly and the date, on the hero.
  Widget _controls(BuildContext context, ParentReportsProvider p) {
    final c = context.colors;
    final next = _step(p.refDate, _period, 1);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppTabs(
        expand: true,
        items: [for (final x in _periods) AppTabItem('pl_period_$x'.tr)],
        index: _periods.indexOf(_period),
        onChanged: (i) => setState(() => _period = _periods[i]),
      ),
      const SizedBox(height: AppSpace.xs),
      Container(
        decoration: BoxDecoration(
          color: c.heroGlass,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
        ),
        child: Row(children: [
          AppIconButton(
            icon: Icons.chevron_left_rounded,
            onHero: true,
            tooltip: MaterialLocalizations.of(context).previousPageTooltip,
            onPressed: () => p.setDate(_step(p.refDate, _period, -1)),
          ),
          Expanded(
            child: Semantics(
              button: true,
              label: 'pa_pick_date'.tr,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: p.refDate, firstDate: DateTime(2020), lastDate: DateTime.now());
                  if (d != null) p.setDate(d);
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppTouch.min),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.calendar_month_rounded, size: AppIconSize.md, color: c.onHero),
                    const SizedBox(width: AppSpace.xs),
                    Flexible(
                      child: Text(plDate(p.refDate), maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: AppType.row(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          AppIconButton(
            icon: Icons.chevron_right_rounded,
            onHero: true,
            tooltip: MaterialLocalizations.of(context).nextPageTooltip,
            onPressed: next.isAfter(DateTime.now()) ? null : () => p.setDate(next),
          ),
        ]),
      ),
      const SizedBox(height: AppSpace.xs),
      Text(paFmt('pa_tz_note', {'tz': AppTime.zoneInfo(AppTime.zoneId).label}), style: AppType.meta(context).copyWith(color: c.onHeroMuted)),
    ]);
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
        value: _p,
        child: Consumer<ParentReportsProvider>(builder: (context, p, _) {
          final kids = PaKids.maybeOf(context);
          final rows = [
            for (final ch in p.children)
              if (ch[_period] is Map && (widget.studentId != null || kids?.selected == null || (ch['student'] as Map?)?['id'] == kids?.selected)) ch,
          ];
          Widget state() => !p.loaded && p.isLoading
              ? const AppListSkeleton(items: 3, padding: EdgeInsets.zero)
              : !p.loaded && p.hasError
                  ? ErrorRetry(message: p.errorMessage ?? '', onRetry: p.reload)
                  : AppEmpty(icon: Icons.family_restroom_rounded, title: 'pl_no_children'.tr);

          // one child: the hero is that child's score
          if (widget.studentId != null) {
            final ch = rows.isEmpty ? null : rows.first;
            final report = ch == null ? null : Map<String, dynamic>.from(ch[_period] as Map);
            final hero = report == null
                ? AppHero(title: widget.studentName, bottom: _controls(context, p))
                : _ChildHero(
                    childId: widget.studentId!,
                    name: '${(ch!['student'] as Map)['name']}',
                    report: report,
                    controls: _controls(context, p),
                  );
            return PaHeroPage(
              onRefresh: p.reload,
              width: AppWidth.reading,
              hero: hero,
              body: report == null
                  ? state()
                  : _ChildReportCard(
                      childId: widget.studentId,
                      name: '${(ch!['student'] as Map)['name']}',
                      report: report,
                      period: _period,
                      profile: p.profiles[widget.studentId],
                    ),
            );
          }

          final hero = AppHero(
            kicker: 'pa_reports_kicker'.tr,
            title: 'pa_reports_title_$_period'.tr,
            subtitle: 'pa_reports_sub'.tr,
            bottom: _controls(context, p),
          );
          return PaHeroPage(
            onRefresh: p.reload,
            width: AppWidth.reading,
            hero: hero,
            body: rows.isEmpty
                ? state()
                : PaStack(children: [
                    for (final ch in rows)
                      _ChildSummaryCard(
                        childId: ((ch['student'] as Map?)?['id'] as num?)?.toInt(),
                        name: '${(ch['student'] as Map)['name']}',
                        grade: '${(ch['student'] as Map)['grade_name'] ?? ''}',
                        report: Map<String, dynamic>.from(ch[_period] as Map),
                      ),
                  ]),
          );
        }),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  The child's hero: the score ring, the tier, the sentence, how it is made, what changed
// ═════════════════════════════════════════════════════════════════════════════
class _ChildHero extends StatelessWidget {
  const _ChildHero({required this.childId, required this.name, required this.report, required this.controls});

  final int childId;
  final String name;
  final Map<String, dynamic> report;
  final Widget controls;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final score = report['score'] as Map;
    final tier = '${score['tier']}';
    final s = report['summary'] as Map, prev = report['previous_summary'] as Map;
    final hw = report['homework'] as Map;
    final wide = paWide(context);
    final changes = <(bool, String)>[
      if (prev.containsKey('score') && (_n(prev, 'score') != _n(score, 'value')))
        (_n(score, 'value') >= _n(prev, 'score'), paFmt('pa_score_change', {'n': appDigits('${(_n(score, 'value') - _n(prev, 'score')).abs().round()}')})),
      if (_n(prev, 'study_minutes') > 0 && _n(s, 'study_minutes') != _n(prev, 'study_minutes'))
        (_n(s, 'study_minutes') > _n(prev, 'study_minutes'),
            paFmt(_n(s, 'study_minutes') > _n(prev, 'study_minutes') ? 'pa_study_up' : 'pa_study_down',
                {'n': plMinutes((_n(s, 'study_minutes') - _n(prev, 'study_minutes')).abs())})),
      if (_n(hw, 'missing') > 0) (false, paFmt('pa_hw_missing_n', {'n': appDigits('${_n(hw, 'missing')}')})),
    ];
    final ring = PaScoreRing(value: _n(score, 'value'), size: wide ? AppDashSize.ring * 2 : AppDashSize.ring * 1.4);
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        PaKidAvatar(id: childId, name: name, size: AppTouch.min - AppSpace.xs),
        const SizedBox(width: AppSpace.xs),
        Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: c.onHero))),
      ]),
      const SizedBox(height: AppSpace.xs),
      Semantics(header: true, child: Text('pl_tier_$tier'.tr, style: AppType.headline(context).copyWith(color: c.onHero))),
      const SizedBox(height: AppSpace.xxs),
      Text('pl_tier_desc_$tier'.tr, style: AppType.body(context).copyWith(color: c.onHeroMuted)),
      const SizedBox(height: AppSpace.sm),
      AppButton.secondary(
        key: const ValueKey('pa.report.how'),
        label: 'pa_score_how'.tr,
        icon: Icons.help_outline_rounded,
        size: AppButtonSize.sm,
        onPressed: () => showParentScoreSheet(context, score),
      ),
    ]);
    return AppHeroSurface(
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
            wide ? AppSpace.lg : AppSpace.md, wide ? AppSpace.lg : AppSpace.md, wide ? AppSpace.lg : AppSpace.md, AppHeroMetrics.overlapPhone + AppSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: text),
            const SizedBox(width: AppSpace.sm),
            ring,
          ]),
          if (changes.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            for (final ch in changes)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                  decoration: BoxDecoration(color: c.heroGlass, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Row(children: [
                    Icon(ch.$1 ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: ch.$1 ? c.kit.ok.color : c.kit.hotTone.color, size: AppIconSize.md),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(child: Text(ch.$2, style: AppType.row(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600))),
                  ]),
                ),
              ),
          ],
          const SizedBox(height: AppSpace.sm),
          controls,
        ]),
      ),
    );
  }
}

/// The score as a white ring on the hero: the figure and "of 100" in its middle.
class PaScoreRing extends StatelessWidget {
  const PaScoreRing({super.key, required this.value, required this.size});

  final num value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: paFmt('pa_score_of', {'n': appDigits('${value.round()}')}),
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.square(
              dimension: size,
              child: CircularProgressIndicator(
                value: (value / 100).clamp(0, 1).toDouble(),
                strokeWidth: size * .1,
                color: c.onHero,
                backgroundColor: c.heroGlass,
                strokeCap: StrokeCap.round,
              ),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              FittedBox(
                child: AppOdometer(
                  appDigits('${value.round()}'),
                  style: AppType.figureLarge(context).copyWith(color: c.onHero, fontSize: size * .3, height: 1),
                ),
              ),
              Text('pa_of_100'.tr, style: AppType.meta(context).copyWith(color: c.onHeroMuted)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// "How is the score made?" (Pa2Reports `screen=how`): the four parts, their weights and this period's values.
Future<void> showParentScoreSheet(BuildContext context, Map score) =>
    showAppSheet<void>(context, (_) => PaScoreSheet(score: score));

/// The sheet's content (a widget of its own so the review renders can draw it).
class PaScoreSheet extends StatelessWidget {
  const PaScoreSheet({super.key, required this.score});
  final Map score;

  @override
  Widget build(BuildContext ctx) {
    final comps = plList(score['components']);
    final kit = ctx.colors.kit;
    final tones = {
      'attendance': (Icons.schedule_rounded, kit.primaryTone),
      'consistency': (Icons.check_rounded, kit.ok),
      'performance': (Icons.star_outline_rounded, kit.warn),
      'homework': (Icons.description_outlined, kit.hotTone),
    };
    return paRole(AppSheetContent(
      title: 'pa_score_how'.tr,
      icon: Icons.help_outline_rounded,
      children: [
        Text('pa_score_explain'.tr, style: AppType.body(ctx)),
        const SizedBox(height: AppSpace.md),
        for (final k in comps) ...[
          AppCard(
            variant: AppCardVariant.flat,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                AppIconBox(icon: (tones['${k['key']}'] ?? (Icons.analytics_rounded, kit.primaryTone)).$1, tone: (tones['${k['key']}'] ?? (Icons.analytics_rounded, kit.primaryTone)).$2),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('pl_comp_${k['key']}'.tr, style: AppType.tileTitle(ctx)),
                    Text('pl_comp_desc_${k['key']}'.tr, style: AppType.meta(ctx)),
                  ]),
                ),
                const SizedBox(width: AppSpace.xs),
                AppStatusBadge(label: paFmt('pa_weight', {'n': appDigits('${k['weight']}%')})),
              ]),
              const SizedBox(height: AppSpace.sm),
              Row(children: [
                Expanded(
                  child: AppProgressBar(
                    value: ((k['value'] as num?) ?? 0).toDouble(),
                    color: (tones['${k['key']}'] ?? (Icons.analytics_rounded, kit.primaryTone)).$2.color,
                  ),
                ),
                const SizedBox(width: AppSpace.xs),
                Text(appDigits('${((k['value'] as num?) ?? 0).round()}%'), style: AppType.label(ctx).copyWith(fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        PaNote(icon: Icons.shield_outlined, text: 'pl_score_note'.tr),
        const SizedBox(height: AppSpace.md),
        AppButton.primary(label: 'pa_got_it'.tr, expand: true, onPressed: () => Navigator.of(ctx).pop()),
      ],
    ));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  One child's summary on the Reports tab
// ═════════════════════════════════════════════════════════════════════════════
class _ChildSummaryCard extends StatelessWidget {
  const _ChildSummaryCard({required this.childId, required this.name, required this.grade, required this.report});

  final int? childId;
  final String name, grade;
  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    final score = report['score'] as Map;
    final tier = '${score['tier']}';
    final s = report['summary'] as Map, prev = report['previous_summary'] as Map;
    final att = report['attendance'] as Map, hw = report['homework'] as Map;
    final insights = plList(report['insights']).take(2).toList();
    final tierTone = switch (tier) { 'excellent' || 'good' => AppTone.success, 'fair' => AppTone.warning, _ => AppTone.danger };
    final kit = context.colors.kit;
    final ringTone = switch (tier) { 'excellent' || 'good' => kit.ok, 'fair' => kit.warn, _ => kit.live };
    final examNow = s['exams_avg_percentage'] as num?, examOld = prev['exams_avg_percentage'] as num?;
    String? delta(num? now, num? old) {
      if (now == null || old == null || now == old) return null;
      return appDigits('${now > old ? '▲' : '▼'} ${(now - old).abs().round()}%');
    }

    Widget fig(String label, String value, String? change) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(
              color: kit.well,
              borderRadius: BorderRadius.circular(AppRadius.tile),
              border: Border.all(color: kit.line, width: AppBorder.strong),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              Text(value, maxLines: 1, style: AppType.statFigure(context, wide: false)),
              if (change != null) Text(change, style: AppType.meta(context).copyWith(color: change.startsWith('▲') ? kit.ok.ink : kit.error.ink)),
            ]),
          ),
        );
    final id = childId;
    return AppCard(
      variant: AppCardVariant.tint,
      tone: id == null ? null : paKidTone(context, id),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppProgressRing(
            value: _n(score, 'value') / 100,
            size: AppDashSize.ring,
            tone: ringTone,
            label: appDigits('${_n(score, 'value').round()}'),
            semanticLabel: paFmt('pa_score_of', {'n': appDigits('${_n(score, 'value').round()}')}),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(name, style: AppType.section(context)),
                AppStatusBadge(label: 'pl_tier_$tier'.tr, tone: tierTone),
              ]),
              if (grade.isNotEmpty) Text(grade, style: AppType.meta(context)),
              const SizedBox(height: AppSpace.xxs),
              Text('pl_tier_desc_$tier'.tr, style: AppType.body(context)),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.md),
        Row(children: [
          fig('pa_attendance'.tr, att['rate'] == null ? '—' : appDigits('${(att['rate'] as num).round()}%'), null),
          const SizedBox(width: AppSpace.xs),
          fig('pa_exams'.tr, examNow == null ? '—' : appDigits('${examNow.round()}%'), delta(examNow, examOld)),
          const SizedBox(width: AppSpace.xs),
          fig(
            'pa_homework'.tr,
            _n(hw, 'due') > 0 ? paFmt('pa_n_of_m', {'n': appDigits('${_n(hw, 'on_time')}'), 'm': appDigits('${_n(hw, 'due')}')}) : '—',
            _n(hw, 'missing') > 0 ? appDigits('▼ ${_n(hw, 'missing')}') : null,
          ),
        ]),
        if (insights.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          for (final i in insights) PlInsightTile(level: '${i['level']}', text: plInsightText(i)),
        ],
        const SizedBox(height: AppSpace.sm),
        AppButton.primary(
          key: ValueKey('pa.report.full.$id'),
          label: 'pa_full_report'.tr,
          trailingIcon: Icons.chevron_right_rounded,
          expand: true,
          onPressed: id == null
              ? null
              : () => paPush<void>(context, ParentChildReportScreen(studentId: id, studentName: name)),
        ),
      ]),
    );
  }
}

/// A report finding as its sentence.
String plInsightText(Map i) {
  final params = Map<String, dynamic>.from(i['params'] as Map);
  if (params.containsKey('slot')) params['slot'] = 'pl_slot_${params['slot']}'.tr;
  return plFmt('pl_ins_${i['code']}', params);
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
  Map get _att => report['attendance'] as Map;
  Map get _hw => report['homework'] as Map;
  Map get _beh => report['behavior'] as Map;
  Map get _trend => report['trend'] as Map;

  num _n(Map m, String k) => (m[k] as num?) ?? 0;

  String _pct(dynamic v) => v == null ? '—' : '${(v as num).round()}%';


  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final insights = plList(report['insights']);
    final courses = plList(report['courses']);
    final exams = plList(report['exams']);
    final log = plList(report['attendance_log']);
    final assignments = plList(report['assignments']);
    final days = (report['days'] as List).length;

    // ── plain-language deltas ───────────────────────────────────────────────
    final prevStudy = _n(_prev, 'study_minutes');
    final studyDelta = prevStudy > 0 ? (_n(_s, 'study_minutes') - prevStudy) / prevStudy * 100 : null;
    final examNow = _s['exams_avg_percentage'] as num?, examOld = _prev['exams_avg_percentage'] as num?;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── WHAT STANDS OUT ─────────────────────────────────────────────────────
      if (insights.isNotEmpty)
        PlSection(
          icon: Icons.star_outline_rounded,
          title: 'pa_highlights'.tr,
          hint: 'pa_highlights_hint'.tr,
          child: Column(children: [for (final i in insights) PlInsightTile(level: '${i['level']}', text: plInsightText(i))]),
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
      Flexible(child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: ink))),
    ]);
  }
}
