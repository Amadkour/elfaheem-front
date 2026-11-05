// lib/features/org/org_effective_access.dart — "what can this person do?" in plain words (GET …/access/users/{uid}).
//
//   effectiveAccessRows(catalog, permissions)   pure: the catalog's modules in order, each with the actions the
//                                               person holds (full / partial / none) — unit-tested
//   OrgEffectiveAccessView                      the result drawn per module (org-wide) and per department
//
// `effective.permissions` is org-wide, `effective.dept_permissions` is {dept_id: {module: [actions]}}: what the
// person can do inside that department only.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../admin/admin_common.dart' show asMapList, t;

/// One module of the catalog and what the person may do in it.
class EffectiveRow {
  const EffectiveRow({required this.module, required this.label, required this.group, required this.allowed, required this.all});
  final String module, label, group;

  /// Action labels the person holds, in the catalog's order.
  final List<String> allowed;

  /// How many actions the module has.
  final int all;

  bool get none => allowed.isEmpty;
  bool get full => allowed.length >= all && all > 0;
}

/// The catalog's modules (those of [deptOnly] scope only when asked) with the actions held in [perms]
/// (`{module: {action, …}}`). Unknown modules in [perms] are ignored: the catalog is the source of truth.
List<EffectiveRow> effectiveAccessRows(Map<String, dynamic> catalog, Map<String, Set<String>> perms, {bool deptOnly = false}) {
  final actionLabel = {for (final a in asMapList(catalog['actions'])) '${a['key']}': t('${a['label_ar']}', '${a['label_en']}')};
  final groupOrder = [for (final g in asMapList(catalog['groups'])) '${g['key']}'];
  final rows = <EffectiveRow>[];
  for (final m in asMapList(catalog['modules'])) {
    if (deptOnly && m['scope'] != 'dept') continue;
    final key = '${m['key']}';
    final actions = [for (final a in (m['actions'] as List? ?? const [])) '$a'];
    final held = perms[key] ?? const <String>{};
    rows.add(EffectiveRow(
      module: key,
      label: t('${m['label_ar']}', '${m['label_en']}'),
      group: '${m['group'] ?? ''}',
      allowed: [for (final a in actions) if (held.contains(a)) actionLabel[a] ?? a],
      all: actions.length,
    ));
  }
  // keep the catalog's module order inside each group, groups in the catalog's group order
  final byGroup = <String, int>{for (var i = 0; i < groupOrder.length; i++) groupOrder[i]: i};
  final indexed = [for (var i = 0; i < rows.length; i++) (i, rows[i])];
  indexed.sort((a, b) {
    final ga = byGroup[a.$2.group] ?? 999, gb = byGroup[b.$2.group] ?? 999;
    return ga != gb ? ga.compareTo(gb) : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// "Result: what they can do now" — only the modules the person has any right in are listed, each with its actions;
/// the rest are one line ("nothing in: …"), so an admin reads the answer instead of hunting through a grid.
class OrgEffectiveAccessView extends StatelessWidget {
  const OrgEffectiveAccessView({super.key, required this.catalog, required this.orgWide, this.perDept = const {}, this.deptName});

  final Map<String, dynamic> catalog;
  final Map<String, Set<String>> orgWide;

  /// {dept id → permissions inside it}.
  final Map<int, Map<String, Set<String>>> perDept;
  final String Function(int id)? deptName;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final org = effectiveAccessRows(catalog, orgWide);
    final held = org.where((r) => !r.none).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('في كل المؤسسة', 'Across the whole organization'), style: AppType.bodyStrong(context)),
      AppSpace.gapXs,
      if (held.isEmpty)
        Text(t('لا يملك أي صلاحية على مستوى المؤسسة.', 'No rights across the whole organization.'), style: AppType.meta(context))
      else
        _rows(context, held),
      if (held.isNotEmpty && held.length < org.length) ...[
        AppSpace.gapXs,
        Text(
          t('بلا صلاحية في: ${org.where((r) => r.none).map((r) => r.label).join('، ')}', 'No rights in: ${org.where((r) => r.none).map((r) => r.label).join(', ')}'),
          style: AppType.meta(context).copyWith(color: c.textLight),
        ),
      ],
      for (final e in perDept.entries) ...[
        AppSpace.gapMd,
        Text('${t('داخل', 'Inside')} ${deptName?.call(e.key) ?? '#${e.key}'}', style: AppType.bodyStrong(context).copyWith(color: c.primary)),
        AppSpace.gapXs,
        _rows(context, effectiveAccessRows(catalog, e.value, deptOnly: true).where((r) => !r.none).toList()),
      ],
    ]);
  }

  Widget _rows(BuildContext context, List<EffectiveRow> rows) {
    final c = context.colors;
    return Column(children: [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Container(
            key: ValueKey('org.effective.${r.module}'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
            decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(r.label, style: AppType.row(context))),
                if (r.full) AppStatusBadge(label: t('كل الصلاحيات', 'Full'), tone: AppTone.success, dense: true),
              ]),
              AppSpace.gapXs,
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final a in r.allowed) AppStatusBadge(label: a, tone: AppTone.brand, dense: true),
              ]),
            ]),
          ),
        ),
    ]);
  }
}
