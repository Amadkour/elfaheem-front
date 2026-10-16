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
    try {
      switch (req['t']) {
        case 'hello':
          final w = await _repo.openWindow((req['session_id'] as num).toInt());
          return {'t': 'window', ...w.toJson()};
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

  @override
  void dispose() {
    _host.stop();
    super.dispose();
  }
}
