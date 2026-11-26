// features/admin/admin_view_as_page.dart  (SUPER-ADMIN only)
//
// Pick a student / teacher → the app switches to that user's own dashboard, read-only.
// The server enforces everything (see services/view_as.py); this page only starts the mode.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../utils/widget/view_as_state.dart';
import 'admin_common.dart';
import 'admin_list.dart' show AdminAvatar;
import 'admin_page.dart';
import 'package:flutter_education_app/design/app_badges.dart';
import 'package:flutter_education_app/design/app_data_table.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppEmpty;
import 'package:flutter_education_app/design/app_states.dart' show appErrorMessage;
import 'package:flutter_education_app/design/app_tabs.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/app_username.dart';
import 'sup/sup_kit.dart';

/// Starts view-as for [id] and lands on that user's own home. ONE place for every entry point
/// (this page, the student/teacher lists, the user detail sheet).
void startViewAs(
  NavigatorState nav, {
  required int id,
  required String name,
  required String role,
}) {
  ViewAsState.instance.start(id: id, name: name, role: role);
  // Same landing routes the real users get (AuthProvider.homeRoute).
  nav.pushNamedAndRemoveUntil(switch (role) {
    'teacher' => '/teacher_dashboard',
    'admin' => '/admin_dashboard',
    _ => '/dashboard',
  }, (r) => false);
}

class AdminViewAsPage extends StatefulWidget {
  const AdminViewAsPage({super.key});

  @override
  State<AdminViewAsPage> createState() => _AdminViewAsPageState();
}

class _AdminViewAsPageState extends State<AdminViewAsPage> {
  static const _pageSize = 20;
  static const _roles = ['student', 'teacher', 'admin'];

  final _api = ApiClient();

  String _role = 'student';
  String _search = '';
  List<Map<String, dynamic>> _items = [];
  int _page = 0; // last page received
  int _received = 0; // rows received from the server (incl. rows hidden client-side)
  int _total = 0; // server total for the current filter
  bool _loading = false; // first page
  bool _loadingMore = false; // next pages
  String? _error;
  int _req = 0; // ignores out-of-order responses (older reply must not overwrite a newer one)

  bool get _hasMore => _received < _total;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AdminRefreshScope.register(context, _load);
  }

  Future<({List<Map<String, dynamic>> rows, int received, int total})> _fetch(int page) async {
    final r = await _api.get(
      '/api/v1/admin/users',
      queryParams: {
        'role': _role,
        'page': page,
        'size': _pageSize,
        if (_search.isNotEmpty) 'search': _search,
      },
    );
    final map = r is Map ? r : const {};
    final all = ((map['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    // role=admin also returns super-admins, and the server refuses to view those.
    final rows = _role == 'admin' ? all.where((u) => '${u['role']}' != 'super-admin').toList() : all;
    final total = (map['total'] as num?)?.toInt() ?? all.length;
    return (rows: rows, received: all.length, total: total);
  }

  Future<void> _load({bool reset = false}) async {
    final req = ++_req;
    setState(() {
      if (reset) _items = []; // another role / search: never show the previous one's rows while loading
      _loading = true;
      _loadingMore = false;
      _error = null;
    });
    try {
      final r = await _fetch(1);
      if (!mounted || req != _req) return;
      setState(() {
        _items = r.rows;
        _page = 1;
        _received = r.received;
        _total = r.total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || req != _req) return;
      setState(() {
        // a failed reload keeps the rows already shown; only a first load can end in the error state
        _error = appErrorMessage(e);
        _loading = false;
      });
      if (_items.isNotEmpty) toast(_error!, error: true);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _error != null) return;
    final req = _req;
    setState(() => _loadingMore = true);
    try {
      final r = await _fetch(_page + 1);
      if (!mounted || req != _req) return;
      final known = _items.map((e) => e['id']).toSet();
      setState(() {
        _items = [..._items, ...r.rows.where((u) => !known.contains(u['id']))];
        _page += 1;
        _received += r.received;
        _total = r.total;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || req != _req) return;
      setState(() => _loadingMore = false);
      toast(appErrorMessage(e), error: true);
    }
  }

  void _open(Map<String, dynamic> u) => startViewAs(
        Navigator.of(context, rootNavigator: true),
        id: (u['id'] as num).toInt(),
        name: '${u['name']}',
        role: _role,
      );

  @override
  Widget build(BuildContext context) {
    if (!isSuperNow(context)) {
      return SupPage(
        kicker: 'a2_people_kicker'.tr, headline: 'a2_viewas_head'.tr,
        title: 'view_as_user'.tr,
        body: Center(child: EmptyState('admin_super_admin_only'.tr, icon: Icons.lock_rounded)),
      );
    }

    final state = _error != null && _items.isEmpty
        ? AppTableState.error
        : (_loading && _items.isEmpty ? AppTableState.loading : AppTableState.ready);

    final table = AppDataTable<Map<String, dynamic>>(
      state: state,
      errorText: _error,
      onRetry: _load,
      rows: _items,
      rowId: (u) => u['id'] as Object,
      searchHint: 'admin_search_by_name_or_e_mail'.tr,
      onSearch: (v) {
        final q = v.trim();
        if (q == _search) return;
        _search = q;
        _load(reset: true);
      },
      columns: [
        AppTableColumn<Map<String, dynamic>>(
          key: 'name',
          label: 'name_label'.tr,
          primary: true,
          flex: 3,
          cell: (ctx, u) {
            final name = '${u['name'] ?? ''}'.trim();
            return Row(children: [
              AdminAvatar(name: name, url: '${u['image_url'] ?? ''}', size: 36),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(name.isEmpty ? '—' : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(ctx)),
                  AppUsernameLine(usernameFrom(u)),
                ]),
              ),
            ]);
          },
        ),
        AppTableColumn<Map<String, dynamic>>.text(
          key: 'email',
          label: 'admin_email'.tr,
          flex: 3,
          text: (u) => '${u['gmail'] ?? ''}',
        ),
        AppTableColumn<Map<String, dynamic>>(
          key: 'status',
          label: 'status'.tr,
          flex: 1,
          showOnPhone: false,
          cell: (ctx, u) => u['is_active'] == false
              ? AppStatusBadge(label: 'admin_inactive'.tr, tone: AppTone.warning, dense: true)
              : AppStatusBadge(label: 'exam_status_active'.tr, tone: AppTone.success, dense: true),
        ),
      ],
      onRowTap: _open,
      rowActions: (u) => [
        AppRowAction<Map<String, dynamic>>(
          icon: Icons.visibility_rounded,
          label: 'view_as_user'.tr,
          onTap: () => _open(u),
        ),
      ],
      empty: _search.isNotEmpty
          ? AppEmpty(icon: Icons.search_off_rounded, title: 'ds_no_results'.tr)
          : AppEmpty(icon: Icons.inbox_outlined, title: 'admin_nothing_here_yet'.tr),
      onLoadMore: _loadMore,
      hasMore: _hasMore,
      loadingMore: _loadingMore,
    );

    return SupPage(
        kicker: 'a2_people_kicker'.tr, headline: 'a2_viewas_head'.tr, line: 'a2_viewas_line'.tr,
        title: 'view_as_user'.tr,
        onRefresh: _load,
        width: AppWidth.content,
        body: Padding(
        padding: AdminPage.bodyPadding(context),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppTabs(
            expand: true,
            items: [
              AppTabItem('student'.tr, icon: Icons.school_rounded),
              AppTabItem('teacher'.tr, icon: Icons.person_pin_rounded),
              AppTabItem('admin_role_admin'.tr, icon: Icons.admin_panel_settings_rounded),
            ],
            index: _roles.indexOf(_role),
            onChanged: (i) {
              if (_roles[i] == _role) return;
              _role = _roles[i];
              _load(reset: true);
            },
          ),
          const SizedBox(height: AppSpace.sm),
          Expanded(child: table),
        ]),
      ),
      );
  }
}

/// Banner shown over EVERY screen while view-as is on. Wrap the app in main.dart's `builder`.
class ViewAsBanner extends StatelessWidget {
  const ViewAsBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Logging out while in view-as left the mode ON (every later request kept sending X-View-As).
    final signedIn = context.select<MyAuthProvider, bool>(
      (a) => a.isAuthenticated,
    );
    if (!signedIn && ViewAsState.active) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ViewAsState.instance.stop(),
      );
    }
    return _banner(context);
  }

  Widget _banner(BuildContext context) => ListenableBuilder(
    listenable: ViewAsState.instance,
    builder: (_, _) {
      final active = ViewAsState.active;
      final s = ViewAsState.instance;
      return Column(
        children: [
          if (active)
            Directionality(
              textDirection: pageDirection,
              child: Material(
                color: context.colors.warning,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.sm,
                      vertical: AppSpace.xs,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.visibility_rounded,
                          color: context.colors.onHero,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpace.xs),
                        Expanded(
                          child: Text(
                            '${'admin_view_only'.tr}: ${s.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.label(context).copyWith(color: context.colors.onHero, fontWeight: FontWeight.w600, decoration: TextDecoration.none),
                          ),
                        ),
                        const SizedBox(width: AppSpace.xs),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: context.colors.onHero,
                            foregroundColor: context.colors.warning,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                          ),
                          icon: const Icon(
                            Icons.admin_panel_settings_rounded,
                            size: 18,
                          ),
                          label: Text(
                            'admin_back_to_admin'.tr,
                            style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600),
                          ),
                          onPressed: exit,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Keyed: the app (Navigator) keeps its state when the banner is added / removed.
          // The banner already covers the status bar — the page below must not add that padding again.
          Expanded(
            key: const ValueKey('app_content'),
            child: MediaQuery.removePadding(
              context: context,
              removeTop: active,
              child: child,
            ),
          ),
        ],
      );
    },
  );

  /// Optional override (main.dart can still set it). Without it, [exit] finds the app's root
  /// Navigator itself, so "Back to admin" works with no extra wiring.
  static VoidCallback? onExit;

  /// Leaves view-as mode and returns to the admin dashboard.
  static void exit() {
    ViewAsState.instance.stop();
    (onExit ?? _goToAdmin)();
  }

  static void _goToAdmin() {
    NavigatorState? nav;
    void visit(Element e) {
      if (nav != null) return;
      if (e is StatefulElement && e.state is NavigatorState) {
        nav = e.state as NavigatorState;
        return;
      }
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    nav?.pushNamedAndRemoveUntil('/admin_dashboard', (r) => false);
  }
}
