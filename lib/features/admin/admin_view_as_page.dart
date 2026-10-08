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
import '../../utils/widget/view_as_state.dart';
import 'admin_common.dart';

/// Starts view-as for [id] and lands on that user's own home. ONE place for every entry point
/// (this page, the student/teacher lists, the user detail sheet).
void startViewAs(NavigatorState nav, {required int id, required String name, required String role}) {
  ViewAsState.instance.start(id: id, name: name, role: role);
  // Same landing routes the real users get (AuthProvider.homeRoute).
  nav.pushNamedAndRemoveUntil(role == 'teacher' ? '/teacher_dashboard' : '/dashboard', (r) => false);
}

class AdminViewAsPage extends StatefulWidget {
  const AdminViewAsPage({super.key});

  @override
  State<AdminViewAsPage> createState() => _AdminViewAsPageState();
}

class _AdminViewAsPageState extends State<AdminViewAsPage> {
  final _api = ApiClient();
  final _q = TextEditingController();
  String _role = 'student';
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;
  Timer? _debounce;
  int _req = 0; // ignores out-of-order responses (type fast → older reply must not overwrite the newer one)

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  /// Search as you type (350 ms after the last key) — no need to press enter.
  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final req = ++_req;
    setState(() {
      _loading = true;
      _error = null;
    });
    List<Map<String, dynamic>> items = [];
    String? error;
    try {
      final r = await _api.get('/api/v1/admin/users', queryParams: {
        'role': _role,
        if (_q.text.trim().isNotEmpty) 'search': _q.text.trim(),
        'size': 30,
      });
      items = ((r is Map ? r['items'] : null) as List? ?? []).cast<Map<String, dynamic>>();
    } catch (e) {
      error = e is ApiException ? e.message : '$e';
    }
    if (!mounted || req != _req) return;
    setState(() {
      _items = items;
      _error = error;
      _loading = false;
    });
  }

  /// First letter of the name — an empty name used to crash on `.characters.first`.
  String _initial(Object? name) {
    final n = '${name ?? ''}'.trim();
    return n.isEmpty ? '?' : n.characters.first.toUpperCase();
  }

  void _open(Map<String, dynamic> u) => startViewAs(
    Navigator.of(context, rootNavigator: true),
    id: (u['id'] as num).toInt(),
    name: '${u['name']}',
    role: _role,
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!context.read<AuthProvider>().isSuper) {
      return BasePage(
        useWebCard: true,
        appBar: ScreenAppBar(title: 'view_as_user'.tr),
        child: EmptyState('admin_super_admin_only'.tr, icon: Icons.lock_rounded),
      );
    }
    return BasePage(
      useWebCard: true,
      maxWith: 1100,
      appBar:ScreenAppBar(title: 'view_as_user'.tr),
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'student', label: Text('student'.tr), icon: const Icon(Icons.school_rounded)),
                ButtonSegment(value: 'teacher', label: Text('teacher'.tr), icon: const Icon(Icons.person_pin_rounded)),
              ],
              selected: {_role},
              onSelectionChanged: (s) {
                _role = s.first;
                _load();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _q,
              onChanged: _onSearchChanged,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'admin_search_by_name_or_e_mail'.tr,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _load),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? ErrorRetry(message: _error!, onRetry: _load)
                : _items.isEmpty
                ? EmptyState('admin_nothing_here_yet'.tr)
                : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final u = _items[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: (u['image_url'] != null && '${u['image_url']}'.isNotEmpty) ? NetworkImage('${u['image_url']}') : null,
                    child: Text(_initial(u['name'])),
                  ),
                  title: Text('${u['name']}'),
                  subtitle: Text('${u['gmail']}', textDirection: TextDirection.ltr),
                  trailing: const Icon(Icons.login_rounded),
                  onTap: () => _open(u),
                );
              },
            ),
          ),
        ]),
      )),
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
    final signedIn = context.select<AuthProvider, bool>((a) => a.isAuthenticated);
    if (!signedIn && ViewAsState.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ViewAsState.instance.stop());
    }
    return _banner(context);
  }

  Widget _banner(BuildContext context) => ListenableBuilder(
    listenable: ViewAsState.instance,
    builder: (_, _) {
      final active = ViewAsState.active;
      final s = ViewAsState.instance;
      return Column(children: [
        if (active)
          Directionality(
            textDirection: pageDirection,
            child: Material(
              color: const Color(0xFFB45309),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(children: [
                    const Icon(Icons.visibility_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${'admin_view_only'.tr}: ${s.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFamily: 'tajawal', decoration: TextDecoration.none, fontSize: 13)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFFB45309),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      icon: const Icon(Icons.admin_panel_settings_rounded, size: 18),
                      label: Text('admin_back_to_admin'.tr,
                          style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 12.5)),
                      onPressed: exit,
                    ),
                  ]),
                ),
              ),
            ),
          ),
        // Keyed: the app (Navigator) keeps its state when the banner is added / removed.
        // The banner already covers the status bar — the page below must not add that padding again.
        Expanded(
          key: const ValueKey('app_content'),
          child: MediaQuery.removePadding(context: context, removeTop: active, child: child),
        ),
      ]);
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