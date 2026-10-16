/// features/attendance/student_checkin_provider.dart
///
/// The student check-in flow (one instance per lesson, scoped to the bottom sheet):
///
///   code typed ─► internet? ──yes──► submit directly (student is their own relay)
///                    │ no
///                    ▼
///            permissions ► find online classmate (Nearby) ► [ask window id] ► send signed request
///                    ▼
///            reply ► verify the SERVER signature ► only then show "present"
///
/// A result is shown to the student ONLY after the server signature verifies. Anything else
/// (timeout, lost link, bad signature) is "pending" or "failed" — never "present".
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/api_client.dart';

import 'attendance_crypto.dart';
import 'attendance_models.dart';
import 'attendance_offline_sync.dart';
import 'attendance_permissions.dart';
import 'attendance_repository.dart';
import 'attendance_store.dart';
import 'relay_transport.dart';

enum Stage { network, permissions, relay, send, server }

enum StageState { waiting, active, ok, failed, skipped }

enum OutcomeKind { accepted, rejected, pending, failed }

class CheckInOutcome {
  const CheckInOutcome(
    this.kind, {
    this.messageKey,
    this.result,
    this.viaRelay = false,
    this.needsSettings = false,
  });
  final OutcomeKind kind;
  final String? messageKey; // translation key (already specific)
  final AttendanceResult? result;
  final bool viaRelay;
  final bool needsSettings; // permanently denied permission -> offer "open settings"
}

class StudentCheckInProvider extends ChangeNotifier {
  StudentCheckInProvider({
    required this.sessionId,
    AttendanceRepository? repo,
    AttendanceStore? store,
    RelayClient? relay,
  })  : _repo = repo ?? AttendanceRepository(),
        _store = store ?? AttendanceStore.instance,
        _relay = relay ?? RelayClient();

  final int sessionId;
  final AttendanceRepository _repo;
  final AttendanceStore _store;
  final RelayClient _relay;

  static const _maxRelayAttempts = 3;
  static final _codeRe = RegExp(r'^\d{6}$');

  final Map<Stage, StageState> stages = {for (final s in Stage.values) s: StageState.waiting};
  CheckInOutcome? outcome;
  bool busy = false;
  bool? online; // null = not probed yet
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _relay.stop();
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

  void _fail(String key, {Stage? at, bool needsSettings = false}) {
    if (at != null) _stage(at, StageState.failed);
    _finish(CheckInOutcome(OutcomeKind.failed, messageKey: key, needsSettings: needsSettings));
  }

  void reset() {
    for (final s in Stage.values) {
      stages[s] = StageState.waiting;
    }
    outcome = null;
    busy = false;
    _emit();
  }

  // ── entry: called when the sheet opens ────────────────────────────────
  /// Warms the cache while the student still has internet (key + this lesson's window) and
  /// re-sends any request whose answer was lost earlier.
  Future<void> warmUp() async {
    try {
      await _store.saveKey(await _repo.fetchKey());
      online = true;
    } on ApiException catch (e) {
      online = !(e.isNetwork || e.isTimeout);
    } catch (_) {
      online = false;
    }
    if (online == true) {
      try {
        await _store.saveWindow(await _repo.openWindow(sessionId));
      } catch (_) {}
      await _flushPending();
    }
    _emit();
  }

  Future<void> _flushPending() async {
    for (final f in await AttendanceOfflineSync.instance.flushPending()) {
      if (f.pending.sessionId == sessionId && outcome == null) {
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
      key = await _repo.fetchKey();
      await _store.saveKey(key);
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
      await _submitDirect(code, key);
    } else {
      await _submitViaRelay(code, key);
    }
  }

  // ── online path: the student is their own relay ───────────────────────
  Future<void> _submitDirect(String code, StudentKey key) async {
    for (final s in [Stage.permissions, Stage.relay]) {
      _stage(s, StageState.skipped);
    }
    _stage(Stage.send, StageState.active);

    OpenWindow window;
    try {
      window = await _repo.openWindow(sessionId);
      await _store.saveWindow(window);
    } on ApiException catch (e) {
      _fail(e.code == 'no_open_attendance' || e.isNotFound ? 'att_err_no_window' : 'att_err_generic',
          at: Stage.send);
      return;
    }

    final p = _build(code, key, window.attendanceSessionId);
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
  Future<void> _submitViaRelay(String code, StudentKey key) async {
    if (!relayLinkSupported) {
      _fail('att_err_unsupported', at: Stage.permissions);
      return;
    }

    _stage(Stage.permissions, StageState.active);
    final perm = await ensureNearbyPermissions(advertise: false);
    if (perm != PermissionOutcome.granted) {
      _fail('att_err_perm',
          at: Stage.permissions, needsSettings: perm == PermissionOutcome.permanentlyDenied);
      return;
    }
    _stage(Stage.permissions, StageState.ok);

    PendingAttendance? pending;
    final tried = <String>{};

    for (var attempt = 0; attempt < _maxRelayAttempts; attempt++) {
      _stage(Stage.relay, StageState.active);
      RelayLink link;
      try {
        link = await _relay.connect(skip: tried);
      } on RelayException catch (e) {
        if (pending != null && e.kind == RelayFailure.noRelay) break; // keep it pending
        _fail(e.kind == RelayFailure.bluetoothOff ? 'att_err_bluetooth' : 'att_err_no_relay',
            at: Stage.relay);
        return;
      }
      tried.add(link.endpointId);
      _stage(Stage.relay, StageState.ok);
      _stage(Stage.send, StageState.active);

      try {
        // Which window? Use the cache, else ask the relay (it asks the server for us).
        if (pending == null) {
          var window = await _store.window(sessionId);
          if (window == null) {
            final r = await link.request({'t': 'hello', 'session_id': sessionId});
            if (r['t'] != 'window') {
              await link.close();
              _fail(r['code'] == 'no_open_attendance' ? 'att_err_no_window' : _errorKey(r['code']?.toString()),
                  at: Stage.send);
              return;
            }
            window = OpenWindow.fromJson(r);
          }
          pending = _build(code, key, window.attendanceSessionId);
          await _store.addPending(pending); // persisted BEFORE it leaves the phone
        }

        final reply = await link.request({'t': 'submit', ...pending.toSubmitBody()});
        await link.close();

        if (reply['t'] == 'error') {
          final c = reply['code']?.toString();
          if (c == 'relay_not_allowed') {
            continue; // this classmate is not in the course -> try another one
          }
          await _store.removePending(pending.requestId);
          _fail(_errorKey(c), at: Stage.send);
          return;
        }

        _stage(Stage.send, StageState.ok);
        _stage(Stage.server, StageState.active);
        await _confirm(AttendanceResult.fromJson(reply), key, pending, viaRelay: true);
        return;
      } on RelayException {
        await link.close();
        _stage(Stage.send, StageState.failed);
        // Same request_id on the next relay: the server answers idempotently.
        continue;
      } catch (_) {
        await link.close();
        continue;
      }
    }

    // Never got a verified answer. The request is stored; it will be re-sent when online.
    _stage(Stage.server, StageState.failed);
    _finish(const CheckInOutcome(OutcomeKind.pending, viaRelay: true));
  }

  // ── helpers ───────────────────────────────────────────────────────────
  PendingAttendance _build(String code, StudentKey key, int attId) {
    final id = newRequestId();
    return PendingAttendance(
      requestId: id,
      sessionId: sessionId,
      attendanceSessionId: attId,
      studentId: key.userId,
      code: code,
      signature: signRequest(key.key, id, attId, code),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
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
