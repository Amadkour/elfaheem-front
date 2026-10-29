import 'dart:async';
import 'dart:developer';
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
import 'prejoin_layout.dart';
import 'prejoin_mic_meter_stub.dart'
    if (dart.library.js_interop) 'prejoin_mic_meter_web.dart' as mic_meter;
import 'room.dart';
import 'widgets/live_room_rules.dart' show liveConnectRetryDelay;
import 'widgets/share_presets.dart' show SharePreset;
import 'package:flutter_education_app/features/shared/rag/app_assistant.dart' show AppAssistant;
import 'package:flutter_education_app/features/shared/live/live_room.dart';
import 'package:flutter_education_app/features/shared/live/live_lobby_sheets.dart' show WaitingForHostPage;
import 'package:flutter_education_app/features/shared/live/live_mini_box.dart' show LiveMiniTile;
import 'package:flutter_education_app/features/shared/live/live_room_host.dart';
import 'package:flutter_education_app/features/shared/live/live_controls_api.dart' show liveJoinRefusalText;
import 'package:flutter_education_app/design/app_kit.dart' show appToast;
import 'package:flutter_education_app/features/shared/points/points_api.dart' show LivePlanDeclined;
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
    this.roomRef,
    this.isHost,
    this.onPoll,
    this.canRecord = false,
    this.autoJoin = false,
    this.startsAt,
    this.hostName,
  });

  /// Part 2 (docs/backend/live-rooms-spec.md §7, §10): press Join by itself as soon as the devices are ready —
  /// "Meet now" and a direct guest link. Once only: never again after a failure or a back.
  final bool autoJoin;

  /// The meeting's scheduled start (UTC), shown in the room's info sheet.
  final DateTime? startsAt;

  /// Who hosts the room, shown in the room's info sheet.
  final String? hostName;

  /// [meeting-recording] The creator of a calendar meeting may record it to a cloud drive (RoomPage.canRecord).
  final bool canRecord;

  /// True for a visitor who came through a public guest link: no account, no token.
  /// The room then skips every authenticated call (attendance, quizzes, participants…).
  final bool guest;

  /// Which live room this is (course session or calendar meeting, docs/backend/live-rooms-spec.md §1).
  /// Null → `LiveRoomRef.fromSessionId(sessionId)` (a meeting room keeps the `-meetingId` convention).
  final LiveRoomRef? roomRef;

  /// Who runs the lobby (share link, admission). Null → `isTeacher && !guest`; a meeting owner passes true
  /// without being a "teacher" (no recorder, no course-session calls).
  final bool? isHost;

  /// Polls a waiting lobby request (`onStart` answered `JoinOutcome.waiting`). Null → [LiveRoomApi.poll],
  /// which picks the public poll when the outcome carries a secret and the member poll otherwise.
  final Future<JoinOutcome> Function(JoinOutcome waiting)? onPoll;

  LiveRoomRef get ref => roomRef ?? LiveRoomRef.fromSessionId(sessionId ?? 0);

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
  /// For students:  calls GET  /live-sessions/{id}/join → returns LiveResponseModel, or a [JoinOutcome]:
  /// `waiting` shows "Waiting for the host…" and polls until admitted (then the room opens), `admitted`
  /// carries the join payload, rejected / expired send the person back.
  final Future<dynamic> Function() onStart;

  /// Called when the session ends (teacher taps End, or room disconnects).
  final Future<dynamic> Function() onEnd;

  /// Called after a student leaves the room. Triggers POST /sessions/{id}/complete.
  final Future<void> Function()? onComplete;

  /// ApiClient instance scoped to the authenticated user.
  /// Passed down to RoomPage → _ClientRecorder for chunk upload auth.
  final ApiClient apiClient;

  /// The same join again after a lost connection (D9): the session the room ran (a quick session created on
  /// the first join keeps its id), pressed by itself once the devices are ready.
  JoinArgs forRejoin({required int sessionId}) => JoinArgs(
        e2ee: e2ee,
        e2eeKey: e2eeKey,
        simulcast: simulcast,
        adaptiveStream: adaptiveStream,
        dynacast: dynacast,
        preferredCodec: preferredCodec,
        enableBackupVideoCodec: enableBackupVideoCodec,
        sessionId: sessionId,
        courseId: courseId,
        maxStudents: maxStudents,
        isTeacher: isTeacher,
        userName: userName,
        userId: userId,
        onStart: onStart,
        onEnd: onEnd,
        onComplete: onComplete,
        sessionName: sessionName,
        apiClient: apiClient,
        guest: guest,
        canPublish: canPublish,
        roomRef: roomRef,
        isHost: isHost,
        onPoll: onPoll,
        canRecord: canRecord,
        autoJoin: true,
        startsAt: startsAt,
        hostName: hostName,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// PreJoinPage — device setup + the join plumbing. The layout lives in
// prejoin_layout.dart (PreJoinLayout) so it can be tested without LiveKit.
// ─────────────────────────────────────────────────────────────────────────────
class PreJoinPage extends StatefulWidget {
  const PreJoinPage({required this.args, super.key, this.startMic = true, this.startCam = true});

  final JoinArgs args;

  /// The microphone / camera to start with (a Rejoin restores what the person had in the room, D9).
  final bool startMic;
  final bool startCam;

  @override
  State<StatefulWidget> createState() => _PreJoinPageState();
}

class _PreJoinPageState extends State<PreJoinPage> {
  List<MediaDevice> _audioInputs = [];
  List<MediaDevice> _videoInputs = [];
  StreamSubscription? _subscription;

  bool _busy = false;
  late bool _enableVideo = widget.startCam;
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

  static const _bestResolution = VideoParametersPresets.h1080_169;

  bool get _canPublish => widget.args.canPublish;

  /// [JoinArgs.autoJoin] was used up (pressed once, or given up because the devices need the person's attention).
  bool _autoJoinDone = false;

  /// Presses Join once the devices are ready (JoinArgs.autoJoin). A refused permission leaves the page to the person
  /// (they may want to fix it first; no camera / mic at all joins anyway); a failed or cancelled join is never
  /// retried by itself.
  void _maybeAutoJoin() {
    if (!widget.args.autoJoin || _autoJoinDone || _busy || !mounted) return;
    _autoJoinDone = true;
    if (_issue == PreJoinIssue.permissionDenied) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_busy) unawaited(_join(context));
    });
  }

  @override
  void initState() {
    super.initState();
    AppAssistant.hide(); // full screen: no floating assistant bubble
    if (!_canPublish) {
      // Listen-only guest: no tracks are ever created, no permission prompt.
      _enableAudio = false;
      _enableVideo = false;
      _maybeAutoJoin();
      return;
    }
    unawaited(_initDevices().whenComplete(_maybeAutoJoin));
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
      const cameraEncoding = VideoEncoding(
        maxBitrate: 5 * 1000 * 1000,
        maxFramerate: 60,
      );
      // D14: one screen-share preset everywhere. Android and the web publish their own track with the mode the
      // presenter picked (SharePreset); what still goes through setScreenShareEnabled (iOS, desktop) gets
      // "Detail" (1080p, 15 fps, 2.5 Mbps) instead of the old 1080p15 capture with 30 fps / 4 Mbps encoding.
      final screenEncoding = SharePreset.detail.encoding;
      late int localSessionId;
      if (args.sessionId==null && !args.guest){
        final TeacherSessionItem? r = await context.read<TeacherCourseScreenProvider>().quickSession(courseId: args.courseId);
        if(r ==null){
          Helpers.showMessage('failed to create session'.tr, isError: true);
          return;
        }
        localSessionId = r.id;
      }
      Room newRoom() => Room(
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
          // iOS (I1): LiveKit publishes the share by itself on iOS_BroadcastStarted with THESE options (no
          // per-call options then); `useiOSBroadcastExtension` picks the extension's socket ('broadcast-manual').
          // Ignored on the other platforms.
          defaultScreenShareCaptureOptions: ScreenShareCaptureOptions(
            useiOSBroadcastExtension: true,
            captureScreenAudio: true,
            maxFrameRate: SharePreset.detail.maxFps.toDouble(),
            params: VideoParameters(dimensions: VideoDimensionsPresets.h1080_169, encoding: screenEncoding),
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

      final sessionId = args.sessionId ?? localSessionId;
      final data = await _resolveJoin(args, sessionId);
      if (data == null) return; // waiting cancelled, or the host refused: stay on the pre-join page

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
        canRecord: args.canRecord, // [meeting-recording]
        freeEndsAt: data.freeEndsAt,
        liveStartedAt: data.liveStartedAt,
        startsAt: args.startsAt,
        hostName: args.hostName,
        // D9: Rejoin opens this page again for the same session, joining by itself with the room's choices.
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
      await context.showErrorDialog(liveJoinRefusalText(error) ?? error);
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
          builder: (_) => WaitingForHostPage(waiting: outcome, title: args.sessionName, poll: args.onPoll),
        ),
      );
      if (admitted == null) return null;
      outcome = admitted;
    }
    if (outcome.isRefused) {
      appToast(liveRoomCodeText(outcome.status == JoinStatus.rejected ? 'join_rejected' : 'request_expired') ?? '', error: true);
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
      title: widget.args.sessionName ?? '',
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
    _autoJoinDone = true;
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
