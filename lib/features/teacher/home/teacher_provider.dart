/// shared/teacher_provider.dart
///
/// Endpoints consumed:
///   GET  /api/v1/teacher/dashboard   — stats + courses + schedule
///   POST /api/v1/sessions            — create a new session
///   POST /api/v1/live-sessions/start — start a Daily.co room

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import '../../category/categories_provider.dart';
import 'teacher_models.dart';

class LiveResponseModel {
  final int sessionId;
  final String url;
  final String token;

  LiveResponseModel(
      {required this.sessionId, required this.url, required this.token});

  Map<String, dynamic> get toJson =>
      {'session_id': sessionId, 'url': url, 'token': token};
}

class TeacherProvider extends BaseProvider {
  final ApiClient _api;

  TeacherProvider({ApiClient? api}) : _api = api ?? ApiClient();

  // ── State ─────────────────────────────────────────────────────────────────

  TeacherStats _stats = TeacherStats.empty;
  List<TeacherCourse> _courses = [];
  List<ScheduleSession> _schedule = [];
  bool _initDone = false;

  TeacherStats get stats => _stats;

  List<TeacherCourse> get allCourses => List.unmodifiable(_courses);

  List<ScheduleSession> get schedule => List.unmodifiable(_schedule);

  bool get initDone => _initDone;

  // ── Boot ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    _initDone = false;
    notifyListeners();

    final result = await run(
      () => _api.get('/api/v1/teacher/dashboard'),
    );
    print("############################");
    print(result);
    if (result is Map<String, dynamic>) {
      print("###############----------#############");

      _stats =
          TeacherStats.fromJson(result['stats'] as Map<String, dynamic>? ?? {});

      _courses = (result['courses'] as List? ?? [])
          .map((e) => TeacherCourse.fromJson(e as Map<String, dynamic>))
          .toList();

      _schedule = (result['schedule'] as List? ?? [])
          .map((e) => ScheduleSession.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    _initDone = true;
    notifyListeners();
  }

  // ── Create session then immediately start live ────────────────────────────

  /// Creates a new SessionModel row, then calls Daily.co to open a live room.
  ///
  /// Returns the teacher's personal meeting URL (with owner token) on success,
  /// or null if either step fails.

  Future<int> createSession({
    required int courseId,
    required String name,
    required int durationMinutes,
    String? description,
  }) async {
    // ── Step 1: Create the session ──────────────────────────────────────────
    final sessionResult = await run(() => _api.post(
          '/api/v1/sessions',
          body: {
            'course_id': courseId,
            'name': name,
            'type': 'live',
            'duration_minutes': durationMinutes,
            if (description != null && description.isNotEmpty)
              'description': description,
          },
        ));
    return sessionResult['id'];
  }

  // ── Legacy: start an already-existing session (kept for backward compat) ──

  // ── GET /api/v1/my-courses ────────────────────────────────────────────────────

  Future<void> fetchMyCourses({int skip = 0, int limit = 50}) async {
    final result = await run(() => _api.get(
          '/api/v1/my-courses',
          queryParams: {'skip': skip, 'limit': limit},
        ));
    if (result is Map<String, dynamic>) {
      final items =
          result['items'] as List? ?? result['courses'] as List? ?? [];
      _allCourses = items
          .map((e) => TeacherCourse.fromJson(e as Map<String, dynamic>))
          .toList();
      _updateStats();
      notifyListeners();
    }
  }

  // ── GET /api/v1/courses/{id}  (full detail with child lists) ──────────────────

  Future<TeacherCourse?> fetchCourseDetail(int courseId) async {
    final result = await run(() => _api.get('/api/v1/courses/$courseId'));
    if (result is Map<String, dynamic>) {
      final updated = TeacherCourse.fromJson(result);
      _allCourses =
          _allCourses.map((c) => c.id == courseId ? updated : c).toList();
      notifyListeners();
      return updated;
    }
    return null;
  }

  // ── Filter ────────────────────────────────────────────────────────────────────

  void setFilter(TeacherCourseStatus status) {
    if (_activeFilter == status) return;
    _activeFilter = status;
    notifyListeners();
  }

  // ── POST /api/v1/courses (multipart/form-data) ────────────────────────────────

  Future<TeacherCourse?> createCourse({
    required String title,
    required String type,
    String? description,
    double fees = 0,
    double? totalHours,
    int? categoryId,
    int? maxStudents,
    String? startDate,
    String? endDate,
    File? logoFile,
    bool publishNow = false,
  }) async {
    final fields = <String, String>{
      'name': title,
      'type': type,
      'fees': fees.toString(),
      if (description != null) 'description': description,
      if (categoryId != null) 'category_id': categoryId.toString(),
      if (maxStudents != null) 'max_students': maxStudents.toString(),
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (totalHours != null) 'total_hours': totalHours.toString(),
    };
    print('============================');
    print(logoFile!.path);
    print('============================');

    final result = await run(() => _api.postMultipart(
          '/api/v1/courses',
          fields: fields,
          imageFile: logoFile,
          imageFieldName: 'logo',
        ));

    if (result is Map<String, dynamic>) {
      final created = TeacherCourse.fromJson(result);
      if (publishNow) {
        await _callPublish(created.id);
        final published = created.copyWith(isPublished: true);
        _allCourses = [published, ..._allCourses];
        _updateStats();
        notifyListeners();
        return published;
      }
      _allCourses = [created, ..._allCourses];
      _updateStats();
      notifyListeners();
      return created;
    }
    return null;
  }

  // ── POST /api/v1/courses/{id}/image ──────────────────────────────────────────

  Future<bool> uploadCourseImage(int courseId, File imageFile) async {
    final result = await run(() => _api.uploadImage(
          '/api/v1/courses/$courseId/image',
          file: imageFile,
        ));
    if (result is Map<String, dynamic>) {
      final url = result['image_url'] as String? ??
          result['logo_url'] as String? ??
          result['url'] as String?;
      if (url != null) {
        _allCourses = _allCourses
            .map((c) => c.id == courseId ? c.copyWith(imageUrl: url) : c)
            .toList();
        notifyListeners();
      }
      return true;
    }
    return false;
  }

  // ── PUT /api/v1/courses/{id} ──────────────────────────────────────────────────

  Future<TeacherCourse?> updateCourse(
    int courseId, {
    String? name,
    String? description,
    double? fees,
    String? type,
    int? categoryId,
    double? totalHours,
    int? maxStudents,
    String? startDate,
    String? endDate,
  }) async {
    final result = await run(() => _api.put('/api/v1/courses/$courseId', body: {
          if (name != null) 'name': name,
          if (description != null) 'description': description,
          if (fees != null) 'fees': fees,
          if (type != null) 'type': type,
          if (categoryId != null) 'category_id': categoryId,
          if (totalHours != null) 'total_hours': totalHours,
          if (maxStudents != null) 'max_students': maxStudents,
          if (startDate != null) 'start_date': startDate,
          if (endDate != null) 'end_date': endDate,
        }));
    if (result is Map<String, dynamic>) {
      final updated = TeacherCourse.fromJson(result);
      _allCourses =
          _allCourses.map((c) => c.id == courseId ? updated : c).toList();
      notifyListeners();
      return updated;
    }
    return null;
  }

  // ── Publish / Unpublish ───────────────────────────────────────────────────────

  Future<bool> publishCourse(int courseId) async {
    final ok = await _callPublish(courseId);
    if (ok) _updateLocalPublish(courseId, isPublished: true);
    return ok;
  }

  Future<bool> unpublishCourse(int courseId) async {
    final result =
        await run(() => _api.post('/api/v1/courses/$courseId/unpublish'));
    if (result != null) {
      _updateLocalPublish(courseId, isPublished: false);
      return true;
    }
    return false;
  }

  Future<bool> _callPublish(int courseId) async {
    final result =
        await run(() => _api.post('/api/v1/courses/$courseId/publish'));
    return result != null;
  }

  // ── DELETE /api/v1/courses/{id} ───────────────────────────────────────────────

  Future<bool> deleteCourse(int courseId) async {
    await run(() => _api.delete('/api/v1/courses/$courseId'));
    if (state == ProviderState.success) {
      _allCourses = _allCourses.where((c) => c.id != courseId).toList();
      _updateStats();
      notifyListeners();
      return true;
    }
    return false;
  }

  // ══════════════════════════════════════════════
  //  SCHEDULE
  // ══════════════════════════════════════════════

  /// POST /api/v1/courses/{id}/schedules
  Future<CourseSchedule?> addSchedule(
    int courseId, {
    required String day,
    required String startTime,
    required String endTime,
  }) async {
    final result = await run(() => _api.post(
          '/api/v1/courses/$courseId/schedules',
          body: {'day': day, 'start_time': startTime, 'end_time': endTime},
        ));
    if (result is Map<String, dynamic>) {
      final s = CourseSchedule.fromJson(result);
      _updateCourse(
          courseId,
          (c) => c.copyWith(
                schedules: [...c.schedules, s],
              ));
      return s;
    }
    return null;
  }

  /// DELETE /api/v1/schedules/{scheduleId}
  Future<bool> removeSchedule(int courseId, int scheduleId) async {
    await run(() => _api.delete('/api/v1/schedules/$scheduleId'));
    if (state == ProviderState.success) {
      _updateCourse(
          courseId,
          (c) => c.copyWith(
                schedules:
                    c.schedules.where((s) => s.id != scheduleId).toList(),
              ));
      return true;
    }
    return false;
  }

  // ══════════════════════════════════════════════
  //  CERTIFICATES
  // ══════════════════════════════════════════════

  /// POST /api/v1/courses/{id}/certificates
  Future<CourseCertificate?> addCertificate(
    int courseId, {
    required String title,
    String? description,
  }) async {
    final result = await run(() => _api.post(
          '/api/v1/courses/$courseId/certificates',
          body: {
            'title': title,
            if (description != null) 'description': description,
          },
        ));
    if (result is Map<String, dynamic>) {
      final c = CourseCertificate.fromJson(result);
      _updateCourse(
          courseId,
          (course) => course.copyWith(
                certificates: [...course.certificates, c],
              ));
      return c;
    }
    return null;
  }

  /// DELETE /api/v1/certificates/{certificateId}
  Future<bool> removeCertificate(int courseId, int certificateId) async {
    await run(() => _api.delete('/api/v1/certificates/$certificateId'));
    if (state == ProviderState.success) {
      _updateCourse(
          courseId,
          (c) => c.copyWith(
                certificates:
                    c.certificates.where((x) => x.id != certificateId).toList(),
              ));
      return true;
    }
    return false;
  }

  // ══════════════════════════════════════════════
  //  TOOLS
  // ══════════════════════════════════════════════

  /// POST /api/v1/courses/{id}/tools
  Future<CourseTool?> addTool(
    int courseId, {
    required String name,
    String? description,
  }) async {
    final result = await run(() => _api.post(
          '/api/v1/courses/$courseId/tools',
          body: {
            'title': name,
            if (description != null) 'description': description,
          },
        ));
    if (result is Map<String, dynamic>) {
      final t = CourseTool.fromJson(result);
      _updateCourse(
          courseId,
          (c) => c.copyWith(
                tools: [...c.tools, t],
              ));
      return t;
    }
    return null;
  }

  /// DELETE /api/v1/tools/{toolId}
  Future<bool> removeTool(int courseId, int toolId) async {
    await run(() => _api.delete('/api/v1/tools/$toolId'));
    if (state == ProviderState.success) {
      _updateCourse(
          courseId,
          (c) => c.copyWith(
                tools: c.tools.where((t) => t.id != toolId).toList(),
              ));
      return true;
    }
    return false;
  }

  // ══════════════════════════════════════════════
  //  PREREQUISITES
  // ══════════════════════════════════════════════

  /// POST /api/v1/courses/{id}/prerequisites
  Future<CoursePrerequisite?> addPrerequisite(
    int courseId, {
    required String title,
    String? description,
  }) async {
    final result = await run(() => _api.post(
          '/api/v1/courses/$courseId/prerequisites',
          body: {
            'title': title,
            if (description != null) 'description': description,
          },
        ));
    if (result is Map<String, dynamic>) {
      final p = CoursePrerequisite.fromJson(result);
      _updateCourse(
          courseId,
          (c) => c.copyWith(
                prerequisites: [...c.prerequisites, p],
              ));
      return p;
    }
    return null;
  }

  /// DELETE /api/v1/prerequisites/{prerequisiteId}
  Future<bool> removePrerequisite(int courseId, int prerequisiteId) async {
    await run(() => _api.delete('/api/v1/prerequisites/$prerequisiteId'));
    if (state == ProviderState.success) {
      _updateCourse(
          courseId,
          (c) => c.copyWith(
                prerequisites: c.prerequisites
                    .where((p) => p.id != prerequisiteId)
                    .toList(),
              ));
      return true;
    }
    return false;
  }

  // ── Live sessions ─────────────────────────────────────────────────────────────
  //
  // Future<String?> startLiveSession(
  //     int sessionId, {
  //       bool enableRecording = true,
  //       int durationHours = 24,
  //     }) async {
  //   final result = await run(() => _api.post(
  //     '/api/v1/live-sessions/start',
  //     queryParams: {
  //       'session_id': sessionId,
  //       'enable_recording': enableRecording,
  //       'duration_hours': durationHours,
  //     },
  //   ));
  //   if (result is Map<String, dynamic>) {
  //     return result['meeting_url'] as String? ??
  //         result['room_url'] as String? ??
  //         result['url'] as String?;
  //   }
  //   return null;
  // }

  Future<bool> endLiveSession(int sessionId,
      {bool saveRecording = true}) async {
    final result = await run(() => _api.post(
          '/api/v1/live-sessions/$sessionId/end',
          queryParams: {'save_recording': saveRecording},
        ));
    return result != null;
  }

  // ── Profile image ─────────────────────────────────────────────────────────────

  Future<bool> uploadProfileImage(File imageFile) async {
    final result = await run(
      () => _api.uploadImage('/api/v1/auth/me/image', file: imageFile),
    );
    return result != null;
  }

  // ── Private helpers ───────────────────────────────────────────────────────────

  void _updateLocalPublish(int courseId, {required bool isPublished}) {
    _allCourses = _allCourses
        .map((c) => c.id == courseId ? c.copyWith(isPublished: isPublished) : c)
        .toList();
    notifyListeners();
  }

  /// Apply [update] to a course in the local list and notify.
  void _updateCourse(
      int courseId, TeacherCourse Function(TeacherCourse) update) {
    _allCourses =
        _allCourses.map((c) => c.id == courseId ? update(c) : c).toList();
    notifyListeners();
  }

  void _updateStats() {
    _stats = TeacherStats(
      overallRating: _stats.overallRating,
      totalStudents: _allCourses.fold(0, (s, c) => s + c.studentsCount),
      totalCourses: _allCourses.length,
    );
  }

//   // ── State ────────────────────────────────────────────────────────────────────

  List<TeacherCourse> _allCourses = [];
  TeacherCourseStatus _activeFilter = TeacherCourseStatus.all;
  late List<Map<String, dynamic>> specializations;
  Map<String, dynamic>? selectedTeachingType;
  Map<String, dynamic>? selectedSpecialization;
  List<Map<String, String>> teachingTypes = [
    {'text': 'live'},
    {'text': 'recorded'},
    {'text': 'both'},
  ];

  void onChangeTeachingType(int i, ExpansibleController controller) {
    controller.collapse();
    selectedTeachingType = teachingTypes[i];
    notifyListeners();
  }

  void onChangeSpecialization(int i, ExpansibleController controller) {
    controller.collapse();
    selectedSpecialization = specializations[i];
    notifyListeners();
  }

  Future<void> getCategories(BuildContext context) async {
    specializations =
        await context.read<CategoriesProvider>().getSpecialization();
    notifyListeners();
  }

  // ── Getters ──────────────────────────────────────────────────────────────────

  TeacherCourseStatus get activeFilter => _activeFilter;

  List<TeacherCourse> get filteredCourses => switch (_activeFilter) {
        TeacherCourseStatus.all => _allCourses,
        TeacherCourseStatus.published =>
          _allCourses.where((c) => c.isPublished).toList(),
        TeacherCourseStatus.draft =>
          _allCourses.where((c) => !c.isPublished).toList(),
      };

  /// Returns the locally-cached course or null.
  TeacherCourse? courseById(int id) =>
      _allCourses.where((c) => c.id == id).firstOrNull;

  Future<void> initAddCourse(BuildContext context) async {
    specializations =
        await context.read<CategoriesProvider>().getSpecialization();
    notifyListeners();
  }
}
