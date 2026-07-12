// ─────────────────────────────────────────────────────────────────────────────
// course_form_provider.dart
//
// Scoped provider — wrap with ChangeNotifierProvider inside the route so it
// is created fresh on push and disposed automatically on pop.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:developer';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import '../../category/categories_provider.dart';
import '../home/teacher_models.dart';
// ─────────────────────────────────────────────────────────────────────────────
// PendingSchedule  — a locally-added weekly appointment for a course that
// doesn't exist on the server yet (CREATE mode). Kept separate from
// [CourseSchedule] so we don't need to know its full constructor shape;
// it's only ever sent to the API via day/startTime/endTime strings.
// ─────────────────────────────────────────────────────────────────────────────

class PendingSchedule {
  final String day;
  final String startTime;
  final String endTime;

  const PendingSchedule({
    required this.day,
    required this.startTime,
    required this.endTime,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// CourseFormState  (immutable value object)
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

  bool get isEmpty =>
      schedules.isEmpty &&
          certificates.isEmpty &&
          tools.isEmpty &&
          prerequisites.isEmpty;
}

// ─────────────────────────────────────────────────────────────────────────────
// CourseFormProvider
// ─────────────────────────────────────────────────────────────────────────────

class CourseFormProvider extends BaseProvider {
  final ApiClient _api;

  CourseFormProvider({ApiClient? api}) : _api = api ?? ApiClient();

  // ── Dropdown state ───────────────────────────────────────────────────────

  List<Map<String, dynamic>> specializations = [];
  Map<String, dynamic>? selectedSpecialization;

  final List<Map<String, String>> teachingTypes = const [
    {'text': 'live'},
    {'text': 'recorded'},
    {'text': 'both'},
  ];
  Map<String, dynamic>? selectedTeachingType;

  // ── Form list state ──────────────────────────────────────────────────────

  CourseFormState _form = const CourseFormState();
  CourseFormState get form => _form;

  /// True when any list (certificates / tools / prerequisites) changed vs
  /// the original course — used to enable the save button independently of
  /// the text fields.
  bool _listsChanged = false;
  bool get listsChanged => _listsChanged;

  /// Weekly appointments added locally while creating a new course (the
  /// course has no id yet, so these can't be POSTed until after creation).
  List<PendingSchedule> _pendingSchedules = [];
  List<PendingSchedule> get pendingSchedules =>
      List.unmodifiable(_pendingSchedules);

  // ─────────────────────────────────────────────────────────────────────────
  // Initialise
  // ─────────────────────────────────────────────────────────────────────────

  /// Call once from initState when opening in CREATE mode.
  Future<void> initCreate(BuildContext context) async {
    _form = const CourseFormState();
    selectedSpecialization = null;
    selectedTeachingType = null;
    _listsChanged = false;
    _pendingSchedules = [];
    notifyListeners();
    await _loadCategories(context);
  }

  /// Call once from initState when opening in UPDATE mode.
  Future<void> initUpdate(BuildContext context, TeacherCourse course) async {
    _form = CourseFormState(
      schedules: List.of(course.schedules),
      certificates: course.certificates.map((e) => e.title).toList(),
      tools: course.tools.map((e) => e.name).toList(),
      prerequisites: course.prerequisites.map((e) => e.title).toList(),
    );
    selectedSpecialization = null;
    selectedTeachingType = null;
    _listsChanged = false;
    _pendingSchedules = [];
    notifyListeners();

    await _loadCategories(context);
    _restoreSpecialization(course);
  }

  Future<void> _loadCategories(BuildContext context) async {
    specializations =
    await context.read<CategoriesProvider>().getSpecialization();
    notifyListeners();
  }

  void _restoreSpecialization(TeacherCourse course) {
    try {
      selectedSpecialization =
          specializations.firstWhere((s) => s['text'] == course.categoryName);
    } catch (_) {
      selectedSpecialization = null;
    }
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Dropdown helpers
  // ─────────────────────────────────────────────────────────────────────────

  void onChangeSpecialization(int i, ExpansibleController ctrl) {
    ctrl.collapse();
    selectedSpecialization = specializations[i];
    _listsChanged = true;
    notifyListeners();
  }

  void onChangeTeachingType(int i, ExpansibleController ctrl) {
    ctrl.collapse();
    selectedTeachingType = teachingTypes[i];
    _listsChanged = true;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // List mutation helpers (certificates / tools / prerequisites)
  // ─────────────────────────────────────────────────────────────────────────

  void addFormCertificate(String title) {
    _form = _form.copyWith(certificates: [..._form.certificates, title]);
    _listsChanged = true;
    notifyListeners();
  }

  void removeFormCertificate(int index) {
    _form = _form.copyWith(
        certificates: List.of(_form.certificates)..removeAt(index));
    _listsChanged = true;
    notifyListeners();
  }

  void addFormTool(String name) {
    _form = _form.copyWith(tools: [..._form.tools, name]);
    _listsChanged = true;
    notifyListeners();
  }

  void removeFormTool(int index) {
    _form =
        _form.copyWith(tools: List.of(_form.tools)..removeAt(index));
    _listsChanged = true;
    notifyListeners();
  }

  void removeFormSchedule(int index) {
    _form = _form.copyWith(
        schedules: List.of(_form.schedules)..removeAt(index));
    _listsChanged = true;
    notifyListeners();
  }

  void addPendingSchedule(PendingSchedule schedule) {
    _pendingSchedules = [..._pendingSchedules, schedule];
    _listsChanged = true;
    notifyListeners();
  }

  void removePendingSchedule(int index) {
    _pendingSchedules = List.of(_pendingSchedules)..removeAt(index);
    _listsChanged = true;
    notifyListeners();
  }

  void addFormPrerequisite(String title) {
    _form = _form.copyWith(prerequisites: [..._form.prerequisites, title]);
    _listsChanged = true;
    notifyListeners();
  }

  void removeFormPrerequisite(int index) {
    _form = _form.copyWith(
        prerequisites: List.of(_form.prerequisites)..removeAt(index));
    _listsChanged = true;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CREATE
  // ─────────────────────────────────────────────────────────────────────────

  Future<TeacherCourse?> submitCreate({
    required String title,
    required String type,
    String? description,
    double fees = 0,
    double? totalHours,
    XFile? logoFile,
    /// When true, the course is published immediately after creation.
    /// When false, it's left as a draft (the server-side default).
    bool publish = false,
  }) async {
    // Step 1: create course record (JSON, no file)
    final result = await run(() => _api.post(
      '/api/v1/courses',
      body: {
        'name': title,
        'type': type,
        'fees': fees,
        if (description != null) 'description': description,
        if (selectedSpecialization?['id'] != null)
          'category_id': selectedSpecialization!['id'],
        if (totalHours != null) 'total_hours': totalHours,
      },
    ));

    if (result is! Map<String, dynamic>) return null;
    TeacherCourse created = TeacherCourse.fromJson(result);

    // Step 2: upload image if provided
    if (logoFile != null) {
      final withImage =
      await _uploadImage(logoFile, courseId: created.id);
      if (withImage != null) created = withImage;
    }

    // Step 3: publish immediately if requested (otherwise stays a draft)
    if (publish) {
      final pubResult = await run(
              () => _api.post('/api/v1/courses/${created.id}/publish'));
      if (pubResult != null) created = created.copyWith(isPublished: true);
    }

    // Step 4: persist extras in parallel
    await Future.wait([
      for (final s in _pendingSchedules)
        _addSchedule(created.id,
            day: s.day, startTime: s.startTime, endTime: s.endTime),
      for (final t in _form.certificates)
        _addCertificate(created.id, title: t),
      for (final t in _form.tools) _addTool(created.id, name: t),
      for (final pr in _form.prerequisites)
        _addPrerequisite(created.id, title: pr),
    ]);

    // Step 5: re-fetch to get full populated course
    final refreshed = await _fetchCourseDetail(created.id) ?? created;
    _pendingSchedules = [];
    return refreshed;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UPDATE
  // ─────────────────────────────────────────────────────────────────────────

  Future<TeacherCourse?> submitUpdate(
      TeacherCourse original, {
        required String name,
        String? description,
        double? fees,
        double? totalHours,
        XFile? logoFile,
      }) async {
    // Step 1: patch scalar fields
    final patchResult = await run(() => _api.put(
      '/api/v1/courses/${original.id}',
      body: {
        'name': name,
        if (description != null) 'description': description,
        if (fees != null) 'fees': fees,
        if (selectedSpecialization?['id'] != null)
          'category_id': selectedSpecialization!['id'],
        if (totalHours != null) 'total_hours': totalHours,
      },
    ));

    if (patchResult is! Map<String, dynamic>) return null;

    // Step 2: diff lists
    final removedScheduleIds = original.schedules
        .where((o) => !_form.schedules.any((f) => f.id == o.id))
        .map((s) => s.id)
        .toList();

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

    // Step 3: apply all changes in parallel
    await Future.wait([
      if (logoFile != null) _uploadImage(logoFile, courseId: original.id),
      for (final id in removedScheduleIds) _removeSchedule(id),
      for (final id in removedCertIds) _removeCertificate(id),
      for (final id in removedToolIds) _removeTool(id),
      for (final id in removedPrereqIds) _removePrerequisite(id),
      for (final s in _pendingSchedules)
        _addSchedule(original.id,
            day: s.day, startTime: s.startTime, endTime: s.endTime),
      for (final t in newCerts) _addCertificate(original.id, title: t),
      for (final t in newTools) _addTool(original.id, name: t),
      for (final pr in newPrereqs) _addPrerequisite(original.id, title: pr),
    ]);

    final refreshed =
        await _fetchCourseDetail(original.id) ?? TeacherCourse.fromJson(patchResult);
    _pendingSchedules = [];
    return refreshed;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private API helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<TeacherCourse?> _fetchCourseDetail(int courseId) async {
    final result = await run(() => _api.get('/api/v1/courses/$courseId'));
    if (result is Map<String, dynamic>) return TeacherCourse.fromJson(result);
    return null;
  }

  Future<TeacherCourse?> _uploadImage(XFile logoFile,
      {required int courseId}) async {
    try {
      final ext =
      p.extension(logoFile.path).replaceFirst('.', '').toLowerCase();
      final mimeType = switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };
      final bytes = await logoFile.readAsBytes();
      final filename = p.basename(logoFile.path).isNotEmpty
          ? p.basename(logoFile.path)
          : 'image.${ext.isEmpty ? 'jpg' : ext}';

      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: MediaType.parse(mimeType),
        ),
      });
      final response = await _api.dio
          .post('/api/v1/courses/$courseId/image', data: formData);
      if (response.statusCode != 200) return null;
      return TeacherCourse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      log('uploadImage ❌ ${e.response?.statusCode}: ${e.response?.data}');
      return null;
    } catch (e) {
      log('uploadImage ❌ unexpected: $e');
      return null;
    }
  }

  Future<void> _addSchedule(int courseId,
      {required String day,
        required String startTime,
        required String endTime}) =>
      run(() => _api.post('/api/v1/courses/$courseId/schedules',
          body: {'day': day, 'start_time': startTime, 'end_time': endTime}));

  Future<void> _removeSchedule(int scheduleId) =>
      run(() => _api.delete('/api/v1/schedules/$scheduleId'));

  Future<void> _addCertificate(int courseId, {required String title}) =>
      run(() => _api.post('/api/v1/courses/$courseId/certificates',
          body: {'title': title}));

  Future<void> _removeCertificate(int certId) =>
      run(() => _api.delete('/api/v1/certificates/$certId'));

  Future<void> _addTool(int courseId, {required String name}) =>
      run(() => _api.post('/api/v1/courses/$courseId/tools',
          body: {'title': name}));

  Future<void> _removeTool(int toolId) =>
      run(() => _api.delete('/api/v1/tools/$toolId'));

  Future<void> _addPrerequisite(int courseId, {required String title}) =>
      run(() => _api.post('/api/v1/courses/$courseId/prerequisites',
          body: {'title': title}));

  Future<void> _removePrerequisite(int prereqId) =>
      run(() => _api.delete('/api/v1/prerequisites/$prereqId'));
}