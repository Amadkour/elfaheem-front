// lib/features/shared/records/record_guest_page.dart — where a guest link to a VIDEO lands, straight to the player:
//   /s/record/g_<secret>   a recording shared with a guest (D-315) or by its open guest link (D-842)
//   /s/video/v_<secret>    a course session's video shared with guests (D-841, [GuestMediaKind.video])
// main.dart's router sends both here before the share-link page and outside _Guard, signed in or not.
// No account: the page calls ONLY the public guest routes with auth: false (RemoteGuestRecordApi /
// RemoteGuestVideoApi), and while it is open a stray 401 elsewhere never redirects to the login page
// (GuestLinkVisit, D-840). View only: the card, then Play → a short-lived signed stream in a plain player (play /
// pause, scrub, ±10 s), no download, and the window is screen-protected like the course player (ScreenSecurity,
// D-083). A signed-out guest sees the soft "create an account / sign in" card under it (GuestLinkCta, D-844).
// The body is the plain-values [GuestRecordView] (test/ui/records_guests_layout_test.dart,
// test/ui/guest_share_layout_test.dart).
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/guest_link_visit.dart';
import '../../../core/screen_security.dart';
import '../../admin/admin_common.dart' show t;
import '../../auth/auth_provider.dart';
import '../guest/guest_link_cta.dart';
import 'package:flutter_education_app/features/sessions/material/material_guest_links_api.dart' show RemoteGuestVideoApi;
import 'records_guests_api.dart';
import 'records_guests_parts.dart';

/// What a guest link plays: a Records item (`g_`) or a course session's video (`v_`).
enum GuestMediaKind { record, video }

class GuestRecordPage extends StatefulWidget {
  const GuestRecordPage({super.key, required this.token, this.api, this.kind = GuestMediaKind.record, this.signedIn});
  final String token;
  final GuestRecordApi? api;
  final GuestMediaKind kind;

  /// Tests: whether the soft sign-up card shows (default: read from MyAuthProvider; no provider = signed out).
  final bool? signedIn;

  @override
  State<GuestRecordPage> createState() => _GuestRecordPageState();
}

class _GuestRecordPageState extends State<GuestRecordPage> {
  late final GuestRecordApi _api =
      widget.api ?? (widget.kind == GuestMediaKind.video ? RemoteGuestVideoApi() : RemoteGuestRecordApi());
  GuestRecordCard? _card;
  String? _error;
  VideoPlayerController? _player;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    GuestLinkVisit.enter(this);
    unawaited(ScreenSecurity.instance.protect(this)); // view only: no screenshots / recordings (D-083)
    _load();
  }

  @override
  void dispose() {
    _player?.dispose();
    unawaited(ScreenSecurity.instance.release(this));
    GuestLinkVisit.leave(this);
    super.dispose();
  }

  bool get _signedIn {
    if (widget.signedIn != null) return widget.signedIn!;
    try {
      return context.read<MyAuthProvider>().isAuthenticated;
    } catch (_) {
      return false; // no provider above (tests / previews)
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final c = await _api.card(widget.token);
      if (mounted) setState(() => _card = c);
    } catch (e) {
      if (mounted) setState(() => _error = guestRecordErrorText(e));
    }
  }

  Future<void> _play() async {
    if (_starting) return;
    final at = _player?.value.position;
    setState(() => _starting = true);
    try {
      final p = await _api.play(widget.token);
      final ctl = VideoPlayerController.networkUrl(Uri.parse(p.url));
      await ctl.initialize();
      if (at != null) await ctl.seekTo(at);
      await ctl.play();
      final old = _player;
      if (!mounted) {
        await ctl.dispose();
        return;
      }
      setState(() {
        _player = ctl;
        _starting = false;
      });
      await old?.dispose();
    } catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      showAppNotice(guestRecordErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = _player;
    return Scaffold(
      key: const ValueKey('records.guest'),
      backgroundColor: c.background,
      appBar: AppHeader(
          title: widget.kind == GuestMediaKind.video ? t('فيديو', 'Video') : t('تسجيل', 'Recording'),
          showBack: Navigator.of(context).canPop()),
      body: SafeArea(
        child: SingleChildScrollView(
          child: GuestRecordView(
            card: _card,
            error: _error,
            starting: _starting,
            onPlay: _play,
            onRetry: _load,
            player: p == null ? null : _GuestPlayer(controller: p, onReload: _play),
            footer: _signedIn
                ? null
                : GuestLinkCta(
                    onRegister: () => openGuestSignUp(context, '/register'),
                    onSignIn: () => openGuestSignUp(context, '/login'),
                  ),
          ),
        ),
      ),
    );
  }
}

/// A plain player: the picture, tap to play / pause, a scrub bar and ±10 s. A stream that stops (the signed URL
/// expired) asks for a fresh one at the same place.
class _GuestPlayer extends StatelessWidget {
  const _GuestPlayer({required this.controller, required this.onReload});
  final VideoPlayerController controller;
  final VoidCallback onReload;

  void _skip(int s) {
    final to = controller.value.position + Duration(seconds: s);
    controller.seekTo(to < Duration.zero ? Duration.zero : to);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, v, _) => Directionality(
        textDirection: TextDirection.ltr, // media controls run left → right in every language (D-312)
        child: Stack(fit: StackFit.expand, children: [
          GestureDetector(
            onTap: () => v.isPlaying ? controller.pause() : controller.play(),
            child: Center(child: AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(controller))),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ColoredBox(
              color: c.heroShade.withValues(alpha: 0.72),
              child: Row(children: [
                IconButton(
                  tooltip: v.isPlaying ? t('إيقاف مؤقت', 'Pause') : t('تشغيل', 'Play'),
                  icon: Icon(v.hasError ? Icons.refresh_rounded : (v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded), color: c.onHero),
                  onPressed: v.hasError ? onReload : () => v.isPlaying ? controller.pause() : controller.play(),
                ),
                IconButton(
                  tooltip: t('رجوع 10 ثوانٍ', 'Back 10 s'),
                  icon: Icon(Icons.replay_10_rounded, color: c.onHero),
                  onPressed: () => _skip(-10),
                ),
                IconButton(
                  tooltip: t('تقديم 10 ثوانٍ', 'Forward 10 s'),
                  icon: Icon(Icons.forward_10_rounded, color: c.onHero),
                  onPressed: () => _skip(10),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                    child: VideoProgressIndicator(controller, allowScrubbing: true,
                        colors: VideoProgressColors(playedColor: c.primary, bufferedColor: c.onHeroMuted, backgroundColor: c.heroGlass)),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
