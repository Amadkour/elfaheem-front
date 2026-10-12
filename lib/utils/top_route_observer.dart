import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/features/student/models.dart';

class TopRouteObserver extends NavigatorObserver {
  Route<dynamic>? currentRoute;
  Route<dynamic>? previousRoute;

  @override
  void didPush(
      Route<dynamic> route,
      Route<dynamic>? previousRoute,
      ) {
    this.previousRoute = previousRoute;
    currentRoute = route;
  }

  @override
  void didPop(
      Route<dynamic> route,
      Route<dynamic>? previousRoute,
      ) {
    this.previousRoute = route;
    currentRoute = previousRoute;
  }

  @override
  void didRemove(
      Route<dynamic> route,
      Route<dynamic>? previousRoute,
      ) {
    this.previousRoute = previousRoute;
    currentRoute = previousRoute;
  }

  @override
  void didReplace({
    Route<dynamic>? newRoute,
    Route<dynamic>? oldRoute,
  }) {
    previousRoute = oldRoute;
    currentRoute = newRoute;
  }

  bool get isCourseDetailActive =>
      currentRoute?.settings.name == '/course-detail';

  String? get activeCourseId {
    final args = currentRoute?.settings.arguments;

    if (args is CourseModel) {
      return args.id;
    }

    return null;
  }

  // Previous route name
  String? get previousRouteName =>
      previousRoute?.settings.name;

  // Current route name
  String? get currentRouteName =>
      currentRoute?.settings.name;
}

final topRouteObserver = TopRouteObserver();