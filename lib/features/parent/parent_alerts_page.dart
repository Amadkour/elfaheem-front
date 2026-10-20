// lib/features/parent/parent_alerts_page.dart
// "Alerts" tab — flags about the children that need attention.
// Order: priority (high → medium → low), then newest first. A toggle switches to "newest first".
// Tap = mark read · swipe or ⋮ = dismiss (undo available) · "View report" opens the child's report.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import 'parent_link_providers.dart';
import 'parent_reports_page.dart';
import 'parent_widgets.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

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

    return Column(children: [
      // ── filters ───────────────────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(children: [
          for (final k in _prios)
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
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
            icon: Icon(Icons.more_vert_rounded, color: c.primary),
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
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
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
          const SizedBox(width: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(value: 'priority', label: Text('pl_sort_priority'.tr, style: const TextStyle(fontSize: 12))),
              ButtonSegment(value: 'date', label: Text('pl_sort_date'.tr, style: const TextStyle(fontSize: 12))),
            ],
            selected: {p.sort},
            onSelectionChanged: (s) => p.setSort(s.first),
          ),
        ]),
      ),
      Expanded(
        child: !p.loaded && p.isLoading
            ? const Center(child: AppLoadingIndicator(size: 56))
            : !p.loaded && p.hasError
                ? PlError(p.errorMessage ?? '', onRetry: p.load)
                : list.isEmpty
                    ? PlEmpty(p.items.isEmpty ? 'pl_alerts_empty'.tr : 'pl_alerts_empty_filter'.tr, icon: Icons.verified_rounded)
                    : RefreshIndicator(
                        onRefresh: p.load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(plFmt('pl_alerts_hint', {'d': p.days}), style: c.caption.copyWith(fontSize: 11.5)),
                            ),
                            ..._rows(context, p, list),
                          ],
                        ),
                      ),
      ),
    ]);
  }

  List<Widget> _rows(BuildContext context, ParentAlertsProvider p, List<Map<String, dynamic>> list) {
    final c = context.colors;
    final out = <Widget>[];
    if (p.sort == 'priority') {
      for (final k in _prios) {
        final group = list.where((a) => a['priority'] == k).toList();
        if (group.isEmpty) continue;
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
          child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: _prioColor(context, k), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text('${'pl_prio_$k'.tr}  (${group.length})', style: c.h2.copyWith(fontSize: 14)),
          ]),
        ));
        out.addAll(group.map((a) => _AlertCard(alert: a, showPriority: false)));
      }
    } else {
      out.addAll(list.map((a) => _AlertCard(alert: a, showPriority: true)));
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
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color : color.withAlpha(24),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withAlpha(selected ? 255 : 70)),
          ),
          child: Column(children: [
            Text('$count', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: selected ? Colors.white : color)),
            Text(label, style: TextStyle(fontSize: 11.5, color: selected ? Colors.white : null), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      );
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

    return Dismissible(
      key: ValueKey(key),
      direction: dismissed ? DismissDirection.none : DismissDirection.horizontal,
      background: _swipeBg(c.primary, Alignment.centerLeft),
      secondaryBackground: _swipeBg(c.primary, Alignment.centerRight),
      onDismissed: (_) {
        p.setStatus([key], 'dismissed');
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text('pl_alert_dismissed'.tr),
            action: SnackBarAction(label: 'pl_undo'.tr, onPressed: () => p.setStatus([key], 'unread')),
          ));
      },
      child: Opacity(
        opacity: dismissed ? 0.5 : 1,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: unread ? col.withAlpha(22) : c.primary.withAlpha(10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: unread ? col.withAlpha(90) : c.primary.withAlpha(25)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: unread ? () => p.setStatus([key], 'read') : null,
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(width: 5, color: col),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(color: col.withAlpha(35), borderRadius: BorderRadius.circular(10)),
                            child: Icon(_typeIcon('${alert['type']}'), size: 18, color: col),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('pl_alert_title_${alert['type']}'.tr,
                                style: TextStyle(fontSize: 14.5, fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
                          ),
                          if (unread) Container(width: 9, height: 9, margin: const EdgeInsets.symmetric(horizontal: 6), decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
                          PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.more_vert_rounded, size: 20),
                            onSelected: (v) => p.setStatus([key], v),
                            itemBuilder: (_) => [
                              if (unread) PopupMenuItem(value: 'read', child: Text('pl_mark_read'.tr)) else PopupMenuItem(value: 'unread', child: Text('pl_mark_unread'.tr)),
                              if (!dismissed) PopupMenuItem(value: 'dismissed', child: Text('pl_dismiss'.tr)),
                            ],
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Text(_text(), style: const TextStyle(fontSize: 13.5, height: 1.4)),
                        const SizedBox(height: 8),
                        Row(children: [
                          Icon(Icons.person_rounded, size: 14, color: c.primary),
                          const SizedBox(width: 3),
                          Flexible(child: Text('${child['name']}', style: TextStyle(fontSize: 12, color: c.primary, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 10),
                          Icon(Icons.schedule_rounded, size: 14, color: context.colors.textMedium),
                          const SizedBox(width: 3),
                          Text(_ago(alert['at']), style: c.caption.copyWith(fontSize: 12)),
                          if (showPriority) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                              decoration: BoxDecoration(color: col.withAlpha(35), borderRadius: BorderRadius.circular(8)),
                              child: Text('pl_prio_$prio'.tr, style: TextStyle(fontSize: 10.5, color: col, fontWeight: FontWeight.w800)),
                            ),
                          ],
                          const Spacer(),
                          TextButton(
                            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => ParentChildReportScreen(studentId: child['id'] as int, studentName: '${child['name']}'))),
                            child: Text('pl_view_report'.tr, style: const TextStyle(fontSize: 12)),
                          ),
                        ]),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _swipeBg(Color col, Alignment al) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: al,
        decoration: BoxDecoration(color: col.withAlpha(40), borderRadius: BorderRadius.circular(16)),
        child: Icon(Icons.done_all_rounded, color: col),
      );
}
