/// features/attendance/student_checkin_provider.dart
///
/// The student check-in flow. One instance per bottom sheet; the target is either one LESSON
/// ([sessionId]) or a whole COURSE ([courseId] — the newest open window of that course).
///
///   code typed ─► internet? ──► resolve the open window (server, cache, or ask a classmate)
///        │
///        ├─ window.requiredWitnesses > 0 ─► collect "I saw you" signals from N nearby classmates
///        │                                  (send our request, receive THEIR signed answer)
///        ▼
///   online  ► submit directly                    offline ► submit through a classmate (relay)
///        ▼
///   reply ► verify the SERVER signature ► only then show "present"
///
/// A result is shown ONLY after the server signature verifies. Anything else (timeout, lost
/// link, bad signature) is "pending" or "failed" — never "present".
library;

import 'package:flutter/foundation.dart';
import 'dart:async';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';

import 'attendance_crypto.dart';
import 'attendance_models.dart';
import 'attendance_offline_sync.dart';
import 'attendance_permissions.dart';
import 'attendance_repository.dart';
import 'attendance_store.dart';
import 'relay_host_provider.dart';
import 'relay_transport.dart';

enum Stage { network, permissions, relay, witness, send, server }

enum StageState { waiting, active, ok, failed, skipped }

enum OutcomeKind { accepted, rejected, pending, failed }

class CheckInOutcome {
  const CheckInOutcome(
    this.kind, {
    this.messageKey,
    this.result,
    this.viaRelay = false,
    this.needsSettings = false,
    this.detail,
  });
  final OutcomeKind kind;
  final String? messageKey; // translation key (already specific)
  final AttendanceResult? result;
  final bool viaRelay;
  final bool needsSettings; // permanently denied permission -> offer "open settings"
  final String? detail; // technical trace for field tests (shown small under the message)
}

class StudentCheckInProvider extends ChangeNotifier {
  StudentCheckInProvider({
    this.sessionId,
    this.courseId,
    AttendanceRepository? repo,
    AttendanceStore? store,
    RelayClient? relay,
    this.host,
  })  : assert(sessionId != null || courseId != null, 'sessionId or courseId is required'),
        _repo = repo ?? AttendanceRepository(),
        _store = store ?? AttendanceStore.instance,
        _relay = relay ?? RelayClient();

  final int? sessionId;
  final int? courseId;

  /// Lets the phone advertise while the sheet is open, so classmates can reach it too.
  final RelayHostProvider? host;

  final AttendanceRepository _repo;
  final AttendanceStore _store;
  final RelayClient _relay;

  static const _maxRelayAttempts = 3;
  static final _codeRe = RegExp(r'^\d{6}$');

  final Map<Stage, StageState> stages = {for (final s in Stage.values) s: StageState.waiting};
  CheckInOutcome? outcome;
  bool busy = false;
  bool? online; // null = not probed yet

  /// Classmates required by the teacher for the window we know about (0 = none).
  int witnessesNeeded = 0;

  /// Signals collected so far in the current attempt.
  int witnessesFound = 0;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _relay.stop();
    host?.releaseCheckIn();
    super.dispose();
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _stage(Stage s, StageState st) {
    stages[s] = st;
    _emit();
  }

  void _finish(CheckInOutcome o) {
    outcome = o;
    busy = false;
    _emit();
  }

  void _fail(String key, {Stage? at, bool needsSettings = false, String? detail}) {
    if (at != null) _stage(at, StageState.failed);
    _finish(CheckInOutcome(OutcomeKind.failed,
        messageKey: key, needsSettings: needsSettings, detail: detail));
  }

  void reset() {
    for (final s in Stage.values) {
      stages[s] = StageState.waiting;
    }
    outcome = null;
    busy = false;
    witnessesFound = 0;
    _emit();
  }

  /// Fetches the key as the internet probe. Skipped when the phone already knows it is offline,
  /// and capped at 8 s (the API client's own connect timeout is very long, which used to make
  /// an offline check-in sit "searching" for minutes before even looking for a classmate).
  Future<StudentKey?> _probeKey() async {
    if (!AppConnectivity.instance.isOnline) throw const _Offline();
    try {
      return await _repo.fetchKey().timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw const _Offline();
    }
  }

  Future<OpenWindow?> _cachedWindow() =>
      sessionId != null ? _store.window(sessionId!) : _store.windowForCourse(courseId!);

  Future<OpenWindow> _fetchWindow() =>
      _repo.openWindow(sessionId: sessionId, courseId: courseId);

  // ── entry: called when the sheet opens ────────────────────────────────
  /// Warms the cache while the student still has internet (key + window), makes this phone
  /// reachable for classmates, and re-sends any request whose answer was lost earlier.
  Future<void> warmUp() async {
    try {
      final k = await _probeKey();
      if (k != null) await _store.saveKey(k);
      online = true;
    } on ApiException catch (e) {
      online = !(e.isNetwork || e.isTimeout);
    } catch (_) {
      online = false;
    }
    // An online phone must be discoverable while its sheet is open, otherwise an offline
    // classmate can never find it (even when the teacher requires no classmate signals).
    if (online == true) host?.holdForCheckIn();
    OpenWindow? w;
    if (online == true) {
      try {
        w = await _fetchWindow();
        await _store.saveWindow(w);
      } catch (_) {}
      await _flushPending();
    }
    w ??= await _cachedWindow();
    witnessesNeeded = w?.requiredWitnesses ?? 0;
    _emit();
  }

  Future<void> _flushPending() async {
    for (final f in await AttendanceOfflineSync.instance.flushPending()) {
      final mine = sessionId != null
          ? f.pending.sessionId == sessionId
          : (await _cachedWindow())?.sessionId == f.pending.sessionId;
      if (mine && outcome == null) {
        _finish(_outcomeFrom(f.result, viaRelay: false));
      }
    }
  }

  // ── main flow ─────────────────────────────────────────────────────────
  Future<void> submit(String rawCode) async {
    if (busy) return;
    final code = rawCode.trim();
    reset();
    if (!_codeRe.hasMatch(code)) {
      _finish(const CheckInOutcome(OutcomeKind.failed, messageKey: 'att_err_code_format'));
      return;
    }
    busy = true;
    _stage(Stage.network, StageState.active);

    // 1) internet probe (also refreshes the key)
    StudentKey? key = await _store.readKey();
    bool isOnline;
    try {
      key = await _probeKey() ?? key;
      if (key != null) await _store.saveKey(key);
      isOnline = true;
    } on ApiException catch (e) {
      if (e.isNetwork || e.isTimeout) {
        isOnline = false;
      } else {
        _fail('att_err_generic', at: Stage.network);
        return;
      }
    } catch (_) {
      isOnline = false;
    }
    online = isOnline;
    _stage(Stage.network, StageState.ok);

    if (key == null) {
      _fail('att_err_no_key', at: Stage.network);
      return;
    }

    if (isOnline) {
      await _submitOnline(code, key);
    } else {
      await _submitOffline(code, key);
    }
  }

  // ── online path: the student is their own relay ───────────────────────
  Future<void> _submitOnline(String code, StudentKey key) async {
    _stage(Stage.relay, StageState.skipped);

    OpenWindow window;
    try {
      window = await _fetchWindow();
      await _store.saveWindow(window);
    } on ApiException catch (e) {
      _fail(e.code == 'no_open_attendance' || e.isNotFound ? 'att_err_no_window' : 'att_err_generic',
          at: Stage.send);
      return;
    }
    witnessesNeeded = window.requiredWitnesses;

    // Classmate signals (only when the teacher asked for them).
    List<Map<String, dynamic>> witnesses = const [];
    if (witnessesNeeded > 0) {
      final got = await _collectWitnesses(window, key, links: null);
      if (got == null) return; // _collectWitnesses already reported the failure
      witnesses = got;
    } else {
      _stage(Stage.permissions, StageState.skipped);
      _stage(Stage.witness, StageState.skipped);
    }

    _stage(Stage.send, StageState.active);
    final p = _build(code, key, window, witnesses);
    await _store.addPending(p);
    _stage(Stage.send, StageState.ok);
    _stage(Stage.server, StageState.active);
    try {
      final res = AttendanceResult.fromJson(await _repo.submit(p.toSubmitBody()));
      await _confirm(res, key, p, viaRelay: false);
    } on ApiException catch (e) {
      if (e.isNetwork || e.isTimeout) {
        _stage(Stage.server, StageState.failed);
        _finish(const CheckInOutcome(OutcomeKind.pending));
      } else {
        await _store.removePending(p.requestId);
        _fail(_errorKey(e.code), at: Stage.server);
      }
    }
  }

  // ── offline path ──────────────────────────────────────────────────────
  Future<void> _submitOffline(String code, StudentKey key) async {
    if (!relayLinkSupported) {
      _fail('att_err_unsupported', at: Stage.permissions);
      return;
    }
    if (!await _permissions()) return;

    PendingAttendance? pending;
    final tried = <String>{};

    for (var attempt = 0; attempt < _maxRelayAttempts; attempt++) {
      // How many phones do we need to reach? The relay + (the witnesses, which are also relays).
      final want = witnessesNeeded > 0 ? witnessesNeeded : 1;
      _stage(Stage.relay, StageState.active);
      List<RelayLink> links;
      try {
        links = await _relay.connectMany(count: want, skip: tried);
      } on RelayException catch (e) {
        if (pending != null && e.kind == RelayFailure.noRelay) break; // keep it pending
        _fail(e.kind == RelayFailure.bluetoothOff ? 'att_err_bluetooth' : 'att_err_no_relay',
            at: Stage.relay, detail: e.detail ?? _relay.diag);
        return;
      }
      for (final l in links) {
        tried.add(l.endpointId);
      }
      _stage(Stage.relay, StageState.ok);

      try {
        // 1) Which window? ALWAYS ask the classmate first (it asks the server): the teacher may
        //    have opened a newer attendance since this phone last saw the internet, and the
        //    cached window would then point at the old, closed one. The cache is only a fallback
        //    when no classmate answers the question.
        OpenWindow? window;
        if (pending == null) {
          try {
            final r = await links.first.request({
              't': 'hello',
              if (sessionId != null) 'session_id': sessionId,
              if (courseId != null) 'course_id': courseId,
            }, timeout: const Duration(seconds: 15));
            if (r['t'] == 'window') {
              window = OpenWindow.fromJson(r);
              await _store.saveWindow(window);
            } else if (r['code']?.toString() == 'no_open_attendance') {
              await _closeAll(links);
              _fail('att_err_no_window', at: Stage.send);
              return;
            }
          } on RelayException {
            // fall through to the cache
          }
          window ??= await _cachedWindow();
          if (window == null) {
            await _closeAll(links);
            _fail('att_err_no_window', at: Stage.send);
            return;
          }
        }
        if (window != null) witnessesNeeded = window.requiredWitnesses;

        // 2) Classmate signals.
        if (pending == null) {
          List<Map<String, dynamic>> witnesses = const [];
          // The phone that forwards the request is itself one of the required classmates (the
          // server counts it), so only N-1 more signed signals are collected from the OTHER
          // phones. With N = 1 and two devices nothing else is needed.
          final extra = witnessesNeeded - 1;
          if (extra > 0) {
            final got = await _collectWitnesses(window!, key,
                links: links, need: extra, ask: links.skip(1).toList());
            if (got == null) {
              await _closeAll(links);
              return;
            }
            witnesses = got;
          } else {
            _stage(Stage.witness, StageState.skipped);
          }
          pending = _build(code, key, window!, witnesses);
          await _store.addPending(pending); // persisted BEFORE it leaves the phone
        }

        // 3) Send through the first classmate that still answers.
        _stage(Stage.send, StageState.active);
        Map<String, dynamic>? reply;
        for (final l in links) {
          try {
            reply = await l.request({'t': 'submit', ...pending.toSubmitBody()});
            break;
          } on RelayException {
            continue;
          }
        }
        await _closeAll(links);
        if (reply == null) {
          _stage(Stage.send, StageState.failed);
          continue; // same request_id on another classmate: the server answers idempotently
        }

        if (reply['t'] == 'error') {
          final c = reply['code']?.toString();
          if (c == 'relay_not_allowed') continue; // that classmate is not in the course
          await _store.removePending(pending.requestId);
          _fail(_errorKey(c), at: Stage.send);
          return;
        }

        _stage(Stage.send, StageState.ok);
        _stage(Stage.server, StageState.active);
        await _confirm(AttendanceResult.fromJson(reply), key, pending, viaRelay: true);
        return;
      } on RelayException {
        await _closeAll(links);
        _stage(Stage.send, StageState.failed);
        continue;
      } catch (_) {
        await _closeAll(links);
        continue;
      }
    }

    // Never got a verified answer. The request is stored; it will be re-sent when online.
    _stage(Stage.server, StageState.failed);
    _finish(const CheckInOutcome(OutcomeKind.pending, viaRelay: true));
  }

  // ── classmate signals ─────────────────────────────────────────────────
  /// Sends our request ("I am student X, attendance window W") to nearby classmates and
  /// RECEIVES their signed answers. Returns the collected witnesses, or null after reporting
  /// a failure. [links] = already-open connections (offline path); null = connect now.
  Future<List<Map<String, dynamic>>?> _collectWitnesses(
    OpenWindow window,
    StudentKey key, {
    required List<RelayLink>? links,
    int? need,
    List<RelayLink>? ask,
  }) async {
    need ??= window.requiredWitnesses;
    final target = need;
    if (links == null && !await _permissions()) return null;
    // Our own phone must be visible too (classmates may be collecting signals from us).
    host?.holdForCheckIn();

    _stage(Stage.witness, StageState.active);
    witnessesFound = 0;
    _emit();

    final own = links == null;
    List<RelayLink> use = links ?? const [];
    if (own) {
      try {
        use = await _relay.connectMany(count: need);
      } on RelayException catch (e) {
        _fail(e.kind == RelayFailure.bluetoothOff ? 'att_err_bluetooth' : 'att_err_witnesses',
            at: Stage.witness, detail: e.detail ?? _relay.diag);
        return null;
      }
    }

    final got = <int, Map<String, dynamic>>{};
    for (final l in (ask ?? use)) {
      if (got.length >= target) break;
      try {
        final r = await l.request({
          't': 'witness',
          'att': window.attendanceSessionId,
          'student_id': key.userId,
        }, timeout: const Duration(seconds: 10));
        if (r['t'] == 'witness') {
          final id = (r['user_id'] as num).toInt();
          if (id != key.userId) {
            got[id] = {'user_id': id, 'ts': (r['ts'] as num).toInt(), 'sig': r['sig'].toString()};
            witnessesFound = got.length;
            _emit();
          }
        }
      } on RelayException {
        continue;
      }
    }
    if (own) await _closeAll(use);

    if (got.length < target) {
      _fail('att_err_witnesses',
          at: Stage.witness,
          detail: '${_relay.diag}; classmates that answered=${got.length}/$target');
      return null;
    }
    _stage(Stage.witness, StageState.ok);
    return got.values.toList();
  }

  Future<bool> _permissions() async {
    if (stages[Stage.permissions] == StageState.ok) return true;
    _stage(Stage.permissions, StageState.active);
    final perm = await ensureNearbyPermissions(advertise: true);
    if (perm != PermissionOutcome.granted) {
      _fail('att_err_perm',
          at: Stage.permissions, needsSettings: perm == PermissionOutcome.permanentlyDenied);
      return false;
    }
    _stage(Stage.permissions, StageState.ok);
    return true;
  }

  Future<void> _closeAll(List<RelayLink> l) async {
    for (final x in l) {
      await x.close();
    }
  }

  // ── helpers ───────────────────────────────────────────────────────────
  PendingAttendance _build(
      String code, StudentKey key, OpenWindow w, List<Map<String, dynamic>> witnesses) {
    final id = newRequestId();
    return PendingAttendance(
      requestId: id,
      sessionId: w.sessionId,
      attendanceSessionId: w.attendanceSessionId,
      studentId: key.userId,
      code: code,
      signature: signRequest(key.key, id, w.attendanceSessionId, code),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      witnesses: witnesses,
    );
  }

  bool _valid(AttendanceResult r, StudentKey key, PendingAttendance p) =>
      r.requestId == p.requestId &&
      r.studentId == p.studentId &&
      r.attendanceSessionId == p.attendanceSessionId &&
      verifyResult(
        studentKey: key.key,
        requestId: r.requestId,
        status: r.status,
        confirmedAt: r.confirmedAt,
        signature: r.serverSignature,
      );

  Future<void> _confirm(AttendanceResult r, StudentKey key, PendingAttendance p,
      {required bool viaRelay}) async {
    if (!_valid(r, key, p)) {
      // Do NOT remove the pending request: an honest retry may still obtain a good answer.
      _stage(Stage.server, StageState.failed);
      _fail('att_err_forged');
      return;
    }
    await _store.removePending(p.requestId);
    _stage(Stage.server, StageState.ok);
    _finish(_outcomeFrom(r, viaRelay: viaRelay));
  }

  CheckInOutcome _outcomeFrom(AttendanceResult r, {required bool viaRelay}) => r.accepted
      ? CheckInOutcome(OutcomeKind.accepted, result: r, viaRelay: viaRelay)
      : CheckInOutcome(OutcomeKind.rejected,
          result: r, viaRelay: viaRelay, messageKey: 'att_reason_${r.reason ?? 'wrong_code'}');

  String _errorKey(String? code) => switch (code) {
        'invalid_signature' => 'att_err_invalid_signature',
        'relay_not_allowed' => 'att_err_relay_not_allowed',
        'no_open_attendance' => 'att_err_no_window',
        _ => 'att_err_generic',
      };
}

class _Offline implements Exception {
  const _Offline();
}
