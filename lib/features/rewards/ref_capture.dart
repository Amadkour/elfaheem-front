// lib/features/rewards/ref_capture.dart — who invited this device (Games v3 §3.2, CONTRACT §8; kill switch
// `rewards.referral`).
//
// A `ref` (the inviter's user id) comes from a start URL: a course share link `/c/<id>?ref=<uid>` or the invite link
// `/app/?ref=<uid>`. It is kept on the device for 30 days and the FIRST one wins: a later link while one is kept
// changes nothing (D-1773). POST /auth/register sends it as `ref`; the server ignores an unknown, invalid or self
// value, so a stale one can never fail a sign-up.
library;

import 'package:shared_preferences/shared_preferences.dart';

class RefCapture {
  RefCapture._();

  static const String prefKey = 'rewards.ref.v1';

  /// How long a captured ref is kept.
  static const Duration keep = Duration(days: 30);

  /// The kept value, written as `<uid>|<captured at, ms since epoch UTC>`.
  static String encode(int ref, DateTime atUtc) => '$ref|${atUtc.toUtc().millisecondsSinceEpoch}';

  static (int, DateTime)? decode(String? raw) {
    if (raw == null) return null;
    final parts = raw.split('|');
    if (parts.length != 2) return null;
    final ref = int.tryParse(parts[0]);
    final ms = int.tryParse(parts[1]);
    if (ref == null || ref <= 0 || ms == null) return null;
    return (ref, DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true));
  }

  /// A `ref` query value as a user id (null = none or not a positive number).
  static int? parse(Object? v) {
    final n = int.tryParse('${v ?? ''}'.trim());
    return n == null || n <= 0 ? null : n;
  }

  /// The ref still valid at [nowUtc] from a kept [raw] value (null = none or older than [keep]).
  static int? validAt(String? raw, DateTime nowUtc) {
    final d = decode(raw);
    if (d == null) return null;
    final age = nowUtc.difference(d.$2);
    return age.isNegative || age > keep ? null : d.$1;
  }

  /// What to keep after a link with [incoming] arrives: the kept value while it is still valid (first touch wins),
  /// else the new one. Null = keep nothing new (no incoming ref and nothing valid).
  static String? next(String? raw, int? incoming, DateTime nowUtc) {
    if (validAt(raw, nowUtc) != null) return raw;
    if (incoming == null) return null;
    return encode(incoming, nowUtc);
  }

  /// Keeps [ref] from a start URL. Never throws.
  static Future<void> capture(int? ref, {DateTime? now}) async {
    if (ref == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(prefKey);
      final n = next(raw, ref, (now ?? DateTime.now()).toUtc());
      if (n != null && n != raw) await p.setString(prefKey, n);
    } catch (_) {}
  }

  /// The `ref` from a start URI's query (`?ref=123`), kept.
  static Future<void> captureFromUri(Uri uri) => capture(parse(uri.queryParameters['ref']));

  /// The kept ref for a sign-up (null = none, or older than 30 days: then it is dropped).
  static Future<int?> current({DateTime? now}) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(prefKey);
      final v = validAt(raw, (now ?? DateTime.now()).toUtc());
      if (v == null && raw != null) await p.remove(prefKey);
      return v;
    } catch (_) {
      return null;
    }
  }

  /// After the account exists: the ref did its job.
  static Future<void> clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(prefKey);
    } catch (_) {}
  }
}
