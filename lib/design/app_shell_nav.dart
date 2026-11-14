// lib/design/app_shell_nav.dart — per-tab back stacks for the role shells (D-081, on top of D-062 / D-077).
//
// Every tab of an [AppShell] owns a Navigator ([AppTabNavigator]), so a page opened from inside a tab (course
// details, settings sub-pages, lists, a notification tap) keeps the role's tab bar — the phone's bottom bar, the
// tablet's rail, the desktop's sidebar — and each tab keeps its own back stack while the person switches tabs.
//
//   What goes where (a push from inside a tab, [shellRouteGoesToRoot]):
//     tab navigator   ordinary pages (MaterialPageRoute, named routes from main.dart's _router)
//     root navigator  dialogs and bottom sheets (they cover the bar, as before), `fullscreenDialog` pages (forms,
//                     the image cropper, attendance live), the auth routes and the role homes ([shellRootRouteNames]),
//                     guest live links — and every replace / remove-until that would remove the tab's own root
//                     (sign-out, "back to home": the whole app stack, as before).
//   A tab-root `pop` / `maybePop` (an old screen that closes itself) goes to the navigator above, as before.
//   A page that must be full-screen inside a tab (video player, exam sitting, pre-join) wraps its body in
//   [ShellFullScreen]: the shell hides its bar / rail / sidebar while that page is the tab's top.
//
//   Back:  the tab's stack first, then the home tab, then out ([shellBackAction]).
//   Tap:   another tab → switch; the current tab with pages on it → back to its root ([shellTapAction]).
//
// [AppShellNav] is the registry of mounted shells: the deep links push into the visible tab ([AppShellNav.pushTarget]),
// topRouteObserver asks it for the route the person sees ([AppShellNav.effectiveTop]), and the floating assistant
// asks it how tall the visible bottom bar is ([AppShellNav.bottomBarHeight]).
// Pure parts are unit-tested in test/ui/app_shell_nav_test.dart.
library;

import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoModalPopupRoute;
import 'package:flutter/material.dart';

import '../utils/top_route_observer.dart' show topRouteObserver;

// ─────────────────────────────────────────────────────────────────────────────
// Pure decisions
// ─────────────────────────────────────────────────────────────────────────────

/// Named routes that never open inside a tab: sign-in and the role homes (each home is a shell of its own).
const shellRootRouteNames = {
  '/login',
  '/register',
  '/otp',
  '/forgot-password',
  '/splash',
  '/home',
  '/dashboard',
  '/teacher_dashboard',
  '/admin_dashboard',
  '/parent_dashboard',
  '/org_dashboard',
  '/org_member',
  '/attendance-live',
};

/// Route name prefixes that never open inside a tab (the public live-guest page).
const shellRootRoutePrefixes = ['/live/'];

/// True when a route pushed from inside a tab belongs on the root navigator instead (see the file header).
bool shellRouteGoesToRoot(Route<dynamic> route) {
  if (route is ModalBottomSheetRoute || route is RawDialogRoute || route is CupertinoModalPopupRoute) return true;
  if (route is PageRoute && route.fullscreenDialog) return true;
  final name = route.settings.name;
  if (name == null) return false;
  if (shellRootRouteNames.contains(name)) return true;
  return shellRootRoutePrefixes.any(name.startsWith);
}

/// What the system back button does in a shell.
enum ShellBack { popTab, homeTab, leave }

ShellBack shellBackAction({required bool tabCanPop, required int index, int homeIndex = 0}) {
  if (tabCanPop) return ShellBack.popTab;
  if (index != homeIndex) return ShellBack.homeTab;
  return ShellBack.leave;
}

/// What a tap on a tab does.
enum ShellTap { switchTab, popToRoot, none }

ShellTap shellTapAction({required int tapped, required int current, required bool tabCanPop}) {
  if (tapped != current) return ShellTap.switchTab;
  return tabCanPop ? ShellTap.popToRoot : ShellTap.none;
}

// ─────────────────────────────────────────────────────────────────────────────
// A tab's navigator
// ─────────────────────────────────────────────────────────────────────────────

/// One tab's back stack: its navigator key, its root route and the routes it holds (kept by its observer).
class ShellTab {
  ShellTab._(this._owner, this.label);

  final ShellTabs _owner;
  final String label;
  final navKey = GlobalKey<NavigatorState>();
  final hero = HeroController(createRectTween: (begin, end) => MaterialRectArcTween(begin: begin, end: end));
  late final observer = _ShellTabObserver(this);

  /// Every route of this tab, bottom first.
  final routes = <Route<dynamic>>[];
  Route<dynamic>? root;

  Route<dynamic>? get top => routes.isEmpty ? null : routes.last;
  /// A page to go back from, or a top page that closes something of its own first (a local history entry: an open
  /// detail panel, D-290).
  bool get canPop => routes.length > 1 || (routes.isNotEmpty && routes.last.willHandlePopInternally);
  NavigatorState? get navigator => navKey.currentState;

  /// The tab's first page: draws the tab's screen (read from [ShellTabScreen], so a new screen widget from the
  /// dashboard reaches the page without a new route).
  Route<dynamic> makeRoot() {
    routes.clear();
    final r = PageRouteBuilder<void>(
      settings: RouteSettings(name: null, arguments: label),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => const _TabRootPage(),
    );
    root = r;
    return r;
  }

  void popToRoot() {
    final nav = navigator;
    if (nav == null || !canPop) return;
    nav.popUntil((r) => r.isFirst);
  }

  void _changed(Route<dynamic> route, {required bool pushed}) {
    if (!pushed) AppShellNav._fullScreen.remove(route); // a full-screen page that left needs no forgetting by hand
    final initial = pushed && routes.length == 1 && identical(routes.first, route);
    _owner._tabChanged(this);
    if (identical(_owner.active, this)) topRouteObserver.didChangeNested(route, pushed: pushed, initial: initial);
  }
}

class _ShellTabObserver extends NavigatorObserver {
  _ShellTabObserver(this.tab);
  final ShellTab tab;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    tab.routes.add(route);
    tab._changed(route, pushed: true);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    tab.routes.remove(route);
    tab._changed(route, pushed: false);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    tab.routes.remove(route);
    tab._changed(route, pushed: false);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : tab.routes.indexOf(oldRoute);
    if (newRoute != null) {
      if (i >= 0) {
        tab.routes[i] = newRoute;
      } else {
        tab.routes.add(newRoute);
      }
      tab._changed(newRoute, pushed: true);
    }
  }
}

/// The tab's screen for its root page.
class ShellTabScreen extends InheritedWidget {
  const ShellTabScreen({super.key, required this.screen, required super.child});
  final Widget screen;

  @override
  bool updateShouldNotify(ShellTabScreen old) => !identical(screen, old.screen);
}

class _TabRootPage extends StatelessWidget {
  const _TabRootPage();

  @override
  Widget build(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellTabScreen>()?.screen ?? const SizedBox.shrink();
}

/// The navigator of one tab. It hands to the navigator above whatever must not live inside a tab (see the file
/// header), so code written for one app-wide navigator keeps doing what it did.
class AppTabNavigator extends Navigator {
  const AppTabNavigator({
    super.key,
    required this.tab,
    super.observers,
    super.onGenerateRoute,
    super.onUnknownRoute,
    super.onGenerateInitialRoutes,
  });

  final ShellTab tab;

  @override
  NavigatorState createState() => AppTabNavigatorState();
}

class AppTabNavigatorState extends NavigatorState {
  /// The navigator this tab sits in (the root one, or the tab of an outer shell).
  NavigatorState? get _up => context.findAncestorStateOfType<NavigatorState>();

  Route<dynamic>? get _tabRoot => (widget as AppTabNavigator).tab.root;

  @override
  Future<T?> push<T extends Object?>(Route<T> route) {
    final up = _up;
    if (up != null && shellRouteGoesToRoot(route)) return up.push<T>(route);
    return super.push<T>(route);
  }

  @override
  Future<T?> pushReplacement<T extends Object?, TO extends Object?>(Route<T> newRoute, {TO? result}) {
    final up = _up;
    if (up != null && (shellRouteGoesToRoot(newRoute) || !canPop())) {
      return up.pushReplacement<T, TO>(newRoute, result: result);
    }
    return super.pushReplacement<T, TO>(newRoute, result: result);
  }

  @override
  Future<T?> pushAndRemoveUntil<T extends Object?>(Route<T> newRoute, RoutePredicate predicate) {
    final up = _up;
    final root = _tabRoot;
    if (up != null && (shellRouteGoesToRoot(newRoute) || (root != null && !predicate(root)))) {
      return up.pushAndRemoveUntil<T>(newRoute, predicate);
    }
    return super.pushAndRemoveUntil<T>(newRoute, predicate);
  }

  @override
  void pop<T extends Object?>([T? result]) {
    final up = _up;
    if (up != null && !canPop()) return up.pop<T>(result);
    super.pop<T>(result);
  }

  @override
  Future<bool> maybePop<T extends Object?>([T? result]) {
    final up = _up;
    if (up != null && !canPop()) return up.maybePop<T>(result);
    return super.maybePop<T>(result);
  }

  @override
  void popUntil(RoutePredicate predicate) {
    var reachedRoot = false;
    super.popUntil((r) {
      if (predicate(r)) return true;
      if (r.isFirst) {
        reachedRoot = true;
        return true;
      }
      return false;
    });
    if (reachedRoot) _up?.popUntil(predicate);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// A shell's tabs
// ─────────────────────────────────────────────────────────────────────────────

/// The tabs of one shell: their navigators, which one is visible, and whether the shell's chrome must hide.
class ShellTabs extends ChangeNotifier {
  final _tabs = <String, ShellTab>{};
  ShellTab? active;

  /// The route the shell is drawn in (the dashboard's route).
  ModalRoute<dynamic>? hostRoute;

  /// The key of the shell's first tab (its home): that tab adds nothing to the home's URL.
  String? homeLabel;

  /// The kind of shell on screen and the height of its bottom bar (0 without one), for the floating assistant.
  double bottomBar = 0;

  /// Width of the sidebar / rail on the start side (0 on phones and full-screen pages), and of the top bar.
  double sideChrome = 0;

  ShellTab tab(String label) => _tabs.putIfAbsent(label, () => ShellTab._(this, label));

  bool get activeCanPop => active?.canPop ?? false;

  /// The visible tab's top page asked for the whole screen ([ShellFullScreen]).
  bool get fullScreen {
    final t = active?.top;
    return t != null && AppShellNav._fullScreen.contains(t);
  }

  void setActive(String label) {
    final t = tab(label);
    if (identical(active, t)) return;
    active = t;
    topRouteObserver.didSwitchTab();
    _notifySoon();
  }

  void popActiveToRoot() => active?.popToRoot();

  void _tabChanged(ShellTab t) => _notifySoon();

  /// A tab's page added or removed a local history entry (an open detail panel, D-290): the shell's Back decision
  /// ([shellBackAction]) changes.
  void popStateChanged() => _notifySoon();

  bool _queued = false;
  bool _disposed = false;

  /// Navigator callbacks run in the middle of a build: listeners hear about it right after.
  void _notifySoon() {
    if (_queued || _disposed) return;
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      if (!_disposed) {
        notifyListeners();
        AppShellNav.changes.value++;
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    for (final t in _tabs.values) {
      t.hero.dispose();
    }
    super.dispose();
  }
}

/// Lets the shell's own chrome (top bar icons, user chip) and any page find the visible tab's navigator.
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required this.tabs, required super.child});
  final ShellTabs tabs;

  static ShellTabs? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<ShellScope>()?.tabs;

  @override
  bool updateShouldNotify(ShellScope old) => !identical(tabs, old.tabs);
}

/// What a wide or rail shell tells the page headers inside it (D-551): ONE bar per screen.
/// While the shell's top bar is showing, a tab's first page must not draw a second gradient and title under it.
/// A page pushed inside the tab draws its own header, and the shell hides its bar and lends [tools].
class ShellChrome extends InheritedWidget {
  const ShellChrome({super.key, required this.barShown, required this.tools, required super.child});

  /// The shell draws a top bar on this tab's first page.
  final bool barShown;

  /// The app-wide actions (calendar, messages, assistant, bell) for a pushed page's own header.
  final WidgetBuilder? tools;

  static ShellChrome? _of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShellChrome>();

  /// True when this page's header would repeat the shell's bar: it is a tab's first page under the bar.
  static bool ownsHeaderOf(BuildContext context) {
    final s = _of(context);
    if (s == null || !s.barShown) return false;
    final route = ModalRoute.of(context);
    return route == null || route.isFirst;
  }

  /// The app-wide actions a pushed page's header should carry, or null.
  static WidgetBuilder? toolsOf(BuildContext context) => _of(context)?.tools;

  @override
  bool updateShouldNotify(ShellChrome old) => barShown != old.barShown || tools != old.tools;
}

// ─────────────────────────────────────────────────────────────────────────────
// Registry
// ─────────────────────────────────────────────────────────────────────────────

class AppShellNav {
  AppShellNav._();

  static final _shells = <ShellTabs>[];
  static final _fullScreen = <Route<dynamic>>{};

  /// Ticks when a shell's tabs, stacks or chrome change (the floating assistant listens).
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static void register(ShellTabs s) => _shells.add(s);
  static void unregister(ShellTabs s) {
    _shells.remove(s);
    changes.value++;
  }

  /// The pages Back walks through, bottom first (the browser's history, lib/core/routing/web_history.dart): each page
  /// of [rootRoutes] and, right above a page that draws a role shell, the pages of its visible tab above the tab's own
  /// first page (nested shells too). Dialogs, sheets and menus are not pages.
  static List<Route<dynamic>> pageStack(List<Route<dynamic>> rootRoutes) {
    final out = <Route<dynamic>>[];
    void walk(Iterable<Route<dynamic>> routes, int depth) {
      for (final r in routes) {
        if (r is! PageRoute) continue;
        out.add(r);
        final s = _shellIn(r);
        final tab = s?.active;
        if (tab != null && depth < 4) walk(tab.routes.skip(1), depth + 1);
      }
    }

    walk(rootRoutes, 0);
    return out;
  }

  /// The tab a role shell drawn in [route] shows, when it is not the shell's first (home) tab: its key
  /// ('my_courses'), else null.
  static String? tabOf(Route<dynamic> route) {
    final s = _shellIn(route);
    final label = s?.active?.label;
    if (s == null || label == null || label == s.homeLabel) return null;
    return label;
  }

  /// The shell drawn in [route], if any.
  static ShellTabs? _shellIn(Route<dynamic>? route) {
    if (route == null) return null;
    for (final s in _shells.reversed) {
      if (identical(s.hostRoute, route)) return s;
    }
    return null;
  }

  /// The innermost shell the person sees, from the root navigator's top route (null: a page covers every shell).
  static ShellTabs? visibleShell([Route<dynamic>? rootTop]) {
    var r = rootTop ?? topRouteObserver.rootRoute;
    ShellTabs? found;
    for (var depth = 0; depth < 4; depth++) {
      final s = _shellIn(r);
      if (s == null) break;
      found = s;
      final t = s.active?.top;
      if (t == null || t.isFirst) break;
      r = t;
    }
    return found;
  }

  /// The route the person sees: the root navigator's top, or the top page of the visible tab inside it. A tab at its
  /// root page reports the shell's own route (e.g. '/dashboard').
  static Route<dynamic>? effectiveTop(Route<dynamic>? rootTop) {
    var r = rootTop;
    for (var depth = 0; depth < 4; depth++) {
      final s = _shellIn(r);
      final t = s?.active?.top;
      if (t == null || t.isFirst) return r;
      r = t;
    }
    return r;
  }

  /// Where a deep link / notification tap pushes: the visible tab's navigator when a shell is on screen (the bar
  /// stays), else null (the caller uses the root navigator).
  static NavigatorState? pushTarget() => visibleShell()?.active?.navigator;

  /// The visible tab of the shell [context] is in (its chrome or one of its pages), else the nearest navigator.
  static NavigatorState navigatorFor(BuildContext context) =>
      ShellScope.maybeOf(context)?.active?.navigator ?? Navigator.of(context);

  /// Back to the root page of the visible tab (a deep link to "home").
  static void popVisibleToRoot() => visibleShell()?.popActiveToRoot();

  /// After a deep link switched the dashboard's tab (AppNavigator.requestedTab): once the switch is drawn, the tab
  /// shows its own first page.
  static void popVisibleToRootAfterSwitch() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => popVisibleToRoot());

  /// Height of the bottom bar on screen (0: none — rail, sidebar, a full-screen page, a page above the shell).
  /// Width of the sidebar / rail on screen at the start side (0: none).
  static double sideChromeWidth() {
    final s = visibleShell();
    if (s == null || s.fullScreen) return 0;
    return s.sideChrome;
  }

  static double bottomBarHeight() {
    final s = visibleShell();
    if (s == null || s.fullScreen) return 0;
    return s.bottomBar;
  }

  /// Call from a page's build: while its route is the visible tab's top, the shell draws no chrome (the same as
  /// wrapping the page in [ShellFullScreen]; forgotten by itself when the page leaves its tab).
  static void markFullScreen(BuildContext context) {
    final r = ModalRoute.of(context);
    if (r != null) _markFullScreen(r, true);
  }

  /// A route left its navigator (topRouteObserver for the root one): nothing to remember about it.
  static void forgetRoute(Route<dynamic> r) => _fullScreen.remove(r);

  static void _markFullScreen(Route<dynamic> r, bool on) {
    final changed = on ? _fullScreen.add(r) : _fullScreen.remove(r);
    if (!changed) return;
    for (final s in List.of(_shells)) {
      s._notifySoon();
    }
  }
}

/// Wrap a page that must take the whole screen even when it was opened inside a tab (video player, exam sitting,
/// pre-join): while its route is the visible tab's top, the shell draws no bar, rail or sidebar. Outside a shell
/// it does nothing.
class ShellFullScreen extends StatefulWidget {
  const ShellFullScreen({super.key, required this.child});
  final Widget child;

  @override
  State<ShellFullScreen> createState() => _ShellFullScreenState();
}

class _ShellFullScreenState extends State<ShellFullScreen> {
  Route<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = ModalRoute.of(context);
    if (identical(r, _route)) return;
    if (_route != null) AppShellNav._markFullScreen(_route!, false);
    _route = r;
    if (r != null) AppShellNav._markFullScreen(r, true);
  }

  @override
  void dispose() {
    if (_route != null) AppShellNav._markFullScreen(_route!, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
