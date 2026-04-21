import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/models.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/student/dashboard/dashboard_screen.dart';
import '../features/student/courses/details/course_detail_screen.dart';
import '../features/student/courses/list/courses_list_screen.dart';
import '../features/teacher/courses/add_course_screen.dart';

class AppRoutes {
  // Route names
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String coursesList = '/courses';
  static const String courseDetail = '/course-detail';
  static const String createCourse = '/create-course';
  static const String lessonDetail = '/lesson-detail';
  static const String videoPlayer = '/video-player';
  static const String uploadVideo = '/upload-video';
  static const String liveSessions = '/live-sessions';
  static const String createLiveSession = '/create-live-session';
  static const String liveStreaming = '/live-streaming';

  /// Generate routes
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());

      case register:
        return MaterialPageRoute(builder: (_) => const RegisterScreen());

      case home:
        return MaterialPageRoute(builder: (_) => const DashboardScreen());

      case coursesList:
        return MaterialPageRoute(builder: (_) => const CoursesListScreen());

      case courseDetail:
        final course = settings.arguments as CourseModel;
        return MaterialPageRoute(
          builder: (_) => CourseDetailScreen(
            course: course,
          ),
        );

      case createCourse:
        return MaterialPageRoute(builder: (_) => const AddCourseScreen());

      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('No route defined for ${settings.name}'),
            ),
          ),
        );
    }
  }
}
