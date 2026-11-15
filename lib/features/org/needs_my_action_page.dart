// lib/features/org/needs_my_action_page.dart
//
// UX v3 phase 2: "Needs my action", every item waiting on me across my organizations, in ONE list.
//   GET /api/v1/me/action-inbox?q=&limit=50
//     {items: [{key, kind, action, title, reason_ar, reason_en, module, id, org_id, org_name, due_at?, overdue,
//      urgency 0-3, created_at}], total}   sorted by urgency, then due
//
//   ActionInboxItem          a defensive parser (tested)
//   NeedsMyActionList        plain values (expectNoLayoutErrors): the rows, each with its action, reason, place, due;
//                            `.sliver` builds only the rows on screen (the page's list, UX v3 phase 5)
//   NeedsMyActionPage        the page: a debounced search (server `q`), All · Urgent · Overdue chips, skeleton while
//                            loading, AppErrorBox with Retry, the calm empty state; a row opens through
//                            AppNavigator.openLink with its link (the ActionBanner rides along). Load more: the
//                            server has `limit` (≤ 200) and `total` but no offset, so near the end the page asks again
//                            with a larger limit (actionInboxNextLimit) while rows are missing
// Opened by module `action_inbox` (a grouped push / notification, a badge with several items).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/notif_link.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/action_banner.dart' show notifActionIcon, notifActionLabel;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart' show AppNavigator;
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../admin/admin_common.dart' show asInt, asMap, asMapList, asStr, t;
import 'org_v3.dart' show orgParseUtc;

const kActionInboxPath = '/api/v1/me/action-inbox';

class ActionInboxItem {
  const ActionInboxItem({
    required this.key,
    this.kind = '',
    this.action = NotifAction.none,
    this.title = '',
    this.reasonAr,
    this.reasonEn,
    this.module,
    this.id,
    this.orgId,
    this.orgName,
    this.dueAt,
    this.overdue = false,
    this.urgency = 0,
    this.createdAt,
    this.raw = const {},
  });

  final String key, kind, title;
  final NotifAction action;
  final String? reasonAr, reasonEn, module, orgName;
  final int? id, orgId;
  final DateTime? dueAt, createdAt;
  final bool overdue;

  /// 0 (low) – 3 (urgent).
  final int urgency;
  final Map<String, dynamic> raw;

  String get reason => NotifLink.fromInboxRow(raw.isEmpty ? {'reason_ar': reasonAr, 'reason_en': reasonEn} : raw).reason;

  /// What the row opens (AppNavigator.openLink). A vote row (module org_council, id = the session) names the agenda
  /// item in `item_id`: the session opens focused on that item's vote.
  NotifLink get link {
    final base = raw.isEmpty ? {'action': action.name, 'module': module, 'id': id, 'org_id': orgId, 'reason_ar': reasonAr, 'reason_en': reasonEn} : raw;
    final itemId = int.tryParse('${raw['item_id'] ?? ''}');
    return NotifLink.fromInboxRow({
      ...base,
      if (base['focus'] == null && module == 'org_council' && itemId != null) 'focus': 'agenda:$itemId',
    });
  }

  factory ActionInboxItem.fromJson(Map<String, dynamic> j) {
    final id = j['id'] == null ? null : asInt(j['id']);
    final org = j['org_id'] == null ? null : asInt(j['org_id']);
    return ActionInboxItem(
      key: asStr(j['key']).isEmpty ? '${j['module'] ?? ''}:${id ?? ''}' : asStr(j['key']),
      kind: asStr(j['kind']),
      action: notifActionOf(j['action']),
      title: [if (asStr(j['ref']).isNotEmpty) asStr(j['ref']), if (asStr(j['title']).isNotEmpty) asStr(j['title'])].join(' · '),
      reasonAr: j['reason_ar']?.toString(),
      reasonEn: j['reason_en']?.toString(),
      module: j['module']?.toString(),
      id: id,
      orgId: org,
      orgName: AppConfig.lang != 'ar' && asStr(j['org_name_en']).trim().isNotEmpty ? asStr(j['org_name_en']) : j['org_name']?.toString(),
      dueAt: orgParseUtc(j['due_at']),
      overdue: j['overdue'] == true,
      urgency: asInt(j['urgency']).clamp(0, 3),
      createdAt: orgParseUtc(j['created_at']),
      raw: j,
    );
  }

  static (List<ActionInboxItem>, int) parse(dynamic body) {
    final m = asMap(body);
    final items = [for (final x in asMapList(m['items'])) ActionInboxItem.fromJson(x)];
    return (items, m['total'] == null ? items.length : asInt(m['total']));
  }
}

/// The filter chips.
enum ActionInboxFilter { all, urgent, overdue }

List<ActionInboxItem> filterActionInbox(List<ActionInboxItem> items, ActionInboxFilter f) => switch (f) {
      ActionInboxFilter.all => items,
      ActionInboxFilter.urgent => [for (final x in items) if (x.urgency >= 2) x],
      ActionInboxFilter.overdue => [for (final x in items) if (x.overdue) x],
    };

String actionUrgencyLabel(int u) => switch (u) {
      3 => t('عاجل', 'Urgent'),
      2 => t('مهم', 'High'),
      1 => t('عادي', 'Normal'),
      _ => t('منخفض', 'Low'),
    };

/// The page size of the action inbox and the server's ceiling (`limit` ≤ 200).
const kActionInboxPage = 50;
const kActionInboxMax = 200;

/// The limit of the next "load more" (the server has no offset: the same list, longer), null when every row is in
/// or the server's ceiling is reached.
int? actionInboxNextLimit({required int limit, required int loaded, required int total}) {
  if (loaded >= total || loaded < limit || limit >= kActionInboxMax) return null;
  return (limit + kActionInboxPage).clamp(kActionInboxPage, kActionInboxMax);
}

/// The rows, plain values. The default is a Column (a short list inside another scroll view);
/// [NeedsMyActionList.sliver] is a lazy SliverList that builds only the rows on screen.
class NeedsMyActionList extends StatelessWidget {
  const NeedsMyActionList({super.key, required this.items, this.onOpen}) : asSliver = false;
  const NeedsMyActionList.sliver({super.key, required this.items, this.onOpen}) : asSliver = true;
  final List<ActionInboxItem> items;
  final ValueChanged<ActionInboxItem>? onOpen;
  final bool asSliver;

  @override
  Widget build(BuildContext context) {
    if (asSliver) {
      return SliverList.builder(itemCount: items.length, itemBuilder: (context, i) => NeedsMyActionRow(item: items[i], onOpen: onOpen));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final x in items) NeedsMyActionRow(item: x, onOpen: onOpen),
    ]);
  }
}

/// One row of the action inbox.
class NeedsMyActionRow extends StatelessWidget {
  const NeedsMyActionRow({super.key, required this.item, this.onOpen});
  final ActionInboxItem item;
  final ValueChanged<ActionInboxItem>? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final x = item;
    return Semantics(
      button: onOpen != null,
      label: actionInboxRowSemantics(x),
      excludeSemantics: true,
      onTap: onOpen == null ? null : () => onOpen!(x),
      child: AppCard(
          key: ValueKey('action_inbox.${x.key}'),
          margin: const EdgeInsets.only(bottom: AppSpace.xs),
          onTap: onOpen == null ? null : () => onOpen!(x),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(notifActionIcon(x.action), size: AppIconSize.lg, color: x.overdue || x.urgency >= 3 ? c.danger : (x.urgency == 2 ? c.warning : c.primary)),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(x.title.isEmpty ? notifActionLabel(x.action) : x.title,
                    style: AppType.row(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark), maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(x.reason.isEmpty ? notifActionLabel(x.action) : '${notifActionLabel(x.action)} · ${x.reason}',
                    style: AppType.meta(context).copyWith(color: c.textMedium), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: AppSpace.xxs),
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                  if (x.overdue) AppBadgePill(t('متأخر', 'Overdue'), color: c.danger, icon: Icons.schedule_rounded),
                  if (x.urgency >= 2) AppBadgePill(actionUrgencyLabel(x.urgency), color: x.urgency >= 3 ? c.danger : c.warning),
                  if (x.dueAt != null) AppBadgePill('${t('قبل', 'By')} ${AppTime.dateTime(x.dueAt!)}', color: c.textMedium, icon: Icons.event_rounded),
                  if ((x.orgName ?? '').isNotEmpty) AppBadgePill(x.orgName!, color: c.textMedium, icon: Icons.apartment_rounded),
                ]),
              ]),
            ),
            const SizedBox(width: AppSpace.xxs),
            Icon(Icons.chevron_right_rounded, size: AppIconSize.lg, color: c.textLight),
          ]),
        ),
    );
  }
}

/// What a screen reader says for one inbox row: the title, what is asked and why, then its flags.
String actionInboxRowSemantics(ActionInboxItem x) => [
      if (x.title.isNotEmpty) x.title,
      x.reason.isEmpty ? notifActionLabel(x.action) : '${notifActionLabel(x.action)}: ${x.reason}',
      if (x.overdue) t('متأخر', 'Overdue'),
      if (x.urgency >= 2) actionUrgencyLabel(x.urgency),
      if (x.dueAt != null) '${t('قبل', 'By')} ${AppTime.dateTime(x.dueAt!)}',
      if ((x.orgName ?? '').isNotEmpty) x.orgName!,
    ].join('. ');

class NeedsMyActionPage extends StatefulWidget {
  const NeedsMyActionPage({super.key, this.embedded = false});

  /// The body alone (tests, a host with its own header).
  final bool embedded;

  @override
  State<NeedsMyActionPage> createState() => _NeedsMyActionPageState();
}

class _NeedsMyActionPageState extends State<NeedsMyActionPage> {
  List<ActionInboxItem>? _items;
  int _total = 0;
  ApiException? _error;
  String _q = '';
  final _qc = TextEditingController();
  ActionInboxFilter _filter = ActionInboxFilter.all;
  int _seq = 0;
  int _limit = kActionInboxPage;
  bool _more = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qc.dispose();
    super.dispose();
  }

  /// The empty state's one action when a search or a filter hides everything: show all again.
  void _clearFilters() {
    _qc.clear();
    setState(() => _filter = ActionInboxFilter.all);
    if (_q.isNotEmpty) {
      _q = '';
      _load();
    }
  }

  /// [limit]: a longer list (load more); otherwise the first page again (open, search, pull to refresh, back from
  /// a row).
  Future<void> _load({int? limit}) async {
    final seq = ++_seq;
    _limit = limit ?? kActionInboxPage;
    if (_error != null || _more != (limit != null)) {
      setState(() {
        _error = null;
        _more = limit != null;
      });
    }
    try {
      final r = await ApiClient().get(kActionInboxPath, queryParams: {if (_q.isNotEmpty) 'q': _q, 'limit': _limit});
      if (!mounted || seq != _seq) return;
      final (items, total) = ActionInboxItem.parse(r);
      setState(() {
        _items = items;
        _total = total;
        _more = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = ApiException.from(e);
        _more = false;
      });
    }
  }

  /// Near the end of the list: the next rows, when the server holds more.
  void _maybeMore() {
    final items = _items;
    if (items == null || _more || _error != null) return;
    final next = actionInboxNextLimit(limit: _limit, loaded: items.length, total: _total);
    if (next != null) _load(limit: next);
  }

  /// AppSearchField calls this once per pause in typing (its own debounce); the same words again ask nothing.
  void _search(String v) {
    final q = v.trim();
    if (q == _q) return;
    _q = q;
    _load();
  }

  Future<void> _open(ActionInboxItem x) async {
    await AppNavigator.openLink(x.link);
    if (mounted) _load(); // what I just handled leaves the list
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final shown = items == null ? const <ActionInboxItem>[] : filterActionInbox(items, _filter);
    Widget? list;
    if (items == null && _error == null) {
      list = const AppListSkeleton(items: 5);
    } else if (_error != null && items == null) {
      list = AppErrorBox(error: _error!, onRetry: _load);
    } else if (shown.isEmpty) {
      final narrowed = _q.isNotEmpty || _filter != ActionInboxFilter.all;
      list = AppEmpty(
        key: const ValueKey('action_inbox.empty'),
        icon: narrowed ? Icons.search_off_rounded : Icons.task_alt_rounded,
        title: narrowed ? t('لا شيء يطابق', 'Nothing matches') : t('لا شيء ينتظرك', 'Nothing is waiting for you'),
        message: narrowed ? t('جرّب كلمة أخرى أو أزل التصفية.', 'Try another word or clear the filter.') : t('كل ما يحتاج إجراءك أُنجز.', 'Everything that needed your action is done.'),
        // one helpful action: show everything again, or check again for anything new
        actionLabel: narrowed ? t('عرض الكل', 'Show everything') : t('تحديث', 'Refresh'),
        onAction: narrowed ? _clearFilters : _load,
      );
    }
    final top = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSearchField(controller: _qc, hint: t('ابحث في ما ينتظرك', 'Search what is waiting for you'), onChanged: _search),
        if (_error != null && items != null) ...[
          // a refresh / search / load-more failed: the list stays, the reason and Retry above it
          AppSpace.gapXs,
          AppErrorBox(error: _error!, onRetry: _load),
        ],
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final f in ActionInboxFilter.values)
            AppChoiceChip(
              key: ValueKey('action_inbox.filter.${f.name}'),
              label: switch (f) {
                ActionInboxFilter.all => t('الكل', 'All'),
                ActionInboxFilter.urgent => t('عاجل', 'Urgent'),
                ActionInboxFilter.overdue => t('متأخر', 'Overdue'),
              },
              selected: _filter == f,
              onTap: () => setState(() => _filter = f),
            ),
        ]),
        if (items != null && _total > 0) ...[
          AppSpace.gapXs,
          Text(countText(_total, ar1: 'عنصر واحد ينتظرك', ar2: 'عنصران ينتظرانك', arFew: '$_total عناصر تنتظرك', arMany: '$_total عنصراً ينتظرك', en1: '1 item is waiting for you', en: '$_total items are waiting for you'),
              style: AppType.meta(context).copyWith(color: context.colors.textMedium)),
        ],
        AppSpace.gapSm,
        ?list,
      ]);
    const pad = EdgeInsets.symmetric(horizontal: AppSpace.md);
    final body = AppRefresh(
      onRefresh: _load,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 400) _maybeMore();
          return false;
        },
        child: CustomScrollView(slivers: [
          SliverPadding(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0), sliver: SliverToBoxAdapter(child: top)),
          // the rows: built as they scroll into view (a long inbox never lays out every card)
          if (list == null) SliverPadding(padding: pad, sliver: NeedsMyActionList.sliver(items: shown, onOpen: _open)),
          if (_more) const SliverPadding(padding: pad, sliver: SliverToBoxAdapter(child: AppListSkeleton(items: 2, padding: EdgeInsets.zero))),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
        ]),
      ),
    );
    if (widget.embedded) return body;
    return BasePage(useWebCard: true, width: AppWidth.reading, appBar: ScreenAppBar(title: t('ينتظر إجرائي', 'Needs my action')), child: body);
  }
}
