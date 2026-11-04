// lib/features/admin/admin_recents.dart
//
// "Recently opened": the admin pages (AdminService.labelKey) this person opened last on THIS device, newest first.
// Local only (SharedPreferences, one key per user), so it costs no request. The Overview draws it, the global search
// palette lists it on an empty query; tiles feed it with `AdminRecents.instance.record(s.labelKey)`.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminRecents extends ChangeNotifier {
  AdminRecents._();
  static final AdminRecents instance = AdminRecents._();

  /// Most keys kept.
  static const cap = 12;

  /// Most tiles the Overview draws.
  static const shown = 6;

  static const _prefix = 'admin_recents_';

  String _user = '';
  final List<String> _keys = [];
  int _gen = 0;

  /// Newest first, no duplicates, at most [cap].
  List<String> get keys => List.unmodifiable(_keys);

  String get _prefsKey => '$_prefix$_user';

  /// Switches to [userId]'s history (loaded from the device). Safe to call often; a failing read leaves it empty.
  Future<void> use(String? userId) async {
    final u = userId ?? '';
    if (u == _user && _loaded) return;
    _user = u;
    _loaded = true;
    final gen = ++_gen;
    List<String> stored = const [];
    try {
      final p = await SharedPreferences.getInstance();
      stored = p.getStringList(_prefsKey) ?? const [];
    } catch (_) {}
    if (gen != _gen) return;
    // keys recorded while the read was in flight stay on top
    final merged = <String>[..._keys, for (final k in stored) if (!_keys.contains(k)) k];
    _keys
      ..clear()
      ..addAll(merged.take(cap));
    notifyListeners();
  }

  bool _loaded = false;

  /// [serviceKey] becomes the newest entry.
  void record(String serviceKey) {
    if (serviceKey.isEmpty) return;
    if (_keys.isNotEmpty && _keys.first == serviceKey) return;
    _keys
      ..remove(serviceKey)
      ..insert(0, serviceKey);
    if (_keys.length > cap) _keys.removeRange(cap, _keys.length);
    notifyListeners();
    _save();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_prefsKey, List.of(_keys));
    } catch (_) {}
  }

  /// Forgets everything in memory (sign-out, tests). The stored list stays.
  @visibleForTesting
  void resetForTest() {
    _keys.clear();
    _user = '';
    _loaded = false;
    _gen++;
  }
}
