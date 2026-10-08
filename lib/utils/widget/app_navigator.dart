// lib/core/app_navigator.dart
//
// One place that knows how to open a "module" from a notification tap, a push, a dialog button
// or a shared link. Everything goes through navigatorKey (main.dart).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../features/student/courses/details/course_link_loader.dart';
import '../../main.dart';
import 'view_as_state.dart';

class AppNavigator {
  AppNavigator._();

  /// AppShell listens to this: set it to a ShellPage.id (e.g. 'profile') to switch tab.
  static final ValueNotifier<String?> requestedTab = ValueNotifier<String?>(null);

  /// Teachers have their own course screen. Set this once (e.g. in main()) to build it:
  ///   AppNavigator.teacherCourseBuilder = (course) => TeacherCourseScreen(course: course);
  /// Left null → teachers also get the shared CourseDetailScreen.
  static Widget Function(Map<String, dynamic> courseJson)? teacherCourseBuilder;

  static Future<void> openCourse(int courseId, {int? ref}) async {
    await navigatorKey.currentState?.push(MaterialPageRoute(
      settings: const RouteSettings(name: '/course-by-id'),
      builder: (_) => CourseLinkLoader(courseId: courseId, ref: ref),
    ));
  }

  /// module: profile | course | notifications | my_courses | subscription
  static Future<void> openModule(String? module, {int? targetId}) async {
    final nav = navigatorKey.currentState;
    final ctx = navigatorKey.currentContext;
    if (nav == null || ctx == null || !ctx.mounted) return;
    // Not logged in (or an admin is only LOOKING at a user's app): never navigate on that user's behalf.
    if (!ctx.read<AuthProvider>().isAuthenticated || ViewAsState.active) return;
    switch (module) {
      case 'course':
        if (targetId != null) {
          await openCourse(targetId);
        } else {
          await nav.pushNamed('/notifications'); // "course" button without a course id: do not do nothing
        }
        return;
      case 'notifications':
        await nav.pushNamed('/notifications');
        return;
      case 'subscription':
        await nav.pushNamed('/subscription');
        return;
      case 'profile':
      case 'my_courses':
      // These are tabs inside the dashboards: pop to the root and ask the AppShell to switch.
        nav.popUntil((r) => r.isFirst);
        requestedTab.value = null; // re-fire even if the same id is requested twice
        requestedTab.value = module;
        return;
      default:
      // A module this app version does not know (server added a new one) → the notifications list
      // is the safest place to land instead of silently ignoring the tap.
        await nav.pushNamed('/notifications');
    }
  }

  /// Notification list tap / push tap. Asks the server where the notification points.
  static Future<void> openNotification(String notificationId) async {
    try {
      final r = await ApiClient().get('/api/v1/notifications/$notificationId/target');
      if (r is! Map) return;
      final module = r['module']?.toString();
      final courseId = int.tryParse('${r['course_id'] ?? ''}');
      await openModule(module, targetId: courseId);
    } catch (_) {/* tapping must never crash */}
  }

  /// FCM payload (tap or foreground). Uses explicit fields when present, else course_id.
  static Future<void> openFromPush(Map<String, dynamic> data) async {
    if (ViewAsState.active) return;
    final module = data['module']?.toString();
    final target = int.tryParse('${data['target_id'] ?? data['course_id'] ?? ''}');
    if (module != null) return openModule(module, targetId: target);
    if (target != null) return openCourse(target);
    await navigatorKey.currentState?.pushNamed('/notifications');
  }

  static String get homeRoute {
    final ctx = navigatorKey.currentContext;
    return ctx == null ? '/login' : ctx.read<AuthProvider>().homeRoute;
  }
}