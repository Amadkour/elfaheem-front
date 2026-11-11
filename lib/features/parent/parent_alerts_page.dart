// lib/features/parent/parent_alerts_page.dart
// "Alerts" tab — flags about the children that need attention.
// Order: priority (high → medium → low), then newest first. A toggle switches to "newest first".
// Tap = mark read · swipe or ⋮ = dismiss (undo available) · "View report" opens the child's report.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import 'parent_link_providers.dart';
import 'parent_reports_page.dart';
import 'parent_widgets.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppCountUp, AppPressScale, AppReveal;
import 'package:flutter_education_app/design/app_bidi.dart' show ltrIsolate;
import 'parent_report_widgets.dart' show PlToneWell;

const _prios = ['high', 'medium', 'low'];

Color _prioColor(BuildContext context, String p) {
  final c = context.colors;
  return p == 'high' ? c.danger : (p == 'medium' ? c.warning : c.primary);
}

IconData _typeIcon(String t) {
  switch (t) {
    case 'failed_exam':
      return Icons.quiz_rounded;
    case 'score_drop':
      return Icons.trending_down_rounded;
    case 'missed_session':
      return Icons.event_busy_rounded;
    case 'missing_homework':
    case 'late_homework':
      return Icons.assignment_late_rounded;
    case 'homework_due_soon':
      return Icons.alarm_rounded;
    case 'low_attendance':
      return Icons.person_off_rounded;
    case 'late_arrival':
      return Icons.schedule_rounded;
    case 'left_early':
      return Icons.directions_run_rounded;
    case 'inactive':
    case 'inactive_long':
      return Icons.pause_circle_rounded;
    case 'course_expiring':
      return Icons.hourglass_bottom_rounded;
    default:
      return Icons.bookmark_rounded; // weak_backlog
  }
}

/// "3 days ago", "in 5 hours" …
String _ago(dynamic iso) {
  final d = DateTime.tryParse('$iso')?.toLocal();
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.isNegative) {
    final h = (-diff.inMinutes / 60).ceil();
    return h < 24 ? plFmt('pl_in_hours', {'n': h}) : plFmt('pl_in_days', {'n': (h / 24).ceil()});
  }
  if (diff.inMinutes < 60) return 'pl_just_now'.tr;
  if (diff.inHours < 24) return plFmt('pl_hours_ago', {'n': diff.inHours});
  if (diff.inDays == 1) return 'pl_yesterday'.tr;
  return plFmt('pl_days_ago', {'n': diff.inDays});
}

class ParentAlertsPage extends StatefulWidget {
  const ParentAlertsPage({super.key});

  @override
  State<ParentAlertsPage> createState() => _ParentAlertsPageState();
}

class _ParentAlertsPageState extends State<ParentAlertsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ParentAlertsProvider>().load(silent: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ParentAlertsProvider>();
    final kids = context.watch<ParentLinkProvider>().children;
    final c = context.colors;
    final list = p.visible;

    final sort = AppTabs(
      items: [AppTabItem('pl_sort_priority'.tr), AppTabItem('pl_sort_date'.tr)],
      index: p.sort == 'priority' ? 0 : 1,
      onChanged: (i) => p.setSort(i == 0 ? 'priority' : 'date'),
    );
    final narrow = MediaQuery.sizeOf(context).width < AppWidth.phoneMax;

    // a list of alerts reads best as one column, not stretched across a desktop window
    return AppWidthBox(
      width: AppWidth.reading,
      gutters: false,
      child: Column(children: [
      // ── filters: the three priority tiles are the page's one memorable element (a count per priority) ─────
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xxs, 0),
        child: Row(children: [
          for (final k in _prios)
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
                child: _PrioChip(
                  label: 'pl_prio_$k'.tr,
                  count: p.counts[k] ?? 0,
                  color: _prioColor(context, k),
                  selected: p.priority == k,
                  onTap: () => p.setPriority(k),
                ),
              ),
            ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: c.textMedium),
            onSelected: (v) {
              if (v == 'read') p.readAll();
              if (v == 'dismissed') p.toggleDismissed();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'read', child: Text('pl_mark_all_read'.tr)),
              PopupMenuItem(value: 'dismissed', child: Text(p.showDismissed ? 'pl_hide_dismissed'.tr : 'pl_show_dismissed'.tr)),
            ],
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxs),
        child: Row(children: [
          if (kids.length > 1)
            Expanded(
              child: DropdownButtonHideUnderline(
                child: AppDropdown<int?>(
                  isExpanded: true,
                  value: p.childId,
                  items: [
                    DropdownMenuItem<int?>(value: null, child: Text('pl_all_children'.tr)),
                    for (final k in kids) DropdownMenuItem<int?>(value: k['id'] as int, child: Text('${k['name']}', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: p.setChild,
                ),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: AppSpace.xs),
          // a phone shares the line (the strip scrolls if it must); a wide window keeps the strip at its own width
          if (narrow) Flexible(child: sort) else sort,
        ]),
      ),
      Expanded(
        child: !p.loaded && p.isLoading
            ? const AppListSkeleton(items: 5)
            : !p.loaded && p.hasError
                ? ErrorRetry(message: p.errorMessage ?? '', onRetry: p.load)
                : list.isEmpty
                    ? AppEmpty(
                        icon: Icons.verified_rounded,
                        title: p.items.isEmpty ? 'pl_alerts_empty'.tr : 'pl_alerts_empty_filter'.tr,
                      )
                    : AppRefresh(
                        onRefresh: p.load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.lg),
                          children: [
                            Text(plFmt('pl_alerts_hint', {'d': p.days}), style: AppType.meta(context)),
                            ..._rows(context, p, list),
                          ],
                        ),
                      ),
      ),
    ]),
    );
  }

  List<Widget> _rows(BuildContext context, ParentAlertsProvider p, List<Map<String, dynamic>> list) {
    final out = <Widget>[];
    var n = 0;
    // ONE entrance: the first cards rise in order (AppReveal caps itself); the group headings stay put.
    Widget card(Map<String, dynamic> a, bool showPriority) =>
        AppReveal(index: n++, group: 'parent.alerts', child: _AlertCard(alert: a, showPriority: showPriority));
    if (p.sort == 'priority') {
      for (final k in _prios) {
        final group = list.where((a) => a['priority'] == k).toList();
        if (group.isEmpty) continue;
        out.add(Padding(
          padding: const EdgeInsets.only(top: AppSpace.lg, bottom: AppSpace.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Icon(Icons.circle, size: AppSpace.sm, color: _prioColor(context, k)),
            const SizedBox(width: AppSpace.xs),
            Flexible(child: Text('pl_prio_$k'.tr, style: AppType.section(context), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: AppSpace.xs),
            Text(ltrIsolate('${group.length}'), style: AppType.figure(context).copyWith(color: context.colors.textLight)),
          ]),
        ));
        out.addAll(group.map((a) => card(a, false)));
      }
    } else {
      out.add(const SizedBox(height: AppSpace.sm));
      out.addAll(list.map((a) => card(a, true)));
    }
    return out;
  }
}

class _PrioChip extends StatelessWidget {
  const _PrioChip({required this.label, required this.count, required this.color, required this.selected, required this.onTap});

  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.card);
    final ink = selected ? c.onHero : appInkOn(context, color, c.cardBg);
    return Semantics(
      button: true,
      selected: selected,
      child: AppPressScale(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: AnimatedContainer(
              duration: AppMotion.of(context).fast,
              curve: AppMotion.curve,
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.sm),
              decoration: BoxDecoration(
                color: selected ? color : c.cardBg,
                borderRadius: radius,
                border: Border.all(color: selected ? color : c.divider),
              ),
              child: Column(children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AppCountUp('$count', memoryKey: 'parent.alerts.$label', style: AppType.figureLarge(context).copyWith(color: ink)),
                ),
                Text(label,
                    style: AppType.meta(context).copyWith(color: selected ? c.onHero : c.textMedium),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.showPriority});

  final Map<String, dynamic> alert;
  final bool showPriority;

  String _text() {
    final params = Map<String, dynamic>.from(alert['params'] as Map);
    for (final k in params.keys.toList()) {
      if (k.endsWith('_ar')) {
        final base = k.substring(0, k.length - 3);
        params[base] = (plIsAr ? params['${base}_ar'] : params['${base}_en']) ?? params['${base}_en'] ?? '';
      }
    }
    return plFmt('pl_alert_text_${alert['type']}', params);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.read<ParentAlertsProvider>();
    final c = context.colors;
    final prio = '${alert['priority']}';
    final col = _prioColor(context, prio);
    final unread = alert['unread'] == true;
    final dismissed = alert['status'] == 'dismissed';
    final child = alert['child'] as Map;
    final key = '${alert['key']}';
    final surface = unread ? c.cardBg : c.background;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Dismissible(
        key: ValueKey(key),
        direction: dismissed ? DismissDirection.none : DismissDirection.horizontal,
        background: _swipeBg(context, Alignment.centerLeft),
        secondaryBackground: _swipeBg(context, Alignment.centerRight),
        onDismissed: (_) {
          p.setStatus([key], 'dismissed');
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(
              content: Text('pl_alert_dismissed'.tr),
              action: SnackBarAction(label: 'pl_undo'.tr, onPressed: () => p.setStatus([key], 'unread')),
            ));
        },
        child: AnimatedOpacity(
          duration: AppMotion.of(context).fast,
          opacity: dismissed ? 0.5 : 1,
          // tone first: an unread alert sits on paper with its priority's hairline; a read one sinks into the canvas
          child: Material(
            color: surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              side: BorderSide(color: unread ? col.withValues(alpha: 0.45) : c.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: unread ? () => p.setStatus([key], 'read') : null,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xxs, AppSpace.xs),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    PlToneWell(icon: _typeIcon('${alert['type']}'), tone: col, surface: surface),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text('pl_alert_title_${alert['type']}'.tr,
                          style: AppType.row(context).copyWith(fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
                    ),
                    if (unread)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
                        child: Icon(Icons.circle, size: AppSpace.xs, color: col),
                      ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded, color: c.textMedium),
                      onSelected: (v) => p.setStatus([key], v),
                      itemBuilder: (_) => [
                        if (unread) PopupMenuItem(value: 'read', child: Text('pl_mark_read'.tr)) else PopupMenuItem(value: 'unread', child: Text('pl_mark_unread'.tr)),
                        if (!dismissed) PopupMenuItem(value: 'dismissed', child: Text('pl_dismiss'.tr)),
                      ],
                    ),
                  ]),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: AppSpace.xs, end: AppSpace.sm),
                    child: Text(_text(), style: AppType.body(context)),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  // the who / when line and the report action share a line while they fit; on a narrow phone the action
                  // drops under them instead of squeezing the child's name
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
                        child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          EntityChip(EntityRef(EntityKind.student, child['id'] as int, label: '${child['name']}')),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.schedule_rounded, size: AppIconSize.xs, color: c.textLight),
                            const SizedBox(width: AppSpace.xxs),
                            Flexible(child: Text(_ago(alert['at']), style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ]),
                          if (showPriority) AppStatusBadge(label: 'pl_prio_$prio'.tr, tone: _prioTone(prio), dense: true),
                        ]),
                      ),
                      AppButton(
                        label: 'pl_view_report'.tr,
                        variant: AppButtonVariant.ghost,
                        size: AppButtonSize.sm,
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ParentChildReportScreen(studentId: child['id'] as int, studentName: '${child['name']}'))),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _swipeBg(BuildContext context, Alignment al) {
    final c = context.colors;
    final tint = appTintOn(context, c.primary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
      alignment: al,
      decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Icon(Icons.done_all_rounded, color: appInkOn(context, c.primary, tint)),
    );
  }
}

AppTone _prioTone(String p) => p == 'high' ? AppTone.danger : (p == 'medium' ? AppTone.warning : AppTone.success);
