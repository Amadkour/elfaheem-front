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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:provider/provider.dart';

import '../../utils/widget/app_bar.dart';
import '../../utils/widget/app_loading_indicator.dart';
import '../../utils/widget/base_page.dart';
import '../../utils/widget/paged_progress.dart';
import '../../utils/widget/phone_field.dart';
import '../../utils/widget/primary_button.dart';
import 'admin_common.dart';
import 'admin_filter_models.dart';
import 'admin_filters.dart';
import 'admin_list.dart' show RowCard;
import 'admin_view_as_page.dart' show startViewAs;

class _AdminsApi {
  static const list = '/api/v1/admin/users';
  static String one(int id) => '/api/v1/admin/users/$id';
}

// ── premium filters ─────────────────────────────────────────────────────────

const _adminSort = SortSpec({
  'newest': 'admin_sort_newest',
  'oldest': 'admin_sort_oldest',
  'name_asc': 'admin_sort_name_asc',
  'name_desc': 'admin_sort_name_desc',
  'last_login': 'admin_sort_last_login',
  'most_logins': 'admin_sort_most_logins',
});

const _adminSpecs = <FilterSpec>[
  FilterSpec.choice('admin_role', 'admin_filter_admin_role', {
    'admin': 'admin_filter_role_admin',
    'super_admin': 'admin_filter_role_super',
  }),
  FilterSpec.choice('status', 'admin_filter_status', {
    'active': 'exam_status_active',
    'inactive': 'admin_inactive',
  }),
  FilterSpec.tri('verified', 'admin_filter_verified'),
  FilterSpec.tri('has_phone', 'admin_filter_has_phone'),
  FilterSpec.dateRange('created_from', 'created_to', 'admin_filter_created'),
  FilterSpec.choice('last_login', 'admin_filter_last_login', {
    'today': 'admin_filter_today',
    '7d': 'admin_filter_last_7_days',
    '30d': 'admin_filter_last_30_days',
    '90d': 'admin_filter_last_90_days',
    'inactive_30d': 'admin_filter_inactive_30d',
    'never': 'admin_filter_never_logged_in',
  }),
];

// ═════════════════════════════════════════════════════════════════════════════
//  Provider
// ═════════════════════════════════════════════════════════════════════════════

class AdminAdminsProvider extends ChangeNotifier implements AdminQueryHost {
  static const pageSize = 20;

  final _api = ApiClient();

  List<Map<String, dynamic>> items = [];
  bool loading = false;
  bool loadingMore = false;
  bool failed = false;
  bool hasMore = true;
  int _total = 0;
  int get total => _total;
  @override
  String search = '';
  @override
  final Map<String, Object?> adv = {};
  @override
  String? sort;
  Timer? _debounce;
  bool _disposed = false;
  int _gen = 0; // drops stale responses when the search changes mid-flight

  @override
  bool get hasActiveQuery => search.isNotEmpty || adv.isNotEmpty || sort != null;

  @override
  int? get resultCount => (loading && items.isEmpty) || failed ? null : total;

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }

  Map<String, dynamic> get _query => {
    'role': 'admin',
    ...encodeFilters(adv),
    if (search.isNotEmpty) 'search': search,
    if (sort != null) 'sort': sort,
  };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Debounced: typing fires one request, not one per letter.
  @override
  Future<void> setSearch(String v) async {
    final t = v.trim();
    if (t == search) return;
    search = t;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!_disposed) refresh();
    });
  }

  @override
  Future<void> applyAdv(Map<String, Object?> values, {String? sortKey}) {
    adv
      ..clear()
      ..addAll({
        for (final e in values.entries)
          if (e.value != null) e.key: e.value,
      });
    sort = sortKey;
    return refresh();
  }

  @override
  Future<void> removeAdv(Iterable<String> keys) {
    keys.forEach(adv.remove);
    return refresh();
  }

  @override
  Future<void> setSort(String? v) {
    sort = v;
    return refresh();
  }

  @override
  Future<void> clearAll() {
    _debounce?.cancel();
    search = '';
    adv.clear();
    sort = null;
    return refresh();
  }

  List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is List) return asMapList(data);
    if (data is Map) {
      if (data['items'] is List) return asMapList(data['items']);
    }
    return [];
  }

  Future<void> refresh() async {
    _debounce?.cancel();
    final gen = ++_gen;
    loading = true;
    failed = false;
    hasMore = true;
    _notify();
    try {
      final data = await _api.get(_AdminsApi.list, queryParams: {
        ..._query,
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
        ..._query,
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
  int _fillRows = -1;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 320) {
      context.read<AdminAdminsProvider>().loadMore();
    }
  }

  /// Too few rows to scroll → keep loading until the screen is full (once per row-count).
  void _fillViewport(AdminAdminsProvider p) {
    if (!p.hasMore || p.loadingMore || p.loading || p.failed) return;
    if (p.items.length == _fillRows) return;
    _fillRows = p.items.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_scroll.position.maxScrollExtent <= 0) p.loadMore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminAdminsProvider>();
    final c = context.colors;

    final search = AdminFilterBar(
      host: p,
      hintKey: 'admin_search_name_email_or_phone',
      specs: _adminSpecs,
      sort: _adminSort,
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
      body = EmptyState(
        (p.hasActiveQuery ? 'admin_filter_no_results' : 'admin_no_admins_found').tr,
        icon: Icons.shield_outlined,
      );
    } else {
      _fillViewport(p);
      body = RefreshIndicator(
        onRefresh: p.refresh,
        child: ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 90),
          itemCount: p.items.length + 1,
          itemBuilder: (ctx, i) {
            if (i == p.items.length) {
              return PagedListFooter(
                loadingMore: p.loadingMore,
                hasMore: p.hasMore,
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
          if (p.items.isNotEmpty && p.total > 20)
            PagedCountCard(
              loaded: p.items.length,
              total: p.total,
              loadingMore: p.loadingMore,
              done: !p.hasMore,
              icon: Icons.admin_panel_settings_rounded,
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            ),
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
  final _password = TextEditingController();
  late bool _active = asBool(widget.existing?['is_active'], true);
  bool busy = false;

  bool get editing => widget.existing != null;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    final phone = _phone.text.trim();
    final bool ok;
    if (editing) {
      ok = await widget.provider.update(asInt(widget.existing!['id']), {
        'name': _name.text.trim(),
        'gmail': _email.text.trim(),
        'phone': phone.isEmpty ? null : phone,
        'country':  kPhoneCountries
          .firstWhere((e) => _phone.text.contains(e.dial))
          .flag,
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
        'country': kPhoneCountries
          .firstWhere((e) => _phone.text.contains(e.dial))
          .flag,
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
                  PhoneInputField(
                    controller: _phone,
                    label: 'admin_phone'.tr,
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