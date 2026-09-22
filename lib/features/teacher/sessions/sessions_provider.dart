// teacher_course_screen_provider.dart
//
// Scoped provider for TeacherSessionsScreen.
// Combines course header data + sessions list in one place so the screen has
// a single ChangeNotifier to watch.  Created with MultiProvider and disposed
// automatically when the route is popped.
//
// CHANGES from original:
//   • joinLive() now passes `apiClient` into JoinArgs (required by the new
//     RoomPage._ClientRecorder for authenticated chunk uploads).
//   • _confirmEndSession() is now fire-and-forget safe (recording stop is
//     handled inside RoomPage._endSessionWithRecording before onEnd fires).
//   • No other logic changed.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/api_client.dart';
import '../../../../core/base_provider.dart';
import '../../auth/auth_provider.dart';
import '../../shared/session/material/session_material_model.dart';
import '../../student/models.dart';
import '../home/teacher_models.dart';
import 'live/prejoin.dart';
import 'model/live_response_model.dart';

class TeacherCourseScreenProvider extends BaseProvider {
  TeacherCourseScreenProvider({
    required TeacherCourse initialCourse,
    ApiClient? api,
  }) : _api = api ?? ApiClient(),
        _course = initialCourse;

  final ApiClient _api;

  // ── Course header ─────────────────────────────────────────────────────────

  TeacherCourse _course;

  TeacherCourse get course => _course;

  /// Optional intro video (عرض أولي) from `reel_url` of GET /courses/{id}.
  String? _reelUrl;

  String? get reelUrl => _reelUrl;

  /// Called by the course form right after a reel upload / removal so the
  /// hero updates immediately (refresh() re-reads it from the server anyway).
  void setReelUrl(String? url) {
    _reelUrl = (url == null || url.isEmpty) ? null : url;
    notifyListeners();
  }

  Future<TeacherCourse?> refreshCourse() async {
    final result = await run(() => _api.get('/api/v1/courses/${_course.id}'));
    if (result is Map<String, dynamic>) {
      _course = TeacherCourse.fromJson(result);
      final reel = (result['reel_url'] as String?)?.trim();
      _reelUrl = (reel == null || reel.isEmpty) ? null : reel;
      notifyListeners();
      return _course;
    }
    return null;
  }

  // ── Sessions ──────────────────────────────────────────────────────────────

  List<TeacherSessionItem> _sessions = [];

  List<TeacherSessionItem> get sessions => List.unmodifiable(_sessions);

  int get sessionCount => _sessions.length;

  bool get openCourseDetails => !isLoading && sessionCount == 0;

  Future<void> fetchSessions() async {
    final result = await run(
          () => _api.get('/api/v1/courses/${_course.id}/sessions'),
    );
    if (result['items'] is List) {
      _sessions =
      result
          .map(
            (e) => TeacherSessionItem.fromJson(e as Map<String, dynamic>),
      )
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      _materialLoaded.clear();
      _uploadingMaterial.clear();
      print(sessions.length);
      notifyListeners();
    }
  }
  bool openMoreDetailsForAddSession=false;
  void onToggleOpenDetails(){
    openMoreDetailsForAddSession=!openMoreDetailsForAddSession;
    notifyListeners();
  }

  // ── Form submission (create / update session) ────────────────────────────
  // A dedicated flag instead of BaseProvider.isLoading. `isLoading` is
  // flipped by *every* run() call this provider makes — fetching sessions,
  // fetching materials, uploading a file, starting a live session, etc.
  // A widget watching the shared flag for its own submit-button spinner
  // (e.g. SessionFormSheet) would show a spinner triggered by something
  // completely unrelated happening elsewhere on the same screen while the
  // sheet is open (a background refresh, another session's material
  // upload...). This flag is set ONLY around createSession/updateSession.
  bool _submitLoading = false;
  bool get submitLoading => _submitLoading;

  Future<TeacherSessionItem?> createSession({
    required String name,
    required String type,
    String? description,
    String? scheduledAt,
    int durationMinutes = 60,
    int order = 0,
  }) async {
    _submitLoading = true;
    notifyListeners();
    final result = await run(
          () => _api.post(
        '/api/v1/sessions',
        body: {
      'course_id': _course.id,
      'name': name,
      'type': type,
      'description': ?description,
      'scheduled_at': ?scheduledAt,
      'duration_minutes': durationMinutes,
      'order': order,
      },
      ),
      makLoading: false,
    );
    _submitLoading = false;
    if (result is Map<String, dynamic>) {
      final s = TeacherSessionItem.fromJson(result);
      _sessions = [s, ..._sessions]..sort((a, b) => a.order.compareTo(b.order));
      notifyListeners();
      return s;
    }
    notifyListeners();
    return null;
  }

  Future<TeacherSessionItem?> quickSession({
    required int courseId,

  }) async {
    final result = await run(
          () =>
          _api.post(
              '/api/v1/quick_session',
              body: {'course_id': _course.id}),
    );
    if (result is Map<String, dynamic>) {
      final s = TeacherSessionItem.fromJson(result);
      _sessions =
      [s, ..._sessions]..sort((a, b) => a.order.compareTo(b.order));
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
    _submitLoading = true;
    notifyListeners();
    final result = await run(
          () => _api.put(
        '/api/v1/sessions/$sessionId',
        body: {
      'name': ?name,
      'description': ?description,
      'type': ?type,
      'scheduled_at': ?scheduledAt,
      'duration_minutes': ?durationMinutes,
      'order': ?order,
      },
      ),
      makLoading: false,
    );
    _submitLoading = false;
    if (result is Map<String, dynamic>) {
      final updated = TeacherSessionItem.fromJson(result);
      _sessions = _sessions
          .map((s) => s.id == sessionId ? updated : s)
          .toList();
      notifyListeners();
      return updated;
    }
    notifyListeners();
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

  // ── Full refresh (called by pull-to-refresh & post-edit) ──────────────────
  bool loadingAllPage = false;

  Future<void> refresh() async {
    loadingAllPage = true;
    notifyListeners();
    await Future.wait([refreshCourse(), fetchSessions()]);
    loadingAllPage = false;
    notifyListeners();
  }

  // ── Materials ─────────────────────────────────────────────────────────────
  final Map<int, List<SessionMaterialModel>> _materials = {};
  final Map<int, bool> _materialLoaded = {};
  final Map<int, bool> _uploadingMaterial = {};

  Map<int, bool> get materialLoaded => Map.unmodifiable(_materialLoaded);

  List<SessionMaterialModel> materialsFor(int sessionId) =>
      List.unmodifiable(_materials[sessionId] ?? []);

  bool isUploadingMaterial(int sessionId) =>
      _uploadingMaterial[sessionId] ?? false;

  Future<void> fetchMaterials(TeacherSessionItem session) async {
    if ((_materialLoaded[session.id] ?? false) &&
        (_materials[session.id]?.length ?? 0) == session.totalMaterial) {
      return;
    }
    final r = await run(
          () => _api.get('/api/v1/sessions/${session.id}/materials'),
    );
    if (r is List) {
      _materials[session.id] = r
          .map((e) => SessionMaterialModel.fromJson(e as Map<String, dynamic>))
          .toList();
      _materialLoaded[session.id] = true;
      notifyListeners();
    }
  }

  Future<SessionMaterialModel?> uploadFileMaterial({
    required int sessionId,
    required String fileName,
    required String name,
    String? description,
    int order = 0,
    required Uint8List fileBytes,
  }) async {
    _uploadingMaterial[sessionId] = true;
    notifyListeners();
    try {
      final result = await _api.postMultipart(
        '/api/v1/sessions/$sessionId/materials/file',
        fields: {
      'name': name,
      'description': ?description,
      'order': order.toString(),
      },
        fileField: 'file',
        fileName: fileName,
        fileBytes: fileBytes,
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

  Future<SessionMaterialModel?> addLinkMaterial({
    required int sessionId,
    required String name,
    required String url,
    String? description,
    int order = 0,
  }) async {
    final r = await run(
          () => _api.post(
        '/api/v1/sessions/$sessionId/materials/link',
        body: {
      'session_id': sessionId,
      'name': name,
      'url': url,
      'type': 'link',
      'description': ?description,
      'order': order,
      },
      ),
    );
    if (r is Map<String, dynamic>) {
      final mat = SessionMaterialModel.fromJson(r);
      _materials[sessionId] = [...(_materials[sessionId] ?? []), mat]
        ..sort((a, b) => a.order.compareTo(b.order));
      notifyListeners();
      return mat;
    }
    return null;
  }

  Future<bool> updateMaterial(
      int sessionId,
      int materialId, {
        String? name,
        String? description,
        String? url,
        int? order,
      }) async {
    final r = await run(
          () => _api.put(
        '/api/v1/sessions/$sessionId/materials/$materialId',
        body: {
      'name': ?name,
      'description': ?description,
      'url': ?url,
      'order': ?order,
      },
      ),
    );
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

  Future<bool> deleteMaterial(int sessionId, int materialId) async {
    await run(
          () => _api.delete('/api/v1/sessions/$sessionId/materials/$materialId'),
    );
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
  int joinSessionId=-1;
  int startSessionId=-1;
  Future<LiveResponseModel?> startLive(
      int sessionId, {
        bool enableRecording = true,
        int durationHours = 24,
      }) async {
    startSessionId = sessionId;
    notifyListeners();
    final result = await run(
          () => _api.post(
        '/api/v1/live-sessions/start',
        queryParams: {
          'session_id': sessionId,
          'enable_recording': enableRecording,
          'duration_hours': durationHours,
        },
      ),
      makLoading: false,
    );
    startSessionId=-1;
    if (result is Map<String, dynamic>) {
      final live = LiveResponseModel(
        sessionId: sessionId,
        url: result['ws_url'] as String? ?? '',
        token: result['token'] as String? ?? '',
      );
      _updateSessionLiveState(sessionId, isLive: true, roomUrl: live.url);
      return live;
    }
    return null;
  }

  Future<bool> endLive(int sessionId, {bool saveRecording = true}) async {
    startSessionId = sessionId;
    notifyListeners();
    final result = await run(
          () => _api.post(
        '/api/v1/live-sessions/$sessionId/end',
        queryParams: {'save_recording': saveRecording},
      ),
      makLoading: false,
    );
    if (result != null) {
      _updateSessionLiveState(
        sessionId,
        isLive: false,
        roomUrl: null,
        recordingStatus: saveRecording ? 'pending' : null,
      );
      startSessionId=-1;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Navigate to PreJoinPage with the correct JoinArgs.
  ///
  /// The key change vs the original: [apiClient] is now forwarded into
  /// [JoinArgs] so that [RoomPage._ClientRecorder] can authenticate its
  /// chunk-upload POSTs with the teacher's Bearer token.
  Future<void> joinLive(
      BuildContext context,
      int sessionId,
      int courseId,
      int maxParticipants,
      bool liveNow,
      ) async {
    final AuthProvider provider = context.read<AuthProvider>();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PreJoinPage(
          args: JoinArgs(
            isTeacher: provider.isTeacher,
            userId: provider.currentUser?.id ?? -1,
            userName: provider.currentUser?.name ?? '--',
            sessionId: sessionId,
            courseId: courseId,
            maxStudents: maxParticipants,
            // ── Pass the authenticated ApiClient ───────────────────────────
            // _ClientRecorder in RoomPage needs baseUrl + authToken to POST
            // chunks to /api/v1/live-sessions/{id}/recording-chunk.
            apiClient: _api,
            onEnd: () =>
                _confirmEndSession(provider.currentUser, sessionId, context),
            // Teachers start the room; students fetch a personal join token.
            onStart: provider.isTeacher && !liveNow
                ? () => _onStartLive(provider.currentUser, sessionId, context)
                : () => _onJoinLiveAsStudent(sessionId, context),
            // Students: automatically mark live session complete when they leave
            onComplete: provider.isTeacher
                ? null
                : () => markSessionComplete(sessionId),
          ),
        ),
      ),
    );
  }

  Future<void> markMaterialComplete(int sessionId, int materialId) async {
    // Fire-and-forget background signal (called when a student opens a
    // material) — must not flip the shared isLoading, or an unrelated
    // spinner elsewhere on screen could appear because of it.
    await run(
          () => _api.post(
        '/api/v1/sessions/$sessionId/materials/$materialId/complete',
      ),
      makLoading: false,
    );
  }

  Future<void> markSessionComplete(int sessionId) async {
    await run(
          () => _api.post('/api/v1/sessions/$sessionId/complete'),
      makLoading: false,
    );
  }

  Future<String?> fetchRecordingUrl(int sessionId) async {
    final result = await run(
          () => _api.get('/api/v1/live-sessions/$sessionId/recording'),
    );
    if (result is Map<String, dynamic>) {
      final url = result['recording_url'] as String?;
      if (url != null) {
        _sessions = _sessions
            .map(
              (s) => s.id == sessionId
              ? s.copyWith(recordingUrl: url, recordingStatus: 'uploaded')
              : s,
        )
            .toList();
        notifyListeners();
      }
      return url;
    }
    return null;
  }

  void _updateSessionLiveState(
      int sessionId, {
        required bool isLive,
        String? roomUrl,
        String? recordingStatus,
      }) {
    _sessions = _sessions
        .map(
          (s) => s.id == sessionId
          ? s.copyWith(
        isLiveActive: isLive,
        roomUrl: roomUrl,
        recordingStatus: recordingStatus,
      )
          : s,
    )
        .toList();
    notifyListeners();
  }

  /// Called when the teacher taps End Session in the room.
  ///
  /// NOTE: recording is stopped inside RoomPage._endSessionWithRecording
  /// BEFORE onEnd() is called, so by the time we reach here all chunks have
  /// already been uploaded.  This method simply calls endLive() on the server.
  Future<void> _confirmEndSession(
      dynamic user,
      int sessionId,
      BuildContext context,
      ) async {
    await endLive(sessionId);
  }

  Future<LiveResponseModel?> _onStartLive(
      dynamic user,
      int sessionId,
      BuildContext context,
      ) async {
    return await startLive(sessionId);
  }

  /// Student join: GET /api/v1/live-sessions/{sessionId}/join
  Future<LiveResponseModel?> _onJoinLiveAsStudent(
      int sessionId,
      BuildContext context,
      ) async {
    final result = await run(
          () => _api.get('/api/v1/live-sessions/$sessionId/join'),
    );
    if (result is Map<String, dynamic>) {
      return LiveResponseModel(
        sessionId: sessionId,
        url: result['ws_url'] as String? ?? '',
        token: result['token'] as String? ?? '',
      );
    }
    return null;
  }
}