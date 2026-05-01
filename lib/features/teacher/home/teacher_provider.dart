// ─────────────────────────────────────────────────────────────────────────────
// teacher_provider.dart
//
// Single source of truth for:
//   • Course list state (fetch / publish / delete)
//   • Add-course form state (step 1 + step 2 extras)
//   • Update-course form state (pre-populated from an existing course)
//
// Screens only hold TextEditingControllers (pure UI); every list mutation and
// every API call lives here.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_education_app/features/category/categories_provider.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import '../courses/component/teacher_stats.dart';
import 'teacher_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CourseFormState  —  the mutable form data owned by the provider
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

  /// Clears all lists.
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

  // ── Form state (shared by add & update screens) ───────────────────────────────

  CourseFormState _form = const CourseFormState();
  CourseFormState get form => _form;

  // ── Add-course step tracking ──────────────────────────────────────────────────

  int _addStep = 1;
  int? _createdCourseId;

  int get addStep => _addStep;
  int? get createdCourseId => _createdCourseId;

  // ── Category / teaching-type dropdowns ───────────────────────────────────────

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

  /// Call once when entering the Add-course screen.
  Future<void> initAddCourse(BuildContext context) async {
    // Reset step + form lists
    _addStep = 1;
    _createdCourseId = null;
    _form = const CourseFormState();
    selectedSpecialization = null;
    selectedTeachingType = null;
    notifyListeners();

    await _loadCategories(context);
  }

  /// Call once when entering the Update-course screen.
  Future<void> initUpdateCourse(
      BuildContext context,
      TeacherCourse course,
      ) async {
    // Pre-populate form from existing course data
    _form = CourseFormState(
      schedules: List.of(course.schedules),
      certificates: course.certificates.map((e) => e.title).toList(),
      tools: course.tools.map((e) => e.name).toList(),
      prerequisites: course.prerequisites.map((e) => e.title).toList(),
    );
    selectedSpecialization = null;
    notifyListeners();

    await _loadCategories(context);

    // Restore previously-selected category after categories are loaded
    if (course.categoryName != null) {
      _restoreSpecialization(course);
    }
  }

  Future<void> _loadCategories(BuildContext context) async {
    specializations =
    await context.read<CategoriesProvider>().getSpecialization();
    notifyListeners();
  }

  /// Matches the course's category name against the loaded specialisations list
  /// and sets [selectedSpecialization] so the dropdown shows the right value.
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
    notifyListeners();
  }

  void onChangeTeachingType(int i, ExpansibleController ctrl) {
    ctrl.collapse();
    selectedTeachingType = teachingTypes[i];
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Form list mutations  (used by both add and update screens)
  // ─────────────────────────────────────────────────────────────────────────────

  void addFormSchedule(String day, String startTime, String endTime) {
    _form = _form.copyWith(
      schedules: [
        ..._form.schedules,
        CourseSchedule.pending(
            day: day, startTime: startTime, endTime: endTime),
      ],
    );
    notifyListeners();
  }

  void removeFormSchedule(int index) {
    final updated = List<CourseSchedule>.of(_form.schedules)..removeAt(index);
    _form = _form.copyWith(schedules: updated);
    notifyListeners();
  }

  void addFormCertificate(String title) {
    _form = _form.copyWith(certificates: [..._form.certificates, title]);
    notifyListeners();
  }

  void removeFormCertificate(int index) {
    final updated = List<String>.of(_form.certificates)..removeAt(index);
    _form = _form.copyWith(certificates: updated);
    notifyListeners();
  }

  void addFormTool(String name) {
    _form = _form.copyWith(tools: [..._form.tools, name]);
    notifyListeners();
  }

  void removeFormTool(int index) {
    final updated = List<String>.of(_form.tools)..removeAt(index);
    _form = _form.copyWith(tools: updated);
    notifyListeners();
  }

  void addFormPrerequisite(String title) {
    _form = _form.copyWith(prerequisites: [..._form.prerequisites, title]);
    notifyListeners();
  }

  void removeFormPrerequisite(int index) {
    final updated = List<String>.of(_form.prerequisites)..removeAt(index);
    _form = _form.copyWith(prerequisites: updated);
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Add-course step 1  —  create the course record
  // ─────────────────────────────────────────────────────────────────────────────

  /// Returns the created [TeacherCourse] on success, null on failure.
  /// Automatically advances [addStep] to 2 on success.
  Future<TeacherCourse?> submitAddCourseStep1({
    required String title,
    required String type,
    String? description,
    double fees = 0,
    double? totalHours,
    int? maxStudents,
    File? logoFile,
    bool publishNow = false,
  }) async {
    final fields = <String, String>{
      'name': title,
      'type': type,
      'fees': fees.toString(),
      if (description != null) 'description': description,
      if (selectedSpecialization?['id'] != null)
        'category_id': selectedSpecialization!['id'].toString(),
      if (maxStudents != null) 'max_students': maxStudents.toString(),
      if (totalHours != null) 'total_hours': totalHours.toString(),
    };

    final result = await run(() => _api.postMultipart(
      '/api/v1/courses',
      fields: fields,
      imageFile: logoFile,
      imageFieldName: 'logo',
    ));

    if (result is! Map<String, dynamic>) return null;

    TeacherCourse created = TeacherCourse.fromJson(result);

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

  /// Fires all pending extras as concurrent API calls.
  /// Returns true when all calls succeed (individual failures are silent —
  /// the same behaviour as the original code).
  Future<bool> submitAddCourseStep2() async {
    final id = _createdCourseId;
    if (id == null) return false;

    await Future.wait([
      for (final s in _form.schedules)
        addSchedule(id, day: s.day, startTime: s.startTime, endTime: s.endTime),
      for (final t in _form.certificates) addCertificate(id, title: t),
      for (final t in _form.tools) addTool(id, name: t),
      for (final p in _form.prerequisites) addPrerequisite(id, title: p),
    ]);

    // Clean up form state
    _form = const CourseFormState();
    _addStep = 1;
    _createdCourseId = null;
    notifyListeners();
    return true;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Update-course  —  single submit that patches basic fields + syncs extras
  // ─────────────────────────────────────────────────────────────────────────────

  /// Patches the course basic fields, then concurrently:
  ///   • Removes extras that were deleted in the form
  ///   • Adds extras that are new (id == -1)
  ///
  /// Returns the updated [TeacherCourse] on success, null on failure.
  Future<TeacherCourse?> submitUpdateCourse(
      TeacherCourse original, {
        required String name,
        String? description,
        double? fees,
        double? totalHours,
      }) async {
    // 1. Patch basic fields
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

    // 2. Sync extras concurrently ─────────────────────────────────────────────
    //
    // Strategy:
    //   • Schedules with id == -1 are new → POST
    //   • Original schedules whose id is NOT in the form list → DELETE
    //   • Same logic for certificates, tools, prerequisites

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
        .map((p) => p.id)
        .toList();

    final newPrereqs = _form.prerequisites
        .where((t) => !original.prerequisites.any((o) => o.title == t))
        .toList();

    await Future.wait([
      // Removes
      for (final id in removedScheduleIds) removeSchedule(original.id, id),
      for (final id in removedCertIds) removeCertificate(original.id, id),
      for (final id in removedToolIds) removeTool(original.id, id),
      for (final id in removedPrereqIds) removePrerequisite(original.id, id),
      // Adds
      for (final s in newSchedules)
        addSchedule(original.id,
            day: s.day, startTime: s.startTime, endTime: s.endTime),
      for (final t in newCerts) addCertificate(original.id, title: t),
      for (final t in newTools) addTool(original.id, name: t),
      for (final p in newPrereqs) addPrerequisite(original.id, title: p),
    ]);

    // 3. Refresh full course from API so local cache is accurate
    final refreshed = await fetchCourseDetail(original.id);
    updated = refreshed ?? updated;

    // Clean up form state
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
  Future<int> createSession(
      {required int courseId,
        required String name,
        required int durationMinutes,
        String? description}) async {
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
  // Course-image upload
  // ─────────────────────────────────────────────────────────────────────────────

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
        _mutateCourse(courseId, (c) => c.copyWith(imageUrl: url));
      }
      return true;
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Extras CRUD  (also used internally by submitAddCourseStep2 / submitUpdateCourse)
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
      _mutateCourse(courseId,
              (course) => course.copyWith(certificates: [...course.certificates, c]));
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
              certificates: c.certificates
                  .where((x) => x.id != certificateId)
                  .toList()));
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
      _mutateCourse(
          courseId, (c) => c.copyWith(tools: [...c.tools, t]));
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
      final p = CoursePrerequisite.fromJson(result);
      _mutateCourse(courseId,
              (c) => c.copyWith(prerequisites: [...c.prerequisites, p]));
      return p;
    }
    return null;
  }

  Future<bool> removePrerequisite(int courseId, int prerequisiteId) async {
    await run(() => _api.delete('/api/v1/prerequisites/$prerequisiteId'));
    if (state == ProviderState.success) {
      _mutateCourse(
          courseId,
              (c) => c.copyWith(
              prerequisites: c.prerequisites
                  .where((p) => p.id != prerequisiteId)
                  .toList()));
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

  Future<bool> endLiveSession(int sessionId, {bool saveRecording = true}) async {
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
    _allCourses =
        _allCourses.map((c) => c.id == courseId ? fn(c) : c).toList();
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