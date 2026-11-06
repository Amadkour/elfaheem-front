// lib/features/org/advising/adv_analytics_parts.dart — the presentational pieces of the advising analytics (Phase 8,
// docs/advising/PHASE8.md). Every widget takes plain values (test/ui/adv_analytics_layout_test.dart); charts come
// from lib/design/app_charts.dart only; a figure the server hides (fewer than 5 students) is written as such, never 0.
//
//   AdvAnCard            one dashboard card: icon, title, subtitle, body
//   AdvBreakdownList     the tappable rows under a chart (label · figure · chevron) → the drill-down
//   AdvKpiRow            the eight KPIs with their previous-range deltas and sparklines
//   AdvLoadCard          advisors' load: distribution chart, the most loaded
//   AdvStrugglingCard    risk bands, students by their highest open alert, open alerts by category
//   AdvRiskTrendCard     alerts opened / resolved per bucket and the at-risk line
//   AdvGpaCard           the CGPA bands with the probation line, the term GPA trend
//   AdvMeetingsCard      meetings by status, completion / no-show rates, modes
//   AdvResponseCard      reply times and complaints
//   AdvRequestsCard      the support-request pipeline and the approval rate
//   AdvActivityCard      active / inactive advisors and what they did
//   AdvOutcomesCard      student success outcomes of a term (supported vs not)
//   AdvSatisfactionCard  meeting survey average (hidden under 5 answers)
//   AdvHealthCard        the daily data check: issues worst first, each with its way out
//   AdvComplianceTable   the per-advisor compliance report (cards on phones, a table on wide screens)
//   AdvAdvisorStatRow    one advisor's figures (a card)
//   AdvOutreachCard      one sent group message with its delivery and read figures
//   AdvFilterSummary     the chips that say what the figures cover
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import 'adv_analytics_models.dart';
import 'adv_case_parts.dart' show AdvMiniStat, AdvTypedText, advPriorityColor;
import 'adv_models.dart' show AdvRef, advPriorities, advPriorityLabel, advStatusLabel;
import 'adv_parts.dart' show AdvLoadBar, AdvStatusPill, advDate, advTextDirection;

// ═════════════════════════════════════════════════════════════════════════════
//  Words and colours
// ═════════════════════════════════════════════════════════════════════════════

/// What a hidden count reads as.
String advFewerText() => t('أقل من 5', 'Fewer than 5');

/// A count as shown: the number, or "Fewer than 5".
String advCountText(int? v) => v == null ? advFewerText() : '$v';

/// A rate / average the server could not give (too few students): "Not enough data".
String advNoDataText() => t('بيانات غير كافية', 'Not enough data');

/// A signed GPA change: "+0.21" · "−0.05" · "0.00".
String advSigned(double v) => '${v > 0 ? '+' : (v < 0 ? '−' : '')}${v.abs().toStringAsFixed(2)}';

/// "N students" with the Arabic forms.
String advStudentsText(int n) =>
    countText(n, ar0: 'لا طلاب', ar1: 'طالب واحد', ar2: 'طالبان', arFew: '$n طلاب', arMany: '$n طالباً', en0: 'No students', en1: '1 student', en: '$n students');

String advAdvisorsText(int n) =>
    countText(n, ar0: 'لا مرشدين', ar1: 'مرشد واحد', ar2: 'مرشدان', arFew: '$n مرشدين', arMany: '$n مرشداً', en0: 'No advisors', en1: '1 advisor', en: '$n advisors');

Color advRiskBandColor(BuildContext context, String key) {
  final c = context.colors;
  return switch (key) {
    'high' => c.danger,
    'medium' => c.warning,
    'low' => c.primary,
    _ => c.success,
  };
}

Color advSeverityColor(BuildContext context, String s) {
  final c = context.colors;
  return switch (s) {
    'critical' => c.danger,
    'warning' => c.warning,
    'info' => c.primary,
    _ => c.success,
  };
}

IconData advSeverityIcon(String s) => switch (s) {
      'critical' => Icons.error_rounded,
      'warning' => Icons.warning_amber_rounded,
      'info' => Icons.info_outline_rounded,
      _ => Icons.check_circle_rounded,
    };

/// Axis labels for a dated series: every one when they fit, else every k-th (the rest blank) so none is cut.
List<String> advSeriesLabels(List<DateTime?> dates, String interval, {int most = 8}) {
  final all = [for (final d in dates) advBucketLabel(d, interval)];
  if (all.length <= most) return all;
  final step = (all.length / most).ceil();
  return [for (var i = 0; i < all.length; i++) i % step == 0 || i == all.length - 1 ? all[i] : ''];
}

/// The range in words: the term's title, or "3 Nov 2026 – 5 Dec 2026".
String advRangeText(AdvRange range) {
  final term = range.term;
  if (term != null) return term.title;
  final f = range.from, e = range.to;
  if (f == null || e == null) return t('الفصل الحالي', 'Current term');
  return '${advDate(f, dateOnly: true)} – ${advDate(e, dateOnly: true)}';
}

// ═════════════════════════════════════════════════════════════════════════════
//  Building blocks
// ═════════════════════════════════════════════════════════════════════════════

/// One dashboard card: a tinted icon, the title and a subtitle, then [children].
class AdvAnCard extends StatelessWidget {
  const AdvAnCard({super.key, required this.icon, required this.title, this.subtitle, required this.children, this.trailing, this.color});
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.primary;
    final sub = subtitle;
    return AppCard(
      padding: AppSpace.card,
      child: LayoutBuilder(builder: (context, box) {
        // a narrow card (a phone, a large text size): the action goes under the title instead of squeezing it
        final under = trailing != null && box.maxWidth < 420 * MediaQuery.textScalerOf(context).scale(1);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ExcludeSemantics(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: AppRadius.chipAll),
              child: Icon(icon, size: AppIconSize.md, color: appInk(context, col)),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(header: true, child: Text(title, style: AppType.section(context))),
              if (sub != null && sub.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(sub, style: AppType.meta(context)),
              ],
            ]),
          ),
          if (trailing != null && !under) ...[const SizedBox(width: AppSpace.xs), trailing!],
        ]),
        if (under) Align(alignment: AlignmentDirectional.centerStart, child: trailing!),
        SizedBox(height: under ? AppSpace.xs : AppSpace.md),
        ...children,
      ]);
      }),
    );
  }
}

/// A small heading inside a card ("By highest open alert").
class AdvAnSubhead extends StatelessWidget {
  const AdvAnSubhead(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.md, bottom: AppSpace.xs),
        child: Semantics(header: true, child: Text(text, style: AppType.bodyStrong(context))),
      );
}

/// A wrap of [AdvMiniStat]s.
class AdvMiniStats extends StatelessWidget {
  const AdvMiniStats(this.stats, {super.key});
  final List<AdvMiniStat> stats;

  @override
  Widget build(BuildContext context) => Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: stats);
}

/// One row under a chart.
class AdvBreakdownRow {
  const AdvBreakdownRow({required this.label, this.value, this.text, this.color, this.hint, this.onTap, this.zeroIsKnown = true});

  final String label;

  /// The count; null (with no [text]) = fewer than 5.
  final int? value;

  /// The figure as text instead of [value] ("23 / 40", "83%").
  final String? text;
  final Color? color;
  final String? hint;

  /// Opens the students behind it (null: not tappable — the aggregate tier, or no list exists).
  final VoidCallback? onTap;

  /// A 0 is a real zero (no chevron then even with [onTap]: an empty list helps nobody).
  final bool zeroIsKnown;

  String get shown => text ?? advCountText(value);
  bool get suppressed => text == null && value == null;
}

/// The rows under a chart: swatch · label (+ hint, + a share bar when [total] is given) · figure · chevron.
class AdvBreakdownList extends StatelessWidget {
  const AdvBreakdownList({super.key, required this.rows, this.total});
  final List<AdvBreakdownRow> rows;

  /// The whole the rows share (bars under the labels); null = no bars.
  final int? total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tot = total;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) Divider(height: 1, color: c.divider),
        _BreakdownTile(row: rows[i], total: tot),
      ],
    ]);
  }
}

class _BreakdownTile extends StatelessWidget {
  const _BreakdownTile({required this.row, this.total});
  final AdvBreakdownRow row;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = row;
    final tap = r.onTap != null && !(r.zeroIsKnown && r.value == 0 && r.text == null) ? r.onTap : null;
    final share = total != null && total! > 0 && r.value != null ? (r.value! / total!).clamp(0.0, 1.0) : null;
    final figureStyle = r.suppressed
        ? AppType.meta(context).copyWith(fontStyle: FontStyle.italic)
        : AppType.row(context).copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]);
    final semantics = '${r.label}: ${r.shown}${r.hint == null ? '' : ', ${r.hint}'}';
    return Semantics(
      button: tap != null,
      label: semantics,
      excludeSemantics: true,
      child: InkWell(
        onTap: tap,
        borderRadius: AppRadius.chipAll,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs, horizontal: AppSpace.xxs),
            child: Row(children: [
              if (r.color != null) ...[
                Container(width: 10, height: 10, decoration: BoxDecoration(color: r.color, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: AppSpace.sm),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(r.label, style: AppType.row(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (r.hint != null && r.hint!.isNotEmpty) Text(r.hint!, style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (share != null) ...[
                    const SizedBox(height: AppSpace.xxs),
                    AppProgressBar(value: share * 100, height: 4, color: r.color ?? c.primary),
                  ],
                ]),
              ),
              const SizedBox(width: AppSpace.sm),
              Text(r.shown, style: figureStyle, textDirection: r.suppressed ? null : TextDirection.ltr),
              SizedBox(
                width: AppIconSize.md + AppSpace.xxs,
                child: tap == null ? null : Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A one-line note under a chart ("Groups of fewer than 5 students are left blank").
class AdvChartNote extends StatelessWidget {
  const AdvChartNote(this.text, {super.key, this.icon = Icons.info_outline_rounded});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ExcludeSemantics(child: Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: AppIconSize.xs, color: context.colors.textLight))),
          const SizedBox(width: AppSpace.xxs),
          Expanded(child: Text(text, style: AppType.meta(context))),
        ]),
      );
}

/// "Groups of fewer than 5 are left blank" — under a chart whose bars may hide a group.
Widget? _suppressedNote(Iterable<int?> values) =>
    values.any((v) => v == null) ? AdvChartNote(t('المجموعات الأقل من 5 طلاب لا تُعرض أعدادها.', 'Groups of fewer than 5 students are not counted here.'), icon: Icons.lock_outline_rounded) : null;

// ═════════════════════════════════════════════════════════════════════════════
//  Filter summary · tier banner
// ═════════════════════════════════════════════════════════════════════════════

/// The chips that say what the figures cover: the range (+ days), then each "who" filter.
class AdvFilterSummary extends StatelessWidget {
  const AdvFilterSummary({super.key, required this.range, required this.filter, this.programName, this.onEdit});
  final AdvRange range;
  final AdvAnalyticsFilter filter;
  final String? programName;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final days = range.days;
    final chips = <(IconData, String)>[
      (Icons.date_range_rounded, [advRangeText(range), if (days > 0) countText(days, ar1: 'يوم', ar2: 'يومان', arFew: '$days أيام', arMany: '$days يوماً', en1: '1 day', en: '$days days')].join(' · ')),
      if (filter.programId != null) (Icons.school_outlined, programName ?? '#${filter.programId}'),
      if (filter.level != null) (Icons.stairs_rounded, filter.level!),
      if (filter.cohort != null) (Icons.groups_outlined, t('دفعة ${filter.cohort}', 'Cohort ${filter.cohort}')),
      if (filter.advisor != null) (Icons.co_present_outlined, filter.advisor!.shown),
    ];
    return Semantics(
      label: '${t('الأرقام تخص', 'The figures cover')}: ${[for (final ch in chips) ch.$2].join('، ')}',
      button: onEdit != null,
      excludeSemantics: true,
      child: InkWell(
        onTap: onEdit,
        borderRadius: AppRadius.chipAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
          child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final (icon, text) in chips)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs + 2),
                decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: AppIconSize.xs, color: c.textMedium),
                  const SizedBox(width: AppSpace.xxs),
                  Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textDark))),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

/// The aggregate tier's banner: totals only, small groups hidden, no student lists.
class AdvAggregateBanner extends StatelessWidget {
  const AdvAggregateBanner({super.key});

  @override
  Widget build(BuildContext context) => AppBanner(
        icon: Icons.shield_outlined,
        text: t('تعرض لك هذه الصفحة الإجماليات فقط: لا أسماء طلاب، والمجموعات الأقل من 5 طلاب تظهر «أقل من 5».',
            'You see totals only: no student names, and groups of fewer than 5 students read "Fewer than 5".'),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  KPIs
// ═════════════════════════════════════════════════════════════════════════════

/// The eight KPIs: value, the change against the same-length range before, a sparkline where a series exists.
class AdvKpiRow extends StatelessWidget {
  const AdvKpiRow({super.key, required this.overview, this.onTap});
  final AdvOverview overview;

  /// A KPI was tapped (null: not tappable); the caller decides which ones lead somewhere.
  final ValueChanged<String>? onTap;

  List<double>? _spark(String key) {
    final o = overview;
    List<double>? of(Iterable<double?> v) {
      final list = [for (final x in v) ?x];
      return list.length >= 2 ? list : null;
    }

    return switch (key) {
      'at_risk' => o.stateSeries ? of(o.riskTrend.map((p) => p.atRisk?.toDouble())) : null,
      'meetings_completed' => of(o.meetings.points.map((p) => p.of('completed').toDouble())),
      'avg_response_hours' => of(o.response.points.map((p) => p.avgHours)),
      'alerts' => of(o.riskTrend.map((p) => p.alerts.toDouble())),
      _ => null,
    };
  }

  IconData _icon(String key) => switch (key) {
        'students' => Icons.school_rounded,
        'unassigned' => Icons.person_search_rounded,
        'at_risk' => Icons.trending_down_rounded,
        'meetings_completed' => Icons.event_available_rounded,
        'no_show_rate' => Icons.event_busy_rounded,
        'avg_response_hours' => Icons.schedule_rounded,
        'alerts' => Icons.notifications_active_outlined,
        _ => Icons.report_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final palette = appChartPalette(context);
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 840 ? 4 : 2;
      final w = (box.maxWidth - AppSpace.sm * (cols - 1)) / cols;
      return Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
        for (var i = 0; i < advKpiKeys.length; i++)
          SizedBox(
            width: w,
            child: Builder(builder: (context) {
              final key = advKpiKeys[i];
              final k = overview.kpi(key);
              final shown = advKpiValue(key, k.value);
              return AppTrendTile(
                label: advKpiLabel(key),
                value: shown.isEmpty ? '—' : shown,
                delta: k.delta,
                upIsGood: advKpiUpIsGood(key),
                icon: _icon(key),
                color: palette[i % 5],
                spark: _spark(key),
                deltaHint: shown.isEmpty ? advNoDataText() : t('مقارنة بالمدة السابقة', 'vs the previous range'),
                onTap: onTap == null ? null : () => onTap!(key),
              );
            }),
          ),
      ]);
    });
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Load
// ═════════════════════════════════════════════════════════════════════════════

class AdvLoadCard extends StatelessWidget {
  const AdvLoadCard({super.key, required this.load, required this.students, this.onBucket, this.onAdvisor, this.onAllAdvisors});
  final AdvLoadSection load;
  final AdvStudentsSection students;

  /// A distribution bucket → the advisors table.
  final ValueChanged<String>? onBucket;

  /// One of the most loaded → their students (manage).
  final ValueChanged<AdvLoadTop>? onAdvisor;
  final VoidCallback? onAllAdvisors;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = load;
    final buckets = [for (final k in advLoadBuckets) (k, l.distribution[k] ?? 0)];
    Color bucketColor(String k) => switch (k) {
          'over' => c.danger,
          'full' || '80_99' => c.warning,
          'empty' => c.textLight,
          _ => appChartPalette(context).first,
        };
    return AdvAnCard(
      icon: Icons.balance_rounded,
      title: t('حمل المرشدين', 'Advisor load'),
      subtitle: t('${advAdvisorsText(l.advisors)} · ${advStudentsText(students.assigned)} لهم مرشد', '${advAdvisorsText(l.advisors)} · ${advStudentsText(students.assigned)} with an advisor'),
      trailing: onAllAdvisors == null
          ? null
          : TextButton(style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)), onPressed: onAllAdvisors, child: Text(t('كل المرشدين', 'All advisors'))),
      children: [
        AdvMiniStats([
          AdvMiniStat(label: t('متوسط الحمل', 'Average load'), value: advFigure(l.avg)),
          AdvMiniStat(label: t('أعلى حمل', 'Highest load'), value: '${l.max}'),
          AdvMiniStat(label: t('فوق الحد', 'Over the maximum'), value: '${l.over}', tone: l.over > 0 ? c.danger : null),
          AdvMiniStat(label: t('مقاعد متاحة', 'Places left'), value: '${l.capacityLeft}'),
        ]),
        const SizedBox(height: AppSpace.md),
        AppBarChart(
          title: t('المرشدون حسب نسبة الحمل', 'Advisors by load'),
          series: [AppChartSeries(t('المرشدون', 'Advisors'), [for (final b in buckets) b.$2.toDouble()])],
          labels: [for (final b in buckets) advLoadBucketLabel(b.$1)],
          height: 150,
          integerAxis: true,
        ),
        const SizedBox(height: AppSpace.xs),
        AdvBreakdownList(rows: [
          for (final (k, n) in buckets)
            if (n > 0) AdvBreakdownRow(label: advLoadBucketLabel(k), value: n, color: bucketColor(k), onTap: onBucket == null ? null : () => onBucket!(k)),
        ]),
        if (l.top.isNotEmpty) ...[
          AdvAnSubhead(t('الأعلى حملاً', 'Most loaded')),
          for (final a in l.top.take(5))
            Semantics(
              button: onAdvisor != null,
              label: '${a.shown}: ${t('الحمل ${a.load} من ${a.maxLoad}', 'load ${a.load} of ${a.maxLoad}')}',
              excludeSemantics: true,
              child: InkWell(
                onTap: onAdvisor == null ? null : () => onAdvisor!(a),
                borderRadius: AppRadius.chipAll,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppTouch.min),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs, horizontal: AppSpace.xxs),
                    child: Row(children: [
                      AppAvatar(name: a.shown, size: 32),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(a.shown, textDirection: advTextDirection(a.shown), style: AppType.row(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: AppSpace.xxs),
                          AdvLoadBar(load: a.load, max: a.maxLoad, warn: a.warn, over: a.over),
                        ]),
                      ),
                      SizedBox(
                        width: AppIconSize.md + AppSpace.xxs,
                        child: onAdvisor == null ? null : Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Struggling
// ═════════════════════════════════════════════════════════════════════════════

class AdvStrugglingCard extends StatelessWidget {
  const AdvStrugglingCard({super.key, required this.struggling, required this.total, this.onBand, this.onPriority, this.onCategory});
  final AdvStrugglingSection struggling;

  /// Every student in the scope (the bands' shares).
  final int total;
  final ValueChanged<String>? onBand, onPriority;
  final ValueChanged<AdvCategoryStat>? onCategory;

  @override
  Widget build(BuildContext context) {
    final s = struggling;
    final pr = [for (final p in advPriorities.reversed) (p, s.byPriority[p])];
    final anyAlert = pr.any((x) => (x.$2 ?? 1) > 0);
    final cats = [...s.byCategory]..sort((a, b) => (b.students ?? 2).compareTo(a.students ?? 2));
    final atRisk = s.atRisk;
    return AdvAnCard(
      icon: Icons.support_rounded,
      title: t('الطلاب المتعثرون', 'Struggling students'),
      subtitle: atRisk == null
          ? t('معرّضون للخطر: ${advFewerText()}', 'At risk: ${advFewerText()}')
          : t('${advStudentsText(atRisk)} معرّضون للخطر (مرتفع + متوسط)', '${advStudentsText(atRisk)} at risk (high + medium)'),
      color: context.colors.danger,
      children: [
        AdvBreakdownList(
          total: total,
          rows: [
            for (final k in advRiskBandKeys)
              AdvBreakdownRow(
                label: advRiskBandName(k),
                value: s.riskBands[k],
                color: advRiskBandColor(context, k),
                hint: switch (k) {
                  'high' => t('درجة 60 فأكثر', 'Score 60 and above'),
                  'medium' => t('درجة 30 – 59', 'Score 30 – 59'),
                  'low' => t('درجة 1 – 29', 'Score 1 – 29'),
                  _ => null,
                },
                onTap: onBand == null ? null : () => onBand!(k),
              ),
          ],
        ),
        ?_suppressedNote(s.riskBands.values),
        AdvAnSubhead(t('حسب أعلى تنبيه مفتوح', 'By their highest open alert')),
        if (!anyAlert)
          AdvChartNote(t('لا تنبيهات مفتوحة الآن.', 'No open alerts right now.'), icon: Icons.check_circle_outline_rounded)
        else ...[
          Center(
            child: AppDonut(
              title: t('الطلاب حسب أعلى تنبيه مفتوح', 'Students by their highest open alert'),
              parts: [for (final (p, n) in pr) AppChartPart(advPriorityLabel(p), (n ?? 0).toDouble(), color: advPriorityColor(context, p))],
              legend: false,
              size: 112,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          AdvBreakdownList(rows: [
            for (final (p, n) in pr) AdvBreakdownRow(label: advPriorityLabel(p), value: n, color: advPriorityColor(context, p), onTap: onPriority == null ? null : () => onPriority!(p)),
          ]),
          ?_suppressedNote(pr.map((x) => x.$2)),
        ],
        if (cats.isNotEmpty) ...[
          AdvAnSubhead(t('التنبيهات المفتوحة حسب التصنيف', 'Open alerts by category')),
          AppBarChart(
            title: t('الطلاب حسب التصنيف', 'Students by category'),
            series: [
              AppChartSeries(t('الطلاب', 'Students'), [for (final x in cats) (x.students ?? 0).toDouble()]),
              AppChartSeries(t('التنبيهات', 'Alerts'), [for (final x in cats) (x.flags ?? 0).toDouble()]),
            ],
            labels: [for (final x in cats) x.category.name],
            height: 160,
            integerAxis: true,
          ),
          const SizedBox(height: AppSpace.xs),
          AdvBreakdownList(rows: [
            for (final x in cats)
              AdvBreakdownRow(
                label: x.category.name,
                value: x.students,
                hint: x.flags == null
                    ? t('التنبيهات: ${advFewerText()}', 'Alerts: ${advFewerText()}')
                    : countText(x.flags!, ar1: 'تنبيه واحد', ar2: 'تنبيهان', arFew: '${x.flags} تنبيهات', arMany: '${x.flags} تنبيهاً', en1: '1 alert', en: '${x.flags} alerts'),
                onTap: onCategory == null || x.category.id == null ? null : () => onCategory!(x),
              ),
          ]),
          ?_suppressedNote(cats.map((x) => x.students)),
        ],
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Risk trend
// ═════════════════════════════════════════════════════════════════════════════

class AdvRiskTrendCard extends StatelessWidget {
  const AdvRiskTrendCard({super.key, required this.points, required this.interval, required this.stateSeries, this.onAlerted});
  final List<AdvRiskPoint> points;
  final String interval;

  /// false with a student filter: the at-risk line is not available.
  final bool stateSeries;
  final VoidCallback? onAlerted;

  @override
  Widget build(BuildContext context) {
    final palette = appChartPalette(context);
    final opened = points.fold<int>(0, (a, p) => a + p.opened), resolved = points.fold<int>(0, (a, p) => a + p.resolved);
    final alerts = points.fold<int>(0, (a, p) => a + p.alerts);
    final line = [for (final p in points) ?p.atRisk?.toDouble()];
    final last = points.reversed.map((p) => p.atRisk).whereType<int>().firstOrNull;
    return AdvAnCard(
      icon: Icons.show_chart_rounded,
      title: t('اتجاه الخطر', 'Risk trend'),
      subtitle: t('التنبيهات المفتوحة والمغلقة في كل فترة', 'Alerts opened and resolved in each period'),
      children: [
        if (points.isEmpty)
          AdvChartNote(t('لا بيانات في هذه المدة بعد.', 'No figures in this range yet.'))
        else
          AppBarChart(
            title: t('التنبيهات حسب الفترة', 'Alerts by period'),
            series: [
              AppChartSeries(t('فُتحت', 'Opened'), [for (final p in points) p.opened.toDouble()]),
              AppChartSeries(t('أُغلقت', 'Resolved'), [for (final p in points) p.resolved.toDouble()], color: palette.length > 2 ? palette[2] : null),
            ],
            labels: advSeriesLabels([for (final p in points) p.date], interval),
            height: 170,
            integerAxis: true,
          ),
        const SizedBox(height: AppSpace.sm),
        if (!stateSeries)
          AdvChartNote(t('خط «المعرّضون للخطر» لا يتوفر مع تصفية الطلاب.', 'The at-risk line is not available while a student filter is on.'))
        else if (line.length >= 2) ...[
          Row(children: [
            Expanded(child: Text(t('المعرّضون للخطر عبر الوقت', 'At risk over time'), style: AppType.bodyStrong(context))),
            if (last != null) Text('$last', textDirection: TextDirection.ltr, style: AppType.row(context).copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: AppSpace.xxs),
          AppSparkline(line, color: context.colors.danger, height: 44, label: t('المعرّضون للخطر عبر الوقت', 'At risk over time')),
        ] else
          AdvChartNote(t('يظهر خط «المعرّضون للخطر» بعد يومين من التحديث اليومي.', 'The at-risk line shows after two daily updates.')),
        const SizedBox(height: AppSpace.xs),
        AdvBreakdownList(rows: [
          AdvBreakdownRow(label: t('صدر لهم تنبيه في المدة', 'Got an alert in the range'), value: alerts, onTap: onAlerted),
          AdvBreakdownRow(label: t('تنبيهات فُتحت', 'Alerts opened'), value: opened),
          AdvBreakdownRow(label: t('تنبيهات أُغلقت', 'Alerts resolved'), value: resolved),
        ]),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  GPA
// ═════════════════════════════════════════════════════════════════════════════

class AdvGpaCard extends StatelessWidget {
  const AdvGpaCard({super.key, required this.gpa, this.onBand});
  final AdvGpaSection gpa;
  final ValueChanged<AdvGpaBand>? onBand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = gpa;
    final line = g.probationBelow;
    final bands = g.distribution;
    final below = line == null ? null : [for (final b in bands) if (b.key != 'none' && b.to != null && b.to! <= line + 1e-9) b];
    int? belowCount;
    if (below != null) {
      belowCount = below.any((b) => b.students == null) ? null : below.fold<int>(0, (a, b) => a + (b.students ?? 0));
    }
    final trend = [for (final p in g.trend) if (p.avgTermGpa != null) p];
    return AdvAnCard(
      icon: Icons.insights_rounded,
      title: t('توزيع المعدل التراكمي', 'CGPA distribution'),
      subtitle: line == null
          ? t('على مقياس من ${advFigure(g.scaleMax)}', 'On a ${advFigure(g.scaleMax)} scale')
          : t('خط الإنذار الأكاديمي: أقل من ${line.toStringAsFixed(2)}', 'Probation line: below ${line.toStringAsFixed(2)}'),
      children: [
        AdvMiniStats([
          AdvMiniStat(label: t('متوسط المعدل', 'Average CGPA'), value: g.avgCgpa == null ? '' : g.avgCgpa!.toStringAsFixed(2)),
          if (line != null)
            AdvMiniStat(
              label: t('تحت خط الإنذار', 'Below the probation line'),
              value: belowCount == null ? '<5' : '$belowCount',
              tone: (belowCount ?? 0) > 0 ? c.danger : null,
            ),
          AdvMiniStat(label: t('بلا معدل بعد', 'No CGPA yet'), value: g.noGpa == null ? '<5' : '${g.noGpa}'),
        ]),
        const SizedBox(height: AppSpace.md),
        AppBarChart(
          title: t('الطلاب حسب شريحة المعدل', 'Students by CGPA band'),
          series: [AppChartSeries(t('الطلاب', 'Students'), [for (final b in bands) (b.students ?? 0).toDouble()])],
          labels: [for (final b in bands) b.short],
          height: 160,
          integerAxis: true,
        ),
        const SizedBox(height: AppSpace.xs),
        AdvBreakdownList(rows: [
          for (final b in bands)
            AdvBreakdownRow(
              label: b.label,
              value: b.students,
              color: below != null && below.contains(b) ? c.danger : (b.key == 'none' ? c.textLight : appChartPalette(context).first),
              hint: below != null && below.contains(b) ? t('تحت خط الإنذار', 'Below the probation line') : null,
              onTap: onBand == null ? null : () => onBand!(b),
            ),
        ]),
        ?_suppressedNote(bands.map((b) => b.students)),
        if (trend.length >= 2) ...[
          AdvAnSubhead(t('متوسط المعدل الفصلي', 'Average term GPA')),
          AppSparkline([for (final p in trend) p.avgTermGpa!], height: 44, label: t('متوسط المعدل الفصلي عبر الفصول', 'Average term GPA across terms')),
          const SizedBox(height: AppSpace.xxs),
          Row(children: [
            Expanded(child: Text('${trend.first.term?.short ?? ''} · ${trend.first.avgTermGpa!.toStringAsFixed(2)}', style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: AppSpace.xs),
            Text('${trend.last.term?.short ?? ''} · ${trend.last.avgTermGpa!.toStringAsFixed(2)}',
                style: AppType.meta(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600), maxLines: 1),
          ]),
        ],
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Meetings
// ═════════════════════════════════════════════════════════════════════════════

class AdvMeetingsCard extends StatelessWidget {
  const AdvMeetingsCard({super.key, required this.meetings, this.onDrill});
  final AdvMeetingsSection meetings;

  /// `met` · `no_show` · `booked`.
  final ValueChanged<String>? onDrill;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = meetings;
    final modes = [for (final k in advMeetingModes) if ((m.byMode[k] ?? 0) > 0) '${_mode(k)} ${m.byMode[k]}'];
    VoidCallback? drill(String k) => onDrill == null ? null : () => onDrill!(k);
    return AdvAnCard(
      icon: Icons.event_available_rounded,
      title: t('اللقاءات الإرشادية', 'Advising meetings'),
      subtitle: t('${m.booked} حجزاً في المدة', '${m.booked} booked in the range'),
      color: c.success,
      children: [
        LayoutBuilder(builder: (context, box) {
          final donut = AppDonut(
            title: t('اللقاءات حسب الحالة', 'Meetings by status'),
            parts: [
              AppChartPart(t('تمت', 'Held'), m.completed.toDouble(), color: c.success),
              AppChartPart(t('غياب', 'No-show'), m.noShow.toDouble(), color: c.danger),
              AppChartPart(t('أُلغيت', 'Cancelled'), m.cancelled.toDouble(), color: c.textLight),
            ],
            legend: false,
            size: 112,
          );
          final stats = AdvMiniStats([
            AdvMiniStat(label: t('نسبة الإتمام', 'Completion rate'), value: advRate(m.completionRate), tone: m.completionRate == null ? null : c.success, hint: m.completionRate == null ? advNoDataText() : null),
            AdvMiniStat(label: t('نسبة الغياب', 'No-show rate'), value: advRate(m.noShowRate), tone: (m.noShowRate ?? 0) >= 20 ? c.danger : null, hint: m.noShowRate == null ? advNoDataText() : null),
            AdvMiniStat(label: t('طلاب التقوا مرشدهم', 'Students met'), value: m.studentsMet == null ? '<5' : '${m.studentsMet}'),
          ]);
          if (box.maxWidth >= 420) {
            return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [donut, const SizedBox(width: AppSpace.md), Expanded(child: stats)]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Center(child: donut), const SizedBox(height: AppSpace.sm), stats]);
        }),
        const SizedBox(height: AppSpace.sm),
        AdvBreakdownList(rows: [
          AdvBreakdownRow(label: t('تمت', 'Held'), value: m.completed, color: c.success, onTap: drill('met')),
          AdvBreakdownRow(label: t('غاب الطالب', 'Student did not come'), value: m.noShow, color: c.danger, onTap: drill('no_show')),
          AdvBreakdownRow(
            label: t('أُلغيت', 'Cancelled'),
            value: m.cancelled,
            color: c.textLight,
            hint: m.lateCancelled > 0 ? t('منها ${m.lateCancelled} في آخر لحظة', '${m.lateCancelled} of them at the last minute') : null,
          ),
          AdvBreakdownRow(label: t('لقاءات قادمة', 'Upcoming'), value: m.upcoming, onTap: drill('booked')),
        ]),
        if (modes.isNotEmpty) AdvChartNote(modes.join(' · '), icon: Icons.devices_other_rounded),
      ],
    );
  }

  String _mode(String k) => switch (k) {
        'in_person' => t('حضوري', 'In person'),
        'video' => t('مرئي', 'Video'),
        'phone' => t('هاتف', 'Phone'),
        _ => t('محادثة', 'Chat'),
      };
}

// ═════════════════════════════════════════════════════════════════════════════
//  Replies and complaints
// ═════════════════════════════════════════════════════════════════════════════

class AdvResponseCard extends StatelessWidget {
  const AdvResponseCard({super.key, required this.response, required this.complaints, this.onAwaiting, this.onComplaints});
  final AdvResponseSection response;
  final AdvComplaintsSection complaints;
  final VoidCallback? onAwaiting, onComplaints;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = response, q = complaints;
    final buckets = [for (final k in advResponseBuckets) (k, r.buckets[k] ?? 0)];
    return AdvAnCard(
      icon: Icons.forum_rounded,
      title: t('الردود والشكاوى', 'Replies and complaints'),
      subtitle: countText(r.replies, ar0: 'لا ردود في المدة', ar1: 'رد واحد في المدة', ar2: 'ردان في المدة', arFew: '${r.replies} ردود في المدة', arMany: '${r.replies} رداً في المدة',
          en0: 'No replies in the range', en1: '1 reply in the range', en: '${r.replies} replies in the range'),
      children: [
        AdvMiniStats([
          AdvMiniStat(label: t('متوسط زمن الرد', 'Average reply time'), value: advHours(r.avgHours), hint: r.avgHours == null ? advNoDataText() : null),
          AdvMiniStat(label: t('ردود في الموعد', 'Replies on time'), value: advRate(r.slaMetPct), tone: r.slaMetPct == null ? null : (r.slaMetPct! >= 80 ? c.success : c.warning)),
          AdvMiniStat(label: t('تنتظر رداً', 'Waiting for a reply'), value: '${r.awaitingReply}', tone: r.awaitingReply > 0 ? c.warning : null),
        ]),
        const SizedBox(height: AppSpace.md),
        AppBarChart(
          title: t('الردود حسب زمن الرد', 'Replies by reply time'),
          series: [AppChartSeries(t('الردود', 'Replies'), [for (final b in buckets) b.$2.toDouble()])],
          labels: [for (final b in buckets) advResponseBucketLabel(b.$1)],
          height: 150,
          integerAxis: true,
        ),
        const SizedBox(height: AppSpace.xs),
        AdvBreakdownList(rows: [
          AdvBreakdownRow(label: t('طلاب ينتظرون رداً', 'Students waiting for a reply'), value: r.awaitingReply, color: c.warning, onTap: onAwaiting),
        ]),
        AdvAnSubhead(t('الشكاوى', 'Complaints')),
        AdvMiniStats([
          AdvMiniStat(label: t('مفتوحة الآن', 'Open now'), value: '${q.openNow}', tone: q.openNow > 0 ? c.warning : null),
          AdvMiniStat(label: t('متوسط زمن الحل', 'Average time to resolve'), value: advHours(q.avgResolutionHours), hint: q.avgResolutionHours == null ? advNoDataText() : null),
          AdvMiniStat(label: t('صُعّدت', 'Escalated'), value: '${q.escalated}'),
        ]),
        const SizedBox(height: AppSpace.xs),
        AdvBreakdownList(rows: [
          AdvBreakdownRow(label: t('شكاوى قُدّمت في المدة', 'Complaints opened in the range'), value: q.opened, onTap: onComplaints),
          AdvBreakdownRow(label: t('أُغلقت', 'Closed'), value: q.closed),
          AdvBreakdownRow(label: t('عن مرشد', 'About an advisor'), value: q.aboutAdvisor),
        ]),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Requests
// ═════════════════════════════════════════════════════════════════════════════

class AdvRequestsCard extends StatelessWidget {
  const AdvRequestsCard({super.key, required this.requests, this.onStage});
  final AdvRequestsSection requests;
  final ValueChanged<String>? onStage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = requests;
    final stages = [for (final k in advRequestStages) (k, q.open[k] ?? 0)];
    final decided = [for (final k in const ['approved', 'rejected', 'withdrawn', 'closed']) if ((q.decided[k] ?? 0) > 0) '${advRequestStageLabel(k)} ${q.decided[k]}'];
    return AdvAnCard(
      icon: Icons.assignment_turned_in_outlined,
      title: t('طلبات الدعم', 'Support requests'),
      subtitle: countText(q.openTotal,
          ar0: 'لا طلبات مفتوحة', ar1: 'طلب مفتوح واحد', ar2: 'طلبان مفتوحان', arFew: '${q.openTotal} طلبات مفتوحة', arMany: '${q.openTotal} طلباً مفتوحاً',
          en0: 'No open requests', en1: '1 open request', en: '${q.openTotal} open requests'),
      children: [
        AdvMiniStats([
          AdvMiniStat(label: t('نسبة القبول', 'Approval rate'), value: advRate(q.approvalRate), hint: q.approvalRate == null ? advNoDataText() : null),
          AdvMiniStat(label: t('متوسط زمن القرار', 'Average time to decide'), value: advDays(q.avgDecisionDays)),
          AdvMiniStat(label: t('متأخرة', 'Overdue'), value: '${q.overdue}', tone: q.overdue > 0 ? c.danger : null),
        ]),
        const SizedBox(height: AppSpace.md),
        AppBarChart(
          title: t('الطلبات المفتوحة حسب المرحلة', 'Open requests by stage'),
          series: [AppChartSeries(t('الطلبات', 'Requests'), [for (final s in stages) s.$2.toDouble()])],
          labels: [for (final s in stages) advRequestStageLabel(s.$1)],
          height: 150,
          integerAxis: true,
        ),
        const SizedBox(height: AppSpace.xs),
        AdvBreakdownList(rows: [
          for (final (k, n) in stages) AdvBreakdownRow(label: advRequestStageLabel(k), value: n, onTap: onStage == null ? null : () => onStage!(k)),
        ]),
        if (decided.isNotEmpty) AdvChartNote(t('قرارات المدة: ${decided.join(' · ')}', 'Decided in the range: ${decided.join(' · ')}'), icon: Icons.gavel_rounded),
        if (q.referralsOpen > 0 || q.referralsDecided.isNotEmpty)
          AdvChartNote(
            t('الإحالات: ${q.referralsOpen} مفتوحة · ${q.referralsDecided['handled'] ?? 0} عولجت · ${q.referralsDecided['declined'] ?? 0} اعتُذر عنها',
                'Referrals: ${q.referralsOpen} open · ${q.referralsDecided['handled'] ?? 0} handled · ${q.referralsDecided['declined'] ?? 0} declined'),
            icon: Icons.call_split_rounded,
          ),
        if (q.byType.isNotEmpty) ...[
          AdvAnSubhead(t('حسب النوع', 'By type')),
          AdvBreakdownList(total: q.byType.fold<int>(0, (a, x) => a + x.count), rows: [for (final x in q.byType) AdvBreakdownRow(label: x.label, value: x.count)]),
        ],
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Activity
// ═════════════════════════════════════════════════════════════════════════════

class AdvActivityCard extends StatelessWidget {
  const AdvActivityCard({super.key, required this.activity, this.onAdvisors});
  final AdvActivitySection activity;

  /// `active` · `inactive` → the advisors table.
  final ValueChanged<String>? onAdvisors;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = activity;
    final days = a.windowDays;
    final window = countText(days, ar1: 'آخر يوم', ar2: 'آخر يومين', arFew: 'آخر $days أيام', arMany: 'آخر $days يوماً', en1: 'the last day', en: 'the last $days days');
    return AdvAnCard(
      icon: Icons.bolt_rounded,
      title: t('نشاط المرشدين', 'Advisor activity'),
      subtitle: t('نشط = لقاء أو رد أو ملاحظة أو تنبيه مغلق في $window', 'Active = a meeting, reply, note or resolved alert in $window'),
      children: [
        LayoutBuilder(builder: (context, box) {
          final donut = AppDonut(
            title: t('المرشدون حسب النشاط', 'Advisors by activity'),
            parts: [
              AppChartPart(t('نشطون', 'Active'), a.active.toDouble(), color: c.success),
              AppChartPart(t('غير نشطين', 'Inactive'), a.inactive.toDouble(), color: c.textLight),
            ],
            legend: false,
            size: 104,
          );
          final stats = AdvMiniStats([
            AdvMiniStat(label: t('لقاءات', 'Meetings'), value: '${a.actions['meetings'] ?? 0}'),
            AdvMiniStat(label: t('ردود', 'Replies'), value: '${a.actions['replies'] ?? 0}'),
            AdvMiniStat(label: t('ملاحظات', 'Notes'), value: '${a.actions['notes'] ?? 0}'),
            AdvMiniStat(label: t('تنبيهات أُغلقت', 'Alerts resolved'), value: '${a.actions['alerts_resolved'] ?? 0}'),
          ]);
          if (box.maxWidth >= 420) return Row(children: [donut, const SizedBox(width: AppSpace.md), Expanded(child: stats)]);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Center(child: donut), const SizedBox(height: AppSpace.sm), stats]);
        }),
        const SizedBox(height: AppSpace.sm),
        AdvBreakdownList(total: a.advisors, rows: [
          AdvBreakdownRow(label: t('نشطون', 'Active'), value: a.active, color: c.success, onTap: onAdvisors == null ? null : () => onAdvisors!('active')),
          AdvBreakdownRow(label: t('غير نشطين', 'Inactive'), value: a.inactive, color: c.textLight, onTap: onAdvisors == null ? null : () => onAdvisors!('inactive')),
        ]),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Outcomes (#10)
// ═════════════════════════════════════════════════════════════════════════════

class AdvOutcomesCard extends StatelessWidget {
  const AdvOutcomesCard({super.key, required this.outcomes, this.onGroup});
  final AdvOutcomes outcomes;

  /// `supported` · `not_supported` · `at_risk_supported` · `at_risk_not_supported` · `not_retained`.
  final ValueChanged<String>? onGroup;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = outcomes;
    final palette = appChartPalette(context);
    int? minus(int a, int? b) => b == null ? null : math.max(0, a - b);
    final notSupported = minus(o.enrolled, o.supported);
    final atRiskNot = o.atRisk == null || o.atRiskSupported == null ? null : math.max(0, o.atRisk! - o.atRiskSupported!);
    final all = o.retention['all'];
    final notRetained = all == null || all.retained == null ? null : math.max(0, all.n - all.retained!);
    VoidCallback? go(String k) => onGroup == null ? null : () => onGroup!(k);
    return AdvAnCard(
      icon: Icons.emoji_events_outlined,
      title: t('نتائج نجاح الطلاب', 'Student success outcomes'),
      subtitle: [
        if (o.term != null) o.term!.title,
        if (o.asOf != null) t('حُسبت ${AppTime.dateTime(o.asOf!)}', 'Computed ${AppTime.dateTime(o.asOf!)}'),
      ].join(' · '),
      color: c.success,
      children: [
        if (o.pending)
          AppBanner(
            icon: Icons.hourglass_top_rounded,
            text: t('تُحسب نتائج الفصل في التحديث اليومي القادم.', 'The term\'s outcomes are computed by the next daily update.'),
          )
        else ...[
          LayoutBuilder(builder: (context, box) {
            final cols = box.maxWidth >= 460 ? 2 : 1;
            final w = (box.maxWidth - AppSpace.sm * (cols - 1)) / cols;
            return Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
              SizedBox(width: w, child: _GroupCompare(
                title: t('كل الطلاب', 'All students'),
                a: (t('تلقّوا دعماً', 'Supported'), o.gpaChange['supported'], o.retention['supported'], palette[0]),
                b: (t('بلا دعم', 'Not supported'), o.gpaChange['not_supported'], null, c.textMedium),
              )),
              SizedBox(width: w, child: _GroupCompare(
                title: t('المعرّضون للخطر', 'Students at risk'),
                a: (t('تلقّوا دعماً', 'Supported'), o.gpaChange['at_risk_supported'], o.retention['at_risk_supported'], palette[0]),
                b: (t('بلا دعم', 'Not supported'), o.gpaChange['at_risk_not_supported'], o.retention['at_risk_not_supported'], c.textMedium),
              )),
            ]);
          }),
          const SizedBox(height: AppSpace.sm),
          AdvBreakdownList(total: o.enrolled, rows: [
            AdvBreakdownRow(label: t('تلقّوا دعماً', 'Supported'), value: o.supported, color: palette[0], onTap: go('supported')),
            AdvBreakdownRow(label: t('لم يتلقوا دعماً', 'Not supported'), value: notSupported, color: c.textLight, onTap: go('not_supported')),
            AdvBreakdownRow(label: t('معرّضون للخطر وتلقّوا دعماً', 'At risk, supported'), value: o.atRiskSupported, color: c.warning, onTap: go('at_risk_supported')),
            AdvBreakdownRow(label: t('معرّضون للخطر بلا دعم', 'At risk, not supported'), value: atRiskNot, color: c.danger, onTap: go('at_risk_not_supported')),
            AdvBreakdownRow(label: t('لم يستمروا', 'Not retained'), value: notRetained, color: c.textMedium, onTap: go('not_retained'), hint: all?.rate == null ? null : t('نسبة الاستمرار ${advRate(all!.rate)}', 'Retention ${advRate(all.rate)}')),
          ]),
          AdvChartNote(
            t('لقاءات تمت ${o.meetingsHeld} · تنبيهات أُغلقت ${o.alertsResolved} · خطط اكتملت ${o.plansCompleted} (حققت هدفها ${o.plansMet})',
                'Meetings held ${o.meetingsHeld} · alerts resolved ${o.alertsResolved} · plans completed ${o.plansCompleted} (met their goal ${o.plansMet})'),
            icon: Icons.fact_check_outlined,
          ),
        ],
      ],
    );
  }
}

/// Supported vs not supported: the average GPA change and retention of each, n shown.
class _GroupCompare extends StatelessWidget {
  const _GroupCompare({required this.title, required this.a, required this.b});
  final String title;
  final (String, AdvGroupAvg?, AdvRetention?, Color) a, b;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget side((String, AdvGroupAvg?, AdvRetention?, Color) s) {
      final (label, g, r, color) = s;
      final avg = g?.avg;
      final n = g?.n ?? 0;
      final change = avg == null ? (n < advMinGroup ? advFewerText() : advNoDataText()) : advSigned(avg);
      return Expanded(
        child: Semantics(
          label: '$label: ${t('تغير المعدل', 'GPA change')} $change, n = $n${r?.rate == null ? '' : ', ${t('الاستمرار', 'retention')} ${advRate(r!.rate)}'}',
          excludeSemantics: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: AppSpace.xxs),
              Flexible(child: Text(label, style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: AppSpace.xxs),
            Text(change,
                textDirection: avg == null ? null : TextDirection.ltr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: avg == null
                    ? AppType.meta(context).copyWith(fontStyle: FontStyle.italic)
                    : AppType.figure(context).copyWith(color: avg > 0 ? appInk(context, c.success) : (avg < 0 ? appInk(context, c.danger) : c.textDark))),
            Text('n = $n', textDirection: TextDirection.ltr, style: AppType.meta(context)),
            if (r?.rate != null) Text(t('الاستمرار ${advRate(r!.rate)}', 'Retention ${advRate(r.rate)}'), style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t('$title — تغير المعدل الفصلي', '$title — change in term GPA'), style: AppType.bodyStrong(context)),
        const SizedBox(height: AppSpace.xs),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [side(a), const SizedBox(width: AppSpace.sm), side(b)]),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Satisfaction
// ═════════════════════════════════════════════════════════════════════════════

class AdvSatisfactionCard extends StatelessWidget {
  const AdvSatisfactionCard({super.key, required this.satisfaction});

  /// null: not available with a student filter.
  final AdvSatisfaction? satisfaction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = satisfaction;
    final avg = s?.average;
    final shown = s == null || s.hidden || avg == null;
    return AdvAnCard(
      icon: Icons.sentiment_satisfied_alt_rounded,
      title: t('رضا الطلاب عن اللقاءات', 'Satisfaction with meetings'),
      subtitle: s == null
          ? t('لا يتوفر مع تصفية الطلاب', 'Not available while a student filter is on')
          : countText(s.count, ar0: 'لا تقييمات بعد', ar1: 'تقييم واحد', ar2: 'تقييمان', arFew: '${s.count} تقييمات', arMany: '${s.count} تقييماً', en0: 'No answers yet', en1: '1 answer', en: '${s.count} answers'),
      color: c.warning,
      children: [
        if (shown)
          AdvChartNote(
            s == null
                ? t('اختر «كل الطلاب» لرؤية متوسط الرضا.', 'Clear the student filters to see the average.')
                : t('يظهر المتوسط بعد 5 تقييمات على الأقل، حفاظاً على خصوصية الطلاب.', 'The average shows from 5 answers, to keep the answers anonymous.'),
            icon: Icons.lock_outline_rounded,
          )
        else
          Semantics(
            label: t('المتوسط ${avg.toStringAsFixed(1)} من 5', 'Average ${avg.toStringAsFixed(1)} of 5'),
            excludeSemantics: true,
            child: Row(children: [
              Text(avg.toStringAsFixed(1), textDirection: TextDirection.ltr, style: AppType.figureLarge(context)),
              const SizedBox(width: AppSpace.sm),
              for (var i = 1; i <= 5; i++)
                Icon(avg >= i - 0.25 ? Icons.star_rounded : (avg >= i - 0.75 ? Icons.star_half_rounded : Icons.star_outline_rounded), color: c.warning, size: AppIconSize.md),
            ]),
          ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Health check (#26)
// ═════════════════════════════════════════════════════════════════════════════

class AdvHealthCard extends StatelessWidget {
  const AdvHealthCard({super.key, this.health, this.loading = false, this.busy = false, this.errorText, this.onRun, this.onItem});

  /// null while loading or when it could not be read.
  final AdvHealth? health;
  final bool loading;

  /// A check is running.
  final bool busy;
  final String? errorText;
  final VoidCallback? onRun;
  final ValueChanged<AdvHealthItem>? onItem;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = health;
    final problems = h?.problems ?? const <AdvHealthItem>[];
    final critical = h?.critical ?? 0;
    final color = h == null ? c.primary : (critical > 0 ? c.danger : (problems.isEmpty ? c.success : c.warning));
    final String title;
    if (h == null) {
      title = t('فحص البيانات', 'Data check');
    } else if (h.neverChecked) {
      title = t('لم تُفحص البيانات بعد', 'The data has not been checked yet');
    } else if (h.issues == 0) {
      title = t('البيانات سليمة', 'Everything checks out');
    } else {
      final n = h.issues;
      title = countText(n, ar1: 'مشكلة واحدة تحتاج انتباهك', ar2: 'مشكلتان تحتاجان انتباهك', arFew: '$n مشكلات تحتاج انتباهك', arMany: '$n مشكلة تحتاج انتباهك',
          en1: '1 issue needs attention', en: '$n issues need attention');
    }
    final change = h?.change;
    final sub = h == null || h.neverChecked
        ? t('يُفحص كل يوم تلقائياً، ويمكنك الفحص الآن', 'Checked every day by itself; you can check now')
        : [
            t('آخر فحص ${AppTime.dateTime(h.checkedAt!)}', 'Last checked ${AppTime.dateTime(h.checkedAt!)}'),
            if (critical > 0) countText(critical, ar1: 'واحدة حرجة', ar2: 'اثنتان حرجتان', arFew: '$critical حرجة', arMany: '$critical حرجة', en1: '1 critical', en: '$critical critical'),
            if (change != null && change != 0)
              change < 0
                  ? t('أقل بـ ${-change} من الفحص السابق', '${-change} fewer than the last check')
                  : t('أكثر بـ $change من الفحص السابق', '$change more than the last check'),
          ].join(' · ');
    return AdvAnCard(
      icon: problems.isEmpty && h != null && !h.neverChecked ? Icons.verified_rounded : Icons.health_and_safety_rounded,
      title: title,
      subtitle: sub,
      color: color,
      trailing: onRun == null
          ? null
          : TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
              onPressed: busy ? null : onRun,
              icon: busy
                  ? SizedBox(width: AppIconSize.xs, height: AppIconSize.xs, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary))
                  : const Icon(Icons.refresh_rounded, size: AppIconSize.sm),
              label: Text(t('افحص الآن', 'Check now')),
            ),
      children: [
        if (loading && h == null)
          const AppListSkeleton(items: 2, withAvatar: false, padding: EdgeInsets.zero)
        else if (h == null)
          AdvChartNote(errorText ?? t('تعذّر قراءة نتيجة الفحص.', 'The check could not be read.'), icon: Icons.cloud_off_rounded)
        else if (problems.isEmpty)
          AdvChartNote(
            h.neverChecked ? t('يجري أول فحص الليلة.', 'The first check runs tonight.') : t('لا طلاب بلا مرشد، ولا تنبيهات بلا مسؤول، ولا طلبات متوقفة.', 'No student without an advisor, no alert without an owner, no stuck request.'),
            icon: Icons.check_circle_outline_rounded,
          )
        else
          for (var i = 0; i < problems.length; i++) ...[
            if (i > 0) Divider(height: 1, color: c.divider),
            _HealthTile(item: problems[i], onTap: onItem == null || problems[i].drill == null ? null : () => onItem!(problems[i])),
          ],
      ],
    );
  }
}

class _HealthTile extends StatelessWidget {
  const _HealthTile({required this.item, this.onTap});
  final AdvHealthItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final i = item;
    final col = advSeverityColor(context, i.severity);
    final sample = [
      for (final s in i.sample.take(3)) s.value == null ? s.shown : '${s.shown} (${advFigure(s.value)})',
    ].join('، ');
    return Semantics(
      button: onTap != null,
      label: '${advSeverityLabel(i.severity)}: ${i.label}, ${i.count}${i.hint == null ? '' : '. ${i.hint}'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.chipAll,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs, horizontal: AppSpace.xxs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(advSeverityIcon(i.severity), color: appInk(context, col), size: AppIconSize.md)),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(i.label, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                    AppBadgePill(advSeverityLabel(i.severity), color: col),
                  ]),
                  if (i.hint != null) ...[const SizedBox(height: 2), Text(i.hint!, style: AppType.meta(context))],
                  if (sample.isNotEmpty) ...[const SizedBox(height: 2), Text(sample, style: AppType.meta(context).copyWith(color: c.textDark), maxLines: 2, overflow: TextOverflow.ellipsis)],
                ]),
              ),
              const SizedBox(width: AppSpace.sm),
              Text('${i.count}', textDirection: TextDirection.ltr, style: AppType.row(context).copyWith(fontWeight: FontWeight.w700, color: appInk(context, col))),
              SizedBox(width: AppIconSize.md + AppSpace.xxs, child: onTap == null ? null : Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Compliance (#25)
// ═════════════════════════════════════════════════════════════════════════════

/// The compliance report: the organization's row first, then each advisor; cards under 760 px, a table above.
class AdvComplianceTable extends StatelessWidget {
  const AdvComplianceTable({super.key, required this.report, this.onAdvisor});
  final AdvCompliance report;

  /// An advisor's row → their students (manage).
  final ValueChanged<AdvComplianceRow>? onAdvisor;

  @override
  Widget build(BuildContext context) {
    final rows = [?report.total, ...report.advisors];
    if (rows.isEmpty) {
      return AdvChartNote(t('لا مرشدين لهم طلاب في هذا الفصل.', 'No advisor had students in this term.'));
    }
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 760) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final r in rows) _ComplianceCard(row: r, report: report, onTap: onAdvisor == null || r.total ? null : () => onAdvisor!(r)),
        ]);
      }
      return _ComplianceGrid(rows: rows, report: report, onAdvisor: onAdvisor);
    });
  }
}

String _cnt(int? v) => v == null ? '<5' : '$v';

Widget _targetPill(BuildContext context, bool? meets) {
  final c = context.colors;
  if (meets == null) return AppBadgePill(t('لا يُحكم', 'Not judged'), color: c.textMedium);
  return meets ? AppBadgePill(t('يحقق الهدف', 'Meets target'), color: c.success, icon: Icons.check_rounded) : AppBadgePill(t('دون الهدف', 'Below target'), color: c.danger, icon: Icons.priority_high_rounded);
}

class _ComplianceCard extends StatelessWidget {
  const _ComplianceCard({required this.row, required this.report, this.onTap});
  final AdvComplianceRow row;
  final AdvCompliance report;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = row;
    final cov = r.coveragePct;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Semantics(
        button: onTap != null,
        child: Material(
          color: r.total ? c.primaryTint : c.inputBg,
          borderRadius: AppRadius.chipAll,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.chipAll,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(r.shown, style: AppType.row(context).copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: AppSpace.xs),
                  if (!r.total) _targetPill(context, r.meetsTarget),
                ]),
                const SizedBox(height: AppSpace.xs),
                Row(children: [
                  Expanded(
                    child: AppProgressBar(value: cov ?? 0, color: cov == null ? c.textLight : (cov >= report.targetCoveragePct ? c.success : c.warning), marker: report.targetCoveragePct, height: 6),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Text(cov == null ? '—' : advRate(cov), textDirection: TextDirection.ltr, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w700, color: c.textDark)),
                ]),
                Text(t('تواصل مع ${_cnt(r.contacted)} من ${_cnt(r.advisees)}', 'Contacted ${_cnt(r.contacted)} of ${_cnt(r.advisees)}'), style: AppType.meta(context)),
                const SizedBox(height: AppSpace.xs),
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                  AdvMiniStat(label: t('تواصل لكل طالب', 'Contacts per student'), value: advFigure(r.contactsPerStudent)),
                  AdvMiniStat(label: t('لقاءات تمت', 'Meetings held'), value: '${r.meetingsCompleted}'),
                  AdvMiniStat(label: t('أول تواصل بعد', 'First contact after'), value: advDays(r.avgFirstContactDays)),
                  AdvMiniStat(label: t('متوسط زمن الرد', 'Average reply time'), value: advHours(r.avgResponseHours)),
                  AdvMiniStat(label: t('معرّضون تواصل معهم', 'At risk contacted'), value: '${_cnt(r.atRiskContacted)} / ${_cnt(r.atRisk)}'),
                  AdvMiniStat(label: t('تغير معدل المدعومين', 'Supported GPA change'), value: r.supportedGpaChange == null ? '' : advSigned(r.supportedGpaChange!)),
                  AdvMiniStat(label: t('الاستمرار', 'Retention'), value: advRate(r.retainedPct)),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComplianceGrid extends StatelessWidget {
  const _ComplianceGrid({required this.rows, required this.report, this.onAdvisor});
  final List<AdvComplianceRow> rows;
  final AdvCompliance report;
  final ValueChanged<AdvComplianceRow>? onAdvisor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final head = AppType.meta(context).copyWith(fontWeight: FontWeight.w700, color: c.textMedium);
    final cell = AppType.row(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final cols = <(String, double, String Function(AdvComplianceRow))>[
      (t('الطلاب', 'Advisees'), 80, (r) => _cnt(r.advisees)),
      (t('تواصل معهم', 'Contacted'), 90, (r) => _cnt(r.contacted)),
      (t('التغطية', 'Coverage'), 84, (r) => r.coveragePct == null ? '—' : advRate(r.coveragePct)),
      (t('تواصل/طالب', 'Contacts / student'), 110, (r) => r.contactsPerStudent == null ? '—' : advFigure(r.contactsPerStudent)),
      (t('لقاءات', 'Meetings'), 80, (r) => '${r.meetingsCompleted}'),
      (t('غياب', 'No-shows'), 80, (r) => '${r.noShows}'),
      (t('تنبيهات أُغلقت', 'Alerts resolved'), 110, (r) => '${r.alertsResolved} / ${r.alerts}'),
      (t('أول تواصل', 'First contact'), 96, (r) => r.avgFirstContactDays == null ? '—' : advDays(r.avgFirstContactDays)),
      (t('زمن الرد', 'Reply time'), 90, (r) => r.avgResponseHours == null ? '—' : advHours(r.avgResponseHours)),
      (t('معرّضون تواصل', 'At risk contacted'), 120, (r) => '${_cnt(r.atRiskContacted)} / ${_cnt(r.atRisk)}'),
      (t('تغير المعدل', 'GPA change'), 96, (r) => r.supportedGpaChange == null ? '—' : advSigned(r.supportedGpaChange!)),
      (t('الاستمرار', 'Retention'), 90, (r) => r.retainedPct == null ? '—' : advRate(r.retainedPct)),
    ];
    const nameW = 200.0, targetW = 130.0;
    final width = nameW + targetW + cols.fold<double>(0, (a, x) => a + x.$2);
    Widget row(AdvComplianceRow? r) {
      final cells = <Widget>[
        SizedBox(
          width: nameW,
          child: r == null ? Text(t('المرشد', 'Advisor'), style: head) : Text(r.shown, textDirection: advTextDirection(r.shown), style: cell.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        for (final (label, w, f) in cols)
          SizedBox(
            width: w,
            child: Text(r == null ? label : f(r), style: r == null ? head : cell, textAlign: TextAlign.center, textDirection: r == null ? null : TextDirection.ltr, maxLines: 2),
          ),
        SizedBox(width: targetW, child: r == null ? Text(t('الهدف', 'Target'), style: head, textAlign: TextAlign.center) : Center(child: r.total ? const SizedBox.shrink() : _targetPill(context, r.meetsTarget))),
      ];
      final body = ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xs), child: Row(children: cells)),
      );
      if (r == null) return body;
      return Material(
        color: r.total ? c.primaryTint : Colors.transparent,
        borderRadius: AppRadius.chipAll,
        child: InkWell(borderRadius: AppRadius.chipAll, onTap: onAdvisor == null || r.total ? null : () => onAdvisor!(r), child: body),
      );
    }

    return AppHScroll(
      child: SizedBox(
        width: width + AppSpace.md,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          row(null),
          Divider(height: 1, color: c.divider),
          for (final r in rows) ...[row(r), Divider(height: 1, color: c.divider)],
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Advisors table row
// ═════════════════════════════════════════════════════════════════════════════

/// One advisor's figures as a card (phones; the table on wide screens uses the same values).
class AdvAdvisorStatRow extends StatelessWidget {
  const AdvAdvisorStatRow({super.key, required this.stat, this.onTap});
  final AdvAdvisorStat stat;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = stat;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Semantics(
        button: onTap != null,
        label: '${a.shown}, ${t('الحمل ${a.load} من ${a.maxLoad}', 'load ${a.load} of ${a.maxLoad}')}, ${a.active ? t('نشط', 'active') : t('غير نشط', 'inactive')}',
        child: AppCard(
          onTap: onTap,
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              ExcludeSemantics(child: AppAvatar(name: a.shown, size: 40)),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.shown, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    a.lastActiveAt == null ? t('لا نشاط مسجل', 'No activity yet') : t('آخر نشاط ${advDate(a.lastActiveAt)}', 'Last active ${advDate(a.lastActiveAt)}'),
                    style: AppType.meta(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
              a.active ? AppBadgePill(t('نشط', 'Active'), color: c.success, icon: Icons.bolt_rounded) : AppBadgePill(t('غير نشط', 'Inactive'), color: c.textMedium, icon: Icons.bedtime_outlined),
              if (a.status != 'available' || a.away) AdvStatusPill(status: a.status, away: a.away),
            ]),
            const SizedBox(height: AppSpace.xs),
            AdvLoadBar(load: a.load, max: a.maxLoad, warn: a.warn, over: a.over),
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              AdvMiniStat(label: t('معرّضون للخطر', 'At risk'), value: _cnt(a.atRisk), tone: (a.atRisk ?? 0) > 0 ? c.danger : null),
              AdvMiniStat(label: t('بلا تواصل', 'No contact'), value: _cnt(a.noContactTerm), tone: (a.noContactTerm ?? 0) > 0 ? c.warning : null),
              AdvMiniStat(label: t('لقاءات', 'Meetings'), value: '${a.meetingsCompleted}'),
              AdvMiniStat(label: t('نسبة الغياب', 'No-show rate'), value: advRate(a.noShowRate)),
              AdvMiniStat(label: t('زمن الرد', 'Reply time'), value: advHours(a.avgResponseHours)),
              AdvMiniStat(label: t('ردود في الموعد', 'On time'), value: advRate(a.slaMetPct)),
              AdvMiniStat(label: t('ملاحظات', 'Notes'), value: '${a.notes}'),
            ]),
          ]),
        ),
      ),
    );
  }
}

String advAdvisorStatusText(AdvAdvisorStat a) => a.away && a.status == 'available' ? t('غير متاح', 'Away') : advStatusLabel(a.status);

// ═════════════════════════════════════════════════════════════════════════════
//  Outreach card
// ═════════════════════════════════════════════════════════════════════════════

Color advOutreachStatusColor(BuildContext context, String s) {
  final c = context.colors;
  return switch (s) {
    'sent' => c.success,
    'failed' => c.danger,
    'sending' => c.primary,
    _ => c.textMedium,
  };
}

/// One sent group message: subject, audience, sender and date, status, delivered / read with the read-rate bar.
class AdvOutreachCard extends StatelessWidget {
  const AdvOutreachCard({super.key, required this.outreach, this.onTap, this.showSender = false});
  final AdvOutreach outreach;
  final VoidCallback? onTap;

  /// Directors see every sender's messages.
  final bool showSender;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = outreach;
    final meta = [
      if (showSender && o.sender != null) o.sender!.shown,
      if (o.createdAt != null) AppTime.dateTime(o.createdAt!),
      if (o.email) t('مع بريد إلكتروني', 'with e-mail'),
    ].join(' · ');
    final rate = o.readRate;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Semantics(
        button: onTap != null,
        label: '${o.subject}, ${advOutreachStatusLabel(o.status)}, ${advStudentsText(o.recipients)}${rate == null ? '' : ', ${t('قرأها', 'read')} ${advRate(rate)}'}',
        child: AppCard(
          onTap: onTap,
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: AdvTypedText(o.subject.isEmpty ? '—' : o.subject, maxLines: 2, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600))),
              const SizedBox(width: AppSpace.xs),
              AppBadgePill(advOutreachStatusLabel(o.status), color: advOutreachStatusColor(context, o.status)),
            ]),
            if (o.label.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(children: [
                Icon(Icons.groups_outlined, size: AppIconSize.xs, color: c.textLight),
                const SizedBox(width: AppSpace.xxs),
                Expanded(child: Text(o.label, style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ],
            if (meta.isNotEmpty) Text(meta, style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: AppSpace.xs),
            Row(children: [
              Expanded(child: AppProgressBar(value: rate ?? 0, height: 6, color: appChartPalette(context).first)),
              const SizedBox(width: AppSpace.sm),
              Text(rate == null ? '—' : advRate(rate), textDirection: TextDirection.ltr, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w700, color: c.textDark)),
            ]),
            const SizedBox(height: AppSpace.xxs),
            Text(
              [
                advStudentsText(o.recipients),
                t('قرأها ${o.read}', '${o.read} read'),
                if (o.failed > 0) t('لم تصل ${o.failed}', '${o.failed} not delivered'),
                if (o.capped > 0) t('تجاوزوا الحد الأسبوعي ${o.capped}', '${o.capped} over the weekly limit'),
              ].join(' · '),
              style: AppType.meta(context),
            ),
          ]),
        ),
      ),
    );
  }
}

/// [AdvRef] of a load-top advisor (the drill's advisor filter).
AdvRef advRefOf(AdvLoadTop a) => AdvRef(userId: a.userId, name: a.name);
