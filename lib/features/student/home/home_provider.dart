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
import '../../category/categories_provider.dart';
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
  final ApiClient _api;

  HomeProvider({ApiClient? api}) : _api = api ?? ApiClient();

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
  // ── Init — run everything in parallel ─────────────────────────────────────

  Future<void> init(BuildContext context) async {
    await Future.wait([
      fetchStudentDashboard(),
    ]);
  }

  // ── Fetch top 5 doctors ───────────────────────────────────────────────────

  /// Calls GET /api/v1/teacher/doctors?page=1&size=5
  /// The backend returns teachers ordered by composite_rate DESC.
  Future<void> fetchStudentDashboard() async {
    notifyListeners();

    final result = await run(
      () => _api.get(
        '/api/v1/teacher/student-dashboard',
        auth: true,
      ),
    );
    if (result['categories'] is List) {
      categories = (result['categories'] as List)
          .map<CategoryModel>((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    if (result['enrolled_courses'] is List) {
      myCourses = (result['enrolled_courses'] as List)
          .map<CourseModel>((e) => CourseModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    if (result['other_courses'] is List) {
      otherCourses = (result['other_courses'] as List)
          .map<CourseModel>((e) => CourseModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    if (result['best_teachers'] is Map &&
        result['best_teachers']['items'] is List) {
      instructors = (result['best_teachers']['items'] as List)
          .whereType<Map<String, dynamic>>()
          .map<InstructorData>(InstructorData.fromJson)
          .toList();
    }
    notifyListeners();
  }
}
