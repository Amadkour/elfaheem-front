// lib/core/offline/sync/sync_engine.dart — sends the outbox through `POST /api/v1/sync/push` (D-1351, D-1352).
//
// When it runs: on reconnect (TopRouteObserver's one connectivity listener calls [onReconnect]), on resume
// (main.dart calls [onResume]) and right after an enqueue. One run at a time; a trigger during a run books one
// more pass. An empty outbox makes no request, so a home's request budget never moves.
//
// One run: the signed-in user's rows, oldest first, in batches of ≤ 100.
//   applied / duplicate → the row goes and the kind's listeners get the server's `entity` (points, badges, …);
//   rejected            → the row goes, the person is told ONCE (showAppNotice with apiErrorText of the code), and
//                         the listeners get the result too (`sync_stale` → the profile screen refetches, D-1352);
//   a transport error, a 5xx or a 429 → every row stays and ONE retry is booked after a growing backoff
//                         (5 s, 10 s, … 5 min); a reconnect, a resume or a new enqueue runs it earlier.
// No polling: the backoff timer is the only timer, and it exists only while a retry is owed.
//
// `sync.offline` in the disable list (or the web): the engine does nothing and Outbox.enqueue answers
// "post directly". A 403 `feature_disabled` from the server keeps the rows and stops the run (the next trigger
// tries again).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../design/app_notice.dart';
import '../../api_client.dart';
import '../../api_error_text.dart';
import '../app_connectivity.dart';
import 'local_db.dart';
import 'outbox.dart';
import 'sync_status.dart';

/// One op's answer from the server.
@immutable
class SyncResult {
  const SyncResult({required this.id, required this.kind, required this.status, this.code, this.entity});

  final String id;
  final String kind;

  /// `applied` | `duplicate` | `rejected`.
  final String status;
  final String? code;
  final Map<String, dynamic>? entity;

  bool get accepted => status == 'applied' || status == 'duplicate';
  bool get rejected => status == 'rejected';
  bool get stale => rejected && code == 'sync_stale';
}

typedef SyncListener = void Function(SyncResult result);

/// The wait before the [n]-th retry in a row (n ≥ 1): 5 s doubling, at most 5 min.
Duration syncBackoff(int n) {
  final s = 5 * (1 << (n - 1).clamp(0, 6));
  return Duration(seconds: s > 300 ? 300 : s);
}

class SyncEngine {
  SyncEngine({
    ApiClient? api,
    Outbox? outbox,
    SyncStatus? status,
    ValueListenable<bool>? online,
    void Function(String message)? notify,
    Duration Function(int n)? backoff,
    Timer Function(Duration d, void Function() f)? timer,
  })  : _api = api,
        _outbox = outbox,
        _status = status,
        _online = online,
        _notify = notify ?? _appNotice,
        _backoff = backoff ?? syncBackoff,
        _timer = timer ?? Timer.new;

  static SyncEngine instance = SyncEngine();

  static const pushPath = '/api/v1/sync/push';
  static const batchMax = 100;

  final ApiClient? _api;
  final Outbox? _outbox;
  final SyncStatus? _status;
  final ValueListenable<bool>? _online;
  final void Function(String) _notify;
  final Duration Function(int) _backoff;
  final Timer Function(Duration, void Function()) _timer;

  ApiClient get api => _api ?? ApiClient.instance;
  Outbox get outbox => _outbox ?? Outbox.instance;
  SyncStatus get status => _status ?? SyncStatus.instance;
  ValueListenable<bool> get online => _online ?? AppConnectivity.instance.online;

  static void _appNotice(String m) => showAppNotice(m, error: true);

  final _listeners = <String, Set<SyncListener>>{};
  Future<void>? _running;
  bool _again = false;
  bool _bound = false;
  int _failures = 0;
  Timer? _retry;

  /// Consecutive failed pushes (0 after a good answer).
  int get failures => _failures;

  /// A retry is booked.
  bool get retryBooked => _retry != null;

  /// Once at start-up (TopRouteObserver.bindConnectivity): the status follows the connection, a new outbox row
  /// runs the engine, and whatever a previous run left is counted and sent.
  void bind() {
    if (_bound) return;
    _bound = true;
    status.bindOnline(online);
    outbox.onEnqueued = kick;
    if (!outbox.available) return;
    unawaited(outbox.refreshCount().then((n) {
      if (n > 0) kick();
    }));
  }

  /// [kind]'s results (applied, duplicate and rejected) go to [l].
  void listen(String kind, SyncListener l) => (_listeners[kind] ??= <SyncListener>{}).add(l);

  void unlisten(String kind, SyncListener l) => _listeners[kind]?.remove(l);

  void onReconnect() => kick();

  void onResume() => kick();

  /// Runs the engine now (or once more after the current run); fire and forget.
  void kick() => unawaited(run());

  /// One run; resolves when it (and any pass a trigger booked meanwhile) is over.
  Future<void> run() {
    final r = _running;
    if (r != null) {
      _again = true;
      return r;
    }
    final f = _loop();
    _running = f;
    return f;
  }

  Future<void> _loop() async {
    try {
      do {
        _again = false;
        await _drain();
      } while (_again);
    } finally {
      _running = null;
      status.setSyncing(false);
    }
  }

  Future<void> _drain() async {
    if (!outbox.available || !online.value) return;
    final uid = await outbox.currentUserId();
    if (uid == null) return;
    var rows = await outbox.rowsFor(uid);
    if (rows.isEmpty) return;                      // nothing waits: no request
    _retry?.cancel();
    _retry = null;
    status.setSyncing(true);
    try {
      while (rows.isNotEmpty) {
        final batch = rows.length > batchMax ? rows.sublist(0, batchMax) : rows;
        final settled = await _push(batch);
        if (settled == null) return;               // kept for a retry
        if (settled == 0) {                        // the server answered none of them: do not spin
          _bookRetry();
          return;
        }
        if (!online.value || (await outbox.currentUserId()) != uid) return;
        rows = await outbox.rowsFor(uid);
      }
    } finally {
      await outbox.refreshCount();
    }
  }

  /// Sends [batch]; returns how many ops the answer settled, or null when the batch was kept.
  Future<int?> _push(List<OutboxRow> batch) async {
    for (final r in batch) {
      await outbox.mark(r.id, state: OutboxRow.sending);
    }
    final Object? res;
    try {
      res = await api.post(pushPath, body: {'ops': [for (final r in batch) _op(r)]});
    } catch (e) {
      final ex = ApiException.from(e);
      for (final r in batch) {
        await outbox.mark(r.id, tries: r.tries + 1, state: OutboxRow.pending);
      }
      if (ex.code == 'feature_disabled' && ex.statusCode == 403) {
        debugPrint('sync: switched off on the server; ${batch.length} op(s) kept');
        return null;
      }
      if (ex.isUnauthorized) return null;          // signed out under us: the rows wait for their user
      _bookRetry();
      return null;
    }
    _failures = 0;
    final byId = {for (final r in batch) r.id: r};
    final done = <String>[];
    final results = <SyncResult>[];
    final list = res is Map ? res['results'] : null;
    for (final x in list is List ? list : const []) {
      if (x is! Map) continue;
      final id = '${x['id'] ?? ''}';
      final row = byId[id];
      if (row == null) continue;
      final status = '${x['status'] ?? ''}';
      if (status != 'applied' && status != 'duplicate' && status != 'rejected') continue;
      final ent = x['entity'];
      results.add(SyncResult(
        id: id,
        kind: row.kind,
        status: status,
        code: x['code']?.toString(),
        entity: ent is Map ? ent.map((k, v) => MapEntry('$k', v)) : null,
      ));
      done.add(id);
    }
    await outbox.remove(done);
    // the rows the answer left out go back to waiting
    for (final r in batch) {
      if (!done.contains(r.id)) await outbox.mark(r.id, state: OutboxRow.pending);
    }
    // each refused op is told once; the same sentence twice in one answer is one notice
    for (final t in {for (final r in results) if (r.rejected) syncRejectedText(r.code)}) {
      _notify(t);
    }
    for (final r in results) {
      for (final l in List.of(_listeners[r.kind] ?? const <SyncListener>{})) {
        try {
          l(r);
        } catch (e) {
          debugPrint('sync: a ${r.kind} listener failed: $e');
        }
      }
    }
    return done.length;
  }

  Map<String, dynamic> _op(OutboxRow r) {
    Object? payload;
    try {
      payload = jsonDecode(r.payload);
    } catch (_) {
      payload = const <String, dynamic>{};
    }
    return {
      'id': r.id,
      'kind': r.kind,
      'payload': payload,
      'client_ts': r.clientTs,
      if (r.baseUpdatedAt != null) 'base_updated_at': r.baseUpdatedAt,
    };
  }

  void _bookRetry() {
    _failures++;
    _retry?.cancel();
    _retry = _timer(_backoff(_failures), () {
      _retry = null;
      kick();
    });
  }

  /// Sign-out: no retry outlives the session; the listeners stay (screens remove their own).
  void reset() {
    _retry?.cancel();
    _retry = null;
    _failures = 0;
  }
}

/// The one sentence shown when the server refused an op: the code's own text (apiErrorText) or a general one.
String syncRejectedText(String? code) {
  final text = apiErrorText(ApiException(
    statusCode: 400,
    message: '',
    code: code,
    body: {'detail': {'code': ?code}},
  ));
  return text.trim().isNotEmpty ? text : apiErrorText(const ApiException(statusCode: 400, message: '', code: 'sync_error'));
}
