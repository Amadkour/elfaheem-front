// The app's root router (D-170): `MaterialApp.router` around the SAME root Navigator the app always had.
//
// Why a Router at all: a plain `MaterialApp` gives its root Navigator `reportsRouteUpdateToEngine`, which pins the
// browser to Flutter's single-entry history (one entry, Back = "pop one route or leave") and rewrites the URL only for
// named routes. Under a Router the navigator stays quiet and [WebHistory] keeps one browser entry per page instead.
//
// Nothing else changes: the navigator is keyed by main.dart's `navigatorKey`, routes by `_router` (onGenerateRoute),
// starts on the same initial route(s), and the 300+ `Navigator.push(MaterialPageRoute(…))` call sites keep working.
// The system back (Android, the browser's Back on the first page) reaches it through the Router's back button
// dispatcher → [PopNavigatorRouterDelegateMixin] → `maybePop`, after the live room's observer, as before.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'web_history.dart';

class AppRouterDelegate extends RouterDelegate<RouteInformation>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<RouteInformation> {
  AppRouterDelegate({
    required this.navigatorKey,
    required this.observers,
    required this.onGenerateRoute,
    required this.initialRoute,
    required this.initialRoutes,
  });

  @override
  final GlobalKey<NavigatorState> navigatorKey;

  final List<NavigatorObserver> observers;
  final RouteFactory onGenerateRoute;

  /// The first route's name, read when the navigator is first built.
  final String Function() initialRoute;

  /// The first route(s) for that name (a page over the home, the offline start's Downloads …).
  final List<Route<dynamic>> Function(String name) initialRoutes;

  @override
  Widget build(BuildContext context) => Navigator(
        key: navigatorKey,
        observers: observers,
        initialRoute: initialRoute(),
        onGenerateRoute: onGenerateRoute,
        onGenerateInitialRoutes: (_, name) => initialRoutes(name),
      );

  /// Never reported through the Router: [WebHistory] writes the browser's entries itself (the Router would push a new
  /// entry for every in-app Back).
  @override
  RouteInformation? get currentConfiguration => null;

  /// The first route comes from [initialRoute] (main.dart decides it from the URL, the sign-in and the network).
  @override
  Future<void> setInitialRoutePath(RouteInformation configuration) => SynchronousFuture<void>(null);

  @override
  Future<void> setNewRoutePath(RouteInformation configuration) {
    if (kIsWeb) {
      WebHistory.instance.browserMoved(configuration); // Back / Forward / a history jump
    } else {
      // an app link while the app runs: pushed by name, as WidgetsApp did
      final uri = configuration.uri;
      navigatorKey.currentState?.pushNamed(Uri.decodeComponent(Uri(
        path: uri.path.isEmpty ? '/' : uri.path,
        queryParameters: uri.queryParametersAll.isEmpty ? null : uri.queryParametersAll,
        fragment: uri.fragment.isEmpty ? null : uri.fragment,
      ).toString()));
    }
    return SynchronousFuture<void>(null);
  }
}

/// The URL is the configuration: parsed by the delegate itself.
class AppRouteInformationParser extends RouteInformationParser<RouteInformation> {
  const AppRouteInformationParser();

  @override
  Future<RouteInformation> parseRouteInformation(RouteInformation routeInformation) =>
      SynchronousFuture<RouteInformation>(routeInformation);

  @override
  RouteInformation? restoreRouteInformation(RouteInformation configuration) => configuration;
}
