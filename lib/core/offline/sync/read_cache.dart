// lib/core/offline/sync/read_cache.dart — the last answer of a few GETs, per user, shown while offline (D-1351).
//
//   await ReadCache.instance.put('games.list', body);              // after a good online answer
//   final c = await ReadCache.instance.get('games.list');          // offline: c?.body, c?.savedAt
//
// Same database as the outbox (local_db.dart), keyed by the signed-in user, so the next account on a shared phone
// never reads the last one's. Identity numbers are stripped before anything is kept (D-1353), and sign-out wipes
// it all. On the web it is memory only. Which readers use it is F13's list (PROGRESS.md, Phase 7).
library;

import 'dart:convert';

import 'package:clock/clock.dart';

import 'local_db.dart';
import 'outbox.dart' show Outbox;

/// A cached answer.
class CachedRead {
  const CachedRead(this.body, this.savedAt, {this.etag});

  final Object? body;
  final DateTime savedAt;
  final String? etag;
}

/// Field names never kept on the device, at any depth of a cached answer.
const identityFieldNames = {
  'national_id',
  'national_id_number',
  'id_number',
  'identity_number',
  'passport_number',
  'civil_id',
  'iqama_number',
};

/// [body] without the [identityFieldNames] keys (maps and lists are copied, other values kept).
Object? stripIdentity(Object? body) {
  if (body is Map) {
    return {
      for (final e in body.entries)
        if (!identityFieldNames.contains('${e.key}'.toLowerCase())) '${e.key}': stripIdentity(e.value),
    };
  }
  if (body is List) return [for (final v in body) stripIdentity(v)];
  return body;
}

class ReadCache {
  ReadCache({Outbox? outbox}) : _outbox = outbox;

  static ReadCache instance = ReadCache();

  final Outbox? _outbox;
  Outbox get _box => _outbox ?? Outbox.instance;

  /// Keeps [body] (a decoded JSON answer) under [key] for the signed-in user. Never throws.
  Future<void> put(String key, Object? body, {String? etag}) async {
    try {
      final uid = await _box.currentUserId();
      final d = await _box.db;
      if (uid == null || d == null) return;
      await d.cachePut(CacheRow(
        userId: uid,
        key: key,
        body: jsonEncode(stripIdentity(body)),
        savedAt: clock.now().toUtc().toIso8601String(),
        etag: etag,
      ));
    } catch (_) {}
  }

  /// The signed-in user's answer under [key], or null.
  Future<CachedRead?> get(String key) async {
    try {
      final uid = await _box.currentUserId();
      final d = await _box.db;
      if (uid == null || d == null) return null;
      final r = await d.cacheGet(uid, key);
      if (r == null) return null;
      return CachedRead(jsonDecode(r.body), DateTime.parse(r.savedAt), etag: r.etag);
    } catch (_) {
      return null;
    }
  }
}
