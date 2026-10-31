// lib/features/org/org_access_page.dart
//
//   OrgAccessPage        Roles (system + custom) · People & access   — module `roles`
//   OrgRoleEditor        name, colour, the permission matrix (drawn from the server catalog)
//   OrgPersonAccess      one person: roles (org-wide or per department) · personal grants (allow / deny / until)
//                        · the EFFECTIVE result, so the admin sees exactly what the person can do
//   OrgActivityPage      who did what, when — the governance trail (+ Excel)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_common.dart';
import 'org_page_header.dart' show OrgPageRefresh, OrgPushedPage, orgUsesDashboardHeader;
import 'org_page_kit.dart' show OrgMenuItem, OrgMoreMenu;
import 'org_providers.dart';
import 'org_ui.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppRefresh;
import 'package:flutter_education_app/design/context_switcher.dart' show ContextExitButton;
import 'package:flutter_education_app/core/display/app_fonts.dart';

/// The catalog is the same for the whole app session: fetch once.
Map<String, dynamic>? _catalogCache;

Future<Map<String, dynamic>?> orgCatalog(OrgSession s) async =>
    _catalogCache ??= await OrgApi.i.getMap('${s.base}/access/catalog');

/// A pushed page's readable column: the dashboard header keeps the page's full width (its one row needs the room),
/// the content stays as narrow as the older page was.
Widget _readable(double maxWidth, Widget child) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: SizedBox.expand(child: child)),
    );

class OrgAccessPage extends StatelessWidget {
  const OrgAccessPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(
          labelColor: c.primary,
          indicatorColor: c.primary,
          unselectedLabelColor: c.textMedium,
          labelStyle: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800),
          tabs: [
            Tab(icon: const Icon(Icons.badge_rounded), text: t('الأدوار', 'Roles')),
            Tab(icon: const Icon(Icons.manage_accounts_rounded), text: t('الأشخاص والصلاحيات', 'People & access')),
          ],
        ),
        const Expanded(child: TabBarView(children: [_RolesTab(), _PeopleTab()])),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Roles
// ═════════════════════════════════════════════════════════════════════════════

class _RolesTab extends StatefulWidget {
  const _RolesTab();

  @override
  State<_RolesTab> createState() => _RolesTabState();
}

class _RolesTabState extends State<_RolesTab> {
  List<Map<String, dynamic>>? _roles;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final r = await OrgApi.i.getMap('${context.read<OrgSession>().base}/access/roles');
    if (!mounted) return;
    setState(() {
      _roles = r == null ? _roles : asMapList(r['items']);
      _failed = r == null && _roles == null;
    });
  }

  Future<void> _open([Map<String, dynamic>? role]) async {
    final s = context.read<OrgSession>();
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(value: s, child: OrgRoleEditor(role: role))));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final c = context.colors;
    final roles = _roles;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: s.can('roles', 'insert')
          ? FloatingActionButton.extended(
              heroTag: 'role_new',
              backgroundColor: c.primary,
              onPressed: () => _open(),
              icon: Icon(Icons.add_rounded, color: c.onHero),
              label: Text(t('دور جديد', 'New role'), style: TextStyle(fontFamily: AppFonts.family, color: c.onHero)),
            )
          : null,
      body: OrgAsync(
        loading: roles == null && !_failed,
        failed: _failed,
        onRetry: _load,
        child: roles == null
            ? const SizedBox.shrink()
            : ListView(padding: const EdgeInsets.fromLTRB(0, 8, 0, 100), children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                      t('الدور = مجموعة صلاحيات باسم واضح. امنحه لشخص على مستوى المؤسسة أو لإدارة واحدة فقط.',
                          'A role is a named bundle of rights. Give it to someone for the whole organization or for one department.'),
                      style: orgText(context, size: 12.5, color: c.textMedium)),
                ),
                for (final r in roles)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: OrgActionCard(
                      icon: r['is_system'] == true ? Icons.verified_user_rounded : Icons.badge_rounded,
                      color: hexColor(r['color'], c.primary),
                      title: t('${r['name_ar'] ?? r['name_en']}', '${r['name_en'] ?? r['name_ar']}'),
                      subtitle: '${r['description'] ?? ''}'.isNotEmpty
                          ? '${r['description']}'
                          : t('${asMap(r['permissions']).length} وحدة · ${r['holders']} شخص', '${asMap(r['permissions']).length} modules · ${r['holders']} people'),
                      trailing: Column(mainAxisSize: MainAxisSize.min, children: [
                        OrgPill(t('${r['holders']} 👤', '${r['holders']} 👤'), color: c.textMedium),
                        if (r['inherited'] == true) ...[
                          const SizedBox(height: 4),
                          OrgPill(t('من المؤسسة الأم', 'From parent'), color: c.textLight),
                        ],
                      ]),
                      onTap: () => _open(r),
                    ),
                  ),
              ]),
      ),
    );
  }
}

class OrgRoleEditor extends StatefulWidget {
  const OrgRoleEditor({super.key, this.role});
  final Map<String, dynamic>? role;

  @override
  State<OrgRoleEditor> createState() => _OrgRoleEditorState();
}

class _OrgRoleEditorState extends State<OrgRoleEditor> {
  late final _ar = TextEditingController(text: '${widget.role?['name_ar'] ?? ''}');
  late final _en = TextEditingController(text: '${widget.role?['name_en'] ?? ''}');
  late final _desc = TextEditingController(text: '${widget.role?['description'] ?? ''}');
  late Map<String, Set<String>> _perms = permsFromJson(widget.role?['permissions']);
  late String _color = '${widget.role?['color'] ?? '#0F7B5F'}';
  Map<String, dynamic>? _catalog;
  bool _busy = false;

  bool get _editable => widget.role == null || widget.role?['editable'] == true;

  /// The dashboard header's Refresh must never rebuild the form (it would lose the typed name and rights).
  final _refresh = OrgPageRefresh()..attach(() async {});

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final c = await orgCatalog(context.read<OrgSession>());
      if (mounted) setState(() => _catalog = c);
    });
  }

  Future<void> _save() async {
    final s = context.read<OrgSession>();
    if (_ar.text.trim().isEmpty && _en.text.trim().isEmpty) {
      toast(t('اكتب اسم الدور', 'Enter a role name'), error: true);
      return;
    }
    setState(() => _busy = true);
    final body = {
      'name_ar': _ar.text.trim(),
      'name_en': _en.text.trim(),
      'description': _desc.text.trim(),
      'color': _color,
      'permissions': permsToJson(_perms),
    };
    final r = widget.role == null
        ? await OrgApi.i.post('${s.base}/access/roles', body, t('أُنشئ الدور', 'Role created'))
        : await OrgApi.i.put('${s.base}/access/roles/${widget.role!['id']}', body, t('حُفظت الصلاحيات', 'Saved'));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) Navigator.pop(context, r);   // the saved role (the member form selects a role created in place)
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.watch<OrgSession>();
    final system = widget.role?['is_system'] == true;
    final title = widget.role == null ? t('دور جديد', 'New role') : t('الدور وصلاحياته', 'Role & rights');
    final canDelete = widget.role != null && !system && s.can('roles', 'delete') && _editable;
    Future<void> delete() async {
      if (!await confirm(context, message: t('حذف الدور؟ يفقده كل من يحمله.', 'Delete the role? Everyone holding it loses it.'), danger: true)) return;
      if (await OrgApi.i.del('${s.base}/access/roles/${widget.role!['id']}', t('تم الحذف', 'Deleted')) != null && context.mounted) {
        Navigator.pop(context);
      }
    }

    final body = _body(context);
    if (orgUsesDashboardHeader(context, null)) {
      final name = widget.role == null ? '' : t('${widget.role!['name_ar'] ?? widget.role!['name_en'] ?? ''}', '${widget.role!['name_en'] ?? widget.role!['name_ar'] ?? ''}');
      return OrgPushedPage(
        title: title,
        subtitle: name.isEmpty ? null : name,
        refresh: _refresh,
        primaryAction: canDelete
            ? OrgMoreMenu(items: [
                OrgMenuItem(icon: Icons.delete_outline_rounded, label: t('حذف الدور', 'Delete role'), danger: true, onTap: delete),
              ])
            : null,
        child: _readable(820, body),
      );
    }
    return BasePage(
      useWebCard: true,
      maxWith: 820,
      appBar: ScreenAppBar(title: title, actions: [
        if (canDelete)
          IconButton(tooltip: t('حذف', 'Delete'), 
            icon: Icon(Icons.delete_outline_rounded, color: c.danger),
            onPressed: delete,
          ),
       const ContextExitButton()]),
      child: body,
    );
  }

  Widget _body(BuildContext context) {
    final c = context.colors;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
        if (!_editable)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(t('هذا الدور معرّف في المؤسسة الأم — للعرض هنا فقط.', 'Defined by the parent organization — read only here.'),
                style: orgText(context, color: c.warning)),
          ),
        Section(
          title: t('الهوية', 'Identity'),
          icon: Icons.badge_rounded,
          child: Column(children: [
            Field(controller: _ar, label: t('الاسم بالعربية — مثلاً: مسؤول القبول', 'Arabic name'), enabled: _editable),
            Field(controller: _en, label: t('الاسم بالإنجليزية', 'English name — e.g. Admission officer'), ltr: true, enabled: _editable),
            Field(controller: _desc, label: t('متى نستخدم هذا الدور؟', 'When is this role used?'), maxLines: 2, enabled: _editable),
            Wrap(spacing: 10, children: [
              for (final h in const ['#0F7B5F', '#2563EB', '#7C3AED', '#DB2777', '#EA580C', '#0891B2', '#475569'])
                GestureDetector(
                  onTap: _editable ? () => setState(() => _color = h) : null,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: hexColor(h, c.primary),
                      shape: BoxShape.circle,
                      border: Border.all(color: _color == h ? c.textDark : Colors.transparent, width: 2.5),
                    ),
                  ),
                ),
            ]),
          ]),
        ),
        Section(
          title: t('ماذا يستطيع حامل الدور أن يفعل؟', 'What can people with this role do?'),
          icon: Icons.tune_rounded,
          child: _catalog == null
              ? const AppListSkeleton(items: 3)
              : OrgPermissionMatrix(
                  catalog: _catalog!,
                  value: _perms,
                  readOnly: !_editable,
                  onChanged: (v) => setState(() => _perms = v),
                ),
        ),
        if (_editable)
          PrimaryButton(isLoading: _busy, label: t('حفظ', 'Save'), icon: Icons.check_rounded, iconBefore: true, onPressed: _save),
      ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  People & access
// ═════════════════════════════════════════════════════════════════════════════

class _PeopleTab extends StatelessWidget {
  const _PeopleTab();

  @override
  Widget build(BuildContext context) {
    final s = context.read<OrgSession>();
    return ChangeNotifierProvider(
      create: (_) => OrgPaged('${s.base}/members', {'role': 'teacher,teacher_assistant,admin_assistant'})..refresh(),
      child: Builder(builder: (context) {
        final p = context.read<OrgPaged>();
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: SearchBox(hint: t('ابحث عن موظف أو مدرس', 'Search staff or teachers'), onChanged: p.setSearch),
          ),
          Expanded(
            child: PagedList<OrgPaged>(
              emptyText: t('لا أحد بعد', 'Nobody yet'),
              itemBuilder: (context, row) {
                final u = asMap(row['user']);
                final teams = asMapList(row['departments']);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: RowCard(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ChangeNotifierProvider.value(value: s, child: OrgPersonAccess(userId: asInt(u['id']))))),
                    child: Row(children: [
                      AdminAvatar(name: '${u['name']}', url: u['image_url'] as String?),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${u['name']}', style: orgText(context, w: FontWeight.w800)),
                          Text(teams.isEmpty ? '${u['email']}' : teams.map((e) => e['title'] ?? '—').join(' · '),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12, color: context.colors.textMedium)),
                        ]),
                      ),
                      Icon(Icons.chevron_right_rounded, color: context.colors.textLight),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]);
      }),
    );
  }
}

class OrgPersonAccess extends StatefulWidget {
  const OrgPersonAccess({super.key, required this.userId});
  final int userId;

  @override
  State<OrgPersonAccess> createState() => _OrgPersonAccessState();
}

class _OrgPersonAccessState extends State<OrgPersonAccess> {
  Map<String, dynamic>? _d, _catalog;
  List<Map<String, dynamic>> _roles = [], _depts = [];
  bool _failed = false;

  String get _base => context.read<OrgSession>().base;

  /// The dashboard header's Refresh reloads this person in place; "Updated" is when it answered.
  final _refresh = OrgPageRefresh();

  @override
  void initState() {
    super.initState();
    _refresh.attach(_load);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = context.read<OrgSession>();
    final results = await Future.wait([
      OrgApi.i.getMap('$_base/access/users/${widget.userId}'),
      OrgApi.i.getMap('$_base/access/roles'),
      OrgApi.i.getMap('$_base/departments'),
    ]);
    _catalog ??= await orgCatalog(s);
    if (!mounted) return;
    setState(() {
      _d = results[0] ?? _d;
      _roles = asMapList(results[1]?['items']);
      _depts = asMapList(results[2]?['items']);
      _failed = _d == null;
    });
    if (results[0] != null) _refresh.markUpdated();
  }

  String _deptName(dynamic id) {
    if (id == null) return t('كل المؤسسة', 'Whole organization');
    final d = _depts.where((x) => x['id'] == id);
    return d.isEmpty ? '#$id' : orgNameOf(d.first);
  }

  Future<int?> _pickScope(BuildContext ctx, {bool allowOrg = true}) => showAdminSheet<int>(ctx, (c2) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          SheetHeader(t('أين تنطبق؟', 'Where does it apply?')),
          if (allowOrg)
            ListTile(
              leading: IconBadge(Icons.domain_rounded, c2.colors.primary, size: 38),
              title: Text(t('كل المؤسسة (وما تحتها)', 'Whole organization (and below)'), style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
              onTap: () => Navigator.pop(c2, 0),
            ),
          for (final d in _depts)
            ListTile(
              leading: IconBadge(deptIcon(d['icon']), hexColor(d['color'], c2.colors.primary), size: 38),
              title: Text(orgNameOf(d), style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
              onTap: () => Navigator.pop(c2, asInt(d['id'])),
            ),
        ],
      ));

  Future<void> _assignRole() async {
    final role = await showAdminSheet<Map<String, dynamic>>(context, (ctx) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            SheetHeader(t('منح دور', 'Give a role')),
            for (final r in _roles)
              ListTile(
                leading: IconBadge(Icons.badge_rounded, hexColor(r['color'], ctx.colors.primary), size: 38),
                title: Text(t('${r['name_ar'] ?? r['name_en']}', '${r['name_en'] ?? r['name_ar']}'),
                    style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
                subtitle: Text('${r['description'] ?? ''}', maxLines: 2),
                onTap: () => Navigator.pop(ctx, r),
              ),
          ],
        ));
    if (role == null || !mounted) return;
    final scope = await _pickScope(context);
    if (scope == null) return;
    final r = await OrgApi.i.post('$_base/access/users/${widget.userId}/roles',
        {'role_id': role['id'], 'dept_id': scope == 0 ? null : scope}, t('مُنح الدور', 'Role given'));
    if (r != null) _load();
  }

  Future<void> _grant() async {
    final scope = await _pickScope(context);
    if (scope == null || !mounted || _catalog == null) return;
    var allow = <String, Set<String>>{}, deny = <String, Set<String>>{};
    final note = TextEditingController();
    DateTime? until;
    bool busy = false;
    await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SheetHeader(t('صلاحيات خاصة — ${_deptName(scope == 0 ? null : scope)}', 'Personal rights — ${_deptName(scope == 0 ? null : scope)}')),
              Field(controller: note, label: t('السبب — مثلاً: قائم بالأعمال أثناء إجازة الرئيس', 'Why — e.g. acting head during leave')),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_busy_rounded),
                title: Text(until == null ? t('بدون تاريخ انتهاء', 'No end date') : '${t('تنتهي في', 'Ends on')} ${until!.toString().substring(0, 10)}',
                    style: TextStyle(fontFamily: AppFonts.family)),
                trailing: TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(context: ctx, firstDate: DateTime.now().add(const Duration(days: 1)),
                        lastDate: DateTime.now().add(const Duration(days: 730)));
                    if (d != null) set(() => until = d);
                  },
                  child: Text(t('اختر', 'Pick')),
                ),
              ),
              Text(t('مسموح', 'Allow'), style: orgText(ctx, w: FontWeight.w800, color: c.success)),
              OrgPermissionMatrix(catalog: _catalog!, value: allow, deptOnly: scope != 0, onChanged: (v) => set(() => allow = v)),
              const SizedBox(height: 10),
              Text(t('ممنوع (يتغلب على أي دور)', 'Deny (beats any role)'), style: orgText(ctx, w: FontWeight.w800, color: c.danger)),
              OrgPermissionMatrix(catalog: _catalog!, value: deny, deptOnly: scope != 0, tone: c.danger, onChanged: (v) => set(() => deny = v)),
              const SizedBox(height: 10),
              PrimaryButton(
                isLoading: busy,
                label: t('حفظ', 'Save'),
                onPressed: () async {
                  set(() => busy = true);
                  final r = await OrgApi.i.post('$_base/access/users/${widget.userId}/grants', {
                    'allow': permsToJson(allow),
                    'deny': permsToJson(deny),
                    'dept_id': scope == 0 ? null : scope,
                    'note': note.text.trim().isEmpty ? null : note.text.trim(),
                    'expires_at': until?.toIso8601String(),
                  }, t('تم الحفظ', 'Saved'));
                  if (!ctx.mounted) return;
                  set(() => busy = false);
                  if (r != null) Navigator.pop(ctx);
                },
              ),
            ]),
          );
        }));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.watch<OrgSession>();
    final d = _d;
    final canEdit = s.can('roles', 'update');
    final title = d == null ? t('الصلاحيات', 'Access') : '${asMap(d['user'])['name']}';
    final body = OrgAsync(
        loading: d == null && !_failed,
        failed: _failed,
        onRetry: _load,
        child: d == null
            ? const SizedBox.shrink()
            : AppRefresh(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
                  Section(
                    title: t('الأدوار', 'Roles'),
                    icon: Icons.badge_rounded,
                    trailing: canEdit ? TextButton.icon(onPressed: _assignRole, icon: const Icon(Icons.add_rounded), label: Text(t('منح', 'Give'))) : null,
                    child: asMapList(d['assignments']).isEmpty
                        ? Text(t('لا أدوار بعد', 'No roles yet'), style: orgText(context, color: c.textMedium))
                        : Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final a in asMapList(d['assignments']))
                              InputChip(
                                avatar: CircleAvatar(backgroundColor: hexColor(a['color'], c.primary), radius: 6),
                                label: Text('${t('${a['role_name_ar'] ?? a['role_name_en']}', '${a['role_name_en'] ?? a['role_name_ar']}')} · ${_deptName(a['dept_id'])}',
                                    style: TextStyle(fontFamily: AppFonts.family)),
                                onDeleted: canEdit && a['inherited'] != true
                                    ? () async {
                                        if (await OrgApi.i.del('$_base/access/assignments/${a['id']}', t('سُحب الدور', 'Role removed')) != null) _load();
                                      }
                                    : null,
                              ),
                          ]),
                  ),
                  Section(
                    title: t('صلاحيات خاصة', 'Personal rights'),
                    icon: Icons.key_rounded,
                    trailing: canEdit ? TextButton.icon(onPressed: _grant, icon: const Icon(Icons.add_rounded), label: Text(t('إضافة', 'Add'))) : null,
                    child: asMapList(d['grants']).isEmpty
                        ? Text(t('لا شيء — الأدوار تكفي في أغلب الحالات', 'None — roles are enough most of the time'),
                            style: orgText(context, color: c.textMedium))
                        : Column(children: [
                            for (final g in asMapList(d['grants']))
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: IconBadge(g['expired'] == true ? Icons.history_rounded : Icons.key_rounded,
                                    g['expired'] == true ? c.textLight : c.accent, size: 38),
                                title: Text('${g['note'] ?? t('صلاحيات خاصة', 'Personal rights')} · ${_deptName(g['dept_id'])}',
                                    style: orgText(context, w: FontWeight.w700)),
                                subtitle: Text(
                                    [
                                      if (asMap(g['allow']).isNotEmpty) '✓ ${asMap(g['allow']).keys.join('، ')}',
                                      if (asMap(g['deny']).isNotEmpty) '✗ ${asMap(g['deny']).keys.join('، ')}',
                                      if (g['expires_at'] != null) '⏳ ${shortDate('${g['expires_at']}')}',
                                    ].join('   '),
                                    style: orgText(context, size: 12, color: c.textMedium)),
                                trailing: canEdit && g['inherited'] != true
                                    ? IconButton(tooltip: t('حذف', 'Delete'), 
                                        icon: Icon(Icons.delete_outline_rounded, color: c.danger),
                                        onPressed: () async {
                                          if (await OrgApi.i.del('$_base/access/grants/${g['id']}', t('تم', 'Done')) != null) _load();
                                        })
                                    : null,
                              ),
                          ]),
                  ),
                  Section(
                    title: t('النتيجة: ما يستطيع فعله الآن', 'Result: what they can do now'),
                    icon: Icons.fact_check_rounded,
                    child: _catalog == null
                        ? const SizedBox.shrink()
                        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            OrgPermissionMatrix(catalog: _catalog!, value: permsFromJson(asMap(d['effective'])['permissions']),
                                readOnly: true, onChanged: (_) {}),
                            for (final e in asMap(asMap(d['effective'])['dept_permissions']).entries) ...[
                              const SizedBox(height: 8),
                              Text('${t('داخل', 'Inside')} ${_deptName(int.tryParse(e.key))}', style: orgText(context, w: FontWeight.w800, color: c.primary)),
                              OrgPermissionMatrix(catalog: _catalog!, value: permsFromJson(e.value), deptOnly: true, readOnly: true, onChanged: (_) {}),
                            ],
                          ]),
                  ),
                ]),
              ),
    );
    if (orgUsesDashboardHeader(context, null)) {
      return OrgPushedPage(
        title: title,
        subtitle: d == null ? null : t('الأدوار والصلاحيات', 'Roles & rights'),
        refresh: _refresh,
        child: _readable(860, body),
      );
    }
    return BasePage(
      useWebCard: true,
      maxWith: 860,
      appBar: ScreenAppBar(title: title, actions: const [ContextExitButton()]),
      child: body,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Activity log
// ═════════════════════════════════════════════════════════════════════════════

class OrgActivityPage extends StatelessWidget {
  const OrgActivityPage({super.key});

  static IconData _icon(String action) {
    final a = action.split('.').first;
    return switch (a) {
      'member' || 'request' => Icons.person_rounded,
      'role' || 'grant' => Icons.key_rounded,
      'dept' || 'team' => Icons.apartment_rounded,
      'ann' => Icons.campaign_rounded,
      'form' => Icons.assignment_rounded,
      'complaint' => Icons.support_agent_rounded,
      'course' || 'enrollment' => Icons.menu_book_rounded,
      'excel' => Icons.table_chart_rounded,
      'material' => Icons.folder_rounded,
      _ => Icons.domain_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<OrgSession>();
    return ChangeNotifierProvider(
      create: (_) => OrgPaged('${s.base}/audit')..refresh(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: s.can('audit', 'export')
            ? FloatingActionButton.small(
                heroTag: 'audit_x',
                backgroundColor: context.colors.primary,
                onPressed: () => downloadExcel(context, 'audit/export'),
                child: Icon(Icons.file_download_rounded, color: context.colors.onHero),
              )
            : null,
        body: PagedList<OrgPaged>(
          emptyText: t('لا نشاط بعد', 'No activity yet'),
          itemBuilder: (context, row) {
            final c = context.colors;
            final actor = asMap(row['actor']);
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Column(children: [
                  IconBadge(_icon('${row['action']}'), c.primary, size: 34),
                  Container(width: 2, height: 22, color: c.divider),
                ]),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${row['summary'] ?? row['action']}', style: orgText(context, size: 13)),
                    Text('${actor.isEmpty ? t('النظام', 'System') : actor['name']} · ${relTime(row['created_at'])}',
                        style: orgText(context, size: 11.5, color: c.textLight)),
                  ]),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }
}
