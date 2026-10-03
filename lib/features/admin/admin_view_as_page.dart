// features/admin/admin_view_as_page.dart  (SUPER-ADMIN only)
//
// Pick a student / teacher → the app switches to that user's own dashboard, read-only.
// The server enforces everything (see services/view_as.py); this page only starts the mode.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:provider/provider.dart';

import '../../utils/widget/view_as_state.dart';
import 'admin_common.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _api.get('/api/v1/admin/users', queryParams: {
        'role': _role,
        if (_q.text.trim().isNotEmpty) 'search': _q.text.trim(),
        'size': 30,
      });
      _items = ((r is Map ? r['items'] : null) as List? ?? []).cast<Map<String, dynamic>>();
    } catch (_) {
      _items = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  void _open(Map<String, dynamic> u) {
    ViewAsState.instance.start(id: u['id'] as int, name: '${u['name']}', role: _role);
    // Same landing routes the real users get (AuthProvider.homeRoute).
    Navigator.of(context).pushNamedAndRemoveUntil(_role == 'teacher' ? '/teacher_dashboard' : '/dashboard', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!context.read<AuthProvider>().isSuper) {
      return Scaffold(body: EmptyState(t('للمدير العام فقط', 'Super-admin only'), icon: Icons.lock_rounded));
    }
    return Directionality(
      textDirection: dir,
      child: Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(title: Text(t('عرض كمستخدم', 'View as user'), style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800))),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'student', label: Text(t('طالب', 'Student')), icon: const Icon(Icons.school_rounded)),
                    ButtonSegment(value: 'teacher', label: Text(t('معلم', 'Teacher')), icon: const Icon(Icons.person_pin_rounded)),
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
                  onSubmitted: (_) => _load(),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: t('ابحث بالاسم أو البريد', 'Search by name or e-mail'),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _load),
                  ),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final u = _items[i];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage: (u['image_url'] != null && '${u['image_url']}'.isNotEmpty) ? NetworkImage('${u['image_url']}') : null,
                              child: Text('${u['name'] ?? '?'}'.characters.first),
                            ),
                            title: Text('${u['name']}'),
                            subtitle: Text('${u['gmail']}'),
                            trailing: const Icon(Icons.visibility_rounded),
                            onTap: () => _open(u),
                          );
                        },
                      ),
              ),
            ]),
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
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: ViewAsState.instance,
        builder: (_, _) {
          if (!ViewAsState.active) return child;
          final s = ViewAsState.instance;
          return Column(children: [
            Material(
              color: const Color(0xFFB45309),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(children: [
                    const Icon(Icons.visibility_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${t('عرض فقط', 'View only')}: ${s.name}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFamily: 'tajawal', decoration: TextDecoration.none, fontSize: 13)),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                      onPressed: () {
                        ViewAsState.instance.stop();
                        // navigatorKey lives in main.dart; the banner sits above the Navigator, so go through it.
                        ViewAsBanner.onExit?.call();
                      },
                      child: Text(t('خروج', 'Exit')),
                    ),
                  ]),
                ),
              ),
            ),
            Expanded(child: child),
          ]);
        },
      );

  /// Set in main.dart: `ViewAsBanner.onExit = () => navigatorKey.currentState?.pushNamedAndRemoveUntil('/admin_dashboard', (r) => false);`
  static VoidCallback? onExit;
}
