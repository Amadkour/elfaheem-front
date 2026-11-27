// lib/features/admin/governance/audit_log_page.dart
//
// The admin activity log (docs/redesign/api/governance.md §2): every write an admin or the super admin made, newest
// first, filtered by person, action and a day range, 50 at a time with "Load more". A row opens its details (the
// route, the target, the answer, the address, the device and the short summary of what was sent; the server never
// keeps secrets). Times through AppTime. Kill switch `admin.audit_log`.
//
// AuditLogTile is the plain-values row (tested by the layout harness).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart' show countText;
import 'package:flutter_education_app/design/app_kit.dart';

import '../adm_kit.dart' show admRole;
import '../cfg_common.dart';
import '../sup/sup_kit.dart';
import 'gov_api.dart';

/// "publish_queue.approve" → a translated name when the app knows it, else the server's text as is.
String auditActionLabel(String action) {
  final key = 'ow_al_act_${action.replaceAll('.', '_')}';
  final t = key.tr;
  return t == key ? action : t;
}

class AuditLogTile extends StatelessWidget {
  const AuditLogTile({super.key, required this.row, this.onTap});

  final AuditRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final at = row.at;
    return AppTile(
      icon: switch (row.method) {
        'DELETE' => Icons.delete_outline_rounded,
        'POST' => Icons.add_circle_outline_rounded,
        _ => Icons.edit_note_rounded,
      },
      tone: row.ok ? null : context.colors.kit.error,
      title: auditActionLabel(row.action),
      subtitle: [row.actorName, if (row.target.isNotEmpty) row.target, if (at != null) AppTime.dateTime(at)].join(' · '),
      onTap: onTap,
      trailing: row.ok ? null : AppStatusBadge(label: '${row.statusCode}', tone: AppTone.danger, dense: true),
    );
  }
}

/// The details of one row (a sheet).
class AuditLogDetails extends StatelessWidget {
  const AuditLogDetails({super.key, required this.row});

  final AuditRow row;

  @override
  Widget build(BuildContext context) {
    Widget line(String label, String? value) => (value ?? '').isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: AppType.meta(context)),
              Text(value!, style: AppType.body(context), softWrap: true),
            ]),
          );
    final changes = row.changes.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSheetHeader(auditActionLabel(row.action)),
        line('ow_al_who'.tr, row.actorRole.isEmpty ? row.actorName : '${row.actorName} (${row.actorRole})'),
        line('ow_al_when'.tr, row.at == null ? null : AppTime.dateTime(row.at!)),
        line('ow_al_target'.tr, row.target),
        line('ow_al_route'.tr, '${row.method} ${row.path}'),
        line('ow_al_result'.tr, '${row.statusCode} · ${(row.ok ? 'ow_al_ok' : 'ow_al_refused').tr}'),
        line('ow_al_ip'.tr, row.ip),
        line('ow_al_device'.tr, row.userAgent),
        line('ow_al_summary'.tr, row.summary),
        line('ow_al_changes'.tr, changes),
      ]),
    );
  }
}

class AdminAuditLogPage extends StatefulWidget {
  const AdminAuditLogPage({super.key});

  @override
  State<AdminAuditLogPage> createState() => _AdminAuditLogPageState();
}

class _AdminAuditLogPageState extends State<AdminAuditLogPage> {
  final _api = GovApi();
  AuditFilter _f = const AuditFilter();
  AuditFacets _facets = const AuditFacets();
  final List<AuditRow> _rows = [];
  int _page = 1, _total = 0;
  bool _hasMore = false, _loading = true, _more = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _api.facets().then((f) {
      if (mounted) setState(() => _facets = f);
    }).catchError((_) {});
  }

  Future<void> _load({bool more = false}) async {
    setState(() => more ? _more = true : _loading = true);
    try {
      final p = await _api.audit(_f, page: more ? _page + 1 : 1);
      if (!mounted) return;
      setState(() {
        if (!more) _rows.clear();
        _rows.addAll(p.items);
        _page = more ? _page + 1 : 1;
        _total = p.total;
        _hasMore = p.hasMore;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (_rows.isEmpty) {
        setState(() => _error = e);
      } else {
        showAppNotice(cfgErrorMessage(e), error: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _more = false;
        });
      }
    }
  }

  void _apply(AuditFilter f) {
    _f = f;
    _load();
  }

  Future<void> _pickDay(bool from) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: (from ? _f.from : _f.to) ?? now,
      firstDate: DateTime(2024),
      lastDate: now,
    );
    if (d == null || !mounted) return;
    _apply(AuditFilter(
      actorId: _f.actorId,
      action: _f.action,
      from: from ? d : _f.from,
      to: from ? _f.to : d,
    ));
  }

  Widget _filters(BuildContext context) {
    final actor = AppDropdown<int>(
      key: const ValueKey('audit_log.actor'),
      value: _f.actorId ?? 0,
      decoration: InputDecoration(labelText: 'ow_al_f_actor'.tr),
      items: [
        DropdownMenuItem(value: 0, child: Text('ow_al_everyone'.tr)),
        for (final a in _facets.actors) DropdownMenuItem(value: a.id, child: Text(a.name.isEmpty ? '#${a.id}' : a.name)),
      ],
      onChanged: (v) => _apply(AuditFilter(actorId: v == 0 ? null : v, action: _f.action, from: _f.from, to: _f.to)),
    );
    final action = AppDropdown<String>(
      key: const ValueKey('audit_log.action'),
      value: _f.action ?? '',
      decoration: InputDecoration(labelText: 'ow_al_f_action'.tr),
      items: [
        DropdownMenuItem(value: '', child: Text('ow_al_all_actions'.tr)),
        for (final a in _facets.actions) DropdownMenuItem(value: a, child: Text(auditActionLabel(a))),
      ],
      onChanged: (v) => _apply(AuditFilter(actorId: _f.actorId, action: (v ?? '').isEmpty ? null : v, from: _f.from, to: _f.to)),
    );
    String day(DateTime? d) => d == null ? '—' : AppTime.wall(d);
    final days = Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
      AppButton.secondary(
          label: '${'ow_al_from'.tr}: ${day(_f.from)}', icon: Icons.event_rounded, size: AppButtonSize.sm, onPressed: () => _pickDay(true)),
      AppButton.secondary(
          label: '${'ow_al_to'.tr}: ${day(_f.to)}', icon: Icons.event_rounded, size: AppButtonSize.sm, onPressed: () => _pickDay(false)),
      if (!_f.isEmpty)
        AppButton.ghost(
            label: 'ow_al_clear'.tr, icon: Icons.filter_alt_off_rounded, size: AppButtonSize.sm, onPressed: () => _apply(const AuditFilter())),
    ]);
    return AppCard(
      child: LayoutBuilder(builder: (context, box) {
        final narrow = box.maxWidth < AppWidth.form.max * .8;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          if (narrow) ...[actor, AppSpace.gapSm, action] else Row(children: [Expanded(child: actor), AppSpace.gapSm, Expanded(child: action)]),
          AppSpace.gapSm,
          days,
        ]);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = <Widget>[
      _filters(context),
      AppSpace.gapMd,
      if (_loading && _rows.isEmpty)
        const AppListSkeleton(withAvatar: false)
      else if (_rows.isEmpty)
        AppEmpty(icon: Icons.history_rounded, title: 'ow_al_empty'.tr, message: 'ow_al_empty_d'.tr)
      else
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < _rows.length; i++) ...[
              if (i > 0) AppSpace.gapXs,
              AuditLogTile(
                row: _rows[i],
                onTap: () => showAppSheet<void>(context, (_) => AuditLogDetails(row: _rows[i])),
              ),
            ],
          ]),
        ),
      if (_hasMore) ...[
        AppSpace.gapMd,
        Center(
          child: AppButton.secondary(
              label: 'ow_al_more'.tr, icon: Icons.expand_more_rounded, busy: _more, onPressed: _more ? null : () => _load(more: true)),
        ),
      ],
    ];
    return SupPage(
      pageKey: const ValueKey(kAuditLogKey),
      role: admRole(context),
      title: 'ow_al_title'.tr,
      kicker: 'ow_gov_kicker'.tr,
      headline: 'ow_al_head'.tr,
      line: _loading && _rows.isEmpty
          ? 'ow_al_line'.tr
          : countText(_total,
              ar1: 'عملية واحدة', ar2: 'عمليتان', arFew: '{n} عمليات', arMany: '{n} عملية', en1: 'One action', en: '{n} actions'),
      onRefresh: _load,
      helpPageId: 'admin.users',
      width: AppWidth.content,
      body: _error != null && _rows.isEmpty
          ? cfgErrorState(_error, onRetry: _load)
          : ListView(padding: SupPage.bodyPadding(context), children: list),
    );
  }
}
