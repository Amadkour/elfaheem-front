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
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';
import 'package:flutter_education_app/features/courses/course_scope.dart' show modeCourseScopeQuery;
import 'package:flutter_education_app/features/courses/category/categories_provider.dart';
import 'package:flutter_education_app/features/home/student/models.dart'
    show AppCurrency, AppCurrencyX, CourseStatus, CourseStatusX;
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart' show RoadmapDraft;
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/features/courses/course_setup.dart';

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
  }) => CourseFormState(
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

  // ── Default plan students see first: 0 yearly · 1 six months · 2 monthly ──
  int defaultPlanIndex = 0;

  void onChangeDefaultPlan(int index) {
    defaultPlanIndex = index;
    notifyListeners();
  }

  // ── Currency state ───────────────────────────────────────────────────────
  // Defaults to EGP; restored from the course's own currency in UPDATE mode.
  AppCurrency selectedCurrency = AppCurrency.egp;

  void onChangeCurrency(AppCurrency currency) {
    selectedCurrency = currency;
    _listsChanged = true;
    notifyListeners();
  }

  // ── Next courses (ORDERED roadmap) / recommended courses ─────────────────
  // Populated from the teacher's own other courses (GET /my-courses), since
  // both fields may only reference courses this teacher owns.

  List<Map<String, dynamic>> otherCourses = [];

  /// Ordered — index 0 is step 1 of the roadmap, index 1 is step 2, etc.
  List<Map<String, dynamic>> selectedNextCourses = [];

  /// The course's level and topic words (D-120): content signals of the recommendations.
  String? level;
  List<String> tags = [];

  /// Editing a personal course of a personal account: its next courses live in the course's Path tab, so the
  /// form neither shows nor sends them (a save would undo what the Path tab changed meanwhile).
  bool nextCoursesInPath = false;

  void setLevel(String? value) {
    level = value;
    notifyListeners();
  }

  /// Adds a topic word (same rules as the Path editor); false when nothing was added.
  bool addTag(String raw) {
    final d = RoadmapDraft(tags: tags);
    if (!d.addTag(raw)) return false;
    tags = d.tags;
    notifyListeners();
    return true;
  }

  void removeTag(String tag) {
    tags = [...tags]..remove(tag);
    notifyListeners();
  }

  /// The Path editor saved the course's level / topic words meanwhile: the form takes them over, so its own save
  /// does not undo them.
  void applyRoadmap(String? newLevel, List<String> newTags) {
    level = newLevel;
    tags = [...newTags];
    notifyListeners();
  }
  Set<int> selectedRecommendedCourseIds = {};

  // ── Who it's for / Where (D-1314) ────────────────────────────────────────
  List<CourseTarget> targets = [];
  int? subjectId;

  /// online | in_person | both.
  String deliveryMode = 'online';
  EduArea? area1, area2;
  String address = '';
  String? countryCode;
  EduCountryCatalog? eduCatalog;

  /// The server refused a save for want of an area (`course_area_required`).
  bool areaMissing = false;

  /// An edit session sends the setup fields only after the course's own detail filled them in, so a list answer that
  /// carries no targets can never wipe the stored ones (the targets list replaces the old one).
  bool _setupReady = true;
  bool _setupDirty = false;
  bool get setupDirty => _setupDirty;

  void _setupTouch() {
    _setupDirty = true;
    areaMissing = false;
    notifyListeners();
  }

  void toggleTarget(CourseTarget t) {
    targets = targets.contains(t) ? ([...targets]..remove(t)) : [...targets, t];
    _setupTouch();
  }

  void setSubject(int? id) {
    subjectId = id;
    _setupTouch();
  }

  void setDeliveryMode(String mode) {
    deliveryMode = mode;
    _setupTouch();
  }

  void setArea(EduArea l1, EduArea? l2) {
    area1 = l1;
    area2 = l2;
    _setupTouch();
  }

  void setAddress(String v) {
    if (v == address) return;
    address = v;
    _setupDirty = true;
  }

  Future<List<EduArea>> loadAreas(int? parentId) => EduCatalog.instance.areas(countryCode ?? 'EG', parentId: parentId);

  /// Marks the save as refused for want of an area (the form shows the bilingual text under the area tile).
  void markAreaMissing() {
    areaMissing = true;
    notifyListeners();
  }

  /// The setup fields of a create / update body. An edit session that has not loaded the course's detail yet sends
  /// nothing (see [_setupReady]). An update always sends every field, so a cleared one really clears.
  Map<String, dynamic> _setupBody({required bool update}) {
    if (!_setupReady) return const {};
    final inPerson = deliveryMode != 'online';
    final area = inPerson ? (area2 ?? area1) : null;
    final addr = inPerson && address.trim().isNotEmpty ? address.trim() : null;
    return {
      'country_code': ?countryCode,
      'delivery_mode': deliveryMode,
      if (update || subjectId != null) 'subject_id': subjectId,
      if (update || area != null) 'area_id': area?.id,
      if (update || addr != null) 'address': addr,
      'targets': [for (final t in targets) t.toJson()],
    };
  }

  /// The platform country: the course's own, else the first country the server lists, else Egypt. Then the catalog.
  Future<void> _loadSetupCatalog(CourseSetup? setup) async {
    var country = setup?.countryCode;
    if (country == null || country.isEmpty) {
      try {
        final r = await _api.get('/api/v1/edu/countries', auth: false);
        if (r is List && r.isNotEmpty && r.first is Map) country = '${(r.first as Map)['code'] ?? ''}'.toUpperCase();
      } catch (_) {}
    }
    countryCode = (country == null || country.isEmpty) ? 'EG' : country;
    eduCatalog = await EduCatalog.instance.load(countryCode!);
    notifyListeners();
  }

  void _applySetup(CourseSetup s) {
    targets = [...s.targets];
    subjectId = s.subject?.id;
    deliveryMode = s.deliveryMode;
    countryCode = s.countryCode ?? countryCode;
    final a = s.area;
    if (a == null) {
      area1 = area2 = null;
    } else {
      final p = a.parent;
      EduArea mk(CourseNamed n, int level) =>
          EduArea(id: n.id, key: '', nameAr: n.nameAr, nameEn: n.nameEn, level: level, hasChildren: false);
      area1 = mk(p ?? a, 1);
      area2 = p == null ? null : mk(a, 2);
    }
    address = s.address ?? '';
  }

  /// The edit form's own detail call fills the setup (the list answer may not carry targets).
  Future<void> _loadSetupFor(TeacherCourse course) async {
    _setupReady = false;
    _applySetup(course.setup);
    await _loadSetupCatalog(course.setup);
    try {
      final r = await _api.get('/api/v1/courses/${course.id}');
      if (r is Map<String, dynamic>) {
        _applySetup(CourseSetup.fromJson(r));
        _setupReady = true;
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Options not already chosen as a next-course step (so the picker
  /// doesn't offer the same course twice).
  List<Map<String, dynamic>> get availableNextCourseOptions {
    final chosen = selectedNextCourses.map((c) => c['id']).toSet();
    return otherCourses.where((c) => !chosen.contains(c['id'])).toList();
  }

  void addNextCourse(Map<String, dynamic> course) {
    selectedNextCourses = [...selectedNextCourses, course];
    _listsChanged = true;
    notifyListeners();
  }

  void removeNextCourseAt(int index) {
    selectedNextCourses = [...selectedNextCourses]..removeAt(index);
    _listsChanged = true;
    notifyListeners();
  }

  void moveNextCourse(int from, int to) {
    if (to < 0 || to >= selectedNextCourses.length) return;
    final updated = [...selectedNextCourses];
    final item = updated.removeAt(from);
    updated.insert(to, item);
    selectedNextCourses = updated;
    _listsChanged = true;
    notifyListeners();
  }

  void toggleRecommendedCourse(int courseId) {
    if (!selectedRecommendedCourseIds.remove(courseId)) {
      selectedRecommendedCourseIds.add(courseId);
    }
    _listsChanged = true;
    notifyListeners();
  }

  Future<void> _loadOtherCourses({int? excludeCourseId}) async {
    // the mode's side only (an organization's course links to its own courses), every course (not the first 20)
    final result = await run(() => _api.get('/api/v1/my-courses', queryParams: {'limit': 100, ...modeCourseScopeQuery()}));
    if (result['items'] is List) {
      otherCourses = (result['items'] as List<dynamic>)
          .whereType<dynamic>()
          .where((c) => c['id'] != excludeCourseId)
          .map(
            (c) => {
          'id': c['id'],
          'text': (c['name'] ?? c['title'] ?? '').toString(),
        },
      )
          .toList();
    } else {
      otherCourses = [];
    }
    notifyListeners();
  }

  void _restoreNextCourses(TeacherCourse course) {
    final byId = {for (final c in otherCourses) c['id']: c};
    selectedNextCourses = course.nextCourseIds
        .where(byId.containsKey)
        .map((id) => byId[id]!)
        .toList();
  }

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
    selectedTeachingType = teachingTypes[1]; // recorded
    selectedCurrency = AppCurrency.egp;
    defaultPlanIndex = 0;
    selectedNextCourses = [];
    selectedRecommendedCourseIds = {};
    level = null;
    tags = [];
    nextCoursesInPath = false;
    _listsChanged = false;
    _pendingSchedules = [];
    targets = [];
    subjectId = null;
    deliveryMode = 'online';
    area1 = area2 = null;
    address = '';
    _setupReady = true;
    _setupDirty = false;
    notifyListeners();
    await Future.wait([_loadCategories(context), _loadOtherCourses(), _loadSetupCatalog(null)]);
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
    selectedTeachingType = teachingTypes.firstWhere(
          (t) => t['text'] == course.type.toString().split('.').last.toLowerCase(),
      orElse: () => teachingTypes[1],
    );
    selectedCurrency = course.currency;
    defaultPlanIndex = course.defaultPricePlanIndex;
    selectedRecommendedCourseIds = course.recommendedCourseIds.toSet();
    level = course.level;
    tags = [...course.tags];
    _listsChanged = false;
    _setupDirty = false;
    _pendingSchedules = [];
    notifyListeners();

    await Future.wait([
      _loadCategories(context),
      _loadOtherCourses(excludeCourseId: course.id),
      _loadSetupFor(course),
    ]);
    _restoreSpecialization(course);
    _restoreNextCourses(course);
    notifyListeners();
  }

  Future<void> _loadCategories(BuildContext context) async {
    specializations = await context
        .read<CategoriesProvider>()
        .getSpecialization();
    notifyListeners();
  }

  void _restoreSpecialization(TeacherCourse course) {
    try {
      selectedSpecialization = specializations.firstWhere(
            (s) =>
        s['text'] ==
            (
            AppConfig.lang == 'ar'
                ? course.category!.nameAr
                : course.category!.nameEn,
            ),
      );
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

  void onChangeTeachingType(String type, ExpansibleController ctrl) {
    ctrl.collapse();
    selectedTeachingType = teachingTypes.firstWhere(
          (item) => item['text'] == type,
    );
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
      certificates: List.of(_form.certificates)..removeAt(index),
    );
    _listsChanged = true;
    notifyListeners();
  }

  void addFormTool(String name) {
    _form = _form.copyWith(tools: [..._form.tools, name]);
    _listsChanged = true;
    notifyListeners();
  }

  void removeFormTool(int index) {
    _form = _form.copyWith(tools: List.of(_form.tools)..removeAt(index));
    _listsChanged = true;
    notifyListeners();
  }

  void removeFormSchedule(int index) {
    _form = _form.copyWith(
      schedules: List.of(_form.schedules)..removeAt(index),
    );
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
      prerequisites: List.of(_form.prerequisites)..removeAt(index),
    );
    _listsChanged = true;
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CREATE
  // ─────────────────────────────────────────────────────────────────────────

  Future<TeacherCourse?> submitCreate({
    required String titleAr,
    required String titleEn,
    required String descriptionAr,
    required String descriptionEn,
    required String type, // live | recorded | both
    double fees = 0, // YEARLY price
    double? priceMonthly, // optional plans (null = not offered)
    double? priceSixMonths,
    double? totalHours,
    XFile? logoFile,
    double? discountPercentage,
    bool isPrivate = false,
    String? accessCode,
    int? discountDays,
    String? certificateTemplateTitle,
    XFile? certificateTemplateFile,
    bool publish = false,
  }) async {
    final result = await run(
          () => _api.post(
        '/api/v1/courses',
        body: {
      if (titleAr.trim().isNotEmpty) 'name_ar': titleAr.trim(),
      if (titleEn.trim().isNotEmpty) 'name_en': titleEn.trim(),
      if (descriptionAr.trim().isNotEmpty)
      'description_ar': descriptionAr.trim(),
      if (descriptionEn.trim().isNotEmpty)
      'description_en': descriptionEn.trim(),
      'type': type,
      'is_private': isPrivate,
      if (isPrivate && (accessCode ?? '').trim().isNotEmpty)
      'access_code': accessCode!.trim(),
      'fees': fees,
      'price_monthly': ?priceMonthly,
      'price_six_months': ?priceSixMonths,
      'default_price_plan_index': defaultPlanIndex,
      'currency': selectedCurrency.code,
      if (selectedSpecialization?['id'] != null)
      'category_id': selectedSpecialization!['id'],
      'hours': ?totalHours,
      'next_course_ids': selectedNextCourses.map((c) => c['id']).toList(),
      'level': ?level,
      if (tags.isNotEmpty) 'tags': tags,
      'recommended_course_ids': selectedRecommendedCourseIds.toList(),
      'discount_percentage': ?discountPercentage,
      'discount_days': ?discountDays,
      ..._setupBody(update: false),
      },
      ),
    );

    if (result is! Map<String, dynamic>) return null;
    TeacherCourse created = TeacherCourse.fromJson(result);

    // Step 2: upload image if provided
    if (logoFile != null) {
      final withImage = await _uploadImage(logoFile, courseId: created.id);
      if (withImage != null) created = withImage;
    }

    // Step 3: publish immediately if requested (otherwise stays a draft)
    if (publish) {
      final pubResult = await run(
            () => _api.post('/api/v1/courses/${created.id}/publish'),
      );
      if (pubResult != null) created = created.copyWith(isPublished: true);
    }

    // Step 4: persist extras in parallel
    await Future.wait([
      for (final s in _pendingSchedules)
        _addSchedule(
          created.id,
          day: s.day,
          startTime: s.startTime,
          endTime: s.endTime,
        ),
      for (final t in _form.certificates) _addCertificate(created.id, title: t),
      for (final t in _form.tools) _addTool(created.id, name: t),
      for (final pr in _form.prerequisites)
        _addPrerequisite(created.id, title: pr),
    ]);

    // Step 4.5: optional certificate template set up during creation
    if (certificateTemplateFile != null &&
        (certificateTemplateTitle?.trim().isNotEmpty ?? false)) {
      await _createCertificateWithTemplate(
        created.id,
        certificateTemplateTitle!.trim(),
        certificateTemplateFile,
      );
    }

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
        required String titleAr,
        required String titleEn,
        required String descriptionAr,
        required String descriptionEn,
        required String type,
        bool isPrivate = false,
        String? accessCode,
        double? fees, // YEARLY price
        double? priceMonthly, // always sent: null = stop offering the plan
        double? priceSixMonths,
        double? totalHours,
        XFile? logoFile,
        double? discountPercentage,
        bool clearDiscount = false,
        int? discountDays,
      }) async {
    final patchResult = await run(
          () => _api.put(
        '/api/v1/courses/${original.id}',
        body: {
      // always sent, so emptying one language really clears it
      'name_ar': titleAr.trim(),
      'name_en': titleEn.trim(),
      'description_ar': descriptionAr.trim(),
      'description_en': descriptionEn.trim(),
      'type': type,
      'is_private': isPrivate,
      if (isPrivate && (accessCode ?? '').trim().isNotEmpty)
      'access_code': accessCode!.trim(),
      'fees': ?fees,
      'price_monthly': priceMonthly,
      'price_six_months': priceSixMonths,
      'default_price_plan_index': defaultPlanIndex,
      'currency': selectedCurrency.code,
      if (selectedSpecialization?['id'] != null)
      'category_id': selectedSpecialization!['id'],
      'total_hours': ?totalHours,
      if (!nextCoursesInPath) 'next_course_ids': selectedNextCourses.map((c) => c['id']).toList(),
      'level': level,
      'tags': tags,
      'recommended_course_ids': selectedRecommendedCourseIds.toList(),
      if (clearDiscount)
      'discount_percentage': null
      else 'discount_percentage': ?discountPercentage,
      'discount_days': ?discountDays,
      ..._setupBody(update: true),
      },
      ),
    );

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
        _addSchedule(
          original.id,
          day: s.day,
          startTime: s.startTime,
          endTime: s.endTime,
        ),
      for (final t in newCerts) _addCertificate(original.id, title: t),
      for (final t in newTools) _addTool(original.id, name: t),
      for (final pr in newPrereqs) _addPrerequisite(original.id, title: pr),
    ]);

    final refreshed =
        await _fetchCourseDetail(original.id) ??
            TeacherCourse.fromJson(patchResult);
    _pendingSchedules = [];
    return refreshed;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Course progress status (in_progress / completed) — separate from
  // publish/draft, which TeacherProvider already handles.
  // ─────────────────────────────────────────────────────────────────────────

  Future<TeacherCourse?> updateStatus(int courseId, CourseStatus status) async {
    final result = await run(
          () => _api.put(
        '/api/v1/courses/$courseId/status',
        body: {'status': status.apiValue},
      ),
    );
    if (result is Map<String, dynamic>) return TeacherCourse.fromJson(result);
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private API helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<TeacherCourse?> _fetchCourseDetail(int courseId) async {
    final result = await run(() => _api.get('/api/v1/courses/$courseId'));
    if (result is Map<String, dynamic>) return TeacherCourse.fromJson(result);
    return null;
  }

  /// Removes the course cover at once (D-880, `DELETE /courses/{id}/image`, harmless twice): the answer is the
  /// course with no `image_url`, for the list and the page to show the default cover. Throws [ApiException].
  Future<TeacherCourse> removeImage(int courseId) async {
    final r = await _api.delete('/api/v1/courses/$courseId/image');
    return TeacherCourse.fromJson(r as Map<String, dynamic>);
  }

  Future<TeacherCourse?> _uploadImage(
      XFile logoFile, {
        required int courseId,
      }) async {
    try {
      final ext = p
          .extension(logoFile.path)
          .replaceFirst('.', '')
          .toLowerCase();
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
      final response = await _api.dio.post(
        '/api/v1/courses/$courseId/image',
        data: formData,
      );
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

  /// Creates a certificate on the freshly-created course and immediately
  /// uploads its template image — used for the optional "certificate
  /// template" widget in the course-creation form. Failures are logged but
  /// never block course creation from succeeding (the teacher can always
  /// add/fix the certificate afterward from the certificate manager).
  Future<void> _createCertificateWithTemplate(
      int courseId,
      String title,
      XFile file,
      ) async {
    final certResult = await run(
          () => _api.post(
        '/api/v1/courses/$courseId/certificates',
        body: {'title': title},
      ),
    );
    if (certResult is! Map<String, dynamic>) return;
    final certId = certResult['id'] as int?;
    if (certId == null) return;
    await _uploadCertificateTemplateBytes(certId, file);
  }

  /// Used by the EDIT-mode certificate template card. If the course
  /// already has a certificate ([existingCertificateId] non-null), the
  /// template is uploaded straight to it; otherwise a certificate is
  /// created first (using [title]) and the template attached to that.
  /// Returns the new template URL on success, or null on failure.
  Future<String?> updateCertificateTemplate({
    required int courseId,
    int? existingCertificateId,
    required String title,
    required XFile file,
  }) async {
    int? certId = existingCertificateId;
    if (certId == null) {
      final certResult = await run(
            () => _api.post(
          '/api/v1/courses/$courseId/certificates',
          body: {'title': title},
        ),
      );
      if (certResult is! Map<String, dynamic>) return null;
      certId = certResult['id'] as int?;
      if (certId == null) return null;
    }
    return _uploadCertificateTemplateBytes(certId, file);
  }

  Future<String?> _uploadCertificateTemplateBytes(
      int certId,
      XFile file,
      ) async {
    try {
      final ext = p.extension(file.path).replaceFirst('.', '').toLowerCase();
      final mimeType = switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };
      final bytes = await file.readAsBytes();
      final filename = p.basename(file.path).isNotEmpty
          ? p.basename(file.path)
          : 'template.${ext.isEmpty ? 'jpg' : ext}';

      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: MediaType.parse(mimeType),
        ),
      });
      final response = await _api.dio.post(
        '/api/v1/certificates/$certId/template',
        data: formData,
      );
      if (response.statusCode != 200) return null;
      final data = response.data as Map<String, dynamic>;
      return data['template_url'] as String?;
    } on DioException catch (e) {
      log(
        'uploadCertificateTemplate ❌ ${e.response?.statusCode}: ${e.response?.data}',
      );
      return null;
    } catch (e) {
      log('uploadCertificateTemplate ❌ unexpected: $e');
      return null;
    }
  }

  Future<void> _addSchedule(
      int courseId, {
        required String day,
        required String startTime,
        required String endTime,
      }) => run(
        () => _api.post(
      '/api/v1/courses/$courseId/schedules',
      body: {'day': day, 'start_time': startTime, 'end_time': endTime},
    ),
  );

  Future<void> _removeSchedule(int scheduleId) =>
      run(() => _api.delete('/api/v1/schedules/$scheduleId'));

  Future<void> _addCertificate(int courseId, {required String title}) => run(
        () => _api.post(
      '/api/v1/courses/$courseId/certificates',
      body: {'title': title},
    ),
  );

  Future<void> _removeCertificate(int certId) =>
      run(() => _api.delete('/api/v1/certificates/$certId'));

  Future<void> _addTool(int courseId, {required String name}) => run(
        () => _api.post('/api/v1/courses/$courseId/tools', body: {'title': name}),
  );

  Future<void> _removeTool(int toolId) =>
      run(() => _api.delete('/api/v1/tools/$toolId'));

  Future<void> _addPrerequisite(int courseId, {required String title}) => run(
        () => _api.post(
      '/api/v1/courses/$courseId/prerequisites',
      body: {'title': title},
    ),
  );

  Future<void> _removePrerequisite(int prereqId) =>
      run(() => _api.delete('/api/v1/prerequisites/$prereqId'));
}