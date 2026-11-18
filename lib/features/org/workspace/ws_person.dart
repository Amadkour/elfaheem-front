// lib/features/org/workspace/ws_person.dart
//
// A person's details in one unit of the teacher workspace (D-1152 / D-1153, docs/teacher-org/PLAN.md): a hero
// (avatar, name, @username, kind, title), a data card (email / phone only when the server sends them — a member
// never gets contact data), and the history timeline from `org_audit_log`, grouped by day, paged by cursor. The
// header of the timeline says whose actions it holds: everyone's (I manage the unit) or only mine. A manager can
// remove the person from the unit (confirm + Undo through `op: restore`).
//
// The plain-value parts ([WsPersonHero], [WsPersonFacts], [WsHistoryList]) take no controller, so the layout
// harness pumps them without a network (test/org/ws_units_test.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_icons.dart' show DirIcons;
import 'package:flutter_education_app/core/api_client.dart' show ApiException;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPushedPage;
import '../org_providers.dart' show OrgSession;
import '../org_v3.dart' show OrgCall, orgErrorText;
import 'ws_models.dart';
import 'ws_shell.dart' show WsController;

/// Bumped whenever people were removed or restored from a details page or a bulk action: every open people list
/// of the workspace reloads on it (an Undo may run after the page that started it is gone).
final wsPeopleChanged = ValueNotifier<int>(0);

/// Pushes [page] with the organization session and the workspace controller of [context] carried over (a pushed
/// route sits outside the dashboard's providers).
Future<T?> wsPushPage<T>(BuildContext context, WsController ws, Widget page) {
  OrgSession? session;
  try {
    session = context.read<OrgSession>();
  } catch (_) {}
  Widget child = ChangeNotifierProvider<WsController>.value(value: ws, child: page);
  if (session != null) child = ChangeNotifierProvider<OrgSession>.value(value: session, child: child);
  return Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => child));
}

/// The bilingual label of a person's kind in a unit.
String wsKindLabel(WsPersonKind k) => switch (k) {
      WsPersonKind.head => t('رئيس', 'Head'),
      WsPersonKind.team => t('فريق العمل', 'Team'),
      WsPersonKind.member => t('عضو', 'Member'),
    };

AppTone wsKindTone(WsPersonKind k) => switch (k) {
      WsPersonKind.head => AppTone.gold,
      WsPersonKind.team => AppTone.info,
      WsPersonKind.member => AppTone.neutral,
    };

/// The text of a server code (bulk `failed` rows, refusals): the workspace's own codes here, the rest through
/// [orgErrorText].
String wsCodeText(String code) => switch (code) {
      'is_self' => t('لا يمكنك إزالة نفسك', "You can't remove yourself"),
      'is_head' => t('لا يمكن إزالة رئيس القسم من هنا', "A head can't be removed here"),
      'not_in_unit' => t('لم يعد في هذا القسم', 'No longer in this department'),
      'not_manager' => t('هذا الإجراء لمدير القسم فقط', 'Only a manager of this department can do this'),
      'person_not_found' => t('لم يُعثر على هذا الشخص في القسم', "This person isn't in the department"),
      _ => orgErrorText(ApiException(statusCode: 0, message: code, code: code)),
    };

/// The text of a failed call: a known workspace code first, else [orgErrorText].
String wsCallText(OrgCall r) {
  final c = r.code;
  if (c != null && const {'is_self', 'is_head', 'not_in_unit', 'not_manager', 'person_not_found'}.contains(c)) return wsCodeText(c);
  return r.error == null ? '' : orgErrorText(r.error!);
}

/// What "joined via" says: the server's `joined_via` (`team` for a team seat, else the membership's
/// auto · approval · code · manual); an unknown key is shown as is.
String wsJoinedViaLabel(String v) => switch (v) {
      'team' => t('مقعد في فريق العمل', 'A team seat'),
      'auto' => t('انضمام تلقائي', 'Joined automatically'),
      'approval' => t('طلب انضمام مقبول', 'Join request approved'),
      'code' => t('رمز الانضمام', 'Join code'),
      'manual' => t('أضافه مسؤول', 'Added by a manager'),
      _ => v,
    };

/// Opens a person's details in a unit: their data + history (D-1152 / D-1153).
Future<void> openWsPerson(BuildContext context, WsController ws, {required int unitId, required int userId}) async {
  final unit = ws.home?.unit(unitId);
  await wsPushPage<void>(
    context,
    ws,
    OrgPushedPage(
      title: t('تفاصيل الشخص', 'Person details'),
      subtitle: unit?.name,
      width: AppWidth.reading,
      child: _WsPersonPage(unitId: unitId, userId: userId, manages: unit?.manages ?? false),
    ),
  );
}

class _WsPersonPage extends StatefulWidget {
  const _WsPersonPage({required this.unitId, required this.userId, required this.manages});
  final int unitId, userId;
  final bool manages;

  @override
  State<_WsPersonPage> createState() => _WsPersonPageState();
}

class _WsPersonPageState extends State<_WsPersonPage> {
  WsPersonDetail? _d;
  OrgCall? _error;
  bool _loading = true, _more = false, _busy = false;
  final _history = <WsHistoryRow>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ws = context.read<WsController>();
    setState(() {
      _loading = true;
      _error = null;
    });
    final (d, r) = await ws.api.person(widget.unitId, widget.userId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (d != null) {
        _d = d;
        _history
          ..clear()
          ..addAll(d.history);
      } else {
        _error = r;
      }
    });
  }

  Future<void> _loadMore() async {
    final cursor = _d?.nextCursor;
    if (cursor == null || _more) return;
    final ws = context.read<WsController>();
    setState(() => _more = true);
    final (d, r) = await ws.api.person(widget.unitId, widget.userId, cursor: cursor);
    if (!mounted) return;
    setState(() {
      _more = false;
      if (d != null) {
        _history.addAll(d.history);
        _d = WsPersonDetail(person: _d!.person, historyAll: _d!.historyAll, history: _history, nextCursor: d.nextCursor);
      }
    });
    if (d == null) showAppNotice(wsCallText(r), error: true);
  }

  Future<void> _remove() async {
    final d = _d;
    if (d == null || _busy) return;
    final ws = context.read<WsController>();
    final ok = await appConfirm(
      context,
      danger: true,
      confirmLabel: t('إزالة', 'Remove'),
      message: t('إزالة ${d.person.name} من هذا القسم؟', 'Remove ${d.person.name} from this department?'),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final r = await ws.api.remove(widget.unitId, [d.person.userId]);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) return; // orgCall already showed the refusal
    final m = r.map;
    final failed = [for (final f in (m['failed'] is List ? m['failed'] as List : const [])) if (f is Map) '${f['code'] ?? ''}'];
    final removed = [for (final x in (m['removed'] is List ? m['removed'] as List : const [])) if (x is Map) x.cast<String, dynamic>()];
    if (failed.isNotEmpty && removed.isEmpty) {
      showAppNotice(wsCodeText(failed.first), error: true);
      return;
    }
    wsPeopleChanged.value++;
    final unitId = widget.unitId;
    showAppNotice(
      t('أُزيل ${d.person.name} من القسم', '${d.person.name} was removed from the department'),
      actionLabel: t('تراجع', 'Undo'),
      onAction: () async {
        final u = await ws.api.restore(unitId, removed);
        if (u.ok) {
          wsPeopleChanged.value++;
          showAppNotice(t('أُعيد إلى القسم', 'Restored to the department'));
        }
      },
    );
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) {
      if (_loading) return const AppListSkeleton(items: 5);
      return AppErrorState(message: _error == null ? null : wsCallText(_error!), onRetry: _load);
    }
    final p = d.person;
    return AppRefresh(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.md),
        children: [
          WsPersonHero(person: p),
          AppSpace.gapMd,
          WsPersonFacts(person: p),
          if (widget.manages) ...[
            AppSpace.gapMd,
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton(
                label: t('إزالة من القسم', 'Remove from department'),
                icon: Icons.person_remove_alt_1_rounded,
                variant: AppButtonVariant.danger,
                busy: _busy,
                onPressed: _remove,
              ),
            ),
          ],
          AppSpace.gapLg,
          WsHistoryList(
            groups: wsHistoryByDay(_history),
            historyAll: d.historyAll,
            hasMore: d.nextCursor != null,
            loadingMore: _more,
            onLoadMore: _loadMore,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Plain-value parts
// ═════════════════════════════════════════════════════════════════════════════

/// The top of the details page: avatar, name, @username, kind and title.
class WsPersonHero extends StatelessWidget {
  const WsPersonHero({super.key, required this.person});
  final WsPerson person;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Row(children: [
        AppAvatar(name: person.name, url: person.avatarUrl, size: AppDashSize.avatarSm),
        AppSpace.gapMd,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text(person.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context))),
            if (person.username != null)
              Text('@${person.username}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.meta(context).copyWith(color: c.textMedium)),
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              AppStatusBadge(label: wsKindLabel(person.kind), tone: wsKindTone(person.kind), dense: true),
              if (person.title != null) Text(person.title!, style: AppType.meta(context).copyWith(color: c.textMedium)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// The person's data: email / phone only when present, joined date and how they joined.
class WsPersonFacts extends StatelessWidget {
  const WsPersonFacts({super.key, required this.person});
  final WsPerson person;

  @override
  Widget build(BuildContext context) {
    final rows = <(IconData, String, String, bool)>[
      if (person.email != null) (Icons.alternate_email_rounded, t('البريد', 'Email'), person.email!, true),
      if (person.phone != null) (Icons.phone_outlined, t('الهاتف', 'Phone'), person.phone!, true),
      if (person.joinedAt != null) (Icons.event_available_outlined, t('انضم في', 'Joined'), AppTime.date(person.joinedAt!.toUtc()), false),
      if (person.joinedVia != null) (DirIcons.login, t('طريقة الانضمام', 'Joined via'), wsJoinedViaLabel(person.joinedVia!), false),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return AppCard(
      child: Column(children: [
        for (final (i, (icon, label, value, ltr)) in rows.indexed) ...[
          if (i > 0) Divider(height: AppSpace.md, color: c.divider),
          Row(children: [
            Icon(icon, size: AppIconSize.md, color: c.textMedium),
            AppSpace.gapSm,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: AppType.meta(context).copyWith(color: c.textMedium)),
                SelectableText(value, textDirection: ltr ? TextDirection.ltr : null, style: AppType.row(context)),
              ]),
            ),
          ]),
        ],
      ]),
    );
  }
}

/// The history timeline: one block per day (newest first), its scope in the header, "Load more" by cursor.
class WsHistoryList extends StatelessWidget {
  const WsHistoryList({
    super.key,
    required this.groups,
    required this.historyAll,
    this.hasMore = false,
    this.loadingMore = false,
    this.onLoadMore,
  });

  final List<(DateTime, List<WsHistoryRow>)> groups;
  final bool historyAll, hasMore, loadingMore;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(header: true, child: Text(t('السجل', 'History'), style: AppType.section(context))),
      const SizedBox(height: AppSpace.xxs),
      Row(children: [
        Icon(historyAll ? Icons.groups_rounded : Icons.person_outline_rounded, size: AppIconSize.sm, color: c.textMedium),
        const SizedBox(width: AppSpace.xxs),
        Expanded(
          child: Text(
            historyAll ? t('سجل الجميع', "Everyone's history") : t('إجراءاتك فقط', 'Your actions only'),
            style: AppType.meta(context).copyWith(color: c.textMedium),
          ),
        ),
      ]),
      AppSpace.gapSm,
      if (groups.isEmpty)
        AppCard(child: Text(t('لا يوجد سجل بعد', 'No history yet'), style: AppType.body(context).copyWith(color: c.textMedium))),
      for (final (day, rows) in groups) ...[
        Padding(
          padding: const EdgeInsetsDirectional.only(top: AppSpace.sm, bottom: AppSpace.xs),
          child: Semantics(header: true, child: Text(day.year <= 1 ? t('بلا تاريخ', 'No date') : AppTime.wall(day), style: AppType.label(context))),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
          child: Column(children: [
            for (final (i, r) in rows.indexed) ...[
              if (i > 0) Divider(height: AppSpace.xs, color: c.divider),
              _HistoryRow(row: r),
            ],
          ]),
        ),
      ],
      if (hasMore)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.md),
          child: Center(
            child: AppButton(
              label: t('عرض المزيد', 'Load more'),
              icon: Icons.expand_more_rounded,
              variant: AppButtonVariant.secondary,
              busy: loadingMore,
              onPressed: onLoadMore,
            ),
          ),
        ),
    ]);
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.row});
  final WsHistoryRow row;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final actor = row.actorName.isEmpty ? t('النظام', 'System') : row.actorName;
    final text = row.summary.isNotEmpty ? row.summary : row.action;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppAvatar(name: actor, url: row.actorAvatar, size: AppTouch.min - AppSpace.md),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(text, style: AppType.row(context)),
              const SizedBox(height: AppSpace.xxs),
              Text(
                row.at == null ? actor : '$actor · ${AppTime.time(row.at!.toUtc())}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.meta(context).copyWith(color: c.textMedium),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
