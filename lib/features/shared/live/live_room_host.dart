// Live rooms — the host layer (D-059): the live room (a course session or a meeting) lives ABOVE the app's
// Navigator, so it can shrink to a small draggable box while the person moves around the app and come back
// full-screen with one tap. Everything about the room (the LiveKit connection, the recorder, chat, hands, timers)
// stays mounted the whole time: minimizing only hides the page (Offstage, focus excluded) and shows
// the box built by [LiveRoomSession.mini].
//
//   LiveRoomLayer  — sits in MaterialApp.builder around the Navigator (main.dart). Draws the open room full-screen
//                    inside its own nested Navigator — the room's dialogs and sheets land there, above the app,
//                    and `Navigator.of(context, rootNavigator: true)` from inside the room is that navigator — or,
//                    minimized, the box. One room at a time.
//   LiveRoomHost   — the static controller: open / minimize / expand / close / leave, and the Android or browser
//                    back button ([installBackHandler], registered before runApp so it is asked BEFORE WidgetsApp:
//                    full-screen, back closes the room's own dialog or sheet, else minimizes — leaving is an
//                    explicit End; minimized, back works on the app as usual).
//   LiveRoomScope  — what the room page reads: `LiveRoomScope.maybeOf(context)` is null when the page was pushed
//                    as a plain route (older callers, tests), else minimize / expand / close / bindLeave.
//
// Pure, unit-tested: [liveMiniSize], [liveMiniSnap], [liveMiniDefault]. Signing out closes the room.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../design/app_notice.dart' show appNoticeTopOverlay;
import '../../auth/auth_provider.dart';

/// What [LiveRoomHost.open] needs: the full-screen page and the content of the minimized box.
class LiveRoomSession {
  LiveRoomSession({required this.page, required this.mini, this.title = ''});

  /// The room page (RoomPage); built once, kept mounted until [LiveRoomHost.close].
  final Widget page;

  /// Builds the box's content (video, name, buttons); it may read [LiveRoomScope.maybeOf] to expand or leave.
  final WidgetBuilder mini;

  final String title;
}

/// Returned by [LiveRoomHost.open]: when the room is minimized and when it closed.
class LiveRoomHandle {
  LiveRoomHandle._(this._room);
  final _ActiveRoom _room;

  /// Completes when the room is closed ([LiveRoomHost.close]) or replaced by another room.
  Future<void> get closed => _room.closed.future;

  ValueListenable<bool> get minimized => _room.minimized;
}

class _ActiveRoom {
  _ActiveRoom(this.session);
  final LiveRoomSession session;
  final navKey = GlobalKey<NavigatorState>();
  final minimized = ValueNotifier<bool>(false);
  final closed = Completer<void>();
  VoidCallback? leave;
}

class LiveRoomHost {
  LiveRoomHost._();

  static final ValueNotifier<_ActiveRoom?> _active = ValueNotifier<_ActiveRoom?>(null);
  static int _layers = 0;
  static bool _backInstalled = false;

  /// Notifies when a room opens or closes (not on minimize: see [LiveRoomHandle.minimized]).
  static Listenable get listenable => _active;

  static bool get isOpen => _active.value != null;

  static bool get isMinimized => _active.value?.minimized.value ?? false;

  /// The open room's "in the box" flag (null when no room is open): the room page stops its decorative loops
  /// while it is minimized (D27).
  static ValueListenable<bool>? get minimizedListenable => _active.value?.minimized;

  /// What waits in the open room (unread chat, new hands, lobby and share requests; live_attention.dart): the
  /// minimized box draws it as a badge. The room page keeps it current; it goes back to 0 when the room closes.
  static final ValueNotifier<int> attention = ValueNotifier<int>(0);

  /// A [LiveRoomLayer] is in the tree — callers fall back to pushing the room as a route otherwise.
  static bool get isInstalled => _layers > 0;

  /// Shows [session] full-screen. A room already open is closed first (its page disposes, which leaves it).
  static LiveRoomHandle open(LiveRoomSession session) {
    final prev = _active.value;
    final room = _ActiveRoom(session);
    _active.value = room;
    if (prev != null) _finish(prev);
    return LiveRoomHandle._(room);
  }

  /// To the box. The room's own dialogs and sheets are closed first (they would be invisible in the box).
  static void minimize() {
    final room = _active.value;
    if (room == null || room.minimized.value) return;
    room.navKey.currentState?.popUntil((r) => r.isFirst);
    room.minimized.value = true;
  }

  static void expand() => _active.value?.minimized.value = false;

  /// Unmounts the page (its dispose leaves the room) and completes [LiveRoomHandle.closed].
  static void close() {
    final room = _active.value;
    if (room == null) return;
    _active.value = null;
    _finish(room);
  }

  static void _finish(_ActiveRoom room) {
    room.leave = null;
    attention.value = 0;
    if (!room.closed.isCompleted) room.closed.complete();
  }

  /// The room page binds what the box's hang-up button does (its End flow, confirmation included).
  static void bindLeave(VoidCallback? onLeave) => _active.value?.leave = onLeave;

  static void leave() => _active.value?.leave?.call();

  /// The back button while a room is full-screen: its own dialog / sheet first, else minimize. False when no
  /// room is open or it is minimized — the app handles it then.
  static Future<bool> handleBack() async {
    final room = _active.value;
    if (room == null || room.minimized.value) return false;
    final nav = room.navKey.currentState;
    if (nav != null && await nav.maybePop()) return true;
    minimize();
    return true;
  }

  /// Registers the back-button observer. Call BEFORE runApp: WidgetsBinding asks observers in registration
  /// order and WidgetsApp (which pops the app's navigator) registers in its initState.
  static void installBackHandler() {
    if (_backInstalled) return;
    _backInstalled = true;
    WidgetsBinding.instance.addObserver(_LiveRoomBackObserver());
  }

  /// Where notices go while the room is full-screen: its own navigator's overlay, above the room's sheets and
  /// dialogs (the app's root overlay is painted under the room). Null when no room covers the app.
  static OverlayState? noticeOverlay() {
    final room = _active.value;
    if (room == null || room.minimized.value) return null;
    return room.navKey.currentState?.overlay;
  }

  /// Tests: forget everything.
  @visibleForTesting
  static void reset() {
    final room = _active.value;
    _active.value = null;
    if (room != null) _finish(room);
  }
}

class _LiveRoomBackObserver with WidgetsBindingObserver {
  @override
  Future<bool> didPopRoute() => LiveRoomHost.handleBack();
}

/// Marks the subtree of a hosted room; the page reads it to minimize / close instead of popping.
class LiveRoomScope extends InheritedWidget {
  const LiveRoomScope({super.key, required super.child});

  /// Null when the page was pushed as a plain route. No dependency is registered (the scope never changes).
  static LiveRoomScope? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<LiveRoomScope>();

  bool get minimized => LiveRoomHost.isMinimized;

  void minimize() => LiveRoomHost.minimize();

  void expand() => LiveRoomHost.expand();

  void close() => LiveRoomHost.close();

  void bindLeave(VoidCallback? onLeave) => LiveRoomHost.bindLeave(onLeave);

  @override
  bool updateShouldNotify(LiveRoomScope oldWidget) => false;
}

// ── Pure geometry of the box ──────────────────────────────────────────────────────────────────────────────────

const double liveMiniEdge = 12;

/// The box: 16:10, about two fifths of a phone's width, never narrower than 150 nor wider than 240.
Size liveMiniSize(Size screen) {
  final w = (screen.width * 0.42).clamp(150.0, 240.0);
  return Size(w, (w * 0.625).roundToDouble());
}

/// Where a box dropped with its top-left at [pos] ends up: against the nearer side, inside the safe area, never
/// off-screen.
Offset liveMiniSnap(Offset pos, Size screen, EdgeInsets padding, Size box) {
  final minY = padding.top + liveMiniEdge;
  final maxY = screen.height - padding.bottom - box.height - liveMiniEdge;
  final y = maxY < minY ? minY : pos.dy.clamp(minY, maxY);
  final left = pos.dx + box.width / 2 < screen.width / 2;
  final x = left ? padding.left + liveMiniEdge : screen.width - padding.right - box.width - liveMiniEdge;
  return Offset(x < 0 ? 0 : x, y);
}

/// The first place of the box: the end side, above a bottom navigation bar.
Offset liveMiniDefault(Size screen, EdgeInsets padding, Size box, {required bool rtl}) => liveMiniSnap(
      Offset(rtl ? 0 : screen.width, screen.height - padding.bottom - box.height - 96),
      screen,
      padding,
      box,
    );

// ── The layer ─────────────────────────────────────────────────────────────────────────────────────────────────

class LiveRoomLayer extends StatefulWidget {
  const LiveRoomLayer({super.key, required this.child});
  final Widget child;

  @override
  State<LiveRoomLayer> createState() => _LiveRoomLayerState();
}

class _LiveRoomLayerState extends State<LiveRoomLayer> {
  Offset? _pos; // the box's top-left; null = the default place
  bool _dragging = false;
  bool _wasSignedIn = false;

  @override
  void initState() {
    super.initState();
    LiveRoomHost._layers++;
    appNoticeTopOverlay = LiveRoomHost.noticeOverlay;
  }

  @override
  void dispose() {
    LiveRoomHost._layers--;
    if (LiveRoomHost._layers == 0 && appNoticeTopOverlay == LiveRoomHost.noticeOverlay) appNoticeTopOverlay = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Signing out (true → false; a guest never was signed in) ends the room. Deferred: not during build.
    final signedIn = context.watch<MyAuthProvider?>()?.isAuthenticated ?? false;
    if (_wasSignedIn && !signedIn && LiveRoomHost.isOpen) scheduleMicrotask(LiveRoomHost.close);
    _wasSignedIn = signedIn;
    return ValueListenableBuilder<_ActiveRoom?>(
      valueListenable: LiveRoomHost._active,
      builder: (context, room, child) {
        if (room == null) return child!;
        return ValueListenableBuilder<bool>(
          valueListenable: room.minimized,
          builder: (context, minimized, _) => Stack(fit: StackFit.expand, children: [
            child!,
            Positioned.fill(
              child: ExcludeFocus(
                excluding: minimized,
                child: Offstage(
                  offstage: minimized,
                  // no TickerMode: the room's own dialog finishes its pop while offstage, and nothing is painted
                  child: Builder(
                    builder: (_) => LiveRoomScope(
                      // its own navigator (dialogs, sheets); HeroControllerScope.none: the app's HeroController
                      // belongs to the app's Navigator alone
                      child: HeroControllerScope.none(
                        child: Navigator(
                          key: room.navKey,
                          onGenerateRoute: (settings) =>
                              MaterialPageRoute<void>(settings: settings, builder: (_) => room.session.page),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (minimized) _box(context, room),
          ]),
        );
      },
      child: widget.child,
    );
  }

  Widget _box(BuildContext context, _ActiveRoom room) {
    final mq = MediaQuery.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final box = liveMiniSize(mq.size);
    final raw = _pos ?? liveMiniDefault(mq.size, mq.padding, box, rtl: rtl);
    final pos = _dragging ? raw : liveMiniSnap(raw, mq.size, mq.padding, box); // a resized window keeps it on screen
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      width: box.width,
      height: box.height,
      child: GestureDetector(
        key: const ValueKey('live_room.mini_box'),
        onPanStart: (_) => setState(() => _dragging = true),
        onPanUpdate: (d) => setState(() => _pos = (_pos ?? pos) + d.delta),
        onPanEnd: (_) => setState(() {
          _dragging = false;
          _pos = liveMiniSnap(_pos ?? pos, mq.size, mq.padding, box);
        }),
        onPanCancel: () => setState(() => _dragging = false),
        child: TweenAnimationBuilder<double>(
          key: ValueKey(room),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          builder: (_, v, c) => Opacity(opacity: v, child: Transform.scale(scale: 0.85 + 0.15 * v, child: c)),
          child: LiveRoomScope(child: Builder(builder: room.session.mini)),
        ),
      ),
    );
  }
}
