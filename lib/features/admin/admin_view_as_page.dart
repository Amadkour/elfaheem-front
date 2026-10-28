// features/admin/admin_view_as_page.dart  (SUPER-ADMIN only)
//
// Pick a student / teacher → the app switches to that user's own dashboard, read-only.
// The server enforces everything (see services/view_as.py); this page only starts the mode.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../utils/widget/app_bar.dart';
import '../../utils/widget/paged_progress.dart';
import '../../utils/widget/view_as_state.dart';
import 'admin_common.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppRefresh;

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

  final _api = ApiClient();
  final _q = TextEditingController();
  final _scroll = ScrollController();

  String _role = 'student';
  List<Map<String, dynamic>> _items = [];
  int _page = 0; // last page received
  int _received =
      0; // rows received from the server (incl. rows hidden client-side)
  int _hidden = 0; // super-admin rows dropped from the admin tab
  int _total = 0; // server total for the current filter
  bool _loading = false; // first page
  bool _loadingMore = false; // next pages
  String? _error;
  Timer? _debounce;
  int _req =
      0; // ignores out-of-order responses (older reply must not overwrite a newer one)

  bool get _hasMore => _received < _total;

  /// What we show as "total": the server total minus the super-admins we already know are hidden.
  int get _shownTotal => _hasMore
      ? (_total - _hidden).clamp(_items.length, _total)
      : _items.length;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _q.dispose();
    super.dispose();
  }

  /// Search as you type (1 s after the last key) — Enter searches at once.
  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(kSearchDelay, _load);
  }

  /// Near the bottom → fetch the next page automatically.
  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 320) _loadMore();
  }

  /// If the first pages don't even fill the screen there is nothing to scroll, so keep loading.
  void _fillViewport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_scroll.position.maxScrollExtent <= 0 && _hasMore) _loadMore();
    });
  }

  Future<({List<Map<String, dynamic>> rows, int received, int total})> _fetch(
    int page,
  ) async {
    final r = await _api.get(
      '/api/v1/admin/users',
      queryParams: {
        'role': _role,
        'page': page,
        'size': _pageSize,
        if (_q.text.trim().isNotEmpty) 'search': _q.text.trim(),
      },
    );
    final map = r is Map ? r : const {};
    final all = ((map['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    // role=admin also returns super-admins, and the server refuses to view those.
    final rows = _role == 'admin'
        ? all.where((u) => '${u['role']}' != 'super-admin').toList()
        : all;
    final total = (map['total'] as num?)?.toInt() ?? all.length;
    return (rows: rows, received: all.length, total: total);
  }

  Future<void> _load() async {
    final req = ++_req;
    setState(() {
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
        _hidden = r.received - r.rows.length;
        _total = r.total;
        _loading = false;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _fillViewport();
    } catch (e) {
      if (!mounted || req != _req) return;
      setState(() {
        _items = [];
        _page = 0;
        _received = 0;
        _hidden = 0;
        _total = 0;
        _error = e is ApiException ? e.message : '$e';
        _loading = false;
      });
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
        _hidden += r.received - r.rows.length;
        _total = r.total;
        _loadingMore = false;
      });
      _fillViewport();
    } catch (e) {
      if (!mounted || req != _req) return;
      setState(() => _loadingMore = false);
      toast(e is ApiException ? e.message : '$e', error: true);
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
      return BasePage(
        useWebCard: true,
        appBar: ScreenAppBar(title: 'view_as_user'.tr),
        child: EmptyState(
          'admin_super_admin_only'.tr,
          icon: Icons.lock_rounded,
        ),
      );
    }

    Widget list;
    if (_loading) {
      list = const AppListSkeleton();
    } else if (_error != null) {
      list = ErrorRetry(message: _error!, onRetry: _load);
    } else if (_items.isEmpty) {
      list = EmptyState('admin_nothing_here_yet'.tr);
    } else {
      list = AppRefresh(
        onRefresh: _load,
        child: ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          itemCount: _items.length + 1,
          itemBuilder: (_, i) {
            if (i == _items.length) {
              return PagedListFooter(
                loadingMore: _loadingMore,
                hasMore: _hasMore,
              );
            }
            return _ViewAsTile(user: _items[i], onTap: () => _open(_items[i]));
          },
        ),
      );
    }

    return BasePage(
      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(title: 'view_as_user'.tr),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'student',
                      label: Text('student'.tr),
                      icon: const Icon(Icons.school_rounded),
                    ),
                    ButtonSegment(
                      value: 'teacher',
                      label: Text('teacher'.tr),
                      icon: const Icon(Icons.person_pin_rounded),
                    ),
                    ButtonSegment(
                      value: 'admin',
                      label: Text('admin_role_admin'.tr),
                      icon: const Icon(Icons.admin_panel_settings_rounded),
                    ),
                  ],
                  selected: {_role},
                  onSelectionChanged: (s) {
                    _role = s.first;
                    _load();
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: TextField(
                  controller: _q,
                  onChanged: _onSearchChanged,
                  onSubmitted: (_) {
                    _debounce?.cancel();
                    _load();
                  },
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'admin_search_by_name_or_e_mail'.tr,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(tooltip: t('بحث', 'Search'), 
                      icon: const Icon(Icons.arrow_forward_rounded),
                      onPressed: _load,
                    ),
                  ),
                ),
              ),
              if (!_loading && _error == null && _items.isNotEmpty && _shownTotal>20)
                PagedCountCard(
                  loaded: _items.length,
                  total: _shownTotal,
                  loadingMore: _loadingMore,
                  done: !_hasMore,
                ),
              Expanded(child: list),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewAsTile extends StatelessWidget {
  const _ViewAsTile({required this.user, required this.onTap});

  final Map<String, dynamic> user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = '${user['name'] ?? ''}'.trim();
    final image = '${user['image_url'] ?? ''}';
    final active = user['is_active'] != false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.divider),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [c.primary, c.primaryDark],
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 23,
                    backgroundColor: c.cardBg,
                    backgroundImage: image.isNotEmpty
                        ? NetworkImage(image)
                        : null,
                    child: image.isEmpty
                        ? Text(
                            name.isEmpty
                                ? '?'
                                : name.characters.first.toUpperCase(),
                            style: TextStyle(
                              color: c.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? '—' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'tajawal',
                          fontWeight: FontWeight.w800,
                          color: c.textDark,
                        ),
                      ),
                      Text(
                        '${user['gmail'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontFamily: 'tajawal',
                          fontSize: 12,
                          color: c.textLight,
                        ),
                      ),
                      if (!active)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: StatusChip('admin_inactive'.tr, c.warning),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(CupertinoIcons.eye, size: 20, color: c.primary),
                ),
              ],
            ),
          ),
        ),
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
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.visibility_rounded,
                          color: context.colors.onHero,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${'admin_view_only'.tr}: ${s.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.colors.onHero,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'tajawal',
                              decoration: TextDecoration.none,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: context.colors.onHero,
                            foregroundColor: context.colors.warning,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          icon: const Icon(
                            Icons.admin_panel_settings_rounded,
                            size: 18,
                          ),
                          label: Text(
                            'admin_back_to_admin'.tr,
                            style: const TextStyle(
                              fontFamily: 'tajawal',
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
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
