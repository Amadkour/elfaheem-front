// "This page is on screen again": a State that mixes in [PageReturnAware] gets [onPageReturn] each time the page that
// holds it becomes the page the person sees AGAIN after another PAGE covered it — a page pushed above it was closed
// (in its own tab's navigator or on the root one, D-081), or its shell tab was switched away and back. It is fed by
// `topRouteObserver.topRoute` (the one place route-dependent work hooks in, CLAUDE.md): no polling timer, nothing on
// the first build, nothing after a dialog / sheet / menu closes (the page was never left).
//
// Use it for a list that something elsewhere can change (round 3 of the paper-exam e2e: the teacher's exam hub kept
// its engine exams after an exam was created from another page).
import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/design/app_shell_nav.dart' show ShellScope, ShellTabs;
import 'package:flutter_education_app/utils/top_route_observer.dart';

/// Whether [top] (the route the person sees, `topRouteObserver.topRoute`) shows the page of [mine]: [mine] itself,
/// or — for a shell tab's first page, which the observer reports as the shell's own route — the [shell]'s route
/// while [mine]'s tab is the active one.
bool pageRouteShown(Route<dynamic>? top, Route<dynamic>? mine, {ShellTabs? shell}) {
  if (top == null || mine == null) return false;
  if (identical(top, mine)) return true;
  if (shell == null || !mine.isFirst || !identical(top, shell.hostRoute)) return false;
  final nav = shell.active?.navigator;
  return nav != null && identical(nav, mine.navigator);
}

mixin PageReturnAware<T extends StatefulWidget> on State<T> {
  Route<dynamic>? _prRoute;
  ShellTabs? _prShell;
  bool _prAway = false;
  bool _prBound = false;

  /// The page is the one on screen again after another page covered it (or its tab was switched back to).
  void onPageReturn();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prRoute = ModalRoute.of(context);
    _prShell = ShellScope.maybeOf(context);
    if (!_prBound) {
      _prBound = true;
      topRouteObserver.topRoute.addListener(_prChanged);
    }
  }

  @override
  void dispose() {
    topRouteObserver.topRoute.removeListener(_prChanged);
    super.dispose();
  }

  void _prChanged() {
    if (!mounted) return;
    final top = topRouteObserver.topRoute.value;
    if (pageRouteShown(top, _prRoute, shell: _prShell)) {
      if (_prAway) {
        _prAway = false;
        onPageReturn();
      }
    } else if (top is PageRoute) {
      _prAway = true;                // a page (or another tab) covers it; a dialog / sheet / menu does not count
    }
  }
}
