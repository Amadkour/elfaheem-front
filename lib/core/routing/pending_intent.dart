// lib/core/routing/pending_intent.dart — what a guest was about to do when the app asked them to sign in (Learning
// Hub F5, D-1324, CONTRACT §4): "book this course" / "buy this store item", kept across the login, the registration
// and a full page reload (Google sign-in on the web), then done once.
//
//   GuestGuard.ensure(…, intent:)        writes it before opening login / register
//   MyAuthProvider.resumePendingIntent   takes it on the first signed-in page (main.dart's route guard), opens the
//                                        course and its checkout, and it is gone
//   MyAuthProvider.logout                clears it
//
// Stored as JSON `{v: 1, kind, id, plan, filters, at}` under the SharedPreferences key `pending_intent`; older than
// [PendingIntent.ttl] (2 h: a Google round trip or a registration with verification fits, the next person on a
// shared device a day later does not) it is dropped unread. Starting guest mode again clears it (GuestState.start). Every storage failure is silent: the worst case is a guest who lands
// on their home instead of the course.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum PendingIntentKind {
  bookCourse('book_course'),
  buyStoreItem('buy_store_item');

  const PendingIntentKind(this.wire);
  final String wire;

  static PendingIntentKind? parse(Object? v) {
    for (final k in values) {
      if (k.wire == v) return k;
    }
    return null;
  }
}

class PendingIntent {
  PendingIntent({required this.kind, required this.id, this.plan, Map<String, dynamic>? filters, DateTime? at})
      : filters = filters ?? const {},
        at = (at ?? clock()).toUtc();

  static const prefsKey = 'pending_intent';
  static const version = 1;
  static const ttl = Duration(hours: 2);

  /// Test hooks.
  static DateTime Function() clock = DateTime.now;
  static Future<SharedPreferences> Function() prefs = SharedPreferences.getInstance;

  final PendingIntentKind kind;

  /// The course id / store item id.
  final String id;

  /// The chosen plan (a subscription plan key, a price option), when the guest picked one.
  final String? plan;

  /// The explorer filters the guest came from (stage_id, grade_id, delivery, area_id …), to restore the search.
  final Map<String, dynamic> filters;

  final DateTime at;

  bool isExpired([DateTime? now]) => (now ?? clock()).toUtc().difference(at) > ttl;

  Map<String, dynamic> toJson() =>
      {'v': version, 'kind': kind.wire, 'id': id, 'plan': plan, 'filters': filters, 'at': at.toIso8601String()};

  static PendingIntent? fromJson(Object? j) {
    if (j is! Map || j['v'] != version) return null;
    final kind = PendingIntentKind.parse(j['kind']);
    final id = '${j['id'] ?? ''}';
    final at = DateTime.tryParse('${j['at'] ?? ''}');
    if (kind == null || id.isEmpty || at == null) return null;
    final f = j['filters'];
    return PendingIntent(
      kind: kind,
      id: id,
      plan: j['plan'] is String && (j['plan'] as String).isNotEmpty ? j['plan'] as String : null,
      filters: f is Map ? Map<String, dynamic>.from(f) : null,
      at: at,
    );
  }

  // ── Store ────────────────────────────────────────────────────────────────────

  /// Replaces whatever was pending: the last thing the guest tried is the one to resume.
  static Future<void> save(PendingIntent intent) async {
    try {
      await (await prefs()).setString(prefsKey, jsonEncode(intent.toJson()));
    } catch (_) {}
  }

  /// The pending intent, without consuming it; an expired or unreadable one is removed and null is returned.
  static Future<PendingIntent?> peek() async {
    try {
      final p = await prefs();
      final raw = p.getString(prefsKey);
      if (raw == null) return null;
      PendingIntent? i;
      try {
        i = fromJson(jsonDecode(raw));
      } catch (_) {}
      if (i == null || i.isExpired()) {
        await p.remove(prefsKey);
        return null;
      }
      return i;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      await (await prefs()).remove(prefsKey);
    } catch (_) {}
  }

  static Future<PendingIntent?>? _taking;

  /// Reads and removes the intent in one step. Two callers at once (two guarded pages mounting together) get it
  /// once: the second one gets null.
  static Future<PendingIntent?> take() {
    if (_taking != null) return Future.value(null);
    final f = _take();
    _taking = f;
    return f.whenComplete(() => _taking = null);
  }

  static Future<PendingIntent?> _take() async {
    final i = await peek();
    if (i != null) await clear();
    return i;
  }

  /// Takes the intent and hands it to [open]; true when there was one. The intent is cleared BEFORE [open] runs, so
  /// a failure there never makes it fire again on the next page.
  static Future<bool> resume(Future<void> Function(PendingIntent intent) open) async {
    final i = await take();
    if (i == null) return false;
    try {
      await open(i);
    } catch (_) {}
    return true;
  }
}
