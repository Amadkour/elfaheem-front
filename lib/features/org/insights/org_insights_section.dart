// lib/features/org/insights/org_insights_section.dart
//
// The Insights section of the organization home (D-103, spec §4): a few clear, touchable charts, not many.
//
//   OrgInsightsSection(orgId:, onOpenLink:, fallback:)   the live section: kill switch `org.insights`; loads after
//                         the home's first frame (never blocking its one dashboard call), the period the person last
//                         picked for this organization first (device-local); skeleton → cards, friendly error + Retry;
//                         403 → nothing; an older server (bare 404) → [fallback] (the old 30-day trends)
//   OrgInsightsView       presentational, plain values (test/ui/org_insights_layout_test.dart, renders in
//                         test/visual/org_insights_golden_test.dart): the period chips (This term · Last term ·
//                         Last 30 days · Custom) and the period line, ≤ 4 OrgInsightCards, the suggestions
//   OrgInsightCard        label · big figure · the change pill · the touchable line (tap / hover shows that day's
//                         value) · ONE summary sentence written in the app (org_insights.dart)
//   OrgSuggestionRow      severity dot · a plain sentence · ONE button that jumps to the fix
//   openOrgInsightLink    the default jump: the shell's section / sub-page (orgJump), a timetable by id
// Colours: context.colors · spacing / radii / motion: app_tokens.dart · charts: app_charts.dart · texts: t(ar, en).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_charts.dart' show AppSparkline, appChartPalette, appInk;
import 'package:flutter_education_app/design/app_kit.dart' show AppShimmer, AppSkeletonBox, appText;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/home_kit.dart' show HomeSection;
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../admin/admin_common.dart' show t;
import '../org_dashboard_home.dart' show orgJump;
import 'org_insights.dart';
import 'org_insights_api.dart';

/// The kill switch (feature catalog: ../back/services/feature_catalog.py).
const orgInsightsFeatureKey = 'org.insights';

/// False while the super admin / the organization has switched Insights off.
bool get orgInsightsEnabled => !AppConfig.disableList.contains(orgInsightsFeatureKey);

/// The default jump for a suggestion: the shell's section / sub-page, or a timetable by id. Needs the org shell's
/// providers above [context] (OrgTabs, OrgSession, OrgDashController); does nothing without them.
Future<void> openOrgInsightLink(BuildContext context, OrgInsightLink link) async {
  final target = orgInsightTarget(link);
  if (target == null) return;
  try {
    await orgJump(context, target.$1, sub: target.$2);
  } catch (_) {
    // not inside the org shell (a test, a page without the shell's providers): nothing to jump to
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The live section
// ═════════════════════════════════════════════════════════════════════════════

class OrgInsightsSection extends StatefulWidget {
  const OrgInsightsSection({super.key, required this.orgId, this.onOpenLink, this.fallback, this.source});

  final int? orgId;

  /// A suggestion's button; default [openOrgInsightLink].
  final void Function(OrgInsightLink link)? onOpenLink;

  /// Drawn when the server has no insights route yet (the old 30-day OrgTrendRow), else nothing.
  final Widget? fallback;

  /// Replaces the real call (tests, renders).
  final OrgInsightsSource? source;

  @override
  State<OrgInsightsSection> createState() => _OrgInsightsSectionState();
}

class _OrgInsightsSectionState extends State<OrgInsightsSection> {
  OrgInsightsLoad? _load;
  OrgPeriodChoice? _choice;
  bool _busy = false;
  int _seq = 0;

  ScrollPosition? _watched;

  @override
  void initState() {
    super.initState();
    // after the home's first frame (the dashboard call goes first), and only once the section is on screen: below
    // the fold (staff and members see it last on a phone) it waits for the first scroll that brings it in
    WidgetsBinding.instance.addPostFrameCallback((_) => _whenVisible());
  }

  @override
  void dispose() {
    _watched?.removeListener(_onScroll);
    super.dispose();
  }

  /// The section's top is inside the viewport (or within 200 px of its bottom edge).
  bool _visible() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final top = box.localToGlobal(Offset.zero).dy;
    return top < MediaQuery.sizeOf(context).height + 200;
  }

  void _whenVisible() {
    if (!mounted) return;
    final pos = Scrollable.maybeOf(context)?.position;
    if (pos == null || _visible()) {
      _start();
      return;
    }
    _watched = pos..addListener(_onScroll);
  }

  void _onScroll() {
    if (!mounted || !_visible()) return;
    _watched?.removeListener(_onScroll);
    _watched = null;
    _start();
  }

  @override
  void didUpdateWidget(OrgInsightsSection old) {
    super.didUpdateWidget(old);
    if (old.orgId != widget.orgId) {
      _load = null;
      _choice = null;
      _start();
    }
  }

  Future<void> _start() async {
    final id = widget.orgId;
    if (id == null || !mounted) return;
    final saved = await OrgInsightsPrefs.read(id);
    if (!mounted || widget.orgId != id) return;
    _choice = saved;
    await _fetch();
  }

  DateTime get _today => orgInsightsToday();

  Future<void> _fetch() async {
    final id = widget.orgId;
    if (id == null) return;
    if (!mounted) return;
    final seq = ++_seq;
    setState(() => _busy = true);
    final terms = _load?.data?.terms ?? const <OrgInsightTerm>[];
    // a saved term choice needs the terms: the first answer (server default) brings them, then it is asked again
    final q = _choice?.query(terms, _today);
    final src = widget.source ?? (int o, Map<String, String>? query) => OrgInsightsPrefetch.loadShared(o, query);
    var r = await src(id, q);
    if (r.badPeriod && q != null) {
      _choice = null;
      await OrgInsightsPrefs.write(id, null);
      r = await src(id, null);
    }
    if (!mounted || seq != _seq) return;
    setState(() {
      _busy = false;
      // a failed reload keeps the figures on screen and toasts nothing: the error card replaces them only at first
      if (r.ok || _load?.data == null) _load = r;
    });
    final d = r.data;
    if (d != null && _choice != null && q == null) {
      // the saved term choice, now that the terms are known — unless the default already is that term; a choice
      // these terms cannot satisfy (This term while none runs) is dropped
      final again = _choice!.query(d.terms, _today);
      if (again == null) {
        setState(() => _choice = null);
      } else if (again['term_id'] == null || again['term_id'] != '${d.period.termId}') {
        await _fetch();
      }
    }
  }

  Future<void> _pick(OrgPeriodKind kind) async {
    final id = widget.orgId;
    if (id == null) return;
    OrgPeriodChoice? next;
    if (kind == OrgPeriodKind.custom) {
      final today = _today;
      final first = DateTime(today.year - 2, today.month, today.day + 1);
      final cur = _choice?.kind == OrgPeriodKind.custom ? _choice : null;
      final range = await showDateRangePicker(
        context: context,
        firstDate: first,
        lastDate: DateTime(today.year, today.month, today.day),
        initialDateRange: cur == null
            ? DateTimeRange(start: DateTime(today.year, today.month, today.day - 29), end: DateTime(today.year, today.month, today.day))
            : DateTimeRange(start: DateTime(cur.from!.year, cur.from!.month, cur.from!.day), end: DateTime(cur.to!.year, cur.to!.month, cur.to!.day)),
        helpText: t('اختر الفترة', 'Choose the period'),
      );
      if (range == null || !mounted) return;
      next = OrgPeriodChoice(kind,
          from: DateTime.utc(range.start.year, range.start.month, range.start.day),
          to: DateTime.utc(range.end.year, range.end.month, range.end.day));
    } else {
      next = OrgPeriodChoice(kind);
    }
    if (next == _choice) return;
    _choice = next;
    await OrgInsightsPrefs.write(id, next);
    await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final r = _load;
    final Widget body;
    if (widget.orgId == null || (r != null && r.forbidden)) {
      body = const SizedBox.shrink();
    } else if (r != null && r.missing) {
      body = widget.fallback ?? const SizedBox.shrink();
    } else {
      body = OrgInsightsView(
        data: r?.data,
        error: r?.data == null ? r?.error : null,
        loading: r == null,
        refreshing: _busy && r?.data != null,
        selected: r?.data == null ? _choice?.kind : orgPeriodKindOf(r!.data!, _choice),
        custom: _choice?.kind == OrgPeriodKind.custom ? _choice : null,
        onPick: _pick,
        onRetry: _fetch,
        onOpenLink: widget.onOpenLink ?? (l) => openOrgInsightLink(context, l),
      );
    }
    // the home's slot spaces the sections BEFORE each one, never after Insights: the gap below is ours, and only
    // when something is drawn, so an empty slot leaves no hole and both desktop columns start on the same line
    return ParentComponent(
      featureKey: orgInsightsFeatureKey,
      child: body is SizedBox ? body : Padding(padding: const EdgeInsets.only(bottom: AppSpace.lg), child: body),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The view (plain values)
// ═════════════════════════════════════════════════════════════════════════════

class OrgInsightsView extends StatelessWidget {
  const OrgInsightsView({
    super.key,
    this.data,
    this.error,
    this.loading = false,
    this.refreshing = false,
    this.selected,
    this.custom,
    this.onPick,
    this.onRetry,
    this.onOpenLink,
  });

  final OrgInsights? data;

  /// First load failed (friendly text) → the error card with Retry.
  final String? error;
  final bool loading;

  /// A new period is loading while the old figures stay.
  final bool refreshing;
  final OrgPeriodKind? selected;

  /// The custom range, when that chip is the selected one (its label shows the dates).
  final OrgPeriodChoice? custom;
  final void Function(OrgPeriodKind kind)? onPick;
  final VoidCallback? onRetry;
  final void Function(OrgInsightLink link)? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final cards = d == null ? const <OrgInsightMetric>[] : orgInsightCards(d);
    final kinds = d == null ? const [OrgPeriodKind.last30, OrgPeriodKind.custom] : orgPeriodKinds(d.terms);
    final line = d == null ? '' : orgPeriodLine(d.period);
    final scope = d != null && !d.orgWide ? t('أقسامك فقط', 'Your departments only') : null;
    final motion = AppMotion.of(context);
    final Widget content;
    if (d == null && error != null) {
      content = _InsightsError(message: error!, onRetry: onRetry);
    } else if (d == null) {
      content = const _InsightsSkeleton();
    } else {
      content = AnimatedOpacity(
        duration: motion.fast,
        opacity: refreshing ? 0.55 : 1,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          if (cards.isEmpty)
            _InsightsNothing(period: d.period)
          else
            _CardGrid(children: [for (final m in cards) OrgInsightCard(metric: m, period: d.period)]),
          if (d.suggestions.isNotEmpty) ...[
            AppSpace.gapLg,
            Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpace.md, end: AppSpace.md, bottom: AppSpace.xs),
              child: Text(t('اقتراحات', 'Suggestions'), style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
            ),
            _RowsCard(children: [
              for (final s in d.suggestions)
                OrgSuggestionRow(
                  text: orgSuggestionText(s, d),
                  action: orgSuggestionAction(s),
                  risk: s.isRisk,
                  onTap: onOpenLink == null || orgInsightTarget(s.link) == null ? null : () => onOpenLink!(s.link),
                ),
            ]),
          ],
        ]),
      );
    }
    final selectedLabel = selected == null ? null : _chipLabel(selected!, custom);
    return HomeSection(
      id: 'org.insights',
      title: t('المؤشرات', 'Insights'),
      foldedSummary: selectedLabel,
      titlePadding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, 0, AppSpace.xs, AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        _PeriodChips(kinds: kinds, selected: selected, custom: custom, onPick: d == null ? null : onPick),
        if (line.isNotEmpty || scope != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xxs, AppSpace.md, 0),
            child: Text(
              [if (line.isNotEmpty) line, ?scope].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context),
            ),
          ),
        SizedBox(
          height: AppSpace.sm,
          child: refreshing
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 5),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: context.colors.primary,
                      backgroundColor: context.colors.divider,
                    ),
                  ),
                )
              : null,
        ),
        content,
      ]),
    );
  }
}

String _chipLabel(OrgPeriodKind k, OrgPeriodChoice? custom) =>
    k == OrgPeriodKind.custom && custom?.from != null && custom?.to != null
        ? orgRangeLabel(custom!.from!, custom.to!)
        : orgPeriodKindLabel(k);

// ── period chips ────────────────────────────────────────────────────────────

class _PeriodChips extends StatelessWidget {
  const _PeriodChips({required this.kinds, required this.selected, required this.custom, required this.onPick});
  final List<OrgPeriodKind> kinds;
  final OrgPeriodKind? selected;
  final OrgPeriodChoice? custom;
  final void Function(OrgPeriodKind kind)? onPick;

  @override
  Widget build(BuildContext context) {
    // a phone: "Custom" is its calendar icon until a range is picked, so the four chips fit one line
    final narrow = MediaQuery.sizeOf(context).width < 480;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      child: Row(children: [
        for (var i = 0; i < kinds.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpace.xs - 2),
          _PeriodChip(
            label: kinds[i] == OrgPeriodKind.custom && narrow && selected != OrgPeriodKind.custom
                ? null
                : _chipLabel(kinds[i], custom),
            tooltip: orgPeriodKindLabel(kinds[i]),
            icon: kinds[i] == OrgPeriodKind.custom ? Icons.date_range_rounded : null,
            selected: kinds[i] == selected,
            onTap: onPick == null ? null : () => onPick!(kinds[i]),
          ),
        ],
      ]),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.label, required this.tooltip, required this.selected, this.icon, this.onTap});

  /// null = the icon alone (its [tooltip] is the label for screen readers and the mouse).
  final String? label;
  final String tooltip;
  final bool selected;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = selected ? appInk(context, c.primary) : c.textMedium;
    final chip = Semantics(
      button: true,
      selected: selected,
      label: label == null ? tooltip : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: AppTouch.min, minWidth: label == null ? AppTouch.min : 0),
        child: Center(
          widthFactor: 1,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(999),
              child: AnimatedContainer(
                duration: AppMotion.of(context).fast,
                constraints: const BoxConstraints(minHeight: 36),
                padding: EdgeInsets.symmetric(horizontal: label == null ? 10 : 14, vertical: 7),
                decoration: BoxDecoration(
                  color: selected ? c.primary.withValues(alpha: c.isDark ? 0.22 : 0.10) : c.cardBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: selected ? c.primary.withValues(alpha: 0.55) : c.divider),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) Icon(icon, size: 16, color: ink),
                  if (icon != null && label != null) const SizedBox(width: 6),
                  if (label != null)
                    Text(label!, style: appText(13, w: selected ? FontWeight.w600 : FontWeight.w500, c: selected ? ink : c.textDark)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
    return label == null ? Tooltip(message: tooltip, child: chip) : chip;
  }
}

// ── the cards ───────────────────────────────────────────────────────────────

/// Equal-height rows of cards: 1 column on phones, 2 from 440 px (a desktop home column), 3 from 760 px, 4 from 1000 px.
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final cols = math.min(children.length, w >= 1000 ? 4 : (w >= 760 ? 3 : (w >= 440 ? 2 : 1))).clamp(1, 4);
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += cols) {
          final slice = children.sublist(i, math.min(i + cols, children.length));
          rows.add(IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // a short last row shares the full width (3 cards on 2 columns: the third spans)
              for (var j = 0; j < slice.length; j++) ...[
                if (j > 0) const SizedBox(width: AppSpace.sm),
                Expanded(child: slice[j]),
              ],
            ]),
          ));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < rows.length; i++) ...[if (i > 0) const SizedBox(height: AppSpace.sm), rows[i]],
        ]);
      }),
    );
  }
}

/// The metric's chart colour: the palette slot it always wears (attendance teal, enrollment primary …).
Color orgInsightColor(BuildContext context, String key) {
  final p = appChartPalette(context);
  final i = switch (key) { 'attendance' => 2, 'enrollment' => 0, 'completion' => 1, 'grades' => 3, 'pending' => 4, _ => 0 };
  return p[i % p.length];
}

IconData orgInsightIcon(String key) => switch (key) {
      'attendance' => Icons.fact_check_outlined,
      'enrollment' => Icons.person_add_alt_1_outlined,
      'completion' => Icons.workspace_premium_outlined,
      'grades' => Icons.grade_outlined,
      'pending' => Icons.hourglass_empty_rounded,
      _ => Icons.insights_rounded,
    };

class OrgInsightCard extends StatelessWidget {
  const OrgInsightCard({super.key, required this.metric, required this.period});
  final OrgInsightMetric metric;
  final OrgInsightPeriod period;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = metric;
    final tone = orgInsightColor(context, m.key);
    final change = orgInsightChange(m);
    final summary = orgInsightSummary(m, period);
    final points = m.points;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.md),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.divider),
        boxShadow: AppShadow.card(context),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: tone.withValues(alpha: c.isDark ? 0.22 : 0.12), shape: BoxShape.circle),
            child: Icon(orgInsightIcon(m.key), size: 16, color: appInk(context, tone)),
          ),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(orgInsightLabel(m.key),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w500)),
          ),
        ]),
        const SizedBox(height: AppSpace.xs),
        Semantics(
          label: summary,
          excludeSemantics: true,
          child: Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(orgInsightFigure(m),
                  textDirection: TextDirection.ltr,
                  style: appText(28, w: FontWeight.w600, c: c.textDark, h: 1.1)),
              if (change != null) _ChangePill(change: change),
            ],
          ),
        ),
        if (points.length >= 2) ...[
          const SizedBox(height: AppSpace.sm),
          OrgInsightChart(metric: m, color: tone, granularity: period.granularity),
        ],
        const SizedBox(height: AppSpace.sm),
        ExcludeSemantics(
          child: Text(summary, maxLines: 3, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w400, c: c.textMedium, h: 1.4)),
        ),
      ]),
    );
  }
}

class _ChangePill extends StatelessWidget {
  const _ChangePill({required this.change});
  final OrgInsightChange change;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = change.good == null ? c.textLight : (change.good! ? c.success : c.danger);
    final icon = change.direction > 0
        ? Icons.arrow_upward_rounded
        : (change.direction < 0 ? Icons.arrow_downward_rounded : Icons.remove_rounded);
    final ink = change.good == null ? c.textMedium : appInk(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: tone.withValues(alpha: c.isDark ? 0.20 : 0.12), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: ink),
        const SizedBox(width: 3),
        Text(change.short, style: appText(12, w: FontWeight.w600, c: ink)),
      ]),
    );
  }
}

/// The metric's line (AppSparkline) made touchable: tap / hover / drag shows that day's value in the read-out above
/// it (default: the last point) and marks the point with a guide and a dot. Days without data are left out.
class OrgInsightChart extends StatefulWidget {
  const OrgInsightChart({super.key, required this.metric, required this.color, this.granularity = 'day', this.height = 44});
  final OrgInsightMetric metric;
  final Color color;
  final String granularity;
  final double height;

  @override
  State<OrgInsightChart> createState() => _OrgInsightChartState();
}

class _OrgInsightChartState extends State<OrgInsightChart> {
  int? _hot;

  /// Same geometry as AppSparkline's painter (5 px pad, first point at the reading start).
  static const _pad = 5.0;

  int? _indexAt(double dx, double width, int n, bool rtl) {
    if (n < 2 || width <= _pad * 2) return null;
    var t = ((dx - _pad) / (width - _pad * 2)).clamp(0.0, 1.0);
    if (rtl) t = 1 - t;
    return (t * (n - 1)).round();
  }

  void _at(Offset local, int n, bool rtl) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final i = _indexAt(local.dx, box.size.width, n, rtl);
    if (i != _hot) setState(() => _hot = i);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pts = widget.metric.points;
    final values = [for (final p in pts) p.value!];
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final hot = _hot == null || _hot! >= pts.length ? null : _hot;
    final shown = pts[hot ?? pts.length - 1];
    final (day, fig) = orgInsightPointParts(shown, widget.metric, granularity: widget.granularity);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        label: '$day · $fig',
        excludeSemantics: true,
        child: Row(children: [
          Flexible(child: Text(day, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, w: hot == null ? FontWeight.w400 : FontWeight.w600, c: hot == null ? c.textLight : c.textDark))),
          Text(' · ', style: appText(12, w: hot == null ? FontWeight.w400 : FontWeight.w600, c: hot == null ? c.textLight : c.textDark)),
          Text(fig, textDirection: TextDirection.ltr, style: appText(12, w: hot == null ? FontWeight.w400 : FontWeight.w600, c: hot == null ? c.textLight : c.textDark)),
        ]),
      ),
      const SizedBox(height: AppSpace.xxs),
      MouseRegion(
        onHover: (e) => _at(e.localPosition, pts.length, rtl),
        onExit: (_) => setState(() => _hot = null),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (e) => _at(e.localPosition, pts.length, rtl),
          onHorizontalDragUpdate: (e) => _at(e.localPosition, pts.length, rtl),
          child: SizedBox(
            height: widget.height,
            child: Stack(fit: StackFit.expand, children: [
              AppSparkline(values, color: widget.color, height: widget.height, label: orgInsightLabel(widget.metric.key)),
              if (hot != null)
                IgnorePointer(
                  child: CustomPaint(
                    painter: _HotPainter(index: hot, values: values, color: widget.color, surface: c.cardBg, guide: c.divider, rtl: rtl),
                  ),
                ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _HotPainter extends CustomPainter {
  _HotPainter({required this.index, required this.values, required this.color, required this.surface, required this.guide, required this.rtl});
  final int index;
  final List<double> values;
  final Color color, surface, guide;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n < 2 || size.width <= 0) return;
    const pad = 5.0;
    final lo = values.reduce(math.min), hi = values.reduce(math.max);
    final w = size.width - pad * 2, h = size.height - pad * 2;
    final tt = index / (n - 1);
    final x = pad + (rtl ? 1 - tt : tt) * w;
    final y = hi == lo ? pad + h / 2 : pad + h - (values[index] - lo) / (hi - lo) * h;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()
      ..color = guide
      ..strokeWidth = 1);
    canvas.drawCircle(Offset(x, y), 6, Paint()..color = surface);
    canvas.drawCircle(Offset(x, y), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HotPainter o) => o.index != index || o.values != values || o.color != color || o.rtl != rtl;
}

// ── suggestions ─────────────────────────────────────────────────────────────

class _RowsCard extends StatelessWidget {
  const _RowsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.divider),
        boxShadow: AppShadow.card(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, indent: AppSpace.md, endIndent: AppSpace.md, color: c.divider),
          children[i],
        ],
      ]),
    );
  }
}

class OrgSuggestionRow extends StatelessWidget {
  const OrgSuggestionRow({super.key, required this.text, required this.action, this.risk = false, this.onTap});
  final String text, action;

  /// risk = a red dot, watch = an amber one.
  final bool risk;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dot = Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(color: risk ? c.danger : c.warning, shape: BoxShape.circle),
    );
    final sentence = Text(text, style: appText(14, w: FontWeight.w500, c: c.textDark, h: 1.45));
    final button = onTap == null
        ? null
        : OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: appInk(context, c.primary),
              side: BorderSide(color: c.primary.withValues(alpha: 0.45)),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              textStyle: appText(13, w: FontWeight.w600),
            ),
            child: Text(action, maxLines: 1, overflow: TextOverflow.ellipsis),
          );
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.sm, AppSpace.sm),
        child: LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < 460 || button == null) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                dot,
                const SizedBox(width: AppSpace.sm),
                Expanded(child: sentence),
              ]),
              if (button != null)
                Align(alignment: AlignmentDirectional.centerEnd, child: Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: button)),
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Padding(padding: const EdgeInsets.only(bottom: 6), child: dot),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: sentence),
            const SizedBox(width: AppSpace.sm),
            ConstrainedBox(constraints: BoxConstraints(maxWidth: box.maxWidth * 0.4), child: button),
          ]);
        }),
      ),
    );
  }
}

// ── states ──────────────────────────────────────────────────────────────────

class _InsightsSkeleton extends StatelessWidget {
  const _InsightsSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget card() => Container(
          height: 168,
          padding: AppSpace.card,
          decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppSkeletonBox(width: 110, height: 12),
            SizedBox(height: AppSpace.sm),
            AppSkeletonBox(width: 80, height: 26),
            Spacer(),
            AppSkeletonBox(height: 34, radius: 10),
            SizedBox(height: AppSpace.sm),
            AppSkeletonBox(height: 10),
          ]),
        );
    return Semantics(
      label: t('جارٍ تحميل المؤشرات', 'Loading insights'),
      child: AppShimmer(child: _CardGrid(children: [card(), card(), card(), card()])),
    );
  }
}

class _InsightsError extends StatelessWidget {
  const _InsightsError({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      padding: AppSpace.card,
      decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.cloud_off_rounded, size: 22, color: c.textLight),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(t('تعذّر تحميل المؤشرات الآن', 'Couldn\'t load the insights right now'), style: AppType.row(context)),
              const SizedBox(height: 2),
              Text(message, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ]),
          ),
        ]),
        if (onRetry != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(t('إعادة المحاولة', 'Retry')),
            ),
          ),
      ]),
    );
  }
}

class _InsightsNothing extends StatelessWidget {
  const _InsightsNothing({required this.period});
  final OrgInsightPeriod period;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      padding: AppSpace.card,
      decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
      child: Row(children: [
        Icon(Icons.insights_rounded, size: 22, color: c.textLight),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(
            t('لا توجد أرقام لهذه الفترة بعد — جرّب فترة أخرى.', 'No figures for this period yet — try another period.'),
            style: AppType.meta(context),
          ),
        ),
      ]),
    );
  }
}
