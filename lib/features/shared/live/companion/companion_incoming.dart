// lib/features/shared/live/companion/companion_incoming.dart — how a request reaches the phone (D-520).
//
// `CompanionIncoming.instance` runs from start-up on a phone. It asks the server for a pending request on every event
// (`live_companion_request`), push, app resume and sign-in, and whatever is pending is shown at once as the call-style
// prompt, above whatever page is open. The server's row is the only truth, so a late or duplicated push cannot
// ring twice and an expired request cannot ring at all.
library;

import 'dart:async';
import 'dart:developer' show log;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_config.dart';
import '../../../../core/api_client.dart';
import '../../../../core/live/live_events_client.dart';
import '../../../../design/app_notice.dart';
import '../../../../main.dart' show navigatorKey;
import '../../../../utils/live_events.dart';
import '../../../admin/admin_common.dart' show t;
import '../../../auth/auth_provider.dart';
import '../live_room_host.dart' show LiveRoomHost;
import 'companion_core.dart';
import 'companion_link.dart' show companionErrorText;
import 'companion_parts.dart';
import 'companion_platform.dart' as platform;
import 'companion_screen.dart';

class CompanionIncoming with WidgetsBindingObserver {
  CompanionIncoming._();
  static final CompanionIncoming instance = CompanionIncoming._();

  final CompanionApi _api = CompanionApi();
  bool _started = false;
  bool _checking = false;
  int? _showingId;
  VoidCallback? _authListener;

  bool get _off => AppConfig.disableList.contains(kCompanionFeatureKey);

  void start() {
    if (_started || !platform.companionRunsOnPhone()) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    LiveEventsClient.instance.bind();
    LiveEvents.instance.listen({LiveEvents.liveCompanionRequest}, (_) => check());
    WidgetsBinding.instance.addPostFrameCallback((_) => _watchAuth());
    Future<void>.delayed(const Duration(seconds: 2), check);
  }

  void _watchAuth() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      Future<void>.delayed(const Duration(seconds: 1), _watchAuth);
      return;
    }
    final auth = ctx.read<MyAuthProvider>();
    var was = auth.isAuthenticated;
    _authListener = () {
      if (auth.isAuthenticated && !was) unawaited(check());
      was = auth.isAuthenticated;
    };
    auth.addListener(_authListener!);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(check());
  }

  /// The one question: is something pending for me right now? Runs on an event, a push, resume.
  Future<void> check() async {
    if (_checking || _off) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    if (!ctx.read<MyAuthProvider>().isAuthenticated) return;
    _checking = true;
    try {
      final r = await _api.pending();
      if (r != null) _show(r);
    } catch (e) {
      log('[LIVE] companion check: $e');
    } finally {
      _checking = false;
    }
  }

  /// A request arrived through its QR link.
  Future<void> openFromLink(String secret) async {
    final r = await _api.bySecret(secret);
    if (r.pending) {
      _show(r);
    } else {
      showAppNotice(t('انتهى هذا الطلب.', 'This request has ended.'), error: true);
    }
  }

  void _show(CompanionRequest r) {
    if (_showingId == r.id || !r.pending || LiveRoomHost.isOpen) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    _showingId = r.id;
    unawaited(nav
        .push<void>(PageRouteBuilder<void>(
          opaque: true,
          transitionDuration: const Duration(milliseconds: 180),
          settings: const RouteSettings(name: '/live/companion/incoming'),
          pageBuilder: (context, _, _) => _IncomingPage(request: r),
        ))
        .whenComplete(() => _showingId = null));
  }
}

class _IncomingPage extends StatefulWidget {
  const _IncomingPage({required this.request});
  final CompanionRequest request;

  @override
  State<_IncomingPage> createState() => _IncomingPageState();
}

class _IncomingPageState extends State<_IncomingPage> {
  final CompanionApi _api = CompanionApi();
  late int _left = widget.request.expiresIn;
  Timer? _timer;
  StreamSubscription<LiveEvent>? _sub;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_left <= 1) {
        _close(notice: t('انتهت مهلة الطلب.', 'The request expired.'));
      } else {
        setState(() => _left--);
      }
    });
    _sub = LiveEvents.instance.listen({LiveEvents.liveCompanionState}, (e) {
      if ('${e.data['id']}' != '${widget.request.id}' || !mounted) return;
      final status = CompanionStatus.parse(e.data['status']);
      if (status != CompanionStatus.pending && status != CompanionStatus.active && status != CompanionStatus.none) {
        _close();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  void _close({String? notice}) {
    if (!mounted) return;
    _timer?.cancel();
    if (notice != null) showAppNotice(notice);
    Navigator.of(context).pop();
  }

  /// The camera and microphone prompts come with the sentence that explains them; a denial drops that source.
  Future<Set<CompanionSource>> _permissions() async {
    final wanted = {...widget.request.sources};
    if (kIsWeb) return wanted; // the browser asks when the track starts
    final asks = <Permission>[
      if (wanted.contains(CompanionSource.camera)) Permission.camera,
      if (wanted.contains(CompanionSource.microphone)) Permission.microphone,
    ];
    if (asks.isEmpty) return wanted;
    final results = await asks.request();
    if (results[Permission.camera]?.isGranted == false) wanted.remove(CompanionSource.camera);
    if (results[Permission.microphone]?.isGranted == false) wanted.remove(CompanionSource.microphone);
    return wanted;
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      final allowed = await _permissions();
      if (allowed.isEmpty) {
        showAppNotice(t('تحتاج السماح بالكاميرا أو الميكروفون لاستخدام هذا الهاتف.',
            'Allow the camera or microphone to use this phone.'), error: true);
        unawaited(_api.decline(widget.request.id).then((_) {}, onError: (_) {}));
        _close();
        return;
      }
      if (allowed.length != widget.request.sources.length) {
        await _api.setSources(widget.request.id, allowed);
      }
      final join = await _api.accept(widget.request.id);
      if (!mounted) return;
      _timer?.cancel();
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/live/companion'),
        builder: (_) => CompanionPage(join: join),
      ));
    } on ApiException catch (e) {
      _close(notice: (e.code != null ? companionErrorText(e.code!) : null) ?? e.message);
    } catch (e) {
      log('[LIVE] companion accept: $e');
      _close(notice: t('تعذّر الاتصال. حاول مرة أخرى.', 'Could not connect. Try again.'));
    }
  }

  Future<void> _decline() async {
    setState(() => _busy = true);
    try {
      await _api.decline(widget.request.id);
    } catch (e) {
      log('[LIVE] companion decline: $e');
    }
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final uses = {
      if (r.sources.contains(CompanionSource.camera) || r.sources.contains(CompanionSource.microphone)) 1,
    };
    return Scaffold(
      body: CompanionIncomingLayout(
        sources: r.sources,
        secondsLeft: _left,
        originLabel: r.originLabel,
        roomTitle: r.title,
        busy: _busy,
        note: uses.isEmpty || kIsWeb
            ? null
            : t('سيطلب الهاتف إذنك لاستخدام الكاميرا أو الميكروفون.', 'Your phone will ask to use its camera or microphone.'),
        onAccept: _accept,
        onDecline: _decline,
      ),
    );
  }
}
