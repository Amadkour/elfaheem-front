import 'package:flutter_education_app/features/home/student/models.dart';

class TeacherStats {
  final double overallRating;
  final double doctorRating;
  final double materialRating;
  final double courseRating;
  final int totalStudents;
  final int totalCourses;
  final TeacherProfileData? teacher;

  const TeacherStats({
    this.overallRating = 0.0,
    this.totalStudents = 0,
    this.totalCourses = 0,
    this.doctorRating = 0,
    this.materialRating = 0,
    this.courseRating = 0,
    this.teacher,
  });

  factory TeacherStats.fromJson(Map<String, dynamic> j) => TeacherStats(
        overallRating: (j['composite_rate'] as num?)?.toDouble() ?? 0,
        doctorRating: (j['doctor_rate'] as num?)?.toDouble() ?? 0,
        materialRating: (j['material_rate'] as num?)?.toDouble() ?? 0,
        courseRating: (j['course_rate'] as num?)?.toDouble() ?? 0,
        totalStudents: j['total_students'] as int? ?? 0,
        totalCourses: j['total_courses'] as int? ?? 0,
    teacher: j['teacher'] != null
        ? TeacherProfileData.fromJson(j['teacher'] as Map<String, dynamic>)
        : null,
      );

  TeacherStats copyWith({
    double? overallRating,
    int? totalStudents,
    int? totalCourses,
    TeacherProfileData? teacher
  }) =>
      TeacherStats(
        overallRating: overallRating ?? this.overallRating,
        totalStudents: totalStudents ?? this.totalStudents,
        totalCourses: totalCourses ?? this.totalCourses, teacher: teacher??this.teacher,
      );
}
