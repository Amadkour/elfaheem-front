// lib/core/offline/sync/outbox.dart — the writes that wait on this device for `POST /api/v1/sync/push` (D-1351).
//
//   final r = await Outbox.instance.enqueue(id: clientId, kind: SyncKinds.gamePlay, payload: {...});
//   if (r == EnqueueResult.postDirectly) { …post to the route as before… }
//
// Four kinds only (SyncKinds); money is never an op. The op id IS the entity's `client_id`, so the same write
// pushed twice, or posted to the route and then pushed, is one row on the server. Rows survive a restart (the
// device database), carry the user who made them and are only ever sent under that user's token (SyncEngine reads
// the signed-in user's rows only). The web, a sign-out, the kill switch `sync.offline` and a database that cannot
// open all answer [EnqueueResult.postDirectly]: the caller then posts straight to the route, as Phase 6 does.
library;

import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_config.dart';
import 'local_db.dart';
import 'sync_status.dart';

/// The kill switch: off = no outbox, no sync requests (CONTRACT §7).
const syncOfflineFeatureKey = 'sync.offline';

/// The op kinds `POST /api/v1/sync/push` takes (CONTRACT §7).
abstract final class SyncKinds {
  static const gamePlay = 'game_play';
  static const nahwAttempt = 'nahw_attempt';
  static const quranProgress = 'quran_progress';
  static const studyProfile = 'study_profile';

  static const all = {gamePlay, nahwAttempt, quranProgress, studyProfile};
}

/// A valid op id / `client_id`: 8–36 of `A-Za-z0-9_.:-`.
final syncOpIdPattern = RegExp(r'^[A-Za-z0-9_.:\-]{8,36}$');

enum EnqueueResult {
  /// Kept on the device; the engine sends it.
  queued,

  /// The same op id is already waiting (a double tap): nothing new was kept.
  alreadyQueued,

  /// No outbox here (web, signed out, `sync.offline` off, no database): post to the route yourself.
  postDirectly,
}

/// The signed-in user's id from the saved user (null = signed out).
Future<int?> savedUserId() async {
  try {
    final raw = (await SharedPreferences.getInstance()).getString('current_user');
    if (raw == null) return null;
    final j = jsonDecode(raw);
    final id = j is Map ? j['id'] : null;
    return id is num ? id.toInt() : int.tryParse('${id ?? ''}');
  } catch (_) {
    return null;
  }
}

/// True when the device keeps an outbox now: not the web and `sync.offline` not in the disable list.
bool syncOfflineAvailable() => !kIsWeb && !AppConfig.disableList.contains(syncOfflineFeatureKey);

class Outbox {
  Outbox({Future<LocalDb> Function()? open, Future<int?> Function()? userId, bool Function()? available, SyncStatus? status})
      : _open = open ?? openDeviceDb,
        _userId = userId ?? savedUserId,
        _available = available ?? syncOfflineAvailable,
        _status = status ?? SyncStatus.instance;

  static Outbox instance = Outbox();

  final Future<LocalDb> Function() _open;
  final Future<int?> Function() _userId;
  final bool Function() _available;
  final SyncStatus _status;
  Future<LocalDb?>? _db;

  /// Called after every new row (SyncEngine runs then).
  VoidCallback? onEnqueued;

  /// The database, opened once; null when it cannot be opened (then nothing is queued).
  Future<LocalDb?> get db => _db ??= _open().then<LocalDb?>((d) => d, onError: (Object e) {
        debugPrint('outbox: no device database ($e)');
        return null;
      });

  bool get available => _available();

  Future<int?> currentUserId() => _userId();

  Future<EnqueueResult> enqueue({
    required String id,
    required String kind,
    required Map<String, dynamic> payload,
    DateTime? clientTs,
    String? baseUpdatedAt,
  }) async {
    assert(SyncKinds.all.contains(kind), 'unknown sync kind $kind');
    assert(syncOpIdPattern.hasMatch(id), 'bad op id $id');
    if (!_available()) return EnqueueResult.postDirectly;
    final uid = await _userId();
    final d = await db;
    if (uid == null || d == null) return EnqueueResult.postDirectly;
    final bool added;
    try {
      added = await d.outboxInsert(OutboxRow(
        id: id,
        kind: kind,
        payload: jsonEncode(payload),
        clientTs: (clientTs ?? clock.now()).toUtc().toIso8601String(),
        baseUpdatedAt: baseUpdatedAt,
        userId: uid,
      ));
    } catch (e) {
      debugPrint('outbox: could not keep $kind ($e)');
      return EnqueueResult.postDirectly;
    }
    await refreshCount();
    if (added) onEnqueued?.call();
    return added ? EnqueueResult.queued : EnqueueResult.alreadyQueued;
  }

  /// The rows of [userId] in the order they were made.
  Future<List<OutboxRow>> rowsFor(int userId) async {
    final d = await db;
    if (d == null) return const [];
    try {
      return await d.outboxRows(userId: userId);
    } catch (_) {
      return const [];
    }
  }

  Future<void> remove(Iterable<String> ids) async {
    final d = await db;
    if (d == null) return;
    try {
      await d.outboxDelete(ids);
    } catch (_) {}
  }

  Future<void> mark(String id, {int? tries, String? state}) async {
    final d = await db;
    if (d == null) return;
    try {
      await d.outboxUpdate(id, tries: tries, state: state);
    } catch (_) {}
  }

  /// Reports the signed-in user's waiting rows to [SyncStatus]; returns the count.
  Future<int> refreshCount() async {
    final uid = await _userId();
    final n = uid == null ? 0 : (await rowsFor(uid)).length;
    _status.report(SyncStatus.outbox, n);
    return n;
  }

  /// Sign-out: every row of every user, and the read caches with them (same database).
  Future<void> wipe() async {
    final d = await db;
    try {
      await d?.wipe();
    } catch (_) {}
    _status.report(SyncStatus.outbox, 0);
  }
}
