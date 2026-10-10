// lib/features/admin/admin_admins_page.dart
//
// Super-admin only: list / search / add / edit / delete admins.
// Same look & feel as admin_users_page.dart.
//
// Uses the EXISTING admin_panel.py endpoints (super-admin rules are enforced there):
//   GET    /api/v1/admin/users?role=admin&search=&page=1&size=20  -> {items, total, page, size, pages}
//   POST   /api/v1/admin/users        {role:"admin", name, gmail, password, phone?, country?}
//   PUT    /api/v1/admin/users/{id}   {name, gmail, phone, country, is_active, password?}
//   DELETE /api/v1/admin/users/{id}
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:provider/provider.dart';

import '../../utils/widget/app_bar.dart';
import '../../utils/widget/app_loading_indicator.dart';
import '../../utils/widget/base_page.dart';
import '../../utils/widget/primary_button.dart';
import 'admin_common.dart';
import 'admin_list.dart' show RowCard;
import 'admin_view_as_page.dart' show startViewAs;

class _AdminsApi {
  static const list = '/api/v1/admin/users';
  static String one(int id) => '/api/v1/admin/users/$id';
}

// ═════════════════════════════════════════════════════════════════════════════
//  Provider
// ═════════════════════════════════════════════════════════════════════════════

class AdminAdminsProvider extends ChangeNotifier {
  static const pageSize = 20;

  final _api = ApiClient();

  List<Map<String, dynamic>> items = [];
  bool loading = false;
  bool loadingMore = false;
  bool failed = false;
  bool hasMore = true;
  int _total = 0;
  String search = '';
  bool _disposed = false;
  int _gen = 0; // drops stale responses when the search changes mid-flight

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void setSearch(String v) {
    if (v == search) return;
    search = v;
    refresh();
  }

  List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is List) return asMapList(data);
    if (data is Map) {
      if (data['items'] is List) return asMapList(data['items']);
    }
    return [];
  }

  Future<void> refresh() async {
    final gen = ++_gen;
    loading = true;
    failed = false;
    hasMore = true;
    _notify();
    try {
      final data = await _api.get(_AdminsApi.list, queryParams: {
        'role': 'admin',
        if (search.isNotEmpty) 'search': search,
        'page': 1,
        'size': pageSize,
      });
      if (gen != _gen) return;
      items = _rows(data);
      _total = asInt(asMap(data)['total'], items.length);
      hasMore = items.length < _total;
    } catch (e) {
      if (gen != _gen) return;
      failed = true;
      items = [];
    }
    loading = false;
    _notify();
  }

  Future<void> loadMore() async {
    if (loading || loadingMore || !hasMore) return;
    final gen = _gen;
    loadingMore = true;
    _notify();
    try {
      final data = await _api.get(_AdminsApi.list, queryParams: {
        'role': 'admin',
        if (search.isNotEmpty) 'search': search,
        'page': items.length ~/ pageSize + 1,
        'size': pageSize,
      });
      if (gen != _gen) return;
      final next = _rows(data);
      final known = items.map((e) => asInt(e['id'])).toSet();
      items = [...items, ...next.where((e) => !known.contains(asInt(e['id'])))];
      _total = asInt(asMap(data)['total'], items.length);
      hasMore = next.isNotEmpty && items.length < _total;
    } catch (e) {
      toast(ApiException.from(e).message, error: true);
    }
    loadingMore = false;
    _notify();
  }

  Future<bool> create(Map<String, dynamic> body) async {
    try {
      await _api.post(_AdminsApi.list, body: body);
      toast('admin_admin_saved'.tr);
      await refresh();
      return true;
    } catch (e) {
      toast(ApiException.from(e).message, error: true);
      return false;
    }
  }

  Future<bool> update(int id, Map<String, dynamic> body) async {
    try {
      await _api.put(_AdminsApi.one(id), body: body);
      toast('admin_admin_saved'.tr);
      await refresh();
      return true;
    } catch (e) {
      toast(ApiException.from(e).message, error: true);
      return false;
    }
  }

  Future<bool> remove(int id) async {
    try {
      await _api.delete(_AdminsApi.one(id));
      items = items.where((e) => asInt(e['id']) != id).toList();
      toast('admin_admin_deleted'.tr);
      _notify();
      return true;
    } catch (e) {
      toast(ApiException.from(e).message, error: true);
      return false;
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class AdminAdminsPage extends StatelessWidget {
  const AdminAdminsPage({super.key, this.embedded = false});

  /// true when shown as a tab inside the dashboard shell (no AppBar).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    // Defence in depth: the server enforces super-admin on every call anyway.
    if (!isSuperNow(context)) {
      return BasePage(
        appBar: embedded ? null : ScreenAppBar(title: 'admin_admins'.tr),
        child: EmptyState('admin_super_admin_only'.tr, icon: Icons.lock_rounded),
      );
    }
    return ChangeNotifierProvider(
      create: (_) => AdminAdminsProvider()..refresh(),
      child: _AdminsView(embedded: embedded),
    );
  }
}

class _AdminsView extends StatefulWidget {
  const _AdminsView({required this.embedded});

  final bool embedded;

  @override
  State<_AdminsView> createState() => _AdminsViewState();
}

class _AdminsViewState extends State<_AdminsView> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
        context.read<AdminAdminsProvider>().loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminAdminsProvider>();
    final c = context.colors;

    final search = Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: SearchBox(
        hint: 'admin_search_name_email_or_phone'.tr,
        onChanged: p.setSearch,
      ),
    );

    Widget body;
    if (p.loading && p.items.isEmpty) {
      body = const Center(child: AppLoadingIndicator());
    } else if (p.failed) {
      body = ErrorRetry(
        message: 'admin_could_not_load_data'.tr,
        onRetry: p.refresh,
      );
    } else if (p.items.isEmpty) {
      body = EmptyState('admin_no_admins_found'.tr, icon: Icons.shield_outlined);
    } else {
      body = RefreshIndicator(
        onRefresh: p.refresh,
        child: ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 90),
          itemCount: p.items.length + (p.loadingMore ? 1 : 0),
          itemBuilder: (ctx, i) {
            if (i >= p.items.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: AppLoadingIndicator()),
              );
            }
            return _AdminTile(p.items[i]);
          },
        ),
      );
    }

    return BasePage(
      useWebCard: !widget.embedded,
      maxWith: 1100,
      enableFooterWidget: !widget.embedded,
      appBar: widget.embedded ? null : ScreenAppBar(title: 'admin_admins'.tr),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: "admins_float",
        key: ValueKey("admins_float"),
        backgroundColor: c.primary,
        onPressed: () => _openAdminForm(context, p),
        icon: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white),
        label: Text(
          'admin_add_admin'.tr,
          style: const TextStyle(fontFamily: 'tajawal', color: Colors.white),
        ),
      ),
      child: Column(
        children: [
          search,
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  const _AdminTile(this.row);

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminAdminsProvider>();
    final id = asInt(row['id']);
    final name = asStr(row['name']);
    final active = asBool(row['is_active'], true);
    final isSuperRow = asStr(row['role']) == 'super-admin';

    return RowCard(
      onTap: () => _openAdminForm(context, p, existing: row),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: c.primary.withValues(alpha: 0.15),
            child: Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: TextStyle(color: c.primary, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontWeight: FontWeight.w800,
                    color: c.textDark,
                  ),
                ),
                Text(
                  asStr(row['gmail']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontSize: 12,
                    color: c.textLight,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  StatusChip(
                    isSuperRow
                        ? 'admin_role_super_admin'.tr
                        : 'admin_role_admin'.tr,
                    isSuperRow ? c.warning : c.primary,
                  ),
                  StatusChip(
                    active ? 'exam_status_active'.tr : 'admin_inactive'.tr,
                    active ? c.success : c.warning,
                  ),
                ]),
              ],
            ),
          ),
          // Super-admin: open this admin's dashboard (read-only). Never another super-admin.
          if (!isSuperRow)
            IconButton(
              tooltip: 'view_as_user'.tr,
              icon: Icon(Icons.visibility_rounded, color: c.warning),
              onPressed: () => startViewAs(
                Navigator.of(context, rootNavigator: true),
                id: id,
                name: name,
                role: 'admin',
              ),
            ),
          IconButton(
            tooltip: 'btn_edit'.tr,
            icon: Icon(Icons.edit_rounded, color: c.primary),
            onPressed: () => _openAdminForm(context, p, existing: row),
          ),
          // A super-admin row can't be deleted from here (server also refuses).
          if (!isSuperRow)
            IconButton(
              tooltip: 'delete'.tr,
              icon: Icon(Icons.delete_outline_rounded, color: c.danger),
              onPressed: () async {
                final ok = await confirm(
                  context,
                  message: trp('admin_delete_admin_confirm', {'name': name}),
                  danger: true,
                );
                if (ok) await p.remove(id);
              },
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Create / edit form
// ═════════════════════════════════════════════════════════════════════════════

Future<void> _openAdminForm(
    BuildContext context,
    AdminAdminsProvider p, {
      Map<String, dynamic>? existing,
    }) {
  return showAdminSheet(
    context,
        (ctx) => _AdminForm(provider: p, existing: existing),
  );
}

class _AdminForm extends StatefulWidget {
  const _AdminForm({required this.provider, this.existing});

  final AdminAdminsProvider provider;
  final Map<String, dynamic>? existing;

  @override
  State<_AdminForm> createState() => _AdminFormState();
}

class _AdminFormState extends State<_AdminForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: asStr(widget.existing?['name']));
  late final _email = TextEditingController(text: asStr(widget.existing?['gmail']));
  late final _phone = TextEditingController(text: asStr(widget.existing?['phone']));
  late final _country = TextEditingController(
    text: asStr(widget.existing?['country']).isEmpty
        ? 'EG'
        : asStr(widget.existing?['country']),
  );
  final _password = TextEditingController();
  late bool _active = asBool(widget.existing?['is_active'], true);
  bool busy = false;

  bool get editing => widget.existing != null;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _country, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    final phone = _phone.text.trim();
    final country = _country.text.trim();
    final bool ok;
    if (editing) {
      ok = await widget.provider.update(asInt(widget.existing!['id']), {
        'name': _name.text.trim(),
        'gmail': _email.text.trim(),
        'phone': phone.isEmpty ? null : phone,
        'country': country.isEmpty ? null : country,
        'is_active': _active,
        if (_password.text.isNotEmpty) 'password': _password.text,
      });
    } else {
      ok = await widget.provider.create({
        'name': _name.text.trim(),
        'gmail': _email.text.trim(),
        'password': _password.text,
        'role': 'admin',
        'phone': phone.isEmpty ? null : phone,
        'country': country.isEmpty ? null : country,
      });
    }
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(editing ? 'admin_edit_admin'.tr : 'admin_add_admin'.tr),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Form(
              key: _form,
              child: Column(
                children: [
                  Field(
                    controller: _name,
                    label: 'name_label'.tr,
                    validator: (v) => (v == null || v.trim().length < 2)
                        ? 'admin_name_is_required'.tr
                        : null,
                  ),
                  Field(
                    controller: _email,
                    label: 'admin_email'.tr,
                    keyboard: TextInputType.emailAddress,
                    ltr: true,
                    validator: (v) =>
                    (v == null || !v.contains('@') || !v.contains('.'))
                        ? 'admin_invalid_email'.tr
                        : null,
                  ),
                  Field(
                    controller: _phone,
                    label: 'admin_phone'.tr,
                    keyboard: TextInputType.phone,
                    ltr: true,
                  ),
                  Field(
                    controller: _country,
                    label: 'admin_country_code'.tr,
                    ltr: true,
                  ),
                  Field(
                    controller: _password,
                    label: editing
                        ? 'admin_new_password_optional'.tr
                        : 'password'.tr,
                    obscure: true,
                    validator: (v) {
                      if (editing && (v == null || v.isEmpty)) return null;
                      return (v == null || v.length < 6)
                          ? 'admin_at_least_6_characters'.tr
                          : null;
                    },
                  ),
                  if (editing)
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: c.primary,
                      title: Text(
                        'exam_status_active'.tr,
                        style: TextStyle(fontFamily: 'tajawal', color: c.textDark),
                      ),
                      value: _active,
                      onChanged: (v) => setState(() => _active = v),
                    ),
                  const SizedBox(height: 8),
                  PrimaryButton(
                    label: 'save'.tr,
                    isLoading: busy,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}