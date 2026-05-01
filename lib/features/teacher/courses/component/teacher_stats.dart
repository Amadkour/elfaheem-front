class TeacherStats {
  final double overallRating;
  final int totalStudents;
  final int totalCourses;

  const TeacherStats({
    this.overallRating = 0.0,
    this.totalStudents = 0,
    this.totalCourses = 0,
  });

  factory TeacherStats.fromJson(Map<String, dynamic> j) => TeacherStats(
        overallRating: (j['overall_rating'] as num?)?.toDouble() ??
            (j['rating'] as num?)?.toDouble() ??
            0.0,
        totalStudents: j['total_students'] as int? ?? 0,
        totalCourses: j['total_courses'] as int? ?? 0,
      );

  TeacherStats copyWith({
    double? overallRating,
    int? totalStudents,
    int? totalCourses,
  }) =>
      TeacherStats(
        overallRating: overallRating ?? this.overallRating,
        totalStudents: totalStudents ?? this.totalStudents,
        totalCourses: totalCourses ?? this.totalCourses,
      );
}
