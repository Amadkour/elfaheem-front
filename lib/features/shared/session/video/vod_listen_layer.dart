// The host of the listen-only bar (D-104), in MaterialApp.builder (main.dart) around the floating assistant, the
// banners and the live-room layer: while a lecture plays as sound, the bar sits at the very top of the app and
// everything else (pages, dialogs, the assistant bubble, the live room's box) is laid out BELOW it, so nothing
// covers it and it covers nothing. The app below keeps its slot (keyed), so showing or hiding the bar never
// rebuilds the Navigator.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../../../design/app_shell_nav.dart' show AppShellNav;
import '../../../auth/auth_provider.dart';
import 'video_player_screen.dart';
import 'vod_listen.dart';
import 'vod_listen_bar.dart';

class VodListenLayer extends StatelessWidget {
  const VodListenLayer({super.key, required this.navigatorKey, required this.child});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  /// Tests: whether someone is signed in (the real one reads MyAuthProvider).
  @visibleForTesting
  static bool Function(BuildContext context)? debugSignedIn;

  void _expand() {
    final s = VodListenSession.instance;
    final nav = AppShellNav.pushTarget() ?? navigatorKey.currentState;
    if (nav == null) return;
    final h = s.takeBack();
    if (h == null) return;
    nav.push(MaterialPageRoute<void>(
      builder: (_) => VideoPlayerScreen(material: h.current, playlist: h.playlist, resume: h),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = debugSignedIn?.call(context) ?? context.select<MyAuthProvider, bool>((a) => a.isAuthenticated);
    final s = VodListenSession.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final h = s.handoff;
        if (h != null && !signedIn) {
          // Signing out stops the lecture (nobody's sound keeps going on the login page).
          WidgetsBinding.instance.addPostFrameCallback((_) => s.stop());
        }
        final show = h != null && signedIn;
        // Laid out bottom-up so the bar is PAINTED after the app: a route's modal barrier (BlockSemantics) drops
        // the semantics of everything painted before the Navigator, which left the bar's buttons unreachable for
        // screen readers and dead on the web while semantics are on.
        return Column(verticalDirection: VerticalDirection.up, children: [
          Expanded(
            key: const ValueKey('vod_listen_app'),
            // The bar already covers the status bar: the pages below must not add it a second time.
            child: MediaQuery.removePadding(context: context, removeTop: show, child: child),
          ),
          if (show)
            _Entrance(
              key: ObjectKey(h),
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: h.controller,
                builder: (_, v, _) {
                  final total = v.duration;
                  final buffered = total > Duration.zero && v.buffered.isNotEmpty
                      ? v.buffered.last.end.inMilliseconds / total.inMilliseconds
                      : 0.0;
                  return VodListenBar(
                    title: h.material.name,
                    position: v.position,
                    duration: total,
                    buffered: buffered,
                    playing: v.isPlaying,
                    busy: s.switching || (v.isBuffering && v.isPlaying) || !v.isInitialized,
                    speed: h.speed,
                    onPlayPause: s.togglePlay,
                    onSeekBy: s.seekBy,
                    onSeekTo: s.seekToFraction,
                    onExpand: _expand,
                    onClose: () => s.stop(),
                  );
                },
              ),
            ),
        ]);
      },
    );
  }
}

/// The bar slides down into place (no motion with Reduce motion).
class _Entrance extends StatelessWidget {
  const _Entrance({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? 1 : 0, end: 1),
      duration: still ? Duration.zero : const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (_, t, child) => ClipRect(
        child: Align(alignment: Alignment.bottomCenter, heightFactor: t, child: child),
      ),
    );
  }
}
