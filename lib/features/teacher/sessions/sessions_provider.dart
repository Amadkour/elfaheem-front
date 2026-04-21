import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_provider.dart';
import 'package:provider/provider.dart';
import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import '../../auth/auth_provider.dart';
import '../../student/models.dart';
import '../../student/sessions/sessions_provider.dart';
import 'live/prejoin.dart';

class TeacherSessionsProvider extends BaseProvider {
  final ApiClient _api;

  TeacherSessionsProvider({ApiClient? api}) : _api = api ?? ApiClient();

  List<TeacherSessionItem> _sessions = [];
  List<AttendanceRecord> _attendance = [];
  bool _attendanceLoading = false;

  List<TeacherSessionItem> get sessions => List.unmodifiable(_sessions);

  List<AttendanceRecord> get attendance => List.unmodifiable(_attendance);

  bool get attendanceLoading => _attendanceLoading;

  // ── Fetch ─────────────────────────────────────────────────────────────────

  Future<void> fetchSessions(int courseId) async {
    final result =
        await run(() => _api.get('/api/v1/courses/$courseId/sessions'));
    if (result is List) {
      _sessions = result
          .map((e) => TeacherSessionItem.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      notifyListeners();
    }
  }

  // ── Create ────────────────────────────────────────────────────────────────

  Future<TeacherSessionItem?> createSession({
    required int courseId,
    required String name,
    required String type,
    String? description,
    String? scheduledAt,
    int durationMinutes = 60,
    int order = 0,
  }) async {
    final result = await run(() => _api.post('/api/v1/sessions', body: {
          'course_id': courseId,
          'name': name,
          'type': type,
          if (description != null) 'description': description,
          if (scheduledAt != null) 'scheduled_at': scheduledAt,
          'duration_minutes': durationMinutes,
          'order': order,
        }));
    if (result is Map<String, dynamic>) {
      final s = TeacherSessionItem.fromJson(result);
      _sessions = [..._sessions, s]..sort((a, b) => a.order.compareTo(b.order));
      notifyListeners();
      return s;
    }
    return null;
  }

  // ── Update ────────────────────────────────────────────────────────────────

  Future<TeacherSessionItem?> updateSession(
    int sessionId, {
    String? name,
    String? description,
    String? type,
    String? scheduledAt,
    int? durationMinutes,
    int? order,
  }) async {
    final result =
        await run(() => _api.put('/api/v1/sessions/$sessionId', body: {
              if (name != null) 'name': name,
              if (description != null) 'description': description,
              if (type != null) 'type': type,
              if (scheduledAt != null) 'scheduled_at': scheduledAt,
              if (durationMinutes != null) 'duration_minutes': durationMinutes,
              if (order != null) 'order': order,
            }));
    if (result is Map<String, dynamic>) {
      final updated = TeacherSessionItem.fromJson(result);
      _sessions =
          _sessions.map((s) => s.id == sessionId ? updated : s).toList();
      notifyListeners();
      return updated;
    }
    return null;
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<bool> deleteSession(int sessionId) async {
    await run(() => _api.delete('/api/v1/sessions/$sessionId'));
    if (state == ProviderState.success) {
      _sessions = _sessions.where((s) => s.id != sessionId).toList();
      notifyListeners();
      return true;
    }
    return false;
  }

  // ── Live: Start ───────────────────────────────────────────────────────────

  Future<LiveResponseModel?> startLive(
    int sessionId, {
    bool enableRecording = true,
    int durationHours = 24,
  }) async {
    final result = await run(() => _api.post(
          '/api/v1/live-sessions/start',
          queryParams: {
            'session_id': sessionId,
            'enable_recording': enableRecording,
            'duration_hours': durationHours,
          },
        ));
    if (result is Map<String, dynamic>) {
      final url = result['ws_url'] as String? ?? '';
      final token = result['token'] as String? ?? '';
      // Mark session as active locally
      _sessions = _sessions
          .map((s) => s.id == sessionId
              ? s.copyWith(isLiveActive: true, roomUrl: url)
              : s)
          .toList();
      notifyListeners();
      return LiveResponseModel(sessionId: sessionId, url: url, token: token);
    }
    return null;
  }

  // ── Live: End ─────────────────────────────────────────────────────────────

  Future<bool> endLive(int sessionId, {bool saveRecording = true}) async {
    final result = await run(() => _api.post(
          '/api/v1/live-sessions/$sessionId/end',
          queryParams: {'save_recording': saveRecording},
        ));
    if (result != null) {
      _sessions = _sessions
          .map((s) => s.id == sessionId
              ? s.copyWith(
                  isLiveActive: false,
                  roomUrl: null,
                  recordingStatus: saveRecording ? 'pending' : null,
                )
              : s)
          .toList();
      notifyListeners();
      return true;
    }
    return false;
  }

  // ── Recording ─────────────────────────────────────────────────────────────

  Future<String?> fetchRecordingUrl(int sessionId) async {
    final result = await run(
      () => _api.get('/api/v1/live-sessions/$sessionId/recording'),
    );
    if (result is Map<String, dynamic>) {
      final url = result['recording_url'] as String?;
      if (url != null) {
        _sessions = _sessions
            .map((s) => s.id == sessionId
                ? s.copyWith(recordingUrl: url, recordingStatus: 'uploaded')
                : s)
            .toList();
        notifyListeners();
      }
      return url;
    }
    return null;
  }

  // ── Attendance ────────────────────────────────────────────────────────────

  Future<void> fetchAttendance(int sessionId) async {
    _attendanceLoading = true;
    notifyListeners();
    final result = await run(
      () => _api.get('/api/v1/sessions/$sessionId/attendance'),
    );
    _attendanceLoading = false;
    if (result is Map && result['attendance'] is List) {
      _attendance = (result['attendance'] as List)
          .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    notifyListeners();
  }

  void joinLive(
      BuildContext context, int sessionId, int courseId, int maxParticipants) {
    UserModel? user = context.read<AuthProvider>().currentUser;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PreJoinPage(
              args: JoinArgs(
                isTeacher: user!.isTeacher,
                userId: user.id,
                userName: user.name,
                sessionId: sessionId,
                courseId: courseId,
                maxStudents: maxParticipants,
                onEnd: () => _confirmEndSession(user, sessionId, context),
                onStart: () => _onStartLive(user, sessionId, context),
              ),
            )));
  }

  Future<void> _confirmEndSession(
      UserModel user, int sessionId, BuildContext context) async {
    // final confirm = await showDialog<bool>(
    //   context: context,
    //   builder: (ctx) => AlertDialog(
    //     backgroundColor: const Color(0xFF1E2235),
    //     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    //     title: const Text('End Session',
    //         style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    //     content: const Text(
    //       'This will end the session for all participants and save the recording.',
    //       style: TextStyle(color: Colors.white70),
    //     ),
    //     actions: [
    //       TextButton(
    //           onPressed: () => Navigator.pop(ctx, false),
    //           child:
    //               const Text('Cancel', style: TextStyle(color: Colors.blue))),
    //       ElevatedButton(
    //         style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
    //         onPressed: () => Navigator.pop(ctx, true),
    //         child: const Text('End Now'),
    //       ),
    //     ],
    //   ),
    // );
    // if (confirm != true) return;
    //
    // try {
    //   if (user.isTeacher) {
    await context.read<TeacherSessionsProvider>().endLive(sessionId);
    // } else {
    // }
    // } catch (_) {}
  }

  Future<LiveResponseModel?> _onStartLive(
      UserModel? user, int sessionId, BuildContext context) async {
    return await startLive(sessionId);
  }

  void clearAttendance() {
    _attendance = [];
    notifyListeners();
  }
}
