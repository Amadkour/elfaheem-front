// ─────────────────────────────────────────────────────────────────────────────
// teacher_provider.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/features/category/categories_provider.dart';
import 'package:http/http.dart' hide MultipartFile;
import 'package:provider/provider.dart';
import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart' as dio;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import '../courses/component/teacher_stats.dart';
import 'teacher_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CourseFormState
// ─────────────────────────────────────────────────────────────────────────────

class CourseFormState {
  final List<CourseSchedule> schedules;
  final List<String> certificates;
  final List<String> tools;
  final List<String> prerequisites;

  const CourseFormState({
    this.schedules = const [],
    this.certificates = const [],
    this.tools = const [],
    this.prerequisites = const [],
  });

  CourseFormState copyWith({
    List<CourseSchedule>? schedules,
    List<String>? certificates,
    List<String>? tools,
    List<String>? prerequisites,
  }) =>
      CourseFormState(
        schedules: schedules ?? this.schedules,
        certificates: certificates ?? this.certificates,
        tools: tools ?? this.tools,
        prerequisites: prerequisites ?? this.prerequisites,
      );

  CourseFormState cleared() => const CourseFormState(
    schedules: [],
    certificates: [],
    tools: [],
    prerequisites: [],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TeacherProvider
// ─────────────────────────────────────────────────────────────────────────────

class TeacherProvider extends BaseProvider {
  final ApiClient _api;

  TeacherProvider({ApiClient? api}) : _api = api ?? ApiClient();

  // ── Course list state ────────────────────────────────────────────────────────
  bool  changeLists=false;
  TeacherStats _stats = const TeacherStats();
  List<TeacherCourse> _allCourses = [];
  List<ScheduleSession> _schedule = [];
  TeacherCourseStatus _activeFilter = TeacherCourseStatus.all;

  TeacherStats get stats => _stats;
  TeacherCourseStatus get activeFilter => _activeFilter;
  List<TeacherCourse> get allCourses => List.unmodifiable(_allCourses);
  List<ScheduleSession> get schedule => List.unmodifiable(_schedule);

  List<TeacherCourse> get filteredCourses => switch (_activeFilter) {
    TeacherCourseStatus.all => _allCourses,
    TeacherCourseStatus.published =>
        _allCourses.where((c) => c.isPublished).toList(),
    TeacherCourseStatus.draft =>
        _allCourses.where((c) => !c.isPublished).toList(),
  };

  TeacherCourse? courseById(int id) =>
      _allCourses.where((c) => c.id == id).firstOrNull;

  // ── Form state ───────────────────────────────────────────────────────────────

  CourseFormState _form = const CourseFormState();
  CourseFormState get form => _form;

  // ── Add-course step tracking ─────────────────────────────────────────────────

  int _addStep = 1;
  int? _createdCourseId;

  int get addStep => _addStep;
  int? get createdCourseId => _createdCourseId;

  // ── Dropdowns ────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> specializations = [];
  Map<String, dynamic>? selectedSpecialization;

  List<Map<String, String>> teachingTypes = [
    {'text': 'live'},
    {'text': 'recorded'},
    {'text': 'both'},
  ];
  Map<String, dynamic>? selectedTeachingType;

  // ─────────────────────────────────────────────────────────────────────────────
  // Form initialisation
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> initAddCourse(BuildContext context) async {
    _addStep = 1;
    _createdCourseId = null;
    _form = const CourseFormState();
    selectedSpecialization = null;
    selectedTeachingType = null;
    notifyListeners();
    await _loadCategories(context);
  }

  Future<void> initUpdateCourse(
      BuildContext context,
      TeacherCourse course,
      ) async {
    _form = CourseFormState(
      schedules: List.of(course.schedules),
      certificates: course.certificates.map((e) => e.title).toList(),
      tools: course.tools.map((e) => e.name).toList(),
      prerequisites: course.prerequisites.map((e) => e.title).toList(),
    );
    selectedSpecialization = null;
    notifyListeners();

    await _loadCategories(context);

    if (course.categoryName != null) {
      _restoreSpecialization(course);
    }
  }

  Future<void> _loadCategories(BuildContext context) async {
    specializations =
    await context.read<CategoriesProvider>().getSpecialization();
    notifyListeners();
  }

  void _restoreSpecialization(TeacherCourse course) {
    try {
      selectedSpecialization = specializations.firstWhere(
            (s) => s['text'] == course.categoryName,
      );
    } catch (_) {
      selectedSpecialization = null;
    }
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Dropdown helpers
  // ─────────────────────────────────────────────────────────────────────────────

  void onChangeSpecialization(int i, ExpansibleController ctrl) {
    ctrl.collapse();
    selectedSpecialization = specializations[i];
    changeLists=true;
    notifyListeners();
  }

  void onChangeTeachingType(int i, ExpansibleController ctrl) {
    ctrl.collapse();
    changeLists=true;
    selectedTeachingType = teachingTypes[i];
    notifyListeners();
  }


  void addFormCertificate(String title) {
    _form = _form.copyWith(certificates: [..._form.certificates, title]);
    changeLists=true;
    notifyListeners();
  }

  void removeFormCertificate(int index) {
    final updated = List<String>.of(_form.certificates)..removeAt(index);
    _form = _form.copyWith(certificates: updated);
    changeLists=true;

    notifyListeners();
  }

  void addFormTool(String name) {
    _form = _form.copyWith(tools: [..._form.tools, name]);
    changeLists=true;
    notifyListeners();
  }

  void removeFormTool(int index) {
    final updated = List<String>.of(_form.tools)..removeAt(index);
    _form = _form.copyWith(tools: updated);
    changeLists=true;
    notifyListeners();
  }

  void addFormPrerequisite(String title) {
    _form = _form.copyWith(prerequisites: [..._form.prerequisites, title]);
    changeLists=true;
    notifyListeners();
  }

  void removeFormPrerequisite(int index) {
    final updated = List<String>.of(_form.prerequisites)..removeAt(index);
    _form = _form.copyWith(prerequisites: updated);
    changeLists=true;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Add-course step 1  —  create the course record THEN upload image separately
  // ─────────────────────────────────────────────────────────────────────────────

  Future<TeacherCourse?> submitAddCourseStep1({
    required String title,
    required String type,
    String? description,
    double fees = 0,
    double? totalHours,
    int? maxStudents,
    XFile? logoFile,
    bool publishNow = false,
  }) async {
    // FIX: POST /courses with JSON only — no multipart here.
    // The API /courses endpoint accepts a CourseBase JSON body, NOT a file.
    // Image is uploaded separately via POST /courses/{id}/image.
    final result = await run(() => _api.post(
      '/api/v1/courses',
      body: {
        'name': title,
        'type': type,
        'fees': fees,
        if (description != null) 'description': description,
        if (selectedSpecialization?['id'] != null)
          'category_id': selectedSpecialization!['id'],
        if (maxStudents != null) 'max_students': maxStudents,
        if (totalHours != null) 'total_hours': totalHours,
      },
    ));

    if (result is! Map<String, dynamic>) return null;

    TeacherCourse created = TeacherCourse.fromJson(result);

    // FIX: Upload image AFTER course is created using the correct endpoint
    if (logoFile != null) {
      final withImage =
      await uploadCourseImage(logoFile, courseId: created.id);
      if (withImage != null) created = withImage;
    }

    if (publishNow) {
      await _callPublish(created.id);
      created = created.copyWith(isPublished: true);
    }

    _allCourses = [created, ..._allCourses];
    _updateStats();
    _createdCourseId = created.id;
    _addStep = 2;
    notifyListeners();
    return created;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Add-course step 2  —  persist extras concurrently
  // ─────────────────────────────────────────────────────────────────────────────

  Future<bool> submitAddCourseStep2() async {
    final id = _createdCourseId;
    if (id == null) return false;

    await Future.wait([
      for (final s in _form.schedules)
        addSchedule(id, day: s.day, startTime: s.startTime, endTime: s.endTime),
      for (final t in _form.certificates) addCertificate(id, title: t),
      for (final t in _form.tools) addTool(id, name: t),
      for (final pr in _form.prerequisites) addPrerequisite(id, title: pr),
    ]);

    _form = const CourseFormState();
    _addStep = 1;
    _createdCourseId = null;
    notifyListeners();
    return true;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Update-course
  // ─────────────────────────────────────────────────────────────────────────────

  Future<TeacherCourse?> submitUpdateCourse(
      TeacherCourse original, {
        required String name,
        String? description,
        double? fees,
        double? totalHours,
        XFile? logoFile, // deferred image — uploaded together with all other changes
      }) async {
    final patchResult =
    await run(() => _api.put('/api/v1/courses/${original.id}', body: {
      'name': name,
      if (description != null) 'description': description,
      if (fees != null) 'fees': fees,
      if (selectedSpecialization?['id'] != null)
        'category_id': selectedSpecialization!['id'],
      if (totalHours != null) 'total_hours': totalHours,
    }));

    if (patchResult is! Map<String, dynamic>) return null;

    TeacherCourse updated = TeacherCourse.fromJson(patchResult);

    final removedScheduleIds = original.schedules
        .where((o) => !_form.schedules.any((f) => f.id == o.id))
        .map((s) => s.id)
        .toList();
    final newSchedules = _form.schedules.where((s) => s.id == -1).toList();

    final removedCertIds = original.certificates
        .where((o) => !_form.certificates.contains(o.title))
        .map((c) => c.id)
        .toList();
    final newCerts = _form.certificates
        .where((t) => !original.certificates.any((o) => o.title == t))
        .toList();

    final removedToolIds = original.tools
        .where((o) => !_form.tools.contains(o.name))
        .map((t) => t.id)
        .toList();
    final newTools = _form.tools
        .where((n) => !original.tools.any((o) => o.name == n))
        .toList();

    final removedPrereqIds = original.prerequisites
        .where((o) => !_form.prerequisites.contains(o.title))
        .map((pr) => pr.id)
        .toList();
    final newPrereqs = _form.prerequisites
        .where((t) => !original.prerequisites.any((o) => o.title == t))
        .toList();

    await Future.wait([
      if (logoFile != null) uploadCourseImage(logoFile, courseId: original.id),
      for (final id in removedScheduleIds) removeSchedule(original.id, id),
      for (final id in removedCertIds) removeCertificate(original.id, id),
      for (final id in removedToolIds) removeTool(original.id, id),
      for (final id in removedPrereqIds) removePrerequisite(original.id, id),
      for (final s in newSchedules)
        addSchedule(original.id,
            day: s.day, startTime: s.startTime, endTime: s.endTime),
      for (final t in newCerts) addCertificate(original.id, title: t),
      for (final t in newTools) addTool(original.id, name: t),
      for (final pr in newPrereqs) addPrerequisite(original.id, title: pr),
    ]);

    final refreshed = await fetchCourseDetail(original.id);
    updated = refreshed ?? updated;

    _form = const CourseFormState();
    notifyListeners();
    return updated;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Dashboard / course list
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> init() async => _fetchDashboard();

  Future<void> _fetchDashboard() async {
    final result = await run(() => _api.get('/api/v1/teacher/dashboard'));
    if (result is Map<String, dynamic>) {
      final data = TeacherDashboardData.fromJson(result);
      _stats = data.stats;
      _allCourses = data.courses;
      _schedule = data.schedule;
      notifyListeners();
    }
  }

  Future<int> createSession({
    required int courseId,
    required String name,
    required int durationMinutes,
    String? description,
  }) async {
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

  void setFilter(TeacherCourseStatus status) {
    if (_activeFilter == status) return;
    _activeFilter = status;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Publish / Unpublish / Delete
  // ─────────────────────────────────────────────────────────────────────────────

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

  // ─────────────────────────────────────────────────────────────────────────────
  // Course-image upload — POST /api/v1/courses/{id}/image
  //
  // FIX 1: Use _api's baseUrl via _api.buildUri() so the host is never missing.
  // FIX 2: Use readAsBytes() + MultipartFile.fromBytes() for Web compatibility.
  // FIX 3: Copy auth headers from the existing _api client.
  // ─────────────────────────────────────────────────────────────────────────────

  // Called from update_screen with just XFile (no courseId yet known there).
  // Also called internally from submitAddCourseStep1 with courseId + XFile?.
  Future<TeacherCourse?> uploadCourseImage(XFile logoFile, {int? courseId}) async {
    final id = courseId ?? _createdCourseId;
    if (id == null) return null;

    try {
      final ext =
      p.extension(logoFile.path).replaceFirst('.', '').toLowerCase();
      final mimeType = switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };

      // ── Read bytes — works on Web AND mobile ────────────────────────────────
      final bytes = await logoFile.readAsBytes();
      final filename = p.basename(logoFile.path).isNotEmpty
          ? p.basename(logoFile.path)
          : 'image.${ext.isEmpty ? 'jpg' : ext}';

      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,                      // FastAPI requires a filename
          contentType: MediaType.parse(mimeType),
        ),
      });

      // FIX: Use _api's own Dio instance (has baseUrl + auth headers already).
      // _api.dio is the internal Dio instance — adjust the getter name to match
      // whatever your ApiClient exposes (commonly .dio or .client).
      final response = await _api.dio.post(
        '/api/v1/courses/$id/image',
        data: formData,
        // ⚠️ Do NOT set Content-Type here — Dio sets it with boundary automatically
      );

      log('uploadCourseImage ✅ status=${response.statusCode}');
      log('uploadCourseImage body=${response.data}');

      if (response.statusCode != 200) return null;
      return TeacherCourse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      log('uploadCourseImage ❌ ${e.response?.statusCode}: ${e.response?.data}');
      return null;
    } catch (e) {
      log('uploadCourseImage ❌ unexpected: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Extras CRUD
  // ─────────────────────────────────────────────────────────────────────────────

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
      _mutateCourse(
          courseId, (c) => c.copyWith(schedules: [...c.schedules, s]));
      return s;
    }
    return null;
  }

  Future<bool> removeSchedule(int courseId, int scheduleId) async {
    await run(() => _api.delete('/api/v1/schedules/$scheduleId'));
    if (state == ProviderState.success) {
      _mutateCourse(
          courseId,
              (c) => c.copyWith(
              schedules: c.schedules.where((s) => s.id != scheduleId).toList()));
      return true;
    }
    return false;
  }

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
      _mutateCourse(
          courseId,
              (course) =>
              course.copyWith(certificates: [...course.certificates, c]));
      return c;
    }
    return null;
  }

  Future<bool> removeCertificate(int courseId, int certificateId) async {
    await run(() => _api.delete('/api/v1/certificates/$certificateId'));
    if (state == ProviderState.success) {
      _mutateCourse(
          courseId,
              (c) => c.copyWith(
              certificates:
              c.certificates.where((x) => x.id != certificateId).toList()));
      return true;
    }
    return false;
  }

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
      _mutateCourse(courseId, (c) => c.copyWith(tools: [...c.tools, t]));
      return t;
    }
    return null;
  }

  Future<bool> removeTool(int courseId, int toolId) async {
    await run(() => _api.delete('/api/v1/tools/$toolId'));
    if (state == ProviderState.success) {
      _mutateCourse(
          courseId,
              (c) =>
              c.copyWith(tools: c.tools.where((t) => t.id != toolId).toList()));
      return true;
    }
    return false;
  }

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
      final pr = CoursePrerequisite.fromJson(result);
      _mutateCourse(
          courseId,
              (c) => c.copyWith(prerequisites: [...c.prerequisites, pr]));
      return pr;
    }
    return null;
  }

  Future<bool> removePrerequisite(int courseId, int prerequisiteId) async {
    await run(() => _api.delete('/api/v1/prerequisites/$prerequisiteId'));
    if (state == ProviderState.success) {
      _mutateCourse(
          courseId,
              (c) => c.copyWith(
              prerequisites:
              c.prerequisites.where((pr) => pr.id != prerequisiteId).toList()));
      return true;
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Live-session helpers
  // ─────────────────────────────────────────────────────────────────────────────

  Future<String?> startLiveSession(
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
      return result['meeting_url'] as String? ??
          result['room_url'] as String? ??
          result['url'] as String?;
    }
    return null;
  }

  Future<bool> endLiveSession(int sessionId,
      {bool saveRecording = true}) async {
    final result = await run(() => _api.post(
      '/api/v1/live-sessions/$sessionId/end',
      queryParams: {'save_recording': saveRecording},
    ));
    return result != null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────────

  void _mutateCourse(int courseId, TeacherCourse Function(TeacherCourse) fn) {
    _allCourses = _allCourses.map((c) => c.id == courseId ? fn(c) : c).toList();
    notifyListeners();
  }

  void _updateLocalPublish(int courseId, {required bool isPublished}) =>
      _mutateCourse(courseId, (c) => c.copyWith(isPublished: isPublished));

  void _updateStats() {
    _stats = _stats.copyWith(
      totalStudents: _allCourses.fold(0, (s, c) => (s!) + c.studentsCount),
      totalCourses: _allCourses.length,
    );
  }
}