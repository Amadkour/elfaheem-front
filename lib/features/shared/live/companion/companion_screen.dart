// lib/features/shared/live/companion/companion_screen.dart — the phone while it lends its camera / mic / speaker (D-520).
//
// The phone is a participant of the same room, `companion:<person>`, publishing only what was granted, never subscribing
// to video and subscribing to the room's audio only when it is the speaker (and never to the person's own microphone).
// It obeys the person's device through the data topic `companion`, and leaves when the person leaves or the room ends.
library;

import 'dart:async';
import 'dart:developer' show log;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:livekit_client/livekit_client.dart';

import '../../../../design/app_notice.dart';
import '../../../admin/admin_common.dart' show t;
import '../live_room_words.dart' show liveT;
import '../../../teacher/sessions/live/widgets/live_call_service.dart';
import '../../../teacher/sessions/live/widgets/live_video_view.dart';
import 'companion_core.dart';
import 'companion_parts.dart';

class CompanionPage extends StatefulWidget {
  const CompanionPage({super.key, required this.join});
  final CompanionJoin join;

  @override
  State<CompanionPage> createState() => _CompanionPageState();
}

class _CompanionPageState extends State<CompanionPage> {
  final CompanionApi _api = CompanionApi();
  late final Room _room = Room(
    roomOptions: const RoomOptions(
      adaptiveStream: false,
      dynacast: true,
      defaultCameraCaptureOptions: CameraCaptureOptions(params: VideoParametersPresets.h720_169),
      defaultAudioCaptureOptions: AudioCaptureOptions(noiseSuppression: true, echoCancellation: true, autoGainControl: true),
    ),
  );
  EventsListener<RoomEvent>? _listener;
  CompanionPhoneState _state = CompanionPhoneState.connecting;
  late Set<CompanionSource> _sources = widget.join.request.sources;
  bool _speakerOn = true;
  bool _frontCamera = true;
  bool _leaving = false;
  bool _closed = false;
  Timer? _primaryGone;
  AppLifecycleListener? _lifecycle;
  bool _pausedForBackground = false;

  String get _primary => companionPrimaryOf(widget.join.identity) ?? '';
  bool get _hasCam => _sources.contains(CompanionSource.camera);
  bool get _hasMic => _sources.contains(CompanionSource.microphone);
  bool get _hasSpeaker => _sources.contains(CompanionSource.speaker);
  LocalParticipant? get _me => _room.localParticipant;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    unawaited(_connect());
  }

  @override
  void dispose() {
    _closed = true;
    _primaryGone?.cancel();
    _lifecycle?.dispose();
    unawaited(_listener?.dispose());
    unawaited(LiveCallService.stop());
    unawaited(_room.disconnect());
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      _listener = _room.createListener()
        ..on<RoomDisconnectedEvent>(_onDisconnected)
        ..on<ParticipantDisconnectedEvent>((e) {
          if (e.participant.identity == _primary) _onPrimaryGone();
          _maybeSetState();
        })
        ..on<ParticipantConnectedEvent>((e) {
          if (e.participant.identity == _primary) {
            _primaryGone?.cancel();
            _primaryGone = null;
          }
        })
        ..on<RoomReconnectingEvent>((_) => _setState(CompanionPhoneState.reconnecting))
        ..on<RoomReconnectedEvent>((_) {
          _setState(CompanionPhoneState.connected);
          _syncAudioSubscriptions();
        })
        ..on<TrackPublishedEvent>((e) {
          _syncAudioSubscriptions();
        })
        ..on<LocalTrackPublishedEvent>((_) => _maybeSetState())
        ..on<LocalTrackUnpublishedEvent>((_) => _maybeSetState())
        ..on<DataReceivedEvent>(_onData)
        ..on<ParticipantPermissionsUpdatedEvent>((e) {
          if (e.participant is LocalParticipant) _maybeSetState();
        });
      await _room.connect(
        widget.join.url,
        widget.join.token,
        connectOptions: const ConnectOptions(autoSubscribe: false),
      );
      if (_closed) return;
      // The grants are decided on the server: each source starts only if it was granted.
      await _publishMissing();
      _setState(CompanionPhoneState.connected);
      _syncAudioSubscriptions();
      if (_hasMic) unawaited(LiveCallService.start());
    } catch (e) {
      log('[LIVE] companion connect: $e');
      _finish(t('تعذّر الانضمام إلى جلستك.', 'Could not join your session.'), error: true);
    }
  }

  Future<void> _publishMissing() async {
    final me = _me;
    if (me == null) return;
    if (_hasCam && !me.isCameraEnabled()) {
      await _guarded(() => me.setCameraEnabled(true));
    }
    if (_hasMic && !me.isMicrophoneEnabled()) {
      await _guarded(() => me.setMicrophoneEnabled(true));
    }
  }

  Future<void> _guarded(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      log('[LIVE] companion: $e');
    }
  }

  // ── what the person's other device says ─────────────────────────────────────────────────────────────────

  void _onData(DataReceivedEvent e) {
    if (e.topic != kCompanionTopic || e.participant?.identity != _primary) return;
    final m = companionFromPacket(e.data);
    if (m == null) return;
    switch (m['t']) {
      case 'set':
        if (m['mic'] is bool && _hasMic) unawaited(_setMic(m['mic'] as bool));
        if (m['cam'] is bool && _hasCam) unawaited(_setCam(m['cam'] as bool));
        if (m['flip'] == true && _hasCam) unawaited(_flip());
      case 'sources':
        unawaited(_applySources(CompanionSource.parseAll(m['sources'])));
      case 'bye':
        _finish(t('أوقفت استخدام الهاتف من جهازك الآخر.', 'You stopped using this phone from your other device.'));
    }
  }

  Future<void> _applySources(Set<CompanionSource> next) async {
    final me = _me;
    if (me == null) return;
    final removed = _sources.difference(next);
    _sources = next;
    for (final s in removed) {
      if (s == CompanionSource.speaker) continue;
      final source = s == CompanionSource.camera ? TrackSource.camera : TrackSource.microphone;
      final pubs = [...me.trackPublications.values.where((p) => p.source == source)];
      for (final p in pubs) {
        await _guarded(() => me.removePublishedTrack(p.sid));
      }
    }
    await _publishMissing();
    _syncAudioSubscriptions();
    if (_hasMic) unawaited(LiveCallService.start());
    _maybeSetState();
  }

  /// Speaker on: hear the room's audio (only audio, and never the person's own voice). Speaker off: nothing.
  void _syncAudioSubscriptions() {
    if (_closed) return;
    for (final p in _room.remoteParticipants.values) {
      if (p.identity == _primary || isCompanionIdentity(p.identity)) {
        for (final pub in p.audioTrackPublications) {
          if (pub.subscribed) unawaited(_guarded(() => pub.unsubscribe()));
        }
        continue;
      }
      for (final pub in p.audioTrackPublications) {
        if (_hasSpeaker && !pub.subscribed) {
          unawaited(_guarded(() => pub.subscribe()));
        } else if (!_hasSpeaker && pub.subscribed) {
          unawaited(_guarded(() => pub.unsubscribe()));
        }
      }
    }
  }

  // ── the phone's own buttons ─────────────────────────────────────────────────────────────────────────────

  bool get _micOn => _me?.isMicrophoneEnabled() ?? false;
  bool get _camOn => _me?.isCameraEnabled() ?? false;

  Future<void> _setMic(bool on) async {
    final me = _me;
    if (me == null) return;
    await _guarded(() => me.setMicrophoneEnabled(on));
    _maybeSetState();
  }

  Future<void> _setCam(bool on) async {
    final me = _me;
    if (me == null) return;
    await _guarded(() => me.setCameraEnabled(on));
    _maybeSetState();
  }

  Future<void> _flip() async {
    final me = _me;
    final track = me?.videoTrackPublications.firstWhereOrNull((p) => p.source == TrackSource.camera)?.track;
    if (track is! LocalVideoTrack) return;
    _frontCamera = !_frontCamera;
    await _guarded(() => track.setCameraPosition(_frontCamera ? CameraPosition.front : CameraPosition.back));
    _maybeSetState();
  }

  void _toggleSpeaker() {
    if (!_hasSpeaker) return;
    setState(() => _speakerOn = !_speakerOn);
    unawaited(_guarded(() => AudioManager.instance.setSpeakerOutputPreferred(_speakerOn)));
  }

  /// In the background a phone may keep its microphone (Android's foreground service, iOS audio) but not its camera:
  /// the camera pauses, the person's device shows the avatar, and it comes back on return.
  void _onLifecycle(AppLifecycleState state) {
    if (kIsWeb || !_hasCam) return;
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      if (_camOn) {
        _pausedForBackground = true;
        unawaited(_setCam(false));
      }
    } else if (state == AppLifecycleState.resumed && _pausedForBackground) {
      _pausedForBackground = false;
      unawaited(_setCam(true));
    }
  }

  Future<void> _leave() async {
    if (_leaving) return _finish(null); // a second tap while the server call runs still closes the page
    _leaving = true;
    _send({'t': 'bye'});
    try {
      await _api.end(widget.join.request.id, reason: 'phone').timeout(const Duration(seconds: 4));
    } catch (e) {
      log('[LIVE] companion leave: $e');
    }
    _finish(null);
  }

  void _send(Map<String, Object?> m) {
    final me = _me;
    if (me == null) return;
    unawaited(me
        .publishData(companionPacket(m), reliable: true, destinationIdentities: [_primary], topic: kCompanionTopic)
        .catchError((Object e) => log('[LIVE] companion send: $e')));
  }

  // ── ending ──────────────────────────────────────────────────────────────────────────────────────────────

  void _onPrimaryGone() {
    _primaryGone?.cancel();
    // A short grace: the person's browser may just be reconnecting.
    _primaryGone = Timer(const Duration(seconds: 8), () {
      if (_room.remoteParticipants.values.none((p) => p.identity == _primary)) {
        _finish(t('انتهت جلستك على الجهاز الآخر.', 'Your session on the other device ended.'));
      }
    });
  }

  void _onDisconnected(RoomDisconnectedEvent e) {
    if (_leaving || _closed) return;
    final kind = widget.join.request.ref.kind;
    final msg = switch (e.reason) {
      DisconnectReason.participantRemoved => t('أُزيل هذا الهاتف من الجلسة.', 'This phone was removed from the session.'),
      DisconnectReason.roomDeleted =>
        liveT(kind, ar: 'انتهت الجلسة.', en: 'The session ended.', meetingAr: 'انتهى الاجتماع.', meetingEn: 'The meeting ended.'),
      _ => t('انقطع اتصال الهاتف بالجلسة.', 'This phone lost the session.'),
    };
    _finish(msg);
  }

  /// Closes the phone's page: the room ended, the person stopped, Leave. D-810: a direct pop past the page's own
  /// PopScope — `maybePop` asked the PopScope, which refused and re-ran Leave, so the page never closed (frozen phone).
  void _finish(String? notice, {bool error = false}) {
    if (!_closed) {
      _closed = true;
      _primaryGone?.cancel();
      if (notice != null) showAppNotice(notice, error: error);
    }
    if (mounted) closeCompanionRoute(context);
  }

  void _setState(CompanionPhoneState s) {
    if (!mounted || _closed) return;
    setState(() => _state = s);
  }

  void _maybeSetState() {
    if (mounted && !_closed) setState(() {});
  }

  Future<void> _confirmLeave() async {
    if (_closed) return _finish(null); // already over (the room ended): back just closes the page
    await _leave();
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    VideoTrack? cam;
    if (me != null && _camOn) {
      final pub = me.videoTrackPublications.firstWhereOrNull((p) => p.source == TrackSource.camera);
      if (pub?.track case final VideoTrack v) cam = v;
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmLeave());
      },
      child: Scaffold(
        body: CompanionPhoneLayout(
          state: _state,
          originLabel: widget.join.request.originLabel ?? t('جهازك', 'your device'),
          sources: _sources,
          micOn: _micOn,
          camOn: _camOn,
          speakerOn: _speakerOn,
          preview: cam == null ? null : LiveVideoView(cam, fit: VideoViewFit.cover),
          notice: _pausedForBackground ? t('الكاميرا متوقفة لأن التطبيق في الخلفية.', 'Camera paused: the app is in the background.') : null,
          onToggleMic: _hasMic ? () => unawaited(_setMic(!_micOn)) : null,
          onToggleCam: _hasCam ? () => unawaited(_setCam(!_camOn)) : null,
          onFlip: _hasCam ? () => unawaited(_flip()) : null,
          onToggleSpeaker: _hasSpeaker ? _toggleSpeaker : null,
          onLeave: _confirmLeave,
        ),
      ),
    );
  }
}
