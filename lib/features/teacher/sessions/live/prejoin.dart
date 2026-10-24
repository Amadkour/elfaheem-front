import 'dart:async';
import 'dart:developer';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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
import '../../../../core/api_client.dart';
import '../sessions_provider.dart';
import 'local_debug_save.dart';
import 'prejoin_layout.dart';
import 'prejoin_mic_meter_stub.dart'
    if (dart.library.js_interop) 'prejoin_mic_meter_web.dart' as mic_meter;
import 'room.dart';
// ─────────────────────────────────────────────────────────────────────────────
// JoinArgs
// ─────────────────────────────────────────────────────────────────────────────
class JoinArgs {
  JoinArgs({
    this.e2ee = false,
    this.e2eeKey,
    this.simulcast = true,
    this.adaptiveStream = true,
    this.dynacast = true,
    this.preferredCodec = 'VP8',
    this.enableBackupVideoCodec = true,
    required this.sessionId,
    required this.courseId,
    this.maxStudents,
    required this.isTeacher,
    required this.userName,
    required this.userId,
    required this.onStart,
    required this.onEnd,
    this.onComplete,
    this.sessionName,
    // ── NEW: ApiClient passed through so RoomPage can upload chunks ──────────
    required this.apiClient,
    this.guest = false,
    this.canPublish = true,
  });

  /// True for a visitor who came through a public guest link: no account, no token.
  /// The room then skips every authenticated call (attendance, quizzes, participants…).
  final bool guest;

  /// False → the participant may only watch and listen: the pre-join screen creates no
  /// microphone / camera tracks and the room shows only Leave, reactions and audio output.
  final bool canPublish;

  late final int? sessionId;
  final int courseId;
  final int? maxStudents;
  final bool e2ee;
  final bool isTeacher;
  final String userName;
  final int userId;
  final String? e2eeKey;
  final bool simulcast;
  final bool adaptiveStream;
  final bool dynacast;
  final String preferredCodec;
  final bool enableBackupVideoCodec;

  /// Optional session / meeting name shown on the pre-join screen
  /// (falls back to the generic "Live session").
  final String? sessionName;

  /// For teachers:  calls POST /live-sessions/start  → returns LiveResponseModel
  /// For students:  calls GET  /live-sessions/{id}/join → returns LiveResponseModel
  final Future<dynamic> Function() onStart;

  /// Called when the session ends (teacher taps End, or room disconnects).
  final Future<dynamic> Function() onEnd;

  /// Called after a student leaves the room. Triggers POST /sessions/{id}/complete.
  final Future<void> Function()? onComplete;

  /// ApiClient instance scoped to the authenticated user.
  /// Passed down to RoomPage → _ClientRecorder for chunk upload auth.
  final ApiClient apiClient;
}

// ─────────────────────────────────────────────────────────────────────────────
// PreJoinPage — device setup + the join plumbing. The layout lives in
// prejoin_layout.dart (PreJoinLayout) so it can be tested without LiveKit.
// ─────────────────────────────────────────────────────────────────────────────
class PreJoinPage extends StatefulWidget {
  const PreJoinPage({required this.args, super.key});

  final JoinArgs args;

  @override
  State<StatefulWidget> createState() => _PreJoinPageState();
}

class _PreJoinPageState extends State<PreJoinPage> {
  List<MediaDevice> _audioInputs = [];
  List<MediaDevice> _videoInputs = [];
  StreamSubscription? _subscription;

  bool _busy = false;
  bool _enableVideo = true;
  bool _enableAudio = true;

  /// Set once the room took over the tracks: dispose must not stop them then.
  bool _joined = false;

  /// Why the devices are unusable (permission denied / nothing found), or null.
  PreJoinIssue? _issue;

  LocalAudioTrack? _audioTrack;
  LocalVideoTrack? _videoTrack;
  Map<String, dynamic>? _selectedVideoDevice;
  Map<String, dynamic>? _selectedAudioDevice;

  /// Web only: live 0–1 microphone level of [_audioTrack] (null → no meter drawn).
  double? _micLevel;
  StreamSubscription<double>? _micLevelSub;

  void _watchMicLevel() {
    unawaited(_micLevelSub?.cancel());
    _micLevelSub = null;
    final track = _audioTrack;
    if (!kIsWeb || track == null) {
      if (_micLevel != null && mounted) setState(() => _micLevel = null);
      return;
    }
    _micLevelSub = mic_meter.micLevelStream(track.mediaStream).listen((v) {
      if (!mounted || !_enableAudio) return;
      // Quantised to the meter's 8 segments: no rebuild while the level stays in the same segment.
      final q = (v * 8).round() / 8;
      if (q != _micLevel) setState(() => _micLevel = q);
    }, onError: (_) {});
  }

  static const _bestResolution = VideoParametersPresets.h1080_169;

  bool get _canPublish => widget.args.canPublish;

  @override
  void initState() {
    super.initState();
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
    _enableVideo = true;
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
        _videoTrack = await LocalVideoTrack.createCameraTrack(
          CameraCaptureOptions(
            deviceId: _selectedVideoDevice!['device_id'] as String,
            cameraPosition: CameraPosition.front,
            maxFrameRate: 60,
            params: _bestResolution,
          ),
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

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_micLevelSub?.cancel());
    if (!_joined) {
      // Left without joining (system back, swipe): release the camera and mic.
      unawaited(_audioTrack?.stop());
      unawaited(_videoTrack?.stop());
    }
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
      const cameraEncoding = VideoEncoding(
        maxBitrate: 5 * 1000 * 1000,
        maxFramerate: 60,
      );
      const screenEncoding = VideoEncoding(
        maxBitrate: 4 * 1000 * 1000,
        maxFramerate: 30,
      );
      late int localSessionId;
      if (args.sessionId==null && !args.guest){
        final TeacherSessionItem? r = await context.read<TeacherCourseScreenProvider>().quickSession(courseId: args.courseId);
        if(r ==null){
          Helpers.showMessage('failed to create session'.tr, isError: true);
        }else {
          localSessionId = r.id;
        }
      }
      final room = Room(
        roomOptions: RoomOptions(
          adaptiveStream: args.adaptiveStream,
          dynacast: args.dynacast,
          defaultAudioPublishOptions: const AudioPublishOptions(
            encoding: AudioEncoding(maxBitrate: 128000),
            dtx: false,
            red: true,
          ),
          defaultCameraCaptureOptions: const CameraCaptureOptions(
            cameraPosition: CameraPosition.front,
            maxFrameRate: 60,
            params: VideoParameters(
              dimensions: VideoDimensionsPresets.h1080_169,
            ),
          ),
          defaultScreenShareCaptureOptions: const ScreenShareCaptureOptions(
            captureScreenAudio: true,
            maxFrameRate: 30,
            params: VideoParametersPresets.screenShareH1080FPS15,
          ),
          defaultVideoPublishOptions: VideoPublishOptions(
            simulcast: args.simulcast,
            videoCodec: args.preferredCodec,
            degradationPreference: DegradationPreference.balanced,
            backupVideoCodec: BackupVideoCodec(
              enabled: args.enableBackupVideoCodec,
            ),
            videoEncoding: cameraEncoding,
            screenShareEncoding: screenEncoding,
          ),
        ),
      );

      final listener = room.createListener();
      final data = await args.onStart() as LiveResponseModel?;
      if (data == null) {
        throw Exception('No LiveResponseModel returned from onStart');
      }

      await room.prepareConnection(data.url, data.token);
      await room.connect(
        data.url,
        data.token,
        fastConnectOptions: FastConnectOptions(
          microphone: TrackOption(track: _audioTrack),
          camera: TrackOption(track: _videoTrack),
        ),
      );
      _joined = true;

      if (!context.mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => RoomPage(
            room,
            listener,
            fastConnection: true,
            onEnd: () async {
              LocalDebugSave.stop();
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
          ),
        ),
      );

      // Student live-completion: fire after room page pops
      if (!args.isTeacher) {
        await args.onComplete?.call();
      } else {
        LocalDebugSave.start();
      }
    } catch (error) {
      log('PreJoinPage._join error: $error');
      if (!context.mounted) return;
      await context.showErrorDialog(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  Future<void> _back() async {
    if (_enableVideo) await _toggleCamera();
    if (_enableAudio) await _toggleAudio();
    if (mounted) Navigator.of(context).pop();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    LivePalette.sync(context);   // live classroom colours follow the app theme
    final args = widget.args;
    final title = (args.sessionName ?? '').trim();
    return Scaffold(
      key: const ValueKey('prejoin'),
      backgroundColor: context.colors.background,
      body: PreJoinLayout(
        title: title.isNotEmpty ? title : 'lr_live_session'.tr,
        subtitle: 'lr_ready_to_join'.tr,
        isTeacher: args.isTeacher,
        isGuest: args.guest,
        canPublish: args.canPublish,
        userName: args.userName,
        preview: _videoTrack != null && _enableVideo
            ? VideoTrackRenderer(
                _videoTrack!,
                renderMode: VideoRenderMode.texture,
                fit: VideoViewFit.cover,
                mirrorMode: VideoViewMirrorMode.mirror,
              )
            : null,
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
      ),
    );
  }
}
