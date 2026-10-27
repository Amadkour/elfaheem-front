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
// The bubble can be dragged; it sticks to the nearer side. [appAssistantPanelRect] (where the pop-up goes),
// [appAssistantSnap] (where a dropped bubble ends up) and [appAssistantOrg] (which organization the chat follows)
// are pure and unit-tested.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/shared/guest/guest_state.dart';
import 'package:flutter_education_app/utils/top_route_observer.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show asMap, asStr, t;
import 'rag_chat_screen.dart';

/// Kill-switch id (admin "Features" page / theme disable list).
const appAssistantFeatureKey = 'rag.app_assistant';

/// Routes where the bubble never shows (no account yet).
const appAssistantHiddenRoutes = {'/login', '/register', '/otp', '/forgot-password', '/splash'};

const _bubble = 54.0;
const _edge = 12.0;

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
}

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

/// Where a bubble dropped at [pos] (its top-left) ends up: against the nearer side, inside the safe area.
Offset appAssistantSnap(Offset pos, Size screen, EdgeInsets padding) {
  final minY = padding.top + _edge;
  final maxY = screen.height - padding.bottom - _bubble - _edge;
  final y = maxY < minY ? minY : pos.dy.clamp(minY, maxY);
  final left = pos.dx + _bubble / 2 < screen.width / 2;
  return Offset(left ? padding.left + _edge : screen.width - padding.right - _bubble - _edge, y);
}

class AppAssistantHost extends StatefulWidget {
  const AppAssistantHost({super.key, required this.navigatorKey, required this.child});
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<AppAssistantHost> createState() => _AppAssistantHostState();
}

class _AppAssistantHostState extends State<AppAssistantHost> {
  Offset? _pos; // the bubble's top-left; null = the default place
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
    final mode = AppModeController.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([topRouteObserver.topRoute, AppAssistant.hiddenBy, AppAssistant.open, GuestState.instance, mode]),
      builder: (context, _) {
        final route = topRouteObserver.topRoute.value;
        final available = signedIn && !GuestState.active && !AppConfig.disableList.contains(appAssistantFeatureKey);
        final onPage = route == null || route is PageRoute;
        final visible = available &&
            AppAssistant.hiddenBy.value == 0 &&
            !appAssistantHiddenRoutes.contains(route?.settings.name);
        final open = visible && AppAssistant.open.value;
        if (!available) _everOpened = false;
        if (open) _everOpened = true;
        final org = appAssistantOrg(isOrg: mode.isOrg, orgId: mode.currentOrgId, entry: mode.current);
        return Stack(fit: StackFit.expand, children: [
          widget.child,
          if (visible && _everOpened) _panel(context, open, org),
          if (visible && onPage && !open) _bubbleAt(context),
        ]);
      },
    );
  }

  Widget _bubbleAt(BuildContext context) {
    final mq = MediaQuery.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // default: the start side (floating action buttons sit at the end), above a bottom navigation bar
    final pos = _pos ??
        appAssistantSnap(Offset(rtl ? mq.size.width : 0, mq.size.height * 0.68), mq.size, mq.padding);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _pos = (_pos ?? pos) + d.delta),
        onPanEnd: (_) => setState(() => _pos = appAssistantSnap(_pos ?? pos, mq.size, mq.padding)),
        child: _Bubble(onTap: () => AppAssistant.open.value = true),
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

class _Bubble extends StatelessWidget {
  const _Bubble({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // no Tooltip: the bubble sits above the Navigator, where there is no Overlay
    return Semantics(
      button: true,
      label: t('مساعد التطبيق', 'App assistant'),
      child: Material(
        color: c.primary,
        shape: const CircleBorder(),
        elevation: 6,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox(width: _bubble, height: _bubble, child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26)),
        ),
      ),
    );
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
