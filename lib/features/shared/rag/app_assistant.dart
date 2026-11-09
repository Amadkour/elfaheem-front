// The floating app assistant: a small bubble above every screen of a signed-in user that opens the app assistant
// (RagChatView with `app: true` — answers from the platform's own documents) in a pop-up, without leaving the page.
// While the person is in Organization mode (AppModeController) the chat is opened with that organization too
// (D-012): it then answers about the app AND about the organization's rules and documents, and the header says so.
//
// [AppAssistantHost] sits in MaterialApp.builder, above the Navigator, so the pop-up has its own Material and
// Overlay (text fields, tooltips) and pushes the full-screen chat through the app's navigator key. It is hidden:
//   • for guests and before sign-in, on the auth routes, and while a dialog / sheet is on top;
//   • by the kill-switch `rag.app_assistant` (AppConfig.disableList);
//   • while a full-screen experience asks for it ([AppAssistant.hide] / [AppAssistant.release]: video player, live
//     room, exam sitting).
// The person decides about the BUBBLE (remembered per user on this device, [AppAssistantPrefs]):
//   • at rest it is a slim tab docked flush against the END side (titles and labels start at the other one), so it
//     covers as little of the page as it can ([appAssistantDockX], [AppAssistantEdgeTab]): its visible face stays
//     inside the page gutter + a card's inner padding ([appAssistantTabFace]), so a card's trailing figures (a score,
//     a percent, an amount) are never under it, on any page and at any scroll position; while the person scrolls
//     it slides out of the way and comes back a moment after the scroll stops (no taps land on it meanwhile);
//   • drag it to any height of either side — it snaps to the nearer side, above the role's bottom tab bar and the
//     strip where pages keep their primary buttons, below the app bar ([appAssistantSnap]);
//   • drag it onto the "×" target that appears at the bottom, or long-press / right-click it → "Hide button": it is
//     gone, a one-time notice says the assistant stays in Settings;
//   • every role's settings / More page has "App assistant" (opens the pop-up directly) and the switch "Floating
//     assistant button" ([AppAssistantOpenTile], [AppAssistantBubbleTile]); the desktop / tablet top bar has the
//     [AppAssistantIcon].
// Pure, unit-tested: [appAssistantPanelRect] (where the pop-up goes), [appAssistantSnap] (where a dropped bubble
// ends up), [appAssistantOverDismiss] (dropped on the hide target), [AppAssistantSpot] (the remembered place),
// [appAssistantOrg] (which organization the chat follows), [appAssistantPrefKey].
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_notice.dart' show showAppNotice;
import 'package:flutter_education_app/design/app_settings.dart';
import 'package:flutter_education_app/design/app_shell_nav.dart' show AppShellNav;
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/shared/guest/guest_state.dart';
import 'package:flutter_education_app/utils/top_route_observer.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../admin/admin_common.dart' show asMap, asStr, t;
import 'rag_chat_screen.dart';
import 'package:flutter_education_app/design/app_gradients.dart';

/// Kill-switch id (admin "Features" page / theme disable list).
const appAssistantFeatureKey = 'rag.app_assistant';

/// Routes where the bubble never shows (no account yet).
const appAssistantHiddenRoutes = {'/login', '/register', '/otp', '/forgot-password', '/splash'};

/// The bubble's size: a 48 dp touch target (Material / WCAG), drawn as a calm 44 dp disc inside it.
const appAssistantBubbleSize = 48.0;
const _edge = 12.0;

/// Kept free above the bottom tab bar / safe area: where pages put their primary buttons (sticky bars, FABs).
const appAssistantBottomClear = 72.0;

/// The docked tab (the bubble at rest): a 44 x 52 touch target flush against the screen edge (H9: the 60 dp
/// free-floating disc covered far more of the page).
const appAssistantTabWidth = 44.0;
const appAssistantTabHeight = 52.0;

/// What is DRAWN of the docked tab, from the screen edge: the page gutter (16) + 10 dp, i.e. inside the padding of a
/// card (12–16 dp) or a list tile (16 dp) — never over its text. The rest of the 44 dp target is transparent. Round 3
/// of the paper-exam e2e: the 44 dp face sat on the first result card's score and percent at 390 px.
const appAssistantTabFace = 26.0;

/// What stays visible of the tab while the person scrolls (it slides out and takes no taps).
const appAssistantTuckedPeek = 6.0;

/// How long after a scroll stops the tab comes back.
const appAssistantReturnDelay = Duration(milliseconds: 900);

class AppAssistant {
  AppAssistant._();

  /// How many full-screen pages asked to hide the bubble.
  static final ValueNotifier<int> hiddenBy = ValueNotifier<int>(0);

  /// Whether the pop-up is open.
  static final ValueNotifier<bool> open = ValueNotifier<bool>(false);

  /// Call from a full-screen page's initState (video, live room, exam); pair it with [release] in dispose.
  /// Deferred: pages call it while the Navigator builds, where notifying the host would throw.
  static void hide() => scheduleMicrotask(() {
        hiddenBy.value++;
        open.value = false;
      });

  static void release() => scheduleMicrotask(() {
        if (hiddenBy.value > 0) hiddenBy.value--;
      });

  /// Opens the pop-up (settings tile, top-bar icon), whether or not the bubble is shown.
  static void openPanel() => open.value = true;

  /// A question waiting to be typed into the pop-up's box (see [ask]); the host takes it once the chat is mounted.
  static final ValueNotifier<String?> draft = ValueNotifier<String?>(null);

  /// Opens the pop-up on a NEW chat with [question] already typed in the box, not sent — the person reads it, edits
  /// it or presses send ("Ask about this page" on the terms / privacy pages, D-088).
  static void ask(String question) {
    draft.value = question;
    open.value = true;
  }

  /// Whether the assistant exists for this person right now (signed in, not a guest, not switched off).
  static bool availableFor(BuildContext context) =>
      context.read<MyAuthProvider>().isAuthenticated &&
      !GuestState.active &&
      !AppConfig.disableList.contains(appAssistantFeatureKey);
}

// ─────────────────────────────────────────────────────────────────────────────
// Pure helpers
// ─────────────────────────────────────────────────────────────────────────────

/// The organization the app assistant follows: (id, name) while the person is in Organization mode with one open,
/// else null (the app alone). Pure over the controller's values.
(int, String)? appAssistantOrg({required bool isOrg, int? orgId, Map<String, dynamic>? entry}) {
  if (!isOrg || orgId == null) return null;
  return (orgId, asStr(asMap(entry?['organization'])['name']));
}

/// Where the pop-up goes in a [screen] (already without the keyboard): a corner card on a wide window, almost the
/// whole screen on a phone. [padding] is the safe-area padding.
Rect appAssistantPanelRect(Size screen, EdgeInsets padding, {required bool rtl}) {
  if (screen.width >= 700 && screen.height >= 520) {
    final w = 420.0;
    final h = (screen.height - padding.vertical - 32).clamp(300.0, 680.0);
    final left = rtl ? 16.0 + padding.left : screen.width - w - 16 - padding.right;
    return Rect.fromLTWH(left, screen.height - padding.bottom - 16 - h, w, h);
  }
  final top = padding.top + 8;
  return Rect.fromLTRB(8 + padding.left, top, screen.width - 8 - padding.right, screen.height - padding.bottom - 8);
}

/// The band a bubble may sit in, top to bottom: below the status bar + [topClear] (the app bar's actions), above
/// the bottom tab bar ([bottomBar], 0 without one) or the safe area, and [bottomClear] (primary buttons).
(double, double) appAssistantBand(Size screen, EdgeInsets padding,
    {double bottomBar = 0, double topClear = 0, double bottomClear = 0, double size = appAssistantBubbleSize}) {
  final minY = padding.top + topClear + _edge;
  final maxY = screen.height - math.max(padding.bottom, bottomBar) - bottomClear - size - _edge;
  return maxY < minY ? (minY, minY) : (minY, maxY);
}

/// Where a bubble dropped at [pos] (its top-left) ends up: against the nearer side, inside [appAssistantBand].
Offset appAssistantSnap(Offset pos, Size screen, EdgeInsets padding,
    {double bottomBar = 0, double topClear = 0, double bottomClear = 0, double size = appAssistantBubbleSize}) {
  final (minY, maxY) = appAssistantBand(screen, padding,
      bottomBar: bottomBar, topClear: topClear, bottomClear: bottomClear, size: size);
  final y = pos.dy.clamp(minY, maxY);
  final left = pos.dx + size / 2 < screen.width / 2;
  return Offset(left ? padding.left + _edge : screen.width - padding.right - size - _edge, y);
}

/// The hide target's centre: bottom middle, above the bottom bar / safe area.
Offset appAssistantDismissCenter(Size screen, EdgeInsets padding, {double bottomBar = 0}) =>
    Offset(screen.width / 2, screen.height - math.max(padding.bottom, bottomBar) - 88);

/// True when a bubble whose centre is at [center] was dropped on the hide target.
bool appAssistantOverDismiss(Offset center, Offset target, {double radius = 56}) => (center - target).distance <= radius;

/// The docked tab's left edge on a [screen]: flush against the chosen side, inside [padding] (safe area + the role
/// shell's sidebar); [tucked] slides it out until only [appAssistantTuckedPeek] of its face shows.
double appAssistantDockX(Size screen, EdgeInsets padding, {required bool left, bool tucked = false}) {
  const hide = appAssistantTabFace - appAssistantTuckedPeek;
  return left
      ? padding.left - (tucked ? hide : 0)
      : screen.width - padding.right - appAssistantTabWidth + (tucked ? hide : 0);
}

/// The bubble's remembered place, independent of the window size: a side and where it sits in the band (0 = top).
class AppAssistantSpot {
  const AppAssistantSpot({required this.left, required this.fraction});

  final bool left;
  final double fraction;

  /// The default: the END side (titles, labels and form fields start at the other one; the band already keeps the
  /// floating action buttons' strip free), low in the band.
  /// On a [wide] window (no role shell around the page: the shell's top bar has its own entry, see
  /// [appAssistantEdgeTabShown]) it sits at the very bottom of the band, the bottom END corner above the strip kept
  /// for primary buttons, where wide pages leave their content gutter — not beside asides and counters (R3).
  static AppAssistantSpot fallback({required bool rtl, bool wide = false}) =>
      AppAssistantSpot(left: rtl, fraction: wide ? 1.0 : 0.86);

  /// From a snapped top-left inside the band.
  static AppAssistantSpot fromOffset(Offset snapped, Size screen, (double, double) band) {
    final (minY, maxY) = band;
    final f = maxY <= minY ? 0.0 : ((snapped.dy - minY) / (maxY - minY)).clamp(0.0, 1.0);
    return AppAssistantSpot(left: snapped.dx + appAssistantBubbleSize / 2 < screen.width / 2, fraction: f);
  }

  Offset toOffset(Size screen, EdgeInsets padding, (double, double) band) {
    final (minY, maxY) = band;
    final x = left ? padding.left + _edge : screen.width - padding.right - appAssistantBubbleSize - _edge;
    return Offset(x, minY + (maxY - minY) * fraction);
  }

  String encode() => '${left ? 'l' : 'r'}:${fraction.toStringAsFixed(3)}';

  static AppAssistantSpot? decode(String? s) {
    if (s == null) return null;
    final parts = s.split(':');
    if (parts.length != 2 || (parts[0] != 'l' && parts[0] != 'r')) return null;
    final f = double.tryParse(parts[1]);
    if (f == null) return null;
    return AppAssistantSpot(left: parts[0] == 'l', fraction: f.clamp(0.0, 1.0));
  }
}

/// Whether the floating edge tab is drawn. Never while a role shell's top bar is on screen ([sideChrome] > 0: the
/// desktop sidebar or the tablet rail): that bar already carries the assistant button next to the calendar and the
/// bell, and a second entry docked on the page edge sat on the course page's aside chevrons and the month view's
/// counts (R3). The phone's bottom-bar shell has no top-bar entry, so the tab stays there.
bool appAssistantEdgeTabShown({required double sideChrome}) => sideChrome <= 0;

/// Device-local preference keys, per signed-in user.
String appAssistantPrefKey(String what, int userId) => 'app_assistant.$what.$userId';

// ─────────────────────────────────────────────────────────────────────────────
// Preferences (per user, on this device)
// ─────────────────────────────────────────────────────────────────────────────

class AppAssistantPrefs extends ChangeNotifier {
  AppAssistantPrefs._();
  static final instance = AppAssistantPrefs._();

  int? _user;
  bool _bubbleHidden = false;
  bool _noticeShown = false;
  AppAssistantSpot? _spot;

  bool get bubbleHidden => _bubbleHidden;
  AppAssistantSpot? get spot => _spot;

  /// Loads the choices of [userId] (null: nobody signed in — the bubble shows). Safe to call from a build.
  void bind(int? userId) {
    if (userId == _user) return;
    _user = userId;
    _bubbleHidden = false;
    _noticeShown = false;
    _spot = null;
    if (userId == null) {
      scheduleMicrotask(notifyListeners);
      return;
    }
    unawaited(_load(userId));
  }

  Future<void> _load(int uid) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (_user != uid) return;
      _bubbleHidden = p.getBool(appAssistantPrefKey('bubble_hidden', uid)) ?? false;
      _noticeShown = p.getBool(appAssistantPrefKey('hide_notice', uid)) ?? false;
      _spot = AppAssistantSpot.decode(p.getString(appAssistantPrefKey('spot', uid)));
    } catch (_) {/* storage unavailable: defaults */}
    notifyListeners();
  }

  Future<void> _save(void Function(SharedPreferences p, int uid) write) async {
    final uid = _user;
    if (uid == null) return;
    try {
      write(await SharedPreferences.getInstance(), uid);
    } catch (_) {}
  }

  /// Shows / hides the floating button. Hiding tells the person once where the assistant is now.
  Future<void> setBubbleHidden(bool hidden, {bool explain = true}) async {
    if (_bubbleHidden == hidden) return;
    _bubbleHidden = hidden;
    notifyListeners();
    await _save((p, uid) => p.setBool(appAssistantPrefKey('bubble_hidden', uid), hidden));
    if (hidden && explain && !_noticeShown) {
      _noticeShown = true;
      showAppNotice('assistant_bubble_hidden'.tr, icon: Icons.auto_awesome_rounded, duration: const Duration(seconds: 5));
      await _save((p, uid) => p.setBool(appAssistantPrefKey('hide_notice', uid), true));
    }
  }

  void setSpot(AppAssistantSpot s) {
    _spot = s;
    unawaited(_save((p, uid) => p.setString(appAssistantPrefKey('spot', uid), s.encode())));
  }

  /// Tests.
  @visibleForTesting
  void debugReset() {
    _user = null;
    _bubbleHidden = false;
    _noticeShown = false;
    _spot = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Host
// ─────────────────────────────────────────────────────────────────────────────

class AppAssistantHost extends StatefulWidget {
  const AppAssistantHost({super.key, required this.navigatorKey, required this.child});
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<AppAssistantHost> createState() => _AppAssistantHostState();
}

class _AppAssistantHostState extends State<AppAssistantHost> {
  Offset? _drag; // the bubble's top-left while it is being dragged
  bool _scrollTuck = false; // the person is scrolling: the tab slides out of the way
  Timer? _tuckTimer;
  bool _menu = false; // the long-press menu is open
  bool _everOpened = false; // the chat stays mounted after the first open (an answer being prepared is kept)
  bool _wasOpen = false; // the pop-up was open at the last build (a new open checks the chat it shows, N6)
  final _panelNav = GlobalKey<NavigatorState>();

  /// The organization the chat follows, as of the last build. The pop-up's Navigator builds its one route once, so
  /// its page must read this field, never a value captured when the route was made: that kept the first scope after
  /// an Organization / Individual switch until the panel was rebuilt (and then jumped to another scope's chat).
  (int, String)? _org;

  // Chat sessions (Track E.5): the current conversation per scope key (`app_assistant_<org id>`) while the host is
  // alive — a scope that was never opened resumes its latest chat; null = the person started a new chat there.
  final _conversation = <String, int?>{};
  final _chats = <String, GlobalKey<RagChatViewState>>{};
  bool _sessions = false; // the server has chat sessions: New chat / Chats in the header

  @override
  Widget build(BuildContext context) {
    final signedIn = context.select<MyAuthProvider, bool>((a) => a.isAuthenticated);
    final userId = context.select<MyAuthProvider, int?>((a) => a.isAuthenticated ? a.currentUser?.id : null);
    final prefs = AppAssistantPrefs.instance..bind(userId);
    final mode = AppModeController.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        topRouteObserver.topRoute,
        AppAssistant.hiddenBy,
        AppAssistant.open,
        AppAssistant.draft,
        GuestState.instance,
        mode,
        prefs,
        AppShellNav.changes,
      ]),
      builder: (context, _) {
        final route = topRouteObserver.topRoute.value;
        final available = signedIn && !GuestState.active && !AppConfig.disableList.contains(appAssistantFeatureKey);
        final onPage = route == null || route is PageRoute;
        final allowed = available &&
            AppAssistant.hiddenBy.value == 0 &&
            !appAssistantHiddenRoutes.contains(route?.settings.name);
        final open = allowed && AppAssistant.open.value;
        final bubble = allowed &&
            onPage &&
            !open &&
            !prefs.bubbleHidden &&
            appAssistantEdgeTabShown(sideChrome: AppShellNav.sideChromeWidth());
        if (!available) _everOpened = false;
        final org = appAssistantOrg(isOrg: mode.isOrg, orgId: mode.currentOrgId, entry: mode.current);
        _org = org;
        // opened again on a chat that ended on a failure: a new chat with the starter questions instead (N6)
        if (open && !_wasOpen && _everOpened) {
          final chat = _chats['app_assistant_${org?.$1}'];
          WidgetsBinding.instance.addPostFrameCallback((_) => chat?.currentState?.reopened());
        }
        _wasOpen = open;
        if (open) _everOpened = true;
        if (!bubble) {
          _drag = null;
          _menu = false;
        }
        if (open && AppAssistant.draft.value != null && !_draftScheduled) _takeDraft(org);
        return Stack(fit: StackFit.expand, children: [
          NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.child),
          if (allowed && _everOpened) _panel(context, open),
          // N2: the tab, the bubble, its menu and the hide target take no keyboard focus. They leave the tree in the
          // very frame a tap opens the pop-up; on the web the browser then hands the focus back to the view, whose
          // initial-focus search measures every traversable node (FocusNode.rect) — and the tab's InkWell node, parked
          // under its old focus parent while its element waits to be unmounted, has no render tree to measure ("Null
          // check operator" in getTransformTo). The keys matter: without them the pop-up, which takes this slot the
          // first time it opens, reused this ExcludeFocus (switched to focusable) as the parked node's parent.
          // Keyboard users have the shell's top-bar button and Settings → App assistant.
          if (bubble)
            ExcludeFocus(
              key: const ValueKey('app_assistant.bubble'),
              child: Stack(fit: StackFit.expand, children: _bubbleLayer(context)),
            ),
        ]);
      },
    );
  }

  @override
  void dispose() {
    _tuckTimer?.cancel();
    super.dispose();
  }

  /// A user's vertical scroll anywhere under the host tucks the tab away; it comes back a moment after the scroll
  /// stops. Programmatic scrolls (auto-playing sliders) never send a user direction, so they leave it alone.
  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is UserScrollNotification) {
      if (n.direction != ScrollDirection.idle) {
        _tuckTimer?.cancel();
        if (!_scrollTuck && _drag == null) setState(() => _scrollTuck = true);
      } else {
        _scheduleReturn();
      }
    } else if (n is ScrollEndNotification) {
      _scheduleReturn();
    }
    return false;
  }

  void _scheduleReturn() {
    if (!_scrollTuck) return;
    _tuckTimer?.cancel();
    _tuckTimer = Timer(appAssistantReturnDelay, () {
      if (mounted && _scrollTuck) setState(() => _scrollTuck = false);
    });
  }

  List<Widget> _bubbleLayer(BuildContext context) {
    final mq = MediaQuery.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final bar = AppShellNav.bottomBarHeight();
    // the role shell's sidebar / rail (start side) and its 64 px top bar count as edges: never over them
    final side = AppShellNav.sideChromeWidth();
    final pad = mq.padding + EdgeInsets.only(left: rtl ? 0 : side, right: rtl ? side : 0);
    final topClear = side > 0 ? 64.0 : kToolbarHeight;
    final band = appAssistantBand(mq.size, pad, bottomBar: bar, topClear: topClear, bottomClear: appAssistantBottomClear);
    // default: the end side, docked (see the header)
    final spot = AppAssistantPrefs.instance.spot ?? AppAssistantSpot.fallback(rtl: rtl, wide: mq.size.width >= 700);
    final rest = spot.toOffset(mq.size, pad, band);
    final docked = _drag == null;
    final tucked = docked && _scrollTuck && !_menu;
    final dockLeft = rest.dx + appAssistantBubbleSize / 2 < mq.size.width / 2;
    final dock = Offset(appAssistantDockX(mq.size, pad, left: dockLeft, tucked: tucked),
        rest.dy - (appAssistantTabHeight - appAssistantBubbleSize) / 2);
    final pos = _drag ?? dock;
    final target = appAssistantDismissCenter(mq.size, mq.padding, bottomBar: bar);
    const half = appAssistantBubbleSize / 2;
    final over = _drag != null && appAssistantOverDismiss(_drag! + const Offset(half, half), target);
    final reduce = MediaQuery.of(context).disableAnimations;
    final dur = reduce ? Duration.zero : const Duration(milliseconds: 220);

    void drop() {
      final d = _drag;
      if (d == null) return;
      if (appAssistantOverDismiss(d + const Offset(half, half), target)) {
        HapticFeedback.mediumImpact();
        setState(() => _drag = null);
        AppAssistantPrefs.instance.setBubbleHidden(true);
        return;
      }
      final snapped = appAssistantSnap(d, mq.size, pad, bottomBar: bar, topClear: topClear, bottomClear: appAssistantBottomClear);
      AppAssistantPrefs.instance.setSpot(AppAssistantSpot.fromOffset(snapped, mq.size, band));
      setState(() => _drag = null);
    }

    return [
      // the hide target, only while dragging (chat heads)
      if (_drag != null)
        Positioned.fill(
          child: IgnorePointer(child: AppAssistantDismissTarget(center: target, active: over)),
        ),
      if (_menu)
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _menu = false),
            child: const SizedBox.expand(),
          ),
        ),
      AnimatedPositioned(
        duration: _drag != null ? Duration.zero : dur,
        curve: Curves.easeOutCubic,
        left: pos.dx,
        top: pos.dy,
        child: IgnorePointer(
          ignoring: tucked,
          child: GestureDetector(
          onPanStart: (_) => setState(() {
            _menu = false;
            _scrollTuck = false;
            _drag = Offset(rest.dx, pos.dy);
          }),
          onPanUpdate: (d) => setState(() => _drag = (_drag ?? pos) + d.delta),
          onPanEnd: (_) => drop(),
          onPanCancel: () => setState(() => _drag = null),
          onLongPress: () {
            HapticFeedback.selectionClick();
            setState(() => _menu = true);
          },
          onSecondaryTap: () => setState(() => _menu = true),
          child: docked
              ? AppAssistantEdgeTab(
                  onLeftSide: dockLeft,
                  onTap: () {
                    setState(() => _menu = false);
                    AppAssistant.openPanel();
                  })
              : AnimatedScale(
                  scale: over ? 0.82 : 1.08,
                  duration: reduce ? Duration.zero : const Duration(milliseconds: 160),
                  child: AppAssistantBubble(onTap: () => AppAssistant.openPanel()),
                ),
          ),
        ),
      ),
      if (_menu)
        _menuAt(context, pos, onLeftSide: pos.dx + half < mq.size.width / 2),
    ];
  }

  Widget _menuAt(BuildContext context, Offset bubble, {required bool onLeftSide}) {
    const w = 208.0;
    final mq = MediaQuery.of(context);
    final top = (bubble.dy + appAssistantBubbleSize / 2 - 52).clamp(mq.padding.top + 8, mq.size.height - 120.0);
    final left = onLeftSide ? bubble.dx + appAssistantBubbleSize + 8 : bubble.dx - w - 8;
    return Positioned(
      left: left.clamp(8.0, mq.size.width - w - 8),
      top: top,
      width: w,
      child: AppAssistantBubbleMenu(
        onOpen: () {
          setState(() => _menu = false);
          AppAssistant.openPanel();
        },
        onHide: () {
          setState(() => _menu = false);
          AppAssistantPrefs.instance.setBubbleHidden(true);
        },
      ),
    );
  }

  Widget _panel(BuildContext context, bool open) {
    final mq = MediaQuery.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final screen = Size(mq.size.width, mq.size.height - mq.viewInsets.bottom);
    final r = appAssistantPanelRect(screen, mq.padding.copyWith(bottom: mq.viewInsets.bottom > 0 ? 0 : mq.padding.bottom), rtl: rtl);
    final wide = mq.size.width >= 700;
    // A closed pop-up stays mounted (an answer being prepared is kept) but leaves the focus order (N2): its nodes sit
    // beside the Navigator, in the view's own focus scope, so Tab, the browser handing focus back to the page and
    // reading-order traversal would otherwise measure them (FocusNode.rect) while they are hidden. Its own traversal
    // group keeps Tab inside the open card in reading order without sorting it against the rest of the app.
    return ExcludeFocus(
      key: const ValueKey('app_assistant.panel'),
      excluding: !open,
      child: Offstage(
      offstage: !open,
      child: TickerMode(
        enabled: open,
        child: FocusTraversalGroup(
        child: Stack(children: [
          if (!wide) Positioned.fill(child: GestureDetector(onTap: _close, child: ColoredBox(color: Colors.black.withValues(alpha: 0.35)))),
          Positioned.fromRect(
            rect: r,
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              child: Material(
                color: context.colors.background,
                elevation: 12,
                clipBehavior: Clip.antiAlias,
                borderRadius: BorderRadius.circular(context.colors.radiusLarge),
                // its own Navigator (not a bare Overlay): the chat's sheets and dialogs (Chats, rename, feedback) need
                // one, and the app's Navigator is below this layer, not above it (no heroes: the app's controller
                // belongs to the app's Navigator)
                child: HeroControllerScope.none(
                  child: Navigator(
                  key: _panelNav,
                  onGenerateRoute: (_) => PageRouteBuilder<void>(
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                    pageBuilder: (context, _, _) {
                      // a new key per organization: the history is that organization's. [_org], not a captured value:
                      // this route is made once, its page is rebuilt with every build of the host
                      final org = _org;
                      final scope = 'app_assistant_${org?.$1}';
                      final chat = _chats.putIfAbsent(scope, GlobalKey<RagChatViewState>.new);
                      return Column(children: [
                        AppAssistantHeader(
                            onClose: _close,
                            onExpand: _expand,
                            orgName: org?.$2,
                            onNewChat: _sessions ? () => chat.currentState?.newChat() : null,
                            onChats: _sessions ? () => chat.currentState?.showSessions() : null),
                        Expanded(
                            child: RagChatView(
                                key: chat,
                                app: true,
                                orgId: org?.$1,
                                compact: true,
                                contextLabel: org?.$2,
                                initialConversationId: _conversation[scope],
                                resumeLatest: !_conversation.containsKey(scope),
                                onConversationChanged: (id) => _conversation[scope] = id,
                                onSessionsSupported: (s) {
                                  if (s != _sessions && mounted) setState(() => _sessions = s);
                                },
                                onNavigate: _close)),
                      ]);
                    },
                  ),
                  ),
                ),
              ),
            ),
          ),
        ]),
        ),
      ),
      ),
    );
  }

  void _close() {
    FocusManager.instance.primaryFocus?.unfocus();
    AppAssistant.open.value = false;
  }

  bool _draftScheduled = false;

  /// Hands [AppAssistant.draft] to the chat of [org]'s scope once it is mounted (the first open builds it this frame).
  void _takeDraft((int, String)? org, [int tries = 0]) {
    _draftScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final text = AppAssistant.draft.value;
      if (!mounted || text == null) {
        _draftScheduled = false;
        return;
      }
      final chat = _chats['app_assistant_${org?.$1}']?.currentState;
      if (chat == null) {
        if (tries < 20) {
          _takeDraft(org, tries + 1);
          WidgetsBinding.instance.scheduleFrame();
        } else {
          _draftScheduled = false;
        }
        return;
      }
      _draftScheduled = false;
      AppAssistant.draft.value = null;
      chat.draft(text);
    });
  }

  /// Full screen: the same chat as a page, on the pop-up's current conversation (its messages come back from the
  /// server) — or on a NEW chat when the pop-up is on one (never the latest conversation instead), with the unsent
  /// question moved along. Back from the page, the pop-up follows the conversation the page ended on and gets the
  /// page's unsent text back.
  void _expand() {
    final org = _org;
    final scope = 'app_assistant_${org?.$1}';
    final chat = _chats[scope]?.currentState;
    final id = chat != null ? chat.conversationId : _conversation[scope];
    final draft = chat?.takeDraft() ?? '';
    _close();
    widget.navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) => RagChatScreen(
            app: true,
            orgId: org?.$1,
            conversationId: id,
            resumeLatest: id != null,
            draft: draft,
            title: org == null ? null : t('مساعد التطبيق · ${org.$2}', 'App assistant · ${org.$2}'),
            onClosed: (conversationId, text) {
              if (!mounted) return;
              _conversation[scope] = conversationId;
              _chats[scope]?.currentState?.resumeFrom(conversationId, text);
            })));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Presentational parts (plain values: the layout harness pumps them)
// ─────────────────────────────────────────────────────────────────────────────

/// The bubble: a calm surface disc with the assistant's mark, a hairline primary ring and a soft tinted shadow.
class AppAssistantBubble extends StatelessWidget {
  const AppAssistantBubble({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // no Tooltip: the bubble sits above the Navigator, where there is no Overlay
    return Semantics(
      button: true,
      label: 'assistant_entry_title'.tr,
      hint: 'assistant_bubble_hide'.tr,
      child: SizedBox(
        width: appAssistantBubbleSize,
        height: appAssistantBubbleSize,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: c.primary.withValues(alpha: c.isDark ? 0.30 : 0.22), blurRadius: 14, offset: const Offset(0, 4)),
              ],
            ),
            child: Material(
              color: c.cardBg,
              shape: CircleBorder(side: BorderSide(color: c.primary.withValues(alpha: c.isDark ? 0.45 : 0.22))),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (r) => c.accentGradient.createShader(r),
                      child: const Icon(Icons.auto_awesome_rounded, size: 22),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bubble at rest: a slim tab docked flush against the screen edge ([onLeftSide]: the left edge), rounded on
/// the page side only, with the assistant's mark. A 44 x 52 touch target whose drawn face is [appAssistantTabFace]
/// wide at the screen edge (gutter + a card's padding), the rest transparent: it never hides a card's text.
class AppAssistantEdgeTab extends StatelessWidget {
  const AppAssistantEdgeTab({super.key, required this.onLeftSide, required this.onTap});
  final bool onLeftSide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const r = Radius.circular(appAssistantTabHeight / 2);
    final radius = onLeftSide ? const BorderRadius.horizontal(right: r) : const BorderRadius.horizontal(left: r);
    final ring = c.primary.withValues(alpha: c.isDark ? 0.45 : 0.22);
    return Semantics(
      button: true,
      label: 'assistant_entry_title'.tr,
      hint: 'assistant_bubble_hide'.tr,
      child: SizedBox(
        width: appAssistantTabWidth,
        height: appAssistantTabHeight,
        // the whole 44 dp target takes the tap; only the face at the screen edge is drawn
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Align(
            alignment: onLeftSide ? Alignment.centerLeft : Alignment.centerRight,
            child: SizedBox(
              key: const ValueKey('app_assistant.tab_face'),
              width: appAssistantTabFace,
              height: appAssistantTabHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(color: c.primary.withValues(alpha: c.isDark ? 0.28 : 0.18), blurRadius: 12, offset: const Offset(0, 3)),
                  ],
                ),
                child: Material(
                  color: c.cardBg,
                  shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: ring)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onTap,
                    child: Padding(
                      // the mark sits a little toward the page, away from the screen edge
                      padding: EdgeInsets.only(left: onLeftSide ? 2 : 0, right: onLeftSide ? 0 : 2),
                      child: Center(
                        child: ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (r) => c.accentGradient.createShader(r),
                          child: const Icon(Icons.auto_awesome_rounded, size: 18),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The long-press / right-click menu: open the assistant, or hide the button (Settings brings it back).
class AppAssistantBubbleMenu extends StatelessWidget {
  const AppAssistantBubbleMenu({super.key, required this.onOpen, required this.onHide});
  final VoidCallback onOpen, onHide;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget row(IconData icon, String label, VoidCallback onTap, {Color? color}) => InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Icon(icon, size: 20, color: color ?? c.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: AppFonts.family, fontSize: 14, fontWeight: FontWeight.w600, color: c.textDark)),
                ),
              ]),
            ),
          ),
        );
    return Material(
      color: c.cardBg,
      elevation: 8,
      shadowColor: c.primary.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(c.radiusLarge),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          row(Icons.auto_awesome_rounded, 'assistant_bubble_open'.tr, onOpen, color: c.isDark ? c.accent : c.primary),
          Divider(height: 1, indent: 16, endIndent: 16, color: c.divider.withValues(alpha: 0.6)),
          row(Icons.visibility_off_rounded, 'assistant_bubble_hide'.tr, onHide, color: c.textMedium),
        ]),
      ),
    );
  }
}

/// The hide target shown at the bottom while the bubble is dragged: a soft scrim, a ring with "×" and a hint;
/// it grows and turns to the danger colour when the bubble is over it.
class AppAssistantDismissTarget extends StatelessWidget {
  const AppAssistantDismissTarget({super.key, required this.center, required this.active});
  final Offset center;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduce = MediaQuery.of(context).disableAnimations;
    final dur = reduce ? Duration.zero : const Duration(milliseconds: 160);
    final size = active ? 68.0 : 56.0;
    // above the Navigator: no Material of its own, so the label would get the debug text style
    return Material(type: MaterialType.transparency, child: Stack(children: [
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              stops: const [0, 0.35],
              colors: [c.textDark.withValues(alpha: 0.22), c.textDark.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
      Positioned(
        left: center.dx - 120,
        width: 240,
        top: center.dy - 34,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 68,
            child: Center(
              child: AnimatedContainer(
                duration: dur,
                curve: Curves.easeOutBack,
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? c.danger : c.cardBg,
                  border: Border.all(color: active ? c.danger : c.divider, width: 1.5),
                  boxShadow: c.cardShadow,
                ),
                child: Icon(Icons.close_rounded, size: active ? 30 : 26, color: active ? c.onHero : c.textMedium),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(999), boxShadow: c.cardShadow),
            child: Text(active ? 'assistant_bubble_drop'.tr : 'assistant_bubble_drag'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, fontWeight: FontWeight.w600, color: c.textDark)),
          ),
        ]),
      ),
    ]));
  }
}

/// The pop-up's header: the assistant's name, the organization it follows (when one is open), New chat and Chats
/// (chat sessions, when the server has them), expand and close.
class AppAssistantHeader extends StatelessWidget {
  const AppAssistantHeader({super.key, required this.onClose, required this.onExpand, this.orgName, this.onNewChat, this.onChats});
  final VoidCallback onClose, onExpand;
  final String? orgName;
  final VoidCallback? onNewChat, onChats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sub = orgName == null || orgName!.isEmpty ? null : t('يجيب عن التطبيق وعن $orgName', 'About the app and $orgName');
    return AppMeshSurface(
      child: Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 4, 6),
        child: Row(children: [
          Icon(Icons.auto_awesome_rounded, color: c.onHero, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(t('مساعد التطبيق', 'App assistant'),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.onHero, fontWeight: FontWeight.w700, fontSize: 15)),
              if (sub != null) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.onHeroMuted, fontSize: 11.5)),
            ]),
          ),
          if (onNewChat != null)
            IconButton(tooltip: 'rag_new_chat'.tr, onPressed: onNewChat, icon: Icon(Icons.add_comment_outlined, color: c.onHero, size: 20)),
          if (onChats != null)
            IconButton(tooltip: 'rag_chats'.tr, onPressed: onChats, icon: Icon(Icons.history_rounded, color: c.onHero, size: 20)),
          IconButton(tooltip: t('ملء الشاشة', 'Full screen'), onPressed: onExpand, icon: Icon(Icons.open_in_full_rounded, color: c.onHero, size: 20)),
          IconButton(tooltip: t('إغلاق', 'Close'), onPressed: onClose, icon: Icon(Icons.close_rounded, color: c.onHero)),
        ]),
      ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Entries: settings tiles + the top-bar icon
// ─────────────────────────────────────────────────────────────────────────────

/// "App assistant" row of a settings / More page: opens the pop-up directly (kill switch `rag.app_assistant`).
class AppAssistantOpenTile extends StatelessWidget implements AppSettingsSearchable {
  const AppAssistantOpenTile({super.key, this.color});
  final Color? color;

  @override
  String get searchText =>
      '${'assistant_entry_title'.tr} ${'assistant_entry_sub'.tr} assistant help chat bot ai مساعد مساعدة ذكاء';

  @override
  Widget build(BuildContext context) => AppSettingsTile(
        featureKey: appAssistantFeatureKey,
        icon: Icons.auto_awesome_rounded,
        color: color ?? context.colors.primary,
        label: 'assistant_entry_title'.tr,
        subtitle: 'assistant_entry_sub'.tr,
        onTap: AppAssistant.openPanel,
      );
}

/// "Floating assistant button" switch of a settings / More page (remembered per user on this device).
class AppAssistantBubbleTile extends StatelessWidget implements AppSettingsSearchable {
  const AppAssistantBubbleTile({super.key, this.color});
  final Color? color;

  @override
  String get searchText =>
      '${'assistant_bubble_show'.tr} ${'assistant_bubble_show_sub'.tr} assistant bubble floating button مساعد زر عائم';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppAssistantPrefs.instance,
        builder: (context, _) {
          final shown = !AppAssistantPrefs.instance.bubbleHidden;
          return AppSettingsTile(
            featureKey: appAssistantFeatureKey,
            icon: Icons.chat_bubble_outline_rounded,
            color: color ?? context.colors.accent2,
            label: 'assistant_bubble_show'.tr,
            subtitle: 'assistant_bubble_show_sub'.tr,
            trailing: AppSwitch(
              value: shown,
              onChanged: (v) => AppAssistantPrefs.instance.setBubbleHidden(!v),
              semanticLabel: 'assistant_bubble_show'.tr,
            ),
          );
        },
      );
}

/// The assistant in a top bar (desktop sidebar shell, tablet rail shell), next to the calendar and the bell.
class AppAssistantIcon extends StatelessWidget {
  const AppAssistantIcon({super.key});

  @override
  Widget build(BuildContext context) {
    if (AppConfig.disableList.contains(appAssistantFeatureKey)) return const SizedBox.shrink();
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'assistant_entry_title'.tr,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Material(
          color: c.accent2,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: AppAssistant.openPanel,
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Icon(Icons.auto_awesome_rounded, color: c.onHero, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}
