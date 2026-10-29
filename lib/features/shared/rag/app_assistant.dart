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

/// Kill-switch id (admin "Features" page / theme disable list).
const appAssistantFeatureKey = 'rag.app_assistant';

/// Routes where the bubble never shows (no account yet).
const appAssistantHiddenRoutes = {'/login', '/register', '/otp', '/forgot-password', '/splash'};

/// The bubble's size: a 48 dp touch target (Material / WCAG), drawn as a calm 44 dp disc inside it.
const appAssistantBubbleSize = 48.0;
const _edge = 12.0;

/// Kept free above the bottom tab bar / safe area: where pages put their primary buttons (sticky bars, FABs).
const appAssistantBottomClear = 72.0;

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
  /// it or presses send ("Ask about this page" on the terms / privacy pages, D-084).
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

/// The bubble's remembered place, independent of the window size: a side and where it sits in the band (0 = top).
class AppAssistantSpot {
  const AppAssistantSpot({required this.left, required this.fraction});

  final bool left;
  final double fraction;

  /// The default: the start side (floating action buttons sit at the end), two thirds down.
  static AppAssistantSpot fallback({required bool rtl}) => AppAssistantSpot(left: !rtl, fraction: 0.72);

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
  bool _menu = false; // the long-press menu is open
  bool _everOpened = false; // the chat stays mounted after the first open (an answer being prepared is kept)
  final _panelOverlay = GlobalKey<OverlayState>();

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
        final bubble = allowed && onPage && !open && !prefs.bubbleHidden;
        if (!available) _everOpened = false;
        if (open) _everOpened = true;
        if (!bubble) {
          _drag = null;
          _menu = false;
        }
        final org = appAssistantOrg(isOrg: mode.isOrg, orgId: mode.currentOrgId, entry: mode.current);
        if (open && AppAssistant.draft.value != null && !_draftScheduled) _takeDraft(org);
        return Stack(fit: StackFit.expand, children: [
          widget.child,
          if (allowed && _everOpened) _panel(context, open, org),
          if (bubble) ..._bubbleLayer(context),
        ]);
      },
    );
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
    // default: the start side on a phone (FABs sit at the end); the end side beside a sidebar / rail
    final spot = AppAssistantPrefs.instance.spot ?? AppAssistantSpot.fallback(rtl: side > 0 ? !rtl : rtl);
    final rest = spot.toOffset(mq.size, pad, band);
    final pos = _drag ?? rest;
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
        child: GestureDetector(
          onPanStart: (_) => setState(() {
            _menu = false;
            _drag = pos;
          }),
          onPanUpdate: (d) => setState(() => _drag = (_drag ?? pos) + d.delta),
          onPanEnd: (_) => drop(),
          onPanCancel: () => setState(() => _drag = null),
          onLongPress: () {
            HapticFeedback.selectionClick();
            setState(() => _menu = true);
          },
          onSecondaryTap: () => setState(() => _menu = true),
          child: AnimatedScale(
            scale: over ? 0.82 : (_drag != null ? 1.08 : 1),
            duration: reduce ? Duration.zero : const Duration(milliseconds: 160),
            child: AppAssistantBubble(onTap: () {
              setState(() => _menu = false);
              AppAssistant.openPanel();
            }),
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

  Widget _panel(BuildContext context, bool open, (int, String)? org) {
    final mq = MediaQuery.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final screen = Size(mq.size.width, mq.size.height - mq.viewInsets.bottom);
    final r = appAssistantPanelRect(screen, mq.padding.copyWith(bottom: mq.viewInsets.bottom > 0 ? 0 : mq.padding.bottom), rtl: rtl);
    final wide = mq.size.width >= 700;
    return Offstage(
      offstage: !open,
      child: TickerMode(
        enabled: open,
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
                child: Overlay(key: _panelOverlay, initialEntries: [
                  OverlayEntry(
                    maintainState: true,
                    builder: (context) {
                      // a new key per organization: the history is that organization's
                      final scope = 'app_assistant_${org?.$1}';
                      final chat = _chats.putIfAbsent(scope, GlobalKey<RagChatViewState>.new);
                      return Column(children: [
                        AppAssistantHeader(
                            onClose: _close,
                            onExpand: () => _expand(org),
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
                ]),
              ),
            ),
          ),
        ]),
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
  /// server).
  void _expand((int, String)? org) {
    _close();
    final scope = 'app_assistant_${org?.$1}';
    widget.navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) => RagChatScreen(
            app: true,
            orgId: org?.$1,
            conversationId: _chats[scope]?.currentState?.conversationId ?? _conversation[scope],
            title: org == null ? null : t('مساعد التطبيق · ${org.$2}', 'App assistant · ${org.$2}'))));
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
    return Material(
      color: c.primary,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 4, 6),
        child: Row(children: [
          const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(t('مساعد التطبيق', 'App assistant'),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              if (sub != null) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 11.5)),
            ]),
          ),
          if (onNewChat != null)
            IconButton(tooltip: 'rag_new_chat'.tr, visualDensity: VisualDensity.compact, onPressed: onNewChat, icon: const Icon(Icons.add_comment_outlined, color: Colors.white, size: 20)),
          if (onChats != null)
            IconButton(tooltip: 'rag_chats'.tr, visualDensity: VisualDensity.compact, onPressed: onChats, icon: const Icon(Icons.history_rounded, color: Colors.white, size: 20)),
          IconButton(tooltip: t('ملء الشاشة', 'Full screen'), visualDensity: VisualDensity.compact, onPressed: onExpand, icon: const Icon(Icons.open_in_full_rounded, color: Colors.white, size: 20)),
          IconButton(tooltip: t('إغلاق', 'Close'), onPressed: onClose, icon: const Icon(Icons.close_rounded, color: Colors.white)),
        ]),
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
