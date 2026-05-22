import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import '../../auth/auth_provider.dart';
import '../../student/models.dart';
import 'live/prejoin.dart';
import 'model/live_response_model.dart';
import 'model/session_material_model.dart';

class TeacherSessionsProvider extends BaseProvider {
  final ApiClient _api;

  TeacherSessionsProvider({ApiClient? api}) : _api = api ?? ApiClient();

  List<TeacherSessionItem> _sessions = [];
  List<AttendanceRecord> _attendance = [];
  bool _attendanceLoading = false;
  final Map<int, List<SessionMaterialModel>> _materials = {};
  final Map<int, bool> _uploadingMaterial = {};

  List<TeacherSessionItem> get sessions => List.unmodifiable(_sessions);

  List<AttendanceRecord> get attendance => List.unmodifiable(_attendance);

  bool get attendanceLoading => _attendanceLoading;

  List<SessionMaterialModel> materialsFor(int sessionId) =>
      List.unmodifiable(_materials[sessionId] ?? []);

  bool isUploadingMaterial(int sessionId) =>
      _uploadingMaterial[sessionId] ?? false;

  // ── Fetch sessions ────────────────────────────────────────────────────────

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

  // ── Create / Update / Delete sessions ────────────────────────────────────

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

  Future<bool> deleteSession(int sessionId) async {
    await run(() => _api.delete('/api/v1/sessions/$sessionId'));
    if (state == ProviderState.success) {
      _sessions = _sessions.where((s) => s.id != sessionId).toList();
      _materials.remove(sessionId);
      notifyListeners();
      return true;
    }
    return false;
  }

  // ── Materials ─────────────────────────────────────────────────────────────

  Future<void> fetchMaterials(int sessionId) async {
    final r =
    await run(() => _api.get('/api/v1/sessions/$sessionId/materials'));
    if (r is List) {
      _materials[sessionId] = r
          .map((e) => SessionMaterialModel.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    }
  }

  /// Upload a file (image / video / PDF / document) as session material.
  /// Uses multipart/form-data.
  Future<SessionMaterialModel?> uploadFileMaterial({
    required int sessionId,
    required String fileName,
    required String name,
    String? description,
    int order = 0,
    Uint8List? fileBytes,
  }) async {
    _uploadingMaterial[sessionId] = true;
    notifyListeners();
    try {

      print(fileName);
      print(fileBytes!.length);
      final result =
      await _api.postMultipart('/api/v1/sessions/$sessionId/materials/file',
          fields: {
            'name': name,
            if (description != null) 'description': description,
            'order': order.toString(),
          },
          fileField: 'file',
          fileName: fileName,
          fileBytes:fileBytes!
      );
      if (result is Map<String, dynamic>) {
        final mat = SessionMaterialModel.fromJson(result);
        _materials[sessionId] = [...(_materials[sessionId] ?? []), mat]
          ..sort((a, b) => a.order.compareTo(b.order));
        notifyListeners();
        return mat;
      }
    } finally {
      _uploadingMaterial[sessionId] = false;
      notifyListeners();
    }
    return null;
  }

  /// Add an external link as session material.
  Future<SessionMaterialModel?> addLinkMaterial({
    required int sessionId,
    required String name,
    required String url,
    String? description,
    int order = 0,
  }) async {
    final r = await run(() => _api.post(
      '/api/v1/sessions/$sessionId/materials/link',
      body: {
        'session_id': sessionId,
        'name': name,
        'url': url,
        'type': 'link',
        if (description != null) 'description': description,
        'order': order,
      },
    ));
    if (r is Map<String, dynamic>) {
      final mat = SessionMaterialModel.fromJson(r);
      _materials[sessionId] = [...(_materials[sessionId] ?? []), mat]
        ..sort((a, b) => a.order.compareTo(b.order));
      notifyListeners();
      return mat;
    }
    return null;
  }

  /// Update material metadata.
  Future<bool> updateMaterial(
      int sessionId,
      int materialId, {
        String? name,
        String? description,
        String? url,
        int? order,
      }) async {
    final r = await run(() => _api.put(
      '/api/v1/sessions/$sessionId/materials/$materialId',
      body: {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (url != null) 'url': url,
        if (order != null) 'order': order,
      },
    ));
    if (r is Map<String, dynamic>) {
      final updated = SessionMaterialModel.fromJson(r);
      _materials[sessionId] = (_materials[sessionId] ?? [])
          .map((m) => m.id == materialId ? updated : m)
          .toList();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Delete material.
  Future<bool> deleteMaterial(int sessionId, int materialId) async {
    await run(
            () => _api.delete('/api/v1/sessions/$sessionId/materials/$materialId'));
    if (state == ProviderState.success) {
      _materials[sessionId] = (_materials[sessionId] ?? [])
          .where((m) => m.id != materialId)
          .toList();
      notifyListeners();
      return true;
    }
    return false;
  }

  // ── Live ──────────────────────────────────────────────────────────────────

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
      final url = LiveResponseModel(
        sessionId: sessionId,
        url: result['ws_url'] as String? ?? '',
        token: result['token'] as String? ?? '',
      );
      _sessions = _sessions
          .map((s) => s.id == sessionId
          ? s.copyWith(isLiveActive: true, roomUrl: url.url)
          : s)
          .toList();
      notifyListeners();
      return url;
    }
    return null;
  }

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
          recordingStatus: saveRecording ? 'pending' : null)
          : s)
          .toList();
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<String?> fetchRecordingUrl(int sessionId) async {
    final result =
    await run(() => _api.get('/api/v1/live-sessions/$sessionId/recording'));
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

  // ── Completion (student) ──────────────────────────────────────────────────

  /// Called when a student finishes viewing a material (video end, image view,
  /// PDF/doc/link open). Hits POST /sessions/{id}/materials/{matId}/complete.
  Future<void> markMaterialComplete(int sessionId, int materialId) async {
    await run(
          () => _api.post(
        '/api/v1/sessions/$sessionId/materials/$materialId/complete',
      ),
    );
  }

  /// Called when a student leaves a live session (room page pops).
  /// Hits POST /sessions/{id}/complete.
  Future<void> markSessionComplete(int sessionId) async {
    await run(
          () => _api.post('/api/v1/sessions/$sessionId/complete'),
    );
  }

  // ── Attendance ────────────────────────────────────────────────────────────

  Future<void> fetchAttendance(int sessionId) async {
    _attendanceLoading = true;
    notifyListeners();
    final result =
    await run(() => _api.get('/api/v1/sessions/$sessionId/attendance'));
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
    final user = context.read<AuthProvider>().currentUser;
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
            // Teachers start the room; students fetch a personal join token.
            onStart: user.isTeacher
                ? () => _onStartLive(user, sessionId, context)
                : () => _onJoinLiveAsStudent(sessionId, context),
            // Students: automatically mark live session complete when they leave
            onComplete: user.isTeacher
                ? null
                : () => markSessionComplete(sessionId),
          ),
        )));
  }

  Future<void> _confirmEndSession(
      dynamic user, int sessionId, BuildContext context) async {
    await context.read<TeacherSessionsProvider>().endLive(sessionId);
  }

  Future<LiveResponseModel?> _onStartLive(
      dynamic user, int sessionId, BuildContext context) async {
    return await startLive(sessionId);
  }

  /// Student join: hits GET /api/v1/live-sessions/{sessionId}/join
  /// Returns a [LiveResponseModel] with the room URL + personal token,
  /// or null on error.
  Future<LiveResponseModel?> _onJoinLiveAsStudent(
      int sessionId, BuildContext context) async {
    final result =
    await run(() => _api.get('/api/v1/live-sessions/$sessionId/join'));
    if (result is Map<String, dynamic>) {
      return LiveResponseModel(
        sessionId: sessionId,
        url: result['ws_url'] as String? ?? '',
        token: result['token'] as String? ?? '',
      );
    }
    return null;
  }

  void clearAttendance() {
    _attendance = [];
    notifyListeners();
  }
}