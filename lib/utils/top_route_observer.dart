import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/features/student/models.dart';

/// Tracks whichever route is currently on top of the navigation stack.
///
/// `navigatorKey.currentContext` alone can't tell you this — it's the
/// Navigator widget's own context, which sits *above* all pushed routes,
/// so `ModalRoute.of(navigatorKey.currentContext)` always returns null.
/// Register this as a `navigatorObservers` entry on your `MaterialApp`
/// (alongside `navigatorKey: navigatorKey`) to get a reliable answer.
class TopRouteObserver extends NavigatorObserver {
  Route<dynamic>? currentRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentRoute = route;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentRoute = previousRoute;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentRoute = previousRoute;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    currentRoute = newRoute;
  }

  bool get isCourseDetailActive =>currentRoute?.settings.name == '/course-detail';


  /// The course currently shown by CourseDetailScreen, if that's the active
  /// route. Matches how main.dart's _router passes it: `settings.arguments
  /// as CourseModel`.
  String? get activeCourseId {
    CourseModel? args = currentRoute?.settings.arguments as CourseModel? ;
    return args is CourseModel ? args.id : null;
  }
}

/// Shared instance — reference this both in MaterialApp's
/// `navigatorObservers` and from notification_service.dart.
final topRouteObserver = TopRouteObserver();
