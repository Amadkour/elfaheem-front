// The signed-in admin's effective permissions (docs/redesign/api/governance.md §3.4), read ONCE when the admin home
// opens (GET /api/v1/admin/roles/me). Only a CUSTOM role narrows anything: a super admin, a plain admin (built-in
// role) and "not loaded yet" all mean "no limit", so a plain admin never sees an item flicker. The server enforces
// the same map on every admin route (403 permission_denied); this only hides what would answer 403.
import 'package:flutter/foundation.dart';

import 'package:flutter_education_app/core/api_client.dart';

class AdminPerms extends ChangeNotifier {
  AdminPerms._();

  static final AdminPerms instance = AdminPerms._();

  /// null = no limit (super admin, built-in admin, or not loaded).
  Set<String>? _perms;

  /// Bumped when the visible set changes (the dashboard rebuilds its shell on it).
  int revision = 0;

  bool get limited => _perms != null;

  /// [perm] null = any admin.
  bool allows(String? perm) => perm == null || _perms == null || _perms!.contains(perm);

  /// Empty = any admin; otherwise one of [perms] is enough.
  bool allowsAny(List<String> perms) => perms.isEmpty || perms.any(allows);

  /// A failed read keeps the current state (the server still refuses what the role lacks).
  Future<void> load([ApiClient? api]) async {
    try {
      final j = await (api ?? ApiClient.instance).get('/api/v1/admin/roles/me');
      if (j is! Map) return;
      final role = j['role'];
      final builtin = role is! Map || role['builtin'] != false;
      set(builtin ? null : {for (final p in (j['permissions'] as List? ?? const [])) '$p'});
    } catch (_) {}
  }

  @visibleForTesting
  void set(Set<String>? perms) {
    final same = perms == null ? _perms == null : (_perms != null && setEquals(perms, _perms));
    if (same) return;
    _perms = perms;
    revision++;
    notifyListeners();
  }

  /// Sign-out / another account: forget without a rebuild.
  void reset() => _perms = null;
}
