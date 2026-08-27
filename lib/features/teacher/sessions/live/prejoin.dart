import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import '../components/exts.dart';
import '../model/live_response_model.dart';
import '../../../../core/api_client.dart';
import 'local_debug_save.dart';
import 'room.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
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
    // ── NEW: ApiClient passed through so RoomPage can upload chunks ──────────
    required this.apiClient,
  });

  final int sessionId;
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
// Design System (local, matches room.dart)
// ─────────────────────────────────────────────────────────────────────────────
class _DS {
  static const bg = Color(0xFF060810);
  static const surfaceHi = Color(0xFF151826);
  static const cyan = Color(0xFF00D4FF);
  static const indigo = Color(0xFF6B6EF9);
  static const rose = Color(0xFFFF4F72);
  static const textHigh = Color(0xFFFFFFFF);
  static const textLow = Color(0x66FFFFFF);
  static const glass10 = Color(0x1AFFFFFF);
  static const glass15 = Color(0x26FFFFFF);
  static const glassBdr = Color(0x30FFFFFF);

  static const camOnGrad = [Color(0xFF00D4FF), Color(0xFF6B6EF9)];
  static const camOffGrad = [Color(0xFFFF4F72), Color(0xFFFF8C42)];
  static const joinGrad = [
    Color(0xFF00D4FF),
    Color(0xFF6B6EF9),
    Color(0xFF9B59F5),
  ];
  static const micOnGrad = [Color(0xFF00E5A0), Color(0xFF00C4D4)];
  static const micOffGrad = [Color(0xFFFF4F72), Color(0xFFFF8C42)];
}

// ─────────────────────────────────────────────────────────────────────────────
// PreJoinPage
// ─────────────────────────────────────────────────────────────────────────────
class PreJoinPage extends StatefulWidget {
  const PreJoinPage({required this.args, super.key});

  final JoinArgs args;

  @override
  State<StatefulWidget> createState() => _PreJoinPageState();
}

class _PreJoinPageState extends State<PreJoinPage>
    with TickerProviderStateMixin {
  List<MediaDevice> _audioInputs = [];
  List<MediaDevice> _videoInputs = [];
  StreamSubscription? _subscription;

  bool _busy = false;
  bool _enableVideo = true;
  bool _enableAudio = true;

  LocalAudioTrack? _audioTrack;
  LocalVideoTrack? _videoTrack;
  Map<String, dynamic>? _selectedVideoDevice;
  Map<String, dynamic>? _selectedAudioDevice;

  static const _bestResolution = VideoParametersPresets.h1080_169;

  late AnimationController _masterFade;
  late AnimationController _joinPressAnim;
  late AnimationController _pulseAnim;
  late AnimationController _auroraAnim;
  late Animation<double> _fadeIn;
  late Animation<double> _slideUp;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();

    _masterFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeIn = CurvedAnimation(parent: _masterFade, curve: Curves.easeOut);
    _slideUp = CurvedAnimation(
      parent: _masterFade,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
    );

    _joinPressAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );

    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseAnim, curve: Curves.easeInOut);

    _auroraAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _masterFade.forward();
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
    await _loadDevices(await Hardware.instance.enumerateDevices());
  }

  @override
  void deactivate() {
    unawaited(_subscription?.cancel());
    super.deactivate();
  }

  Future<void> _loadDevices(List<MediaDevice> devices) async {
    _audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
    _videoInputs = devices.where((d) => d.kind == 'videoinput').toList();

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
    setState(() {});
  }

  Future<void> _toggleAudio() async {
    _enableAudio = !_enableAudio;
    if (!_enableAudio) {
      await _audioTrack?.stop();
      _audioTrack = null;
    } else {
      if (_selectedAudioDevice == null && _audioOptions.isNotEmpty) {
        _selectedAudioDevice = _audioOptions.first;
      }
      await _changeLocalAudioTrack();
    }
    setState(() {});
  }

  Future<void> _changeLocalAudioTrack() async {
    if (!_enableAudio) return;
    await _audioTrack?.stop();
    _audioTrack = null;
    if (_selectedAudioDevice != null) {
      _audioTrack = await LocalAudioTrack.create(
        AudioCaptureOptions(
          deviceId: _selectedAudioDevice!['device_id'] as String,
        ),
      );
      await _audioTrack!.start();
    }
  }

  Future<void> _changeLocalVideoTrack() async {
    if (!_enableVideo) return;
    await _videoTrack?.stop();
    _videoTrack = null;
    if (_selectedVideoDevice != null) {
      _videoTrack = await LocalVideoTrack.createCameraTrack(
        CameraCaptureOptions(
          deviceId: _selectedVideoDevice!['device_id'] as String,
          cameraPosition: CameraPosition.front,
          maxFrameRate: 60,
          params: _bestResolution,
        ),
      );
      await _videoTrack!.start();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _masterFade.dispose();
    _joinPressAnim.dispose();
    _pulseAnim.dispose();
    _auroraAnim.dispose();
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
      if (data == null)
        throw Exception('No LiveResponseModel returned from onStart');

      await room.prepareConnection(data.url, data.token);
      await room.connect(
        data.url,
        data.token,
        fastConnectOptions: FastConnectOptions(
          microphone: TrackOption(track: _audioTrack),
          camera: TrackOption(track: _videoTrack),
        ),
      );

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
            sessionId: args.sessionId,
            // ── Passes the authenticated ApiClient so _ClientRecorder can
            //    upload chunks with the correct Bearer token ─────────────────
            apiClient: args.apiClient,
            // ── Prejoin audio/video toggle state ─────────────────────────────
            enableAudio: _enableAudio,
            enableVideo: _enableVideo,
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
          'text': d.label.isNotEmpty ? d.label : 'Camera',
          'value': d.toString(),
          'is_front': d.label.toLowerCase().contains('front'),
          'device_id': d.deviceId,
        },
      )
      .toList();

  List<Map<String, dynamic>> get _audioOptions => _audioInputs
      .map<Map<String, dynamic>>(
        (d) => <String, dynamic>{
          'text': d.label.isNotEmpty ? d.label : 'Microphone',
          'value': d.toString(),
          'device_id': d.deviceId,
        },
      )
      .toList();

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(),
      child: Scaffold(
        backgroundColor: _DS.bg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Animated aurora mesh
            AnimatedBuilder(
              animation: _auroraAnim,
              builder: (_, _) => CustomPaint(
                painter: _AuroraPainter(_auroraAnim.value),
                child: const SizedBox.expand(),
              ),
            ),

            // Full-screen camera preview
            FadeTransition(opacity: _fadeIn, child: _buildCameraPreview()),

            // Bottom scrim
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: MediaQuery.of(context).size.height * 0.50,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      _DS.bg.withValues(alpha: 0.72),
                      _DS.bg.withValues(alpha: 0.96),
                      _DS.bg,
                    ],
                    stops: const [0.0, 0.28, 0.6, 1.0],
                  ),
                ),
              ),
            ),

            // Top scrim
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 130,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _DS.bg.withValues(alpha: 0.85),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // UI content
            SafeArea(
              child: Column(
                children: [
                  FadeTransition(opacity: _fadeIn, child: _buildTopBar()),
                  const SizedBox(height: 10),
                  const Spacer(),
                  SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.25),
                      end: Offset.zero,
                    ).animate(_slideUp),
                    child: FadeTransition(
                      opacity: _fadeIn,
                      child: _buildBottomSection(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Camera preview ────────────────────────────────────────────────────────
  Widget _buildCameraPreview() {
    if (_videoTrack != null && _enableVideo) {
      return VideoTrackRenderer(
        renderMode: VideoRenderMode.texture,
        fit: VideoViewFit.cover,
        _videoTrack!,
      );
    }
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) => Container(
        color: _DS.bg,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 160,
                height: 160,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer ring
                    Container(
                      width: 150 + _pulse.value * 10,
                      height: 150 + _pulse.value * 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: (_enableVideo ? _DS.cyan : _DS.rose)
                              .withValues(alpha: 0.12 + _pulse.value * 0.08),
                          width: 1,
                        ),
                      ),
                    ),
                    // Middle ring
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: (_enableVideo ? _DS.cyan : _DS.rose)
                              .withValues(alpha: 0.2 + _pulse.value * 0.1),
                          width: 1,
                        ),
                      ),
                    ),
                    // Core
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            (_enableVideo ? _DS.cyan : _DS.rose).withValues(
                              alpha: 0.18 + _pulse.value * 0.1,
                            ),
                            Colors.transparent,
                          ],
                        ),
                        border: Border.all(
                          color: (_enableVideo ? _DS.cyan : _DS.rose)
                              .withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        _enableVideo
                            ? Icons.videocam_rounded
                            : Icons.videocam_off_rounded,
                        color: (_enableVideo ? _DS.cyan : _DS.rose).withValues(
                          alpha: 0.9,
                        ),
                        size: 36,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _enableVideo
                    ? 'Starting camera…'
                    : (_videoInputs.isEmpty
                          ? 'No camera — screen share will be recorded'
                          : 'Camera is off'),
                style: TextStyle(
                  fontFamily: 'tajawal',
                  color: _DS.textLow,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _GlassIconButton(
            onTap: () async {
              if (_enableVideo) await _toggleCamera();
              if (_enableAudio) await _toggleAudio();
              if (mounted) Navigator.of(context).pop();
            },
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: _DS.textHigh,
              size: 17,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ready to join?',
                style: TextStyle(
                  fontFamily: 'tajawal',
                  color: _DS.textHigh,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Check your devices below',
                style: TextStyle(
                  fontFamily: 'tajawal',
                  color: _DS.textLow,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Pulsing 1080p badge
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, _) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                gradient: LinearGradient(
                  colors: [
                    _DS.cyan.withValues(alpha: 0.14 + _pulse.value * 0.07),
                    _DS.indigo.withValues(alpha: 0.14 + _pulse.value * 0.07),
                  ],
                ),
                border: Border.all(
                  color: _DS.cyan.withValues(alpha: 0.38 + _pulse.value * 0.14),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _DS.cyan.withValues(
                      alpha: 0.10 + _pulse.value * 0.08,
                    ),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.hd_rounded,
                    color: _DS.cyan.withValues(alpha: 0.9),
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '1080p',
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      color: _DS.cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom section ────────────────────────────────────────────────────────
  Widget _buildBottomSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Camera + Mic cards
          Row(
            children: [
              Expanded(
                child: _buildDeviceCard(
                  icon: _enableVideo
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                  label: 'Camera',
                  sublabel: _enableVideo ? 'Front · 1080p' : 'Disabled',
                  isActive: _enableVideo,
                  gradColors: _enableVideo ? _DS.camOnGrad : _DS.camOffGrad,
                  onTap: _toggleCamera,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDeviceCard(
                  icon: _enableAudio
                      ? Icons.mic_rounded
                      : Icons.mic_off_rounded,
                  label: 'Microphone',
                  sublabel: _enableAudio
                      ? (_audioInputs.isNotEmpty &&
                                _audioInputs.first.label.isNotEmpty
                            ? _audioInputs.first.label
                            : 'Default mic')
                      : 'Muted',
                  isActive: _enableAudio,
                  gradColors: _enableAudio ? _DS.micOnGrad : _DS.micOffGrad,
                  onTap: _toggleAudio,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Divider
          Row(
            children: [
              Expanded(child: Divider(color: _DS.glassBdr, thickness: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'ALL SET?',
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    color: _DS.textLow,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              Expanded(child: Divider(color: _DS.glassBdr, thickness: 1)),
            ],
          ),

          const SizedBox(height: 18),

          _buildJoinButton(),
        ],
      ),
    );
  }

  // ── Device card ────────────────────────────────────────────────────────────
  Widget _buildDeviceCard({
    required IconData icon,
    required String label,
    required String sublabel,
    required bool isActive,
    required List<Color> gradColors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: _DS.glass10,
          border: Border.all(
            color: isActive
                ? gradColors.first.withValues(alpha: 0.4)
                : _DS.glassBdr,
            width: 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: gradColors.first.withValues(alpha: 0.14),
                    blurRadius: 22,
                    spreadRadius: 0,
                  ),
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Icon chip
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: isActive
                        ? LinearGradient(
                            colors: gradColors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isActive ? null : _DS.glass15,
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: gradColors.first.withValues(alpha: 0.4),
                              blurRadius: 10,
                            ),
                          ]
                        : [],
                  ),
                  child: Icon(
                    icon,
                    color: isActive ? Colors.white : _DS.textLow,
                    size: 19,
                  ),
                ),
                // Mini toggle
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 38,
                  height: 22,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    gradient: isActive
                        ? LinearGradient(colors: gradColors)
                        : null,
                    color: isActive ? null : _DS.glass15,
                    border: isActive
                        ? null
                        : Border.all(color: _DS.glassBdr, width: 1),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    alignment: isActive
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.all(3),
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              sublabel,
              style: TextStyle(
                fontFamily: 'tajawal',
                color: isActive
                    ? gradColors.first.withValues(alpha: 0.85)
                    : _DS.textLow,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }

  // ── Join button ────────────────────────────────────────────────────────────
  Widget _buildJoinButton() {
    return GestureDetector(
      onTapDown: (_) => _joinPressAnim.forward(),
      onTapUp: (_) {
        _joinPressAnim.reverse();
        if (!_busy) _join(context);
      },
      onTapCancel: () => _joinPressAnim.reverse(),
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 0.97).animate(
          CurvedAnimation(parent: _joinPressAnim, curve: Curves.easeInOut),
        ),
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (_, _) => AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 62,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: _busy
                  ? null
                  : const LinearGradient(
                      colors: _DS.joinGrad,
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
              color: _busy ? _DS.surfaceHi : null,
              border: _busy ? Border.all(color: _DS.glassBdr, width: 1) : null,
              boxShadow: _busy
                  ? []
                  : [
                      BoxShadow(
                        color: _DS.cyan.withValues(
                          alpha: 0.28 + _pulse.value * 0.14,
                        ),
                        blurRadius: 26 + _pulse.value * 12,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: _DS.indigo.withValues(
                          alpha: 0.18 + _pulse.value * 0.08,
                        ),
                        blurRadius: 40,
                        spreadRadius: -4,
                        offset: const Offset(0, 14),
                      ),
                    ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!_busy)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 26,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.13),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _busy
                      ? [
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: AppLoadingIndicator(),
                          ),
                        ]
                      : [
                          const Icon(
                            Icons.play_circle_filled_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Join Session',
                            style: TextStyle(
                              fontFamily: 'tajawal',
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Aurora background painter
// ─────────────────────────────────────────────────────────────────────────────
class _AuroraPainter extends CustomPainter {
  const _AuroraPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final a = t * 2 * math.pi;
    _blob(
      canvas,
      Offset(
        size.width * (0.12 + 0.07 * math.sin(a)),
        size.height * (0.13 + 0.06 * math.cos(a * 0.7)),
      ),
      size.width * 0.58,
      const Color(0xFF00D4FF).withValues(alpha: 0.09),
    );
    _blob(
      canvas,
      Offset(
        size.width * (0.84 + 0.06 * math.cos(a * 1.3)),
        size.height * (0.24 + 0.08 * math.sin(a * 0.9)),
      ),
      size.width * 0.52,
      const Color(0xFF6B6EF9).withValues(alpha: 0.08),
    );
    _blob(
      canvas,
      Offset(
        size.width * (0.16 + 0.05 * math.sin(a * 0.6)),
        size.height * (0.77 + 0.05 * math.cos(a * 0.5)),
      ),
      size.width * 0.48,
      const Color(0xFF00E5A0).withValues(alpha: 0.06),
    );
    _blob(
      canvas,
      Offset(
        size.width * (0.87 + 0.04 * math.cos(a * 1.1)),
        size.height * (0.83 + 0.04 * math.sin(a * 0.8)),
      ),
      size.width * 0.44,
      const Color(0xFFFF4F72).withValues(alpha: 0.05),
    );
  }

  void _blob(Canvas canvas, Offset center, double r, Color color) {
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [color, Colors.transparent],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
// _GlassIconButton
// ─────────────────────────────────────────────────────────────────────────────
class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: _DS.glass10,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _DS.glassBdr, width: 1),
      ),
      child: Center(child: child),
    ),
  );
}
