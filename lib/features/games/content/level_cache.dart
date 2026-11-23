// lib/features/games/content/level_cache.dart — the offline pool of a level (Games v4 T36, CONTRACT §4 `pool`, §9).
//
// Phones and desktop only (`kDownloadsAvailable`): the web has no device database and never calls GET /pool, so
// every method here answers "nothing" there. What is kept:
//   * the pool (up to 3 × count items in snapshot form) of each level the learner took offline, in a local table,
//     valid until the pool's `expires_at` (30 days);
//   * the audio files of those items for the learner's chosen reciter only (RecitationCache, one folder per reciter);
//   * which items were already seen on this device, so an offline round takes unseen items first, then a shuffle.
// An offline round is `pickRound`: it renumbers the picked items 0..k-1 (the trace's `i` is the position inside
// `picked`) and answers the draw map `GameSession.fromDraw` reads, plus `picked` (the pool `n` of each, in round
// order) for the play. A play on a pool is never ranked (the server saves it `no_round`).
//
// A reciter change: `refreshForReciter` re-resolves the cached pools' audio through GET /games/quran/audio, rewrites
// the entries, downloads the new files and deletes the old reciter's folder when no pool needs it any more. It runs
// on Wi-Fi only unless [force] (the audio of a level is a few MB).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/offline/downloads_availability.dart';
import 'package:flutter_education_app/features/games/content/games_v4_api.dart';
import 'package:flutter_education_app/features/games/content/level_store_web.dart' if (dart.library.io) 'level_store_io.dart' as device;
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/recitation_cache.dart';

/// One stored pool.
class PoolRow {
  const PoolRow({
    required this.userId,
    required this.gameId,
    required this.body,
    required this.expiresAt,
    required this.savedAt,
    this.reciter,
  });
  final int userId, gameId;

  /// The reciter key the pool's audio was resolved for.
  final String? reciter;

  /// The pool answer as JSON.
  final String body;
  final String expiresAt, savedAt;

  PoolRow withBody(String body, String? reciter) =>
      PoolRow(userId: userId, gameId: gameId, body: body, expiresAt: expiresAt, savedAt: savedAt, reciter: reciter);
}

/// The device's pool storage (sqflite in level_store_io.dart; [MemoryLevelStore] on the web and in tests).
abstract class LevelStore {
  Future<void> putPool(PoolRow row);
  Future<PoolRow?> getPool(int userId, int gameId);
  Future<List<PoolRow>> pools(int userId);
  Future<void> deletePool(int userId, int gameId);
  Future<void> markSeen(int userId, int gameId, Iterable<int> itemIds);
  Future<Set<int>> seen(int userId, int gameId);
  Future<void> wipe();
}

class MemoryLevelStore implements LevelStore {
  final _pools = <(int, int), PoolRow>{};
  final _seen = <(int, int), Set<int>>{};

  @override
  Future<void> putPool(PoolRow row) async => _pools[(row.userId, row.gameId)] = row;
  @override
  Future<PoolRow?> getPool(int userId, int gameId) async => _pools[(userId, gameId)];
  @override
  Future<List<PoolRow>> pools(int userId) async => [for (final e in _pools.entries) if (e.key.$1 == userId) e.value];
  @override
  Future<void> deletePool(int userId, int gameId) async => _pools.remove((userId, gameId));
  @override
  Future<void> markSeen(int userId, int gameId, Iterable<int> itemIds) async =>
      (_seen[(userId, gameId)] ??= <int>{}).addAll(itemIds);
  @override
  Future<Set<int>> seen(int userId, int gameId) async => {...?_seen[(userId, gameId)]};
  @override
  Future<void> wipe() async {
    _pools.clear();
    _seen.clear();
  }
}

/// An offline round picked from a pool.
class OfflineRound {
  const OfflineRound({required this.draw, required this.picked, required this.itemIds});

  /// The map `GameSession.fromDraw` reads (kind `pool`, items renumbered, no `round_id`).
  final Map<String, dynamic> draw;

  /// The pool `n` of each item, in round order: the play's `picked`.
  final List<int> picked;

  /// The item ids of the round (for [LevelCache.markPlayed]).
  final List<int> itemIds;
}

/// Every audio entry of a pool answer (the maps are the live ones: callers may rewrite them).
Iterable<Map> poolAudioEntries(Map<String, dynamic> pool) sync* {
  for (final it in (pool['items'] as List? ?? const [])) {
    if (it is! Map) continue;
    final media = it['media'];
    final audio = media is Map ? media['audio'] : null;
    if (audio is List) {
      for (final e in audio) {
        if (e is Map) yield e;
      }
    }
  }
}

class LevelCache {
  LevelCache({
    LevelStore? store,
    GamesV4Api? api,
    RecitationCache? audio,
    bool? enabled,
    DateTime Function()? now,
    Future<bool> Function()? onWifi,
    Random? random,
  })  : _store = store,
        _apiOverride = api,
        _audio = audio ?? RecitationCache.instance,
        enabled = enabled ?? kDownloadsAvailable,
        _now = now ?? DateTime.now,
        _onWifi = onWifi ?? _defaultOnWifi,
        _rng = random ?? Random();

  static final LevelCache instance = LevelCache();

  /// False on the web: everything answers "nothing".
  final bool enabled;
  LevelStore? _store;
  final GamesV4Api? _apiOverride;
  GamesV4Api? _apiLazy;
  GamesV4Api get _api => _apiOverride ?? (_apiLazy ??= GamesV4Api());
  final RecitationCache _audio;
  final DateTime Function() _now;
  final Future<bool> Function() _onWifi;
  final Random _rng;

  static Future<bool> _defaultOnWifi() async {
    try {
      final r = await Connectivity().checkConnectivity();
      return r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return false;
    }
  }

  Future<LevelStore> _s() async => _store ??= await device.openLevelStore();

  /// Pool times are the server's naive UTC.
  DateTime? _parse(String s) {
    final d = DateTime.tryParse(s);
    if (d == null) return null;
    return d.isUtc ? d : DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second);
  }

  bool _expired(String expiresAt) {
    final d = _parse(expiresAt);
    return d == null || !d.isAfter(_now().toUtc());
  }

  // ---- storing a pool ----

  /// Keeps [pool] (a `GET /games/{id}/pool` answer) for [userId] and downloads its audio. [onProgress] hears
  /// (done, total) files. Returns the number of audio files cached (0 when disabled or nothing has audio).
  Future<int> storePool(int userId, int gameId, V4Draw pool, {void Function(int done, int total)? onProgress}) async {
    if (!enabled || !pool.isPool) return 0;
    final store = await _s();
    final saved = _now().toUtc().toIso8601String();
    await store.putPool(PoolRow(
      userId: userId,
      gameId: gameId,
      reciter: pool.reciter?.key,
      body: jsonEncode(pool.raw),
      expiresAt: pool.raw['expires_at'] is String ? pool.raw['expires_at'] as String : saved,
      savedAt: saved,
    ));
    return _downloadAudio(pool.raw, pool.reciter?.key, onProgress);
  }

  Future<int> _downloadAudio(Map<String, dynamic> pool, String? chosen, void Function(int, int)? onProgress) async {
    final todo = <(String, String)>{};
    for (final e in poolAudioEntries(pool)) {
      final url = e['url'];
      if (url is String && url.isNotEmpty) todo.add(((e['reciter'] as String?) ?? chosen ?? 'default', url));
    }
    var done = 0, ok = 0;
    for (final (reciter, url) in todo) {
      if (await _audio.ensure(reciter, url) != null) ok++;
      onProgress?.call(++done, todo.length);
    }
    return ok;
  }

  // ---- reading ----

  /// The stored pool of the level, or null (missing, expired — an expired one is dropped — or disabled).
  Future<V4Draw?> pool(int userId, int gameId) async {
    final row = await _row(userId, gameId);
    if (row == null) return null;
    try {
      return V4Draw(Map<String, dynamic>.from(jsonDecode(row.body) as Map));
    } catch (_) {
      return null;
    }
  }

  Future<PoolRow?> _row(int userId, int gameId) async {
    if (!enabled) return null;
    final store = await _s();
    final row = await store.getPool(userId, gameId);
    if (row == null) return null;
    if (_expired(row.expiresAt)) {
      await store.deletePool(userId, gameId);
      return null;
    }
    return row;
  }

  Future<bool> hasPool(int userId, int gameId) async => await _row(userId, gameId) != null;

  /// The game ids this user has a live pool for.
  Future<List<int>> cachedGames(int userId) async {
    if (!enabled) return const [];
    final out = <int>[];
    for (final r in await (await _s()).pools(userId)) {
      if (!_expired(r.expiresAt)) out.add(r.gameId);
    }
    return out;
  }

  /// The cached audio file of an entry (null on the web or when it is not downloaded yet).
  Future<File?> audioFile(String reciter, String url) => _audio.cached(reciter, url);

  // ---- an offline round ----

  /// Picks [count] items (default: the pool's own `settings.count`) unseen-on-this-device first, then a shuffle.
  Future<OfflineRound?> pickRound(int userId, int gameId, {int? count}) async {
    final pool = await this.pool(userId, gameId);
    if (pool == null) return null;
    final items = pool.items;
    if (items.isEmpty) return null;
    final want = (count ?? ((pool.raw['settings'] is Map ? (pool.raw['settings'] as Map)['count'] : null) as num?)?.toInt() ?? items.length)
        .clamp(1, items.length);
    final seen = await (await _s()).seen(userId, gameId);
    final fresh = [for (final it in items) if (!seen.contains(it['id'])) it]..shuffle(_rng);
    final old = [for (final it in items) if (seen.contains(it['id'])) it]..shuffle(_rng);
    final chosen = [...fresh, ...old].take(want).toList();

    final out = <Map<String, dynamic>>[];
    final picked = <int>[], ids = <int>[];
    var max = 0;
    for (var i = 0; i < chosen.length; i++) {
      final it = Map<String, dynamic>.from(chosen[i]);
      picked.add((it['n'] as num?)?.toInt() ?? items.indexOf(chosen[i]));
      ids.add((it['id'] as num?)?.toInt() ?? 0);
      it['n'] = i;
      max += (it['max'] as num?)?.toInt() ?? GameItem.fromJson(it)?.max ?? 0;
      out.add(it);
    }
    final draw = Map<String, dynamic>.from(pool.raw)
      ..['items'] = out
      ..['kind'] = 'pool'
      ..['round_id'] = null
      ..['max_score'] = max
      ..['count'] = out.length;
    return OfflineRound(draw: draw, picked: picked, itemIds: ids);
  }

  /// Marks a finished offline round's items as seen on this device.
  Future<void> markPlayed(int userId, int gameId, Iterable<int> itemIds) async {
    if (!enabled) return;
    await (await _s()).markSeen(userId, gameId, itemIds.where((e) => e != 0));
  }

  // ---- a reciter change ----

  /// Cached levels whose audio is not [reciterKey]'s yet.
  Future<List<int>> staleFor(int userId, String reciterKey) async {
    if (!enabled) return const [];
    return [
      for (final r in await (await _s()).pools(userId))
        if (!_expired(r.expiresAt) && r.reciter != null && r.reciter != reciterKey) r.gameId,
    ];
  }

  /// Re-resolves and downloads the audio of every stale cached level for [reciterKey] (a change of reciter), then
  /// removes the files of the old reciters nobody needs. Wi-Fi only unless [force]. Returns the levels refreshed.
  Future<int> refreshForReciter(int userId, String reciterKey, {bool force = false}) async {
    if (!enabled) return 0;
    final stale = await staleFor(userId, reciterKey);
    if (stale.isEmpty) return 0;
    if (!force && !await _onWifi()) return 0;
    DrawReciter? who;
    try {
      final list = await _api.reciters();
      for (final r in list.items) {
        if (r.key == reciterKey) who = DrawReciter(key: r.key, nameAr: r.nameAr, nameEn: r.nameEn);
      }
    } catch (_) {}
    final store = await _s();
    final oldKeys = <String>{};
    var refreshed = 0;
    for (final gameId in stale) {
      final row = await store.getPool(userId, gameId);
      if (row == null) continue;
      try {
        final pool = Map<String, dynamic>.from(jsonDecode(row.body) as Map);
        final entries = poolAudioEntries(pool).toList();
        final refs = {for (final e in entries) if (e['ref'] is String) e['ref'] as String}.toList();
        if (refs.isNotEmpty) {
          final fresh = await _api.quranAudio(refs, reciterKey);
          for (final e in entries) {
            final s = fresh[e['ref']];
            if (s == null) continue;
            e['url'] = s.url;
            e['start_ms'] = s.startMs;
            e['end_ms'] = s.endMs;
            e['reciter'] = s.reciter ?? reciterKey;
          }
        }
        pool['reciter'] = who == null
            ? {'key': reciterKey, 'name_ar': '', 'name_en': ''}
            : {'key': who.key, 'name_ar': who.nameAr, 'name_en': who.nameEn};
        await _downloadAudio(pool, reciterKey, null);
        await store.putPool(row.withBody(jsonEncode(pool), reciterKey));
        if (row.reciter != null) oldKeys.add(row.reciter!);
        refreshed++;
      } catch (e) {
        debugPrint('LevelCache.refreshForReciter $gameId: $e');
      }
    }
    // an old reciter's folder goes when no stored pool still plays it
    final left = <String>{};
    for (final r in await store.pools(userId)) {
      if (r.reciter != null) left.add(r.reciter!);
    }
    for (final k in oldKeys) {
      if (!left.contains(k)) await _audio.clear(k);
    }
    return refreshed;
  }

  /// Drops every pool (sign-out). Audio files stay in the temp folder the OS may clear.
  Future<void> wipe() async {
    if (!enabled) return;
    await (await _s()).wipe();
  }
}
