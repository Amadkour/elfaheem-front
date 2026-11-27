// lib/features/admin/governance/admin_roles_page.dart
//
// The super admin's roles and permissions editor (docs/redesign/api/governance.md §3). Two tabs:
//   Roles   the built-in Super admin and Admin (locked: never edited or deleted) and the custom roles; a role opens
//           its editor (both names, then its permissions as grouped AppSwitch rows); "New role" opens an empty one.
//   Admins  every admin with their role (a dropdown; a super admin always has everything).
// Kill switch `admin.roles`. Only the super admin opens it (the server answers 403 super_admin_only otherwise).
//
// RolePermissionsEditor is the plain-values part (tested by the layout harness).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/plural.dart' show countText;
import 'package:flutter_education_app/design/app_kit.dart';

import '../adm_kit.dart' show admRole;
import '../cfg_common.dart';
import '../sup/sup_kit.dart';
import 'gov_api.dart';

String _permCount(int n) =>
    countText(n, ar1: 'صلاحية واحدة', ar2: 'صلاحيتان', arFew: '{n} صلاحيات', arMany: '{n} صلاحية', en1: 'One permission', en: '{n} permissions');

String _adminCount(int n) =>
    countText(n, ar1: 'مدير واحد', ar2: 'مديران', arFew: '{n} مديرين', arMany: '{n} مديرًا', en1: 'One admin', en: '{n} admins');

/// The permission groups of a role as switch rows; [onChanged] null = read only (a built-in role).
class RolePermissionsEditor extends StatelessWidget {
  const RolePermissionsEditor({super.key, required this.catalog, required this.selected, this.onChanged});

  final List<PermGroup> catalog;
  final Set<String> selected;
  final void Function(String key, bool on)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (var g = 0; g < catalog.length; g++) ...[
        if (g > 0) AppSpace.gapMd,
        SupCard(
          title: catalog[g].title,
          subtitle: '${catalog[g].items.where((i) => selected.contains(i.key)).length} / ${catalog[g].items.length}',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            for (final it in catalog[g].items)
              AppSwitchTile(
                key: ValueKey('roles.perm.${it.key}'),
                title: it.title,
                value: selected.contains(it.key),
                onChanged: onChanged == null ? null : (v) => onChanged!(it.key, v),
              ),
          ]),
        ),
      ],
    ]);
  }
}

class AdminRolesPage extends StatefulWidget {
  const AdminRolesPage({super.key});

  @override
  State<AdminRolesPage> createState() => _AdminRolesPageState();
}

class _AdminRolesPageState extends State<AdminRolesPage> {
  final _api = GovApi();
  RolesOverview? _data;
  Object? _error;
  int _tab = 0;
  int? _assigning;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _api.roles();
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (_data == null) {
        setState(() => _error = e);
      } else {
        showAppNotice(cfgErrorMessage(e), error: true);
      }
    }
  }

  Future<void> _open(AdminRoleModel? role) async {
    final d = _data;
    if (d == null) return;
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => AdminRoleEditorPage(role: role, catalog: d.catalog, api: _api)));
    if (changed == true) _load();
  }

  Future<void> _assign(AdminPerson p, int? roleId) async {
    setState(() => _assigning = p.id);
    try {
      await _api.assign(p.id, roleId);
      showAppNotice('ow_ro_assigned'.tr);
      await _load();
    } catch (e) {
      showAppNotice(cfgErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _assigning = null);
    }
  }

  List<Widget> _roles(RolesOverview d) => [
        for (var i = 0; i < d.roles.length; i++) ...[
          if (i > 0) AppSpace.gapSm,
          AppCard(
            child: AppTile(
              key: ValueKey('roles.role.${d.roles[i].key}'),
              icon: d.roles[i].builtin ? Icons.lock_rounded : Icons.badge_rounded,
              title: d.roles[i].name,
              subtitle: [_permCount(d.roles[i].permissions.length), _adminCount(d.roles[i].adminsCount)].join(' · '),
              trailing: d.roles[i].builtin ? AppStatusBadge(label: 'ow_ro_builtin'.tr, dense: true) : null,
              onTap: () => _open(d.roles[i]),
            ),
          ),
        ],
      ];

  List<Widget> _admins(RolesOverview d) {
    final choices = [for (final r in d.roles) if (r.key != 'super_admin') r];
    return [
      if (d.admins.isEmpty) AppEmpty(icon: Icons.group_off_rounded, title: 'ow_ro_no_admins'.tr),
      for (var i = 0; i < d.admins.length; i++) ...[
        if (i > 0) AppSpace.gapSm,
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(d.admins[i].name, style: AppType.section(context), maxLines: 2, overflow: TextOverflow.ellipsis),
            AppSpace.gapXs,
            if (d.admins[i].isSuper)
              Text('ow_ro_super_fixed'.tr, style: AppType.meta(context))
            else
              AppDropdown<int>(
                key: ValueKey('roles.assign.${d.admins[i].id}'),
                value: d.admins[i].roleId,
                enabled: _assigning == null,
                decoration: InputDecoration(labelText: 'ow_ro_role'.tr),
                items: [for (final r in choices) DropdownMenuItem(value: r.id, child: Text(r.name))],
                onChanged: (v) {
                  if (v == null || v == d.admins[i].roleId) return;
                  final role = choices.firstWhere((r) => r.id == v);
                  _assign(d.admins[i], role.builtin ? null : v);
                },
              ),
          ]),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final custom = d?.roles.where((r) => !r.builtin).length ?? 0;
    return SupPage(
      pageKey: const ValueKey(kAdminRolesKey),
      role: admRole(context),
      title: 'ow_ro_title'.tr,
      kicker: 'ow_gov_kicker'.tr,
      headline: 'ow_ro_head'.tr,
      line: 'ow_ro_line'.tr,
      actions: [
        if (d != null) SupHeroButton(label: 'ow_ro_new'.tr, icon: Icons.add_rounded, onTap: () => _open(null)),
      ],
      stats: [
        if (d != null) AppHeroStat(value: '$custom', label: 'ow_ro_custom'.tr),
        if (d != null) AppHeroStat(value: '${d.admins.length}', label: 'ow_ro_tab_admins'.tr),
      ],
      tabs: [AppTabItem('ow_ro_tab_roles'.tr), AppTabItem('ow_ro_tab_admins'.tr)],
      tab: _tab,
      onTab: (i) => setState(() => _tab = i),
      onRefresh: _load,
      helpPageId: 'admin.users',
      width: AppWidth.content,
      body: _error != null && d == null
          ? cfgErrorState(_error, onRetry: _load)
          : d == null
              ? const AppListSkeleton(withAvatar: false)
              : ListView(padding: SupPage.bodyPadding(context), children: _tab == 0 ? _roles(d) : _admins(d)),
    );
  }
}

/// One role's editor: both names and the permission switches; Save, and Delete for a custom role. Pops true when
/// something changed.
class AdminRoleEditorPage extends StatefulWidget {
  const AdminRoleEditorPage({super.key, required this.role, required this.catalog, required this.api});

  final AdminRoleModel? role;
  final List<PermGroup> catalog;
  final GovApi api;

  @override
  State<AdminRoleEditorPage> createState() => _AdminRoleEditorPageState();
}

class _AdminRoleEditorPageState extends State<AdminRoleEditorPage> {
  late final _ar = TextEditingController(text: widget.role?.nameAr ?? '');
  late final _en = TextEditingController(text: widget.role?.nameEn ?? '');
  late Set<String> _perms = {...?widget.role?.permissions};
  bool _busy = false;

  bool get _locked => widget.role?.builtin ?? false;

  bool get _dirty {
    final r = widget.role;
    if (_locked) return false;
    if (r == null) return _ar.text.trim().isNotEmpty || _en.text.trim().isNotEmpty || _perms.isNotEmpty;
    return _ar.text.trim() != r.nameAr || _en.text.trim() != r.nameEn || !_sameSet(_perms, r.permissions.toSet());
  }

  static bool _sameSet(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

  @override
  void dispose() {
    _ar.dispose();
    _en.dispose();
    super.dispose();
  }

  List<String> get _ordered => [for (final g in widget.catalog) for (final i in g.items) if (_perms.contains(i.key)) i.key];

  Future<void> _save() async {
    final ar = _ar.text.trim(), en = _en.text.trim().isEmpty ? _ar.text.trim() : _en.text.trim();
    if (ar.length < 2) {
      showAppNotice('ow_ro_name_short'.tr, error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final r = widget.role;
      if (r == null) {
        await widget.api.createRole(ar, en, _ordered);
      } else {
        await widget.api.updateRole(r.id, ar, en, _ordered);
      }
      showAppNotice('ow_ro_saved'.tr);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      showAppNotice(cfgErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final r = widget.role;
    if (r == null) return;
    final yes = await appConfirm(context, message: 'ow_ro_delete_q'.tr, danger: true, confirmLabel: 'ow_ro_delete'.tr);
    if (!yes || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.deleteRole(r.id);
      showAppNotice('ow_ro_deleted'.tr);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      showAppNotice(cfgErrorMessage(e), error: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.role;
    return SupPage(
      role: admRole(context),
      title: r == null ? 'ow_ro_new'.tr : r.name,
      kicker: 'ow_ro_title'.tr,
      headline: r == null ? 'ow_ro_new_head'.tr : r.name,
      line: _locked ? 'ow_ro_locked'.tr : _permCount(_perms.length),
      dirty: _dirty,
      width: AppWidth.form,
      actions: [
        if (!_locked) cfgSaveButton(dirty: _dirty, busy: _busy, onSave: _save),
        if (r != null && !_locked) SupHeroButton(label: 'ow_ro_delete'.tr, icon: Icons.delete_outline_rounded, onTap: _busy ? null : _delete),
      ],
      body: ListView(padding: SupPage.bodyPadding(context), children: [
        SupCard(
          title: 'ow_ro_names'.tr,
          icon: Icons.badge_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            AppField(
                key: const ValueKey('roles.name_ar'),
                controller: _ar,
                label: 'ow_ro_name_ar'.tr,
                required: true,
                readOnly: _locked,
                maxLength: 120,
                onChanged: (_) => setState(() {})),
            AppSpace.gapSm,
            AppField(
                key: const ValueKey('roles.name_en'),
                controller: _en,
                label: 'ow_ro_name_en'.tr,
                readOnly: _locked,
                ltr: true,
                maxLength: 120,
                onChanged: (_) => setState(() {})),
          ]),
        ),
        AppSpace.gapMd,
        RolePermissionsEditor(
          catalog: widget.catalog,
          selected: _perms,
          onChanged: _locked ? null : (k, on) => setState(() => _perms = on ? ({..._perms, k}) : ({..._perms}..remove(k))),
        ),
      ]),
    );
  }
}
