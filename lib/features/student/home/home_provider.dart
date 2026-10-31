// ─────────────────────────────────────────────────────────────────────────────
// home_provider.dart  —  v3.3.0
//
// Changes:
//   • Hardcoded instructors removed
//   • fetchTopDoctors() calls GET /api/v1/teacher/doctors?page=1&size=5
//   • InstructorData promoted to a real model with fromJson factory
//   • init() now awaits all three providers + top-doctors fetch in parallel
// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/base_provider.dart';
import '../../../core/api_client.dart';
import '../../../core/app_mode.dart';
import '../../shared/course/course_scope.dart' show modeCourseScopeQuery;
import '../../shared/category/categories_provider.dart';
import '../../shared/guest/guest_state.dart';
import '../models.dart';

// ── Simple models ─────────────────────────────────────────────────────────────

class HomeUser {
  final String name;
  final String greeting;

  const HomeUser({required this.name, required this.greeting});
}

class UpcomingCourse {
  final String title;
  final String subtitle;
  final String time;

  const UpcomingCourse({
    required this.title,
    required this.subtitle,
    required this.time,
  });
}

// ── InstructorData — now a real model ────────────────────────────────────────

class InstructorData {
  final double compositeRate;
  final double doctorRate;
  final double courseRate;
  final double materialRate;
  final int totalCourses;
  final int totalStudents;
  final TeacherProfileData? teacher;

  const InstructorData({
    this.compositeRate = 0.0,
    this.doctorRate = 0.0,
    this.courseRate = 0.0,
    this.materialRate = 0.0,
    this.totalCourses = 0,
    this.totalStudents = 0,
    this.teacher,
  });

  factory InstructorData.fromJson(Map<String, dynamic> json) {
    return InstructorData(
      teacher: json['teacher'] != null
          ? TeacherProfileData.fromJson(json['teacher'] as Map<String, dynamic>)
          : null,
      compositeRate: (json['composite_rate'] as num?)?.toDouble() ?? 0.0,
      doctorRate: (json['doctor_rate'] as num?)?.toDouble() ?? 0.0,
      courseRate: (json['course_rate'] as num?)?.toDouble() ?? 0.0,
      materialRate: (json['material_rate'] as num?)?.toDouble() ?? 0.0,
      totalCourses: (json['total_courses'] as num?)?.toInt() ?? 0,
      totalStudents: (json['total_students'] as num?)?.toInt() ?? 0,
    );
  }
}

// ── HomeProvider ──────────────────────────────────────────────────────────────

class HomeProvider extends BaseProvider {
  // ── State ──────────────────────────────────────────────────────────────────
  final ApiClient api;

  HomeProvider({ApiClient? api}) : api = api ?? ApiClient() {
    _side = _sideKey;
    AppModeController.instance.addListener(_onMode);
  }

  // GET /teacher/student-dashboard carries the mode's side (`scope` / `org_id`, the server's default is the
  // personal account): "My courses" and "Other courses" are that side's. A switch drops the other side's lists at
  // once and reloads (once the home was loaded); an answer that arrives after a switch is dropped.
  late String _side;
  bool _fetched = false;

  static String get _sideKey {
    final q = modeCourseScopeQuery();
    return '${q['scope']}:${q['org_id'] ?? ''}';
  }

  void _onMode() {
    final now = _sideKey;
    if (now == _side) return;
    _side = now;
    if (!_fetched || GuestState.active) return;
    myCourses = [];
    otherCourses = [];
    notifyListeners();
    fetchStudentDashboard();
  }

  @override
  void dispose() {
    AppModeController.instance.removeListener(_onMode);
    super.dispose();
  }

  // Upcoming banner — in production this comes from the dashboard API
  final UpcomingCourse upcomingCourse = const UpcomingCourse(
    title: 'الدوره ستبداً قريباً',
    subtitle: 'اللغه الانجليزيه',
    time: '٩:٣٠ مساء',
  );

  List<CourseModel> myCourses=[];
  List<CourseModel> otherCourses=[];
  List<CategoryModel> categories=[];
  List<InstructorData> instructors = [];

  /// The last dashboard request failed (offline / server error). The screen shows a retry
  /// state instead of staying on the shimmer.
  bool loadFailed = false;

  bool get hasData =>
      myCourses.isNotEmpty ||
          otherCourses.isNotEmpty ||
          categories.isNotEmpty ||
          instructors.isNotEmpty;
  // ── Init — run everything in parallel ─────────────────────────────────────

  Future<void> init(BuildContext context) async {
    try {
      await fetchStudentDashboard();
    } catch (e) {
      // e.g. a parsing error: never leave the page on the shimmer
      loadFailed = true;
      stopLoading();
      notifyListeners();
    }
  }

  // ── Fetch top 5 doctors ───────────────────────────────────────────────────

  /// Calls GET /api/v1/teacher/doctors?page=1&size=5
  /// The backend returns teachers ordered by composite_rate DESC.
  Future<void> fetchStudentDashboard() async {
    makeLoading();
    loadFailed = false;
    _fetched = true;
    final side = _side;
    final result = await run(
          () => api.get(
        '/api/v1/teacher/student-dashboard',
        // the mode's side; a guest has none (no token at all → the server answers with the public catalogue)
        queryParams: GuestState.active ? null : modeCourseScopeQuery(),
        // Guest: no token at all → the server answers with the public catalogue.
        auth: !GuestState.active,
      ),
    );
    if (side != _side) return; // the mode changed meanwhile: its own reload answers for the new side
    // Request failed → run() already holds the error. This used to throw "operator [] on null" here.
    if (result is! Map) {
      loadFailed = true;
      stopLoading(); // otherwise the page stays on the shimmer forever
      notifyListeners();
      return;
    }

    if (result['categories'] is List) {
      categories = (result['categories'] as List)
          .map<CategoryModel>((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    }

    // if (result['enrolled_courses'] is List) {
    //   myCourses = (result['enrolled_courses'] as List)
    //       .map<CourseModel>((e) => CourseModel.fromJson(e as Map<String, dynamic>))
    //       .toList();
    //   notifyListeners();
    //
    // }
    //
    // if (result['other_courses'] is List) {
    //   otherCourses = (result['other_courses'] as List)
    //       .map<CourseModel>((e) => CourseModel.fromJson(e as Map<String, dynamic>))
    //       .toList();
    //   notifyListeners();
    //
    // }
    List<Map<String, dynamic>> asMapList(dynamic v) {
      if (v is List && v.isNotEmpty && v.first is List) v = v.first; // [[...], total]
      return v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];
    }

    myCourses = asMapList(result['enrolled_courses']).map(CourseModel.fromJson).toList();
    otherCourses = asMapList(result['other_courses']).map(CourseModel.fromJson).toList();

    if (result['best_teachers'] is Map &&
        result['best_teachers']['items'] is List) {
      instructors = (result['best_teachers']['items'] as List)
          .whereType<Map<String, dynamic>>()
          .map<InstructorData>(InstructorData.fromJson)
          .toList();

    }
    stopLoading();
    notifyListeners();
  }
}