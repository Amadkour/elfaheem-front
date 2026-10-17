/// features/attendance/teacher_attendance_provider.dart
///
/// Teacher side: open an attendance window for a lesson, show the rotating code,
/// watch the live "present" counter, close the window. Scoped to the teacher sheet.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/api_client.dart';

import 'attendance_models.dart';
import 'attendance_repository.dart';
import 'relay_host_provider.dart';

class TeacherAttendanceProvider extends ChangeNotifier {
  TeacherAttendanceProvider({required this.sessionId, AttendanceRepository? repo, this.host})
      : _repo = repo ?? AttendanceRepository();

  final int sessionId;

  /// While the window is open this phone is visible to nearby OFFLINE students and forwards their
  /// check-ins to the server (needs internet on this phone). Not a classmate: gives no signals.
  final RelayHostProvider? host;
  final AttendanceRepository _repo;

  TeacherWindow? window;
  TeacherCode? code;
  int secondsLeft = 0;
  int minutes = 15;

  /// Classmate signals each student must collect (0 = none). Chosen before starting.
  int requiredWitnesses = 0;
  bool loading = false;
  bool closed = false;
  String? error;

  Timer? _tick;
  int _sinceSync = 0;
  bool _disposed = false;

  static const _syncEvery = 5; // seconds: refresh counter + resync clock
  static const options = [10, 15, 30, 60];
  static const witnessOptions = [0, 1, 2, 3, 4, 5];

  bool get isOpen => window != null && !closed && (code?.isOpen ?? true);

  void setMinutes(int m) {
    minutes = m;
    notifyListeners();
  }

  void setWitnesses(int n) {
    requiredWitnesses = n.clamp(0, 10);
    notifyListeners();
  }

  Future<void> open({int rotationSeconds = 45}) async {
    if (loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      window = await _repo.open(sessionId,
          minutes: minutes, rotation: rotationSeconds, witnesses: requiredWitnesses);
      closed = false;
      host?.holdForCheckIn(asTeacher: true);
      await _sync();
      _startTicker();
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> close() async {
    final w = window;
    if (w == null) return;
    loading = true;
    notifyListeners();
    try {
      await _repo.close(w.id);
      closed = true;
      _tick?.cancel();
      host?.releaseCheckIn();
    } on ApiException catch (e) {
      error = e.message;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _sync() async {
    final w = window;
    if (w == null) return;
    try {
      final c = await _repo.code(w.id);
      code = c;
      secondsLeft = c.secondsLeft;
      _sinceSync = 0;
      if (!c.isOpen) {
        _tick?.cancel(); // expired on the server
        host?.releaseCheckIn();
      }
    } on ApiException catch (e) {
      error = e.message; // keep ticking: a short network blip must not blank the screen
    }
  }

  void _startTicker() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_disposed) return;
      secondsLeft = secondsLeft > 0 ? secondsLeft - 1 : 0;
      _sinceSync++;
      if (secondsLeft == 0 || _sinceSync >= _syncEvery) {
        await _sync();
      }
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _tick?.cancel();
    host?.releaseCheckIn();
    super.dispose();
  }
}
