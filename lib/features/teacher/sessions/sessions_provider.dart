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
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:provider/provider.dart';

import '../../../../core/api_client.dart';
import '../../../../core/base_provider.dart';
import '../../auth/auth_provider.dart';
import '../../shared/session/material/session_material_model.dart';
import '../../shared/upload/upload_queue_manager.dart';
import '../../student/models.dart';
import '../home/teacher_models.dart';
import 'live/prejoin.dart';
import 'model/live_response_model.dart';

class TeacherCourseScreenProvider extends BaseProvider {
  TeacherCourseScreenProvider({
    required TeacherCourse initialCourse,
    ApiClient? api,
  }) : _api = api ?? ApiClient(),
        _course = initialCourse {
    // Bridge the global upload queue's notifications into this provider's
    // own notifyListeners(), so widgets that already `watch` this provider
    // (e.g. the session card's progress bar) update as a background video
    // upload progresses, without every one of them needing a second watch
    // on UploadQueueManager directly.
    UploadQueueManager.instance.addListener(notifyListeners);
  }

  final ApiClient _api;

  @override
  void dispose() {
    UploadQueueManager.instance.removeListener(notifyListeners);
    super.dispose();
  }

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
    print(result);
    if (result['items'] is List) {
      if ((result['items'] as List).isNotEmpty) {
        _sessions =
        (result['items'] as List)
            .map((e) => TeacherSessionItem.fromJson(e))
            .toList()
          ..sort((a, b) {
            int compareOrder = a.order.compareTo(b.order);
            if (compareOrder == 0) {
              return a.createdAt.compareTo(b.createdAt);
            }
            return compareOrder;
          });
      } else {
        _sessions = [];
      }
      _materialLoaded.clear();
      _uploadingMaterial.clear();
      print(_sessions.length);
      notifyListeners();
    }
  }

  /// Drag-and-drop reorder of the course's sessions (same contract as
  /// [reorderMaterials]: optimistic UI, one request, rollback on failure).
  Future<bool> reorderSessions(int oldIndex, int newIndex) async {
    final list = [..._sessions];
    if (oldIndex < 0 || oldIndex >= list.length) return false;
    if (newIndex > oldIndex) newIndex -= 1; // ReorderableListView semantics
    if (newIndex == oldIndex) return true;

    final previous = _sessions;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _sessions = [
      for (var i = 0; i < list.length; i++) list[i].copyWith(order: i),
    ];
    notifyListeners();

    final r = await run(
          () => _api.put(
        '/api/v1/courses/${_course.id}/reorder-sessions',
        body: {'session_ids': list.map((s) => s.id).toList()},
      ),
      makLoading: false,
    );
    if (r == null) {
      _sessions = previous;
      notifyListeners();
      return false;
    }
    return true;
  }

  bool openMoreDetailsForAddSession = false;

  void onToggleOpenDetails() {
    openMoreDetailsForAddSession = !openMoreDetailsForAddSession;
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

  Future<TeacherSessionItem?> quickSession({required int courseId}) async {
    final result = await run(
          () => _api.post('/api/v1/quick_session', body: {'course_id': _course.id}),
    );
    if (result is Map<String, dynamic>) {
      final s = TeacherSessionItem.fromJson(result);
      _sessions = [s, ..._sessions]..sort((a, b) => a.order.compareTo(b.order));
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
      (_uploadingMaterial[sessionId] ?? false) ||
          UploadQueueManager.instance.isUploadingForSession(sessionId);

  /// 0..1 progress for a background (video) upload on this session, or null
  /// when nothing is uploading via the background queue — the session
  /// card uses this to switch its progress bar from indeterminate (the old
  /// bytes-based image/PDF flow below) to determinate.
  double? uploadProgressForSession(int sessionId) =>
      UploadQueueManager.instance.progressForSession(sessionId);

  Future<void> fetchMaterials(TeacherSessionItem session) async {
    if ((_materialLoaded[session.id] ?? false) &&
        (_materials[session.id]?.length ?? 0) == session.totalMaterial) {
      return;
    }
    final r = await run(
          () => _api.get('/api/v1/sessions/${session.id}/materials'),
    );
    if (r is List) {
      _materials[session.id] =
      r
          .map(
            (e) => SessionMaterialModel.fromJson(e as Map<String, dynamic>),
      )
          .toList()
        ..sort(_byOrder);
      _materialLoaded[session.id] = true;
      notifyListeners();
    }
  }

  /// Uploads STRAIGHT to MinIO (presign → PUT → confirm) instead of routing
  /// the file through this API server — works for every material type
  /// (video / pdf / image / document / anything else), not just video.
  /// Previously this called `_api.postMultipart(.../from-upload, ...)`
  /// directly, but that endpoint only ever accepted a JSON body
  /// ({object_key, name, description, order}); posting multipart form data to
  /// it made FastAPI reject the request with 422 before any of our code ran —
  /// which is why every non-video file (pptx, txt, py, pdf, ...) failed.
  Future<SessionMaterialModel?> uploadFileMaterial({
    required int sessionId,
    required String fileName,
    required String name,
    String? description,
    int order = 0,
    int? durationSeconds,
    required Uint8List fileBytes,
  }) async {
    _uploadingMaterial[sessionId] = true;
    notifyListeners();
    try {
      // 1) Ask the API for a short-lived signed MinIO PUT url for this file.
      final presign = await _api.post(
        '/api/v1/sessions/$sessionId/materials/presign',
        queryParams: {'filename': fileName},
      );
      if (presign is! Map<String, dynamic>) return null;
      final uploadUrl = presign['upload_url'] as String;
      final objectKey = presign['object_key'] as String;
      final contentType =
          presign['content_type'] as String? ?? 'application/octet-stream';

      // 2) PUT the bytes DIRECTLY to MinIO. A bare Dio() on purpose: the
      //    presigned URL's own signature is the only credential MinIO
      //    checks, this isn't our API host, and reusing `_api.dio` would
      //    also run its 401-refresh / device-header interceptors against a
      //    request they were never meant to see.
      try {
        final put = await Dio().put(
          uploadUrl,
          data: fileBytes,
          options: Options(
            contentType: contentType,
            headers: {'Content-Length': fileBytes.length},
          ),
        );
        if (put.statusCode == null || put.statusCode! >= 300) {
          throw ApiException(
            statusCode: put.statusCode ?? 0,
            message: 'تعذر رفع الملف، حاول مرة أخرى',
          );
        }
      } on DioException catch (e) {
        throw ApiException(
          statusCode: e.response?.statusCode ?? 0,
          message: 'تعذر رفع الملف، حاول مرة أخرى',
        );
      }

      // 3) Confirm with the API: it re-verifies the file server-side (real
      //    size / real type straight from MinIO, never trusting what the
      //    client claims) and creates the SessionMaterial row.
      final result = await _api.post(
        '/api/v1/sessions/$sessionId/materials/from-upload',
        body: {
          'object_key': objectKey,
          if (durationSeconds != null) 'duration_seconds': durationSeconds,
          'name': name,
          if (description != null && description.isNotEmpty)
            'description': description,
          'order': order,
        },
      );
      if (result is Map<String, dynamic>) {
        final mat = SessionMaterialModel.fromJson(result);
        _materials[sessionId] = [...(_materials[sessionId] ?? []), mat]
          ..sort((a, b) => a.order.compareTo(b.order));
        _bumpMaterialCount(sessionId, 1);
        notifyListeners();
        return mat;
      }
    } finally {
      _uploadingMaterial[sessionId] = false;
      notifyListeners();
    }
    return null;
  }

  /// Long videos: streams the file straight from disk (never loads the
  /// whole thing into memory) through the app-wide [UploadQueueManager],
  /// so the sheet that started it can close immediately and progress shows
  /// in [UploadProgressFooter] on any screen — not just this one.
  Future<SessionMaterialModel?> uploadFileMaterialInBackground({
    required int sessionId,
    required String filePath,
    required String fileName,
    final Uint8List? bytes,
    required String name,
    String? description,
    int order = 0,
    int? durationSeconds,
  }) async {
    final json = await UploadQueueManager.instance.enqueueFileUpload(
      dio: _api.dio,
      sessionId: sessionId,
      path: filePath,
      bytes: bytes, // null → streamed from disk by the queue
      fileName: fileName,
      endpoint: '/api/v1/sessions/$sessionId/materials/from-upload',
      contentType: _guessVideoContentType(fileName),
      fields: {
        'name': name,
        if (description != null && description.isNotEmpty)
          'description': description,
        'order': order.toString(),
        if (durationSeconds != null) 'duration_seconds': durationSeconds.toString(),
      },
    );
    if (json == null) return null;

    final mat = SessionMaterialModel.fromJson(json);
    _materials[sessionId] = [...(_materials[sessionId] ?? []), mat]
      ..sort((a, b) => a.order.compareTo(b.order));
    _bumpMaterialCount(sessionId, 1);
    notifyListeners();
    return mat;
  }

  MediaType _guessVideoContentType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'mov' => MediaType('video', 'quicktime'),
      'mkv' => MediaType('video', 'x-matroska'),
      'webm' => MediaType('video', 'webm'),
      'avi' => MediaType('video', 'x-msvideo'),
      _ => MediaType('video', 'mp4'),
    };
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
      _bumpMaterialCount(sessionId, 1);
      notifyListeners();
      return mat;
    }
    return null;
  }

  /// Keeps SessionItem.totalMaterial in step with add / delete. Without this
  /// the card's "N materials" chip (hidden while totalMaterial == 0) and the
  /// fetchMaterials() cache check stay stale until the next full refresh.
  /// Caller must notifyListeners().
  void _bumpMaterialCount(int sessionId, int delta) {
    _sessions = _sessions
        .map(
          (s) => s.id == sessionId
          ? s.copyWith(
        totalMaterial: (s.totalMaterial + delta).clamp(0, 1 << 30),
      )
          : s,
    )
        .toList();
  }

  /// order first, then id (stable & matches the backend ORDER BY).
  static int _byOrder(SessionMaterialModel a, SessionMaterialModel b) {
    final c = a.order.compareTo(b.order);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  /// Drag-and-drop reorder. Updates the UI immediately, then persists the
  /// whole new sequence with ONE request; rolls back + refetches on failure.
  Future<bool> reorderMaterials(
      int sessionId,
      int oldIndex,
      int newIndex,
      ) async {
    final list = [...(_materials[sessionId] ?? const <SessionMaterialModel>[])];
    if (oldIndex < 0 || oldIndex >= list.length) return false;
    if (newIndex > oldIndex) newIndex -= 1; // ReorderableListView semantics
    if (newIndex == oldIndex) return true;

    final previous = _materials[sessionId] ?? const <SessionMaterialModel>[];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _materials[sessionId] = [
      for (var i = 0; i < list.length; i++) list[i].copyWith(order: i),
    ];
    notifyListeners();

    final r = await run(
          () => _api.put(
        '/api/v1/sessions/$sessionId/reorder-materials',
        body: {'material_ids': list.map((m) => m.id).toList()},
      ),
      makLoading: false,
    );
    if (r == null) {
      _materials[sessionId] = [...previous];
      notifyListeners();
      return false;
    }
    return true;
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
      // Merge into the existing model: the PUT response carries no
      // completion / rating / requires_play data, so replacing the whole
      // object would wipe them.
      _materials[sessionId] = (_materials[sessionId] ?? [])
          .map(
            (m) => m.id == materialId
            ? m.copyWith(
          name: r['name'] as String? ?? name,
          description: r['description'] as String? ?? description,
          order: (r['order'] as num?)?.toInt() ?? order,
        )
            : m,
      )
          .toList()
        ..sort(_byOrder);
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
      _bumpMaterialCount(sessionId, -1);
      notifyListeners();
      return true;
    }
    return false;
  }

  // ── Live ──────────────────────────────────────────────────────────────────
  int joinSessionId = -1;
  int startSessionId = -1;

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
    startSessionId = -1;
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
      startSessionId = -1;
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