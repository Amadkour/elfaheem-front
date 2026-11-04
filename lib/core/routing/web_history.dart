// The browser's history follows the app's pages (web only, D-170).
//
// Before: the app ran on Navigator 1's single-entry history. Every page opened inside a role tab (D-081) or pushed
// as a plain MaterialPageRoute left the address bar and the browser's history untouched, so after Home → page 2 →
// page 3 the browser had nothing to go back to and Back left the site.
//
// Now every PAGE the person can go back to (the root navigator's pages, and inside a role shell the visible tab's
// pages, AppShellNav.pageStack) is one browser entry, with its URL (AppRoutes.locationOf; a page without a URL of its
// own keeps the URL of the page under it). Dialogs, sheets and menus are not entries.
//
//   [guard] [page 0] [page 1] … [top]        ← the browser's entries of this page load, `_have`
//
// * The app pushes / pops / replaces a page → the entries are brought in line ([planHistory]: go back over the
//   entries that are gone, replace the top's URL if it changed — a tab switch —, push the new ones).
// * The person presses Back (or jumps back through the history list) → the browser is already on an older entry; the
//   app goes back the same number of pages through the system back ([onBack]: the live room first, then the
//   navigator, whose role shell pops its tab, then goes to the home tab — D-081). A step the app refuses (a "leave the
//   exam?" confirm, a dialog that closed instead) is pushed again, so the browser never runs ahead of the app.
// * The guard is the entry under the first page (the URL the app was opened with, rewritten to the first page's URL).
//   Back from the first page lands on it: one system back (the shell's home tab, a dialog), else the person really
//   leaves and the browser goes one more step back — out of the site, or to an earlier page load of the app.
// * Forward to a page the app has closed re-opens it when it has a URL of its own; an entry of an earlier page load
//   (after a refresh) becomes the new guard and its URL opens ([onOpen]).
//
// Every browser operation runs in one queue, so a push never overtakes a pending `history.go`. The browser's own
// popstate for a `go` the app made arrives as a move to the entry the app is already on, which is a no-op: no flag can
// get out of step. On mobile / desktop this class is never enabled: the hardware back is the system back as before.
import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../design/app_shell_nav.dart' show AppShellNav;
import '../../utils/widget/url_strategy.dart' show browserGo;
import 'app_routes.dart';

/// One browser entry the app made: the page's serial (0 = the guard) and its URL.
@immutable
class HistoryEntry {
  const HistoryEntry(this.serial, this.location);

  final int serial;
  final String location;

  @override
  bool operator ==(Object other) => other is HistoryEntry && other.serial == serial && other.location == location;

  @override
  int get hashCode => Object.hash(serial, location);

  @override
  String toString() => '$serial:$location';
}

/// One step that brings the browser in line with the app.
sealed class HistoryOp {
  const HistoryOp();
}

/// `history.go(delta)` (always back here).
class HistoryGo extends HistoryOp {
  const HistoryGo(this.delta);
  final int delta;

  @override
  bool operator ==(Object other) => other is HistoryGo && other.delta == delta;

  @override
  int get hashCode => delta.hashCode;

  @override
  String toString() => 'go($delta)';
}

/// A new entry on top.
class HistoryPush extends HistoryOp {
  const HistoryPush(this.entry);
  final HistoryEntry entry;

  @override
  bool operator ==(Object other) => other is HistoryPush && other.entry == entry;

  @override
  int get hashCode => entry.hashCode;

  @override
  String toString() => 'push($entry)';
}

/// The current (top) entry gets a new URL.
class HistoryReplace extends HistoryOp {
  const HistoryReplace(this.entry);
  final HistoryEntry entry;

  @override
  bool operator ==(Object other) => other is HistoryReplace && other.entry == entry;

  @override
  int get hashCode => entry.hashCode;

  @override
  String toString() => 'replace($entry)';
}

/// The steps that turn the browser's entries [have] (the browser on the last one) into [want]. Both start with the
/// guard (serial 0). Entries are the same page when their serials match; only the top's URL is rewritten in place (an
/// entry under the top cannot be changed without leaving it).
List<HistoryOp> planHistory(List<HistoryEntry> have, List<HistoryEntry> want) {
  var p = 0;
  while (p < have.length && p < want.length && have[p].serial == want[p].serial) {
    p++;
  }
  final ops = <HistoryOp>[];
  final extra = have.length - p;
  if (extra > 0) ops.add(HistoryGo(-extra));
  if (p > 0 && have[p - 1].location != want[p - 1].location) ops.add(HistoryReplace(want[p - 1]));
  for (var i = p; i < want.length; i++) {
    ops.add(HistoryPush(want[i]));
  }
  return ops;
}

/// Keeps the browser's history in step with the app's pages. A [NavigatorObserver] of the root navigator; the role
/// shells report through [AppShellNav.changes].
class WebHistory extends NavigatorObserver {
  WebHistory._();
  static final WebHistory instance = WebHistory._();

  bool _enabled = false;

  /// The system back: true when something handled it (a page or dialog closed, the shell switched tab).
  Future<bool> Function() onBack = () async => false;

  /// Opens [location] on top of what is shown (Forward to a closed page, an entry of an earlier page load): true when
  /// a page opened or the home switched tab.
  Future<bool> Function(String location) onOpen = (_) async => false;

  /// Turns the sync on (web, once, before the root navigator's first page).
  void enable() {
    if (_enabled) return;
    _enabled = true;
    AppShellNav.changes.addListener(_changed);
  }

  final _root = <Route<dynamic>>[];
  final _serials = Expando<int>('webHistorySerial');
  var _nextSerial = 1;
  int? _adopt;
  final String _sid = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1 << 30).toRadixString(36)}';

  /// The browser's entries of this page load, guard first; the browser is on the last one. Empty until the first sync.
  var _have = <HistoryEntry>[];

  Future<void> _tail = Future<void>.value();
  bool _queued = false;

  NavigatorState? _nav;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // a new root navigator (the app rebuilt it): the old one's routes are gone without a pop
    if (!identical(navigator, _nav)) {
      _nav = navigator;
      _root.clear();
    }
    _root.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _root.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _root.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _root.indexOf(oldRoute);
    if (newRoute != null) {
      if (i >= 0) {
        _root[i] = newRoute;
      } else {
        _root.add(newRoute);
      }
    }
    _changed();
  }

  /// Navigator callbacks run in the middle of a navigation: the sync runs right after, once per burst.
  void _changed() {
    if (!_enabled || _queued) return;
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      _enqueue(_sync);
    });
  }

  void _enqueue(Future<void> Function() op) {
    _tail = _tail.then((_) => op()).catchError((Object e, StackTrace s) {
      debugPrint('[webHistory] $e\n$s');
    });
  }

  int _serialOf(Route<dynamic> r) {
    var s = _serials[r];
    if (s == null) {
      s = _adopt ?? _nextSerial;
      _adopt = null;
      _nextSerial = max(_nextSerial, s + 1);
      _serials[r] = s;
    }
    return s;
  }

  String? _locationOf(Route<dynamic> r) {
    final base = AppRoutes.locationOf(r.settings.name, r.settings.arguments);
    final tab = AppShellNav.tabOf(r); // the role home on another tab than its first
    if (tab != null && base != null && AppRoutes.homes.any((h) => h.path == base)) return AppRoutes.tabLocation(base, tab);
    return base;
  }

  List<Route<dynamic>> _pages() => AppShellNav.pageStack(_root);

  /// The entries the app's pages call for, guard first.
  List<HistoryEntry> _want() {
    final pages = _pages();
    final out = <HistoryEntry>[];
    var loc = _have.isEmpty ? '/' : _have.first.location;
    for (final r in pages) {
      loc = _locationOf(r) ?? loc;
      out.add(HistoryEntry(_serialOf(r), loc));
    }
    return [HistoryEntry(0, out.isEmpty ? loc : out.first.location), ...out];
  }

  Future<void> _report(HistoryEntry e, {bool replace = false}) async {
    // cheap when already selected; a second MaterialApp (the boot splash) selects the single-entry history
    await SystemNavigator.selectMultiEntryHistory();
    await SystemNavigator.routeInformationUpdated(
        uri: Uri.parse(e.location), state: <String, Object>{'sid': _sid, 'nb': e.serial}, replace: replace);
  }

  Future<void> _sync() async {
    if (!_enabled) return;
    final want = _want();
    if (_have.isEmpty) {
      // the first sync: the entry the app was opened on becomes the guard, the pages go on top of it
      await _report(want.first, replace: true);
      _have = [want.first];
      for (final e in want.skip(1)) {
        await _report(e);
        _have.add(e);
      }
      return;
    }
    for (final op in planHistory(_have, want)) {
      switch (op) {
        case HistoryGo(:final delta):
          _have.removeRange(_have.length + delta, _have.length);
          await browserGo(delta);
        case HistoryReplace(:final entry):
          await _report(entry, replace: true);
          _have[_have.length - 1] = entry;
        case HistoryPush(:final entry):
          await _report(entry);
          _have.add(entry);
      }
    }
  }

  /// The browser moved to another entry (Back, Forward, a jump through the history list): the app follows.
  void browserMoved(RouteInformation info) {
    if (!_enabled) return;
    _enqueue(() => _follow(info));
  }

  Future<void> _settle() async {
    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _follow(RouteInformation info) async {
    if (_have.isEmpty) return;
    final st = info.state;
    final ours = st is Map && st['sid'] == _sid;
    final serial = ours ? (st['nb'] as num?)?.toInt() : null;
    final i = serial == null ? -1 : _have.indexWhere((e) => e.serial == serial);
    if (i == _have.length - 1) return; // the entry the app is on: its own `go`, or nothing changed

    if (i >= 0) {
      // Back: the browser is on _have[i], i pages from the bottom (0 = the guard)
      final pagesBefore = _have.length - 1;
      _have.removeRange(i + 1, _have.length);
      final keep = max(i, 1);
      for (var n = 0; n < 40 && _pages().length > keep; n++) {
        final before = _pages().length;
        final handled = await onBack();
        await _settle();
        if (!handled || _pages().length >= before) break; // refused: the entries are pushed again below
      }
      if (i == 0 && pagesBefore == 1) {
        // Back from the first page: the shell's home tab or a dialog, else the person leaves
        final handled = await onBack();
        await _settle();
        if (!handled) {
          if (await browserGo(-1)) return; // out of the app, or to an earlier page load (a move like any other)
        }
      }
      await _sync();
      return;
    }

    final location = _cleanLocation(info.uri);
    final top = _have.last.location;
    if (ours && serial != null && serial > 0) {
      // Forward to a page the app closed since: re-open it when it has a URL of its own, else step back again
      if (location != top && AppRoutes.match(location) != null) {
        _have.add(HistoryEntry(serial, location));
        _adopt = serial;
        final opened = await onOpen(location);
        await _settle();
        _adopt = null;
        if (opened) {
          await _sync();
          return;
        }
        _have.removeLast();
      }
      await browserGo(-1);
      return;
    }

    // An entry of an earlier page load (after a refresh), or one the app did not make. Another page the person may
    // open: it opens, and that entry becomes the guard under it. The page already shown, or one that cannot open: the
    // person is on the way out of the app, so the browser keeps going back (one press, not one per old entry).
    if (location != _want().last.location) {
      _have = [HistoryEntry(0, location)];
      if (await onOpen(location)) {
        await _settle();
        await _sync();
        return;
      }
    }
    if (await browserGo(-1)) return;
    _have = [HistoryEntry(0, location)]; // nowhere further back: the app stays, on this entry
    await _sync();
  }

  static String _cleanLocation(Uri uri) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    return uri.query.isEmpty ? path : '$path?${uri.query}';
  }

  /// Tests: forget everything.
  @visibleForTesting
  void reset() {
    if (_enabled) AppShellNav.changes.removeListener(_changed);
    _enabled = false;
    _root.clear();
    _have = [];
    _nextSerial = 1;
    _adopt = null;
    _tail = Future<void>.value();
  }
}
