// lib/features/parent/parent_alerts_page.dart — the "Alerts" tab (Pa2Alerts `screen=alerts|empty`, phase 4): flags
// about the children that need attention.
//   hero   n alerts in the last 30 days, how many urgent, how many unread; three priority figures that filter
//   body   priority / newest (the kit's pill), "Show dismissed", "Mark all read"; the alerts grouped by priority
//          (or newest first), each a card: the type's icon, title, unread dot, the sentence, the child, when, the
//          priority, mark read / dismiss and "View the report". Swipe dismisses too (undo in the notice).
// The child picked in the top bar's switcher filters the list (ParentAlertsProvider.setChild).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/core/course_access.dart' show parseUtc;
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import 'pa_kit.dart';
import 'parent_link_providers.dart';
import 'parent_reports_page.dart';
import 'parent_widgets.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:flutter_education_app/design/app_kit.dart';

const _prios = ['high', 'medium', 'low'];

KitTone _prioTone(BuildContext context, String p) {
  final kit = context.colors.kit;
  return p == 'high' ? kit.live : (p == 'medium' ? kit.warn : kit.ok);
}

IconData _typeIcon(String t) {
  switch (t) {
    case 'failed_exam':
      return Icons.close_rounded;
    case 'score_drop':
      return Icons.trending_down_rounded;
    case 'missed_session':
      return Icons.schedule_rounded;
    case 'missing_homework':
    case 'late_homework':
      return Icons.assignment_late_outlined;
    case 'homework_due_soon':
      return Icons.alarm_rounded;
    case 'low_attendance':
      return Icons.person_off_outlined;
    case 'late_arrival':
      return Icons.schedule_rounded;
    case 'left_early':
      return Icons.directions_run_rounded;
    case 'inactive':
    case 'inactive_long':
      return Icons.pause_circle_outline_rounded;
    case 'course_expiring':
      return Icons.hourglass_bottom_rounded;
    default:
      return Icons.bookmark_outline_rounded; // weak_backlog
  }
}

/// "3 days ago", "in 5 hours" …
String _ago(dynamic iso) {
  final d = parseUtc(iso?.toString());
  if (d == null) return '';
  final diff = DateTime.now().toUtc().difference(d);
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // the top bar's child switcher is the filter
    final kids = PaKids.maybeOf(context);
    if (kids == null) return;
    final p = context.read<ParentAlertsProvider>();
    if (p.childId != kids.selected) WidgetsBinding.instance.addPostFrameCallback((_) => p.setChild(kids.selected));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ParentAlertsProvider>();
    final list = p.visible;
    final live = [for (final a in p.items) if (a['status'] != 'dismissed' && (p.childId == null || (a['child'] as Map?)?['id'] == p.childId)) a];
    final high = live.where((a) => a['priority'] == 'high').length;
    final unread = live.where((a) => a['unread'] == true).length;
    final counts = {for (final k in _prios) k: live.where((a) => a['priority'] == k).length};
    final kit = context.colors.kit;

    final hero = AppHero(
      kicker: 'pl_tab_alerts'.tr,
      title: live.isEmpty
          ? paFmt('pa_alerts_none_title', {'d': appDigits('${p.days}')})
          : paFmt(high > 0 ? 'pa_alerts_title_urgent' : 'pa_alerts_title', {
              'n': appDigits('${live.length}'),
              'd': appDigits('${p.days}'),
              'h': appDigits('$high'),
            }),
      subtitle: unread == 0 ? 'pa_alerts_all_read'.tr : paFmt('pa_alerts_unread', {'n': appDigits('$unread')}),
      statsOnPhone: true,
      stats: [
        for (final k in _prios)
          AppHeroStat(
            key: ValueKey('pa.alerts.prio.$k'),
            icon: Icons.circle,
            label: 'pl_prio_$k'.tr + (p.priority == k ? ' ✓' : ''),
            value: appDigits('${counts[k]}'),
            onTap: () => p.setPriority(k),
          ),
      ],
    );

    final controls = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppTabs(
        expand: true,
        items: [AppTabItem('pa_sort_priority'.tr), AppTabItem('pa_sort_newest'.tr)],
        index: p.sort == 'priority' ? 0 : 1,
        onChanged: (i) => p.setSort(i == 0 ? 'priority' : 'date'),
      ),
      const SizedBox(height: AppSpace.sm),
      Row(children: [
        AppSwitch(value: p.showDismissed, onChanged: (_) => p.toggleDismissed(), semanticLabel: 'pa_show_dismissed'.tr),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text('pa_show_dismissed'.tr, style: AppType.row(context))),
      ]),
      const SizedBox(height: AppSpace.xs),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppButton.secondary(
          key: const ValueKey('pa.alerts.read_all'),
          label: 'pa_mark_all_read'.tr,
          icon: Icons.done_rounded,
          size: AppButtonSize.sm,
          onPressed: unread == 0 ? null : p.readAll,
        ),
      ),
    ]);

    final first = PaKids.maybeOf(context)?.current?.firstName;
    final Widget content = !p.loaded && p.isLoading
        ? const AppListSkeleton(items: 4, padding: EdgeInsets.zero)
        : !p.loaded && p.hasError
            ? ErrorRetry(message: p.errorMessage ?? '', onRetry: p.load)
            : list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
                    child: Column(children: [
                      AppIconBox(icon: Icons.check_rounded, size: AppDashSize.disc, tone: kit.ok),
                      const SizedBox(height: AppSpace.sm),
                      Text(p.items.isEmpty || p.priority.isEmpty ? 'pa_alerts_empty'.tr : 'pl_alerts_empty_filter'.tr,
                          textAlign: TextAlign.center, style: AppType.section(context)),
                      const SizedBox(height: AppSpace.xxs),
                      Text(
                        first == null
                            ? paFmt('pa_alerts_empty_sub', {'d': appDigits('${p.days}')})
                            : paFmt('pa_alerts_empty_sub_name', {'name': first, 'd': appDigits('${p.days}')}),
                        textAlign: TextAlign.center,
                        style: AppType.meta(context),
                      ),
                    ]),
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _rows(context, p, list));

    return PaHeroPage(
      onRefresh: p.load,
      width: AppWidth.reading,
      hero: hero,
      body: AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [controls, content])),
    );
  }

  List<Widget> _rows(BuildContext context, ParentAlertsProvider p, List<Map<String, dynamic>> list) {
    final out = <Widget>[];
    if (p.sort == 'priority') {
      for (final k in _prios) {
        final group = list.where((a) => a['priority'] == k).toList();
        if (group.isEmpty) continue;
        out.add(Padding(
          padding: const EdgeInsets.only(top: AppSpace.lg, bottom: AppSpace.sm),
          child: Row(children: [
            Icon(Icons.circle, size: AppSpace.sm, color: _prioTone(context, k).color),
            const SizedBox(width: AppSpace.xs),
            Flexible(child: Text('pl_prio_$k'.tr, style: AppType.section(context), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: AppSpace.xs),
            Text(appDigits('${group.length}'), style: AppType.meta(context)),
          ]),
        ));
        out.addAll(group.map((a) => _AlertCard(alert: a, showPriority: true)));
      }
    } else {
      out.add(const SizedBox(height: AppSpace.md));
      out.addAll(list.map((a) => _AlertCard(alert: a, showPriority: true)));
    }
    return out;
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
    final tone = _prioTone(context, prio);
    final unread = alert['unread'] == true;
    final dismissed = alert['status'] == 'dismissed';
    final child = alert['child'] as Map;
    final childId = (child['id'] as num).toInt();
    final key = '${alert['key']}';
    final set = AppAreaScope.of(context);

    final card = Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        gradient: unread ? LinearGradient(colors: [c.cardBg, set.tint]) : null,
        color: unread ? null : c.kit.well,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: unread ? Color.lerp(set.tint, set.a, .3)! : c.kit.line, width: AppBorder.strong),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppIconBox(icon: _typeIcon('${alert['type']}'), tone: tone),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text('pl_alert_title_${alert['type']}'.tr,
                      style: AppType.tileTitle(context).copyWith(fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
                ),
                if (unread) ...[
                  const SizedBox(width: AppSpace.xs),
                  Icon(Icons.circle, size: AppSpace.xs, color: set.a, semanticLabel: 'pa_unread'.tr),
                ],
              ]),
              const SizedBox(height: AppSpace.xxs),
              Text(_text(), style: AppType.body(context).copyWith(color: c.textMedium)),
            ]),
          ),
          AppIconButton(
            icon: unread ? Icons.done_rounded : Icons.mark_email_unread_outlined,
            tooltip: unread ? 'pl_mark_read'.tr : 'pl_mark_unread'.tr,
            onPressed: () => p.setStatus([key], unread ? 'read' : 'unread'),
          ),
          if (!dismissed)
            AppIconButton(icon: Icons.close_rounded, tooltip: 'pl_dismiss'.tr, onPressed: () => p.setStatus([key], 'dismissed')),
        ]),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppChip(label: '${child['name']}'.split(' ').first, leading: PaKidAvatar(id: childId, name: '${child['name']}'), selected: false),
          Text(_ago(alert['at']), style: AppType.meta(context)),
          if (showPriority) AppStatusBadge(label: 'pl_prio_$prio'.tr, tone: prio == 'high' ? AppTone.danger : (prio == 'medium' ? AppTone.warning : AppTone.success)),
        ]),
        const SizedBox(height: AppSpace.sm),
        AppButton.secondary(
          label: 'pa_view_report'.tr,
          expand: true,
          onPressed: () => paPush<void>(context, ParentChildReportScreen(studentId: childId, studentName: '${child['name']}')),
        ),
      ]),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Dismissible(
        key: ValueKey(key),
        direction: dismissed ? DismissDirection.none : DismissDirection.horizontal,
        onDismissed: (_) {
          p.setStatus([key], 'dismissed');
          showAppNotice('pl_alert_dismissed'.tr, actionLabel: 'pl_undo'.tr, onAction: () => p.setStatus([key], 'unread'));
        },
        child: Opacity(opacity: dismissed ? .5 : 1, child: card),
      ),
    );
  }
}
