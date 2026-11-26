// lib/features/admin/admin_admins_page.dart
//
// Super-admin only: list / search / add / edit / delete admins.
// Same look & feel as admin_users_page.dart.
//
// Uses the EXISTING admin_panel.py endpoints (super-admin rules are enforced there):
//   GET    /api/v1/admin/users?role=admin&search=&page=1&size=20  -> {items, total, page, size, pages}
//   POST   /api/v1/admin/users        {role:"admin", name, gmail, password, phone?, country?}
//   PUT    /api/v1/admin/users/{id}   {name, gmail, phone, country, is_active, password?, username? (null = remove)}
//   DELETE /api/v1/admin/users/{id}
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:provider/provider.dart';

import '../../utils/widget/phone_field.dart';
import '../../utils/widget/primary_button.dart';
import 'admin_common.dart';
import 'admin_filter_models.dart';
import 'admin_filters.dart';
import 'admin_list.dart' show AdminAvatar;
import 'admin_models.dart' show AdminUser;
import 'admin_page.dart';
import 'admin_view_as_page.dart' show startViewAs;
import 'admin_mfa_page.dart' show confirmResetUserMfa, mfaResetLabel;
import '../auth/auth_provider.dart' show MyAuthProvider;
import 'package:flutter_education_app/design/app_inputs.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_badges.dart';
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_education_app/design/app_data_table.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppBanner, AppEmpty;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/app_username.dart';
import '../auth/username.dart' show UsernameError;
import '../auth/username_field.dart' show UsernameStatus;
import 'admin_username_field.dart';
import 'package:flutter_education_app/design/app_side_sheet.dart' show AppSheetMode;
import 'sup/sup_kit.dart';

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

  /// The server's message of the last failed load (null while the list is good).
  String? errorMessage;

  /// Reloads page 1. A FAILED reload keeps the rows already on screen (the page shows [errorMessage] with Retry);
  /// only a successful one replaces them.
  Future<void> refresh() async {
    _debounce?.cancel();
    final gen = ++_gen;
    loading = true;
    failed = false;
    errorMessage = null;
    loadingMore = false; // a load-more of the previous query is dropped below: it must not leave this flag set
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
      errorMessage = ApiException.from(e).message;
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
      if (gen != _gen) return; // a search / filter replaced the list meanwhile (refresh() reset loadingMore)
      final next = _rows(data);
      final known = items.map((e) => asInt(e['id'])).toSet();
      items = [...items, ...next.where((e) => !known.contains(asInt(e['id'])))];
      _total = asInt(asMap(data)['total'], items.length);
      hasMore = next.isNotEmpty && items.length < _total;
    } catch (e) {
      if (gen == _gen) toast(ApiException.from(e).message, error: true);
    }
    if (gen != _gen) return;
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

  /// [onError] also gets the server's error (a USERNAME_* code lands on the form's username field).
  Future<bool> update(int id, Map<String, dynamic> body, {ValueChanged<ApiException>? onError}) async {
    try {
      await _api.put(_AdminsApi.one(id), body: body);
      toast('admin_admin_saved'.tr);
      await refresh();
      return true;
    } catch (e) {
      final err = ApiException.from(e);
      onError?.call(err);
      toast(err.message, error: true);
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

  /// true when shown as a tab inside the dashboard shell (no Back).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    // Defence in depth: the server enforces super-admin on every call anyway.
    if (!isSuperNow(context)) {
      return SupPage(
        kicker: 'a2_people_kicker'.tr, headline: 'a2_admins_head'.tr,
        title: 'admin_admins'.tr,
        showBack: !embedded,
        body: Center(child: EmptyState('admin_super_admin_only'.tr, icon: Icons.lock_rounded)),
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
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // the shell's Refresh reloads in place: filters, search text and scroll stay
    AdminRefreshScope.register(context, context.read<AdminAdminsProvider>().refresh);
  }

  String? _sortKey(String? s) {
    if (s == null) return null;
    if (s.startsWith('name')) return 'name';
    if (s == 'newest' || s == 'oldest') return 'joined';
    if (s == 'last_login') return 'last_login';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminAdminsProvider>();
    final me = context.read<MyAuthProvider>().currentUser?.id;
    final rows = [for (final r in p.items) AdminUser(r)];

    // a failed reload keeps the rows (a banner with Retry sits above them); only a first load can fail empty
    final state = p.failed && p.items.isEmpty
        ? AppTableState.error
        : (p.loading && p.items.isEmpty ? AppTableState.loading : AppTableState.ready);

    final table = AppDataTable<AdminUser>(
      state: state,
      errorText: p.errorMessage,
      onRetry: p.refresh,
      rows: rows,
      rowId: (u) => u.id,
      searchHint: 'admin_search_name_email_or_phone'.tr,
      onSearch: p.setSearch,
      toolbarTrailing: Row(mainAxisSize: MainAxisSize.min, children: [
        AdminFilterButton(host: p, specs: _adminSpecs, sort: _adminSort),
      ]),
      columns: [
        AppTableColumn<AdminUser>(
          key: 'name',
          label: 'name_label'.tr,
          primary: true,
          sortable: true,
          flex: 3,
          cell: (ctx, u) => Row(children: [
            AdminAvatar(name: u.name, url: u.imageUrl, size: 36),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(ctx))),
          ]),
        ),
        AppTableColumn<AdminUser>(
          key: 'contact',
          label: 'admin_email'.tr,
          flex: 3,
          cell: (ctx, u) {
            final uname = usernameFrom(u.j);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(u.gmail.isEmpty ? '—' : u.gmail,
                  maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.row(ctx)),
              if (uname != null)
                Text('@$uname',
                    maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.meta(ctx)),
            ]);
          },
        ),
        AppTableColumn<AdminUser>(
          key: 'status',
          label: 'status'.tr,
          flex: 2,
          cell: (ctx, u) {
            final isSuperRow = u.role == 'super-admin';
            final active = asBool(u.j['is_active'], true);
            return Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
              AppStatusBadge(
                label: isSuperRow ? 'admin_role_super_admin'.tr : 'admin_role_admin'.tr,
                tone: isSuperRow ? AppTone.brand : AppTone.info,
                dense: true,
              ),
              AppStatusBadge(
                label: active ? 'exam_status_active'.tr : 'admin_inactive'.tr,
                tone: active ? AppTone.success : AppTone.warning,
                dense: true,
              ),
            ]);
          },
        ),
        AppTableColumn<AdminUser>.text(
          key: 'joined',
          label: 'admin_joined'.tr,
          sortable: true,
          flex: 2,
          showOnPhone: false,
          text: (u) => shortDate(u.createdAt),
        ),
        AppTableColumn<AdminUser>.text(
          key: 'last_login',
          label: 'admin_last_login'.tr,
          sortable: true,
          flex: 2,
          showOnPhone: false,
          text: (u) => shortDateTime(u.lastLogin),
        ),
      ],
      sortKey: _sortKey(p.sort),
      sortAscending: p.sort == 'name_asc' || p.sort == 'oldest',
      onSort: (k, asc) => p.setSort(switch (k) {
        'name' => asc ? 'name_asc' : 'name_desc',
        'joined' => asc ? 'oldest' : 'newest',
        _ => 'last_login',
      }),
      onRowTap: (u) => _openAdminForm(context, p, existing: u.j),
      rowActions: (u) {
        final isSuperRow = u.role == 'super-admin';
        return [
          // Super-admin: open this admin's dashboard (read-only). Never another super-admin.
          if (!isSuperRow)
            AppRowAction<AdminUser>(
              icon: Icons.visibility_rounded,
              label: 'view_as_user'.tr,
              onTap: () => startViewAs(Navigator.of(context, rootNavigator: true), id: u.id, name: u.name, role: 'admin'),
            ),
          AppRowAction<AdminUser>(
            icon: Icons.edit_rounded,
            label: 'btn_edit'.tr,
            onTap: () => _openAdminForm(context, p, existing: u.j),
          ),
          // Lost phone AND recovery codes: remove their two-step verification (not your own: turn it off instead)
          if (me != u.id)
            AppRowAction<AdminUser>(
              icon: Icons.phonelink_erase_rounded,
              label: mfaResetLabel(),
              onTap: () => confirmResetUserMfa(context, userId: u.id, name: u.name),
            ),
          // A super-admin row can't be deleted from here (server also refuses).
          if (!isSuperRow)
            AppRowAction<AdminUser>(
              icon: Icons.delete_outline_rounded,
              label: 'delete'.tr,
              danger: true,
              onTap: () async {
                final ok = await confirm(
                  context,
                  message: trp('admin_delete_admin_confirm', {'name': u.name}),
                  danger: true,
                );
                if (ok) await p.remove(u.id);
              },
            ),
        ];
      },
      empty: p.hasActiveQuery
          ? AppEmpty(
              icon: Icons.search_off_rounded,
              title: 'admin_filter_no_results'.tr,
              actionLabel: 'ds_clear_filters'.tr,
              onAction: p.clearAll,
            )
          : AppEmpty(icon: Icons.shield_outlined, title: 'admin_no_admins_found'.tr),
      onClearFilters: p.clearAll,
      onLoadMore: p.loadMore,
      hasMore: p.hasMore,
      loadingMore: p.loadingMore,
    );

    return SupPage(
        kicker: 'a2_people_kicker'.tr, headline: p.failed || p.loading ? 'a2_admins_head'.tr : countText(p.total, ar1: 'شخص واحد يقدر يدخل لوحة التحكم', ar2: 'شخصان يقدرون يدخلون لوحة التحكم', arFew: '{n} أشخاص يقدرون يدخلون لوحة التحكم', arMany: '{n} شخصًا يقدرون يدخلون لوحة التحكم', en1: 'One person can open the dashboard', en: '{n} people can open the dashboard'), line: 'a2_admins_line'.tr,
        title: 'admin_admins'.tr,
        showBack: !widget.embedded,
        onRefresh: p.refresh,
        body: Padding(
        padding: AdminPage.bodyPadding(context),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (p.failed && p.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: AppBanner(
                icon: Icons.error_outline_rounded,
                text: p.errorMessage ?? 'admin_could_not_load_data'.tr,
                color: context.colors.danger,
                action: AppButton.ghost(label: 'retry'.tr, size: AppButtonSize.sm, onPressed: p.refresh),
              ),
            ),
          AdminActiveFilterChips(host: p, specs: _adminSpecs, sort: _adminSort),
          Expanded(child: table),
        ]),
      ),
        actions: [AppButton.primary(
        key: const ValueKey('admins_add'),
        label: 'admin_add_admin'.tr,
        icon: Icons.admin_panel_settings_rounded,
        onPressed: () => _openAdminForm(context, p),
      )],
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
    context, mode: AppSheetMode.side,
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
  // the row's @username: a super-admin may set, change or remove it (D-071, admin edit)
  late final String? _currentUsername = usernameFrom(widget.existing);
  late final _username = TextEditingController(text: _currentUsername ?? '');
  UsernameError? _usernameError;
  UsernameStatus _usernameStatus = UsernameStatus.current;
  bool busy = false;

  bool get editing => widget.existing != null;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password, _username]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final uname = editing
        ? adminUsernameBody(current: _currentUsername, text: _username.text, enabled: adminUsernameOn)
        : const <String, Object?>{};
    final hold = adminUsernameHold(uname, _usernameStatus);
    if (hold != null) {
      toast(hold, error: _usernameStatus != UsernameStatus.checking);
      return;
    }
    setState(() => busy = true);
    final phone = _phone.text.trim();
    final bool ok;
    if (editing) {
      ok = await widget.provider.update(asInt(widget.existing!['id']), {
        'name': _name.text.trim(),
        'gmail': _email.text.trim(),
        'phone': phone.isEmpty ? null : phone,
        // no known dial code (or no phone): leave the stored country alone instead of throwing
        if (kPhoneCountries.where((e) => _phone.text.contains(e.dial)).firstOrNull case final pc?) 'country': pc.flag,
        'is_active': _active,
        if (_password.text.isNotEmpty) 'password': _password.text,
        ...uname,
      }, onError: (e) {
        final err = UsernameError.from(e, submitted: _username.text);
        if (err != null && mounted) setState(() => _usernameError = err);
      });
    } else {
      ok = await widget.provider.create({
        'name': _name.text.trim(),
        'gmail': _email.text.trim(),
        'password': _password.text,
        'role': 'admin',
        'phone': phone.isEmpty ? null : phone,
        // no known dial code (or no phone): leave the stored country alone instead of throwing
        if (kPhoneCountries.where((e) => _phone.text.contains(e.dial)).firstOrNull case final pc?) 'country': pc.flag,
      });
    }
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(editing ? 'admin_edit_admin'.tr : 'admin_add_admin'.tr),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
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
                  AppEmailField(controller: _email, label: 'admin_email'.tr),
                  PhoneInputField(
                    controller: _phone,
                    label: 'admin_phone'.tr,
                  ),
                  if (editing)
                    AdminUsernameField(
                      controller: _username,
                      currentUsername: _currentUsername,
                      error: _usernameError,
                      onStatusChanged: (s) => setState(() => _usernameStatus = s),
                    ),
                  AppPasswordField(controller: _password, label: editing
                        ? 'admin_new_password_optional'.tr
                        : 'password'.tr, required: !editing),
                  if (editing)
                    AppSwitchTile(
                      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                      title: 'exam_status_active'.tr,
                      value: _active,
                      onChanged: (v) => setState(() => _active = v),
                    ),
                  const SizedBox(height: AppSpace.xs),
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
