// lib/core/offline/sync/sync_engine.dart — sends the outbox through `POST /api/v1/sync/push` (D-1351, D-1352).
//
// When it runs: on reconnect (TopRouteObserver's one connectivity listener calls [onReconnect]), on resume
// (main.dart calls [onResume]) and right after an enqueue. One run at a time; a trigger during a run books one
// more pass. An empty outbox makes no request, so a home's request budget never moves.
//
// One run: the signed-in user's rows, oldest first, in batches of ≤ 100, each row at most once per run. The push
// names the user the rows belong to (`user_id`): under another user's token the server answers 409
// `sync_wrong_user` and applies nothing. Nothing runs while View-As is on.
//   applied / duplicate → the row goes and the kind's listeners get the server's `entity` (points, badges, …);
//   rejected            → the row goes, the person is told ONCE (showAppNotice with apiErrorText of the code), and
//                         the listeners get the result too (`sync_stale` → the profile screen refetches, D-1352);
//   rejected sync_error → a transient server error: the row stays (tries + 1), no notice, a retry is booked;
//   no answer for an op → the row stays (tries + 1), a retry is booked.
// The whole push failed (7.R):
//   no status (transport, timeout), 408, 429, 5xx → every row stays (tries + 1) and ONE retry is booked after a
//                         growing backoff (5 s, 10 s, … 5 min); a reconnect, a resume or a new enqueue runs it earlier;
//   401, any 403 (`feature_disabled`, a device or account block), 409 `sync_wrong_user` → the rows stay as they
//                         were, no retry, not a failure (the next trigger tries again);
//   any other 4xx        → a batch of several is sent again one op per request, once, in order; an op that alone
//                         gets such an answer can never be taken: it goes, reported once as `sync_bad_op`.
// A row whose tries reach [OutboxRow.parkAt] is parked: left out of automatic runs, tried once on app start
// ([bind]) and on a manual "Sync now" (`run(withParked: true)`, the chip); SyncStatus counts it apart.
// No polling: the backoff timer is the only timer, and it exists only while a retry is owed by an unparked row.
//
// `sync.offline` in the disable list (or the web): the engine does nothing and Outbox.enqueue answers
// "post directly".
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
  final _told = <String>{};
  Future<void>? _running;
  bool _again = false;
  bool _wantParked = false;
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
      if (n > 0) kick(withParked: true);           // app start: the parked rows get their one try too
    }));
  }

  /// [kind]'s results (applied, duplicate and rejected) go to [l].
  void listen(String kind, SyncListener l) => (_listeners[kind] ??= <SyncListener>{}).add(l);

  void unlisten(String kind, SyncListener l) => _listeners[kind]?.remove(l);

  void onReconnect() => kick();

  void onResume() => kick();

  /// Runs the engine now (or once more after the current run); fire and forget. [withParked]: the parked rows
  /// are tried too (app start, a manual "Sync now").
  void kick({bool withParked = false}) => unawaited(run(withParked: withParked));

  /// One run; resolves when it (and any pass a trigger booked meanwhile) is over.
  Future<void> run({bool withParked = false}) {
    _wantParked |= withParked;
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
        final parked = _wantParked;
        _wantParked = false;
        await _drain(withParked: parked);
      } while (_again);
    } finally {
      _running = null;
      status.setSyncing(false);
    }
  }

  Future<void> _drain({bool withParked = false}) async {
    if (!outbox.available || outbox.viewingAs || !online.value) return;
    final uid = await outbox.currentUserId();
    if (uid == null) return;
    final tried = <String>{};
    Future<List<OutboxRow>> next() async => [
          for (final r in await outbox.rowsFor(uid))
            if (!tried.contains(r.id) && (withParked || r.state != OutboxRow.parked)) r,
        ];
    var rows = await next();
    if (rows.isEmpty) return;                      // nothing waits: no request
    _retry?.cancel();
    _retry = null;
    _told.clear();
    status.setSyncing(true);
    var owed = false;
    try {
      while (rows.isNotEmpty) {
        final batch = rows.length > batchMax ? rows.sublist(0, batchMax) : rows;
        tried.addAll(batch.map((r) => r.id));
        final o = await _push(uid, batch);
        owed |= o.owed;
        if (o.stop) break;
        if (!online.value || (await outbox.currentUserId()) != uid) return;
        rows = await next();
      }
      if (owed) _bookRetry();
    } finally {
      await outbox.refreshCount();
    }
  }

  /// A push that failed as a whole may succeed later: no status at all (transport, timeout), 408, 429, 5xx.
  static bool _retryable(int s) => s <= 0 || s == 408 || s == 429 || s >= 500 || s < 400;

  /// The push can not go now, but nothing is wrong with the ops: signed out under us, any 403 (the kill switch,
  /// a device or account block), or rows of another user than the token's.
  static bool _halt(ApiException e) =>
      e.isUnauthorized || e.statusCode == 401 || e.statusCode == 403 || (e.statusCode == 409 && e.code == 'sync_wrong_user');

  /// [r] stays for a later run: tries + 1 ([count]), parked at [OutboxRow.parkAt]. True = it still owes a retry.
  Future<bool> _keep(OutboxRow r, {bool count = true}) async {
    final tries = count ? r.tries + 1 : r.tries;
    final parked = r.state == OutboxRow.parked || tries >= OutboxRow.parkAt;
    await outbox.mark(r.id, tries: tries, state: parked ? OutboxRow.parked : OutboxRow.pending);
    return !parked;
  }

  /// [r] as it was before this push (a halted push is not a failure).
  Future<void> _restore(OutboxRow r) =>
      outbox.mark(r.id, state: r.state == OutboxRow.parked ? OutboxRow.parked : OutboxRow.pending);

  /// Sends [batch] as [uid]'s; `stop` = end the run now, `owed` = a kept row owes a retry.
  Future<({bool stop, bool owed})> _push(int uid, List<OutboxRow> batch) async {
    for (final r in batch) {
      await outbox.mark(r.id, state: OutboxRow.sending);
    }
    final Object? res;
    try {
      res = await api.post(pushPath, body: {'user_id': uid, 'ops': [for (final r in batch) _op(r)]});
    } catch (e) {
      final ex = ApiException.from(e);
      if (_halt(ex)) {
        debugPrint('sync: push halted (${ex.statusCode} ${ex.code}); ${batch.length} op(s) kept');
        for (final r in batch) {
          await _restore(r);
        }
        return (stop: true, owed: false);
      }
      if (_retryable(ex.statusCode)) {
        var owed = false;
        for (final r in batch) {
          owed |= await _keep(r);
        }
        return (stop: true, owed: owed);
      }
      // a 4xx the server will answer every time: find the op it can not take
      if (batch.length > 1) {
        for (final r in batch) {
          await _restore(r);
        }
        var owed = false;
        for (var i = 0; i < batch.length; i++) {
          final o = await _push(uid, [batch[i]]);
          owed |= o.owed;
          if (o.stop) return (stop: true, owed: owed);
        }
        return (stop: false, owed: owed);
      }
      final r = batch.single;
      debugPrint('sync: ${r.kind} op ${r.id} refused (${ex.statusCode} ${ex.code}); dropped');
      await outbox.remove([r.id]);
      _report([SyncResult(id: r.id, kind: r.kind, status: 'rejected', code: 'sync_bad_op')]);
      return (stop: false, owed: false);
    }
    _failures = 0;
    final byId = {for (final r in batch) r.id: r};
    final done = <String>[];
    final again = <String>{};
    final results = <SyncResult>[];
    final list = res is Map ? res['results'] : null;
    for (final x in list is List ? list : const []) {
      if (x is! Map) continue;
      final id = '${x['id'] ?? ''}';
      final row = byId[id];
      if (row == null) continue;
      final status = '${x['status'] ?? ''}';
      if (status != 'applied' && status != 'duplicate' && status != 'rejected') continue;
      final code = x['code']?.toString();
      if (status == 'rejected' && code == 'sync_error') {
        again.add(id);                             // transient on the server: kept and sent again later
        continue;
      }
      final ent = x['entity'];
      results.add(SyncResult(
        id: id,
        kind: row.kind,
        status: status,
        code: code,
        entity: ent is Map ? ent.map((k, v) => MapEntry('$k', v)) : null,
      ));
      done.add(id);
    }
    await outbox.remove(done);
    // a transient error and the rows the answer left out go back to waiting
    var owed = false;
    for (final r in batch) {
      if (!done.contains(r.id)) owed |= await _keep(r);
    }
    _report(results);
    return (stop: false, owed: owed);
  }

  /// Each refused op is told once (the same sentence twice in one run is one notice); every result reaches its
  /// kind's listeners.
  void _report(List<SyncResult> results) {
    for (final r in results) {
      if (!r.rejected) continue;
      final t = syncRejectedText(r.code);
      if (_told.add(t)) _notify(t);
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
