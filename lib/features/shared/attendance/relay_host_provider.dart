/// features/attendance/relay_host_provider.dart
///
/// App-wide provider for the ONLINE student who agrees to "Help classmates".
/// While enabled, the phone advertises over Nearby Connections; an offline classmate can
/// connect and the phone forwards their already-signed request to the server with THIS
/// student's normal login. The relay can neither read the student's key nor sign a result.
///
/// Opt-in on purpose (battery + permission prompts). The choice is remembered.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../exam_engine/offline/offline_exam_relay.dart';

import 'attendance_crypto.dart';
import 'attendance_permissions.dart';
import 'attendance_repository.dart';
import 'attendance_store.dart';
import 'relay_transport.dart';

class RelayHostProvider extends ChangeNotifier {
  RelayHostProvider({AttendanceRepository? repo, AttendanceStore? store, RelayHost? host})
      : _repo = repo ?? AttendanceRepository(),
        _store = store ?? AttendanceStore.instance,
        _host = host ?? RelayHost();

  static const _kEnabled = 'attendance_relay_enabled_v1';

  final AttendanceRepository _repo;
  final AttendanceStore _store;
  final RelayHost _host;

  bool enabled = false;
  bool starting = false;
  String? errorKey; // translation key
  bool needsSettings = false;
  int helped = 0;

  bool get supported => relayLinkSupported;
  bool get running => _host.running;
  String? get hostError => _host.lastError;

  /// Call once after login (e.g. from the home screen's initState).
  Future<void> init() async {
    helped = await _store.helped();
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_kEnabled) == true && supported) {
      await setEnabled(true, persist: false);
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool on, {bool persist = true}) async {
    errorKey = null;
    needsSettings = false;
    if (!on) {
      await _host.stop();
      enabled = false;
      if (persist) await _save(false);
      notifyListeners();
      return;
    }
    if (!supported) {
      errorKey = 'att_err_unsupported';
      notifyListeners();
      return;
    }
    starting = true;
    notifyListeners();

    final perm = await ensureNearbyPermissions(advertise: true);
    if (perm != PermissionOutcome.granted) {
      errorKey = 'att_err_perm';
      needsSettings = perm == PermissionOutcome.permanentlyDenied;
      starting = false;
      enabled = false;
      notifyListeners();
      return;
    }

    final ok = await _host.start(handler: _handle);
    enabled = ok;
    errorKey = ok ? null : 'att_err_bluetooth';
    starting = false;
    if (persist) await _save(ok);
    notifyListeners();
  }

  Future<void> _save(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, v);
  }

  /// Everything the relay does: forward, never decide.
  Future<Map<String, dynamic>> _handle(Map<String, dynamic> req) async {
    // an offline exam handed out / answers collected (same link, same opt-in)
    if ('${req['t']}'.startsWith('exam_')) return OfflineExamHost.instance.handle(req);
    try {
      switch (req['t']) {
        case 'hello':
          final w = await _repo.openWindow(
            sessionId: (req['session_id'] as num?)?.toInt(),
            courseId: (req['course_id'] as num?)?.toInt(),
          );
          return {'t': 'window', ...w.toJson()};
        case 'witness':
          // A teacher phone forwards check-ins but is not a classmate: it gives no signal.
          if (_teacherMode) return {'t': 'error', 'code': 'not_classmate', 'message': 'teacher'};
          // "I saw student X next to me" — signed with THIS phone's own key. Needs no internet.
          var me = await _store.readKey();
          if (me == null) {
            // never opened the sheet on this phone: fetch the key now (this phone is online)
            try {
              me = await _repo.fetchKey();
              await _store.saveKey(me);
            } catch (_) {}
          }
          if (me == null) return {'t': 'error', 'code': 'no_key', 'message': 'no key'};
          final ts = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
          final att = (req['att'] as num).toInt();
          final student = (req['student_id'] as num).toInt();
          return {
            't': 'witness',
            'user_id': me.userId,
            'ts': ts,
            'sig': signWitness(me.key, att, student, ts),
          };
        case 'submit':
          final body = <String, dynamic>{
            'request_id': req['request_id'],
            'attendance_session_id': req['attendance_session_id'],
            'student_id': req['student_id'],
            'code': req['code'],
            'signature': req['signature'],
          };
          final res = await _repo.submit(body);
          helped = await _store.incrementHelped();
          notifyListeners();
          return {'t': 'result', ...res};
      }
      return {'t': 'error', 'code': 'bad_message', 'message': 'unknown message'};
    } on ApiException catch (e) {
      return {'t': 'error', 'code': e.code ?? 'server_${e.statusCode}', 'message': e.message};
    }
  }

  // ── temporary hosting while a check-in sheet is open ─────────────────────
  // Classmates must be reachable at the moment a student checks in, so the phone advertises
  // while the sheet is open — even if the user never switched "Help classmates" on.
  bool _temporary = false;
  bool _teacherMode = false;

  /// [asTeacher]: the teacher's phone serves offline students (forwards their check-ins to the
  /// server) but never vouches as a classmate.
  Future<void> holdForCheckIn({bool asTeacher = false}) async {
    if (asTeacher) _teacherMode = true;
    if (!supported || _host.running) return;
    final perm = await ensureNearbyPermissions(advertise: true);
    if (perm != PermissionOutcome.granted) {
      _host.lastError = 'permission $perm';
      notifyListeners();
      return;
    }
    if (await _host.start(handler: _handle)) _temporary = true;
    notifyListeners();
  }

  Future<void> releaseCheckIn() async {
    if (_temporary && !enabled) await _host.stop();
    _temporary = false;
    _teacherMode = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _host.stop();
    super.dispose();
  }
}
