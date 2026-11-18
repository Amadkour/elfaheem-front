// lib/features/org/workspace/ws_alerts.dart
//
// The workspace's Alerts tab (D-1156, docs/teacher-org/PLAN.md): GET …/my-alerts in three views (Active · Snoozed ·
// Archived), filtered by source and severity (removable chips), drawn in the remembered style (prefs.alertView):
//   grouped   one collapsible card per source (name · unread count · worst severity tone), the first one open
//   expanded  the same cards, all open
//   list      one flat list, newest first
// A row: severity tone, title, subtitle, the person's avatar, the relative time, an unread dot. Tap = mark read
// (optimistic) and open the person (openWsPerson) or the server's link (orgJump). Per row: swipe (start → read /
// unread, end → archive or restore) and the ⋯ menu (read / unread, snooze 1 h · tomorrow morning · next week,
// archive with Undo, restore). A group's "Mark all read" sends every key in one call. After each change the tab
// badge follows the response's counts (or a refetch).
//
// The plain-value parts (WsAlertRow, WsAlertGroupCard) and the pure helpers (wsSnoozeUntil, wsFilterAlerts,
// wsNewestFirst) are tested in test/org/ws_alerts_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart' show countText;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/master_detail/entity_specs.dart' show mdAgo;
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import '../home/org_home_tasks.dart' show OrgAllCaughtUp;
import '../org_dashboard_home.dart' show orgJump;
import '../org_page_header.dart' show OrgPageRefresh;
import '../org_page_kit.dart' show OrgMenuItem, OrgMoreMenu;
import '../org_ui.dart' show OrgPill;
import '../org_v3.dart' show orgErrorText;
import 'ws_models.dart';
import 'ws_person.dart' show openWsPerson;
import 'ws_shell.dart' show WsController;

// ═════════════════════════════════════════════════════════════════════════════
//  Pure helpers
// ═════════════════════════════════════════════════════════════════════════════

/// The three views, in the segment order; the value is the server's `view`.
const wsAlertViews = ['active', 'snoozed', 'archived'];

enum WsSnooze { hour, tomorrow, nextWeek }

/// The hour a "morning" snooze wakes at, on the platform / organization clock.
const wsSnoozeMorningHour = 8;

/// When a snooze ends, as a UTC instant: in an hour; tomorrow at 8:00; a week from today at 8:00 — the mornings on
/// the effective clock (AppTime: the organization / platform timezone), not the device's.
DateTime wsSnoozeUntil(WsSnooze s, {DateTime? nowUtc}) {
  final now = (nowUtc ?? DateTime.now()).toUtc();
  if (s == WsSnooze.hour) return now.add(const Duration(hours: 1));
  final wall = AppTime.toZone(now);
  final days = s == WsSnooze.tomorrow ? 1 : 7;
  return AppTime.fromZone(DateTime(wall.year, wall.month, wall.day + days, wsSnoozeMorningHour));
}

/// The alerts whose source is in [sources] (WsAlertSource.key) and severity in [severities]; an empty set keeps all.
List<WsAlert> wsFilterAlerts(List<WsAlert> alerts, {Set<String> sources = const {}, Set<WsSeverity> severities = const {}}) => [
      for (final a in alerts)
        if ((sources.isEmpty || sources.contains(a.source.key)) && (severities.isEmpty || severities.contains(a.severity))) a,
    ];

/// The flat list: newest first; rows without a time (attention rows) after the dated ones, worst severity first.
List<WsAlert> wsNewestFirst(List<WsAlert> alerts) => [...alerts]..sort((a, b) {
    if (a.at == null && b.at == null) return a.severity.index.compareTo(b.severity.index);
    if (a.at == null) return 1;
    if (b.at == null) return -1;
    return b.at!.compareTo(a.at!);
  });

String wsSeverityLabel(WsSeverity s) => switch (s) {
      WsSeverity.high => t('عاجل', 'High'),
      WsSeverity.medium => t('متوسط', 'Medium'),
      WsSeverity.low => t('عادي', 'Low'),
    };

Color wsSeverityColor(BuildContext context, WsSeverity s) {
  final c = context.colors;
  return switch (s) { WsSeverity.high => c.danger, WsSeverity.medium => c.warning, WsSeverity.low => c.primary };
}

IconData _severityIcon(WsSeverity s) => switch (s) {
      WsSeverity.high => Icons.priority_high_rounded,
      WsSeverity.medium => Icons.error_outline_rounded,
      WsSeverity.low => Icons.info_outline_rounded,
    };

String wsSnoozeLabel(WsSnooze s) => switch (s) {
      WsSnooze.hour => t('ساعة واحدة', 'For 1 hour'),
      WsSnooze.tomorrow => t('صباح الغد', 'Tomorrow morning'),
      WsSnooze.nextWeek => t('الأسبوع القادم', 'Next week'),
    };

String _sourceName(WsAlertSource s) {
  if (s.isOrg) return t('المؤسسة', 'The organization');
  return s.name.isNotEmpty ? s.name : t('القسم', 'Department');
}

// ═════════════════════════════════════════════════════════════════════════════
//  Plain-value parts
// ═════════════════════════════════════════════════════════════════════════════

/// One alert: the severity mark, title, subtitle, the person's avatar, the time, an unread dot, the ⋯ menu.
class WsAlertRow extends StatelessWidget {
  const WsAlertRow({super.key, required this.alert, this.onTap, this.actions = const [], this.now});

  final WsAlert alert;
  final VoidCallback? onTap;
  final List<OrgMenuItem> actions;

  /// The clock the relative time is measured from (tests); null = now.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = wsSeverityColor(context, alert.severity);
    final when = alert.at == null ? '' : mdAgo(alert.at!.toUtc(), now: now?.toUtc());
    final untilAt = alert.snoozedUntil == null ? '' : AppTime.dateTime(alert.snoozedUntil!.toUtc());
    final until = untilAt.isEmpty ? '' : t('حتى $untilAt', 'Until $untilAt');
    final meta = [if (alert.personName != null) alert.personName!, if (until.isNotEmpty) until else if (when.isNotEmpty) when].join(' · ');
    final unreadLabel = alert.read ? '' : t('غير مقروء، ', 'Unread, ');
    final mark = Container(
      width: AppIconSize.hero,
      height: AppIconSize.hero,
      decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Icon(_severityIcon(alert.severity), size: AppIconSize.md, color: appInk(context, tone)),
    );
    return Semantics(
      button: onTap != null,
      label: '$unreadLabel${wsSeverityLabel(alert.severity)}: ${alert.title}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.xxs, AppSpace.xs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ExcludeSemantics(
                child: alert.personName == null
                    ? mark
                    : Stack(clipBehavior: Clip.none, children: [
                        AppAvatar(name: alert.personName!, url: alert.personAvatar, size: AppIconSize.hero),
                        PositionedDirectional(
                          bottom: -AppSpace.xxs / 2,
                          end: -AppSpace.xxs / 2,
                          child: Container(
                            padding: const EdgeInsets.all(AppSpace.xxs / 2),
                            decoration: BoxDecoration(color: c.cardBg, shape: BoxShape.circle),
                            child: Icon(_severityIcon(alert.severity), size: AppIconSize.xs, color: appInk(context, tone)),
                          ),
                        ),
                      ]),
              ),
              AppSpace.gapSm,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(alert.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: (alert.read ? AppType.row(context) : AppType.bodyStrong(context)).copyWith(color: c.textDark)),
                    ),
                    if (!alert.read) ...[
                      const SizedBox(width: AppSpace.xs),
                      Container(width: AppSpace.xs, height: AppSpace.xs, decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle)),
                    ],
                  ]),
                  if (alert.subtitle.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xxs / 2),
                    Text(alert.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
                  ],
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xxs / 2),
                    Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
                  ],
                ]),
              ),
              if (actions.isNotEmpty) OrgMoreMenu(items: actions, compact: true),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A source's card: the header (tone bar · name · unread count · chevron) toggles it; open, it shows [children]
/// and "Mark all read" when something is unread.
class WsAlertGroupCard extends StatelessWidget {
  const WsAlertGroupCard({
    super.key,
    required this.group,
    required this.open,
    required this.children,
    this.onToggle,
    this.onMarkAllRead,
  });

  final WsAlertGroup group;
  final bool open;
  final List<Widget> children;

  /// null: always open (the expanded style), no chevron.
  final VoidCallback? onToggle;
  final VoidCallback? onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = wsSeverityColor(context, group.worst);
    final unread = group.unread;
    final name = _sourceName(group.source);
    final count = unread > 0
        ? countText(unread, ar1: 'غير مقروء واحد', ar2: 'غير مقروءين', arFew: '{n} غير مقروءة', arMany: '{n} غير مقروء', en1: '1 unread', en: '{n} unread')
        : countText(group.alerts.length, ar1: 'تنبيه واحد', ar2: 'تنبيهان', arFew: '{n} تنبيهات', arMany: '{n} تنبيهاً', en1: '1 alert', en: '{n} alerts');
    final header = Semantics(
      button: onToggle != null,
      expanded: onToggle == null ? null : open,
      label: '$name, $count, ${wsSeverityLabel(group.worst)}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xs, AppSpace.sm, AppSpace.xs),
            child: Row(children: [
              Container(
                  width: AppSpace.xxs,
                  height: AppIconSize.lg,
                  decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(AppRadius.pill))),
              AppSpace.gapSm,
              Icon(group.source.isOrg ? Icons.domain_rounded : Icons.account_tree_rounded,
                  size: AppIconSize.md, color: c.textMedium),
              AppSpace.gapXs,
              Expanded(
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
              ),
              AppSpace.gapXs,
              Flexible(child: OrgPill(count, color: unread > 0 ? tone : c.textMedium)),
              if (onToggle != null) ...[
                AppSpace.gapXs,
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: AppMotion.of(context).fast,
                  child: Icon(Icons.expand_more_rounded, size: AppIconSize.md, color: c.textMedium),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        if (open) ...[
          Divider(height: 1, color: c.divider),
          ...children,
          if (onMarkAllRead != null && unread > 0)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.xs),
                child: AppButton.ghost(
                    label: t('تعليم الكل كمقروء', 'Mark all read'), icon: Icons.done_all_rounded, size: AppButtonSize.sm, onPressed: onMarkAllRead),
              ),
            ),
        ],
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The tab
// ═════════════════════════════════════════════════════════════════════════════

class WsAlertsTab extends StatefulWidget {
  const WsAlertsTab({super.key});
  @override
  State<WsAlertsTab> createState() => _WsAlertsTabState();
}

class _WsAlertsTabState extends State<WsAlertsTab> {
  int _view = 0;
  List<WsAlert> _items = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _sources = {};
  final Set<WsSeverity> _severities = {};

  /// The open group cards (grouped style); null until the person toggles one: the first card is open.
  Set<String>? _open;
  OrgPageRefresh? _refresh;
  int _seq = 0;

  WsController get _ws => context.read<WsController>();

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _load();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    super.dispose();
  }

  Future<void> _reload() => _load(quiet: true);

  Future<void> _load({bool quiet = false}) async {
    final seq = ++_seq;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final ws = _ws;
    final (items, counts, r) = await ws.api.alerts(view: wsAlertViews[_view]);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _items = items;
        _error = null;
      } else if (!quiet || _items.isEmpty) {
        _error = r.error == null ? t('تعذّر التحميل', 'Could not load') : orgErrorText(r.error!);
      }
    });
    if (r.ok) {
      ws.setAlertCounts(counts);
      OrgPageRefresh.reportUpdated(context);
    }
  }

  void _setView(int i) {
    if (i == _view) return;
    setState(() {
      _view = i;
      _items = const [];
      _open = null;
    });
    _load();
  }

  /// Applies [state] to [keys] at once (optimistic), then the server; a refusal puts the list back.
  Future<bool> _apply(List<String> keys, String state, {DateTime? until}) async {
    if (keys.isEmpty) return true;
    final ws = _ws;
    final before = _items;
    final set = keys.toSet();
    setState(() {
      _items = switch (state) {
        'read' || 'unread' => [for (final a in _items) set.contains(a.key) ? a.copyWith(read: state == 'read') : a],
        _ => [for (final a in _items) if (!set.contains(a.key)) a],
      };
    });
    final r = await ws.api.setAlertState(keys, state, until: until);
    if (!r.ok) {
      if (mounted) setState(() => _items = before);
      showAppNotice(r.error == null ? t('تعذّر الحفظ', 'Could not save') : orgErrorText(r.error!), error: true);
      return false;
    }
    _countsFrom(ws, r.map);
    return true;
  }

  static void _countsFrom(WsController ws, Map<String, dynamic> m) {
    final c = m['counts'];
    if (c is Map) {
      ws.setAlertCounts(WsAlertCounts.fromJson(c.cast<String, dynamic>()));
    } else {
      ws.refreshAlertCounts();
    }
  }

  Future<void> _archive(List<String> keys) async {
    final ws = _ws;
    if (!await _apply(keys, 'archive')) return;
    showAppNotice(
      keys.length == 1 ? t('أُرشف التنبيه', 'Alert archived') : t('أُرشفت التنبيهات', 'Alerts archived'),
      icon: Icons.archive_outlined,
      actionLabel: t('تراجع', 'Undo'),
      onAction: () async {
        final r = await ws.api.setAlertState(keys, 'restore');
        if (!r.ok) {
          showAppNotice(r.error == null ? t('تعذّر التراجع', 'Could not undo') : orgErrorText(r.error!), error: true);
          return;
        }
        _countsFrom(ws, r.map);
        if (mounted) _load(quiet: true);
      },
    );
  }

  Future<void> _restore(List<String> keys) async {
    if (await _apply(keys, 'restore')) showAppNotice(t('أُعيد التنبيه إلى النشطة', 'Moved back to Active'));
  }

  Future<void> _snooze(WsAlert a) async {
    final pick = await showAppSheet<WsSnooze>(
      context,
      (ctx) => AppSheetContent(
        title: t('تأجيل التنبيه', 'Snooze alert'),
        icon: Icons.snooze_rounded,
        children: [
          for (final s in WsSnooze.values)
            ListTile(
              leading: Icon(switch (s) {
                WsSnooze.hour => Icons.hourglass_bottom_rounded,
                WsSnooze.tomorrow => Icons.wb_twilight_rounded,
                WsSnooze.nextWeek => Icons.date_range_rounded,
              }),
              title: Text(wsSnoozeLabel(s)),
              subtitle: Text(AppTime.dateTime(wsSnoozeUntil(s))),
              onTap: () => Navigator.of(ctx).pop(s),
            ),
        ],
      ),
    );
    if (pick == null || !mounted) return;
    final until = wsSnoozeUntil(pick);
    if (await _apply([a.key], 'snooze', until: until)) {
      final at = AppTime.dateTime(until);
      showAppNotice(t('أُجّل حتى $at', 'Snoozed until $at'), icon: Icons.snooze_rounded);
    }
  }

  void _openAlert(WsAlert a) {
    final ws = _ws;
    if (!a.read) _apply([a.key], 'read');
    if (a.opensPerson) {
      openWsPerson(context, ws, unitId: a.deptId!, userId: a.personId!);
      return;
    }
    final section = '${a.link['section'] ?? ''}';
    if (section.isEmpty) return;
    final sub = a.link['sub'];
    orgJump(context, section, sub: sub == null || '$sub'.isEmpty ? null : '$sub');
  }

  List<OrgMenuItem> _actions(WsAlert a) {
    final view = wsAlertViews[_view];
    return [
      if (view != 'archived')
        a.read
            ? OrgMenuItem(icon: Icons.mark_email_unread_outlined, label: t('تعليم كغير مقروء', 'Mark as unread'), onTap: () => _apply([a.key], 'unread'))
            : OrgMenuItem(icon: Icons.mark_email_read_outlined, label: t('تعليم كمقروء', 'Mark as read'), onTap: () => _apply([a.key], 'read')),
      if (view == 'active') OrgMenuItem(icon: Icons.snooze_rounded, label: t('تأجيل…', 'Snooze…'), onTap: () => _snooze(a)),
      if (view != 'active') OrgMenuItem(icon: Icons.unarchive_outlined, label: t('إعادة إلى النشطة', 'Restore'), onTap: () => _restore([a.key])),
      if (view != 'archived') OrgMenuItem(icon: Icons.archive_outlined, label: t('أرشفة', 'Archive'), onTap: () => _archive([a.key])),
    ];
  }

  Widget _row(WsAlert a) {
    final c = context.colors;
    final view = wsAlertViews[_view];
    Widget bg(IconData icon, String label, Color color, AlignmentDirectional align) => Container(
          color: color.withValues(alpha: 0.12),
          alignment: align,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: AppIconSize.md, color: appInk(context, color)),
            AppSpace.gapXs,
            Flexible(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: appInk(context, color)))),
          ]),
        );
    final endLabel = view == 'active' ? t('أرشفة', 'Archive') : t('إعادة', 'Restore');
    final readLabel = a.read ? t('غير مقروء', 'Unread') : t('مقروء', 'Read');
    return Dismissible(
      key: ValueKey('ws-alert-${a.key}'),
      direction: view == 'archived' ? DismissDirection.endToStart : DismissDirection.horizontal,
      background: bg(a.read ? Icons.mark_email_unread_outlined : Icons.mark_email_read_outlined, readLabel, c.primary, AlignmentDirectional.centerStart),
      secondaryBackground:
          bg(view == 'active' ? Icons.archive_outlined : Icons.unarchive_outlined, endLabel, c.textMedium, AlignmentDirectional.centerEnd),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          _apply([a.key], a.read ? 'unread' : 'read');
          return false;
        }
        return true;
      },
      onDismissed: (_) => view == 'active' ? _archive([a.key]) : _restore([a.key]),
      child: WsAlertRow(alert: a, onTap: () => _openAlert(a), actions: _actions(a)),
    );
  }

  Future<void> _filterSheet(List<WsAlertSource> sources) => showAppSheet<void>(
        context,
        (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
          void change(VoidCallback fn) {
            setState(fn);
            setSheet(() {});
          }

          return AppSheetContent(
            title: t('تصفية التنبيهات', 'Filter alerts'),
            icon: Icons.filter_list_rounded,
            children: [
              if (sources.isNotEmpty) ...[
                Text(t('المصدر', 'Source'), style: AppType.label(context)),
                AppSpace.gapXs,
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                  for (final s in sources)
                    AppChoiceChip(
                      label: _sourceName(s),
                      selected: _sources.contains(s.key),
                      onTap: () => change(() => _sources.contains(s.key) ? _sources.remove(s.key) : _sources.add(s.key)),
                    ),
                ]),
                AppSpace.gapMd,
              ],
              Text(t('الأهمية', 'Severity'), style: AppType.label(context)),
              AppSpace.gapXs,
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final s in WsSeverity.values)
                  AppChoiceChip(
                    label: wsSeverityLabel(s),
                    icon: _severityIcon(s),
                    selected: _severities.contains(s),
                    onTap: () => change(() => _severities.contains(s) ? _severities.remove(s) : _severities.add(s)),
                  ),
              ]),
              AppSpace.gapMd,
              Wrap(alignment: WrapAlignment.end, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                if (_sources.isNotEmpty || _severities.isNotEmpty)
                  AppButton.ghost(
                      label: t('مسح التصفية', 'Clear filters'),
                      onPressed: () => change(() {
                            _sources.clear();
                            _severities.clear();
                          })),
                AppButton.primary(label: t('تم', 'Done'), onPressed: () => Navigator.of(ctx).pop()),
              ]),
            ],
          );
        }),
      );

  Widget _controls(WsController ws, WsAlertView style, List<WsAlertSource> sources) {
    final nFilters = _sources.length + _severities.length;
    Widget styleBtn(WsAlertView v, IconData icon, String label) => AppIconButton(
          icon: icon,
          tooltip: label,
          variant: style == v ? AppIconButtonVariant.tonal : AppIconButtonVariant.standard,
          onPressed: () => ws.prefs.update((p) => p.copyWith(alertView: v)),
        );
    final chips = <Widget>[
      for (final s in sources.where((s) => _sources.contains(s.key)))
        InputChip(
          label: Text(_sourceName(s), maxLines: 1, overflow: TextOverflow.ellipsis),
          onDeleted: () => setState(() => _sources.remove(s.key)),
          deleteButtonTooltipMessage: t('إزالة', 'Remove'),
        ),
      for (final s in _severities.toList()..sort((a, b) => a.index.compareTo(b.index)))
        InputChip(
          avatar: Icon(_severityIcon(s), size: AppIconSize.sm, color: appInk(context, wsSeverityColor(context, s))),
          label: Text(wsSeverityLabel(s)),
          onDeleted: () => setState(() => _severities.remove(s)),
          deleteButtonTooltipMessage: t('إزالة', 'Remove'),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTabs(
          items: [
            AppTabItem(t('النشطة', 'Active'),
                icon: Icons.notifications_active_outlined, count: ws.alertCounts.active > 0 ? ws.alertCounts.active : null),
            AppTabItem(t('المؤجلة', 'Snoozed'), icon: Icons.snooze_rounded),
            AppTabItem(t('المؤرشفة', 'Archived'), icon: Icons.archive_outlined),
          ],
          index: _view,
          onChanged: _setView,
        ),
        AppSpace.gapSm,
        Row(children: [
          Flexible(
            child: AppButton.secondary(
              label: nFilters == 0 ? t('تصفية', 'Filter') : t('تصفية ($nFilters)', 'Filter ($nFilters)'),
              icon: Icons.filter_list_rounded,
              size: AppButtonSize.sm,
              onPressed: () => _filterSheet(sources),
            ),
          ),
          const Spacer(),
          Semantics(
            container: true,
            label: t('طريقة العرض', 'Display style'),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              styleBtn(WsAlertView.grouped, Icons.view_agenda_outlined, t('مجمّعة', 'Grouped')),
              styleBtn(WsAlertView.expanded, Icons.unfold_more_rounded, t('موسّعة', 'Expanded')),
              styleBtn(WsAlertView.list, Icons.view_list_rounded, t('قائمة', 'List')),
            ]),
          ),
        ]),
        if (chips.isNotEmpty) ...[
          AppSpace.gapXs,
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: chips),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WsController>();
    final c = context.colors;
    final style = ws.prefs.prefs.alertView;
    final seen = <String>{};
    final sources = [for (final a in _items) if (seen.add(a.source.key)) a.source];
    final shown = wsFilterAlerts(_items, sources: _sources, severities: _severities);
    final view = wsAlertViews[_view];

    final List<Widget> body;
    if (_loading && _items.isEmpty) {
      body = const [AppListSkeleton(items: 5)];
    } else if (_error != null && _items.isEmpty) {
      body = [Padding(padding: const EdgeInsets.all(AppSpace.md), child: AppErrorState(message: _error, onRetry: _load))];
    } else if (_items.isEmpty) {
      body = [
        if (view == 'active')
          const OrgAllCaughtUp()
        else
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: AppEmpty(
              icon: view == 'snoozed' ? Icons.snooze_rounded : Icons.archive_outlined,
              title: view == 'snoozed' ? t('لا تنبيهات مؤجلة', 'Nothing snoozed') : t('لا تنبيهات مؤرشفة', 'Nothing archived'),
              message: view == 'snoozed'
                  ? t('التنبيه المؤجل يعود إلى النشطة في موعده.', 'A snoozed alert comes back to Active when its time comes.')
                  : t('ما تؤرشفه يبقى هنا ويمكنك إعادته.', 'What you archive stays here, and you can bring it back.'),
            ),
          ),
      ];
    } else if (shown.isEmpty) {
      body = [
        Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: AppEmpty(
            icon: Icons.filter_alt_off_rounded,
            title: t('لا تنبيهات بهذه التصفية', 'No alerts match these filters'),
            actionLabel: t('مسح التصفية', 'Clear filters'),
            onAction: () => setState(() {
              _sources.clear();
              _severities.clear();
            }),
          ),
        ),
      ];
    } else if (style == WsAlertView.list) {
      final rows = wsNewestFirst(shown);
      body = [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: c.divider),
                _row(rows[i]),
              ],
            ]),
          ),
        ),
      ];
    } else {
      final groups = wsGroupAlerts(shown);
      final open = _open ?? {if (groups.isNotEmpty) groups.first.source.key};
      body = [
        for (final g in groups)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.sm),
            child: WsAlertGroupCard(
              group: g,
              open: style == WsAlertView.expanded || open.contains(g.source.key),
              onToggle: style == WsAlertView.expanded
                  ? null
                  : () => setState(() {
                        final s = {...open};
                        s.contains(g.source.key) ? s.remove(g.source.key) : s.add(g.source.key);
                        _open = s;
                      }),
              onMarkAllRead: view == 'archived' ? null : () => _apply([for (final a in g.alerts) if (!a.read) a.key], 'read'),
              children: [
                for (var i = 0; i < g.alerts.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: AppSpace.md, endIndent: AppSpace.md, color: c.divider),
                  _row(g.alerts[i]),
                ],
              ],
            ),
          ),
      ];
    }

    return AppRefresh(
      onRefresh: () => _load(quiet: true),
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpace.xl),
        children: [_controls(ws, style, sources), ...body],
      ),
    );
  }
}
