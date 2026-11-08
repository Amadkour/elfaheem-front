import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_shell_nav.dart' show AppShellNav;
import 'package:livekit_client/livekit_client.dart';
import 'widgets/live_palette.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../utils/helpers.dart';
import '../../../student/models.dart';
import '../components/exts.dart';
import '../model/live_response_model.dart';
import '../sessions_provider.dart';
import 'prejoin_layout.dart';
import 'prejoin_mic_meter_stub.dart'
    if (dart.library.js_interop) 'prejoin_mic_meter_web.dart' as mic_meter;
import 'join_args.dart';
import 'room.dart';
import 'widgets/live_room_rules.dart' show liveConnectRetryDelay;
import 'widgets/share_presets.dart' show SharePreset;
import 'widgets/live_video_view.dart';
import 'package:flutter_education_app/features/shared/live/live_self_view.dart';
import 'package:flutter_education_app/features/shared/rag/app_assistant.dart' show AppAssistant;
import 'package:flutter_education_app/features/shared/live/live_room.dart';
import 'package:flutter_education_app/features/shared/live/live_room_words.dart' show liveTr;
import 'package:flutter_education_app/features/shared/live/live_config.dart';
import 'package:flutter_education_app/features/shared/live/live_media_plan.dart';
import 'package:flutter_education_app/features/shared/live/live_lobby_sheets.dart' show WaitingForHostPage;
import 'package:flutter_education_app/features/shared/live/live_mini_box.dart' show LiveMiniTile;
import 'package:flutter_education_app/features/shared/live/live_room_host.dart';
import 'package:flutter_education_app/features/shared/live/live_controls_api.dart' show liveJoinRefusalText;
import 'package:flutter_education_app/design/app_kit.dart' show appToast;
import 'package:flutter_education_app/features/shared/points/points_api.dart' show LivePlanDeclined;
export 'join_args.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PreJoinPage — device setup + the join plumbing. The layout lives in
// prejoin_layout.dart (PreJoinLayout) so it can be tested without LiveKit.
// ─────────────────────────────────────────────────────────────────────────────
class PreJoinPage extends StatefulWidget {
  const PreJoinPage({required this.args, super.key, this.startMic = true, this.startCam});

  final JoinArgs args;

  /// The microphone / camera to start with (a Rejoin restores what the person had in the room, D9). A null
  /// [startCam] follows the super admin's `participants_camera_default_off` (D-090): a student's camera starts off
  /// and no camera track exists until they turn it on; a host's starts on.
  final bool startMic;
  final bool? startCam;

  @override
  State<StatefulWidget> createState() => _PreJoinPageState();
}

class _PreJoinPageState extends State<PreJoinPage> {
  List<MediaDevice> _audioInputs = [];
  List<MediaDevice> _videoInputs = [];
  StreamSubscription? _subscription;

  bool _busy = false;

  /// The live media settings: the last ones a join answered with until this join answers (D-090).
  LiveConfig _config = LiveConfig.lastKnown;

  /// The camera started off because of the participants' default (the page says why).
  late final bool _cameraOffByDefault = widget.startCam == null && !_config.cameraStartsOn(host: widget.args.hostRole);
  late bool _enableVideo = widget.startCam ?? _config.cameraStartsOn(host: widget.args.hostRole);
  late bool _enableAudio = widget.startMic;

  /// Set once the room took over the tracks: dispose must not stop them then.
  bool _joined = false;

  /// Why the devices are unusable (permission denied / nothing found), or null.
  PreJoinIssue? _issue;

  LocalAudioTrack? _audioTrack;
  LocalVideoTrack? _videoTrack;
  Map<String, dynamic>? _selectedVideoDevice;
  Map<String, dynamic>? _selectedAudioDevice;

  /// Live 0–1 microphone level of [_audioTrack] (null → no meter drawn): an AudioContext analyser on the web,
  /// LiveKit's native visualizer on Android / iOS (prejoin_mic_meter_*.dart).
  double? _micLevel;
  StreamSubscription<double>? _micLevelSub;

  void _watchMicLevel() {
    unawaited(_micLevelSub?.cancel());
    _micLevelSub = null;
    final track = _audioTrack;
    if (track == null) {
      if (_micLevel != null && mounted) setState(() => _micLevel = null);
      return;
    }
    _micLevelSub = mic_meter.micLevelStream(track).listen((v) {
      if (!mounted || !_enableAudio) return;
      // Quantised to the meter's 8 segments: no rebuild while the level stays in the same segment.
      final q = (v * 8).round() / 8;
      if (q != _micLevel) setState(() => _micLevel = q);
    }, onError: (_) {});
  }

  bool get _canPublish => widget.args.canPublish;

  // D-106: nothing here presses Join — not after the devices are ready, not for Meet now / Go live / Live now / a
  // direct guest link / a Rejoin. The person checks the preview and presses Join (focused; Enter on the web).

  @override
  void initState() {
    super.initState();
    AppAssistant.hide(); // full screen: no floating assistant bubble
    // D-092: the preview takes the self-view's remembered shape.
    SelfViewStore.instance.addListener(_onSelfViewPrefs);
    unawaited(SelfViewStore.instance.load());
    if (!_canPublish) {
      // Listen-only guest: no tracks are ever created, no permission prompt.
      _enableAudio = false;
      _enableVideo = false;
      return;
    }
    unawaited(_initDevices());
    if (lkPlatformIs(PlatformType.android)) unawaited(_checkPermissions());
  }

  Future<void> _checkPermissions() async {
    for (final perm in [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.camera,
      Permission.microphone,
      Permission.ignoreBatteryOptimizations,
      Permission.audio,
    ]) {
      final s = await perm.request();
      if (s.isPermanentlyDenied) log('$perm permanently denied');
    }
  }

  Future<void> _initDevices() async {
    _subscription = Hardware.instance.onDeviceChange.stream.listen(
      _loadDevices,
    );
    await _enumerate();
  }

  Future<void> _enumerate() async {
    try {
      await _loadDevices(await Hardware.instance.enumerateDevices());
    } catch (e) {
      log('PreJoin: enumerateDevices failed: $e');
      _issue = PreJoinIssue.permissionDenied;
      if (mounted) setState(() {});
    }
  }

  /// Retry after a permission or device problem: ask again, re-enumerate.
  Future<void> _retry() async {
    if (lkPlatformIs(PlatformType.android)) await _checkPermissions();
    _issue = null;
    _selectedAudioDevice = null;
    _selectedVideoDevice = null;
    _enableAudio = true;
    _enableVideo = widget.startCam ?? _config.cameraStartsOn(host: widget.args.hostRole);
    if (mounted) setState(() {});
    await _enumerate();
  }

  @override
  void deactivate() {
    unawaited(_subscription?.cancel());
    super.deactivate();
  }

  Future<void> _loadDevices(List<MediaDevice> devices) async {
    _audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
    _videoInputs = devices.where((d) => d.kind == 'videoinput').toList();

    if (_audioInputs.isEmpty && _videoInputs.isEmpty) {
      _issue ??= PreJoinIssue.noDevices;
    } else if (_issue == PreJoinIssue.noDevices) {
      _issue = null;
    }

    if (_enableAudio &&
        _audioInputs.isNotEmpty &&
        _selectedAudioDevice == null) {
      _selectedAudioDevice = _audioOptions.first;
      await _changeLocalAudioTrack();
    }

    // On Flutter Web without a camera, _videoInputs is empty — that's fine.
    // The teacher can still join and the client recorder will use screen share or audio.
    if (_enableVideo &&
        _videoInputs.isNotEmpty &&
        _selectedVideoDevice == null) {
      final opts = _videoOptions;
      _selectedVideoDevice = opts.firstWhere(
            (d) => d['is_front'] == true,
        orElse: () => opts.first,
      );
      await _changeLocalVideoTrack();
    } else if (_enableVideo && _videoInputs.isEmpty) {
      // No camera available — disable video silently rather than showing error
      _enableVideo = false;
      log(
        'PreJoin: no camera found — video disabled, continuing with audio/screen share',
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleCamera() async {
    _enableVideo = !_enableVideo;
    if (!_enableVideo) {
      await _videoTrack?.stop();
      _videoTrack = null;
    } else {
      if (_selectedVideoDevice == null && _videoOptions.isNotEmpty) {
        final opts = _videoOptions;
        _selectedVideoDevice = opts.firstWhere(
              (d) => d['is_front'] == true,
          orElse: () => opts.first,
        );
      }
      await _changeLocalVideoTrack();
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleAudio() async {
    _enableAudio = !_enableAudio;
    if (!_enableAudio) {
      await _audioTrack?.stop();
      _audioTrack = null;
      _watchMicLevel();
    } else {
      if (_selectedAudioDevice == null && _audioOptions.isNotEmpty) {
        _selectedAudioDevice = _audioOptions.first;
      }
      await _changeLocalAudioTrack();
    }
    if (mounted) setState(() {});
  }

  Future<void> _selectAudio(String deviceId) async {
    final opt = _audioOptions.where((d) => d['device_id'] == deviceId).toList();
    if (opt.isEmpty) return;
    _selectedAudioDevice = opt.first;
    if (_enableAudio) await _changeLocalAudioTrack();
    if (mounted) setState(() {});
  }

  Future<void> _selectVideo(String deviceId) async {
    final opt = _videoOptions.where((d) => d['device_id'] == deviceId).toList();
    if (opt.isEmpty) return;
    _selectedVideoDevice = opt.first;
    if (_enableVideo) await _changeLocalVideoTrack();
    if (mounted) setState(() {});
  }

  Future<void> _changeLocalAudioTrack() async {
    if (!_enableAudio) return;
    await _audioTrack?.stop();
    _audioTrack = null;
    if (_selectedAudioDevice != null) {
      try {
        _audioTrack = await LocalAudioTrack.create(
          AudioCaptureOptions(
            deviceId: _selectedAudioDevice!['device_id'] as String,
          ),
        );
        await _audioTrack!.start();
      } catch (e) {
        // Typically the browser / OS refused the microphone.
        log('PreJoin: microphone track failed: $e');
        _audioTrack = null;
        _enableAudio = false;
        _issue = PreJoinIssue.permissionDenied;
      }
    }
    _watchMicLevel();
  }

  Future<void> _changeLocalVideoTrack() async {
    if (!_enableVideo) return;
    await _videoTrack?.stop();
    _videoTrack = null;
    if (_selectedVideoDevice != null) {
      try {
        // D-090: the role's cap at camera_fps (was 1080p60 for everyone) — the capture is what the camera, the
        // encoder and every later unmute (a muted camera restarts with these options) cost.
        _videoTrack = await LocalVideoTrack.createCameraTrack(
          cameraCaptureFor(_config, host: widget.args.hostRole, deviceId: _selectedVideoDevice!['device_id'] as String),
        );
        await _videoTrack!.start();
      } catch (e) {
        log('PreJoin: camera track failed: $e');
        _videoTrack = null;
        _enableVideo = false;
        _issue = PreJoinIssue.permissionDenied;
      }
    }
  }

  void _onSelfViewPrefs() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SelfViewStore.instance.removeListener(_onSelfViewPrefs);
    unawaited(_subscription?.cancel());
    unawaited(_micLevelSub?.cancel());
    if (!_joined) {
      // Left without joining (system back, swipe): release the camera and mic.
      unawaited(_audioTrack?.stop());
      unawaited(_videoTrack?.stop());
    }
    AppAssistant.release();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // _join  — connects to LiveKit, pushes RoomPage, then calls onComplete
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _join(BuildContext context) async {
    _busy = true;
    setState(() {});
    final args = widget.args;

    try {
      late int localSessionId;
      if (args.sessionId==null && !args.guest){
        final TeacherSessionItem? r = await context.read<TeacherCourseScreenProvider>().quickSession(courseId: args.courseId);
        if(r ==null){
          Helpers.showMessage('failed to create session'.tr, isError: true);
          return;
        }
        localSessionId = r.id;
      }
      // D-090: everything the room publishes follows the super admin's live_config of THIS join (read when the Room
      // is made, after the join answered): the camera cap per role at camera_fps with explicit simulcast layers,
      // the codec (+ VP8 backup), Opus DTX / RED, the screen share's ceilings. Adaptive stream + dynacast stay on.
      Room newRoom() {
        final cfg = _config;
        final host = args.hostRole;
        final codec = effectiveVideoCodec(cfg.videoCodec, LiveCodecPlatform.current());
        // D14: what still goes through setScreenShareEnabled (iOS, desktop) gets "Detail" with the config's ceilings;
        // Android and the web publish their own track with the mode the presenter picked.
        final screen = SharePreset.detail.tuned(cfg, codec: codec);
        final screenEncoding = screen.encoding;
        return Room(
        roomOptions: RoomOptions(
          adaptiveStream: args.adaptiveStream,
          dynacast: args.dynacast,
          defaultAudioPublishOptions: audioPublishFor(cfg, host: host),
          defaultCameraCaptureOptions: cameraCaptureFor(cfg, host: host),
          // iOS (I1): LiveKit publishes the share by itself on iOS_BroadcastStarted with THESE options (no
          // per-call options then); `useiOSBroadcastExtension` picks the extension's socket ('broadcast-manual').
          // Ignored on the other platforms.
          defaultScreenShareCaptureOptions: ScreenShareCaptureOptions(
            useiOSBroadcastExtension: true,
            captureScreenAudio: true,
            maxFrameRate: screen.maxFps.toDouble(),
            params: VideoParameters(dimensions: VideoDimensionsPresets.h1080_169, encoding: screenEncoding),
          ),
          defaultVideoPublishOptions: () {
            final o = videoPublishFor(cfg, host: host, codec: codec, screenEncoding: screenEncoding);
            return o.copyWith(
              simulcast: args.simulcast,
              backupVideoCodec: args.enableBackupVideoCodec ? o.backupVideoCodec : const BackupVideoCodec(enabled: false),
            );
          }(),
        ),
      );
      }

      final sessionId = args.sessionId ?? localSessionId;
      final data = await _resolveJoin(args, sessionId);
      if (data == null) return; // waiting cancelled, or the host refused: stay on the pre-join page

      // D-090: this join's live_config. A preview captured with other settings (the last join's, or the defaults)
      // is made again so the published camera is the configured one.
      LiveConfig.remember(data.liveConfig);
      _config = data.liveConfig;
      final preview = _videoTrack;
      if (preview != null && _enableVideo &&
          cameraCaptureDiffers(preview.currentOptions, cameraCaptureFor(_config, host: args.hostRole))) {
        await _changeLocalVideoTrack();
        if (mounted) setState(() {});
      }

      // D10: a network failure is tried twice more (after 1 s, then 3 s) with a fresh Room and fresh tracks (a
      // failed connect cleans its Room up and stops what it had published); a refused token (4xx) is not. A Room
      // that never connected is disposed with its listener.
      final (room, listener) = await _connectWithRetry(newRoom, data);
      _joined = true;

      if (!context.mounted) {
        await listener.dispose();
        await room.dispose();
        return;
      }
      final nav = Navigator.of(context);
      final page = RoomPage(
        room,
        listener,
        fastConnection: true,
        onEnd: () async {
          args.onEnd.call();
        },
        isTeacher: args.isTeacher,
        courseId: args.courseId,
        sessionId: args.sessionId??localSessionId,
        // ── Passes the authenticated ApiClient so _ClientRecorder can
        //    upload chunks with the correct Bearer token ─────────────────
        apiClient: args.apiClient,
        // ── Prejoin audio/video toggle state ─────────────────────────────
        enableAudio: _enableAudio,
        enableVideo: _enableVideo,
        recordingEnabled: data.recordingEnabled,
        sessionName: args.sessionName,
        isGuest: args.guest,
        canPublish: args.canPublish,
        roomRef: args.ref,
        isHost: args.isHost,
        isOwner: args.isOwner,
        canRecord: args.canRecord, // [meeting-recording]
        freeEndsAt: data.freeEndsAt,
        liveStartedAt: data.liveStartedAt,
        liveConfig: data.liveConfig,
        startsAt: args.startsAt,
        hostName: args.hostName,
        // D9: Rejoin opens this page again for the same session, with the room's mic / camera choices; it waits for Join (D-106).
        onRejoin: (micOn, camOn) {
          if (!nav.mounted) return;
          unawaited(nav.push(MaterialPageRoute<void>(
            builder: (_) => PreJoinPage(args: args.forRejoin(sessionId: sessionId), startMic: micOn, startCam: camOn),
          )));
        },
      );
      await _showRoom(context, page, room);

      // Student live-completion: fires after the room closed
      if (!args.isTeacher) {
        await args.onComplete?.call();
      }
    } catch (error) {
      // The owner closed the live-plan sheet without subscribing: stay here quietly (spec §8).
      if (error is LivePlanDeclined) return;
      log('PreJoinPage._join error: $error');
      if (!context.mounted) return;
      // The host's controls refused the join (423 room_locked, 403 participant_removed / guest_blocked): say why,
      // never retry (a 4xx; liveConnectRetryDelay retries only network failures).
      await context.showErrorDialog(liveJoinRefusalText(error, kind: args.ref.kind) ?? error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Connects a new Room from [newRoom]; network failures are retried per [liveConnectRetryDelay]. Every Room
  /// that failed is disposed (with its listener) before the next try or the rethrow.
  Future<(Room, EventsListener<RoomEvent>)> _connectWithRetry(Room Function() newRoom, LiveResponseModel data) async {
    for (var attempt = 0;; attempt++) {
      final room = newRoom();
      final listener = room.createListener();
      try {
        try {
          await room.prepareConnection(data.url, data.token);
        } catch (e) {
          log('PreJoin: prepareConnection: $e'); // a warm-up only
        }
        await room.connect(
          data.url,
          data.token,
          fastConnectOptions: FastConnectOptions(
            microphone: TrackOption(track: _audioTrack),
            camera: TrackOption(track: _videoTrack),
          ),
        );
        return (room, listener);
      } catch (e) {
        await listener.dispose();
        await room.dispose();
        final wait = liveConnectRetryDelay(e, attempt);
        if (wait == null || !mounted) rethrow;
        log('PreJoin: connect failed (${attempt + 1}), retrying in ${wait.inSeconds}s: $e');
        await Future<void>.delayed(wait);
        if (!mounted) rethrow;
        // The failed Room stopped the tracks it had published: start fresh ones with the same choices.
        await _changeLocalAudioTrack();
        await _changeLocalVideoTrack();
      }
    }
  }

  // ── Lobby: onStart may answer "waiting" ───────────────────────────────────

  /// Runs `onStart` and turns its answer into room credentials. A `JoinOutcome.waiting` pushes
  /// [WaitingForHostPage] over this page and polls until the host decides; null means "do not join"
  /// (cancelled, rejected, expired — the person is told and stays here).
  Future<LiveResponseModel?> _resolveJoin(JoinArgs args, int sessionId) async {
    final res = await args.onStart();
    if (res is LiveResponseModel) return res;
    if (res == null) throw Exception('No LiveResponseModel returned from onStart');
    if (res is! JoinOutcome) throw Exception('Unexpected onStart answer: ${res.runtimeType}');
    var outcome = res;
    if (outcome.isWaiting) {
      if (!mounted) return null;
      final admitted = await Navigator.of(context).push<JoinOutcome>(
        MaterialPageRoute(
          builder: (_) => WaitingForHostPage(waiting: outcome, title: _title, poll: args.onPoll),
        ),
      );
      if (admitted == null) return null;
      outcome = admitted;
    }
    if (outcome.isRefused) {
      appToast(
          liveRoomCodeText(outcome.status == JoinStatus.rejected ? 'join_rejected' : 'request_expired', kind: args.ref.kind) ?? '',
          error: true);
      return null;
    }
    if (outcome.url.isEmpty || outcome.token.isEmpty) throw Exception('Join answered without room credentials');
    return outcome.live(sessionId: sessionId);
  }

  // ── Device option lists ───────────────────────────────────────────────────

  List<Map<String, dynamic>> get _videoOptions => _videoInputs
      .map<Map<String, dynamic>>(
        (d) => <String, dynamic>{
      'text': d.label.isNotEmpty ? d.label : 'lr_camera'.tr,
      'value': d.toString(),
      'is_front': d.label.toLowerCase().contains('front'),
      'device_id': d.deviceId,
    },
  )
      .toList();

  List<Map<String, dynamic>> get _audioOptions => _audioInputs
      .map<Map<String, dynamic>>(
        (d) => <String, dynamic>{
      'text': d.label.isNotEmpty ? d.label : 'lr_microphone'.tr,
      'value': d.toString(),
      'device_id': d.deviceId,
    },
  )
      .toList();

  /// Plain `(id, label)` pairs for the layout; unnamed devices get "Microphone 1", "Camera 2", …
  List<PreJoinDevice> _asDevices(List<MediaDevice> list, String fallback) => [
        for (var i = 0; i < list.length; i++)
          (list[i].deviceId, list[i].label.isNotEmpty ? list[i].label : '$fallback ${i + 1}'),
      ];

  /// Shows the room. Normally in [LiveRoomLayer] above the Navigator, so it can be minimized to a box while
  /// the person moves around the app: this pre-join page stays beneath the full-screen room and takes itself
  /// off the stack the moment the room is minimized (it would show behind the box) or closed — what the
  /// room's own second pop did. Without a layer (tests, an older host) the room is pushed as a route.
  Future<void> _showRoom(BuildContext context, RoomPage page, Room room) async {
    if (!LiveRoomHost.isInstalled) {
      await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => page));
      return;
    }
    final handle = LiveRoomHost.open(LiveRoomSession(
      title: _title,
      page: page,
      mini: (_) => LiveMiniTile(room: room),
    ));
    void onMinimized() {
      if (handle.minimized.value) _dismissSelf();
    }

    handle.minimized.addListener(onMinimized);
    await handle.closed;
    handle.minimized.removeListener(onMinimized);
    _dismissSelf();
  }

  /// Takes this page off the stack: pops when it is on top, else removes it from underneath (a notification
  /// may have pushed a page while the room was full-screen).
  void _dismissSelf() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final nav = Navigator.of(context);
    if (route.isCurrent) {
      nav.pop();
    } else {
      nav.removeRoute(route);
    }
  }

  Future<void> _back() async {
    if (_enableVideo) await _toggleCamera();
    if (_enableAudio) await _toggleAudio();
    if (mounted) Navigator.of(context).pop();
  }

  /// The room's name, or "Live session" / "Live meeting" by its kind (D-106).
  String get _title {
    final name = (widget.args.sessionName ?? '').trim();
    return name.isNotEmpty ? name : liveTr('lr_live_session', widget.args.ref.kind);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    LivePalette.sync(context);   // live classroom colours follow the app theme
    AppShellNav.markFullScreen(context); // no tab bar on the pre-join page, even inside a tab (D-081)
    final args = widget.args;
    return Scaffold(
      key: const ValueKey('prejoin'),
      backgroundColor: context.colors.background,
      body: PreJoinLayout(
        title: _title,
        subtitle: 'lr_ready_to_join'.tr,
        // D-106: a calendar meeting («اجتماع») or a course session («الحصة») — from roomRef / the -meetingId id.
        roomKind: args.ref.kind,
        isHost: args.hostRole,
        isTeacher: args.isTeacher,
        isGuest: args.guest,
        canPublish: args.canPublish,
        userName: args.userName,
        // D-092: LiveVideoView (this page rebuilds on every mic-level sample; the renderer no longer re-attaches),
        // in the self-view's remembered shape — the same box or circle as in the room.
        preview: _videoTrack != null && _enableVideo
            ? LiveVideoView(_videoTrack!, fit: VideoViewFit.cover, mirror: VideoViewMirrorMode.mirror)
            : null,
        previewShape: SelfViewStore.instance.value.shape,
        onPreviewShape: (s) => unawaited(SelfViewStore.instance.update(SelfViewStore.instance.value.copyWith(shape: s))),
        micOn: _enableAudio,
        camOn: _enableVideo,
        micLevel: _enableAudio && _audioTrack != null ? _micLevel : null,
        onToggleMic: _audioInputs.isEmpty && !_enableAudio ? null : _toggleAudio,
        onToggleCam: _videoInputs.isEmpty && !_enableVideo ? null : _toggleCamera,
        mics: _asDevices(_audioInputs, 'lr_microphone'.tr),
        cams: _asDevices(_videoInputs, 'lr_camera'.tr),
        selectedMic: _selectedAudioDevice?['device_id'] as String?,
        selectedCam: _selectedVideoDevice?['device_id'] as String?,
        onMicChanged: _selectAudio,
        onCamChanged: _selectVideo,
        busy: _busy,
        onJoin: _busy ? null : () => _join(context),
        onBack: _back,
        issue: _issue,
        onRetry: _retry,
        cameraOffHint: _cameraOffByDefault && !_enableVideo && _videoInputs.isNotEmpty,
      ),
    );
  }
}
