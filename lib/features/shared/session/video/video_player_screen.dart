/// lib/screens/video_player/video_player_screen.dart
library;

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_shell_nav.dart' show AppShellNav;
import 'package:flutter/services.dart';
import 'package:floating/floating.dart';
import 'package:flutter_education_app/core/offline/offline_video_service.dart';
import 'package:flutter_education_app/features/shared/session/material/session_material_model.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_education_app/core/screen_security.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:dio/dio.dart' as dio;
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

import '../../../../config/app_config.dart';
import '../../../../core/offline/offline_strings.dart';
import '../../../../utils/helpers.dart';
import '../../../student/courses/details/course_detail_provider.dart';
import '../../../student/courses/security/device_blocked_dialog.dart';
import '../../../student/courses/security/device_id_service.dart';
import '../../../student/courses/security/device_security_provider.dart';
import 'fullscreen_stub.dart'
if (dart.library.js_interop) 'fullscreen_web.dart' as webfs;

import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import '../../../admin/admin_common.dart' show t;
import 'vod_player_parts.dart';
import 'vod_listen.dart';
import 'package:flutter_education_app/core/media_focus.dart';
import 'package:flutter_education_app/design/app_notice.dart' show showAppNotice;
import 'package:flutter_education_app/features/shared/rag/app_assistant.dart' show AppAssistant;
import 'package:flutter_education_app/core/display/app_fonts.dart';
// ════════════════════════════════════════════════════════════════════════════
// VideoPlayerScreen
// ════════════════════════════════════════════════════════════════════════════
// API (unchanged):
//   material: SessionMaterialModel  -> reads videoVariants / audioVariants
//   VideoPlayerScreen.fromLegacy(...) keeps old call-sites working.
//
// UX highlights:
//   • Double-tap left/right = -10s / +10s (accumulates: 10 → 20 → 30 …)
//   • Press & hold the right half = temporary 2× speed
//   • Custom seek bar (buffer + progress + scrub-time bubble)
//   • Controls lock, quality/audio picker, speed picker, fullscreen
//   • Always LTR layout for the player chrome (so left/right gestures are
//     correct even when the app is RTL / Arabic)
// ════════════════════════════════════════════════════════════════════════════

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.material,
    this.autoPlay = true,
    this.startFullScreen = false,
    this.playlist,
    this.resume,
  });

  final SessionMaterialModel material;

  /// Back from the listen-only bar (D-104): plays on with that controller, at the same place, without a new
  /// POST …/play (which would count another view).
  final VodListenHandoff? resume;

  /// The materials around [material] (e.g. the session's list): enables the lecture list and "up next".
  final List<SessionMaterialModel>? playlist;
  final bool autoPlay;
  final bool startFullScreen;

  /// Legacy factory — wraps plain URL list so old call-sites keep working.
  factory VideoPlayerScreen.fromLegacy({
    Key? key,
    required List<({String label, String url})> qualities,
    required String title,
    String? subtitle,
    String? audioUrl,
    bool autoPlay = true,
    bool startFullScreen = false,
  }) {
    final variants = qualities
        .map((e) => _LegacyHelper.variantFromLabel(
      label: e.label,
      url: e.url,
    ))
        .toList();

    final model = _LegacyHelper.buildModel(
      title: title,
      subtitle: subtitle,
      variants: variants,
      audioUrl: audioUrl,
    );

    return VideoPlayerScreen(
      key: key,
      material: model,
      autoPlay: autoPlay,
      startFullScreen: startFullScreen,
    );
  }

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

// ── Legacy helper (keeps old callers working) ─────────────────────────────────
class _LegacyHelper {
  static MaterialVariant variantFromLabel(
      {required String label, required String url}) {
    QualityTier tier;
    if (label.contains('1080') || label.toLowerCase() == 'high') {
      tier = QualityTier.high;
    } else if (label.contains('720') || label.toLowerCase() == 'medium') {
      tier = QualityTier.medium;
    } else {
      tier = QualityTier.low;
    }
    return MaterialVariant(url: url, tier: tier, isAudio: false);
  }

  static SessionMaterialModel buildModel({
    required String title,
    String? subtitle,
    required List<MaterialVariant> variants,
    String? audioUrl,
  }) {
    final high = variants.where((v) => v.tier == QualityTier.high).firstOrNull;
    final medium =
        variants.where((v) => v.tier == QualityTier.medium).firstOrNull;
    final low = variants.where((v) => v.tier == QualityTier.low).firstOrNull;

    return SessionMaterialModel(
      id: 0,
      sessionId: 0,
      name: title,
      description: subtitle,
      type: SessionMaterialType.video,
      order: 0,
      createdAt: DateTime.now(),
      completed: false,
      urlHigh: high?.url,
      urlMedium: medium?.url,
      urlLow: low?.url,
      rawUrlHigh: high?.url,
      rawUrlMedium: medium?.url,
      rawUrlLow: low?.url,
      audioUrl: audioUrl,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with SingleTickerProviderStateMixin {
  // ── Active stream ─────────────────────────────────────────────────────────
  late MaterialVariant _activeVariant;

  /// The lecture on screen; changes in place when the student picks another one from the playlist.
  late SessionMaterialModel _current = widget.material;

  // ── Controllers ───────────────────────────────────────────────────────────
  VideoPlayerController? _vc;
  bool _vcReady = false;
  bool _isLoading = true;
  bool _hasError = false;

  /// Incremented on every _initPlayer call so a slow, superseded init
  /// (e.g. the user tapped two qualities quickly) can never win the race.
  int _initToken = 0;

  /// A quality / audio switch is opening the new stream (the old frame stays, dimmed, under a spinner).
  bool _switching = false;

  /// Listen-only: the picture left the tree, the controller goes to the bar next.
  bool _handingOff = false;

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _isFullScreen = false;
  bool _isLocked = false;
  bool _lockHint = false;
  bool _controlsShown = true;
  bool _isSeeking = false;
  double _seekFraction = 0;
  double _speed = 1.0;

  // Press-and-hold 2× boost
  bool _boosting = false;

  // ── Orientation / Picture-in-Picture ──────────────────────────────────────
  /// true  = the sensor decides (rotate the phone left/right/portrait)
  /// false = locked by the user via the fullscreen / rotation buttons
  bool _autoRotate = true;

  static const _allOrientations = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];
  static const _landscapes = <DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  /// Fullscreen on the web: the browser refused the orientation lock (iOS Safari
  /// never allows it), so the player rotates itself 90° while the phone is portrait.
  bool _webForceRotate = false;
  void Function()? _webFsUnlisten;

  static const _landscapeOnly = <DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
  ];

  final Floating _floating = Floating();
  bool _pipAvailable = false;
  bool _inPip = false;
  StreamSubscription<PiPStatus>? _pipSub;

  // ── Offline (encrypted local copy) ────────────────────────────────────────
  bool _isOffline = false; // currently playing from the local encrypted file
  bool _downloaded = false; // an offline copy exists
  bool get _canDownload => !kIsWeb && !_isAudioMode && _mat.id != 0;

  static const _speedOptions = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  // ── Seek flash (accumulating) ─────────────────────────────────────────────
  bool _flashRewind = false;
  bool _flashForward = false;
  int _seekAccum = 0;
  Timer? _flashTimer;

  // ── Animations / timers ───────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  Timer? _hideTimer;
  Timer? _lockHintTimer;

  // Last-seen controller flags (so the listener only reacts to *changes*)
  bool _wasPlaying = false;
  bool _wasEnded = false;

  // ── Getters ───────────────────────────────────────────────────────────────
  bool get _isAudioMode => _activeVariant.isAudio;

  // URLs come from POST .../play when the list endpoint hid them.
  SessionMaterialModel? _resolved;
  SessionMaterialModel get _mat => _resolved ?? _current;
  String? _viewsNote; // e.g. "المشاهدات المتبقية هذا الشهر: 2"

  // Watch-progress
  CourseDetailProvider? _progressProvider;
  bool _completionSent = false;

  // Resume, up next, captions, volume / brightness, keyboard
  bool _resumeChecked = false;
  Duration? _resumedAt;
  Timer? _resumeChipTimer;
  Timer? _saveTimer;
  Timer? _nextTimer;
  int? _nextIn;
  bool _hasCaptions = false;
  bool _captionsOn = false;
  double _volume = 1.0;
  double _dim = 0; // darkening overlay (web/desktop), 0 = full brightness
  double _brightness = 1; // real screen brightness (phones)
  ({bool brightness, double value})? _hud;
  Timer? _hudTimer;
  final FocusNode _focus = FocusNode(debugLabel: 'vod-player');

  static const _maxDim = 0.8;
  bool get _touchDevice =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  List<SessionMaterialModel> get _list => vodPlaylist(widget.playlist ?? const []);
  SessionMaterialModel? get _next => vodNextOf(_list, _current);

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    AppAssistant.hide(); // full screen: no floating assistant bubble
    // One sound at a time: a lecture playing in the listen-only bar stops here (D-104).
    MediaFocus.claim(this);

    final back = widget.resume;
    if (back != null) {
      _resolved = back.material;
      _activeVariant = back.variant;
      _speed = back.speed;
      _captionsOn = back.captionsOn;
      _isOffline = back.isOffline;
      _downloaded = back.downloaded;
      _viewsNote = back.viewsNote;
      _completionSent = back.completionSent;
      _resumeChecked = true;
    } else {
      _activeVariant = _mat.defaultVideoVariant;
    }

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _pulseAnim = Tween(begin: 0.92, end: 1.08)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    WakelockPlus.enable().ignore();
    _protectScreen(true);
    _initOrientationAndPip();
    if (back != null) {
      _adopt(back);
    } else {
      _startPlayback();
    }
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _persistPos());
    _readSystemLevels();

    if (widget.startFullScreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _enterFullScreen());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The player may be opened from places that have no CourseDetailProvider
    // (legacy callers). context.read would throw there, so guard it.
    if (_progressProvider == null) {
      try {
        _progressProvider = context.read<CourseDetailProvider>();
      } catch (_) {}
    }
    // Fires on every orientation change (MediaQuery dependency).
    _syncWithOrientation();
  }

  /// Takes the controller back from the listen-only bar; when the bar had moved to the audio track, the picture's
  /// stream comes back (same place, same play state).
  void _adopt(VodListenHandoff h) {
    final vc = h.controller;
    _vc = vc;
    _vcReady = vc.value.isInitialized;
    _isLoading = !_vcReady;
    _wasPlaying = vc.value.isPlaying;
    vc.addListener(_onVcUpdate);
    if (h.swapped) {
      _attachCaptions(vc);
    } else {
      _hasCaptions = _mat.captionsUrl != null || _isOffline; // the player's own file is still attached
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncPulse();
      _startHideTimer();
      final to = h.returnTo;
      if (to != null) _switchVariant(to);
    });
  }

  /// Blocks screenshots / screen recording while the player is open
  /// (Android FLAG_SECURE, iOS blur in app switcher + screenshot prevention).
  /// Owned through ScreenSecurity (D-083): another protected screen closing never switches this one off.
  Future<void> _protectScreen(bool on) =>
      on ? ScreenSecurity.instance.protect(this) : ScreenSecurity.instance.release(this);

  /// Asks the server for the video URLs (this is what counts a view), then plays.
  Future<void> _startPlayback() async {
    // Downloaded copy? Play it from the encrypted local file. This works
    // offline and does NOT call /play, so no monthly view is consumed.
    if (!kIsWeb && _current.id != 0) {
      try {
        final local = await OfflineVideoService.instance
            .localVariant(_current.sessionId, _current.id);
        if (!mounted) return;
        if (local != null) {
          setState(() {
            _isOffline = true;
            _downloaded = true;
            _activeVariant = local;
          });
          await _initPlayer(local, autoPlay: widget.autoPlay);
          return;
        }
      } catch (_) {
        // fall through to normal streaming
      }
    }

    if (_current.requiresPlay && _current.id != 0) {
      try {
        final r = await ApiClient().post(
          '/api/v1/sessions/${_current.sessionId}/materials/${_current.id}/play',
        );
        if (r is! Map<String, dynamic>) throw StateError('bad play response');
        final resolved = _current.withPlayData(r);
        if (!mounted) return;
        final left = r['views_left'];
        setState(() {
          _resolved = resolved;
          _viewsNote =
          left == null
              ? null
              : offlineT('dl_views_left').replaceAll('{n}', '$left');
          _activeVariant = resolved.defaultVideoVariant;
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        await _handlePlayError(e);
        return;
      } catch (_) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasError = true;
          });
        }
        return;
      }
    }
    if (!mounted) return;
    await _initPlayer(_activeVariant, autoPlay: widget.autoPlay);
  }

  Future<void> _handlePlayError(ApiException e) async {
    if (e.isDeviceBlocked) {
      final p = DeviceSecurityProvider();
      await p.check();
      if (mounted) {
        await showDeviceBlockedDialog(
          context,
          p,
          courseId: int.tryParse(_progressProvider?.course.id.toString() ?? ''),
        );
      }
    } else if (e.isViewLimit) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(offlineT('dl_views_ended')),
            content: Text(e.message),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(offlineT('dl_ok')))
            ],
          ),
        ),
      );
    } else {
      Helpers.showMessage(e.message);
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    // NOTE: the old code called _checkWatchThreshold() here. That could notify
    // the provider while the widget tree is being torn down (setState during
    // unmount). The listener already handles completion while playing.
    _persistPos();
    _initToken++; // cancel any in-flight init
    _saveTimer?.cancel();
    _nextTimer?.cancel();
    _resumeChipTimer?.cancel();
    _hudTimer?.cancel();
    _focus.dispose();
    if (_touchDevice) ScreenBrightness.instance.resetApplicationScreenBrightness().catchError((Object _) {});
    _hideTimer?.cancel();
    _flashTimer?.cancel();
    _lockHintTimer?.cancel();
    _pipSub?.cancel();
    _floating.cancelOnLeavePiP();
    _pulseCtrl.dispose();
    _vc?.removeListener(_onVcUpdate);
    _vc?.dispose();
    WakelockPlus.disable().ignore();
    _protectScreen(false);
    if (kIsWeb) {
      _webFsUnlisten?.call();
      if (_isFullScreen) webfs.exitLandscapeFullscreen();
    }
    _restoreSystemUI();
    AppAssistant.release();
    MediaFocus.release(this);
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Player init
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initPlayer(
      MaterialVariant variant, {
        Duration seekTo = Duration.zero,
        bool autoPlay = true,
      }) async {
    if (!mounted) return;
    final token = ++_initToken;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    if (variant.url == null || variant.url!.isEmpty) {
      Helpers.showMessage('video_not_available'.tr);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
      return;
    }

    // Mobile: stream links only work together with this device's id header (the offline copy's loopback server
    // ignores it; skipping every 127.0.0.1 link broke a build pointed at a local stack over `adb reverse`).
    // Web: a <video> element can't send headers; the server's link already carries the id as ?d=..., so send none.
    final next = VideoPlayerController.networkUrl(
      Uri.parse(variant.url!),
      httpHeaders: kIsWeb ? const <String, String>{} : await DeviceIdService.instance.headers(),
      // Keep playing (sound) in background. iOS also needs
      // UIBackgroundModes=audio in Info.plist. Ignored on web.
      videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
    );

    try {
      await next.initialize();

      // A newer init started (or the screen closed) while we were waiting.
      if (token != _initToken || !mounted) {
        await next.dispose();
        return;
      }

      var at = seekTo;
      if (at == Duration.zero && !_resumeChecked) {
        _resumeChecked = true;
        final saved = await VodResume.load(_mat.sessionId, _mat.id);
        if (token != _initToken || !mounted) {
          await next.dispose();
          return;
        }
        final r = saved == null ? null : VodResume.pick(saved, next.value.duration);
        if (r != null) {
          at = r;
          _showResumeChip(r);
        }
      }
      if (at > Duration.zero) await next.seekTo(at);
      await next.setPlaybackSpeed(_speed);
      if (!_touchDevice) await next.setVolume(_volume);
      _attachCaptions(next);
      next.addListener(_onVcUpdate);

      final old = _vc;
      _wasPlaying = false;
      _wasEnded = false;

      setState(() {
        _vc = next;
        _vcReady = true;
        _isLoading = false;
        _activeVariant = variant;
      });
      old?.removeListener(_onVcUpdate);
      await old?.dispose();

      if (autoPlay && mounted && token == _initToken) {
        await next.play();
        _startHideTimer();
      }
      _syncPulse();
    } catch (_) {
      await next.dispose();
      if (mounted && token == _initToken) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  /// Retry after an error — resumes from where playback stopped.
  void _retry() {
    final pos = _vc?.value.position ?? Duration.zero;
    _initPlayer(_activeVariant, seekTo: pos, autoPlay: true);
  }

  /// Controller listener. It does NOT rebuild the screen on every tick any more
  /// (the controls use a ValueListenableBuilder); it only reacts to changes.
  void _onVcUpdate() {
    final vc = _vc;
    if (vc == null || !mounted) return;
    final v = vc.value;

    _checkWatchThreshold();

    if (v.hasError && !_hasError) {
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
      return;
    }

    final playing = v.isPlaying;
    if (playing != _wasPlaying) {
      _wasPlaying = playing;
      _syncPulse();
      if (playing) {
        _startHideTimer();
      } else {
        _hideTimer?.cancel();
      }
    }

    final ended = v.isInitialized &&
        v.duration > Duration.zero &&
        !v.isPlaying &&
        v.position >= v.duration - const Duration(milliseconds: 300);
    if (ended && !_wasEnded) {
      _wasEnded = true;
      _showControls(); // always reveal the replay button at the end
      _startNextCountdown();
    } else if (!ended) {
      if (_wasEnded) _stopNextTimer();
      _wasEnded = false;
    }
  }

  // ── Resume position ───────────────────────────────────────────────────────

  void _persistPos() {
    final v = _vc?.value;
    if (v == null || !v.isInitialized) return;
    unawaited(VodResume.save(_mat.sessionId, _mat.id, v.position, v.duration));
  }

  void _showResumeChip(Duration at) {
    _resumeChipTimer?.cancel();
    setState(() => _resumedAt = at);
    _resumeChipTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _resumedAt = null);
    });
  }

  void _startOver() {
    _resumeChipTimer?.cancel();
    _vc?.seekTo(Duration.zero);
    setState(() => _resumedAt = null);
  }

  // ── Captions (WebVTT) ─────────────────────────────────────────────────────

  void _attachCaptions(VideoPlayerController vc) {
    // Only a real file counts: `captions_status == 'ready'` without a `captions_url` is still "no captions".
    final url = _mat.captionsUrl;
    _hasCaptions = url != null || _isOffline;
    if (!_hasCaptions) return;
    final file = _isOffline ? _localCaptions() : _fetchCaptions(url!);
    unawaited(vc.setClosedCaptionFile(file).catchError((Object _) {
      if (mounted) setState(() => _hasCaptions = _captionsOn = false);
    }));
  }

  /// Captions saved with the offline copy; throws when there are none so the CC button disappears.
  Future<ClosedCaptionFile> _localCaptions() async {
    final text = await OfflineVideoService.instance.localCaptions(_mat.sessionId, _mat.id);
    if (text == null) throw StateError('no offline captions');
    return WebVTTCaptionFile(text);
  }

  Future<ClosedCaptionFile> _fetchCaptions(String url) async {
    final headers = kIsWeb ? const <String, String>{} : await DeviceIdService.instance.headers();
    final r = await dio.Dio().get<String>(url,
        options: dio.Options(responseType: dio.ResponseType.plain, headers: headers));
    return WebVTTCaptionFile(r.data ?? '');
  }

  void _toggleCaptions() {
    if (!_hasCaptions) return;
    setState(() => _captionsOn = !_captionsOn);
  }

  // ── Playlist / up next ────────────────────────────────────────────────────

  void _startNextCountdown() {
    if (_next == null || _isLocked) return;
    _nextTimer?.cancel();
    setState(() => _nextIn = 5);
    _nextTimer = Timer.periodic(const Duration(seconds: 1), (tm) {
      if (!mounted) return tm.cancel();
      final n = (_nextIn ?? 0) - 1;
      if (n <= 0) {
        tm.cancel();
        _playNext();
      } else {
        setState(() => _nextIn = n);
      }
    });
  }

  void _stopNextTimer() {
    _nextTimer?.cancel();
    if (_nextIn != null && mounted) setState(() => _nextIn = null);
  }

  void _playNext() {
    final n = _next;
    if (n != null) _openLecture(n);
  }

  /// Switches lecture inside the same screen, so screen protection, wakelock and
  /// orientation never flip off between two lectures.
  Future<void> _openLecture(SessionMaterialModel m) async {
    if (m.id == _current.id && m.sessionId == _current.sessionId) return;
    _stopNextTimer();
    _persistPos();
    await _vc?.pause();
    if (!mounted) return;
    _resumeChipTimer?.cancel();
    setState(() {
      _current = m;
      _resolved = null;
      _viewsNote = null;
      _completionSent = false;
      _resumeChecked = false;
      _resumedAt = null;
      _isOffline = false;
      _downloaded = false;
      _hasCaptions = false;
      _isLoading = true;
      _hasError = false;
      _activeVariant = m.defaultVideoVariant;
    });
    await _startPlayback();
  }

  void _openLectures() {
    _hideTimer?.cancel();
    showVodLectureList(context, items: _list, currentId: _current.id, onSelect: _openLecture)
        .whenComplete(_startHideTimer);
  }

  // ── Volume / brightness ───────────────────────────────────────────────────

  void _setVolume(double v) {
    _volume = v.clamp(0.0, 1.0);
    if (_touchDevice) {
      // Phones: the real media volume (the player itself stays at 1.0).
      VolumeController.instance.setVolume(_volume).catchError((Object _) {});
    } else {
      _vc?.setVolume(_volume);
    }
  }

  /// Phones: swipes change the real screen brightness; elsewhere the video is dimmed instead.
  void _setBrightness(double b) {
    if (_touchDevice) {
      _brightness = b.clamp(0.0, 1.0);
      ScreenBrightness.instance.setApplicationScreenBrightness(_brightness).catchError((Object _) {});
    } else {
      _dim = ((1 - b) * _maxDim).clamp(0.0, _maxDim);
    }
  }

  double get _brightnessLevel => _touchDevice ? _brightness : 1 - _dim / _maxDim;

  Future<void> _readSystemLevels() async {
    if (!_touchDevice) return;
    try {
      VolumeController.instance.showSystemUI = false;
      _volume = (await VolumeController.instance.getVolume()).clamp(0.0, 1.0);
    } catch (_) {}
    try {
      _brightness = (await ScreenBrightness.instance.application).clamp(0.0, 1.0);
    } catch (_) {}
  }

  void _flashHud(bool brightness, {bool hold = false}) {
    _hudTimer?.cancel();
    setState(() => _hud = (brightness: brightness, value: brightness ? _brightnessLevel : _volume));
    if (!hold) {
      _hudTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _hud = null);
      });
    }
  }

  void _onLevelDrag(DragUpdateDetails d, {required bool brightness}) {
    final step = -(d.primaryDelta ?? 0) / (MediaQuery.sizeOf(context).height * 0.7);
    if (brightness) {
      _setBrightness(_brightnessLevel + step);
    } else {
      _setVolume(_volume + step);
    }
    _flashHud(brightness, hold: true);
  }

  void _toggleMute() {
    _setVolume(_volume == 0 ? 1 : 0);
    _flashHud(false);
  }

  // ── Keyboard (web / desktop / hardware keyboards) ─────────────────────────

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (!_vcReady || _vc == null || _isLocked) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final down = e is KeyDownEvent;
    const digits = [
      LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
    ];
    if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyK) {
      if (down) _togglePlayPause();
    } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyJ) {
      _seekRelative(k == LogicalKeyboardKey.keyJ ? 10 : 5, forward: false);
    } else if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyL) {
      _seekRelative(k == LogicalKeyboardKey.keyL ? 10 : 5, forward: true);
    } else if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      _setVolume(_volume + (k == LogicalKeyboardKey.arrowUp ? 0.1 : -0.1));
      _flashHud(false);
    } else if (k == LogicalKeyboardKey.keyM) {
      if (down) _toggleMute();
    } else if (k == LogicalKeyboardKey.keyF) {
      if (down) _toggleFullScreen();
    } else if (k == LogicalKeyboardKey.escape && _isFullScreen) {
      if (down) _exitFullScreen();
    } else if (k == LogicalKeyboardKey.keyC && _hasCaptions) {
      if (down) _toggleCaptions();
    } else if (k == LogicalKeyboardKey.keyN && _next != null) {
      if (down) _playNext();
    } else if (digits.contains(k)) {
      _vc!.seekTo(_vc!.value.duration * (digits.indexOf(k) / 10));
      _showControls();
    } else if (e.character == '>' || e.character == '<') {
      final i = (_speedOptions.indexOf(_speed) + (e.character == '>' ? 1 : -1)).clamp(0, _speedOptions.length - 1);
      _setSpeed(_speedOptions[i]);
      Helpers.showMessage('${_speedOptions[i]}×');
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Pulse animation only runs while audio is actually playing.
  void _syncPulse() {
    if (!mounted) return;
    final shouldRun = _isAudioMode && (_vc?.value.isPlaying ?? false);
    if (shouldRun && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    } else if (!shouldRun && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
    }
  }

  /// Marks the material complete once the student has watched ~75% of it.
  void _checkWatchThreshold() {
    if (_completionSent) return;
    final vc = _vc;
    if (vc == null || !vc.value.isInitialized) return;

    final dur = vc.value.duration;
    if (dur <= Duration.zero) return;

    final watched = vc.value.position.inMilliseconds / dur.inMilliseconds;
    if (watched >= 0.75) {
      _completionSent = true;
      final provider = _progressProvider;
      if (provider != null) {
        unawaited(provider.markMaterialComplete(_mat.sessionId, _mat.id));
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stream switching
  // ─────────────────────────────────────────────────────────────────────────

  /// Same lecture, another stream (quality or audio). The old stream stays until the new one is open: it keeps the
  /// place, play / pause, speed and captions, and when the new stream fails the old one goes on with a notice
  /// (D-104). Before, a failed init left the error screen, and the picker closed the whole player (see showVodPicker).
  Future<void> _switchVariant(MaterialVariant v) async {
    switch (vodSwitchDecision(_activeVariant, v)) {
      case VodSwitch.same:
        return;
      case VodSwitch.unavailable:
        showAppNotice('video_not_available'.tr, error: true);
        return;
      case VodSwitch.go:
        break;
    }
    final old = _vc;
    if (old == null || !old.value.isInitialized || _hasError) {
      // Nothing playing yet (or the stream failed): a plain start on the chosen stream.
      await _initPlayer(v, seekTo: old?.value.position ?? Duration.zero, autoPlay: true);
      return;
    }
    _stopBoost();
    _stopNextTimer();
    final carry = VodCarry(position: old.value.position, playing: old.value.isPlaying, speed: _speed, captionsOn: _captionsOn);
    final from = _activeVariant;
    final token = ++_initToken;
    setState(() {
      _isLoading = true;
      _switching = true;
    });
    await old.pause().catchError((Object _) {});
    VideoPlayerController next;
    try {
      next = await openVodController(v,
          at: carry.position, speed: carry.speed, volume: _touchDevice ? null : _volume);
    } catch (_) {
      if (!mounted || token != _initToken) return;
      setState(() {
        _isLoading = false;
        _switching = false;
      });
      if (carry.playing) unawaited(old.play());
      showAppNotice(
          'vod_switch_failed'.tr.replaceAll('{q}', v.label).replaceAll('{old}', from.label),
          error: true);
      return;
    }
    if (!mounted || token != _initToken || !identical(_vc, old)) {
      unawaited(next.dispose());
      return;
    }
    _attachCaptions(next);
    old.removeListener(_onVcUpdate);
    next.addListener(_onVcUpdate);
    _wasPlaying = false;
    _wasEnded = false;
    setState(() {
      _vc = next;
      _vcReady = true;
      _activeVariant = v;
      _isLoading = false;
      _switching = false;
    });
    // The old stream goes only after the frame that draws the new one: disposing it first releases the platform
    // texture the VideoPlayer widget still shows for one frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(old.dispose().catchError((Object _) {})));
    WidgetsBinding.instance.scheduleFrame();
    if (carry.playing) {
      await next.play();
      _startHideTimer();
    }
    _syncPulse();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Listen only (D-104)
  // ─────────────────────────────────────────────────────────────────────────

  bool get _canListen => _vcReady && _vc != null && !_hasError && !_isLoading && !_inPip && !_handingOff;

  /// Hands the playing controller to the listen-only bar at the top of the app and closes the page: the lecture
  /// goes on as sound while the person moves around the app, with the screen allowed to sleep.
  Future<void> _startListenOnly() async {
    final vc = _vc;
    if (!_canListen || vc == null) return;
    HapticFeedback.selectionClick();
    final v = vc.value;
    final play = !vodFinished(v.position, v.duration, playing: v.isPlaying);
    _stopNextTimer();
    _stopBoost();
    _hideTimer?.cancel();
    _persistPos();
    if (_isFullScreen && kIsWeb) webfs.exitLandscapeFullscreen();
    // The picture leaves the tree first: on the web a <video> taken off the page is paused by the browser, so the
    // bar starts it again once that happened.
    setState(() {
      _handingOff = true;
      _isFullScreen = false;
    });
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !identical(_vc, vc)) return;
    vc.removeListener(_onVcUpdate);
    _initToken++; // nothing in flight may touch the controller any more
    final h = VodListenHandoff(
      controller: vc,
      material: _mat,
      current: _current,
      variant: _activeVariant,
      playlist: widget.playlist,
      speed: _speed,
      captionsOn: _captionsOn,
      isOffline: _isOffline,
      downloaded: _downloaded,
      viewsNote: _viewsNote,
      completionSent: _completionSent,
      progress: _progressProvider,
    );
    _vc = null; // ours no more: dispose() must not touch it
    _vcReady = false;
    VodListenSession.instance.start(h, play: play);
    showAppNotice('vod_listen_started'.tr, icon: Icons.headphones_rounded);
    final route = ModalRoute.of(context);
    if (route == null) return;
    final nav = Navigator.of(context);
    if (route.isCurrent) {
      nav.pop();
    } else {
      nav.removeRoute(route);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Controls visibility
  // ─────────────────────────────────────────────────────────────────────────

  void _showControls() {
    if (!mounted) return;
    if (!_controlsShown) setState(() => _controlsShown = true);
    _startHideTimer();
  }

  void _hideControls() {
    if (!mounted || !_controlsShown) return;
    setState(() => _controlsShown = false);
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_vcReady && !_isSeeking && (_vc?.value.isPlaying ?? false)) {
      _hideTimer = Timer(const Duration(seconds: 4), _hideControls);
    }
  }

  void _toggleControls() => _controlsShown ? _hideControls() : _showControls();

  // ─────────────────────────────────────────────────────────────────────────
  // Playback
  // ─────────────────────────────────────────────────────────────────────────

  void _togglePlayPause() {
    final vc = _vc;
    if (vc == null) return;
    HapticFeedback.lightImpact();
    if (vc.value.isPlaying) {
      vc.pause();
      _hideTimer?.cancel();
      _showControls();
    } else {
      vc.play();
      _startHideTimer();
    }
  }

  void _replay() {
    _stopNextTimer();
    _vc?.seekTo(Duration.zero);
    _vc?.play();
    _startHideTimer();
  }

  void _seekRelative(int seconds, {required bool forward}) {
    final vc = _vc;
    if (vc == null || !_vcReady) return;
    final dur = vc.value.duration;

    // FIX: the old code always ADDED the seconds, so "rewind" jumped forward.
    var pos = vc.value.position + Duration(seconds: forward ? seconds : -seconds);
    if (pos < Duration.zero) pos = Duration.zero;
    if (pos > dur) pos = dur;
    vc.seekTo(pos);

    HapticFeedback.selectionClick();

    setState(() {
      // Switching direction restarts the accumulator.
      if ((forward && _flashRewind) || (!forward && _flashForward)) {
        _seekAccum = 0;
      }
      _seekAccum += seconds;
      _flashForward = forward;
      _flashRewind = !forward;
    });

    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() {
        _flashForward = false;
        _flashRewind = false;
        _seekAccum = 0;
      });
    });
    _showControls();
  }

  void _setSpeed(double s) {
    setState(() => _speed = s);
    _vc?.setPlaybackSpeed(s);
  }

  // Press & hold → temporary 2× (YouTube-style)
  void _startBoost() {
    final vc = _vc;
    if (vc == null || !_vcReady || !vc.value.isPlaying) return;
    HapticFeedback.mediumImpact();
    vc.setPlaybackSpeed(2.0);
    setState(() => _boosting = true);
  }

  void _stopBoost() {
    if (!_boosting) return;
    _vc?.setPlaybackSpeed(_speed);
    if (mounted) setState(() => _boosting = false);
  }

  // ── Seek-bar callbacks ────────────────────────────────────────────────────

  void _onSeekStart(double f) {
    _hideTimer?.cancel();
    setState(() {
      _isSeeking = true;
      _seekFraction = f;
    });
  }

  void _onSeekUpdate(double f) => setState(() => _seekFraction = f);

  void _onSeekEnd() {
    final vc = _vc;
    if (vc != null && vc.value.isInitialized) {
      final ms = (_seekFraction * vc.value.duration.inMilliseconds).round();
      // Keep showing the scrub position until the seek really completes,
      // otherwise the thumb flickers back to the old position for a moment.
      vc.seekTo(Duration(milliseconds: ms)).whenComplete(() {
        if (mounted) setState(() => _isSeeking = false);
      });
    } else {
      setState(() => _isSeeking = false);
    }
    _startHideTimer();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lock
  // ─────────────────────────────────────────────────────────────────────────

  void _lock() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isLocked = true;
      _controlsShown = false;
    });
    _pokeLockHint();
  }

  void _unlock() {
    HapticFeedback.mediumImpact();
    _lockHintTimer?.cancel();
    setState(() {
      _isLocked = false;
      _lockHint = false;
      _controlsShown = true;
    });
    _startHideTimer();
  }

  void _pokeLockHint() {
    _lockHintTimer?.cancel();
    setState(() => _lockHint = true);
    _lockHintTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _lockHint = false);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Full-screen
  // ─────────────────────────────────────────────────────────────────────────

  /// Player allows sensor rotation (portrait / landscape-left / landscape-right)
  /// and sets up Picture-in-Picture (Android only: package:floating has no iOS side — D-061; iOS never
  /// sets _pipAvailable, so the Minimize button is not drawn there).
  void _initOrientationAndPip() {
    if (kIsWeb) return;
    SystemChrome.setPreferredOrientations(_allOrientations);

    if (defaultTargetPlatform == TargetPlatform.android) {
      _floating.isPipAvailable.then((ok) {
        if (mounted) setState(() => _pipAvailable = ok);
      });
      _pipSub = _floating.pipStatusStream.listen((s) {
        if (!mounted) return;
        final inPip = s == PiPStatus.enabled;
        setState(() => _inPip = inPip);
        if (inPip) {
          _hideTimer?.cancel();
        } else {
          _showControls();
        }
      });
    }
  }

  /// Auto mode: turning the phone sideways (left OR right) enters fullscreen,
  /// turning it back to portrait exits. Called from didChangeDependencies,
  /// so no setState is needed — the build that follows picks the value up.
  void _syncWithOrientation() {
    if (kIsWeb || !_autoRotate || _inPip) return;
    final mq = MediaQuery.of(context);
    if (mq.size.shortestSide >= 600) return; // tablets: don't force fullscreen
    final landscape = mq.orientation == Orientation.landscape;
    if (landscape == _isFullScreen) return;
    _isFullScreen = landscape;
    SystemChrome.setEnabledSystemUIMode(
        landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  /// Button → landscape. Both landscape sides stay allowed, so physically
  /// flipping the phone left/right still rotates the picture. Portrait is
  /// blocked until the user exits fullscreen or turns auto-rotate back on.
  void _enterFullScreen() {
    if (kIsWeb) {
      _enterWebFullScreen();
      return;
    }
    if (_isFullScreen) return;
    _autoRotate = false;
    // ONE landscape side only → the sensor can no longer flip or un-rotate it.
    SystemChrome.setPreferredOrientations(_landscapeOnly);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() => _isFullScreen = true);
  }

  /// Button → portrait (locked until auto-rotate is turned on again).
  void _exitFullScreen() {
    if (kIsWeb) {
      webfs.exitLandscapeFullscreen();
      setState(() {
        _isFullScreen = false;
        _webForceRotate = false;
      });
      return;
    }
    _autoRotate = false;
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    setState(() => _isFullScreen = false);
  }

  /// Web: real fullscreen + landscape lock where the browser allows it
  /// (Chrome / Android), otherwise the player rotates itself (iOS Safari).
  Future<void> _enterWebFullScreen() async {
    if (_isFullScreen) return;
    setState(() => _isFullScreen = true);
    final locked = await webfs.enterLandscapeFullscreen();
    if (!mounted) return;
    _webFsUnlisten ??= webfs.onFullscreenExit(() {
      // Esc / system back gesture left fullscreen → leave our fullscreen UI too.
      if (!mounted || !_isFullScreen) return;
      webfs.exitLandscapeFullscreen();
      setState(() {
        _isFullScreen = false;
        _webForceRotate = false;
      });
    });
    setState(() => _webForceRotate = !locked);
  }

  /// Rotation lock / auto-rotate toggle.
  void _toggleAutoRotate() {
    if (kIsWeb) return;
    HapticFeedback.selectionClick();
    final on = !_autoRotate;
    setState(() => _autoRotate = on);
    if (on) {
      SystemChrome.setPreferredOrientations(_allOrientations);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_syncWithOrientation);
      });
    } else {
      SystemChrome.setPreferredOrientations(
          _isFullScreen ? _landscapes : [DeviceOrientation.portraitUp]);
    }
    Helpers.showMessage(
        offlineT(on ? 'dl_rotation_auto' : 'dl_rotation_locked'));
  }

  // ── Offline download ──────────────────────────────────────────────────────

  Widget _buildDownloadBtn() {
    final svc = OfflineVideoService.instance;
    final id = svc.idOf(_mat.sessionId, _mat.id);
    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: svc.downloading,
      builder: (_, map, _) {
        final p = map[id];
        if (p != null) return _ProgressIconBtn(progress: p);
        return _GlassIconBtn(
          icon: _downloaded
              ? Icons.download_done_rounded
              : Icons.download_rounded,
          tooltip: offlineT(
              _downloaded ? 'dl_delete_title' : 'dl_tooltip_download'),
          onTap: _onDownloadTap,
        );
      },
    );
  }

  Future<void> _onDownloadTap() async {
    final svc = OfflineVideoService.instance;
    final sid = _mat.sessionId;
    final mid = _mat.id;

    // Already downloaded → offer to delete.
    if (_downloaded) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(offlineT('dl_delete_title')),
            content: Text(offlineT('dl_delete_body')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('cancel'.tr)),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('delete'.tr)),
            ],
          ),
        ),
      ) ??
          false;
      if (!ok || !mounted) return;
      await svc.delete(sid, mid);
      if (!mounted) return;
      if (_isOffline) {
        // We are playing that very file — close the player.
        Navigator.of(context).maybePop();
      } else {
        setState(() => _downloaded = false);
      }
      return;
    }

    // Download the stream that is currently playing.
    final url = _activeVariant.url;
    if (url == null || url.isEmpty) {
      Helpers.showMessage('video_not_available'.tr);
      return;
    }
    Helpers.showMessage(offlineT('dl_started'));
    try {
      await svc.download(
        sessionId: sid,
        materialId: mid,
        title: _mat.name,
        description: _mat.description,
        captionsUrl: _mat.captionsUrl,
        variant: _activeVariant,
      );
      if (!mounted) return;
      setState(() => _downloaded = true);
      Helpers.showMessage(offlineT('dl_done_offline'));
    } catch (_) {
      Helpers.showMessage(offlineT('dl_failed'));
    }
  }

  /// Minimize → system Picture-in-Picture window (Android 8+).
  Future<void> _enterPip() async {
    if (!_pipAvailable) {
      Helpers.showMessage(offlineT('dl_pip_unsupported'));
      return;
    }
    HapticFeedback.selectionClick();
    try {
      await _floating.enable(ImmediatePiP(aspectRatio: Rational.landscape()));
      // await _floating.enable();
    } catch (_) {
      Helpers.showMessage(offlineT('dl_pip_failed'));
    }
  }

  void _toggleFullScreen() {
    HapticFeedback.selectionClick();
    _isFullScreen ? _exitFullScreen() : _enterFullScreen();
  }

  void _restoreSystemUI() {
    if (kIsWeb) return;
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sheets
  // ─────────────────────────────────────────────────────────────────────────

  // Both sheets close with their OWN context (showVodPicker): inside a role shell the sheet sits on the root
  // navigator and the player on the tab's, so popping the player's context closed the player (the quality bug).

  Future<void> _openStreamPicker() async {
    _hideTimer?.cancel();
    // The last row, "Audio only", answers [vodAudioOnlyChoice]: the page closes and the lecture goes on as sound in
    // the bar at the top of the app (the same hand-off as the Listen button).
    final picked = await showVodPicker<Object>(
      context,
      (_, pick) => _StreamPickerSheet(
        material: _mat,
        activeVariant: _activeVariant,
        onSelect: pick,
        onAudioOnly: _canListen ? () => pick(vodAudioOnlyChoice) : null,
      ),
    );
    if (!mounted) return;
    _startHideTimer();
    if (identical(picked, vodAudioOnlyChoice)) {
      await _startListenOnly();
    } else if (picked is MaterialVariant) {
      await _switchVariant(picked);
    }
  }

  Future<void> _openSpeedSheet() async {
    _hideTimer?.cancel();
    final picked = await showVodPicker<double>(
      context,
      (_, pick) => _SpeedSheet(speeds: _speedOptions, current: _speed, onSelect: pick),
    );
    if (!mounted) return;
    _startHideTimer();
    if (picked != null) _setSpeed(picked);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  /// Rebuilds only the wrapped subtree when the controller value changes.
  Widget _withVc(Widget Function(VideoPlayerValue v) builder) {
    final vc = _vc;
    if (vc == null) return builder(const VideoPlayerValue.uninitialized());
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: vc,
      builder: (_, v, _) => builder(v),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    AppShellNav.markFullScreen(context); // the player takes the whole screen, even inside a tab (D-081)
    return PopScope(
      canPop: !_isFullScreen,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && _isFullScreen) _exitFullScreen();
      },
      child: Scaffold(
        backgroundColor: VodInk.letterbox,
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final body = _buildPlayerBody();
    final mq = MediaQuery.of(context);
    if (kIsWeb &&
        _isFullScreen &&
        _webForceRotate &&
        mq.orientation == Orientation.portrait) {
      return RotatedBox(
        quarterTurns: 1,
        child: MediaQuery(
          data: mq.copyWith(
            size: Size(mq.size.height, mq.size.width),
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.zero,
            viewInsets: EdgeInsets.zero,
          ),
          child: body,
        ),
      );
    }
    return body;
  }

  Widget _buildPlayerBody() {
    // The player chrome is always LTR so "left = rewind / right = forward"
    // and the seek bar direction are correct in RTL (Arabic) too. Text that
    // should follow the app direction (titles) gets it back explicitly.
    final appDir = Directionality.of(context);

    // Picture-in-Picture window: video only, no controls.
    if (_inPip) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Container(color: VodInk.letterbox, child: _buildBackground()),
      );
    }

    final mq = MediaQuery.of(context).padding;
    final bottomInset = _isFullScreen ? 0.0 : mq.bottom;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackground(),
          if (_dim > 0) IgnorePointer(child: ColoredBox(color: VodInk.shade(_dim))),
          if (_captionsOn)
            IgnorePointer(
              child: _withVc((v) => AnimatedPadding(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.fromLTRB(16, 0, 16, (_controlsShown ? 104 : 22) + bottomInset),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Directionality(textDirection: appDir, child: VodCaption(text: v.caption.text)),
                ),
              )),
            ),
          if (_isLocked) _buildLockCatcher() else _buildGestureZones(),
          _buildSeekFlash(),
          _buildBoostPill(),
          _withVc((v) => _buildOverlay(v, appDir)),
          if (_hud != null)
            IgnorePointer(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(top: (_isFullScreen ? 0 : mq.top) + 64),
                  child: VodLevelHud(brightness: _hud!.brightness, value: _hud!.value),
                ),
              ),
            ),
          if (_resumedAt != null && !_isLocked && !_isLoading)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 104 + bottomInset),
                child: Directionality(
                    textDirection: appDir, child: VodResumeChip(at: _resumedAt!, onStartOver: _startOver)),
              ),
            ),
          if (_isLocked) _buildLockPill(),
          if (_isLoading)
            _vcReady
                ? IgnorePointer(child: _buildLoadingState())
                : Directionality(
                    textDirection: appDir,
                    child: VodPlayerSkeleton(
                        title: _mat.name,
                        onBack: () => _isFullScreen ? _exitFullScreen() : Navigator.maybePop(context))),
          if (_hasError) _buildErrorState(),
        ],
      ),
    ),
    );
  }

  // ── Overlay (controls + mini progress + buffering) ────────────────────────

  Widget _buildOverlay(VideoPlayerValue v, TextDirection appDir) {
    final ready = _vcReady && v.isInitialized;
    final dur = ready ? v.duration : Duration.zero;
    final pos = ready ? v.position : Duration.zero;

    final fraction = dur.inMilliseconds > 0
        ? (_isSeeking ? _seekFraction : pos.inMilliseconds / dur.inMilliseconds)
        .clamp(0.0, 1.0)
        .toDouble()
        : 0.0;

    double buffered = 0;
    if (ready && v.buffered.isNotEmpty && dur.inMilliseconds > 0) {
      buffered = (v.buffered.last.end.inMilliseconds / dur.inMilliseconds)
          .clamp(0.0, 1.0)
          .toDouble();
    }

    final isPlaying = ready && v.isPlaying;
    final buffering = ready && v.isBuffering && !_isLoading;
    final finished = ready &&
        !v.isPlaying &&
        dur > Duration.zero &&
        pos >= dur - const Duration(milliseconds: 300);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (!_isLocked)
          IgnorePointer(
            ignoring: !_controlsShown,
            child: AnimatedOpacity(
              opacity: _controlsShown ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 240),
              child: _buildFullControls(
                appDir: appDir,
                isPlaying: isPlaying,
                finished: finished,
                buffering: buffering,
                fraction: fraction,
                buffered: buffered,
                pos: pos,
                dur: dur,
              ),
            ),
          ),
        if (finished && _next != null && !_isLocked)
          LayoutBuilder(builder: (_, box) {
            final narrow = box.maxWidth < 500;
            return Align(
              alignment: appDir == TextDirection.rtl ? Alignment.bottomLeft : Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 70, 16, box.maxHeight < 420 ? 64 : 104),
                child: Directionality(
                  textDirection: appDir,
                  child: VodNextUpCard(
                    next: _next!,
                    seconds: _nextIn,
                    maxWidth: narrow ? box.maxWidth - 32 : (box.maxWidth * 0.38).clamp(220.0, 360.0),
                    onPlay: _playNext,
                    onCancel: _stopNextTimer,
                  ),
                ),
              ),
            );
          }),
        // Thin progress line when controls are hidden
        if (!_controlsShown && !_isLocked)
          Align(
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(
              child: Container(
                height: 2.5,
                color: VodInk.ink(0.12),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(color: context.colors.primary),
                ),
              ),
            ),
          ),
        // Standalone buffering spinner while controls are hidden
        if (buffering && !_controlsShown)
          const IgnorePointer(
            child: Center(
              child: SizedBox(
                width: 46,
                height: 46,
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: VodInk.textHigh),
              ),
            ),
          ),
      ],
    );
  }

  // ── Background ────────────────────────────────────────────────────────────

  Widget _buildBackground() {
    if (_vcReady && _vc != null && !_isAudioMode && !_handingOff) {
      final ar = _vc!.value.aspectRatio;
      return Center(
        child: AspectRatio(
          aspectRatio: ar > 0 ? ar : 16 / 9,
          child: VideoPlayer(_vc!),
        ),
      );
    }
    return _buildAudioOnlyBg();
  }

  Widget _buildAudioOnlyBg() {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.6,
          colors: [c.primaryDark.withValues(alpha: 0.6), VodInk.letterbox],
        ),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ScaleTransition(
            scale: _pulseAnim,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.primary.withValues(alpha: 0.10),
                border: Border.all(
                    color: c.primary.withValues(alpha: 0.25), width: 2),
                boxShadow: [
                  BoxShadow(
                      color: c.primary.withValues(alpha: 0.25),
                      blurRadius: 50,
                      spreadRadius: 4),
                ],
              ),
              child: Container(
                margin: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.primary.withValues(alpha: 0.18),
                ),
                child:
                Icon(Icons.music_note_rounded, size: 56, color: c.primary),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 52),
            child: Text(_mat.name,
                style: c.h3.copyWith(color: VodInk.textHigh),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
          if (_mat.description != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 52),
              child: Text(_mat.description!,
                  style: c.body.copyWith(color: VodInk.textSoft),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
          const SizedBox(height: 16),
          _GlassPill(
            label: _activeVariant.fullLabel,
            icon: Icons.headphones_rounded,
            color: c.primary,
          ),
        ]),
      ),
    );
  }

  // ── Gesture zones ─────────────────────────────────────────────────────────

  Widget _buildGestureZones() {
    Widget zone({required bool forward}) => Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _toggleControls,
        onDoubleTap: () => _seekRelative(10, forward: forward),
        onLongPressStart: forward ? (_) => _startBoost() : null,
        onLongPressEnd: forward ? (_) => _stopBoost() : null,
        onLongPressCancel: forward ? _stopBoost : null,
        // Mobile: swipe up/down — left half = brightness, right half = volume.
        onVerticalDragUpdate: _touchDevice ? (d) => _onLevelDrag(d, brightness: !forward) : null,
        onVerticalDragEnd: _touchDevice ? (_) => _flashHud(!forward) : null,
      ),
    );
    return Row(children: [zone(forward: false), zone(forward: true)]);
  }

  /// While locked: swallow all touches, tapping only reveals the unlock pill.
  Widget _buildLockCatcher() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _pokeLockHint,
  );

  // ── Seek flash ────────────────────────────────────────────────────────────

  Widget _buildSeekFlash() {
    Widget half({required bool active, required bool forward}) => Expanded(
      child: AnimatedOpacity(
        opacity: active ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              // FIX: glow now comes from the screen edge the user tapped
              center: forward ? Alignment.centerRight : Alignment.centerLeft,
              radius: 1.2,
              colors: [
                VodInk.ink(0.16),
                Colors.transparent
              ],
            ),
          ),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                forward
                    ? Icons.fast_forward_rounded
                    : Icons.fast_rewind_rounded,
                color: VodInk.textHigh,
                size: 44,
              ),
              const SizedBox(height: 4),
              Text(forward ? '+${_seekAccum}s' : '-${_seekAccum}s',
                  style: TextStyle(
                      color: VodInk.textHigh,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      fontFamily: AppFonts.family)),
            ]),
          ),
        ),
      ),
    );

    return IgnorePointer(
      child: Row(children: [
        half(active: _flashRewind, forward: false),
        half(active: _flashForward, forward: true),
      ]),
    );
  }

  Widget _buildBoostPill() {
    final c = context.colors;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(
              top: (_isFullScreen ? 14 : MediaQuery.of(context).padding.top) + 12),
          child: AnimatedOpacity(
            opacity: _boosting ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: VodInk.shade(0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: c.primary.withValues(alpha: 0.6)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.fast_forward_rounded, color: VodInk.textHigh, size: 16),
                SizedBox(width: 6),
                Text('2×',
                    style: TextStyle(
                        color: VodInk.textHigh,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        fontFamily: AppFonts.family)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── Full controls ─────────────────────────────────────────────────────────

  Widget _buildFullControls({
    required TextDirection appDir,
    required bool isPlaying,
    required bool finished,
    required bool buffering,
    required double fraction,
    required double buffered,
    required Duration pos,
    required Duration dur,
  }) {
    return Column(children: [
      _buildTopBar(appDir),
      Expanded(
        child: _buildCenterRow(
            isPlaying: isPlaying, finished: finished, buffering: buffering),
      ),
      _buildBottomPanel(
          fraction: fraction, buffered: buffered, pos: pos, dur: dur),
    ]);
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar(TextDirection appDir) {
    final c = context.colors;
    final mq = MediaQuery.of(context).padding;
    final top = _isFullScreen ? 10.0 : mq.top;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [VodInk.shade(0.78), Colors.transparent],
        ),
      ),
      // Respect notch / camera cut-out in landscape.
      padding: EdgeInsets.fromLTRB(6 + mq.left, top, 10 + mq.right, 24),
      child: Row(children: [
        IconButton(
          tooltip: t('رجوع', 'Back'),
          onPressed: () =>
          _isFullScreen ? _exitFullScreen() : Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: VodInk.textHigh, size: 20),
        ),
        Expanded(
          // Titles follow the app language direction (Arabic = right aligned).
          child: Directionality(
            textDirection: appDir,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_mat.name,
                    style: c.h4.copyWith(color: VodInk.textHigh),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (_mat.description != null)
                  Text(_mat.description!,
                      style: c.caption.copyWith(color: VodInk.textSoft),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                if (_isOffline)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: _InfoChip(
                        icon: Icons.offline_pin_rounded,
                        label: offlineT('dl_on_device')),
                  ),
                // FIX: _viewsNote was computed but never shown anywhere.
                if (_viewsNote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: _InfoChip(
                        icon: Icons.visibility_outlined, label: _viewsNote!),
                  ),
              ],
            ),
          ),
        ),
        // Phones: the quality is on the chip below already; the title and "Listen" need the room.
        if (MediaQuery.sizeOf(context).width >= 600) ...[
          _ActiveStreamBadge(variant: _activeVariant),
          const SizedBox(width: 6),
        ],
        if (_canDownload) ...[
          _buildDownloadBtn(),
          const SizedBox(width: 6),
        ],
        if (_pipAvailable && !_isAudioMode) ...[
          _GlassIconBtn(
            icon: Icons.picture_in_picture_alt_rounded,
            tooltip: offlineT('dl_minimize'),
            onTap: _enterPip,
          ),
          const SizedBox(width: 6),
        ],
        if (_canListen) ...[
          VodListenButton(
            label: MediaQuery.sizeOf(context).width >= 360 ? 'vod_listen_short'.tr : null,
            tooltip: 'vod_listen_only_hint'.tr,
            onTap: _startListenOnly,
          ),
          const SizedBox(width: 6),
        ],
        _GlassIconBtn(
          icon: Icons.lock_open_rounded,
          tooltip: 'lock_controls'.tr,
          onTap: _lock,
        ),
      ]),
    );
  }

  // ── Center play row ───────────────────────────────────────────────────────

  Widget _buildCenterRow({
    required bool isPlaying,
    required bool finished,
    required bool buffering,
  }) {
    final c = context.colors;
    return Center(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _CircleCtrlBtn(
          label: t('رجوع 10 ثوانٍ', 'Back 10 seconds'),
          icon: Icons.replay_10_rounded,
          size: 32,
          onTap: () => _seekRelative(10, forward: false),
        ),
        const SizedBox(width: 28),
        Semantics(
          button: true,
          label: finished ? t('إعادة التشغيل', 'Replay') : (isPlaying ? t('إيقاف مؤقت', 'Pause') : t('تشغيل', 'Play')),
          child: _PressScale(
          onTap: finished ? _replay : _togglePlayPause,
          child: Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.primary.withValues(alpha: 0.92),
              border: Border.all(
                  color: VodInk.ink(0.25), width: 1.5),
              boxShadow: [
                ...c.primaryShadow,
                BoxShadow(
                    color: VodInk.shade(0.4), blurRadius: 24),
              ],
            ),
            child: buffering
                ? const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: VodInk.textHigh),
            )
                : AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                finished
                    ? Icons.replay_rounded
                    : (isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded),
                key: ValueKey('$finished$isPlaying'),
                color: VodInk.textHigh,
                size: 44,
              ),
            ),
          ),
        )),
        const SizedBox(width: 28),
        _CircleCtrlBtn(
          label: t('تقديم 10 ثوانٍ', 'Forward 10 seconds'),
          icon: Icons.forward_10_rounded,
          size: 32,
          onTap: () => _seekRelative(10, forward: true),
        ),
      ]),
    );
  }

  // ── Bottom panel ──────────────────────────────────────────────────────────

  Widget _buildBottomPanel({
    required double fraction,
    required double buffered,
    required Duration pos,
    required Duration dur,
  }) {
    final c = context.colors;
    final mq = MediaQuery.of(context).padding;
    final bot = _isFullScreen ? 10.0 : mq.bottom + 4;

    final scrubLabel = _fmt(
        Duration(milliseconds: (_seekFraction * dur.inMilliseconds).round()));

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [VodInk.shade(0.88), Colors.transparent],
        ),
      ),
      padding: EdgeInsets.fromLTRB(16 + mq.left, 28, 16 + mq.right, bot),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ── Seek bar ──────────────────────────────────────────────────────
        _SeekBar(
          fraction: fraction,
          buffered: buffered,
          dragging: _isSeeking,
          accent: c.primary,
          previewLabel: scrubLabel,
          onStart: _onSeekStart,
          onUpdate: _onSeekUpdate,
          onEnd: _onSeekEnd,
        ),

        const SizedBox(height: 2),

        // ── Controls row ──────────────────────────────────────────────────
        Row(children: [
          Text(
              '${_fmt(_isSeeking ? Duration(milliseconds: (_seekFraction * dur.inMilliseconds).round()) : pos)} / ${_fmt(dur)}',
              style: TextStyle(
                  color: VodInk.textMid,
                  fontSize: 11.5,
                  fontFamily: AppFonts.family,
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          // FittedBox: the right-hand group scales down instead of
          // overflowing on narrow phones.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                // Only when the material really has more than one stream.
                if (_mat.availableVariants.length > 1) ...[
                  _ControlChip(
                    icon: _isAudioMode
                        ? Icons.headphones_rounded
                        : Icons.hd_rounded,
                    label: _activeVariant.label,
                    active: _isAudioMode,
                    onTap: _openStreamPicker,
                  ),
                  const SizedBox(width: 6),
                ],

                if (_hasCaptions) ...[
                  _ControlChip(
                    icon: _captionsOn ? Icons.closed_caption_rounded : Icons.closed_caption_off_rounded,
                    label: 'CC',
                    active: _captionsOn,
                    onTap: _toggleCaptions,
                  ),
                  const SizedBox(width: 6),
                ],
                if (_list.length > 1) ...[
                  _ControlChip(
                    icon: Icons.playlist_play_rounded,
                    label: t('المحاضرات', 'Lectures'),
                    active: false,
                    onTap: _openLectures,
                  ),
                  const SizedBox(width: 6),
                ],
                _ControlChip(
                  icon: Icons.speed_rounded,
                  label: _speed == 1.0 ? 'normal_speed'.tr : '$_speed×',
                  active: _speed != 1.0,
                  onTap: _openSpeedSheet,
                ),
                const SizedBox(width: 10),
                if (!_touchDevice) ...[
                  Tooltip(
                    message: t('كتم (M)', 'Mute (M)'),
                    child: _PressScale(
                      onTap: _toggleMute,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Icon(_volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                            color: VodInk.textHigh, size: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                if (_next != null) ...[
                  Tooltip(
                    message: t('التالي (N)', 'Next (N)'),
                    child: _PressScale(
                      onTap: _playNext,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.skip_next_rounded, color: VodInk.textHigh, size: 26),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],

                // Rotation: auto (sensor, left/right/portrait) vs locked.
                if (!kIsWeb) ...[
                  Tooltip(
                    message: t('تدوير الشاشة تلقائياً', 'Auto-rotate'),
                    child: _PressScale(
                    onTap: _toggleAutoRotate,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        _autoRotate
                            ? Icons.screen_rotation_rounded
                            : Icons.screen_lock_rotation_rounded,
                        color: _autoRotate ? VodInk.textHigh : c.primary,
                        size: 24,
                      ),
                    ),
                  )),
                  const SizedBox(width: 10),
                ],

                // Fullscreen: locks landscape (sensor ignored) / back to portrait.
                _FullscreenButton(
                  active: _isFullScreen,
                  accent: c.primary,
                  onTap: _toggleFullScreen,
                ),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }

  // ── Lock pill ─────────────────────────────────────────────────────────────

  Widget _buildLockPill() {
    final mq = MediaQuery.of(context).padding;
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.only(right: 20 + mq.right),
        child: IgnorePointer(
          ignoring: !_lockHint,
          child: AnimatedOpacity(
            opacity: _lockHint ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            child: GestureDetector(
              onTap: _unlock,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: VodInk.ink(0.14),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                          color: VodInk.ink(0.24)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.lock_rounded,
                          color: VodInk.textHigh, size: 18),
                      const SizedBox(width: 8),
                      Text('unlock_controls'.tr,
                          style: TextStyle(
                              color: VodInk.textHigh,
                              fontSize: 12,
                              fontFamily: AppFonts.family,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Loading / Error ───────────────────────────────────────────────────────

  Widget _buildLoadingState() {
    return Container(
      // Dim the last frame while switching quality so the change is obvious.
      color: _vcReady ? VodInk.shade(0.45) : Colors.transparent,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 44, height: 44, child: AppLoadingIndicator()),
          const SizedBox(height: 14),
          Text((_switching ? 'vod_switching' : 'loading_video').tr,
              style: TextStyle(
                  color: VodInk.textSoft, fontSize: 13, fontFamily: AppFonts.family)),
        ]),
      ),
    );
  }

  Widget _buildErrorState() {
    final c = context.colors;
    return Container(
      color: VodInk.shade(0.88),
      child: SafeArea(
        child: Stack(children: [
          // Back button always reachable on the error screen.
          Align(
            alignment: AlignmentDirectional.topStart,
            child: IconButton(
              tooltip: t('رجوع', 'Back'),
              onPressed: () => _isFullScreen
                  ? _exitFullScreen()
                  : Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: VodInk.textHigh, size: 20),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.danger.withValues(alpha: 0.14)),
                  child: Icon(Icons.error_outline_rounded,
                      color: c.danger, size: 44),
                ),
                const SizedBox(height: 20),
                Text('video_load_error'.tr,
                    style: c.h4.copyWith(color: VodInk.textHigh),
                    textAlign: TextAlign.center),
                const SizedBox(height: 28),
                _PressScale(
                  onTap: _retry,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                    decoration: BoxDecoration(
                        color: c.primary,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: c.primaryShadow),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.refresh_rounded,
                          color: VodInk.textHigh, size: 18),
                      const SizedBox(width: 8),
                      Text('retry'.tr,
                          style: TextStyle(
                              color: VodInk.textHigh,
                              fontWeight: FontWeight.w700,
                              fontFamily: AppFonts.family,
                              fontSize: 14)),
                    ]),
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

// ════════════════════════════════════════════════════════════════════════════
// _SeekBar — custom: aligned buffer + progress + thumb + scrub-time bubble
// ════════════════════════════════════════════════════════════════════════════

class _SeekBar extends StatelessWidget {
  const _SeekBar({
    required this.fraction,
    required this.buffered,
    required this.dragging,
    required this.accent,
    required this.previewLabel,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final double fraction;
  final double buffered;
  final bool dragging;
  final Color accent;
  final String previewLabel;
  final void Function(double) onStart;
  final void Function(double) onUpdate;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth;
      double toFrac(Offset p) =>
          w <= 0 ? 0.0 : (p.dx / w).clamp(0.0, 1.0).toDouble();

      final trackH = dragging ? 6.0 : 4.0;
      final thumb = dragging ? 18.0 : 12.0;
      final x = (fraction * w).clamp(0.0, w).toDouble();
      const dur = Duration(milliseconds: 120);

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          onStart(toFrac(d.localPosition));
          onEnd();
        },
        onHorizontalDragStart: (d) => onStart(toFrac(d.localPosition)),
        onHorizontalDragUpdate: (d) => onUpdate(toFrac(d.localPosition)),
        onHorizontalDragEnd: (_) => onEnd(),
        onHorizontalDragCancel: onEnd,
        child: SizedBox(
          height: 34,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              // track
              AnimatedContainer(
                duration: dur,
                height: trackH,
                width: w,
                decoration: BoxDecoration(
                  color: VodInk.ink(0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              // buffered
              AnimatedContainer(
                duration: dur,
                height: trackH,
                width: w * buffered,
                decoration: BoxDecoration(
                  color: VodInk.ink(0.34),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              // played
              AnimatedContainer(
                duration: dur,
                height: trackH,
                width: x,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              // thumb
              Positioned(
                left: x - thumb / 2,
                child: AnimatedContainer(
                  duration: dur,
                  width: thumb,
                  height: thumb,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: VodInk.textHigh,
                    boxShadow: [
                      BoxShadow(
                          color: accent.withValues(alpha: 0.55),
                          blurRadius: dragging ? 12 : 6),
                    ],
                  ),
                ),
              ),
              // scrub-time bubble
              if (dragging)
                Positioned(
                  top: -30,
                  left: (x - 30).clamp(0.0, (w - 60).clamp(0.0, w)).toDouble(),
                  child: Container(
                    width: 60,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: VodInk.shade(0.75),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: accent.withValues(alpha: 0.6)),
                    ),
                    child: Text(previewLabel,
                        style: TextStyle(
                            color: VodInk.textHigh,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            fontFamily: AppFonts.family)),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Bottom sheets
// ════════════════════════════════════════════════════════════════════════════

/// Shared sheet shell: rounded card, handle, scrollable (so it never overflows
/// in landscape) and width-limited (so it doesn't stretch across a tablet).
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mq = MediaQuery.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1.0,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: mq.size.height * 0.88,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(24, 12, 24, mq.padding.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: c.divider, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 18),
            Flexible(child: SingleChildScrollView(child: child)),
          ]),
        ),
      ),
    );
  }
}

class _StreamPickerSheet extends StatelessWidget {
  const _StreamPickerSheet({
    required this.material,
    required this.activeVariant,
    required this.onSelect,
    this.onAudioOnly,
  });

  final SessionMaterialModel material;
  final MaterialVariant activeVariant;
  final void Function(MaterialVariant) onSelect;

  /// "Audio only": close the video and go on as sound in the bar (null while the stream is not ready).
  final VoidCallback? onAudioOnly;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final videoVariants = material.videoVariants;

    return _SheetFrame(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.tune_rounded, color: c.primary, size: 20),
          const SizedBox(width: 8),
          Text('stream_quality'.tr, style: c.h3),
        ]),
        const SizedBox(height: 20),
        _SectionHeader(
          icon: Icons.videocam_rounded,
          label: 'video'.tr,
          color: c.primary,
        ),
        const SizedBox(height: 8),
        ...videoVariants.map((v) => _VariantTile(
          variant: v,
          selected: v.url == activeVariant.url,
          onTap: () => onSelect(v),
        )),
        // One "Audio only" row (the bar picks the lecture's audio track itself, else the lightest picture).
        if (onAudioOnly != null) ...[
          const SizedBox(height: 16),
          _SectionHeader(
            icon: Icons.headphones_rounded,
            label: 'audio_only'.tr,
            color: c.accent2,
          ),
          const SizedBox(height: 8),
          VodAudioOnlyTile(onTap: onAudioOnly!),
        ],
      ]),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 14),
      ),
      const SizedBox(width: 8),
      Text(label,
          style: c.caption.copyWith(
              color: c.textMedium,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8)),
      const SizedBox(width: 8),
      Expanded(child: Divider(color: c.divider, height: 1)),
    ]);
  }
}

class _VariantTile extends StatelessWidget {
  const _VariantTile(
      {required this.variant, required this.selected, required this.onTap});

  final MaterialVariant variant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accentColor =
    variant.isAudio ? c.accent2 : c.primary;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? accentColor.withValues(alpha: 0.10)
              : c.inputBg.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? accentColor.withValues(alpha: 0.45)
                : c.divider.withValues(alpha: 0.5),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? accentColor.withValues(alpha: 0.15)
                  : c.divider.withValues(alpha: 0.3),
            ),
            child: Icon(
              variant.isAudio
                  ? Icons.headphones_rounded
                  : _videoIcon(variant.tier),
              size: 18,
              color: selected ? accentColor : c.textLight,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  variant.fullLabel,
                  style: c.bodyBold.copyWith(
                    color: selected ? accentColor : c.textDark,
                    fontSize: 13,
                  ),
                ),
                if (variant.sizeLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(variant.sizeLabel,
                      style:
                      c.caption.copyWith(color: c.textLight, fontSize: 11)),
                ],
              ],
            ),
          ),
          if (!variant.isOriginal)
            _QualityBadge(
                variant: variant, selected: selected, accent: accentColor),
          const SizedBox(width: 8),
          AnimatedOpacity(
            opacity: selected ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
            child:
            Icon(Icons.check_circle_rounded, color: accentColor, size: 20),
          ),
        ]),
      ),
    );
  }

  IconData _videoIcon(QualityTier tier) {
    switch (tier) {
      case QualityTier.high:
        return Icons.hd_rounded;
      case QualityTier.medium:
        return Icons.sd_rounded;
      case QualityTier.low:
        return Icons.video_settings_rounded;
    }
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge(
      {required this.variant, required this.selected, required this.accent});

  final MaterialVariant variant;
  final bool selected;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final badgeText = variant.isAudio
        ? (variant.tier == QualityTier.high ? 'HQ' : 'MQ')
        : variant.tier.label;

    final tierColor = variant.isAudio
        ? accent
        : switch (variant.tier) {
      QualityTier.high => c.warning,
      QualityTier.medium => c.success,
      QualityTier.low => c.textLight,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tierColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: tierColor.withValues(alpha: selected ? 0.50 : 0.25)),
      ),
      child: Text(
        badgeText,
        style: TextStyle(
          color: tierColor,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          fontFamily: AppFonts.family,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ActiveStreamBadge extends StatelessWidget {
  const _ActiveStreamBadge({required this.variant});

  final MaterialVariant variant;

  @override
  Widget build(BuildContext context) {
    if (variant.isOriginal) return const SizedBox.shrink();
    final c = context.colors;
    final color = variant.isAudio ? c.accent2 : c.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
            variant.isAudio
                ? Icons.headphones_rounded
                : Icons.play_circle_outline_rounded,
            size: 11,
            color: color),
        const SizedBox(width: 4),
        Text(variant.label,
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                fontFamily: AppFonts.family)),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Reusable micro-widgets
// ════════════════════════════════════════════════════════════════════════════

/// Download-in-progress indicator that matches [_GlassIconBtn].
class _ProgressIconBtn extends StatelessWidget {
  const _ProgressIconBtn({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: VodInk.ink(0.10),
      border: Border.all(color: VodInk.ink(0.18)),
    ),
    alignment: Alignment.center,
    child: Stack(alignment: Alignment.center, children: [
      SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          // 0 → indeterminate until the first bytes arrive
          value: progress > 0 ? progress : null,
          strokeWidth: 2.5,
          color: VodInk.textHigh,
          backgroundColor: VodInk.glassBorder,
        ),
      ),
      const Icon(Icons.arrow_downward_rounded,
          size: 11, color: VodInk.textHigh),
    ]),
  );
}

/// Subtle press-down scale for every tappable control (premium feel).
class _PressScale extends StatefulWidget {
  const _PressScale({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: widget.child,
      ),
    );
  }
}

class _CircleCtrlBtn extends StatelessWidget {
  const _CircleCtrlBtn(
      {required this.icon, required this.size, required this.onTap, required this.label});

  final String label;
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: _PressScale(
    onTap: onTap,
    child: Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: VodInk.ink(0.12),
        border: Border.all(color: VodInk.ink(0.14)),
      ),
      child: Icon(icon, color: VodInk.textHigh, size: size),
    ),
  ));
}

/// Premium fullscreen toggle: glass tile that lights up in the accent colour
/// (with a soft glow) while fullscreen is on; the icon rotates + scales on swap.
class _FullscreenButton extends StatelessWidget {
  const _FullscreenButton({
    required this.active,
    required this.accent,
    required this.onTap,
  });

  final bool active;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final deep = HSLColor.fromColor(accent)
        .withLightness(
        (HSLColor.fromColor(accent).lightness - 0.12).clamp(0.0, 1.0))
        .toColor();
    return _PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: active
                ? [accent, deep]
                : [
              VodInk.ink(0.18),
              VodInk.ink(0.06),
            ],
          ),
          border: Border.all(
            color: active
                ? VodInk.ink(0.35)
                : VodInk.ink(0.22),
          ),
          boxShadow: active
              ? [
            BoxShadow(
              color: accent.withValues(alpha: 0.45),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ]
              : const [],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) => RotationTransition(
            turns: Tween(begin: 0.85, end: 1.0).animate(anim),
            child: ScaleTransition(scale: anim, child: child),
          ),
          child: Icon(
            active
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            key: ValueKey(active),
            color: VodInk.textHigh,
            size: 26,
          ),
        ),
      ),
    );
  }
}

class _GlassIconBtn extends StatelessWidget {
  const _GlassIconBtn({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? '',
    child: _PressScale(
      onTap: onTap,
      // 38 px glass disc inside a 48 px touch target.
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: VodInk.ink(0.10),
          border: Border.all(color: VodInk.ink(0.18)),
        ),
        child: Icon(icon, color: VodInk.textMid, size: 18),
      )),
      ),
    ),
  );
}

class _ControlChip extends StatelessWidget {
  const _ControlChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? c.primary.withValues(alpha: 0.90)
              : VodInk.ink(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active
                  ? c.primary.withValues(alpha: 0.60)
                  : VodInk.ink(0.20)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: active ? VodInk.textHigh : VodInk.textMid),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: active ? VodInk.textHigh : VodInk.textMid,
                  fontSize: 11,
                  fontFamily: AppFonts.family,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: VodInk.ink(0.10),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: VodInk.ink(0.16)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: VodInk.textMid),
      const SizedBox(width: 4),
      Flexible(
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: VodInk.textMid,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                fontFamily: AppFonts.family)),
      ),
    ]),
  );
}

class _GlassPill extends StatelessWidget {
  const _GlassPill(
      {required this.label, required this.icon, required this.color});

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 14),
      const SizedBox(width: 6),
      Text(label,
          style: TextStyle(
              color: color,
              fontSize: 12,
              fontFamily: AppFonts.family,
              fontWeight: FontWeight.w700)),
    ]),
  );
}

// ── Speed sheet ───────────────────────────────────────────────────────────────

class _SpeedSheet extends StatelessWidget {
  const _SpeedSheet(
      {required this.speeds, required this.current, required this.onSelect});

  final List<double> speeds;
  final double current;
  final void Function(double) onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _SheetFrame(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('select_speed'.tr, style: c.h3),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: speeds.map((s) {
            final sel = s == current;
            final label = s == 1.0 ? 'normal_speed'.tr : '$s×';
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onSelect(s);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 80,
                height: 48,
                decoration: BoxDecoration(
                  color: sel ? c.primary : c.inputBg,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: sel ? c.primaryShadow : [],
                ),
                alignment: Alignment.center,
                child: Text(label,
                    style: c.bodyBold.copyWith(
                        color: sel ? c.onHero : c.textMedium,
                        fontSize: 13)),
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }
}