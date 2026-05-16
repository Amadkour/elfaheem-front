/// ─────────────────────────────────────────────────────────────────────────────
/// home_provider.dart  —  v3.2.0
///
/// Changes:
///   • Stub data removed — HomeProvider is now a thin shell
///   • Real data comes from CategoriesProvider + CoursesProvider
///   • Keeps only: user info, nav index, upcoming banner
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/base_provider.dart';
import 'package:provider/provider.dart';

import '../../category/categories_provider.dart';
import '../courses/list/courses_provider.dart';

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

class HomeProvider extends BaseProvider {

  Future<void> init(BuildContext context)async{
    await Future.value([
      context.read<CategoriesProvider>().fetchCategories(),
      context.read<CoursesProvider>().fetchCourses(),
    ]);
  }
  List<InstructorData> instructors = [
  InstructorData(
  'محمد عبد الله', 'الهندسه المعماريه', 'https://i.pravatar.cc/150?img=50'),
  InstructorData('ايهاب نافع', 'علم النفس', 'https://i.pravatar.cc/150?img=35'),
  InstructorData(
  'منه الله محمد', 'اللغه الانجليزيه', 'https://i.pravatar.cc/150?img=47'),
  ];
  // Upcoming banner — in production this comes from the dashboard API
  final UpcomingCourse upcomingCourse = const UpcomingCourse(
    title:    'الدوره ستبداً قريباً',
    subtitle: 'اللغه الانجليزيه',
    time:     '٩:٣٠ مساء',
  );
}

class InstructorData {
  final String name;
  final String specialty;
  final String avatarUrl;

  const InstructorData(this.name, this.specialty, this.avatarUrl);
}

