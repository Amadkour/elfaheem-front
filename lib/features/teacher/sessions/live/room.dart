import 'package:flutter_education_app/config/app_config.dart';
import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, ValueListenable;
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'widgets/live_palette.dart';
// Annotation over the shared screen (D-079): docs/live/annotation_wiring.md, the "Annotation" region below
import 'annotation/annotation_controller.dart';
// The whiteboard (D-087): the "Whiteboard" region below
import 'whiteboard/board_controller.dart';
import 'whiteboard/board_protocol.dart' show BoardBackground, BoardFormat;
import 'whiteboard/board_toolbar.dart' show boardShortcutTool;
import 'whiteboard/board_view.dart';
import 'annotation/annotation_layer.dart';
import 'annotation/annotation_toolbar.dart'
    show AnnotationControllerToolbar, annotPresetColors, annotShortcutThickness, annotShortcutTool;
import 'widgets/live_call_service.dart';
import 'widgets/live_top_row.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../admin/admin_common.dart';
import '../components/exts.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_kit.dart' show appConfirm;
import 'package:flutter_education_app/core/app_time.dart';
import 'widgets/controls.dart';
import 'widgets/live_chat.dart';
import 'widgets/live_control_bar.dart' show kLiveControlsMobileBreakpoint;
import 'widgets/live_data_route.dart';
import 'widgets/live_duration.dart';
import 'widgets/live_hands.dart';
import 'widgets/live_quiz.dart';
import 'widgets/live_reactions.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_education_app/features/shared/rag/app_assistant.dart' show AppAssistant;
import 'package:flutter_education_app/features/shared/live/live_room.dart';
import 'package:flutter_education_app/features/shared/live/live_lobby_sheets.dart';
import 'package:flutter_education_app/features/shared/live/live_room_host.dart';
// Host controls (live hardening L2): docs/live/teacher_controls_wiring.md, the "Host controls" region below
import 'package:flutter_education_app/features/shared/live/live_controls_api.dart'
    show kLiveRoomLockFeatureKey, kLiveTeacherControlsFeatureKey, liveControlTargetFrom, liveIdentityIsStudent,
        liveIsGuestIdentity, liveControlsError, LiveControlTarget, LivePublishSource;
import 'package:flutter_education_app/features/shared/live/live_participant_controls.dart'
    show LiveHostControlsController, LiveHostControlsHeader, LiveParticipantControlsButton, showLiveParticipantControls;
import 'package:flutter_education_app/features/shared/live/live_end_signal.dart';
// One share at a time + "Request to share", the attention badges and the chat preview: the "Share arbitration"
// region below (lib/features/shared/live/live_share_arbiter.dart, live_attention.dart, live_share_widgets.dart)
import 'package:flutter_education_app/features/shared/live/live_share_arbiter.dart';
import 'package:flutter_education_app/features/shared/live/live_attention.dart';
import 'package:flutter_education_app/features/shared/live/live_share_widgets.dart';
import 'widgets/ios_share.dart' show IosShareNative;
import 'widgets/participant.dart';
import 'widgets/participant_info.dart';
import 'widgets/recording_placeholder.dart';
import 'package:flutter_education_app/core/app_identity.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:provider/provider.dart';
import 'widgets/room_recorder.dart';
// [meeting-recording] meeting rooms record to the creator's cloud drive (docs/backend/live-rooms-spec.md §5)
import 'package:flutter_education_app/features/shared/live/meeting_recording.dart'
    show RecordingQuality, RecordingStart;
import 'package:flutter_education_app/features/shared/live/meeting_recording_sheets.dart'
    show showRecordSetupSheet;
// Part 2 (live-rooms-spec §8, §11): the free-time countdown, the (i) sheet and the live plan
import 'package:flutter_education_app/features/shared/live/live_time_limit.dart';
import 'package:flutter_education_app/features/shared/live/live_config.dart';
import 'package:flutter_education_app/features/shared/live/live_media_plan.dart'
    show isBoardVideoName, liveVideoBudget, wantBoardVideo;
import 'package:flutter_education_app/features/shared/live/live_media_controller.dart';
import 'package:flutter_education_app/features/shared/live/live_net_pill.dart';
import 'package:flutter_education_app/features/shared/live/live_quality_governor.dart' show LiveVideoTier;
import 'whiteboard/board_video_track.dart';
import 'package:flutter_education_app/features/shared/live/meeting_info_sheet.dart';
import 'package:flutter_education_app/features/shared/points/live_plan_sheet.dart' show showLivePlanSheet;
import 'package:permission_handler/permission_handler.dart';
import 'widgets/room_screen_share.dart';
import 'widgets/android_share.dart' show LiveMicGate;
import 'widgets/live_room_ended.dart';
import 'widgets/live_room_rules.dart';
import 'widgets/live_tile_order.dart';
import 'widgets/live_video_view.dart';
import 'widgets/self_view_pip.dart';
import 'widgets/presenter_cam_box.dart';
import 'package:flutter_education_app/features/shared/live/live_self_view.dart';
import 'package:flutter_education_app/features/shared/live/live_presenter_cam.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_icons.dart';
import 'widgets/recorder_web_stub.dart'
if (dart.library.html) 'widgets/recorder_web_impl.dart' as web_rec;
import 'package:flutter_education_app/core/display/app_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design System
// ─────────────────────────────────────────────────────────────────────────────
Color get _bg => LivePalette.bg;
Color get _surface => LivePalette.surface;
Color get _surfaceHi => LivePalette.surfaceHi;
Color get _cyan => LivePalette.accent;
Color get _indigo => LivePalette.accent2;
Color get _emerald => LivePalette.success;
Color get _rose => LivePalette.danger;
const _textHigh = LivePalette.textHigh;
const _textMid = LivePalette.textMid;
const _textLow = LivePalette.textLow;
const _glass10 = LivePalette.glass;
const _glass15 = LivePalette.glassBorder;
const _glassBdr = LivePalette.glassBorder;

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────
class EnrolledStudent {
  final int id;
  final String name;
  final String? imageUrl;
  bool isAttended;
  final DateTime? joinDate;
  final DateTime? leaveDate;

  EnrolledStudent({
    required this.id,
    required this.name,
    this.imageUrl,
    this.isAttended = false,
    this.joinDate,
    this.leaveDate,
  });

  factory EnrolledStudent.fromJson(
      Map<String, dynamic> j,
      List<int> studentsId,
      List<String?> studentsJoinDate,
      List<String?> studentsLeaveDate,
      ) {
    bool isPresent = false;
    String? presentDate;
    String? leaveDate;
    int? index;
    int it = 0;
    for (int i = 0; i < studentsId.length; i++) {
      if (studentsId[i] == j['id']) {
        presentDate = studentsJoinDate[i];
        leaveDate = studentsLeaveDate[i];
        isPresent = true;
      }
    }
    studentsId.firstWhereIndexedOrNull((e, i) {
      bool t = e == j['id'];
      if (t) index = it;
      it++;
      return t;
    });
    if (index != null) {
      isPresent = true;
      presentDate = studentsJoinDate[index!];
    }
    return EnrolledStudent(
      id: j['id'] ?? 0,
      name: j['name'] ?? '',
      imageUrl: j['image_url'],
      isAttended: isPresent,
      // naive UTC from the server ("None" when empty): never DateTime.parse, which reads it as local time
      joinDate: liveParseServerUtc(presentDate),
      leaveDate: liveParseServerUtc(leaveDate),
    );
  }
}

class ActiveQuiz {
  final int examId;
  final String name;
  final String? description;
  final int totalMarks;
  final int durationMinutes;
  final String? passcode;
  final List<QuizQuestion> questions;

  const ActiveQuiz({
    required this.examId,
    required this.name,
    this.description,
    required this.totalMarks,
    required this.durationMinutes,
    this.passcode,
    required this.questions,
  });

  factory ActiveQuiz.fromJson(Map<String, dynamic> j) => ActiveQuiz(
    examId: j['id'] ?? 0,
    name: j['name'] ?? '',
    description: j['description'],
    totalMarks: j['total_marks'] ?? 0,
    durationMinutes: j['duration'] ?? 10,
    passcode: j['passcode'],
    questions: (j['questions'] as List? ?? [])
        .map((q) => QuizQuestion.fromJson(q as Map<String, dynamic>))
        .toList(),
  );
}

class QuizQuestion {
  final int id;
  final String text;
  final List<String> options;
  final int? correctIndex;

  const QuizQuestion({
    required this.id,
    required this.text,
    required this.options,
    this.correctIndex,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> j) {
    final opts = <String>[];
    if (j['option_a'] != null) opts.add(j['option_a']);
    if (j['option_b'] != null) opts.add(j['option_b']);
    if (j['option_c'] != null) opts.add(j['option_c']);
    if (j['option_d'] != null) opts.add(j['option_d']);
    return QuizQuestion(
      id: j['id'] ?? 0,
      text: j['text'] ?? '',
      options: opts,
      correctIndex: j['correct_option'],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HD audio helpers  (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────
const _hdAudioCaptureOptions = AudioCaptureOptions(
  noiseSuppression: true,
  echoCancellation: true,
  autoGainControl: true,
  highPassFilter: true,
  typingNoiseDetection: true,
);

Future<void> _enableHdAudio(LocalParticipant local) async {
  try {
    // await local.setMicrophoneEnabled(
    //   true,
    //   audioCaptureOptions: _hdAudioCaptureOptions,
    // );
    // for (final pub in local.audioTrackPublications) {
    //   if (pub.track is LocalAudioTrack) {
    //     await local.publishAudioTrack(
    //       pub.track as LocalAudioTrack,
    //       publishOptions: _hdAudioPublishOptions,
    //     );
    //   }
    // }
    await local.setMicrophoneEnabled(
      true,
      audioCaptureOptions: _hdAudioCaptureOptions,
    );
  } catch (_) {}
}

// RecState + ClientRecorder → room_recorder.dart

/// Which panel sits in the side column (wide) / bottom sheet (phones).
enum _SidePanel { hands, chat }

// ─────────────────────────────────────────────────────────────────────────────
// RoomPage
// ─────────────────────────────────────────────────────────────────────────────
class RoomPage extends StatefulWidget {
  final Room room;
  final EventsListener<RoomEvent> listener;
  final bool fastConnection;
  final Future<dynamic> Function() onEnd;
  final bool isTeacher;
  final int courseId;
  final int sessionId;
  final ApiClient apiClient;
  final bool enableAudio;
  final bool enableVideo;
  // Optional: shown on the recording's placeholder frame (and nowhere else
  // yet) whenever there's no screen share/camera to draw. Pass the actual
  // session/lecture title from wherever the caller already has it (e.g. the
  // session list); falls back to a generic label if omitted.
  final String? sessionName;

  /// False when the session creator switched recording off for this session:
  /// the teacher's device never records and no recording UI is shown.
  final bool recordingEnabled;

  /// A visitor from a public guest link: no account and no token, so every
  /// authenticated call (leave / attendance, participants, quizzes…) is skipped —
  /// a 401 would otherwise send the guest to the login screen.
  final bool isGuest;

  /// False → listen-only: no microphone / camera controls at all.
  final bool canPublish;

  // ── Live rooms: share links + admission lobby (docs/backend/live-rooms-spec.md) ──
  /// Which room this is (course session or calendar meeting). Null → from [sessionId] (negative = meeting).
  final LiveRoomRef? roomRef;

  /// Runs the lobby. Null → `isTeacher && !isGuest`; a meeting owner passes true (no recorder, no course calls).
  final bool? isHost;

  LiveRoomRef get ref => roomRef ?? LiveRoomRef.fromSessionId(sessionId);

  bool get host => isHost ?? (isTeacher && !isGuest);

  /// [meeting-recording] The creator of a calendar meeting (the detail's `can_record` / `is_owner`): the room
  /// offers Record → RecordSetupSheet → chunks to the recording's own route (spec §5). Course sessions ignore it.
  final bool canRecord;

  /// Part 2 (spec §8, §11): when a student meeting's free time ends (`time_limit.ends_at`, UTC); null = no limit.
  /// Everyone sees the countdown; the owner ([host] of a meeting) gets "Upgrade" from 3 minutes left.
  final DateTime? freeEndsAt;

  /// The meeting's scheduled start and its host, for the (i) sheet.
  final DateTime? startsAt;
  final String? hostName;

  /// Part 3 (spec §16): when the room really went live (`live_started_at`, UTC; a meeting's first join, a course
  /// session's start). The (i) sheet's "Live for" counts from it; null → the person's own time in the room.
  final DateTime? liveStartedAt;

  /// The super admin's live media settings from the join payload (D-090): the receive side (weak network, hidden
  /// video), who records (device in client mode, Egress in server mode) and the share's ceilings.
  final LiveConfig liveConfig;

  /// D9: the connection-lost dialog's Rejoin. The pre-join page passes how to join again (a fresh token, then
  /// connect) with the microphone / camera as they were in the room; null hides Rejoin.
  final void Function(bool micOn, bool camOn)? onRejoin;

  const RoomPage(
      this.room,
      this.listener, {
        this.fastConnection = false,
        super.key,
        required this.onEnd,
        required this.isTeacher,
        required this.courseId,
        required this.sessionId,
        required this.apiClient,
        this.enableAudio = true,
        this.enableVideo = true,
        this.sessionName,
        this.recordingEnabled = true,
        this.isGuest = false,
        this.canPublish = true,
        this.roomRef,
        this.isHost,
        this.canRecord = false,
        this.freeEndsAt,
        this.startsAt,
        this.hostName,
        this.liveStartedAt,
        this.liveConfig = LiveConfig.defaults,
        this.onRejoin,
      });

  @override
  State<StatefulWidget> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage>
    with TickerProviderStateMixin, RoomScreenShareMixin {

  // ── RoomScreenShareMixin requirements ───────────────────────────────────
  @override Room get room => widget.room;
  @override ClientRecorder? get recorder => _recorder;
  @override bool get isTeacher => widget.isTeacher;
  @override void showSnack(String msg) => _showSnack(msg);
  @override bool get shareAudioAllowed => _allowed.shareAudio;
  // The Android whole-screen overlay starts with the room's annotation colour / thickness (room_wiring_pending §4).
  @override int? get annotationColorArgb => _annot.colorArgb;
  @override int get annotationThickness => _annot.thickness;
  // The share sheet offers the whiteboard (the "Whiteboard" region).
  @override bool get whiteboardOffered => _boardEnabled;
  @override LiveConfig get liveConfig => widget.liveConfig;

  // ── D-090: the receive side (weak network, hidden video) and the board's recording track ─────────────────
  late final LiveMediaController _media = LiveMediaController(room: widget.room, config: widget.liveConfig);
  late final BoardVideoPublisher _boardVideo = BoardVideoPublisher(room: widget.room, pageKey: _boardPageKey);

  void _onMediaChanged() {
    if (mounted) setState(() {});
  }

  /// The course session's device recorder runs (client mode, or a server that does not say; never in server mode,
  /// where LiveKit Egress records).
  bool get _deviceRecords => widget.isTeacher && widget.recordingEnabled && widget.liveConfig.deviceRecorder;

  /// Minimized with pause_hidden_video: the page draws no video at all (adaptive stream then pauses every track the
  /// box does not show; the box keeps its own renderer).
  bool get _videoParked => (_minimized?.value ?? false) && widget.liveConfig.pauseHiddenVideo;

  void _onMinimizedVideo() {
    if (mounted) setState(() {});
  }

  /// The aurora behind the stage runs only while nothing else is on it (the waiting card): behind a video, a share
  /// or a board it is barely visible and cost a full-screen repaint 60 times a second.
  void _syncAurora() {
    // Not before didChangeDependencies (it reads MediaQuery); not while minimized (_syncDecorLoops parks it).
    if (!mounted || !_depsReady || (_minimized?.value ?? false)) return;
    // Never while my camera is on (D-092): the waiting card is opaque, and a 60 fps background under a live camera
    // box is what made a phone hot for nothing.
    final idle = _stageTracks.isEmpty && !_isBoardMain && _localCamTrack == null;
    if (idle) {
      // D-092: this called itself (an endless recursion: ~98 000 frames and a Stack Overflow, logged with its whole
      // trace and sent to Crashlytics, up to 3 times a second while the stage was empty — logcat7 22:56–22:59).
      if (!_auroraAnim.isAnimating) syncMotionLoop(context, _auroraAnim, rest: 0);
    } else if (_auroraAnim.isAnimating) {
      _auroraAnim.stop();
    }
  }

  /// The board's recording track runs exactly while wanted (server recording mode, a server recording on, this
  /// device presenting a board, a platform that can feed a track).
  void _syncBoardVideo() {
    final want = wantBoardVideo(
      config: widget.liveConfig,
      roomRecording: _serverRecording,
      presentingBoard: _boardEnabled && _board.isLocalPresenting,
      supported: boardVideoSupported(),
    );
    unawaited(_boardVideo.sync(want: want));
  }

  void _onBoardScene() => _boardVideo.markDirty();

  bool _depsReady = false;
  // D-093 hook (whiteboard page format): the share sheet's choice reaches _startBoard.
  @override
  Future<void> startWhiteboard(BoardBackground background, {BoardFormat format = BoardFormat.landscape}) =>
      _startBoard(background, format: format);

  // ── D29: what the server lets this participant publish (follows ParticipantPermissionsUpdatedEvent) ─────
  late LiveAllowedControls _allowed = _allowedFrom(widget.room.localParticipant?.permissions);

  LiveAllowedControls _allowedFrom(ParticipantPermissions? p) {
    if (p == null) {
      return widget.canPublish
          ? liveAllowedControls(canPublish: true, sources: const [], host: widget.isTeacher || widget.host)
          : LiveAllowedControls.none;
    }
    return liveAllowedControls(
      canPublish: p.canPublish,
      sources: [for (final s in p.canPublishSources) s.name],
      host: widget.isTeacher || widget.host,
    );
  }

  Future<void> _onLocalPermissions(ParticipantPermissions permissions) async {
    final next = _allowedFrom(permissions);
    final before = _allowed;
    if (next == before || !mounted) return;
    log('[LIVE] permissions: $before -> $next');
    setState(() => _allowed = next);
    final local = widget.room.localParticipant;
    if (local != null) {
      final revoked = liveRevokedSources(next, local.trackPublications.values.map((p) => p.source));
      // The share first: on Android its device audio rides on the mic track (M1: a revoked share audio stops a
      // share with device audio too; liveRevokedSources lists published sources only).
      if (revoked.contains(TrackSource.screenShareVideo)) {
        await stopScreenShare();
      } else {
        await stopShareIfDeviceAudioRevoked(
          micRevoked: revoked.contains(TrackSource.microphone),
          shareAudioRevoked: before.shareAudio && !next.shareAudio,
        );
      }
      for (final source in revoked) {
        if (source == TrackSource.screenShareVideo) continue;
        final pub = local.getTrackPublicationBySource(source);
        if (pub == null) continue;
        try {
          await local.removePublishedTrack(pub.sid);
        } catch (e) {
          log('[LIVE] unpublish $source after a permission change: $e');
        }
      }
      if (!next.camera) _bgCamera.forget();
    }
    // Android 14+: the live-call service keeps the microphone alive in the background while one may be used.
    if (next.mic != before.mic) unawaited(next.mic ? LiveCallService.start() : LiveCallService.stop());
    // A share the host allowed for one request (and takes back when it ends) has its own notices (Share region).
    final shareOnly = before.mic == next.mic && before.camera == next.camera;
    if (shareOnly && _share.everAccepted) return;
    switch (livePermissionNotice(before, next)) {
      case LivePermissionNotice.granted:
        _showSnack(t('سمح لك المضيف بالمشاركة: الميكروفون والكاميرا مغلقان حتى تفتحهما',
            'The host let you take part: your microphone and camera stay off until you turn them on'));
      case LivePermissionNotice.revoked:
        _showSnack(t('غيّر المضيف ما يمكنك مشاركته', 'The host changed what you can share'));
      case LivePermissionNotice.none:
        break;
    }
  }

  // ── D8: the camera while the app is in the background (phones) ──────────────────────────────────────────
  final LiveBackgroundCamera _bgCamera = LiveBackgroundCamera();
  AppLifecycleListener? _lifecycle;

  void _onAppLifecycle(AppLifecycleState state) {
    if (kIsWeb || !lkPlatformIsMobile()) return;
    // D-090: nobody watches the videos of an app in the background — they stop until it is back (audio goes on).
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      _media.setAppHidden(true);
    } else if (state == AppLifecycleState.resumed) {
      _media.setAppHidden(false);
    }
    final local = widget.room.localParticipant;
    if (local == null) return;
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      // A frozen frame is all the others would see; the mic keeps going as the person set it, and a running
      // screen share is never touched (it must continue in the background).
      if (_bgCamera.onBackground(cameraOn: local.isCameraEnabled(), sharing: screenShareActive)) {
        log('[LIVE] background: camera off');
        unawaited(local.setCameraEnabled(false).then((_) {}, onError: (Object e) => log('[LIVE] camera off: $e')));
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_bgCamera.onForeground(allowed: _allowed.camera)) {
        log('[LIVE] foreground: camera back on');
        unawaited(local.setCameraEnabled(true).then((_) {}, onError: (Object e) => log('[LIVE] camera on: $e')));
      }
    }
  }

  // ── D9: what Rejoin restores (kept up to date while connected; read once the room is gone) ───────────────
  bool _lastMicOn = false;
  bool _lastCamOn = false;

  void _rememberLocalChoices() {
    final local = widget.room.localParticipant;
    if (local == null || widget.room.connectionState != ConnectionState.connected) return;
    _lastMicOn = LiveMicGate.instance.micOn(local);
    _lastCamOn = local.isCameraEnabled() || _bgCamera.pausedByUs;
  }

  // ── D21: one throttled re-layout (≤ 2 per second, the last change always applied) ──────────────────────
  late final LiveUpdateThrottle _sortThrottle =
      LiveUpdateThrottle(const Duration(milliseconds: 500), _sortParticipants);
  final LiveSpeakerOrder _speakerOrder = LiveSpeakerOrder();
  Timer? _sortRecheck;

  void _scheduleSort() {
    if (mounted) _sortThrottle.request();
  }

  // ── D27: decorative loops stop while the room is a box (and follow Reduce motion) ──────────────────────
  ValueListenable<bool>? _minimized;

  void _syncDecorLoops() {
    if (!mounted) return;
    if (_minimized?.value ?? false) {
      _auroraAnim.stop();
      _recDotAnim.stop();
      if (_annotOpen) _closeAnnot(); // the box shows no toolbar
      WidgetsBinding.instance.addPostFrameCallback((_) => _hideChatToast()); // the box has its own badge
      return;
    }
    // Full-screen again: a share request that waited while the room was a box is asked now.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openShareDialog());
    syncMotionLoop(context, _auroraAnim, rest: 0);
    if (!_recDotAnim.isAnimating) _recDotAnim.repeat(reverse: true); // tells something: never parked by motion
  }

  // Live emoji reactions (everyone): published lossy on topic 'reaction', shown by LiveReactionsOverlay.
  late final LiveReactionsController _reactions = LiveReactionsController(
    onSend: (bytes) async => widget.room.localParticipant
        ?.publishData(bytes, reliable: false, topic: kLiveReactionTopic),
  );
  String get _myReactionName {
    final p = widget.room.localParticipant;
    return (p?.name.isNotEmpty ?? false) ? p!.name : (p?.identity ?? '');
  }
  String get _myIdentity => widget.room.localParticipant?.identity ?? '';

  // Hand-raise queue (reliable data on topic 'hand'; see live_hands.dart).
  late final LiveHandsController _hands = LiveHandsController(
    localIdentity: () => _myIdentity,
    onSend: (bytes) async => widget.room.localParticipant
        ?.publishData(bytes, reliable: true, topic: kLiveHandTopic),
  );
  int _handsSeen = 0;
  void _onHandsChanged() {
    final n = _hands.count;
    // Teacher: a short notice when a new hand goes up while the queue is closed.
    if (widget.isTeacher && n > _handsSeen && _side != _SidePanel.hands && _hands.hands.isNotEmpty) {
      _showSnack('✋ ${_hands.hands.last.name}');
    }
    _handsSeen = n;
    _syncAttention();
    if (mounted) setState(() {});
  }

  // In-room chat (reliable data on topic 'chat'; see live_chat.dart).
  late final LiveChatController _chat = LiveChatController(
    localIdentity: () => _myIdentity,
    onSend: (bytes) async => widget.room.localParticipant
        ?.publishData(bytes, reliable: true, topic: kLiveChatTopic),
  );

  // Hands / chat live in a side column on wide screens and a dark bottom sheet on phones.
  _SidePanel? _side;
  static const double _sidePanelBreakpoint = 900;
  static const double _sidePanelWidth = 320;
  bool get _wideForSidePanel => mounted && MediaQuery.sizeOf(context).width >= _sidePanelBreakpoint;

  /// The panel open as a phone sheet (null: none) — the attention counts treat it as "looked at".
  _SidePanel? _sheetPanel;

  void _togglePanel(_SidePanel which) {
    if (_wideForSidePanel) {
      setState(() => _side = _side == which ? null : which);
      _syncWatching();
      return;
    }
    _sheetPanel = which;
    _syncWatching();
    _showLiveSheet(_buildSidePanel(which, inSheet: true)).whenComplete(() {
      _sheetPanel = null;
      _syncWatching();
    });
  }

  void _closeSidePanel() {
    setState(() => _side = null);
    _syncWatching();
  }

  /// The hands queue on screen (side column or sheet): new hands are seen as they come.
  void _syncWatching() {
    final hands = _side == _SidePanel.hands || _sheetPanel == _SidePanel.hands;
    _attention.setWatching(LiveAttentionKind.hands, hands);
  }

  void _openHands() => _togglePanel(_SidePanel.hands);
  void _openChat() => _togglePanel(_SidePanel.chat);

  Future<void> _showLiveSheet(Widget child) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: LayoutBuilder(builder: (ctx, box) {
          final h = (box.maxHeight.isFinite ? box.maxHeight : MediaQuery.sizeOf(ctx).height) *
              (MediaQuery.viewInsetsOf(ctx).bottom > 0 ? 1 : 0.85);
          return Directionality(
            textDirection: dir,
            child: SizedBox(
              height: h,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: Container(
                  decoration: BoxDecoration(
                    color: _surfaceHi,
                    border: Border(top: BorderSide(color: _glassBdr)),
                  ),
                  child: Column(children: [
                    Container(
                      width: 42,
                      height: 5,
                      margin: const EdgeInsets.only(top: 10, bottom: 2),
                      decoration: BoxDecoration(color: _glassBdr, borderRadius: BorderRadius.circular(3)),
                    ),
                    Expanded(child: child),
                  ]),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSidePanel(_SidePanel which, {bool inSheet = false}) {
    final VoidCallback close = inSheet
        ? () => Navigator.of(context, rootNavigator: false).maybePop()
        : _closeSidePanel;
    switch (which) {
      case _SidePanel.hands:
        return ValueListenableBuilder<String?>(
          valueListenable: _guestBusy,
          builder: (_, busy, _) => LiveHandsPanel(
            key: const ValueKey('live_room.hands_panel'),
            controller: _hands,
            isTeacher: widget.isTeacher,
            onClose: close,
            busyIdentity: busy,
            onLower: widget.isTeacher ? _hands.lower : null,
            onAllowSpeak: widget.isTeacher && !widget.isGuest
                ? (id) => _guestAllowSpeak(id, true)
                : null,
          ),
        );
      case _SidePanel.chat:
        return LiveChatPanel(
          key: const ValueKey('live_room.chat_panel'),
          controller: _chat,
          senderName: _myReactionName,
          canClear: widget.isTeacher,
          onClose: close,
        );
    }
  }

  // ── Guest moderation (teacher only; never from a guest's own device) ─────
  /// Identity whose call is in flight ('*' = mute all). A notifier so the hands panel inside a bottom sheet
  /// (a separate route, not rebuilt by this State) can show its spinner too.
  final ValueNotifier<String?> _guestBusy = ValueNotifier<String?>(null);
  void _setGuestBusy(String? v) {
    _guestBusy.value = v;
    if (mounted) setState(() {});
  }

  String _guestErrorText(Object e) {
    final ex = ApiException.from(e);
    final detail = ApiException.asMap(ex.body)?['detail'];
    final code = ex.code ?? (detail is Map ? detail['code'] : detail)?.toString();
    switch (code) {
      case 'guest_not_found':
        return 'lr_guest_not_found'.tr;
      case 'live_not_started':
        return 'lr_live_not_started'.tr;
    }
    return ex.message;
  }

  Future<bool> _guestCall(String identity, String path, {Map<String, dynamic>? body, String? okMsg}) async {
    if (!widget.isTeacher || widget.isGuest || _guestBusy.value != null) return false;
    _setGuestBusy(identity);
    try {
      await widget.apiClient.post(
        '/api/v1/live-sessions/${widget.sessionId}/guests/${Uri.encodeComponent(identity)}/$path',
        body: body,
      );
      if (okMsg != null) _showSnack(okMsg);
      return true;
    } catch (e) {
      _showSnack(_guestErrorText(e), error: true);
      return false;
    } finally {
      _setGuestBusy(null);
    }
  }

  Future<void> _guestMute(String identity) => _guestCall(identity, 'mute', okMsg: 'lr_guest_muted'.tr);

  Future<void> _guestAllowSpeak(String identity, bool allow) async {
    final ok = await _guestCall(identity, 'allow-speak',
        body: {'allow': allow}, okMsg: (allow ? 'lr_speak_allowed' : 'lr_speak_blocked').tr);
    if (ok && allow) _hands.lower(identity); // they got what they asked for
  }

  Future<void> _guestKick(String identity, String name) async {
    final yes = await appConfirm(context,
        message: trp('lr_remove_guest_confirm', {'name': name}),
        danger: true,
        confirmLabel: 'lr_remove_guest'.tr);
    if (!yes || !mounted) return;
    final ok = await _guestCall(identity, 'kick', okMsg: 'lr_guest_removed'.tr);
    if (ok) _hands.drop(identity);
  }

  Future<void> _guestsMuteAll() async {
    if (!widget.isTeacher || widget.isGuest || _guestBusy.value != null) return;
    _setGuestBusy('*');
    try {
      final r = await widget.apiClient.post('/api/v1/live-sessions/${widget.sessionId}/guests/mute-all');
      final n = r is Map ? (r['muted'] ?? 0) : 0;
      _showSnack(trp('lr_guests_muted_n', {'n': '$n'}));
    } catch (e) {
      _showSnack(_guestErrorText(e), error: true);
    } finally {
      _setGuestBusy(null);
    }
  }

  // Called by RoomScreenShareMixin when iOS broadcast starts/stops.
  @override
  void onIOSBroadcastStateChanged(bool active) {
    if (!mounted) return;
    setState(() => _isBroadcastingIOS = active);
    if (active) {
      showAppNotice('lr_share_hint'.tr, icon: Icons.screen_share_rounded, duration: const Duration(seconds: 4));
    }
  }

  bool _isBroadcastingIOS = false;

  /// A calendar meeting (courseId 0): the course-only calls (roster, quiz feed, attendance leave) are skipped.
  bool get _isMeeting => widget.ref.isMeeting;

  Future<void> _stopIOSBroadcast() async {
    if (!_isBroadcastingIOS) return;
    await stopIOSBroadcast();
  }

  List<ParticipantTrack> participantTracks = [];

  EventsListener<RoomEvent> get _listener => widget.listener;

  bool get fastConnection => widget.fastConnection;

  // ── LiveKit server recording status (shown to all participants) ───────────
  bool _serverRecording = false;

  // ── Client-side recorder (teacher only) ──────────────────────────────────
  ClientRecorder? _recorder;
  bool _recorderStarted = false; // guard: prevents multiple start() calls
  bool _endingSession = false;     // true while awaiting final chunk before onEnd()

  // ── [meeting-recording] begin ─────────────────────────────────────────────
  // A calendar meeting records to its creator's Google Drive / OneDrive (docs/backend/live-rooms-spec.md §5):
  // Record opens the setup sheet, the server answers chunk_path, and the same ClientRecorder posts there.

  /// The creator may record this meeting (feature key `live.meeting_recording`).
  bool get _canRecordMeeting =>
      widget.ref.isMeeting &&
      widget.canRecord &&
      !widget.isGuest &&
      !AppConfig.disableList.contains('live.meeting_recording');

  /// This device is the one recording: the teacher of a course session, or a meeting creator who pressed
  /// Record. Every recorder-only gate reads this instead of isTeacher.
  bool get _recordsHere => widget.isTeacher || _meetingRecording != null;

  RecordingStart? _meetingRecording;
  bool _meetingRecordBusy = false;

  Future<void> _recordMeeting() async {
    if (!_canRecordMeeting || _recorder != null || _meetingRecordBusy || _endingSession) return;
    final start = await showRecordSetupSheet(context, kind: widget.ref.kindName, id: widget.ref.id);
    if (start == null || !mounted) return;
    setState(() {
      _meetingRecording = start;
      _meetingRecordBusy = true;
    });
    try {
      await _startRecorderOnce(chunkPath: start.chunkPath, quality: start.quality, stopPath: start.stopPath);
    } catch (e) {
      log('[REC] meeting recording start error: $e');
      if (mounted) _showSnack(t('تعذّر بدء التسجيل', 'Could not start the recording'));
    } finally {
      if (mounted) setState(() => _meetingRecordBusy = false);
    }
  }

  Future<void> _stopMeetingRecording() async {
    final rec = _recorder;
    if (rec == null || _meetingRecording == null || _endingSession) return;
    final ok = await appConfirm(context,
        message: t('إيقاف التسجيل؟ يُجمَّع الملف ويُرفع إلى سحابتك.', 'Stop recording? The file is assembled and uploaded to your drive.'),
        confirmLabel: t('إيقاف', 'Stop'));
    if (!ok || !mounted) return;
    setState(() {
      _recorder = null;
      _meetingRecording = null;
      _recorderStarted = false; // a new recording may start later in the same room
    });
    _stopLiveKitAudioTap();
    unawaited(_stopAndDrain(rec));
  }

  /// Leaving a meeting without End (back swipe, disconnect): stop first, then drain — a bare drain would wait
  /// the whole timeout for a "done" that never comes. Runs in the background after the screen popped.
  static Future<void> _stopAndDrain(ClientRecorder rec) async {
    try {
      await rec.stopRecordingOnly();
    } catch (e) {
      log('[REC] meeting stop error: $e');
    }
    await _drainAndDispose(rec);
  }
  // ── [meeting-recording] end ───────────────────────────────────────────────

  // ── Part 2: free-time limit · info sheet (docs/backend/live-rooms-spec.md §8, §11) ──────────────────────────
  /// The meeting's owner: the only one who can lift the limit (the live plan).
  bool get _isMeetingOwner => widget.host && widget.ref.isMeeting && !widget.isGuest;

  /// The owner subscribed during this visit: the countdown is gone.
  bool _limitLifted = false;
  bool _planBusy = false;

  LiveTimeLimit? get _timeLimit {
    final end = widget.freeEndsAt;
    if (end == null) return null;
    return LiveTimeLimit(endsAt: end, isOwner: _isMeetingOwner, lifted: _limitLifted);
  }

  Future<void> _upgradePlan() async {
    if (_planBusy || !mounted) return;
    setState(() => _planBusy = true);
    try {
      final ok = await showLivePlanSheet(context);
      if (ok && mounted) setState(() => _limitLifted = true);
    } catch (e) {
      log('live plan sheet: $e');
    } finally {
      if (mounted) setState(() => _planBusy = false);
    }
  }

  /// The owner's "Free time ended" after the server deleted the room for the limit; Subscribe opens the plan.
  Future<void> _showFreeTimeEnded() async {
    final subscribe = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: LiveFreeTimeEndedCard(
          onSubscribe: () => Navigator.pop(ctx, true),
          onClose: () => Navigator.pop(ctx, false),
        ),
      ),
    );
    if (subscribe == true && mounted) {
      try {
        await showLivePlanSheet(context);
      } catch (e) {
        log('live plan sheet: $e');
      }
    }
  }

  LiveInfoRecording get _infoRecording {
    final st = _recorder?.state;
    if (_recordsHere && st == RecState.paused) return LiveInfoRecording.paused;
    if (_recordsHere && st == RecState.recording) return LiveInfoRecording.recording;
    if (_serverRecording) return LiveInfoRecording.server;
    if (!widget.ref.isMeeting && widget.recordingEnabled) return LiveInfoRecording.server;
    return LiveInfoRecording.off;
  }

  MeetingInfo _infoSnapshot() {
    final limit = _timeLimit;
    return MeetingInfo(
      title: widget.sessionName ?? '',
      isMeeting: widget.ref.isMeeting,
      role: widget.isGuest ? LiveRoomRole.guest : (widget.host ? LiveRoomRole.host : LiveRoomRole.member),
      hostName: widget.hostName,
      startsAt: widget.startsAt,
      elapsed: Duration(seconds: _sessionElapsedSeconds),
      liveFor: meetingLiveFor(widget.liveStartedAt, DateTime.now().toUtc(), own: Duration(seconds: _sessionElapsedSeconds)),
      participants: widget.room.remoteParticipants.length + 1,
      recording: _infoRecording,
      freeLeft: limit == null || limit.lifted ? null : limit.remaining(DateTime.now()),
    );
  }

  Future<void> _openInfo() async {
    _pokeControls();
    await showMeetingInfoSheet(context, ref: widget.ref, snapshot: _infoSnapshot);
  }

  bool _isPausingRecording = false; // true while pauseRecording() is in flight
  bool _isResumingRecording = false; // true while resumeRecording() is in flight

  // ── LiveKit mic PCM tap → native recorder ─────────────────────────────────
  // RPScreenRecorder's own .audioMic/.audioApp capture never delivers a
  // single sample while a LiveKit call is simultaneously active — its
  // internal mic tap can't get access to hardware LiveKit's WebRTC audio
  // engine already owns (confirmed via testing: audioSeen stayed 0
  // regardless of permission, duration, or session count). Instead, tap the
  // audio LiveKit is already successfully capturing for the call itself via
  // LocalAudioTrack.addAudioRenderer(), and forward those raw PCM frames to
  // the native recorder over the SAME method channel it already uses for
  // startMicRecording/stopRecording — see AppDelegate.swift's "sendAudioFrame"
  // case. iOS-only for now: Android's native recorder backend doesn't have
  // the corresponding handler yet.
  static const MethodChannel _audioFrameChannel =
  MethodChannel('com.example.flutter_education_app/native_recorder');
  CancelListenFunc? _audioTapCancel;
  // The exact LocalAudioTrack instance _audioTapCancel is currently bound
  // to. WebRTC renegotiation (e.g. adding a screen-share track) can cause
  // LiveKit to unpublish and republish the mic as a NEW LocalAudioTrack
  // object — if that happens, the OLD tap keeps existing (isn't cancelled,
  // doesn't log anything) but silently stops receiving frames forever,
  // since PCM now flows through the new object instead. Tracking the bound
  // instance lets _startLiveKitAudioTap() detect that mismatch and rebind,
  // rather than assuming "a tap exists" always means "the tap is live".
  LocalAudioTrack? _tappedAudioTrack;

  void _startLiveKitAudioTap() {
    if (kIsWeb || !Platform.isIOS) return;

    final micTrack = widget.room.localParticipant?.audioTrackPublications
        .map((pub) => pub.track)
        .whereType<LocalAudioTrack>()
        .firstOrNull;

    if (micTrack == null) {
      log('[REC] LiveKit audio tap: no published mic track yet — skipping');
      return;
    }

    if (_audioTapCancel != null && identical(_tappedAudioTrack, micTrack)) {
      // Already bound to the current track — nothing to do. Calling this
      // repeatedly (e.g. from LocalTrackPublishedEvent) must be a safe
      // no-op in the common case, not a churn of cancel+rebind every time.
      return;
    }

    // Either no tap yet, or it's bound to a stale/replaced track instance
    // — drop the old one (if any) before attaching to the current track.
    _audioTapCancel?.call();
    _audioTapCancel = null;

    _dropTapBuffer();
    _audioTapCancel = micTrack.addAudioRenderer(
      onFrame: (frame) {
        // I14: ~100 ms per channel call instead of one per 10 ms frame (the native side timestamps by sample
        // count and takes any frame size). A format change drops what was buffered in the old one.
        final fmt = (frame.sampleRate, frame.channels, frame.format.name);
        if (_tapFormat != fmt) {
          _dropTapBuffer();
          _tapFormat = fmt;
        }
        final bytesPerSample = frame.format == AudioFormat.Float32 ? 4 : 2;
        _tapChunks.add(frame.data);
        _tapBytes += frame.data.lengthInBytes;
        _tapFrames += frame.data.lengthInBytes ~/ (math.max(1, frame.channels) * bytesPerSample);
        if (_tapFrames >= frame.sampleRate ~/ 10) _flushTapBuffer();
      },
    );
    _tappedAudioTrack = micTrack;
    log('[REC] LiveKit audio tap: started');
  }

  // I14: the tap's batch (one sendAudioFrame per ~100 ms).
  final List<Uint8List> _tapChunks = [];
  int _tapBytes = 0;
  int _tapFrames = 0;
  (int, int, String)? _tapFormat;

  void _dropTapBuffer() {
    _tapChunks.clear();
    _tapBytes = 0;
    _tapFrames = 0;
  }

  void _flushTapBuffer() {
    final fmt = _tapFormat;
    if (fmt == null || _tapChunks.isEmpty) {
      _dropTapBuffer();
      return;
    }
    final out = Uint8List(_tapBytes);
    var at = 0;
    for (final c in _tapChunks) {
      out.setRange(at, at + c.lengthInBytes, c);
      at += c.lengthInBytes;
    }
    _dropTapBuffer();
    // Fire-and-forget: the audio callback never waits on the channel's round trip.
    _audioFrameChannel.invokeMethod<void>('sendAudioFrame', {
      'data': out,
      'sampleRate': fmt.$1,
      'channels': fmt.$2,
      'format': fmt.$3,
    }).catchError((Object e) => log('[REC] sendAudioFrame: $e'));
  }

  void _stopLiveKitAudioTap() {
    _audioTapCancel?.call();
    _audioTapCancel = null;
    _flushTapBuffer(); // what was buffered before the stop
    _tapFormat = null;
    _tappedAudioTrack = null;
    log('[REC] LiveKit audio tap: stopped');
  }

  // Exposed to RoomScreenShareMixin (see restartAudioTap contract) so the
  // iOS share-start flow can force a rebind check right after negotiation
  // settles, in addition to the automatic LocalTrackPublishedEvent hook
  // below — belt and suspenders, since renegotiation timing across
  // flutter_webrtc/LiveKit internals isn't something this app controls.
  @override
  void restartAudioTap() => _startLiveKitAudioTap();

  // ── Recording elapsed-time clock ──────────────────────────────────────────
  // Ticks every second while RecState.recording. Paused when recording is
  // paused, stopped when recording ends. Displayed in the REC badge.
  Timer? _recClockTimer;
  int _recElapsedSeconds = 0;

  // ── Total session clock ────────────────────────────────────────────────
  // Separate from the recording clock above: starts once when the room
  // connects and runs continuously for the whole session — never paused,
  // never reset, regardless of recording pause/resume/stop. Visible to
  // every participant (not gated by isTeacher like the recording badge),
  // since "how long has this session been going" is meaningful to
  // everyone, not just whoever's recording.
  Timer? _sessionClockTimer;
  int _sessionElapsedSeconds = 0;

  /// D-092: the two clocks tick this instead of setState — only the badge column and the iOS share banner listen,
  /// so the whole room (every tile, every video) is no longer rebuilt once a second.
  final ValueNotifier<int> _clockTick = ValueNotifier<int>(0);

  void _startSessionClock() {
    if (_sessionClockTimer != null) return; // already ticking — RoomConnectedEvent shouldn't fire twice, but be safe
    _sessionClockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) { _sessionClockTimer?.cancel(); _sessionClockTimer = null; return; }
      _sessionElapsedSeconds++;
      _clockTick.value++;
    });
  }

  // Controls bar: auto-hides on phones after 4 s without interaction, a tap on the video brings it back;
  // keyboard shortcuts (M / V / S / R / E) drive ControlsWidget through this key.
  final _controlsKey = GlobalKey<ControlsWidgetState>();
  final _shortcutsFocus = FocusNode(debugLabel: 'live_room_shortcuts');
  bool _controlsVisible = true;
  Timer? _controlsHideTimer;
  static const _controlsHideAfter = Duration(seconds: 4);

  bool get _controlsAutoHide =>
      mounted &&
      MediaQuery.sizeOf(context).width < kLiveControlsMobileBreakpoint &&
      !_reactions.pickerOpen &&
      !_annotOpen && // drawing: the bar stays (its Annotate action closes the toolbar)
      !(_isBoardMain && _board.canDrawLocal); // the same on the whiteboard

  void _pokeControls() {
    _controlsHideTimer?.cancel();
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    if (!_controlsAutoHide) return;
    _controlsHideTimer = Timer(_controlsHideAfter, () {
      if (!mounted) return;
      final next = liveControlsAfterIdle(visible: _controlsVisible, autoHide: _controlsAutoHide);
      if (next != _controlsVisible) setState(() => _controlsVisible = next);
    });
  }

  /// A tap on the stage (or on a self-view that has nothing to swap with): live_self_view.dart's rule.
  void _toggleControlsVisibility() {
    final next = liveControlsAfterTap(visible: _controlsVisible, autoHide: _controlsAutoHide);
    if (next.restartTimer) {
      _pokeControls();
    } else {
      _controlsHideTimer?.cancel();
      if (next.visible != _controlsVisible) setState(() => _controlsVisible = next.visible);
    }
  }

  KeyEventResult _onRoomKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    // Typing in a text field (chat, quiz …) must never trigger a shortcut.
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null && focused.findAncestorStateOfType<EditableTextState>() != null) {
      return KeyEventResult.ignored;
    }
    final controls = _controlsKey.currentState;
    final k = e.logicalKey;
    // The annotation toolbar's own keys (P / H / E / L, 1–3, Esc; AnnotationShortcuts) while it is open.
    if (_annotOpen &&
        (annotShortcutTool(k) != null || annotShortcutThickness(k) != null || k == LogicalKeyboardKey.escape)) {
      return KeyEventResult.ignored;
    }
    // The whiteboard's keys (V / P / H / I / A / R / O / T / E / L, 1-3, Delete, PageUp / PageDown) while drawing on it.
    if (_isBoardMain &&
        _board.canDrawLocal &&
        (boardShortcutTool(k) != null ||
            annotShortcutThickness(k) != null ||
            k == LogicalKeyboardKey.delete ||
            k == LogicalKeyboardKey.backspace ||
            k == LogicalKeyboardKey.pageUp ||
            k == LogicalKeyboardKey.pageDown ||
            k == LogicalKeyboardKey.escape)) {
      return KeyEventResult.ignored;
    }
    // Full view (D-095): Esc leaves it, F toggles it.
    if (k == LogicalKeyboardKey.escape && _focusOn) {
      _setFocus(false);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyF && _canFocus) {
      _setFocus(!_focusOn);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyM) {
      controls?.toggleMic();
    } else if (k == LogicalKeyboardKey.keyV) {
      controls?.toggleCamera();
    } else if (k == LogicalKeyboardKey.keyS) {
      if (_shareButtonMode == LiveShareButton.hidden) return KeyEventResult.ignored;
      controls?.toggleShare();
    } else if (k == LogicalKeyboardKey.keyR) {
      _reactions.togglePicker();
    } else if (k == LogicalKeyboardKey.keyH) {
      controls?.toggleHand();
    } else if (k == LogicalKeyboardKey.keyC) {
      controls?.openChat();
    } else if (k == LogicalKeyboardKey.keyE || k == LogicalKeyboardKey.end) {
      controls?.requestEnd();
    } else {
      return KeyEventResult.ignored;
    }
    _pokeControls();
    return KeyEventResult.handled;
  }

  // Participant panel
  bool _showParticipants = false;
  List<EnrolledStudent> _enrolledStudents = [];
  bool _loadingStudents = false;

  // Quiz
  ActiveQuiz? _activeQuiz;
  bool _quizVisible = false;
  Timer? _quizPollTimer;
  StreamSubscription<LiveEvent>? _quizEvents;
  int _currentQuestionIndex = 0;
  Map<int, int> _selectedAnswers = {};
  bool _quizSubmitted = false;
  Timer? _quizTimer;
  int _quizSecondsLeft = 0;

  // ── D-092: the self-view (widgets/self_view_pip.dart, rules in live_self_view.dart) ──
  // When true, my camera is on the stage and the stage's video sits in the box (a tap on the box; only while the
  // stage shows someone's video or a share — never a board, which would disappear).
  bool _pipSwapped = false;

  /// "Hide self view" — per room (the next class starts with it shown).
  bool _selfHidden = false;

  SelfViewPrefs get _selfPrefs => SelfViewStore.instance.value;

  void _onSelfViewPrefs() {
    if (!mounted) return;
    setState(() {});
    _syncAurora();
  }

  /// My camera while it sends a picture (published and not muted); null otherwise.
  LocalVideoTrack? get _localCamTrack {
    final local = widget.room.localParticipant;
    if (local == null) return null;
    for (final pub in local.videoTrackPublications) {
      if (pub.isScreenShare || isBoardVideoName(pub.name)) continue;
      final t = pub.track;
      if (t != null && !pub.muted) return t;
    }
    return null;
  }

  /// Someone's video, a share (mine too, even before its tile exists) or a board is on the stage.
  bool get _stageHasOther =>
      _stageTracks.isNotEmpty || _isBoardMain || (widget.room.localParticipant?.isScreenShareEnabled() ?? false);

  /// A tap on the box swaps it with the stage only while the stage shows a video (someone's camera or a share).
  bool get _canSwapSelf => _stageTracks.isNotEmpty && !_isBoardMain;

  SelfViewSpot get _selfSpot => selfViewSpot(
        camOn: _localCamTrack != null,
        stageHasOther: _stageHasOther,
        swapped: _pipSwapped && _canSwapSelf,
        hidden: _selfHidden,
        aloneOnStage: _selfPrefs.aloneOnStage,
        parked: _videoParked,
      );

  // Animations
  late AnimationController _thumbBarAnim;
  late Animation<double> _thumbBarFade;
  late AnimationController _recDotAnim;
  late Animation<double> _recDotOpacity;
  late AnimationController _auroraAnim;
  late AnimationController _entryAnim;
  late Animation<double> _entryFade;
  late Animation<double> _entrySlide;
  late AnimationController _panelAnim;
  late Animation<double> _panelSlide;
  late AnimationController _quizAnim;
  late Animation<double> _quizSlide;

  // _screenShareChannel → RoomScreenShareMixin

  Future<void> _requestPermissions() async {
    if (kIsWeb) return;
    try {
      if (lkPlatformIs(PlatformType.android)) {
        // Request both at once — Android shows them sequentially.
        final statuses = await [
          Permission.camera,
          Permission.microphone,
        ].request();

        if (statuses[Permission.camera] != PermissionStatus.granted) {
          log('[PERM] Camera permission denied — recording will have no camera PiP');
        }
        if (statuses[Permission.microphone] != PermissionStatus.granted) {
          log('[PERM] Microphone permission denied — recording will have no audio');
        }
      } else {
        // iOS: request microphone permission before RPScreenRecorder starts.
        // Without this, the AVAudioSession mic input is silent on first launch.
        final mic = await Permission.microphone.request();
        if (mic != PermissionStatus.granted) {
          log('[PERM] iOS microphone permission denied — audio will be silent');
        }
      }
    } catch (e) {
      log('[PERM] _requestPermissions error: $e');
    }
  }

// ═══════════════════════════════════════════════════════════════════════════
// 2.  initState()
// ═══════════════════════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
    AppAssistant.hide(); // full screen: no floating assistant bubble
    _setUpListeners();
    // Android: share stopped from the system UI, phone calls (RoomScreenShareMixin).
    initLiveNativeEvents();
    // iOS: the share state follows the broadcast extension (RoomScreenShareMixin, I3).
    initIOSBroadcastState();
    // Android 14+: keeps the microphone alive in the background (a listen-only participant needs nothing). The
    // notification's Leave only brings the app to the front; the usual confirmation and End follow.
    if (_allowed.mic) unawaited(LiveCallService.start());
    LiveCallService.onLeaveRequested = () {
      if (mounted) unawaited(_leaveFromMiniBox());
    };
    // Annotation (D-079): the Android overlay's burned-in switch, the students' notices.
    annotationOverlayActive.addListener(_onAnnotOverlay);
    _annot.addListener(_onAnnotChanged);
    _annotGranted = _annotStudentGranted;
    _board.addListener(_onBoardChanged); // the "Whiteboard" region
    // One share at a time, requests, attention badges, the chat preview (the "Share arbitration" region).
    _shareEvents = _share.events.listen(_onShareEvent);
    _share.addListener(_onShareChanged);
    _attention.addListener(_onAttention);
    _chat.addListener(_onChatChanged);
    // A class can last hours: never let the phone sleep (it pauses camera / mic on many devices).
    WakelockPlus.enable().catchError((_) {});

    // ── Animations ────────────────────────────────────────────────────────────
    _thumbBarAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _thumbBarFade = CurvedAnimation(
      parent: _thumbBarAnim,
      curve: Curves.easeOut,
    );

    _recDotAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _recDotOpacity = Tween<double>(begin: 1.0, end: 0.25).animate(
      CurvedAnimation(parent: _recDotAnim, curve: Curves.easeInOut),
    );

    _auroraAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _entryAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _entryFade = CurvedAnimation(parent: _entryAnim, curve: Curves.easeOut);
    _entrySlide = CurvedAnimation(
      parent: _entryAnim,
      curve: const Interval(0.15, 1.0, curve: Curves.easeOutCubic),
    );
    _entryAnim.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pokeControls());

    _panelAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _panelSlide = CurvedAnimation(
      parent: _panelAnim,
      curve: Curves.easeOutCubic,
    );

    _quizAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _quizSlide = CurvedAnimation(
      parent: _quizAnim,
      curve: Curves.easeOutBack,
    );

    _serverRecording = widget.room.isRecording;
    // One source of re-layouts: the room's events (the Room's own ChangeNotifier fired for the same changes
    // again — D21), throttled in _scheduleSort.
    _hands.addListener(_onHandsChanged);
    _sortParticipants();
    _rememberLocalChoices();
    _lifecycle = AppLifecycleListener(onStateChange: _onAppLifecycle);
    _media
      ..addListener(_onMediaChanged)
      ..start();
    _board.scene.addListener(_onBoardScene);
    // D-092: the remembered self-view (shape, size, position, alone on the stage).
    SelfViewStore.instance.addListener(_onSelfViewPrefs);
    unawaited(SelfViewStore.instance.load());
    // D-094: the presenter's camera box over a share (shape, size, position).
    PresenterCamStore.instance.addListener(_onSelfViewPrefs);
    unawaited(PresenterCamStore.instance.load());

    if (lkPlatformIs(PlatformType.android)) {
      // Same call Hardware.setSpeakerphoneOn(true) forwarded to before it was deprecated.
      unawaited(AudioManager.instance.setSpeakerOutputPreferred(true));
    }

    // Guests have no token: the roster and the quiz feed need an account. A calendar meeting has no course
    // (courseId 0): no roster, no quiz feed.
    if (!widget.isGuest && !_isMeeting) _fetchEnrolledStudents();
    if (!widget.isTeacher && !widget.isGuest && !_isMeeting) _startQuizPolling();
    if (widget.isTeacher && !_isMeeting) LiveQuizBroadcast.latest.addListener(_onQuizPublished);
    _startLobby(); // host only; see the "Lobby" region
    _startControls(); // host only; see the "Host controls" region

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Annotation: ask the room for the board (a late joiner sees what is drawn already).
      if (mounted && _annotEnabled) _annot.requestSnapshot();
      // Whiteboard: the presenter (if any) sends the board.
      if (mounted && _boardEnabled) _requestBoard();

      // ── Step 1: request runtime permissions ───────────────────────────────
      // CAMERA and MICROPHONE are dangerous permissions on Android 6+.
      // PixelCopy itself needs no permission, but camera PiP and mic
      // recording require these to be granted at runtime.
      if (widget.isTeacher) {
        await _requestPermissions();
      }

      // ── Step 2: enable HD audio ────────────────────────────────────────────
      final local = widget.room.localParticipant;
      // Listen-only guests never publish: skipping this keeps their mic off (the server token would refuse anyway).
      // A person who switched the mic off on the pre-join page stays muted until they unmute themselves.
      if (local != null && _allowed.mic && widget.enableAudio) await _enableHdAudio(local);

      // ── Step 3: start recorder if room is already connected ────────────────
      // Handles the race where the room connected before initState() ran.
      if (_deviceRecords && widget.room.connectionState == ConnectionState.connected) {
        await _startRecorderOnce();
      }
    });
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _depsReady = true;
    // Hosted in LiveRoomLayer: follow the box (minimized → the aurora and the REC dot stop).
    if (_minimized == null && LiveRoomScope.maybeOf(context) != null) {
      _minimized = LiveRoomHost.minimizedListenable;
      _minimized?.addListener(_syncDecorLoops);
      _minimized?.addListener(_onMinimizedVideo);
    }
    _syncDecorLoops();
    if (!_annotColorSet) {
      _annotColorSet = true;
      _annot.setColor(annotPresetColors(context.colors).first.toARGB32());
    }
  }

  void _onRecorderUpdate() {
    if (!mounted) return;
    final state = _recorder?.state;
    if (state == RecState.recording) {
      _ensureRecClockRunning();
    } else {
      _stopRecClock(pause: state == RecState.paused);
    }
    setState(() {});
  }

  void _ensureRecClockRunning() {
    if (_recClockTimer != null) return; // already ticking
    _recClockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) { _recClockTimer?.cancel(); _recClockTimer = null; return; }
      _recElapsedSeconds++;
      _clockTick.value++;
    });
  }

  void _stopRecClock({bool pause = false}) {
    _recClockTimer?.cancel();
    _recClockTimer = null;
    if (!pause) {
      // Full stop — reset counter so next recording starts from 0.
      _recElapsedSeconds = 0;
    }
    // When paused we keep _recElapsedSeconds so it resumes from where it left off.
  }

  String _formatElapsed(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
    }
    return '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
  }

  String get _recElapsedLabel => _formatElapsed(_recElapsedSeconds);

  /// The "reconnecting" notice while it is up (it stays until the network is back or the room closes).
  String? _netNotice;

  /// Weak network: tell people what is happening instead of showing a frozen picture. A notice, not a SnackBar:
  /// the room's Scaffold sits under its own sheets and dialogs, the notice above them.
  void _showNetBanner(bool reconnecting) {
    if (!mounted) return;
    final msg = (reconnecting ? 'lr_reconnecting' : 'lr_reconnected').tr;
    showAppNotice(msg,
        error: reconnecting,
        icon: reconnecting ? Icons.wifi_off_rounded : Icons.wifi_rounded,
        duration: reconnecting ? const Duration(minutes: 5) : const Duration(seconds: 2));
    _netNotice = reconnecting ? msg : null;
  }

  @override
  void dispose() {
    _sortThrottle.dispose();
    _sortRecheck?.cancel();
    _lifecycle?.dispose();
    _minimized?.removeListener(_syncDecorLoops);
    _minimized?.removeListener(_onMinimizedVideo);
    _media
      ..removeListener(_onMediaChanged)
      ..dispose();
    _board.scene.removeListener(_onBoardScene);
    SelfViewStore.instance.removeListener(_onSelfViewPrefs);
    PresenterCamStore.instance.removeListener(_onSelfViewPrefs);
    _clockTick.dispose();
    unawaited(_boardVideo.stop());
    _lobby?.dispose();
    _controls?.dispose();
    // Annotation: the Android overlay is hidden by disposeLiveNativeEvents() below (it owns onClosed).
    annotationOverlayActive.removeListener(_onAnnotOverlay);
    _annot.removeListener(_onAnnotChanged);
    _annot.dispose();
    _board.removeListener(_onBoardChanged);
    if (_board.isLocalPresenting) _board.stopPresenting(); // best effort: the room may be gone already
    _board.dispose();
    unawaited(_shareEvents?.cancel());
    _share.removeListener(_onShareChanged);
    _share.dispose();
    _attention.removeListener(_onAttention);
    _attention.dispose();
    _chat.removeListener(_onChatChanged);
    _chatToastTimer?.cancel();
    _lobby?.removeListener(_syncAttention);
    unawaited(LiveCallService.stop());
    LiveCallService.onLeaveRequested = null;
    _reactions.dispose();
    _hands.removeListener(_onHandsChanged);
    LiveQuizBroadcast.latest.removeListener(_onQuizPublished);
    _quizEvents?.cancel();
    _hands.dispose();
    _chat.dispose();
    _guestBusy.dispose();
    WakelockPlus.disable().catchError((_) {});
    if (_netNotice != null) hideAppNotice(message: _netNotice);
    if (!widget.isTeacher && !widget.isGuest && !_isMeeting) {
      // Check-out time: without this every student's attendance showed "stayed 0 min" (check-out = join time).
      // (A guest has no attendance record and no token: nothing to send. A meeting is not a course session.)
      widget.apiClient
          .post('/api/v1/live-sessions/${widget.sessionId}/leave')
          .then((_) {}, onError: (_) {});
    }
    unawaited(_disposeRoomAsync());
    _thumbBarAnim.dispose();
    _recDotAnim.dispose();
    _auroraAnim.dispose();
    _entryAnim.dispose();
    _panelAnim.dispose();
    _quizAnim.dispose();
    _controlsHideTimer?.cancel();
    _shortcutsFocus.dispose();
    _quizPollTimer?.cancel();
    _quizTimer?.cancel();
    _recClockTimer?.cancel();
    _sessionClockTimer?.cancel();
    _liveScreenCaptureTimer?.cancel();
    _webPlaceholderDebounce?.cancel();
    // iOS: a broadcast still running when the room closes would keep ReplayKit capturing after the person
    // left. Before the recorder is detached below (stopIOSBroadcast unhooks its broadcast events).
    if (!kIsWeb && Platform.isIOS) {
      unawaited(stopIOSBroadcast(leaving: true));
      disposeBroadcastSub();
    }
    // Android: a share still running ends with the room (VirtualDisplay + projection released).
    disposeLiveNativeEvents();
    // Recorder: if user exits without pressing End Session (e.g. back-swipe),
    // stop the camera fast and drain remaining uploads in the background.
    if (_recorder != null) {
      final rec = _recorder!;
      _recorder = null;
      _stopLiveKitAudioTap();
      // [meeting-recording] a meeting recording is stopped first (see _stopAndDrain)
      unawaited(_meetingRecording != null ? _stopAndDrain(rec) : _drainAndDispose(rec));
    }
    AppAssistant.release();
    super.dispose();
  }

  /// Leaves the screen. Hosted in [LiveRoomLayer] (the normal way: the room can be minimized to a box) the
  /// layer is closed and the pre-join page pops itself; pushed as a plain route, the room and the pre-join
  /// page pop.
  void _leaveRoom() {
    // Once: End for everyone may close the room from its own call AND from the disconnect it causes (a plain
    // route would otherwise pop twice as many pages).
    if (!mounted || _leftRoom) return;
    _leftRoom = true;
    unawaited(LiveCallService.stop());
    LiveCallService.onLeaveRequested = null;
    final scope = LiveRoomScope.maybeOf(context);
    if (scope != null) {
      scope.close();
      return;
    }
    Navigator.pop(context);
    if (mounted) Navigator.pop(context);
  }

  bool _leftRoom = false;

  /// The hang-up button of the minimized box: back to full screen, then the same confirmation as End.
  Future<void> _leaveFromMiniBox() async {
    LiveRoomScope.maybeOf(context)?.expand();
    final ok = await context.showDisconnectDialog();
    if (ok != true || !mounted) return;
    // The same path as the End button: it closes the layer, and the page's dispose disconnects the room once
    // (a second disconnect() here raced that one).
    await _endSessionWithRecording();
  }

  Future<void> _disposeRoomAsync() async {
    await _listener.dispose();
    await widget.room.dispose();
  }

  // ── End session ───────────────────────────────────────────────────────────
  //
  // Mobile: stopRecordingOnly() → ACTION_STOP (fast, < 200ms) → pop immediately.
  //   The native FGS drains remaining uploads independently and calls stopSelf()
  //   only after all pendingUploads reach zero (up to 120s) — this happens
  //   at the OS level regardless of Dart-side sequencing below, so the
  //   onEnd-before-drain ordering mainly matters for web (see next note).
  //   _drainAndDispose runs unawaited and waits for RecState.done via polling.
  //
  // Web: stopRecordingOnly() now only stops the LOCAL recorder/compositor —
  //   it no longer waits for chunk uploads to finish (see WebRecorder.stop()
  //   in recorder_web_impl.dart), so this resolves in well under a second.
  //   The end-session API call (widget.onEnd(), hitting the server's
  //   /live-sessions/{id}/end endpoint) is explicitly sequenced to complete
  //   BEFORE the remaining chunk drain/upload starts — see the unawaited
  //   block below. Both still run entirely in the background, not blocking
  //   this function or the teacher's screen: onEnd() alone can take up to
  //   ~150s server-side, and the server tolerates the client moving on
  //   before the final chunk lands (see local_recorder.py's assembly
  //   pipeline) — there's nothing that needs the screen to stay frozen for
  //   either call, only that they run in this specific order relative to
  //   each other.
  /// [serverEnded]: the room was already ended on the server (End for everyone): the recorder is stopped and
  /// drained the same way, without a second `onEnd` call.
  Future<dynamic> _endSessionWithRecording({bool serverEnded = false}) async {
    if (_endingSession) return null;
    if (mounted) setState(() => _endingSession = true);

    final rec = _recorder;
    _recorder = null; // detach so dispose() never interferes

    if (_recordsHere && // [meeting-recording]
        rec != null &&
        rec.state != RecState.done &&
        rec.state != RecState.error) {
      try {
        _stopLiveKitAudioTap();
        await rec.stopRecordingOnly();
        log('[REC] stopRecordingOnly complete — recorder stopped locally; '
            'any remaining chunks upload in the background');
      } catch (e) {
        log('[REC] stopRecordingOnly error: $e');
      }

      // Web only: hadRealData is set synchronously the moment any real
      // chunk was ever captured, so this is accurate immediately — it does
      // NOT depend on whether background uploads have finished yet.
      if (kIsWeb && !rec.webHadRealData && mounted) {
        _showSnack(
          'lr_no_recording_saved'.tr,
        );
      }
    }

    // Sequenced in the background: the end-session API call now completes
    // FIRST, and only THEN do any remaining recorded chunks get
    // drained/uploaded — per explicit requirement. Previously these two
    // ran as separate unawaited() calls with no ordering between them, so
    // depending on timing the chunk upload could finish before, during, or
    // after the end-session call landed server-side.
    //
    // Still entirely non-blocking for the UI — the screen pops immediately
    // below, unchanged from before. This only changes the ORDER these two
    // background operations run in relative to EACH OTHER, not whether the
    // teacher's screen waits on either of them (see the comment above this
    // function for why blocking navigation on either call, especially
    // onEnd()'s up-to-150s server-side wait, would be a bad regression).
    unawaited(() async {
      if (!serverEnded) {
        try {
          await widget.onEnd();
        } catch (e) {
          log('[REC] onEnd error: $e');
        }
      }
      if (rec != null) {
        await _drainAndDispose(rec);
      }
    }());

    // L1: an Android share with device audio soft-mutes the mic; really mute it before the disconnect, so the
    // last frames are never heard.
    if (!kIsWeb && lkPlatformIs(PlatformType.android)) {
      try {
        await LiveMicGate.instance.release(widget.room.localParticipant);
      } catch (e) {
        log('[LIVE] mic gate release: $e');
      }
    }
    _leaveRoom();
    return null;
  }

  // ── NEW: pause recording ──────────────────────────────────────────────────
  //
  // Tells the native chunk loop to finish the current chunk and park.
  // Guarded so double-taps and rapid UI re-renders are safe.
  Future<void> _pauseRecording() async {
    final rec = _recorder;
    if (rec == null || rec.state != RecState.recording) return;
    if (_isPausingRecording || _endingSession) return;
    if (mounted) setState(() => _isPausingRecording = true);
    try {
      await rec.pauseRecording();
    } catch (e) {
      log('[REC] _pauseRecording error: $e');
    } finally {
      if (mounted) setState(() => _isPausingRecording = false);
    }
  }

  // ── NEW: resume recording ─────────────────────────────────────────────────
  //
  // Wakes the parked chunk loop and resumes chunking from the next index.
  Future<void> _resumeRecording() async {
    final rec = _recorder;
    if (rec == null || rec.state != RecState.paused) return;
    if (_isResumingRecording || _endingSession) return;
    if (mounted) setState(() => _isResumingRecording = true);
    try {
      await rec.resumeRecording();
    } catch (e) {
      log('[REC] _resumeRecording error: $e');
    } finally {
      if (mounted) setState(() => _isResumingRecording = false);
    }
  }

  /// Waits for all in-flight chunk uploads (RecState.done) then disposes.
  /// Runs in background after screen has already popped.
  static Future<void> _drainAndDispose(ClientRecorder rec) async {
    try {
      await rec.drainPending();
    } catch (e) {
      log('[REC] background drain error: $e');
    } finally {
      try {
        await rec.dispose();
      } catch (_) {}
      log('[REC] background drain complete');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Enrolled students
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _fetchEnrolledStudents() async {
    if (_loadingStudents || widget.isGuest || _isMeeting) return;
    if (mounted) setState(() => _loadingStudents = true);
    try {
      final resp = await widget.apiClient.get(
        '/api/v1/courses/${widget.courseId}/students',
      );
      final participants =
      await widget.apiClient.get(
        '/api/v1/live-sessions/${widget.sessionId}/participants',
      )
      as List<dynamic>;
      final ids = participants.map<int>((p) => p['student_id'] as int).toList();
      final joins = participants
          .map<String?>((p) => p['join_date']?.toString())
          .toList();
      final leaves = participants
          .map<String?>((p) => p['leave_date']?.toString())
          .toList();
      if (resp['students'] is List) {
        if (mounted) {
          setState(() {
            _enrolledStudents = (resp['students'] as List)
                .map(
                  (e) => EnrolledStudent.fromJson(
                e as Map<String, dynamic>,
                ids,
                joins,
                leaves,
              ),
            )
                .toList()
                .cast<EnrolledStudent>();
          });
        }
      }
    } catch (e) {
      log('fetchEnrolledStudents error: $e');
    } finally {
      if (mounted) setState(() => _loadingStudents = false);
    }
  }

  // ── Quiz feed (students) ───────────────────────────────────────────────────
  // One fetch on join. Then the teacher's data packet on topic 'quiz' (LiveQuizBroadcast, sent when they publish
  // an exam of the course from their open room) and the live event `quiz_started{course_id}` fetch at once; the
  // periodic poll is only the fallback (a teacher who published from another device).
  static const _quizFallbackPoll = Duration(minutes: 5);

  void _startQuizPolling() {
    _quizPollTimer = Timer.periodic(_quizFallbackPoll, (_) => _pollActiveQuiz());
    _quizEvents = LiveEvents.instance.listen({LiveEvents.quizStarted}, (e) {
      final cid = int.tryParse('${e.data['course_id'] ?? ''}');
      if (cid == null || cid == widget.courseId) _pollActiveQuiz();
    });
    _pollActiveQuiz();
  }

  /// A 'quiz' packet from the teacher: fetch the active exam now (students only; a guest has no token).
  void _onQuizPacket(List<int> bytes) {
    if (widget.isTeacher || widget.isGuest || _isMeeting) return;
    final s = LiveQuizBroadcast.decode(bytes);
    if (s == null || (s.courseId != null && s.courseId != widget.courseId)) return;
    _pollActiveQuiz();
  }

  /// Teacher: an exam of this course was just published → one reliable packet on topic 'quiz'.
  void _onQuizPublished() {
    final s = LiveQuizBroadcast.latest.value;
    if (s == null || !widget.isTeacher || !mounted) return;
    if (s.courseId != null && s.courseId != widget.courseId) return;
    unawaited(widget.room.localParticipant
        ?.publishData(LiveQuizBroadcast.encode(s), reliable: true, topic: kLiveQuizTopic));
  }

  Future<void> _pollActiveQuiz() async {
    if (!mounted) return;
    try {
      final data = await widget.apiClient.get(
        '/api/v1/courses/${widget.courseId}/exams/active',
      );
      if (data == null || data is! List || data.isEmpty) return;
      final examJson = data.first as Map<String, dynamic>;
      final examId = examJson['id'] as int? ?? 0;
      final qData = await widget.apiClient.get(
        '/api/v1/exams/$examId/questions',
      );
      if (qData == null || qData is! List) return;
      examJson['questions'] = qData;
      final newQuiz = ActiveQuiz.fromJson(examJson);
      if (!mounted) return;
      if (_activeQuiz?.examId != newQuiz.examId && !_quizSubmitted) {
        setState(() {
          _activeQuiz = newQuiz;
          _quizVisible = true;
          _currentQuestionIndex = 0;
          _selectedAnswers = {};
          _quizSubmitted = false;
          _quizSecondsLeft = newQuiz.durationMinutes * 60;
        });
        _quizAnim.forward();
        _startQuizTimer();
      }
    } catch (e) {
      log('pollActiveQuiz error: $e');
    }
  }

  void _startQuizTimer() {
    _quizTimer?.cancel();
    _quizTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_quizSecondsLeft <= 0) {
        _quizTimer?.cancel();
        _submitQuiz(autoSubmit: true);
      } else {
        setState(() => _quizSecondsLeft--);
      }
    });
  }

  Future<void> _submitQuiz({bool autoSubmit = false}) async {
    if (_activeQuiz == null || _quizSubmitted) return;
    if (mounted) setState(() => _quizSubmitted = true);
    _quizTimer?.cancel();
    for (final entry in _selectedAnswers.entries) {
      await widget.apiClient.post(
        '/api/v1/exam-answers',
        body: {
          'exam_id': _activeQuiz!.examId,
          'question_id': entry.key,
          'selected_option': entry.value,
        },
      );
    }
    if (!mounted) return;
    _showSnack(
      autoSubmit ? 'lr_quiz_auto_submitted'.tr : 'lr_quiz_submitted'.tr,
    );
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) _dismissQuiz();
  }

  void _dismissQuiz() {
    _quizAnim.reverse().then((_) {
      if (mounted) setState(() => _quizVisible = false);
    });
  }

  // ── Recording placeholder: mirror the real live screen ──────────────
  // iOS records the real on-screen UI directly — whatever's genuinely
  // rendered (camera, waiting card, anything else) is what its recording
  // shows automatically, no extra code needed. Web's compositor already
  // composites a live camera MediaStream when one's attached (see
  // room_recorder.dart's addStream(stream, 'camera')) — Flutter web can't
  // screenshot that HTML <video> platform view via RepaintBoundary even if
  // we wanted to, so the compositor's own drawing is the only way real
  // video gets into a web recording. Web only needs the placeholder-image
  // swap (_sendLiveScreenPlaceholderWeb below) for the "nothing to show"
  // case.
  //
  // Android has no such path: its pre-Share recording is entirely
  // synthetic (a bitmap drawn by ScreenPlaceholderRenderer), so it needs
  // an explicit push of whatever should appear. Rather than recreating
  // camera-view/waiting-card/speaker-badge logic separately (as an earlier
  // version of this did), this periodically screenshots the ENTIRE live
  // screen — see _liveScreenCaptureKey's RepaintBoundary wrapping the
  // whole Scaffold body in build(): aurora background, recording
  // indicator, thumbnail strip, PiP, the main video/waiting card, AND the
  // controls bar footer — and sends that. Whatever's truly on screen is
  // what gets sent, automatically, with no per-component or per-state
  // branching to keep in sync by hand.
  //
  // KNOWN RISK: if _buildMainVideo() is currently showing
  // VideoTrackRenderer(renderMode: VideoRenderMode.texture) (camera view),
  // that may be backed by a hardware SurfaceTexture that some
  // Skia/Impeller configurations can't read back via
  // RepaintBoundary.toImage() — some devices could see a black frame
  // instead of the real camera image. Test on real hardware; if frames
  // come back black, that's this platform limitation, not a bug here, and
  // would need a native camera-frame-bridging patch instead (mirroring
  // how screen-share frames already reach ElFaheemBridge).
  final GlobalKey _liveScreenCaptureKey = GlobalKey();
  Timer? _liveScreenCaptureTimer;
  // Guards against overlapping captures: Timer.periodic does NOT wait for
  // a tick's callback to finish before firing the next one. A full-screen
  // RepaintBoundary.toImage() + PNG encode + platform-channel round trip
  // is expensive enough (especially with a camera texture on screen) that
  // it can occasionally take longer than the tick interval — without this
  // guard, ticks pile up and never finish draining, which is exactly what
  // freezes the main isolate. This was the actual bug behind camera+share
  // freezing the app.
  bool _liveScreenCaptureInFlight = false;

  void _startLiveScreenCapture() {
    if (!widget.isTeacher || !Platform.isAndroid) return;
    _liveScreenCaptureTimer?.cancel();
    _liveScreenCaptureTimer = Timer.periodic(
      const Duration(milliseconds: 500), // ~2fps — see cost note above
          (_) => unawaited(_captureAndSendLiveScreen()),
    );
    unawaited(_captureAndSendLiveScreen()); // don't wait for the first tick
  }

  void _stopLiveScreenCapture() {
    _liveScreenCaptureTimer?.cancel();
    _liveScreenCaptureTimer = null;
  }

  /// Called from the ParticipantEvent listener so sharing starts/stops
  /// (which publish/unpublish a track, firing that event) pause/resume
  /// this without a direct cross-file call into room_screen_share.dart.
  void _maybeSyncLiveScreenCapture() {
    if (!widget.isTeacher || !Platform.isAndroid) return;
    // D-092: only while the device recorder records frames. Every participant event used to (re)start this for a
    // teacher — in server mode (Egress) and with no recording at all too — so the phone screenshotted the whole room
    // (a GPU read-back of the camera texture + a PNG encode + a channel call) twice a second for nothing.
    final r = _recorder;
    if (!_recorderStarted || r == null || r.audioOnly) {
      _stopLiveScreenCapture();
      return;
    }
    final sharing = widget.room.localParticipant?.isScreenShareEnabled() == true;
    if (sharing) {
      _stopLiveScreenCapture();
    } else if (_liveScreenCaptureTimer == null) {
      _startLiveScreenCapture();
    }
  }

  Future<void> _captureAndSendLiveScreen() async {
    // Overlap guard — see _liveScreenCaptureInFlight's doc comment above.
    if (_liveScreenCaptureInFlight) return;
    // Re-check right before doing the expensive work, not just when the
    // timer was scheduled: closes the gap between "sharing just started"
    // and the ParticipantEvent handler actually cancelling this timer —
    // without this, a tick already in flight (or one more queued tick)
    // could still run its full capture/encode/IPC cost concurrently with
    // the native screen-share pipeline right as it's starting up, which
    // is exactly the moment device resources are tightest.
    if (widget.room.localParticipant?.isScreenShareEnabled() == true) {
      _stopLiveScreenCapture();
      return;
    }
    _liveScreenCaptureInFlight = true;
    try {
      final png = await _captureLiveScreenPng();
      if (png == null) return;
      await const MethodChannel(
        'com.example.flutter_education_app/native_recorder',
      ).invokeMethod('setPlaceholderImage', {'png': png});
    } catch (e) {
      log('[REC] live screen capture/send error: $e');
    } finally {
      _liveScreenCaptureInFlight = false;
    }
  }

  // ── Listeners ──────────────────────────────────────────────────────────────
  void _setUpListeners() => _listener
    ..on<RoomConnectedEvent>((_) async {
      // Room is fully connected — safe to start the recorder now.
      // This fires exactly once after the LiveKit handshake completes,
      // so the MediaProjection dialog appears AFTER the camera/mic are
      // already running (no race with LiveKit track setup).
      log("----------------------111");
      _startSessionClock(); // everyone — total session time, not gated on isTeacher
      if (_deviceRecords) await _startRecorderOnce();
    })
    ..on<RoomDisconnectedEvent>((event) async {
      log('Room disconnected: reason => ${event.reason}');
      if (_endedForAll) {
        // This host ended the room for everyone: its own removal / the deleted room is no news to them. Leave as
        // after End (the recorder stops and drains; once, whichever of this and the call's answer comes first).
        WidgetsBindingCompatible.instance
            ?.addPostFrameCallback((_) => unawaited(_endSessionWithRecording(serverEnded: true)));
        return;
      }
      // A removal right after the host's "ending for everyone" packet is the session ending (live_end_signal.dart).
      final action = liveDisconnectActionAfterEndSignal(
        liveDisconnectAction(event.reason, isTeacher: widget.isTeacher),
        hostEnding: _endSignal.hostEnding(DateTime.now()),
      );
      final rejoin = widget.onRejoin;
      final mic = _lastMicOn, cam = _lastCamOn;
      WidgetsBindingCompatible.instance?.addPostFrameCallback((_) async {
        if (mounted) LiveRoomScope.maybeOf(context)?.expand(); // minimized: the dialog must be seen
        final limit = _timeLimit;
        var rejoinNow = false;
        if (event.reason == DisconnectReason.roomDeleted &&
            limit != null &&
            limit.showFreeTimeEnded(DateTime.now()) &&
            mounted) {
          // The server ended the meeting for the free-time limit: the owner is offered the plan.
          await _showFreeTimeEnded();
        } else if (action == LiveDisconnectAction.sessionEnded && mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const _SessionEndedDialog(),
          );
        } else if (mounted &&
            (action == LiveDisconnectAction.rejoin ||
                action == LiveDisconnectAction.removed ||
                action == LiveDisconnectAction.otherDevice)) {
          // A lost connection offers Rejoin (the pre-join page's join again); being removed or joining from
          // another device never rejoins by itself.
          final kind = switch (action) {
            LiveDisconnectAction.removed => LiveEndedKind.removed,
            LiveDisconnectAction.otherDevice => LiveEndedKind.otherDevice,
            _ => LiveEndedKind.lost,
          };
          rejoinNow = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => Dialog(
                  backgroundColor: Colors.transparent,
                  child: LiveRoomEndedCard(
                    kind: kind,
                    onRejoin: kind == LiveEndedKind.lost && rejoin != null ? () => Navigator.of(ctx).pop(true) : null,
                    onClose: () => Navigator.of(ctx).pop(false),
                  ),
                ),
              ) ==
              true;
        }
        _leaveRoom();
        if (rejoinNow && rejoin != null) rejoin(mic, cam);
      });
    })
    ..on<ParticipantEvent>((e) {
      // Data packets (chat, hands, reactions) and transcriptions change no tile.
      if (e is DataReceivedEvent || e is TranscriptionEvent) return;
      _scheduleSort();
      _maybeSyncLiveScreenCapture();
      _maybeRefreshWebPlaceholder();
    })
    ..on<ActiveSpeakersChangedEvent>((_) => _scheduleSort())
    // A raised hand leaves with its owner; a late joiner gets my raised hand re-announced.
    ..on<ParticipantDisconnectedEvent>((e) {
      _hands.drop(e.participant.identity);
      _share.participantLeft(e.participant.identity); // their request, approval and grant go too
      _board.participantLeft(e.participant.identity); // a presenter who left takes the board with them
      _scheduleSort();
    })
    ..on<ParticipantConnectedEvent>((e) {
      _hands.reannounceLocal();
      // Annotation: the responder (presenter, else the first host) sends the newcomer the board.
      if (_annotEnabled) _annot.onParticipantJoined(e.participant.identity);
      // Whiteboard: the presenter sends the newcomer the board.
      if (_boardEnabled) _board.onParticipantJoined(e.participant.identity);
      _scheduleSort();
    })
    // D29: the host let this participant speak / share, or took it back.
    ..on<ParticipantPermissionsUpdatedEvent>((e) {
      if (e.participant is LocalParticipant) unawaited(_onLocalPermissions(e.permissions));
    })
    ..on<RoomRecordingStatusChanged>((event) {
      // D25: a notice (and the REC pill), never a dialog on everyone's screen.
      if (!mounted || event.activeRecording == _serverRecording) return;
      setState(() => _serverRecording = event.activeRecording);
      _syncBoardVideo(); // D-090: the board goes into a server recording as a slow track
      showAppNotice((event.activeRecording ? 'lk_recording_active' : 'lk_recording_stopped').tr,
          icon: event.activeRecording ? Icons.fiber_manual_record_rounded : Icons.stop_circle_outlined);
    })
    ..on<RoomAttemptReconnectEvent>(
          (e) => log('Reconnect ${e.attempt}/${e.maxAttemptsRetry}'),
    )
    ..on<RoomReconnectingEvent>((_) => _showNetBanner(true))
    ..on<RoomReconnectedEvent>((_) {
      _showNetBanner(false);
      if (_annotEnabled) _annot.requestSnapshot(); // strokes sent while away
      if (_boardEnabled) _requestBoard(reconnected: true);
    })
    ..on<LocalTrackPublishedEvent>((_) {
      _scheduleSort();
      // Cheap no-op if already bound to the current mic track (see
      // _startLiveKitAudioTap's identical() check) — but if screen-share
      // negotiation (or anything else) caused LiveKit to republish the mic
      // as a new LocalAudioTrack instance, this is what catches it and
      // rebinds, instead of the recording silently losing mic audio for
      // the rest of the session with no error anywhere.
      if (widget.isTeacher) _startLiveKitAudioTap();
    })
    ..on<LocalTrackUnpublishedEvent>((e) {
      _scheduleSort();
      onLocalTrackUnpublished(e); // web: the browser's own "Stop sharing" (RoomScreenShareMixin)
    })
    ..on<TrackSubscribedEvent>((event) {
      _scheduleSort();
      // Mixes each remote participant's audio into the web recording —
      // previously NOTHING did this for any remote participant (only the
      // local teacher's own mic and, when sharing, screen audio ever
      // reached the recording), so students speaking never appeared in
      // it, regardless of whether they were audible live. Each
      // participant gets its own label (sid) in the compositor so they
      // don't overwrite each other. See nativeAudioStreamFromTrack's doc
      // comment in recorder_web_impl.dart for the one unverified part of
      // this bridge. Android/iOS need no equivalent: their local
      // recording captures ambient/room audio through the physical mic,
      // a fundamentally different mechanism unaffected by this gap.
      if (kIsWeb && _recordsHere && event.track is RemoteAudioTrack) { // [meeting-recording]
        final nativeStream = web_rec.nativeAudioStreamFromTrack(
          (event.track as RemoteAudioTrack).mediaStreamTrack,
        );
        _recorder?.addRemoteAudioStream(event.participant.sid, nativeStream);
      }
    })
    ..on<TrackUnsubscribedEvent>((event) {
      _scheduleSort();
      if (kIsWeb && _recordsHere && event.track is RemoteAudioTrack) { // [meeting-recording]
        _recorder?.removeRemoteAudioStream(event.participant.sid);
      }
    })
    ..on<TrackMutedEvent>((_) => _scheduleSort())
    ..on<TrackUnmutedEvent>((_) => _scheduleSort())
    ..on<TrackE2EEStateEvent>((e) => log('e2ee: $e'))
    ..on<ParticipantNameUpdatedEvent>((e) {
      log('Name: ${e.participant.identity} → ${e.name}');
      _scheduleSort();
    })
    ..on<DataReceivedEvent>((event) {
      final p = event.participant;
      final senderName = (p?.name.isNotEmpty ?? false) ? p!.name : p?.identity;
      if (event.topic == kLiveEndForAllTopic) {
        _endSignal.receive(event.data, senderIdentity: p?.identity);
        return;
      }
      switch (liveDataRoute(event.topic)) {
        case LiveDataRoute.reaction:
          _reactions.receive(event.data, fallbackName: senderName);
          return;
        case LiveDataRoute.quiz:
          _onQuizPacket(event.data);
          return;
        case LiveDataRoute.annotation:
          // The sender is LiveKit's participant, never an identity read from the payload.
          if (_annotEnabled) _annot.receive(event.topic!, event.data, sender: p?.identity);
          return;
        case LiveDataRoute.board:
          // The sender is LiveKit's participant, never an identity read from the payload.
          if (_boardEnabled) {
            _board.localIdentity = _myIdentity;
            _board.receive(event.topic!, event.data, sender: p?.identity);
          }
          return;
        case LiveDataRoute.share:
          // The sender is LiveKit's participant; an answer / stop counts only from a host the server set up.
          _share.receive(event.data,
              sender: p?.identity,
              senderIsHost: p != null && _isServerHost(p),
              senderName: senderName,
              senderImageUrl: participantPhotoFromMetadata(p?.metadata));
          return;
        case LiveDataRoute.handOrChat:
          // Hands and chat: matched by topic, and by payload type for senders that set no topic.
          if (_hands.receive(event.data, senderIdentity: p?.identity, fallbackName: senderName)) return;
          if (_chat.receive(event.data, senderIdentity: p?.identity, fallbackName: senderName)) return;
        case LiveDataRoute.ignore:
          break;
      }
      // Unknown topic / payload: any participant can publish data, so it is never shown on everyone's screen.
      if (kDebugMode) log('live data ignored: topic ${event.topic}, ${event.data.length} bytes');
    })
    ..on<AudioPlaybackStatusChanged>((event) async {
      if (!widget.room.canPlaybackAudio) {
        final yesNo = await context.showPlayAudioManuallyDialog();
        if (yesNo == true) await widget.room.startAudio();
      }
    });


  /// Screenshots the ACTUAL on-screen live screen (_liveScreenCaptureKey) — header, footer/controls, and main content all included —
  /// not a rebuilt duplicate widget — so whatever's genuinely live is what
  /// gets returned. Shared by Android's continuous capture
  /// (_captureAndSendLiveScreen) and Web's single-shot send below.
  Future<Uint8List?> _captureLiveScreenPng() async {
    if (LiveRoomHost.isMinimized) return null; // offstage in the box: nothing is painted to capture
    try {
      final boundary = _liveScreenCaptureKey.currentContext?.findRenderObject()
      as RenderRepaintBoundary?;
      if (boundary == null || boundary.debugNeedsPaint) return null;
      // pixelRatio lowered from an earlier video-tile-only version's 1.5 —
      // this now captures the whole screen, and the native renderer
      // letterboxes to fit anyway, so full device pixel ratio isn't worth
      // the extra encode time/memory on every ~2fps tick.
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      log('[REC] _captureLiveScreenPng error: $e');
      return null;
    }
  }

  /// Web: sends one screenshot of the real live screen to the JS compositor
  /// — only meaningful (and only called) when the screen is genuinely
  /// showing the waiting card, not the camera: a live camera feed on web
  /// is an HTML <video> platform view, invisible to Flutter's own capture,
  /// and already reaches the recording correctly via the compositor's own
  /// addStream(stream, 'camera') — pushing a screenshot over that would at
  /// best do nothing and at worst fight with the compositor's own drawing
  /// (recorder_compositor.js's actual precedence between a pushed
  /// placeholder image and a live attached stream isn't visible from these
  /// files, so this deliberately stays out of that camera-on case).
  /// Requires recorder_compositor.js to implement 'setPlaceholderImage' —
  /// see _compositorSetPlaceholderImage's doc comment in
  /// recorder_web_impl.dart.
  Future<void> _sendLiveScreenPlaceholderWeb() async {
    if (!kIsWeb || !_recordsHere) return; // [meeting-recording]
    final local = widget.room.localParticipant;
    if (local?.isScreenShareEnabled() == true) return;
    if (local?.isCameraEnabled() == true) return;
    final png = await _captureLiveScreenPng();
    if (png == null) return;
    _recorder?.setPlaceholderImage(png);
    log('[REC] placeholder image sent to web compositor (${png.length} bytes)');
  }

  Timer? _webPlaceholderDebounce;

  /// Debounced trigger for Web's single-shot send — hooked into the same
  /// ParticipantEvent listener as _maybeSyncLiveScreenCapture, so speaker
  /// changes, participants joining, and camera/share toggles all re-sync
  /// it without re-capturing on every single event.
  void _maybeRefreshWebPlaceholder() {
    if (!kIsWeb || !_recordsHere) return; // [meeting-recording]
    _webPlaceholderDebounce?.cancel();
    _webPlaceholderDebounce = Timer(
      const Duration(milliseconds: 1200),
          () => unawaited(_sendLiveScreenPlaceholderWeb()),
    );
  }

  Future<void> _startRecorderOnce({
    // [meeting-recording] the recording's own chunk route, quality and stop route (null = course session)
    String? chunkPath,
    RecordingQuality? quality,
    String? stopPath,
  }) async {
    if (_recorderStarted) return;
    _recorderStarted = true;

    _recorder = ClientRecorder(
      sessionId: widget.sessionId,
      apiClient: widget.apiClient,
      chunkPath: chunkPath,
      quality: quality,
      stopPath: stopPath,
    );
    _recorder!.addListener(_onRecorderUpdate);
    _recorder!.onNoMediaWarning = () {
      if (!mounted) return;
      _showSnack(
        'lr_cam_mic_unavailable'.tr,
      );
    };

    // Step 1: Configure the service with session params.
    // No dialog is shown yet; the service enters its ready state.
    await _recorder!.start();
    log('[REC] Recorder service configured');

    // Start capturing mic PCM from LiveKit's own already-working audio
    // pipeline (see _startLiveKitAudioTap's comment) — internally a no-op
    // on web/Android where it isn't needed/wired yet.
    _startLiveKitAudioTap();

    if (kIsWeb) {
      final local = widget.room.localParticipant;
      final teacherName = local?.name.isNotEmpty == true
          ? local!.name
          : (local?.identity ?? '');
      final sessionTitle = widget.sessionName ?? 'lr_live_session'.tr;
      final participantCount = widget.room.remoteParticipants.length + 1;
      await _recorder!.startWebCompositor(
        teacherName: teacherName,
        sessionTitle: sessionTitle,
        // +1 to include the local participant (teacher) themselves —
        // remoteParticipants only counts everyone else in the room.
        participantCount: participantCount,
      );
      // Screenshots the real on-screen waiting card (if that's what's
      // showing — see _sendLiveScreenPlaceholderWeb's doc comment for why
      // camera-on is deliberately skipped here) and sends it to the web
      // compositor, so the placeholder matches Android/iOS exactly instead
      // of the compositor's own separately hand-drawn one.
      unawaited(_sendLiveScreenPlaceholderWeb());
      return;
    }

    // Step 2-4 (screen-capture dialog + Phase-2 wait): iOS only from here on.
    // Android used to request the MediaProjection grant immediately at
    // session start, before the teacher ever intends to share — showing a
    // system dialog for a feature they might never use, and (with the old
    // architecture) requiring a second, separate MediaProjection grant from
    // flutter_webrtc later that forced local recording to pause during any
    // live share. Android now defers the single MediaProjection request
    // entirely to the Share button (see room_screen_share.dart), where one
    // grant drives both local recording and the live share simultaneously
    // via ElFaheemFrameCapturer — no downgrade-for-share needed. Until
    // Share is tapped, the session runs audio-only PLUS a rendered
    // placeholder (see ScreenPlaceholderRenderer.kt), matching the same
    // teacherName/sessionTitle/participantCount the web compositor above
    // already uses — sent once here so the native placeholder shows the
    // real session info instead of a flat color.
    // [meeting-recording] audio-only: nothing draws a frame anywhere — no Android screenshots for the
    // placeholder, no RPScreenRecorder on iOS. The native side records the audio alone from Phase 1.
    if (_recorder!.audioOnly) return;

    if (Platform.isAndroid) {
      // Starts the periodic real-screenshot capture (see
      // _startLiveScreenCapture) — whatever's genuinely on screen (waiting
      // card or camera view) is sent from the very first tick, no separate
      // one-shot send needed here.
      _startLiveScreenCapture();
      return;
    }

    // Step 2: Arm the Phase-2 completer BEFORE calling startScreenCaptureService.
    // On iOS, RPScreenRecorder.startCapture() emits 'screenLoopStarted' in its
    // async completion handler — which can fire before invokeMethod returns.
    // prepareUpgradeWait() creates the Completer now so _onNativeEvent can
    // resolve it even if it fires during the await below.
    _recorder!.prepareUpgradeWait();

    // Step 3: Start the native screen-capture service.
    // iOS:     calls RPScreenRecorder.startCapture() → mic-permission dialog
    //          on first use → red-pill indicator → AVAssetWriter chunk loop.
    // Both platforms return true when capture is actively running.
    try {
      final granted = await const MethodChannel(
        'com.example.flutter_education_app/screen_share',
      ).invokeMethod<bool>('startScreenCaptureService');

      if (granted == true) {
        // Step 4: Wait for Phase-2 'screenLoopStarted' — confirms the
        // AVAssetWriter is writing real video frames (not just audio).
        await _recorder!.upgradeToScreenRecording();
        log('[REC] Phase-2 confirmed — video+audio chunks active');
        if (mounted) setState(() {});
      } else {
        log('[REC] startScreenCaptureService: returned false — recording skipped');
      }
    } on PlatformException catch (e) {
      log('[REC] startScreenCaptureService PlatformException: ${e.code} ${e.message}');
    } catch (e) {
      log('[REC] startScreenCaptureService error: $e');
    }
  }

  bool _hasVideoTrack(TrackPublication pub) => pub.track is VideoTrack;

  void _sortParticipants() {
    final userMedia = <ParticipantTrack>[];
    final screenTracks = <ParticipantTrack>[];

    for (final p in widget.room.remoteParticipants.values) {
      for (final t in p.videoTrackPublications) {
        if (isBoardVideoName(t.name)) continue; // a board's recording track: the board is drawn from vectors
        if (t.isScreenShare) {
          // Include screen shares even before the track object is loaded
          // (_PremiumScreenShareView handles the null-track loading state).
          screenTracks.add(
            ParticipantTrack(
              participant: p,
              type: ParticipantTrackType.kScreenShare,
            ),
          );
        } else if (_hasVideoTrack(t)) {
          userMedia.add(ParticipantTrack(participant: p));
        }
      }
    }

    // D21: a stable order — whoever spoke in the last 2 s stays on top in their place (no tile jumping on every
    // word), then the most recent speaker, cameras on, who joined first (live_tile_order.dart).
    final now = DateTime.now();
    final sortedMedia = _speakerOrder.order<ParticipantTrack>([
      for (final t in userMedia)
        LiveTileFacts(
          item: t,
          id: '${t.participant.identity}/${t.type.name}',
          speaking: t.participant.isSpeaking,
          lastSpokeAt: t.participant.lastSpokeAt,
          hasVideo: t.participant.hasVideo,
          joinedAt: t.participant.joinedAt,
        ),
    ], now);
    userMedia
      ..clear()
      ..addAll(sortedMedia);
    // Someone held only by the 2 s hysteresis leaves the speaking group without an event: re-sort then.
    _sortRecheck?.cancel();
    final recheck = _speakerOrder.recheckAt;
    if (recheck != null && mounted) {
      _sortRecheck = Timer(recheck.difference(now) + const Duration(milliseconds: 20), _scheduleSort);
    }
    _rememberLocalChoices();

    ParticipantTrack? localCamera;
    final localScreen = <ParticipantTrack>[];
    final localPubs = widget.room.localParticipant?.videoTrackPublications;
    if (localPubs != null) {
      for (final t in localPubs) {
        if (isBoardVideoName(t.name)) continue;
        if (t.isScreenShare) {
          // Include local screen share even before track object loads.
          localScreen.add(
            ParticipantTrack(
              participant: widget.room.localParticipant!,
              type: ParticipantTrackType.kScreenShare,
            ),
          );
        } else if (_hasVideoTrack(t)) {
          localCamera = ParticipantTrack(
            participant: widget.room.localParticipant!,
          );
        }
      }
    }

    // One share at a time: who presents now (the arbiter, the lead host's enforcement), and the share that wins
    // goes on the stage first — never a muted one left over from a takeover.
    _syncPresenters();
    final stageOrder = _share.stageOrder(_identityIsHost);
    int rank(ParticipantTrack t) {
      final i = stageOrder.indexOf(t.participant.identity);
      return i < 0 ? stageOrder.length : i;
    }
    final allScreen = [...screenTracks, ...localScreen];
    mergeSort(allScreen, compare: (a, b) => rank(a).compareTo(rank(b))); // stable: ties keep their order
    final ordered = allScreen.isNotEmpty
    ? [...allScreen, ?localCamera, ...userMedia]
        : [?localCamera, ...userMedia];

    if (mounted) {
      setState(() {
        participantTracks = ordered;
        // The video I swapped with is gone: I go back to the box (else a new arrival would land in it).
        if (_pipSwapped && !_canSwapSelf) _pipSwapped = false;
      });
    }
    _syncAurora();
    _syncAnnotRoles();
    // The strip shows the stage tracks after the first (the local camera is in the self-view box, not the strip).
    if ((localCamera == null ? ordered.length : ordered.length - 1) > 1) {
    _thumbBarAnim.forward();
    } else {
    _thumbBarAnim.reverse();
    }

    // Keep the (web) recording placeholder's participant count in sync —
    // this runs on every join/leave/track event, same as the on-screen UI.
    if (kIsWeb) {
    _recorder?.updateParticipantCount(
    widget.room.remoteParticipants.length + 1,
    );
    }
  }

  VideoTrack? _resolveScreenTrack(Participant p) {
    for (final pub in p.videoTrackPublications) {
      if (pub.isScreenShare && !isBoardVideoName(pub.name)) {
        final t = pub.track;
        if (t is VideoTrack) return t;
      }
    }
    return null;
  }


  /// What may fill the stage and the thumbnail strip: every track except the local camera, which lives in the
  /// self-view box only — for every role. (Only a teacher's own camera used to be left out, so a student or a
  /// meeting owner saw their own camera on the stage AND in the box.)
  List<ParticipantTrack> get _stageTracks {
    final local = widget.room.localParticipant;
    return participantTracks
        .where((t) => !(t.participant == local && t.type != ParticipantTrackType.kScreenShare))
        .toList();
  }

  bool get _isScreenShareMain {
    final stage = _stageTracks;
    return stage.isNotEmpty && stage.first.type == ParticipantTrackType.kScreenShare;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  // Always a notice: full-screen, LiveRoomLayer hands showAppNotice the room navigator's overlay, so it is drawn
  // above the room's own sheets and dialogs (a SnackBar in the room's Scaffold sat behind them); minimized or
  // pushed as a plain route it lands in the app's root overlay as usual.
  void _showSnack(String msg, {bool error = false}) => showAppNotice(msg, error: error);

  Future<void> _toggleParticipantPanel() async {
    if (_showParticipants) {
      _panelAnim.reverse().then((_) {
        if (mounted) setState(() => _showParticipants = false);
      });
    } else {
      setState(() => _showParticipants = true);
      _panelAnim.forward();
      await _fetchEnrolledStudents();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    LivePalette.sync(context);   // live classroom colours follow the app theme
    // Defensive: also ensured here, not just from the RoomConnectedEvent
    // handler — idempotent (no-ops once already running), and safe to call
    // during build since it only schedules a Timer, it doesn't call
    // setState() synchronously. Guards against any edge case where that
    // event fires before this State object's listeners are fully wired up.
    _startSessionClock();
    LiveRoomScope.maybeOf(context)?.bindLeave(_leaveFromMiniBox);
    final minimized = _minimized;
    final page = _buildRoomPage();
    if (minimized == null) return page;
    // In the box: nothing of the page is painted, so its decorative loops (the share view's glow, banner pulses)
    // stop until it is full-screen again (D27).
    return ValueListenableBuilder<bool>(
      valueListenable: minimized,
      builder: (_, min, child) => TickerMode(enabled: !min, child: child!),
      child: page,
    );
  }

  Widget _buildRoomPage() {
    // Full view (D-095): the back button brings the bars back first (LiveRoomHost.handleBack asks the room's
    // navigator, whose maybePop lands here), then minimizes as before.
    return PopScope(
      canPop: !_focusOn,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _focusOn) _setFocus(false);
      },
      child: Theme(
      data: ThemeData.dark(),
      child: Scaffold(
        backgroundColor: _bg,
        // RepaintBoundary around the WHOLE body (not just the video area)
        // is what makes the Android recording placeholder an actual
        // screenshot of the entire live screen — aurora background,
        // recording indicator, thumbnail strip, PiP, the main video/
        // waiting card, AND the controls bar — instead of just the video
        // stage. See _captureAndSendLiveScreen.
        body: Focus(
          focusNode: _shortcutsFocus,
          autofocus: true,
          onKeyEvent: _onRoomKey,
          child: RepaintBoundary(
          key: _liveScreenCaptureKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Aurora background (its own layer: its repaints never repaint the stage)
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _auroraAnim,
                  builder: (_, _) => CustomPaint(
                    painter: _AuroraPainter(_auroraAnim.value),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),

              // Main content (+ the hands / chat side column on wide screens)
              SafeArea(
                child: Row(
                  children: [
                    Expanded(
                child: FadeTransition(
                  opacity: _entryFade,
                  child: Column(
                    children: [
                      // The top row (D-095): one line above the stage — info, live time, countdown, network, lock,
                      // recording, full view, minimize. Hidden in full view; the clocks rebuild only it (D-092).
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: _focusOn ? const SizedBox(width: double.infinity, height: 0) : _buildTopRow(),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (ctx, constraints) => Stack(
                            fit: StackFit.expand,
                            children: [
                              // A tap anywhere on the stage shows / hides the bar (D-092: no video renderer takes
                              // the tap any more — LiveVideoView), and focuses my camera when it fills the stage.
                              GestureDetector(
                                key: const ValueKey('live_room.stage'),
                                behavior: HitTestBehavior.opaque,
                                onTapUp: (d) => _onStageTap(d.localPosition, constraints.biggest),
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.all(
                                    Radius.circular(20),
                                  ),
                                  child: _buildMainVideo(),
                                ),
                              ),

                              // Thumbnail strip
                              if (_stageTracks.length > 1 &&
                                  !_isScreenShareMain && !_isBoardMain && !_videoParked && !_focusOn)
                                FadeTransition(
                                  opacity: _thumbBarFade,
                                  child: Positioned(
                                    top: 12,
                                    left: 0,
                                    right: 0,
                                    child: SizedBox(
                                      height: 108,
                                      child: ListView.builder(
                                        // D-090: no tile is built off-screen (a built tile counts as watched and
                                        // keeps its video coming), and past the device's video budget a tile
                                        // shows the avatar (the stage is one of the budget).
                                        scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        scrollDirection: Axis.horizontal,
                                        itemCount: _stageTracks.length - 1,
                                        itemBuilder: (_, i) {
                                          final track = _stageTracks[i + 1];
                                          return _ThumbnailCard(
                                            track: track,
                                            resolveScreenTrack: _resolveScreenTrack,
                                            handUp: _hands.isUp(track.participant.identity),
                                            renderVideo: i + 1 < liveVideoBudget(MediaQuery.sizeOf(context).width),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),

                              // D-090: audio only (weak_network audio_first) — why, and Show video
                              if (_media.audioOnly)
                                PositionedDirectional(
                                  start: 12,
                                  end: 12,
                                  // A phone keeps clear of the bottom badges; a wide stage has room between them.
                                  bottom: (MediaQuery.sizeOf(context).width >= 900 ? 14 : 64) + _boardDockClearance,
                                  child: Center(
                                    child: LiveAudioOnlyCard(
                                      onShowVideo: _media.showVideo,
                                      keepsScreen: _isScreenShareMain,
                                    ),
                                  ),
                                ),

                              // iOS broadcast share banner + stop button
                              if (widget.isTeacher)
                                ValueListenableBuilder<int>(
                                  valueListenable: _clockTick,
                                  builder: (_, _, _) => _buildIOSShareBanner(),
                                ),

                              // Annotation toolbar (while drawing on the shared screen)
                              if (_annotOpen && _isScreenShareMain) _buildAnnotToolbar(),

                              // Participant count badge — in full view, the way back to the bars (D-095)
                              Positioned(
                                bottom: 14 + _boardDockClearance,
                                right: 14, // the self-view keeps clear of the bottom row (D-092)
                                child: _focusOn
                                    ? LiveFocusExitButton(
                                        onTap: () => _setFocus(false),
                                        recording: _recordsHere && _recorder?.state == RecState.recording,
                                        compact: MediaQuery.sizeOf(context).width < kLiveTopRowCompactWidth,
                                      )
                                    : GestureDetector(
                                  onTap: _toggleParticipantPanel,
                                  child: _GlassBadge(
                                    icon: Icons.people_rounded,
                                    label:
                                    '${widget.room.remoteParticipants.length + 1}',
                                    color: _showParticipants ? _cyan : null,
                                  ),
                                ),
                              ),

                              // D-094: the presenter's camera (and a few others) over a share or a board, for
                              // every viewer; under my self-view, never on it.
                              _buildPresenterCam(),

                              // My own camera (D-092): a box / circle over everything on the stage — the board, a
                              // shared screen, the annotation layer — that takes only its own touches.
                              _buildSelfView(),

                              // Live reactions (bubbles + picker)
                              LiveReactionsOverlay(
                                controller: _reactions,
                                senderName: _myReactionName,
                              ),

                              // A new chat message while the chat is closed (tap → the chat)
                              PositionedDirectional(
                                start: 12,
                                end: 12,
                                bottom: 60, // above the participant count badge
                                child: Align(
                                  alignment: AlignmentDirectional.bottomStart,
                                  child: LiveChatToastSlot(
                                    data: _chatToast,
                                    onOpen: () {
                                      _hideChatToast();
                                      _openChat();
                                    },
                                    onDismiss: _hideChatToast,
                                  ),
                                ),
                              ),

                              // Quiz overlay
                              if (_quizVisible && _activeQuiz != null)
                                _buildQuizOverlay(),
                            ],
                          ),
                        ),
                      ),

                      // Controls bar (collapses on phones after 4 s idle; tap the video to bring it back)
                      if(widget.room.localParticipant!=null)
                        SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 1),
                            end: Offset.zero,
                          ).animate(_entrySlide),
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topCenter,
                            child: _controlsVisible && !_focusOn
                                ? _buildControlsBar()
                                : const SizedBox(width: double.infinity, height: 0),
                          ),
                        ),
                    ],
                  ),
                ),
                    ),
                    if (_side != null && _wideForSidePanel)
                      Container(
                        key: const ValueKey('live_room.side_panel'),
                        width: _sidePanelWidth,
                        decoration: BoxDecoration(
                          border: BorderDirectional(start: BorderSide(color: _glassBdr)),
                        ),
                        child: _buildSidePanel(_side!),
                      ),
                  ],
                ),
              ),

              // Participant panel
              if (_showParticipants) _buildParticipantPanel(),

              // Lobby: "X wants to join" (host only; see the "Lobby" region)
              if (_lobby != null) _buildLobbyBanner(),

              // ── Ending-session overlay ───────────────────────────────────────
              // Shown while we wait for the final recording chunk to upload
              // before calling onEnd(). Prevents teacher from navigating away
              // prematurely and blocks UI interaction during the wait.
              if (_endingSession)
                Container(
                  color: LivePalette.shade(0.72),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 28,
                      ),
                      decoration: BoxDecoration(
                        color: LivePalette.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _cyan.withValues(alpha: 0.35),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _cyan.withValues(alpha: 0.12),
                            blurRadius: 32,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: _cyan,
                            strokeWidth: 2.5,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'lr_saving_recording'.tr,
                            style: TextStyle(
                              fontFamily: AppFonts.family,
                              color: LivePalette.textHigh,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ListenableBuilder(
                            listenable: _recorder ?? ChangeNotifier(),
                            builder: (_, _) {
                              final r = _recorder;
                              if (r == null) return const SizedBox.shrink();
                              final mb = (r.totalBytes / (1024 * 1024))
                                  .toStringAsFixed(1);
                              return Text(
                                trp('lr_chunk_mb', {'n': '${r.uploadedChunks}', 'mb': mb}),
                                style: TextStyle(
                                  fontFamily: AppFonts.family,
                                  color: LivePalette.ink(0.55),
                                  fontSize: 13,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        ),
      ),
      ),
    );
  }

  // ── Main video ─────────────────────────────────────────────────────────────
  //
  // Layout rules (teacher):
  //   • Main view: placeholder (if no remote) or first remote/screen-share track.
  //   • PiP corner: always the teacher's own camera feed (if camera on).
  //   • Swap: tapping PiP swaps the contents of main and PiP.
  //
  // Layout rules (student):
  //   • Main view: first participant track (teacher camera or screen share).
  //   • PiP corner: student's own camera (if enabled).
  Widget _buildMainVideo() {
    // D-090: minimized, the page draws no video (the box shows one); a board stays (vectors, no network).
    if (_videoParked && !_isBoardMain) return ColoredBox(color: _bg, child: const SizedBox.expand());
    final (video, shown) = _mainVideo();
    if (shown == null || !_hands.isUp(shown.identity)) return video;
    // The ✋ badge of whoever fills the main view (bottom-start: the thumbnail strip owns the top edge).
    return Stack(fit: StackFit.expand, children: [
      video,
      const PositionedDirectional(bottom: 14, start: 14, child: LiveHandBadge()),
    ]);
  }

  /// The main view and the participant it shows (null for the waiting placeholder).
  (Widget, Participant?) _mainVideo() {
    final local = widget.room.localParticipant;

    // D-092: my camera fills the stage when the self-view rules say so (swapped with the stage's video, or alone
    // with "fill the screen while I'm alone"); never the stage AND the box at once.
    final selfCam = _localCamTrack;
    if (selfCam != null && _selfSpot == SelfViewSpot.stage) {
      return (LiveVideoView(selfCam, key: const ValueKey('live_room.self_stage'), fit: VideoViewFit.cover), local);
    }

    // A presented whiteboard fills the stage (D-087), unless a screen share wins the one-share rule.
    if (_isBoardMain) {
      final presenter = _board.presenter!;
      return (_buildBoardStage(), presenter == _myIdentity ? local : _remoteBy(presenter));
    }

    // The local camera never fills the stage while someone else (or a share) can: it is in the self-view box.
    final mainTracks = _stageTracks;

    if (mainTracks.isEmpty) {
      // Mirror the recording's fallback order (see recorder_compositor.js's
      // draw loop): screen share > full-screen camera > placeholder. Before
      // this, an enabled camera never appeared here at all — only in the
      // small PiP corner — so the placeholder showed even while the
      // teacher's own camera was live. Now, with no screen share and no
      // other participant showing video, an enabled camera fills the main
      // view instead; the placeholder is reserved for when nothing at all
      // is available, same as the recorded output.
      final isMicOn = LiveMicGate.instance.micOn(local);
      final isCamOn = local?.isCameraEnabled() ?? false;

      // Premium placeholder — shown only when there's truly nothing to
      // display: no screen share, no other participant's video, and no
      // (or not-yet-ready) local camera.
      final teacherName = local?.name ?? local?.identity ?? 'Teacher';
      return (
        _PremiumWaitingPlaceholder(
          teacherName: teacherName,
          isMicOn: isMicOn,
          isCamOn: isCamOn,
          auroraAnim: _auroraAnim,
          room: widget.room,
          sessionTitle: widget.sessionName,
          enrolledStudents: _enrolledStudents,
          // D-095: no app logo in the room. The recording placeholder IS a
          // screenshot of this live screen (_captureLiveScreenPng), so the
          // recording has no logo either: true parity, nothing is drawn
          // for the recording only.
          showLogo: false,
          // The top row carries LIVE + the time now (D-095): no second live chip on the card.
          live: false,
        ),
        null,
      );
    }

    final main = mainTracks.first;
    if (main.type == ParticipantTrackType.kScreenShare) {
      return (
        _PremiumScreenShareView(
          participant: main.participant,
          resolveScreenTrack: _resolveScreenTrack,
          auroraAnim: _auroraAnim,
          annot: _annotEnabled ? _annot : null,
          // A host stops a participant's share from the stage (one share at a time).
          onStopShare: _canStopShareOf(main.participant)
              ? () => unawaited(_stopPresenter(main.participant.identity, notify: true))
              : null,
          stopBusy: _stopping.contains(main.participant.identity),
        ),
        main.participant,
      );
    }
    return (ParticipantWidget.widgetFor(main, showStatsLayer: false), main.participant);
  }

  // ── Self-view (D-092) ──────────────────────────────────────────────────────
  //
  // My own camera, in every state of the room while it is on: a box or circle I drag anywhere (it snaps to the
  // nearer edge or a corner), over the waiting card, someone's video, a shared screen (mine too), the whiteboard or
  // the annotation layer. Tap → swap with the stage's video (when there is one); long-press or ⋮ → options (shape,
  // size, fill the screen while alone, hide). Never on the stage AND in the box: the "camera twice" fix holds.

  /// What the box keeps clear of: the thumbnail strip, the annotation toolbar, the board's bar and dock, the
  /// share's bottom bar and the bottom badge row (the top badges left the stage for the top row, D-095).
  SelfViewKeepOut get _selfKeepOut {
    final strip = _stageTracks.length > 1 && !_isScreenShareMain && !_isBoardMain && !_videoParked;
    var top = 12.0;
    if (strip) top = 132;
    if (_annotOpen && _isScreenShareMain) top = math.max(top, 76);
    if (_isBoardMain) top = math.max(top, 64);
    var bottom = 58.0 + _boardDockClearance;
    if (_isScreenShareMain) bottom = math.max(bottom, 84);
    if (_focusOn) bottom = math.max(bottom, 72); // full view: clear of the exit button (D-095)
    return SelfViewKeepOut(base: EdgeInsets.fromLTRB(12, top, 12, bottom));
  }

  void _onStageTap(Offset at, Size stage) {
    // Full view (D-095): a tap on the stage brings the bars back.
    if (_focusOn) {
      _setFocus(false);
      return;
    }
    _toggleControlsVisibility();
    // Tap to focus where it works (a local camera on a phone; guarded, never an exception per tap).
    if (_selfSpot == SelfViewSpot.stage) unawaited(LiveCameraFocus.tap(_localCamTrack, at, stage));
  }

  void _selfMoved(SelfViewSide side, double y) {
    unawaited(SelfViewStore.instance.update(_selfPrefs.copyWith(side: side, y: y)));
  }

  Widget _buildSelfView() {
    final spot = _selfSpot;
    final local = widget.room.localParticipant;
    final cam = _localCamTrack;
    if (spot == SelfViewSpot.none || local == null || cam == null) return const SizedBox.shrink();
    final prefs = _selfPrefs;
    if (spot == SelfViewSpot.stage) {
      if (_pipSwapped && _canSwapSelf) {
        // Swapped: the stage's video in the box; a tap puts it back.
        return Positioned.fill(
          child: SelfViewLayer(
            key: const ValueKey('live_room.self_view'),
            prefs: prefs,
            keepOut: _selfKeepOut,
            onMoved: _selfMoved,
            onTap: () => setState(() => _pipSwapped = false),
            onLongPress: _openSelfViewOptions,
            tile: ClipRRect(
              borderRadius: BorderRadius.circular(prefs.shape == SelfViewShape.circle ? 999 : 16),
              child: AbsorbPointer(child: ParticipantWidget.widgetFor(_stageTracks.first, showStatsLayer: false)),
            ),
          ),
        );
      }
      // Alone on the stage: one chip, with the bar, brings the box back.
      if (!_controlsVisible) return const SizedBox.shrink();
      return Positioned(
        top: 12,
        left: 12,
        child: SelfViewChip(
          key: const ValueKey('live_room.self_view.to_box'),
          icon: Icons.picture_in_picture_alt_rounded,
          label: 'lr_self_view_to_box'.tr,
          onTap: () {
            setState(() => _pipSwapped = false);
            unawaited(SelfViewStore.instance.update(prefs.copyWith(aloneOnStage: false)));
            _pokeControls();
          },
        ),
      );
    }
    return Positioned.fill(
      child: SelfViewLayer(
        key: const ValueKey('live_room.self_view'),
        prefs: prefs,
        keepOut: _selfKeepOut,
        hidden: spot == SelfViewSpot.hiddenChip,
        onShow: () {
          setState(() => _selfHidden = false);
          _pokeControls();
        },
        onMoved: _selfMoved,
        onTap: _canSwapSelf ? () => setState(() => _pipSwapped = true) : _toggleControlsVisibility,
        onLongPress: _openSelfViewOptions,
        tile: SelfViewTile(
          shape: prefs.shape,
          name: _myReactionName,
          video: LiveVideoView(cam, key: const ValueKey('live_room.self_video'), fit: VideoViewFit.cover),
          micOn: LiveMicGate.instance.micOn(local),
          speaking: local.isSpeaking,
          handUp: _hands.localUp,
          showChrome: _controlsVisible,
          onMenu: _openSelfViewOptions,
        ),
      ),
    );
  }

  Future<void> _openSelfViewOptions() async {
    _pokeControls();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) => Directionality(
        textDirection: dir,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: DecoratedBox(
              decoration: BoxDecoration(color: _surfaceHi, border: Border(top: BorderSide(color: _glassBdr))),
              child: SafeArea(
                top: false,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 42,
                    height: 5,
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    decoration: BoxDecoration(color: _glassBdr, borderRadius: BorderRadius.circular(3)),
                  ),
                  Flexible(
                    child: ValueListenableBuilder<SelfViewPrefs>(
                      valueListenable: SelfViewStore.instance,
                      builder: (_, p, _) => SelfViewOptions(
                        key: const ValueKey('live_room.self_view.options'),
                        prefs: p,
                        onChanged: (next) => unawaited(SelfViewStore.instance.update(next)),
                        onToStage: _canSwapSelf
                            ? () {
                                Navigator.of(ctx).pop();
                                if (mounted) setState(() => _pipSwapped = true);
                              }
                            : null,
                        onHide: () {
                          Navigator.of(ctx).pop();
                          if (mounted) setState(() => _selfHidden = true);
                        },
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── The presenter's camera over a share (D-094) ────────────────────────────────────────────────
  //
  // While a screen share or the whiteboard fills the stage the thumbnail strip is off, so a viewer used to see the
  // content only — and adaptive stream paused the presenter's camera that nobody drew (the presenter saw both: their
  // own self-view). Every viewer now gets the presenter's camera in a floating box (the self-view's look; drag, snap,
  // shape / size, minimize to a name) and up to a few other cameras as bubbles next to it, inside liveVideoBudget.
  // Drawing them is what makes them stream again. The presenter sees nothing new. Rules: live_presenter_cam.dart;
  // widget: widgets/presenter_cam_box.dart.

  /// A camera the viewer tapped into the box, and for whose share (a new share starts on its presenter again).
  String? _camPinned;
  String? _camPinnedFor;

  /// "Minimize to a name" — per room, like "Hide self view".
  bool _camCollapsed = false;

  PresenterCamPrefs get _camPrefs => PresenterCamStore.instance.value;

  /// Whoever fills the stage with a share or a board (null: neither is on the stage).
  String? get _stagePresenter {
    if (_isBoardMain) return _board.presenter;
    if (_isScreenShareMain) return _stageTracks.first.participant.identity;
    return null;
  }

  /// A participant's camera when it can be drawn: published, not muted and received (an audio-only room has none);
  /// never a share, never the board's recording track.
  VideoTrack? _cameraTrackOf(Participant p) {
    for (final pub in p.videoTrackPublications) {
      if (pub.isScreenShare || isBoardVideoName(pub.name) || pub.muted) continue;
      final t = pub.track;
      if (t is VideoTrack) return t;
    }
    return null;
  }

  PresenterCamPlan get _camPlan {
    final presenter = _stagePresenter;
    if (presenter == null) return PresenterCamPlan.none;
    final cams = <LiveCamFacts>[];
    for (final id in [
      presenter,
      for (final t in _stageTracks)
        if (t.type != ParticipantTrackType.kScreenShare) t.participant.identity,
    ]) {
      final p = _remoteBy(id);
      cams.add(LiveCamFacts(id, camOn: p != null && _cameraTrackOf(p) != null));
    }
    return presenterCamPlan(
      presenter: presenter,
      me: _myIdentity,
      cams: cams,
      pinned: _camPinnedFor == presenter ? _camPinned : null,
      // Minimized without video, or my camera swapped onto the stage (the share is then in my box).
      suppressed: _videoParked || _selfSpot == SelfViewSpot.stage,
      budget: liveVideoBudget(MediaQuery.sizeOf(context).width),
    );
  }

  /// The presenter's camera (or its pill) is on the stage — for a mode that hides the bars and keeps the box.
  bool get presenterCamShown => _camPlan.any;

  Widget _buildPresenterCam() {
    final plan = _camPlan;
    if (!plan.any) return const SizedBox.shrink();
    PresenterCamItem? item(String id) {
      final p = _remoteBy(id);
      if (p == null) return null;
      final cam = _cameraTrackOf(p);
      return PresenterCamItem(
        id: id,
        name: _nameOf(id),
        video: cam == null ? null : LiveVideoView(cam, key: ValueKey('live_room.presenter_cam.$id'), fit: VideoViewFit.cover),
        imageUrl: participantPhotoFromMetadata(p.metadata),
        micOn: p.isMicrophoneEnabled(),
        speaking: p.isSpeaking,
        handUp: _hands.isUp(id),
      );
    }

    final presenter = _stagePresenter;
    final selfPrefs = _selfPrefs;
    final keep = _selfKeepOut;
    final Rect? Function(Size)? avoid = switch (_selfSpot) {
      SelfViewSpot.box => (stage) => selfViewRect(stage: stage, prefs: selfPrefs, keepOut: keep),
      SelfViewSpot.hiddenChip => (stage) => selfViewChipRect(stage: stage, prefs: selfPrefs, keepOut: keep),
      _ => null,
    };
    return Positioned.fill(
      child: PresenterCamLayer(
        key: const ValueKey('live_room.presenter_cam'),
        prefs: _camPrefs,
        keepOut: keep,
        selfSide: selfPrefs.side,
        main: plan.main == null ? null : item(plan.main!),
        bubbles: [for (final id in plan.bubbles) ?item(id)],
        more: plan.more,
        avoid: avoid,
        collapsed: _camCollapsed,
        showChrome: _controlsVisible,
        onTap: _toggleControlsVisibility,
        onMenu: () => unawaited(_openPresenterCamOptions()),
        onCollapse: () => setState(() => _camCollapsed = true),
        onExpand: () {
          setState(() => _camCollapsed = false);
          _pokeControls();
        },
        onPin: (id) => setState(() {
          _camPinned = id;
          _camPinnedFor = presenter;
        }),
        onMore: () => unawaited(_toggleParticipantPanel()),
        onMoved: (side, y) => unawaited(PresenterCamStore.instance.update(_camPrefs.copyWith(side: side, y: y))),
      ),
    );
  }

  Future<void> _openPresenterCamOptions() async {
    _pokeControls();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) => Directionality(
        textDirection: dir,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: DecoratedBox(
              decoration: BoxDecoration(color: _surfaceHi, border: Border(top: BorderSide(color: _glassBdr))),
              child: SafeArea(
                top: false,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 42,
                    height: 5,
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    decoration: BoxDecoration(color: _glassBdr, borderRadius: BorderRadius.circular(3)),
                  ),
                  Flexible(
                    child: ValueListenableBuilder<PresenterCamPrefs>(
                      valueListenable: PresenterCamStore.instance,
                      builder: (_, p, _) => SelfViewOptions(
                        key: const ValueKey('live_room.presenter_cam.options'),
                        prefs: p.asSelfViewPrefs,
                        showAloneSwitch: false,
                        showCircleTip: false,
                        icon: Icons.co_present_rounded,
                        title: 'lr_presenter_cam'.tr,
                        hint: 'lr_presenter_cam_hint'.tr,
                        hideIcon: Icons.close_fullscreen_rounded,
                        hideTitle: 'lr_presenter_cam_collapse'.tr,
                        hideSubtitle: 'lr_presenter_cam_collapse_sub'.tr,
                        onChanged: (next) =>
                            unawaited(PresenterCamStore.instance.update(p.copyWith(shape: next.shape, size: next.size))),
                        onHide: () {
                          Navigator.of(ctx).pop();
                          if (mounted) setState(() => _camCollapsed = true);
                        },
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── iOS Share Active Banner ──────────────────────────────────────────────────
  // Shown only on iOS when teacher has started a broadcast (opened another app).
  // Floats at the top of the screen so it's visible after switching to any app.
  Widget _buildIOSShareBanner() {
    if (!_isBroadcastingIOS) return const SizedBox.shrink();
    return Positioned(
      top: 12,
      left: 24,
      right: 24,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: LivePalette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _cyan.withValues(alpha: 0.5),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: _cyan.withValues(alpha: 0.18),
                blurRadius: 20,
              ),
            ],
          ),
          child: Row(
            children: [
              // Pulsing dot
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.3, end: 1.0),
                duration: const Duration(milliseconds: 800),
                onEnd: () { if (mounted) setState(() {}); },
                builder: (_, v, _) => Opacity(
                  opacity: v,
                  child: Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: _cyan,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.screen_share_rounded, color: _cyan, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'lr_sharing_screen'.tr,
                  style: TextStyle(
                    fontFamily: AppFonts.family,
                    color: LivePalette.textHigh,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              // Elapsed recording time shown here too
              if (_recElapsedSeconds > 0)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10),
                  child: Text(
                    _recElapsedLabel,
                    style: TextStyle(
                      fontFamily: AppFonts.family,
                      color: _cyan,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              // Stop button
              GestureDetector(
                onTap: _stopIOSBroadcast,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _rose.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _rose.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    'lr_stop_sharing'.tr,
                    style: TextStyle(
                      fontFamily: AppFonts.family,
                      color: _rose,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top row (D-095, widgets/live_top_row.dart) ───────────────────────────
  //
  // One line above the stage: (i) · LIVE + how long the room has been live (`live_started_at`) · the free-time
  // countdown · the weak-network pill · Room locked · the recording control (Record / REC time → Pause · Resume ·
  // Stop) · Full view · Minimize. The clocks and the recorder rebuild only this (D-092).
  Widget _buildTopRow() => Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        child: ListenableBuilder(
          listenable: Listenable.merge([_clockTick, ?_recorder]),
          builder: (_, _) => _topRow(),
        ),
      );

  LiveTopRow _topRow() {
    final scope = LiveRoomScope.maybeOf(context);
    final now = DateTime.now();
    final own = Duration(seconds: _sessionElapsedSeconds);

    // Recording: this device's recorder (a course's teacher, a meeting creator who pressed Record) wins; then the
    // creator's Record; then the server's recording (everyone, no controls — D-090 server mode included).
    final rec = _recorder;
    final st = _recordsHere ? rec?.state : null;
    // The gate the bar's Pause / Resume had: a teacher follows the course's record switch (and the device recorder
    // mode), anyone else only while this device records.
    final controls = st != null &&
        showsRecorderControls(
          isTeacher: widget.isTeacher,
          recordingEnabled: widget.recordingEnabled && widget.liveConfig.deviceRecorder,
          recordsHere: _recordsHere,
        );
    final meetingRec = _canRecordMeeting && _meetingRecording != null;
    final phase = liveRecPhase(
      state: st,
      pending: meetingRec,
      offer: _canRecordMeeting && _meetingRecording == null && !_endingSession,
      server: _serverRecording,
    );
    final detail = rec != null && st != null && st != RecState.idle
        ? trp('lr_chunk_mb', {'n': '${rec.uploadedChunks}', 'mb': (rec.totalBytes / (1024 * 1024)).toStringAsFixed(1)})
        : null;

    final limit = _timeLimit;
    return LiveTopRow(
      onInfo: _endingSession ? null : _openInfo,
      liveFor: _sessionClockTimer == null ? null : (meetingLiveFor(widget.liveStartedAt, now.toUtc(), own: own) ?? own),
      limit: limit != null && limit.showPill(now)
          ? LiveTopLimit(
              remaining: limit.remaining(now),
              tone: limit.tone(now),
              showUpgrade: limit.showUpgrade(now),
              busy: _planBusy,
              onUpgrade: _upgradePlan,
            )
          : null,
      netLowered: _media.lowered && !_media.audioOnly,
      netRecovering: _media.tier == LiveVideoTier.medium,
      // Room locked (hosts; live.room_lock) — the participants panel holds the switch.
      locked: _controls?.locked == true && !AppConfig.disableList.contains(kLiveRoomLockFeatureKey),
      onLocked: _showParticipants ? null : _toggleParticipantPanel,
      recording: LiveTopRecording(
        phase: phase,
        elapsed: Duration(seconds: _recElapsedSeconds),
        detail: detail,
        busy: _meetingRecordBusy || _isPausingRecording || _isResumingRecording,
        onRecord: _recordMeeting,
        onPause: controls && st == RecState.recording && !_isPausingRecording && !_endingSession
            ? () => unawaited(_pauseRecording())
            : null,
        onResume: controls && st == RecState.paused && !_isResumingRecording && !_endingSession
            ? () => unawaited(_resumeRecording())
            : null,
        onStop: meetingRec && !_endingSession && !_meetingRecordBusy ? () => unawaited(_stopMeetingRecording()) : null,
      ),
      onFocus: _canFocus && !_endingSession ? () => _setFocus(true) : null,
      onMinimize: scope == null || _endingSession ? null : scope.minimize,
      pulse: _recDotOpacity,
    );
  }

  // ── Full view (D-095) ─────────────────────────────────────────────────────
  // The top row, the bottom bar and the thumbnail strip step aside so what fills the stage (a shared screen, the
  // whiteboard, a camera) uses the whole screen. The way back: the floating exit button (where the participant
  // count sits), a tap on the stage, Esc, the back button. The annotation / board toolbars live on the stage and
  // stay; so does the self-view box.
  bool _focus = false;

  /// Something fills the stage (not the waiting card, not a parked minimized page).
  bool get _canFocus =>
      !_videoParked &&
      (_isScreenShareMain || _isBoardMain || _stageTracks.isNotEmpty || _selfSpot == SelfViewSpot.stage);

  /// Full view is on — and drops by itself when the stage goes back to the waiting card.
  bool get _focusOn => _focus && _canFocus;

  void _setFocus(bool on) {
    if (on == _focus || !mounted) return;
    setState(() => _focus = on);
    if (!on) _pokeControls();
  }

  // ── Controls bar ──────────────────────────────────────────────────────────
  Widget _buildControlsBar() {
    // The bar paints its own glass shell (mobile pill / wide grouped bar) — see LiveControlBar.
    return ListenableBuilder(
        listenable: Listenable.merge([_reactions, _hands, _chat, _annot, _share, _attention, ?_lobby]),
        builder: (_, _) => ControlsWidget(
        widget.room,
        widget.room.localParticipant!,
        key: _controlsKey,
        // Lobby (host only): the waiting count on the bar's lobby button; what is new adds to the "More" badge.
        waitingCount: _lobby?.waitingCount ?? 0,
        lobbyAttention: _attention.count(LiveAttentionKind.lobby),
        handsAttention: _attention.count(LiveAttentionKind.hands),
        // One share at a time: Share / Stop / Ask to share / Waiting… — the tap goes through _onShareTap.
        shareButton: _shareButtonMode,
        onLobby: _lobby == null ? null : _openLobby,
        // Recording (Record / Pause / Resume / Stop) is in the top row, not on the bar (D-095).
        onInteraction: _pokeControls,
        // End session goes through our recorder-aware wrapper
        onEndSession: _endSessionWithRecording,
        isTeacher: widget.isTeacher,
        isHost: widget.host,
        // D29: what the server allows right now (a guest allowed to speak, a student allowed to share)
        canPublish: _allowed.any,
        allowMic: _allowed.mic,
        allowCamera: _allowed.camera,
        allowShare: _allowed.share,
        onToggleScreenShare: _onShareTap,
        onToggleReactions: _reactions.togglePicker,
        reactionsOpen: _reactions.pickerOpen,
        // Hands: students and guests raise; the teacher gets the queue chip.
        onToggleHand: widget.isTeacher ? null : () => _hands.toggleLocal(name: _myReactionName),
        handUp: _hands.localUp,
        onOpenHands: widget.isTeacher ? _openHands : null,
        handsCount: _hands.count,
        handsOpen: _side == _SidePanel.hands,
        // Chat: everyone (data only, so guests too).
        onOpenChat: _openChat,
        chatUnread: _chat.unread,
        chatOpen: _side == _SidePanel.chat || _chat.isOpen,
        // Annotation (D-079): hosts, the presenter, students a host allowed; only while a share fills the stage.
        onAnnotate: _canAnnotate || _annotOpen ? _toggleAnnot : null,
        annotating: _annotOpen,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Lobby — live rooms: share links + admission (docs/backend/live-rooms-spec.md §4)
  //
  // Host only (RoomPage.host) and never while `live.lobby` is switched off. The controller polls
  // GET /api/v1/live/{kind}/{id}/lobby every 15 s (4 s while the lobby sheet is open, nothing in the
  // background), refreshes at once on the silent push `live_join_request` (LiveLobbyEvents) and on
  // resume, and plays a short sound on a new request; the bar's lobby
  // button carries the waiting count and opens LobbySheet; a new request also shows LobbyBanner
  // (Admit / Reject inline) at the top of the room. Everything else lives in
  // lib/features/shared/live/ — keep this region the only lobby code in this file.
  // ═══════════════════════════════════════════════════════════════════════════
  LiveLobbyController? _lobby;

  void _startLobby() {
    if (!widget.host || AppConfig.disableList.contains(kLiveLobbyFeatureKey)) return;
    _lobby = LiveLobbyController(widget.ref)
      ..addListener(_syncAttention)
      ..start();
  }

  Future<void> _openLobby() async {
    final c = _lobby;
    if (c == null) return;
    _pokeControls();
    _attention.setWatching(LiveAttentionKind.lobby, true); // the requests are seen while the sheet is open
    try {
      await showLobbySheet(context, widget.ref, controller: c, title: widget.sessionName);
    } finally {
      if (mounted) _attention.setWatching(LiveAttentionKind.lobby, false);
    }
  }

  Widget _buildLobbyBanner() {
    final c = _lobby!;
    return ListenableBuilder(
      listenable: c,
      builder: (_, _) {
        final r = c.latestNew;
        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, anim) => SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: r == null
                  ? const SizedBox.shrink()
                  : Padding(
                      key: ValueKey('lobby.banner.${r.id}'),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Center(
                        child: LobbyBanner(
                          request: r,
                          othersWaiting: (c.waitingCount - 1).clamp(0, 999),
                          busy: c.busy.contains(r.id) || c.busy.contains('*'),
                          onAdmit: () => c.admit(r.id),
                          onReject: () => c.reject(r.id),
                          onOpen: _openLobby,
                          onDismiss: c.dismissBanner,
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
  // ═══════════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════════════
  // Annotation over the shared screen (D-079, feature key `live.annotation`) — docs/live/annotation_wiring.md
  //
  // Peer to peer over the room's data channel (topics `annot` / `annot.laser`, no server route). Hosts (`teacher_*`,
  // plus this device when it hosts a meeting) and the person whose share is on the stage draw; students only when a
  // host allows it (everyone, or one by one from the participants panel). Late joiners get the board from the
  // responder (the presenter, else the first host). On an Android whole-screen share the overlay of
  // RoomScreenShareMixin burns the strokes into the video instead (burned-in mode: nothing travels as vectors).
  // Keep this region the only annotation code in this file (plus the layer in _PremiumScreenShareView).
  // ═══════════════════════════════════════════════════════════════════════════
  static const _kAnnotFeatureKey = 'live.annotation';

  late final AnnotationController _annot = AnnotationController(
    localIdentity: _myIdentity,
    send: (topic, bytes, reliable, {to}) async {
      final lp = widget.room.localParticipant;
      if (lp == null) return;
      await lp.publishData(bytes, reliable: reliable, topic: topic, destinationIdentities: to);
    },
    nameOf: _presenceNameOf, // D-093: the name tags
  );

  /// The name on a drawer's tag (D-093): the participant's LiveKit display name — a guest's is the name they typed —
  /// never an identity; nobody known by name → "Participant" / "Guest".
  String _presenceNameOf(String identity) {
    final p = _remoteBy(identity);
    final name = p?.name.trim() ?? '';
    if (name.isNotEmpty) return name;
    return isGuestIdentity(identity) ? t('ضيف', 'Guest') : t('مشارك', 'Participant');
  }

  /// The in-app toolbar is shown (and the layer takes the pointer).
  bool _annotOpen = false;
  bool _annotColorSet = false;

  /// A host's permission lets this (non-host) person draw — the students' notices follow it.
  bool _annotGranted = false;

  /// Whose share was on the stage at the last re-layout (null: none).
  String? _annotPresenter;

  bool get _annotEnabled => !AppConfig.disableList.contains(_kAnnotFeatureKey);

  bool get _annotStudentGranted =>
      !_annot.isHost && (_annot.allowStudents || _annot.allowedIdentities.contains(_annot.localIdentity));

  /// Annotate is offered: a share fills the stage, this person may draw, and no Android overlay burns it in.
  bool get _canAnnotate =>
      _annotEnabled && _isScreenShareMain && !_isBoardMain && _annot.canDrawLocal && !_annot.burnedIn;

  /// Hosts present and the presenter on the stage → the controller (a no-op when nothing changed). Runs after
  /// every re-layout (_sortParticipants: connect / disconnect / track (un)publish / local track events).
  void _syncAnnotRoles() {
    final local = widget.room.localParticipant;
    final hosts = <String>{
      for (final p in widget.room.remoteParticipants.values)
        if (isHostIdentity(p.identity)) p.identity,
      if (local != null && local.identity.isNotEmpty && (isHostIdentity(local.identity) || widget.host))
        local.identity,
    };
    final presenter = _isScreenShareMain ? _stageTracks.first.participant.identity : null;
    final before = _annotPresenter;
    _annotPresenter = presenter;
    if (before != presenter) {
      // The drawings belonged to that content: a host clears them when the share ends or changes hands.
      if (before != null && _annot.isHost) _annot.clearAll();
      if (_annotOpen) {
        _annot.setDrawMode(false);
        if (mounted) setState(() => _annotOpen = false);
      }
    }
    _annot.setRoles(hosts: hosts, presenter: presenter);
  }

  void _onAnnotChanged() {
    if (!mounted) return;
    _board.permissionsChanged(); // the whiteboard shares the drawing permission (D-087)
    final granted = _annotStudentGranted;
    if (granted != _annotGranted) {
      _annotGranted = granted;
      if (_annotEnabled) {
        _showSnack(granted
            ? (_isBoardMain
                ? t('يمكنك الآن الكتابة والرسم على السبورة', 'You can now write and draw on the whiteboard')
                : t('يمكنك الآن الرسم على الشاشة المشتركة', 'You can now draw on the shared screen'))
            : t('أوقف المعلّم الرسم للطلاب', 'The teacher turned drawing off'));
      }
    }
    // Drawing taken away (permission, burned-in mode, the share ended): the toolbar closes.
    if (_annotOpen && !_canAnnotate) setState(() => _annotOpen = false);
  }

  /// The Android whole-screen overlay is shown / closed (RoomScreenShareMixin, room_wiring_pending.md §4).
  void _onAnnotOverlay() {
    if (!mounted) return;
    final on = annotationOverlayActive.value;
    // _syncAnnotRoles has made the local presenter a lead by now (LocalTrackPublishedEvent re-sorts).
    _annot.setBurnedIn(on);
    if (on && _annotOpen) {
      _annot.setDrawMode(false);
      setState(() => _annotOpen = false); // the native toolbar replaces the in-app one
    }
  }

  void _toggleAnnot() {
    if (_annotOpen) {
      _closeAnnot();
      return;
    }
    if (!_canAnnotate) return;
    _annot.setDrawMode(true);
    setState(() => _annotOpen = true);
    _pokeControls();
  }

  void _closeAnnot() {
    _annot.setDrawMode(false);
    if (mounted) setState(() => _annotOpen = false);
  }

  /// The participants panel's "Allow / Revoke drawing" (LiveHostControlsController.onDrawingChanged): the
  /// permission packet; the controller has already switched `can_publish_data` on when it was off.
  Future<void> _setDrawingFor(String identity, bool allow) async {
    final ids = Set.of(_annot.allowedIdentities);
    if (allow) {
      ids.add(identity);
    } else {
      ids.remove(identity);
    }
    _annot.setAllowedIdentities(ids);
  }

  bool _drawingAllowedFor(String identity) =>
      _annot.allowStudents || _annot.allowedIdentities.contains(identity);

  Widget _buildAnnotToolbar() => PositionedDirectional(
        top: 12,
        start: 12,
        end: 12,
        child: Center(
          child: AnnotationControllerToolbar(
            key: const ValueKey('live_room.annotation_toolbar'),
            controller: _annot,
            onClose: _closeAnnot,
          ),
        ),
      );
  // ═══════════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════════════
  // Whiteboard (D-087, feature key `live.whiteboard`) — lib/features/teacher/sessions/live/whiteboard/
  //
  // The Share sheet's "Whiteboard" tab presents a board instead of a screen: vector ink, shapes, text boxes and
  // pages on the data channel (topics `board` / `board.laser`, no track, no server route). It counts as presenting
  // for the one-share rule (the arbiter's presenters include the board's presenter; a host's takeover, a hand-over
  // or the lead host's enforcement stops it like a screen share) and fills everyone's stage while presented. Who may
  // present: a host, or someone the server lets share their screen (the same "Ask to share" path). Who may draw:
  // the presenter and hosts, students when the host allows drawing (the annotation permission). Late joiners get the
  // board from the presenter. Keep this region the only whiteboard code in this file.
  // ═══════════════════════════════════════════════════════════════════════════
  static const _kBoardFeatureKey = 'live.whiteboard';

  late final BoardController _board = BoardController(
    localIdentity: _myIdentity,
    send: (topic, bytes, reliable, {to}) async {
      final lp = widget.room.localParticipant;
      if (lp == null) return;
      await lp.publishData(bytes, reliable: reliable, topic: topic, destinationIdentities: to);
    },
    isHost: _identityIsHost,
    mayPresent: _mayPresentBoard,
    studentMayDraw: _drawingAllowedFor,
    // D-093: name tags (shown for everyone once students may draw) and the host's "Show who drew what".
    nameOf: _presenceNameOf,
    othersMayDraw: () => _annot.allowStudents || _annot.allowedIdentities.isNotEmpty,
    showAuthors: () => _annot.showAuthors,
  );
  final GlobalKey _boardPageKey = GlobalKey(debugLabel: 'live_room.board_page');
  String? _boardPresenterSeen;

  bool get _boardEnabled => !AppConfig.disableList.contains(_kBoardFeatureKey);

  /// The board fills the stage: one is presented and no screen share wins over it (the arbiter's stage order).
  bool get _isBoardMain {
    if (!_boardEnabled || !_board.active) return false;
    if (!_isScreenShareMain) return true;
    final order = _share.stageOrder(_identityIsHost);
    return order.isNotEmpty && order.first == _board.presenter;
  }

  /// Room for the tool dock under the page (the PiP and the participant badge sit above it).
  double get _boardDockClearance {
    if (!_isBoardMain || !_board.canDrawLocal) return 0;
    return MediaQuery.sizeOf(context).width >= 980 ? 70 : 118;
  }

  bool _mayPresentBoard(String identity) {
    if (identity.isEmpty) return false;
    if (identity == _myIdentity) return _isShareHost || _allowed.share;
    if (_identityIsHost(identity)) return true;
    final rp = _remoteBy(identity);
    return rp != null && _controlTarget(rp).permissions.mayShareScreen;
  }

  /// The Share sheet's Whiteboard: this device's own screen share stops first (one share), then the board goes up.
  Future<void> _startBoard(BoardBackground background, {BoardFormat format = BoardFormat.landscape}) async {
    if (!_boardEnabled || !mounted) return;
    final me = _myIdentity;
    if (me.isEmpty) return;
    if (screenShareActive) await stopScreenShare();
    if (!mounted) return;
    _board.localIdentity = me;
    _board.setTool(BoardTool.pen);
    _board.setDrawMode(true);
    _board.startPresenting(background: background, format: format);
    LiveRoomScope.maybeOf(context)?.expand();
    _scheduleSort(); // → the arbiter: a host takes over, an approved presenter's grant is used
    _pokeControls();
  }

  void _stopBoard() {
    if (!_board.isLocalPresenting) return;
    _board.stopPresenting();
    _syncBoardVideo();
    _scheduleSort();
    if (mounted) setState(() {});
  }

  /// Whatever this device presents stops (the one-share rule, a host's stop, a hand-over).
  Future<void> _stopAnyLocalShare() async {
    _stopBoard();
    await _boardVideo.stop(); // the board's recording track first: it is not a screen share to stop
    if (screenShareActive) await stopScreenShare();
  }

  /// On joining and after a reconnect: ask for the board; a presenter who was away sends theirs to everyone again.
  void _requestBoard({bool reconnected = false}) {
    _board.localIdentity = _myIdentity;
    if (reconnected && _board.isLocalPresenting) {
      _board.sendSnapshot();
      return;
    }
    _board.requestSnapshot();
  }

  void _onBoardChanged() {
    if (!mounted) return;
    _boardVideo.markDirty();
    _syncBoardVideo();
    final presenter = _board.presenter;
    if (presenter != _boardPresenterSeen) {
      final before = _boardPresenterSeen;
      _boardPresenterSeen = presenter;
      if (presenter != null && presenter != _myIdentity && before == null && _boardEnabled) {
        showAppNotice(t('يعرض ${_nameOf(presenter)} سبورة بيضاء', '${_nameOf(presenter)} is presenting a whiteboard'),
            icon: Icons.draw_rounded);
      }
      _scheduleSort(); // the stage changes; the arbiter sees the board's presenter
    }
    _maybeRefreshWebPlaceholder(); // the web recording's still of the room follows the board
  }

  Future<void> _openBoardOptions() => showWhiteboardOptionsSheet(
        context,
        controller: _board,
        pageKey: _boardPageKey,
        isHost: _annot.isHost,
        allowStudents: () => _annot.allowStudents,
        onAllowStudents: _annot.isHost ? _annot.setAllowStudents : null,
        showAuthors: () => _annot.showAuthors, // D-093
        onShowAuthors: _annot.isHost ? _annot.setShowAuthors : null,
        listenable: _annot,
        fileStem: (widget.sessionName ?? '').trim().isEmpty ? 'whiteboard' : widget.sessionName!.trim(),
      );

  Widget _buildBoardStage() {
    final presenter = _board.presenter ?? '';
    final mine = _board.isLocalPresenting;
    return WhiteboardRoomView(
      key: const ValueKey('live_room.whiteboard'),
      controller: _board,
      presenterName: _nameOf(presenter),
      fallbackRtl: AppConfig.lang == 'ar',
      pageKey: _boardPageKey,
      onOptions: mine ? () => unawaited(_openBoardOptions()) : null,
      // The presenter stops it; a host stops a participant's board (one share at a time).
      onStop: mine
          ? _stopBoard
          : (_isShareHost && presenter.isNotEmpty && !_identityIsHost(presenter)
              ? () => unawaited(_stopPresenter(presenter, notify: true))
              : null),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Host controls (live.teacher_controls / live.room_lock) — live hardening L2
  // ═══════════════════════════════════════════════════════════════════════════
  // A host (`widget.host && !widget.isGuest`) gets LiveHostControlsController: the participants panel's header
  // (Mute all · Lock room · End for everyone) and a ⋮ per participant (mute · stop camera / share · allow / revoke
  // screen share · remove). UI and API in lib/features/shared/live/live_controls_api.dart +
  // live_participant_controls.dart; wiring in docs/live/teacher_controls_wiring.md — keep this region the only
  // host-controls code in this file. End for everyone publishes the "ending" packet first (live_end_signal.dart),
  // so the people the server removes read "the host ended the session".
  // ═══════════════════════════════════════════════════════════════════════════
  LiveHostControlsController? _controls;

  /// The host's "ending for everyone" packets (every room listens; only hosts send).
  final LiveEndForAllSignal _endSignal = LiveEndForAllSignal();

  /// This host is ending / ended the room for everyone: its own disconnect then shows no dialog.
  bool _endedForAll = false;

  bool get _canModerate => widget.host && !widget.isGuest;

  /// The per-participant ⋮ and Mute all (not only the lock row) are on.
  bool get _teacherControlsOn =>
      _controls != null && !AppConfig.disableList.contains(kLiveTeacherControlsFeatureKey);

  void _startControls() {
    if (!_canModerate) return;
    final off = AppConfig.disableList;
    if (off.contains(kLiveTeacherControlsFeatureKey) && off.contains(kLiveRoomLockFeatureKey)) return;
    // Allow / Revoke drawing = the annotation permission packet (+ can_publish_data, done by the controller).
    _controls = LiveHostControlsController(widget.ref, onDrawingChanged: _annotEnabled ? _setDrawingFor : null)
      ..onEndForAllPhase = _announceEndForAll
      // One share at a time: the presenter's app stops its share (the server mute is the fallback); a revoked
      // share ends a temporary grant.
      ..stopScreenShare = ((target) => _stopPresenter(target.identity))
      ..onScreenShareRevoked = ((identity) => _share.takeGrant(identity));
    if (!off.contains(kLiveRoomLockFeatureKey)) unawaited(_controls!.loadLock());
  }

  /// Right before end-for-all (true) and after it failed (false): tells every room why they are about to leave.
  Future<void> _announceEndForAll(bool ending) async {
    _endedForAll = ending;
    await widget.room.localParticipant
        ?.publishData(liveEndForAllPacket(ending: ending), reliable: true, topic: kLiveEndForAllTopic);
  }

  /// The server ended the room for everyone: stop / drain a device recorder, then leave as after End.
  void _onEndedForAll() {
    _endedForAll = true;
    unawaited(_endSessionWithRecording(serverEnded: true));
  }

  LiveControlTarget _controlTarget(RemoteParticipant p) {
    final perms = p.permissions;
    return liveControlTargetFrom(
      identity: p.identity,
      name: p.name,
      kind: widget.ref.kind,
      localIdentity: _myIdentity,
      imageUrl: participantPhotoFromMetadata(p.metadata),
      micOn: p.isMicrophoneEnabled(),
      cameraOn: p.isCameraEnabled(),
      screenSharing: p.isScreenShareEnabled(),
      canPublish: perms.canPublish,
      sources: [for (final s in perms.canPublishSources) s.name], // proto names: CAMERA, SCREEN_SHARE, …
      canPublishData: perms.canPublishData,
      drawingAllowed: _drawingAllowedFor(p.identity),
    );
  }

  Future<void> _openParticipantControls(RemoteParticipant p) async {
    final c = _controls;
    if (c == null) return;
    _pokeControls();
    await showLiveParticipantControls(context,
        controller: c, target: _controlTarget(p), drawingAvailable: _annotEnabled && c.onDrawingChanged != null);
  }

  /// The ⋮ of a participant's row in the panel (null when the controls are off or the person is a host).
  Widget? _controlsButton(RemoteParticipant? rp, String name) {
    final c = _controls;
    if (c == null || rp == null || !_teacherControlsOn) return null;
    final target = _controlTarget(rp);
    if (target.isHost || target.isSelf) return null;
    return AnimatedBuilder(
      animation: c,
      builder: (_, _) => LiveParticipantControlsButton(
        name: name,
        busy: c.busyFor(rp.identity) != null,
        onPressed: () => unawaited(_openParticipantControls(rp)),
      ),
    );
  }
  // ═══════════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════════════
  // Share arbitration — one screen share at a time, "Ask to share", attention badges, the chat preview
  //
  // LiveShareArbiter (lib/features/shared/live/live_share_arbiter.dart) is the state machine; packets ride on topic
  // `share` (reliable, to everyone). A host who starts sharing takes over (every other share stops, no prompt); a
  // participant without the permission, or while someone else shares, asks — every host gets the request dialog
  // (live_share_widgets.dart), the first answer wins and closes the others. Accept: the server grants
  // `screen_share` when the requester has none (POST …/permissions — the server is the gate, LiveKit refuses any
  // other publish), this host's own share stops, the accept hands over (every other presenter stops) and the
  // requester's share starts. A host stops a participant's share from the stage chip or the participant's ⋮; the
  // app stops it cleanly and the server mute is the fallback; a grant given for one request ends with that share.
  // The lead host (smallest identity) also enforces the rule for whatever slips through (races, older apps).
  // LiveAttention counts what waits (chat, new hands, lobby, share requests): the phone pill's "More" badge, the
  // minimized box, and hidden controls come back when something new arrives.
  // ═══════════════════════════════════════════════════════════════════════════
  late final LiveShareArbiter _share = LiveShareArbiter(
    localIdentity: () => _myIdentity,
    isHost: () => _isShareHost,
    send: (bytes) async {
      final lp = widget.room.localParticipant;
      if (lp == null) return;
      await lp.publishData(bytes, reliable: true, topic: kLiveShareTopic);
    },
  );
  StreamSubscription<LiveShareEvent>? _shareEvents;
  final LiveAttention _attention = LiveAttention();
  int _attentionLast = 0;
  bool _shareDialogOpen = false;

  /// Presenters a host asked to stop (the stage chip spins until their share is gone).
  final Set<String> _stopping = {};

  /// Presenters the lead host's enforcement already asked to stop (asked once per share).
  final Set<String> _enforced = {};

  /// The chat preview on screen (null: none).
  LiveChatToastData? _chatToast;
  Timer? _chatToastTimer;
  String? _lastChatId;

  /// This device hosts the share rules: the room's host whom the SERVER set up as one too (a co-host the server
  /// minted as a member would have its answers ignored by everyone else — it asks like a member then).
  bool get _isShareHost {
    if (!widget.host || widget.isGuest) return false;
    final local = widget.room.localParticipant;
    if (local == null) return true;
    final perms = local.permissions;
    return liveIsServerHost(
        identity: local.identity, kind: widget.ref.kind, canPublish: perms.canPublish, sources: perms.canPublishSources);
  }

  bool get _shareRequestsOn => !AppConfig.disableList.contains(kLiveShareRequestsFeatureKey);

  /// A host as the SERVER set them up (live_share_arbiter.dart): their answers and stops count.
  bool _isServerHost(Participant p) {
    if (p is LocalParticipant) return _isShareHost;
    final perms = p.permissions;
    return liveIsServerHost(
      identity: p.identity,
      kind: widget.ref.kind,
      canPublish: perms.canPublish,
      sources: perms.canPublishSources,
    );
  }

  bool _identityIsHost(String identity) {
    if (identity == _myIdentity) return _isShareHost;
    final p = _remoteBy(identity);
    return p != null && _isServerHost(p);
  }

  RemoteParticipant? _remoteBy(String identity) =>
      widget.room.remoteParticipants.values.firstWhereOrNull((p) => p.identity == identity);

  String _nameOf(String identity) {
    final p = _remoteBy(identity);
    if (p == null) return identity == _myIdentity ? _myReactionName : identity;
    return p.name.isNotEmpty ? p.name : p.identity;
  }

  bool get _hostPresent => widget.room.remoteParticipants.values.any(_isServerHost);

  /// This device presents now (iOS: the broadcast runs before its track is published).
  bool get _localPresenting =>
      _board.isLocalPresenting ||
      (widget.room.localParticipant?.isScreenShareEnabled() ?? false) ||
      (!kIsWeb && IosShareNative.supported && IosShareNative.broadcasting.value);

  /// The Share button now.
  LiveShareButton get _shareButtonMode {
    final mode = liveShareButtonFor(
      isHost: _isShareHost,
      sharing: _localPresenting,
      mayShare: _allowed.share,
      othersSharing: _share.othersSharing,
      requestPending: _share.requestPending,
      isGuest: widget.isGuest,
      requestsOn: _shareRequestsOn,
    );
    // A phone browser cannot share at all: asking would lead to an accept that cannot start.
    if (kIsWeb && lkPlatformIsWebMobile() && mode == LiveShareButton.request && !_boardEnabled) return LiveShareButton.hidden;
    return mode;
  }

  /// A host may stop [p]'s share from the stage (never another host's: the server refuses to moderate a host).
  bool _canStopShareOf(Participant p) => _isShareHost && p is RemoteParticipant && !_isServerHost(p);

  /// The bar's Share: start / stop / ask / withdraw (liveShareTapDecision).
  Future<void> _onShareTap() async {
    if (widget.room.localParticipant == null) return;
    final d = liveShareTapDecision(
      isHost: _isShareHost,
      sharing: _localPresenting,
      mayShare: _allowed.share,
      othersSharing: _share.othersSharing,
      requestPending: _share.requestPending,
      hostPresent: _hostPresent,
      isGuest: widget.isGuest,
      requestsOn: _shareRequestsOn,
    );
    switch (d) {
      case LiveShareTap.stop when _board.isLocalPresenting:
        _stopBoard();
      case LiveShareTap.stop:
      case LiveShareTap.start:
        // A host's start takes over once its share is live (_syncPresenters), so a closed picker stops nobody.
        await toggleScreenShare();
        _scheduleSort();
      case LiveShareTap.request:
        if (_share.request(name: _myReactionName)) {
          _showSnack(_share.othersSharing
              ? t('أُرسل طلبك: سيبدأ عرضك عندما يوافق المضيف', 'Request sent: you will present once the host accepts')
              : t('أُرسل طلب المشاركة إلى المضيف', 'Share request sent to the host'));
        }
      case LiveShareTap.cancelRequest:
        _share.cancelRequest();
        _showSnack(t('سُحب طلب المشاركة', 'Share request withdrawn'));
      case LiveShareTap.noHost:
        _showSnack(t('لا يوجد مضيف في الغرفة الآن ليوافق على المشاركة', 'No host is in the room right now to approve sharing'));
      case LiveShareTap.hidden:
        break;
    }
  }

  /// Presenters → the arbiter; a host whose share just went live takes over; the lead host enforces "one share".
  void _syncPresenters() {
    final local = widget.room.localParticipant;
    final me = _myIdentity;
    final ids = <String>[
      for (final p in widget.room.remoteParticipants.values)
        if (p.videoTrackPublications.any((t) => t.isScreenShare && !t.muted && !isBoardVideoName(t.name))) p.identity,
      if (local != null && me.isNotEmpty && _localPresenting) me,
      // A whiteboard counts as presenting (D-087).
      if (_boardEnabled && _board.presenter != null && _board.presenter != me) _board.presenter!,
    ];
    _board.localIdentity = me;
    final wasPresenting = me.isNotEmpty && _share.isPresenting(me);
    _share.setPresenters(ids);
    final nowPresenting = me.isNotEmpty && _share.isPresenting(me);
    if (_isShareHost && !wasPresenting && nowPresenting && _share.othersSharing) {
      final others = _share.presenters.keys.where((id) => id != me).toList();
      _share.takeOver(name: _myReactionName);
      for (final id in others) {
        _enforced.add(id);
        _scheduleShareFallback(id);
      }
    }
    _stopping.removeWhere((id) => !_share.isPresenting(id));
    _enforced.removeWhere((id) => !_share.isPresenting(id));
    _enforceOneShare();
  }

  /// The lead host stops every share but the one that wins (liveSharesToStop) — once per share.
  void _enforceOneShare() {
    if (!_isShareHost || _myIdentity.isEmpty) return;
    final hosts = {
      for (final p in widget.room.remoteParticipants.values)
        if (_isServerHost(p)) p.identity,
      _myIdentity,
    };
    if (liveLeadHost(hosts) != _myIdentity) return;
    for (final id in _share.sharesToStop(_identityIsHost)) {
      if (_enforced.contains(id)) continue;
      _enforced.add(id);
      if (id == _myIdentity) {
        unawaited(_stopAnyLocalShare().then((_) => _scheduleSort()));
        continue;
      }
      _share.askToStop(id, name: _myReactionName);
      _scheduleShareFallback(id);
    }
  }

  /// A presenter who does not stop by itself (an older app) is muted by the server after 4 s.
  void _scheduleShareFallback(String identity) {
    Timer(const Duration(seconds: 4), () {
      if (!mounted || !_share.isPresenting(identity)) return;
      final c = _controls;
      final rp = _remoteBy(identity);
      if (c == null || rp == null || _isServerHost(rp)) return;
      unawaited(c.api.mute(identity, source: LivePublishSource.screenShare).then((_) {}, onError: (Object e) {
        log('[SHARE] server stop of $identity: $e');
      }));
    });
  }

  /// A host stops [identity]'s share (the stage chip, the participant's ⋮). Its temporary grant ends with it.
  Future<void> _stopPresenter(String identity, {bool notify = false}) async {
    if (_stopping.contains(identity)) return;
    setState(() => _stopping.add(identity));
    _share.askToStop(identity, name: _myReactionName);
    _scheduleShareFallback(identity);
    if (notify) _showSnack(t('أُوقفت مشاركة ${_nameOf(identity)}', "${_nameOf(identity)}'s share was stopped"));
    // The chip stops spinning once the share is gone (_syncPresenters), at the latest after 8 s.
    Timer(const Duration(seconds: 8), () {
      if (mounted && _stopping.remove(identity)) setState(() {});
    });
  }

  void _onShareChanged() {
    _syncAttention();
    if (mounted) setState(() {});
  }

  void _onShareEvent(LiveShareEvent e) {
    if (!mounted) return;
    switch (e) {
      case LiveShareRequested(:final request):
        if (LiveRoomHost.isMinimized) {
          showAppNotice(
              t('يطلب ${request.name} مشاركة شاشته — افتح الغرفة للرد', '${request.name} wants to share their screen — open the room to answer'),
              icon: Icons.screen_share_rounded);
        } else {
          _openShareDialog();
        }
      case LiveShareAnswered(:final request, :final accepted, :final byMe, :final byName):
        if (!byMe) {
          final who = byName.isNotEmpty ? byName : t('مضيف آخر', 'Another host');
          _showSnack(accepted
              ? t('وافق $who على مشاركة ${request.name}', "$who accepted ${request.name}'s share")
              : t('رفض $who طلب ${request.name}', "$who declined ${request.name}'s request"));
        }
      case LiveShareRequestExpired(:final request):
        _showSnack(t('انتهت مهلة طلب ${request.name} للمشاركة', "${request.name}'s share request timed out"));
      case LiveShareWithdrawn():
        break; // the dialog follows the arbiter; a grant that ends is LiveShareGrantEnded
      case LiveShareMyRequestAccepted():
        unawaited(_startAcceptedShare());
      case LiveShareMyRequestRejected():
        _showSnack(t('اعتذر المضيف عن مشاركة شاشتك الآن', "The host can't take your screen share right now"));
      case LiveShareMyRequestExpired():
        _showSnack(t('لم يرد المضيف على طلبك. حاول مرة أخرى بعد قليل.', 'No answer from the host. Try again in a moment.'));
      case LiveShareStopAsked(:final byName, :final keep, :final takeover):
        unawaited(_stopMyShareAsked(byName: byName, keep: keep, takeover: takeover));
      case LiveShareGrantEnded(:final identity):
        unawaited(_revokeShareGrant(identity));
    }
  }

  /// A host asked this device to stop its share (stopped it, took over, or handed over to someone else).
  Future<void> _stopMyShareAsked({required String byName, String? keep, bool takeover = false}) async {
    if (!_localPresenting && !screenShareActive) return;
    await _stopAnyLocalShare();
    _scheduleSort();
    if (!mounted) return;
    final who = byName.isNotEmpty ? byName : t('المضيف', 'The host');
    _showSnack(takeover
        ? t('بدأ $who مشاركة شاشته، فتوقفت مشاركتك', '$who started sharing, so your share stopped')
        : keep != null
            ? t('توقفت مشاركتك ليعرض ${_nameOf(keep)}', 'Your share stopped so ${_nameOf(keep)} can present')
            : t('أوقف $who مشاركة شاشتك', '$who stopped your screen share'));
  }

  /// A host accepted my request: the permission may still be on its way (≤ 8 s), then the share starts by itself
  /// (the options sheet and the OS picker still ask on web / Android).
  Future<void> _startAcceptedShare() async {
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (mounted && !_allowed.share && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (!mounted) return;
    if (!_allowed.share) {
      _share.withdrawAccepted();
      _showSnack(t('تعذّر بدء المشاركة: لم يصل الإذن بعد. اطلب مرة أخرى.', "Couldn't start sharing: the permission did not arrive. Ask again."),
          error: true);
      return;
    }
    LiveRoomScope.maybeOf(context)?.expand();
    _showSnack(t('وافق المضيف — اختر ما تريد مشاركته', 'The host accepted — choose what to share'));
    if (!_localPresenting) await toggleScreenShare();
    if (!mounted) return;
    _scheduleSort();
    // iOS: the broadcast sheet may still be open; the approval lapses there on its own if nothing starts.
    final iosPending = !kIsWeb && lkPlatformIs(PlatformType.iOS);
    if (!iosPending && !_localPresenting) _share.withdrawAccepted(); // closed the picker: the hosts take it back
  }

  /// The request dialog over the room (once; it follows the arbiter and closes by itself).
  void _openShareDialog() {
    if (!mounted || _shareDialogOpen || _share.current == null || LiveRoomHost.isMinimized || !_isShareHost) return;
    _shareDialogOpen = true;
    _pokeControls();
    unawaited(showLiveShareRequestDialog(
      context,
      arbiter: _share,
      onAnswer: (r, accept) => unawaited(_answerShare(r, accept)),
      note: _shareAcceptNote,
      imageFor: (r) => participantPhotoFromMetadata(_remoteBy(r.identity)?.metadata) ?? r.imageUrl,
    ).whenComplete(() {
      _shareDialogOpen = false;
      // Closed by a minimize with requests left: asked again when the room is full-screen (_syncDecorLoops).
    }));
  }

  (LiveShareAcceptNote, String) _shareAcceptNote() {
    if (_localPresenting) return (LiveShareAcceptNote.yours, '');
    final other = _share.presenters.keys.where((id) => id != _myIdentity).firstOrNull;
    if (other != null) return (LiveShareAcceptNote.other, _nameOf(other));
    return (LiveShareAcceptNote.none, '');
  }

  /// Accept / Decline from the dialog. Accept: the server's permission first (when the requester has none), then
  /// this host's own share stops, then the answer (every host closes its dialog; the requester starts).
  Future<void> _answerShare(LiveShareRequest r, bool accept) async {
    final me = _myReactionName;
    if (!accept) {
      _share.answer(r.id, accept: false, name: me);
      return;
    }
    if (!_share.beginAnswer(r.id)) return;
    final rp = _remoteBy(r.identity);
    if (rp == null) {
      _share.answer(r.id, accept: false, name: me);
      _showSnack(t('غادر ${r.name} الغرفة', '${r.name} left the room'));
      return;
    }
    var granted = false;
    final perms = _controlTarget(rp).permissions;
    if (!perms.mayShareScreen) {
      final c = _controls;
      if (c == null) {
        _share.abortAnswer(r.id);
        _showSnack(t('أدوات المضيف متوقفة: لا يمكن منح إذن المشاركة', 'Host controls are off: the share permission cannot be given'),
            error: true);
        return;
      }
      try {
        await c.api.setPermissions(r.identity, perms.withScreenShare(true));
        granted = true;
      } catch (e) {
        _share.abortAnswer(r.id);
        _showSnack(liveControlsError(e), error: true);
        return;
      }
    }
    if (_localPresenting) {
      await _stopAnyLocalShare();
      _scheduleSort();
    }
    // The grant is noted first: an answer that comes back at once (a lapsed request) already finds it.
    if (granted) _share.noteGrant(r.identity); // taken back when that share ends (LiveShareGrantEnded)
    final answered = _share.answer(r.id, accept: true, name: me);
    if (granted && answered == null && _share.approvedAt(r.identity) == null && _share.takeGrant(r.identity)) {
      unawaited(_revokeShareGrant(r.identity)); // it lapsed / was withdrawn meanwhile
    }
  }

  /// Takes back a share permission this host gave for one request.
  Future<void> _revokeShareGrant(String identity) async {
    final c = _controls;
    final rp = _remoteBy(identity);
    if (c == null || rp == null) return;
    final perms = _controlTarget(rp).permissions;
    if (!perms.mayShareScreen) return;
    try {
      await c.api.setPermissions(identity, perms.withScreenShare(false));
    } catch (e) {
      log('[SHARE] revoke the grant of $identity: $e');
    }
  }

  // ── Attention ──────────────────────────────────────────────────────────────
  void _syncAttention() {
    _attention.setChatUnread(_chat.unread);
    if (widget.isTeacher || _isShareHost) _attention.setHands([for (final h in _hands.hands) h.identity]);
    final lobby = _lobby;
    if (lobby != null) _attention.setLobby([for (final r in lobby.waiting) r.id]);
    _attention.setShareRequests(_isShareHost ? _share.pendingCount : 0);
  }

  void _onAttention() {
    final total = _attention.total;
    // Something new while the phone's controls are hidden: they come back with the badge.
    if (total > _attentionLast && mounted) _pokeControls();
    _attentionLast = total;
    LiveRoomHost.attention.value = total;
  }

  // ── Chat preview ───────────────────────────────────────────────────────────
  bool get _chatVisible => _chat.isOpen || _side == _SidePanel.chat || _sheetPanel == _SidePanel.chat;

  void _onChatChanged() {
    _syncAttention();
    final msgs = _chat.messages;
    if (msgs.isEmpty) {
      _lastChatId = null;
      return;
    }
    final last = msgs.last;
    if (last.id == _lastChatId) return;
    _lastChatId = last.id;
    if (last.mine || _chatVisible || LiveRoomHost.isMinimized || !mounted) {
      if (_chatVisible) _hideChatToast();
      return;
    }
    final photo = participantPhotoFromMetadata(_remoteBy(last.identity)?.metadata);
    setState(() => _chatToast = LiveChatToastData(
          id: last.id,
          name: last.name,
          text: last.text,
          imageUrl: photo,
          more: (_chat.unread - 1).clamp(0, 999),
        ));
    _chatToastTimer?.cancel();
    _chatToastTimer = Timer(const Duration(seconds: 5), _hideChatToast);
  }

  void _hideChatToast() {
    _chatToastTimer?.cancel();
    _chatToastTimer = null;
    if (_chatToast != null && mounted) setState(() => _chatToast = null);
  }
  // ═══════════════════════════════════════════════════════════════════════════

  // ── Participant panel ──────────────────────────────────────────────────────
  Widget _buildParticipantPanel() {
    final liveIdentities = widget.room.remoteParticipants.values
        .map((p) => p.identity)
        .toSet();
    final guests = widget.room.remoteParticipants.values
        .where((p) => isGuestIdentity(p.identity))
        .toList();
    // Host controls: everyone else in the room who is not on the roster (meeting members, staff, a co-host),
    // so the host can reach them too. Only for a host: other viewers keep the roster as it was.
    final others = _controls == null
        ? const <RemoteParticipant>[]
        : widget.room.remoteParticipants.values
            .where((p) =>
                !liveIsGuestIdentity(p.identity) &&
                !_enrolledStudents.any(
                    (s) => liveIdentityIsStudent(p.identity, p.name, studentId: s.id, studentName: s.name)))
            .toList();

    return Positioned.fill(
      child: GestureDetector(
        onTap: _toggleParticipantPanel,
        child: Container(color: LivePalette.shade(0.45)),
      ),
    ).withChild(
      Positioned(
        top: 0,
        bottom: 0,
        right: 0,
        width: 300,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(_panelSlide),
          child: Container(
            decoration: BoxDecoration(
              color: _surfaceHi,
              border: Border(left: BorderSide(color: _glassBdr, width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 8, 12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: _glassBdr)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.people_rounded, color: _cyan, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Participants',
                        style: TextStyle(
                          fontFamily: AppFonts.family,
                          color: _textHigh,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      if (_loadingStudents)
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _cyan,
                          ),
                        ),
                      // Teacher: one tap mutes every guest (guests never see moderation). The host controls' Mute
                      // all (everyone but the hosts) replaces it while they are on.
                      if (widget.isTeacher && !widget.isGuest && guests.isNotEmpty && !_teacherControlsOn)
                        _guestBusy.value == '*'
                            ? const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: _textMid)),
                              )
                            : IconButton(
                                key: const ValueKey('live_room.mute_all_guests'),
                                tooltip: 'lr_mute_all_guests'.tr,
                                onPressed: _guestBusy.value == null ? _guestsMuteAll : null,
                                icon: Icon(Icons.mic_off_rounded, size: 18, color: LivePalette.warning),
                              ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: _toggleParticipantPanel,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: _glass10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: _textMid,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Host controls: Mute all · Lock room · End for everyone (each behind its own kill switch).
                if (_controls != null)
                  LiveHostControlsHeader(controller: _controls!, onEnded: _onEndedForAll),

                // Teacher row
                _ParticipantRow(
                  name: widget.room.localParticipant?.name ?? 'You',
                  isOnline: true,
                  isTeacher: true,
                  isAttended: true,
                  micOn: LiveMicGate.instance.micOn(widget.room.localParticipant),
                  camOn:
                  widget.room.localParticipant?.isCameraEnabled() ?? false,
                  joinDate: widget.room.localParticipant?.joinedAt,
                ),

                Divider(color: _glassBdr, height: 1),

                // Section label
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Row(
                    children: [
                      Text(
                        trp('lr_students_count', {'n': '${_enrolledStudents.length}'}),
                        style: TextStyle(
                          fontFamily: AppFonts.family,
                          color: _textLow,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _emerald.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _emerald.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          trp('lr_n_attended', {'n': '${_enrolledStudents.where((s) => s.isAttended).length}'}),
                          style: TextStyle(
                            fontFamily: AppFonts.family,
                            color: _emerald,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Guests (public link): not enrolled, known only from the room itself.
                if (guests.isNotEmpty)
                  for (final g in guests)
                    _ParticipantRow(
                      name: g.name.isNotEmpty ? g.name : g.identity.substring(6),
                      isOnline: true,
                      isTeacher: false,
                      isGuest: true,
                      isAttended: false,
                      micOn: g.isMicrophoneEnabled(),
                      camOn: g.isCameraEnabled(),
                      joinDate: g.joinedAt,
                      handUp: _hands.isUp(g.identity),
                      trailing: widget.isTeacher && !widget.isGuest ? _guestMenu(g) : null,
                    ),

                // Student list
                Expanded(
                  child: _enrolledStudents.isEmpty && others.isEmpty
                      ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.school_outlined,
                          color: _textLow,
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'lr_no_students'.tr,
                          style: TextStyle(
                            fontFamily: AppFonts.family,
                            color: _textLow,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                      : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: others.length + _enrolledStudents.length,
                    itemBuilder: (ctx, i) {
                      if (i < others.length) {
                        final o = others[i];
                        final name = o.name.isNotEmpty ? o.name : o.identity;
                        return _ParticipantRow(
                          name: name,
                          isOnline: true,
                          isTeacher: false,
                          isAttended: false,
                          joinDate: o.joinedAt,
                          micOn: o.isMicrophoneEnabled(),
                          camOn: o.isCameraEnabled(),
                          handUp: _hands.isUp(o.identity),
                          trailing: _controlsButton(o, name),
                        );
                      }
                      final s = _enrolledStudents[i - others.length];
                      final rp = widget.room.remoteParticipants.values
                          .firstWhereOrNull(
                            (p) => liveIdentityIsStudent(p.identity, p.name, studentId: s.id, studentName: s.name),
                      );
                      final online = rp != null ||
                          liveIdentities.contains(s.id.toString()) ||
                          liveIdentities.contains(s.name);
                      return _ParticipantRow(
                        name: s.name,
                        isOnline: online,
                        isTeacher: false,
                        isAttended: s.isAttended,
                        joinDate: s.joinDate,
                        leaveDate: s.leaveDate,
                        micOn: rp?.isMicrophoneEnabled() ?? false,
                        camOn: rp?.isCameraEnabled() ?? false,
                        handUp: rp != null && _hands.isUp(rp.identity),
                        trailing: _controlsButton(rp, s.name),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ⋮ menu of a guest row: Mute · Allow / Block speaking · Remove (teacher only).
  Widget _guestMenu(RemoteParticipant g) {
    final id = g.identity;
    final name = g.name.isNotEmpty ? g.name : id.substring(kGuestIdentityPrefix.length);
    if (_guestBusy.value == id) {
      return const SizedBox(
          width: 32, height: 32, child: Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _textMid))));
    }
    final canSpeak = g.permissions.canPublish;
    return PopupMenuButton<String>(
      key: ValueKey('live_room.guest_menu.$id'),
      tooltip: 'more'.tr,
      enabled: _guestBusy.value == null,
      color: _surfaceHi,
      padding: EdgeInsets.zero,
      iconSize: 18,
      icon: const Icon(Icons.more_vert_rounded, color: _textMid),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _glassBdr)),
      onSelected: (v) {
        switch (v) {
          case 'mute':
            unawaited(_guestMute(id));
          case 'speak':
            unawaited(_guestAllowSpeak(id, !canSpeak));
          case 'kick':
            unawaited(_guestKick(id, name));
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'mute',
          enabled: g.isMicrophoneEnabled(),
          child: _menuRow(Icons.mic_off_rounded, 'lr_mute_guest'.tr),
        ),
        PopupMenuItem(
          value: 'speak',
          child: _menuRow(canSpeak ? Icons.voice_over_off_rounded : Icons.record_voice_over_rounded,
              (canSpeak ? 'lr_block_speak' : 'lr_allow_speak').tr),
        ),
        PopupMenuItem(
          value: 'kick',
          child: _menuRow(Icons.person_remove_rounded, 'lr_remove_guest'.tr, color: _rose),
        ),
      ],
    );
  }

  static Widget _menuRow(IconData icon, String label, {Color? color}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: color ?? _textMid),
        const SizedBox(width: 10),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: AppFonts.family, fontSize: 13, fontWeight: FontWeight.w600, color: color ?? _textHigh)),
        ),
      ]);

  // ── Quiz overlay ──────────────────────────────────────────────────────────
  Widget _buildQuizOverlay() {
    final quiz = _activeQuiz!;
    final totalQ = quiz.questions.length;
    final mins = _quizSecondsLeft ~/ 60;
    final secs = _quizSecondsLeft % 60;
    final timerStr =
        '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    final isLast = _currentQuestionIndex == totalQ - 1;

    return Positioned.fill(
      child: Container(
        color: LivePalette.shade(0.80),
        child: Center(
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(_quizSlide),
            child: FadeTransition(
              opacity: _quizSlide,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: _surfaceHi,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _cyan.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _cyan.withValues(alpha: 0.12),
                      blurRadius: 40,
                    ),
                    BoxShadow(
                      color: LivePalette.shade(0.6),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: _quizSubmitted
                    ? _buildQuizResultView(quiz)
                    : _buildQuizActiveView(quiz, timerStr, isLast),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuizActiveView(ActiveQuiz quiz, String timerStr, bool isLast) {
    final q = quiz.questions[_currentQuestionIndex];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_cyan.withValues(alpha: 0.15), Colors.transparent],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(23)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _cyan.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.quiz_rounded, size: 13, color: _cyan),
                    SizedBox(width: 5),
                    Text(
                      'lr_live_quiz'.tr,
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        color: _cyan,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _quizSecondsLeft < 30
                      ? _rose.withValues(alpha: 0.2)
                      : _glass10,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _quizSecondsLeft < 30
                        ? _rose.withValues(alpha: 0.5)
                        : _glassBdr,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timer_rounded,
                      size: 13,
                      color: _quizSecondsLeft < 30 ? _rose : _textMid,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      timerStr,
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        color: _quizSecondsLeft < 30 ? _rose : _textMid,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text(
            quiz.name,
            style: const TextStyle(
              color: _textHigh,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(
            children: [
              Text(
                trp('lr_question_of', {'n': '${_currentQuestionIndex + 1}', 'total': '${quiz.questions.length}'}),
                style: TextStyle(
                  fontFamily: AppFonts.family,
                  color: _textLow,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_currentQuestionIndex + 1) / quiz.questions.length,
                    backgroundColor: _glass10,
                    valueColor: AlwaysStoppedAnimation(_cyan),
                    minHeight: 4,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Text(
            q.text,
            style: const TextStyle(
              color: _textHigh,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
        ...List.generate(q.options.length, (idx) {
          final selected = _selectedAnswers[q.id] == idx;
          return GestureDetector(
            onTap: () {
              if (mounted) setState(() => _selectedAnswers[q.id] = idx);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: selected ? _cyan.withValues(alpha: 0.15) : _glass10,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? _cyan.withValues(alpha: 0.6) : _glassBdr,
                  width: selected ? 1.5 : 1,
                ),
                boxShadow: selected
                    ? [
                  BoxShadow(
                    color: _cyan.withValues(alpha: 0.15),
                    blurRadius: 12,
                  ),
                ]
                    : [],
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? _cyan : Colors.transparent,
                      border: Border.all(
                        color: selected ? _cyan : _glassBdr,
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? Icon(Icons.check_rounded, size: 13, color: _bg)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      q.options[idx],
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        color: selected ? _textHigh : _textMid,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Row(
            children: [
              if (_currentQuestionIndex > 0) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (mounted) setState(() => _currentQuestionIndex--);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: _glass10,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _glassBdr),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.arrow_back_rounded,
                            size: 16,
                            color: _textMid,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Back',
                            style: TextStyle(
                              fontFamily: AppFonts.family,
                              color: _textMid,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: isLast
                      ? () => _submitQuiz()
                      : () {
                    if (mounted) setState(() => _currentQuestionIndex++);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_cyan, _indigo],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: _cyan.withValues(alpha: 0.3),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isLast ? 'Submit' : 'Next',
                          style: const TextStyle(
                            color: _textHigh,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          isLast
                              ? Icons.check_circle_rounded
                              : Icons.arrow_forward_rounded,
                          size: 16,
                          color: _textHigh,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuizResultView(ActiveQuiz quiz) {
    final answered = _selectedAnswers.length;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _emerald.withValues(alpha: 0.15),
              border: Border.all(
                color: _emerald.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: Icon(Icons.check_rounded, color: _emerald, size: 36),
          ),
          const SizedBox(height: 18),
          Text(
            'lr_quiz_submitted_title'.tr,
            style: TextStyle(
              fontFamily: AppFonts.family,
              color: _textHigh,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            trp('lr_you_answered', {'n': '$answered', 'total': '${quiz.questions.length}'}),
            style: TextStyle(
              fontFamily: AppFonts.family,
              color: _textMid,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _dismissQuiz,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 13),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [_cyan, _indigo]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _cyan.withValues(alpha: 0.3),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: Text(
                'lr_back_to_room'.tr,
                style: TextStyle(
                  fontFamily: AppFonts.family,
                  color: _textHigh,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Extension helper
// ─────────────────────────────────────────────────────────────────────────────
extension _WidgetEx on Widget {
  Widget withChild(Widget child) => Stack(children: [this, child]);
}

// ─────────────────────────────────────────────────────────────────────────────
// _ParticipantRow  — cleaned up (removed debug prints, fixed join/leave display)
// ─────────────────────────────────────────────────────────────────────────────
class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.name,
    required this.isOnline,
    required this.isTeacher,
    required this.isAttended,
    required this.micOn,
    required this.camOn,
    this.joinDate,
    this.leaveDate,
    this.isGuest = false,
    this.handUp = false,
    this.trailing,
  });

  final String name;
  final bool isOnline;
  final bool isTeacher;

  /// Joined through a public guest link (no enrolment, no attendance).
  final bool isGuest;
  final bool isAttended;
  final bool micOn;
  final bool camOn;
  final DateTime? joinDate;
  final DateTime? leaveDate;
  /// ✋ in the queue right now.
  final bool handUp;
  /// The host's ⋮: the guest menu for guests, the host controls' button for everyone else in the room.
  final Widget? trailing;

  String _fmtDuration(DateTime? from, DateTime? to) {
    final mins = liveMinutesBetween(from, to);
    if (mins == null) return '';
    if (mins < 60) return trp('lr_duration_m', {'m': '$mins'});
    return trp('lr_duration_hm', {'h': '${mins ~/ 60}', 'm': '${mins % 60}'});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isTeacher ? _cyan.withValues(alpha: 0.05) : Colors.transparent,
        border: Border(
          bottom: BorderSide(color: _glassBdr.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          // Avatar + online dot
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isTeacher
                        ? [
                      _cyan.withValues(alpha: 0.8),
                      _indigo.withValues(alpha: 0.8),
                    ]
                        : [_glass15, _glass10],
                  ),
                  border: Border.all(
                    color: isTeacher ? _cyan.withValues(alpha: 0.5) : _glassBdr,
                    width: 1.2,
                  ),
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontFamily: AppFonts.family,
                      color: isTeacher ? _bg : _textMid,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOnline ? _emerald : _textLow,
                    border: Border.all(color: _surfaceHi, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),

          // Name + tags + duration
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: _textHigh,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (isTeacher)
                      _MiniTag(label: 'teacher'.tr, color: _cyan)
                    else if (isGuest) ...[
                      _MiniTag(label: 'lr_guest'.tr, color: LivePalette.warning),
                      if (isOnline) ...[
                        const SizedBox(width: 4),
                        _MiniTag(label: 'lr_online'.tr, color: _emerald),
                      ],
                    ] else ...[
                      _MiniTag(
                        label: isAttended ? 'lr_attended'.tr : 'lr_absent'.tr,
                        color: isAttended ? _emerald : _rose,
                      ),
                      if (isOnline) ...[
                        const SizedBox(width: 4),
                        _MiniTag(label: 'lr_online'.tr, color: _emerald),
                      ],
                    ],
                  ],
                ),
                // Join → leave duration (clean, no debug prints)
                if (joinDate != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    isOnline
                        ? trp('lr_joined_ago', {'t': _fmtDuration(joinDate, null)})
                        : leaveDate != null
                        ? trp('lr_stayed', {'t': _fmtDuration(joinDate, leaveDate)})
                        : '',
                    style: TextStyle(
                      fontFamily: AppFonts.family,
                      color: _textLow,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Hand · mic / cam · menu
          if (handUp) ...[
            const LiveHandBadge(compact: true),
            const SizedBox(width: 6),
          ],
          if (isOnline && !isTeacher) ...[
            Icon(
              micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
              size: 14,
              color: micOn ? LivePalette.textSoft : _rose.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 6),
            Icon(
              camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              size: 14,
              color: camOn ? LivePalette.textSoft : _rose.withValues(alpha: 0.7),
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: 2),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontFamily: AppFonts.family,
        color: color,
        fontSize: 9,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _ThumbnailCard, _PremiumScreenShareView, and all other widgets below are
// unchanged from the original room.dart — copied verbatim.
// ─────────────────────────────────────────────────────────────────────────────

class _ThumbnailCard extends StatelessWidget {
  const _ThumbnailCard({required this.track, required this.resolveScreenTrack, this.handUp = false, this.renderVideo = true});

  final ParticipantTrack track;
  final VideoTrack? Function(Participant) resolveScreenTrack;
  final bool handUp;

  /// False past the device's video budget (D-090): the avatar instead of a renderer.
  final bool renderVideo;

  @override
  Widget build(BuildContext context) {
    final isScreen = track.type == ParticipantTrackType.kScreenShare;
    final screenTrack = isScreen ? resolveScreenTrack(track.participant) : null;
    final isSpeaking = track.participant.isSpeaking;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 152,
      height: 108,
      margin: const EdgeInsetsDirectional.only(end: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSpeaking
              ? _cyan.withValues(alpha: 0.8)
              : isScreen
              ? _cyan.withValues(alpha: 0.55)
              : _glassBdr,
          width: isSpeaking ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: LivePalette.shade(0.45),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
          if (isScreen || isSpeaking)
            BoxShadow(
              color: _cyan.withValues(alpha: isSpeaking ? 0.25 : 0.15),
              blurRadius: 16,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isScreen && screenTrack != null && renderVideo)
              LiveVideoView(screenTrack, key: ValueKey(screenTrack.sid), fit: VideoViewFit.contain)
            else
              ParticipantWidget.widgetFor(track, showStatsLayer: false, renderVideo: renderVideo),
            if (handUp)
              const PositionedDirectional(top: 5, start: 5, child: LiveHandBadge(compact: true)),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      LivePalette.shade(0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    if (isScreen)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 4),
                        child: Icon(
                          Icons.screen_share_rounded,
                          size: 10,
                          color: _cyan,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        track.participant.name.isNotEmpty
                            ? track.participant.name
                            : track.participant.identity,
                        style: const TextStyle(
                          fontSize: 10,
                          color: _textMid,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSpeaking)
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsetsDirectional.only(start: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _cyan,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _PremiumScreenShareView and all sub-widgets (unchanged) ─────────────────

class _PremiumScreenShareView extends StatefulWidget {
  final Participant participant;
  final VideoTrack? Function(Participant) resolveScreenTrack;
  final AnimationController auroraAnim;

  /// Annotation over the shared video (null: `live.annotation` is off).
  final AnnotationController? annot;

  /// A host's "Stop share" on this participant's share (null hides it).
  final VoidCallback? onStopShare;
  final bool stopBusy;

  const _PremiumScreenShareView({
    required this.participant,
    required this.resolveScreenTrack,
    required this.auroraAnim,
    this.annot,
    this.onStopShare,
    this.stopBusy = false,
  });

  @override
  State<_PremiumScreenShareView> createState() =>
      _PremiumScreenShareViewState();
}

class _PremiumScreenShareViewState extends State<_PremiumScreenShareView>
    with SingleTickerProviderStateMixin {
  late AnimationController _borderGlowAnim;
  late Animation<double> _borderGlow;

  @override
  void initState() {
    super.initState();
    // D-092: a still glow. Pulsing, it repainted two large blurred shadows (32 / 48) around the shared video on
    // every frame, for as long as a share was on the stage.
    _borderGlowAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
      value: 0.55,
    );
    _borderGlow = CurvedAnimation(
      parent: _borderGlowAnim,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _borderGlowAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenTrack = widget.resolveScreenTrack(widget.participant);
    final presenterName = widget.participant.name.isNotEmpty
        ? widget.participant.name
        : widget.participant.identity;
    final isSpeaking = widget.participant.isSpeaking;
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.3),
              radius: 1.2,
              colors: [LivePalette.surfaceHi, LivePalette.bg],
            ),
          ),
        ),
        AnimatedBuilder(
          animation: widget.auroraAnim,
          builder: (_, _) => CustomPaint(
            painter: _ScreenShareAuroraPainter(
              widget.auroraAnim.value * 2 * 3.14159,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 72),
            child: AnimatedBuilder(
              animation: _borderGlow,
              builder: (_, child) => Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _cyan.withValues(
                      alpha: 0.25 + 0.35 * _borderGlow.value,
                    ),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _cyan.withValues(
                        alpha: 0.08 + 0.14 * _borderGlow.value,
                      ),
                      blurRadius: 32,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: _indigo.withValues(
                        alpha: 0.06 + 0.08 * _borderGlow.value,
                      ),
                      blurRadius: 48,
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: child,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(19),
                child: screenTrack != null
                    ? (widget.annot == null
                        ? LiveVideoView(screenTrack, fit: VideoViewFit.contain)
                        : _AnnotatedShareVideo(track: screenTrack, controller: widget.annot!))
                    : _ScreenShareLoadingPlaceholder(
                  presenterName: presenterName,
                ),
              ),
            ),
          ),
        ),
        PositionedDirectional(
          top: 20,
          start: 20,
          end: 112, // clear of the SCREEN badge
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _PresenterBadge(name: presenterName, isSpeaking: isSpeaking),
              if (widget.onStopShare != null) LiveStopShareChip(onTap: widget.onStopShare!, busy: widget.stopBusy),
            ]),
          ),
        ),
        const PositionedDirectional(top: 20, end: 20, child: _ScreenShareLiveBadge()),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _ScreenShareBottomBar(
            participant: widget.participant,
            presenterName: presenterName,
          ),
        ),
      ],
    );
  }
}

/// The shared video with the annotation layer on top. It owns the renderer so the layer reads the REAL frame size
/// (RTCVideoValue: width / height / rotation, the same aspect RTCVideoView's `contain` fit uses), which follows
/// rotation and window resizes. Until the first frame the layer uses its own size.
class _AnnotatedShareVideo extends StatefulWidget {
  const _AnnotatedShareVideo({required this.track, required this.controller});

  final VideoTrack track;
  final AnnotationController controller;

  @override
  State<_AnnotatedShareVideo> createState() => _AnnotatedShareVideoState();
}

class _AnnotatedShareVideoState extends State<_AnnotatedShareVideo> {
  final rtc.RTCVideoRenderer _renderer = rtc.RTCVideoRenderer();
  bool _ready = false;
  bool _disposed = false;
  Size? _frame;

  @override
  void initState() {
    super.initState();
    _renderer.addListener(_onValue);
    unawaited(_renderer.initialize().then((_) {
      if (!_disposed && mounted) setState(() => _ready = true);
    }, onError: (Object e) => log('[ANNOT] renderer init: $e')));
  }

  void _onValue() {
    if (!mounted) return;
    final v = _renderer.value;
    final next = v.width > 0 && v.height > 0 ? Size(v.aspectRatio, 1) : null;
    if (next != _frame) setState(() => _frame = next);
  }

  @override
  void dispose() {
    _disposed = true;
    _renderer.removeListener(_onValue);
    // The VideoTrackRenderer below was unmounted first (children go first) and does not dispose a cached renderer.
    unawaited(() async {
      try {
        _renderer.srcObject = null;
        await _renderer.dispose();
      } catch (e) {
        log('[ANNOT] renderer dispose: $e');
      }
    }());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.expand();
    return Stack(fit: StackFit.expand, children: [
      // D-092: LiveVideoView — no renderer gesture (my own share's taps threw setFocusMode and hid the bar's tap).
      LiveVideoView(
        widget.track,
        mirror: VideoViewMirrorMode.off,
        fit: VideoViewFit.contain,
        cachedRenderer: _renderer,
        autoDisposeRenderer: false,
      ),
      AnnotationLayer(controller: widget.controller, contentSize: _frame),
    ]);
  }
}

class _PresenterBadge extends StatelessWidget {
  const _PresenterBadge({required this.name, required this.isSpeaking});

  final String name;
  final bool isSpeaking;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: isSpeaking
          ? _cyan.withValues(alpha: 0.22)
          : LivePalette.shade(0.55),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(
        color: isSpeaking ? _cyan.withValues(alpha: 0.7) : _glassBdr,
        width: 1,
      ),
      boxShadow: isSpeaking
          ? [BoxShadow(color: _cyan.withValues(alpha: 0.25), blurRadius: 16)]
          : [],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSpeaking ? _cyan : _textLow,
            boxShadow: isSpeaking
                ? [BoxShadow(color: _cyan, blurRadius: 6)]
                : [],
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          Icons.person_rounded,
          size: 13,
          color: isSpeaking ? _cyan : _textMid,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppFonts.family,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isSpeaking ? _cyan : _textMid,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ScreenShareLiveBadge extends StatelessWidget {
  const _ScreenShareLiveBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          _indigo.withValues(alpha: 0.85),
          _cyan.withValues(alpha: 0.75),
        ],
      ),
      borderRadius: BorderRadius.circular(30),
      boxShadow: [
        BoxShadow(color: _indigo.withValues(alpha: 0.4), blurRadius: 14),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.screen_share_rounded, size: 13, color: LivePalette.textHigh),
        SizedBox(width: 6),
        Text(
          'SCREEN',
          style: TextStyle(
            fontFamily: AppFonts.family,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: LivePalette.textHigh,
            letterSpacing: 1.2,
          ),
        ),
      ],
    ),
  );
}

class _ScreenShareBottomBar extends StatelessWidget {
  const _ScreenShareBottomBar({
    required this.participant,
    required this.presenterName,
  });

  final Participant participant;
  final String presenterName;

  @override
  Widget build(BuildContext context) {
    final micOn = participant.isMicrophoneEnabled();
    final camOn = participant.isCameraEnabled();

    return Container(
      height: 64,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            LivePalette.shade(0.85),
            LivePalette.shade(0.55),
            Colors.transparent,
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [_cyan, _indigo],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(color: _cyan.withValues(alpha: 0.35), blurRadius: 10),
              ],
            ),
            child: Center(
              child: Text(
                presenterName.isNotEmpty ? presenterName[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: LivePalette.textHigh,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  presenterName,
                  style: const TextStyle(
                    color: _textHigh,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'lr_sharing_screen'.tr,
                  style: TextStyle(
                    fontFamily: AppFonts.family,
                    color: _cyan.withValues(alpha: 0.8),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              _StatusPill(
                icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                color: micOn ? _emerald : _rose,
                active: micOn,
              ),
              const SizedBox(width: 6),
              _StatusPill(
                icon: camOn
                    ? Icons.videocam_rounded
                    : Icons.videocam_off_rounded,
                color: camOn ? _emerald : _textLow,
                active: camOn,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.color,
    required this.active,
  });

  final IconData icon;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: active ? 0.18 : 0.08),
      border: Border.all(
        color: color.withValues(alpha: active ? 0.5 : 0.2),
        width: 1,
      ),
    ),
    child: Icon(icon, size: 14, color: color),
  );
}

class _ScreenShareLoadingPlaceholder extends StatelessWidget {
  const _ScreenShareLoadingPlaceholder({required this.presenterName});

  final String presenterName;

  @override
  Widget build(BuildContext context) => Container(
    color: LivePalette.bg,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _indigo.withValues(alpha: 0.12),
            border: Border.all(
              color: _indigo.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Icon(
            Icons.screen_share_rounded,
            size: 32,
            color: _indigo,
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: _cyan),
        ),
        const SizedBox(height: 14),
        Text(
          trp('lr_presenter_sharing', {'name': presenterName}),
          style: const TextStyle(
            color: _textMid,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Connecting…',
          style: TextStyle(
            fontFamily: AppFonts.family,
            color: _cyan.withValues(alpha: 0.6),
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}

class _ScreenShareAuroraPainter extends CustomPainter {
  const _ScreenShareAuroraPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    _blob(
      canvas,
      Offset(
        size.width * (0.15 + 0.05 * math.sin(t * 0.7)),
        size.height * (0.2 + 0.06 * math.cos(t * 0.5)),
      ),
      size.width * 0.45,
      _indigo.withValues(alpha: 0.06),
    );
    _blob(
      canvas,
      Offset(
        size.width * (0.82 + 0.04 * math.cos(t * 0.9)),
        size.height * (0.75 + 0.05 * math.sin(t * 0.6)),
      ),
      size.width * 0.4,
      _cyan.withValues(alpha: 0.04),
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
  bool shouldRepaint(_ScreenShareAuroraPainter old) => old.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
// _PremiumWaitingPlaceholder  — Teams-style tile grid (no-content placeholder)
// Shows a Microsoft Teams-style grid: the teacher's tile first, then real
// attended participants, each a colored initials circle (or photo) with a
// name+mic pill anchored bottom-left — matching the reference screenshots
// (colored circle avatars, dark tiles, bottom-left name+mic chip).
//
// Also reused, unchanged, as the frozen recording placeholder on Android
// (see _captureAndSendLiveScreen / _sendLiveScreenPlaceholderWeb) — this is the single source of truth for
// "what does the app show when there's nothing else to display", so the
// recorded video and the live in-app view are guaranteed to look the same,
// and both match what iOS's own screen recording captures naturally (iOS
// just screen-records whatever's actually on screen, which is this same
// widget in the equivalent state).
// ─────────────────────────────────────────────────────────────────────────────
class _PremiumWaitingPlaceholder extends StatelessWidget {
  const _PremiumWaitingPlaceholder({
    required this.teacherName,
    required this.isMicOn,
    required this.isCamOn,
    required this.auroraAnim,
    required this.room,
    this.sessionTitle,
    this.enrolledStudents = const [],
    this.showLogo = false,
    this.live = true,
  });

  final String teacherName;
  final bool isMicOn;
  final bool isCamOn;
  // No longer used by this widget's own visuals (the old aurora
  // background + pulsing ring were replaced by a flat Teams-style grid —
  // Teams' own waiting/grid views don't use glow effects), but kept as a
  // required param so both call sites (the live "waiting" view and the
  // recording capture) don't need to change just to stop passing it.
  final AnimationController auroraAnim;
  // Live LiveKit roster — the actual source of truth for who's in the
  // grid, their real mic state, and real-time speaking status. Previously
  // this widget was handed a pre-filtered List<EnrolledStudent> (filtered
  // by .isAttended, which is only refreshed by periodic REST polling, not
  // real-time) — a student could be genuinely connected via LiveKit right
  // now and still show isAttended==false if that poll hadn't run recently,
  // which is exactly why only the teacher tile was appearing. Reading
  // room.remoteParticipants directly removes that lag entirely.
  final Room room;
  final String? sessionTitle;
  // Only used now for enrichment (photo, join/leave times) by matching
  // against the live roster — see the id/name matching in build() below,
  // mirroring the pattern already used elsewhere in this file
  // (p.identity == s.id.toString() || p.name == s.name).
  final List<EnrolledStudent> enrolledStudents;
  final bool showLogo;

  /// The card's own pulsing "live" chip (the room's top row shows LIVE + the time instead, D-095).
  final bool live;


  /// Matches a live LiveKit participant against the enrolled-students list
  /// to enrich the tile with data LiveKit itself doesn't carry (photo,
  /// join/leave times) — same matching rule already used elsewhere in this
  /// file (identity==id.toString(), falling back to name).
  EnrolledStudent? _matchEnrolledStudent(Participant p) {
    for (final s in enrolledStudents) {
      if (p.identity == s.id.toString() || p.name == s.name) return s;
    }
    return null;
  }

  /// Best-effort parse of Participant.metadata as JSON, so any extra
  /// profile fields the join/token flow embeds there (email, etc.) can be
  /// shown in the profile dialog generically — see _ProfileInfoRow usage
  /// in _showParticipantProfileDialog. Returns null if metadata is empty,
  /// missing, or not valid JSON (nothing here assumes a particular shape).
  static Map<String, dynamic>? _parseMetadata(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Teacher tile always first, then every REAL, currently-connected
    // participant from the live roster — mirrors the Teams reference
    // screenshots: a grid of tiles, each a colored initials circle (or
    // photo) with a name+mic pill anchored bottom-left,
    // no separate "waiting" message once anyone's actually in the tile
    // grid (the grid itself — even with just the teacher alone — reads as
    // the meeting view, same as Teams shows just yourself before others
    // join).
    final local = room.localParticipant;
    final tiles = <_TeamsTileData>[
      _TeamsTileData(
        name: teacherName,
        isHost: true,
        isMicOn: isMicOn,
        // Real-time, not a guess: the teacher's own tile is "speaking"
        // exactly when LiveKit says so.
        isSpeaking: local?.isSpeaking ?? false,
        extra: _parseMetadata(local?.metadata),
      ),
      for (final p in room.remoteParticipants.values)
        _TeamsTileData(
          name: p.name.isNotEmpty ? p.name : p.identity,
          isHost: false,
          isGuest: isGuestIdentity(p.identity),
          // Real per-participant state from the live roster — previously
          // this was hardcoded to "always on" because EnrolledStudent
          // carries no live mic info at all.
          isMicOn: p.isMicrophoneEnabled(),
          isSpeaking: p.isSpeaking,
          imageUrl: _matchEnrolledStudent(p)?.imageUrl,
          isAttended: true, // by definition: they're in room.remoteParticipants right now
          joinDate: _matchEnrolledStudent(p)?.joinDate,
          leaveDate: _matchEnrolledStudent(p)?.leaveDate,
          extra: _parseMetadata(p.metadata),
        ),
    ];

    // ── Visuals: widgets/recording_placeholder.dart (presentational, layout-tested) ──
    // tiles[0] is this device's participant (the host when the teacher records);
    // the roster maps index i to tiles[i + 1]. The host's photo: the LiveKit token
    // carries none, so the cached signed-in user's photo is used when available.
    String? hostPhoto;
    try {
      hostPhoto = Provider.of<MyAuthProvider>(context, listen: false).currentUser?.imageUrl;
    } on ProviderNotFoundException {
      hostPhoto = null;
    }
    final me = tiles.first;
    return RecordingPlaceholderFrame(
      host: PlaceholderParticipant(
        name: me.name,
        imageUrl: me.imageUrl ?? hostPhoto,
        isHost: local == null || isHostIdentity(local.identity),
        isGuest: local != null && isGuestIdentity(local.identity),
        micOn: me.isMicOn,
        isSpeaking: me.isSpeaking,
        audioLevel: local?.audioLevel ?? 0,
      ),
      others: [
        for (final t in tiles.skip(1))
          PlaceholderParticipant(
            name: t.name,
            imageUrl: t.imageUrl,
            isGuest: t.isGuest,
            micOn: t.isMicOn,
            isSpeaking: t.isSpeaking,
          ),
      ],
      sessionTitle: sessionTitle,
      platformName: AppIdentity.instance.name,
      showLogo: showLogo,
      live: live,
      onTapHost: () => _showParticipantProfileDialog(context, me),
      onTapOther: (i) => _showParticipantProfileDialog(context, tiles[i + 1]),
      onTapOverflow: () => _showAllParticipantsDialog(context, tiles),
    );
  }
}

// Teams-style pastel avatar palette — deterministic per name (simple sum
// of code units, not cryptographic — just needs to be stable and roughly
// evenly spread) so the same person always lands on the same color across
// rebuilds and across the different tiles they might appear in.
const List<Color> _avatarPalette = [
  Color(0xFFFFD9B3), // peach
  Color(0xFFB3E5FC), // sky blue
  Color(0xFFC8E6C9), // mint
  Color(0xFFF8BBD0), // pink
  Color(0xFFFFF59D), // pale yellow
  Color(0xFFD1C4E9), // lavender
  Color(0xFFB2DFDB), // teal
];

Color _avatarColorFor(String name) {
  if (name.trim().isEmpty) return _avatarPalette[0];
  final hash = name.trim().codeUnits.fold<int>(0, (a, c) => a + c);
  return _avatarPalette[hash % _avatarPalette.length];
}

class _TeamsTileData {
  const _TeamsTileData({
    required this.name,
    required this.isHost,
    this.isGuest = false,
    required this.isMicOn,
    required this.isSpeaking,
    this.imageUrl,
    this.isAttended = false,
    this.joinDate,
    this.leaveDate,
    this.extra,
  });

  final String name;
  final bool isHost;
  final bool isGuest;
  final bool isMicOn;
  final bool isSpeaking;
  final String? imageUrl;
  final bool isAttended;
  final DateTime? joinDate;
  final DateTime? leaveDate;
  // Best-effort parsed Participant.metadata — whatever extra profile
  // fields (email, etc.) the join/token flow embeds there, if any. Shown
  // generically in the profile dialog; null if metadata was empty/absent/
  // not JSON.
  final Map<String, dynamic>? extra;
}

/// Full participant list — opened by tapping the "+N" overflow tile.
/// Every participant, tappable to drill into their profile.
void _showAllParticipantsDialog(BuildContext context, List<_TeamsTileData> tiles) {
  showDialog(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: _surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      trp('lr_participants_count', {'n': '${tiles.length}'}),
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        color: _textHigh,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: t('إغلاق', 'Close'),
                    icon: const Icon(Icons.close_rounded, color: _textLow),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _glassBdr),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: tiles.length,
                itemBuilder: (context, i) {
                  final t = tiles[i];
                  final hasPhoto = t.imageUrl != null && t.imageUrl!.isNotEmpty;
                  final initials = t.name.trim().isNotEmpty
                      ? t.name.trim()[0].toUpperCase()
                      : '؟';
                  return ListTile(
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      _showParticipantProfileDialog(context, t);
                    },
                    leading: CircleAvatar(
                      backgroundColor: _avatarColorFor(t.name),
                      backgroundImage: hasPhoto ? NetworkImage(t.imageUrl!) : null,
                      child: hasPhoto
                          ? null
                          : Text(initials,
                          style: TextStyle(
                              color: LivePalette.shade(0.87),
                              fontWeight: FontWeight.w700)),
                    ),
                    title: Text(
                      t.name,
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        color: _textHigh,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      t.isHost ? 'teacher'.tr : 'student'.tr,
                      style: TextStyle(
                          fontFamily: AppFonts.family, color: _textLow, fontSize: 12),
                    ),
                    trailing: Icon(
                      t.isMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                      size: 18,
                      color: t.isMicOn ? _textLow : _rose,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// "Premium" participant profile — opened by tapping any tile (grid or
/// full-list). Shows everything available: role, live mic/speaking state,
/// and — for students — attendance/join/leave times from EnrolledStudent.
void _showParticipantProfileDialog(BuildContext context, _TeamsTileData data) {
  final hasPhoto = data.imageUrl != null && data.imageUrl!.isNotEmpty;
  final initials = data.name.trim().isNotEmpty
      ? data.name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join()
      : '؟';
  // Server attendance times are UTC instants: shown in the platform / organization zone and 12h/24h choice.
  String fmt(DateTime? d) => d == null ? '—' : AppTime.dateTime(d.toUtc());

  showDialog(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 340,
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _glassBdr),
          boxShadow: [
            BoxShadow(
              color: _avatarColorFor(data.name).withValues(alpha: 0.25),
              blurRadius: 40,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _avatarColorFor(data.name),
                    image: hasPhoto
                        ? DecorationImage(
                        image: NetworkImage(data.imageUrl!), fit: BoxFit.cover)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: _avatarColorFor(data.name).withValues(alpha: 0.4),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: hasPhoto
                      ? null
                      : Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                          color: LivePalette.shade(0.87),
                          fontSize: 32,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                if (data.isHost)
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _cyan,
                        border: Border.all(color: _surface, width: 3),
                      ),
                      child: Icon(Icons.workspace_premium_rounded,
                          size: 14, color: LivePalette.shade(0.87)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              data.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppFonts.family,
                color: _textHigh,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: (data.isHost ? _cyan : _emerald).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: (data.isHost ? _cyan : _emerald).withValues(alpha: 0.5)),
              ),
              child: Text(
                data.isHost ? 'teacher'.tr : 'student'.tr,
                style: TextStyle(
                  fontFamily: AppFonts.family,
                  color: data.isHost ? _cyan : _emerald,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 20),
            _ProfileInfoRow(
              icon: data.isMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
              iconColor: data.isMicOn ? _emerald : _rose,
              label: 'lr_profile_mic'.tr,
              value: data.isMicOn ? 'lr_on'.tr : 'lr_off'.tr,
            ),
            _ProfileInfoRow(
              icon: Icons.graphic_eq_rounded,
              iconColor: data.isSpeaking ? _emerald : _textLow,
              label: 'status'.tr,
              value: data.isSpeaking ? 'lr_speaking_now'.tr : 'lr_inactive'.tr,
            ),
            if (!data.isHost) ...[
              _ProfileInfoRow(
                icon: Icons.how_to_reg_rounded,
                iconColor: data.isAttended ? _emerald : _textLow,
                label: 'lr_attendance'.tr,
                value: data.isAttended ? 'lr_present'.tr : 'lr_not_registered'.tr,
              ),
              _ProfileInfoRow(
                icon: DirIcons.login,
                iconColor: _textLow,
                label: 'lr_join_time'.tr,
                value: fmt(data.joinDate),
              ),
              if (data.leaveDate != null)
                _ProfileInfoRow(
                  icon: DirIcons.logout,
                  iconColor: _textLow,
                  label: 'lr_leave_time'.tr,
                  value: fmt(data.leaveDate),
                ),
            ],
            // Whatever extra profile fields Participant.metadata carried
            // (parsed best-effort in _PremiumWaitingPlaceholder.build()) —
            // email specifically labeled if present, anything else shown
            // generically by its raw key. Nothing shown at all if metadata
            // was empty/absent/not JSON (data.extra == null) — see this
            // widget's doc comment on _parseMetadata for why this can't be
            // guaranteed to exist without confirming where your app
            // actually puts this data.
            if (data.extra != null && data.extra!.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(top: 6, bottom: 2),
                child: Divider(height: 1, color: _glassBdr),
              ),
              if (data.extra!['email'] != null)
                _ProfileInfoRow(
                  icon: Icons.email_outlined,
                  iconColor: _textLow,
                  label: 'email_label'.tr,
                  value: '${data.extra!['email']}',
                ),
              for (final entry in data.extra!.entries)
                if (entry.key != 'email')
                  _ProfileInfoRow(
                    icon: Icons.info_outline_rounded,
                    iconColor: _textLow,
                    label: entry.key,
                    value: '${entry.value}',
                  ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                style: TextButton.styleFrom(
                  backgroundColor: _glass10,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'close'.tr,
                  style: TextStyle(
                      fontFamily: AppFonts.family,
                      color: _textMid,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
                fontFamily: AppFonts.family, color: _textLow, fontSize: 13),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontFamily: AppFonts.family,
              color: _textHigh,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}


class _GlassBadge extends StatelessWidget {
  const _GlassBadge({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color != null
          ? color!.withValues(alpha: 0.2)
          : LivePalette.shade(0.5),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: color != null ? color!.withValues(alpha: 0.45) : _glassBdr,
        width: 1,
      ),
      boxShadow: color != null
          ? [BoxShadow(color: color!.withValues(alpha: 0.18), blurRadius: 14)]
          : [],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color ?? _textMid),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontFamily: AppFonts.family,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color ?? _textMid,
          ),
        ),
      ],
    ),
  );
}

class _SessionEndedDialog extends StatelessWidget {
  const _SessionEndedDialog();

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    child: Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _surfaceHi,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _glassBdr, width: 1),
        boxShadow: [
          BoxShadow(color: _cyan.withValues(alpha: 0.10), blurRadius: 40),
          BoxShadow(color: LivePalette.shade(0.6), blurRadius: 20),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _rose.withValues(alpha: 0.12),
              border: Border.all(color: _rose.withValues(alpha: 0.4), width: 2),
            ),
            child: Icon(
              Icons.meeting_room_rounded,
              color: _rose,
              size: 34,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'lr_teacher_ended_title'.tr,
            style: TextStyle(
              fontFamily: AppFonts.family,
              color: _textHigh,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'lr_teacher_ended_msg'.tr,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.family,
              color: _textMid.withValues(alpha: 0.85),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_cyan, _indigo],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _cyan.withValues(alpha: 0.28),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: Text(
                'OK',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppFonts.family,
                  color: _textHigh,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

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
      LivePalette.accent.withValues(alpha: 0.07),
    );
    _blob(
      canvas,
      Offset(
        size.width * (0.84 + 0.06 * math.cos(a * 1.3)),
        size.height * (0.24 + 0.08 * math.sin(a * 0.9)),
      ),
      size.width * 0.52,
      LivePalette.accent2.withValues(alpha: 0.06),
    );
    _blob(
      canvas,
      Offset(
        size.width * (0.16 + 0.05 * math.sin(a * 0.6)),
        size.height * (0.77 + 0.05 * math.cos(a * 0.5)),
      ),
      size.width * 0.48,
      LivePalette.success.withValues(alpha: 0.04),
    );
    _blob(
      canvas,
      Offset(
        size.width * (0.87 + 0.04 * math.cos(a * 1.1)),
        size.height * (0.83 + 0.04 * math.sin(a * 0.8)),
      ),
      size.width * 0.44,
      LivePalette.danger.withValues(alpha: 0.04),
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

class NotificationChannelHelper {
  static const _channel = MethodChannel(
    'com.example.flutter_education_app/notifications',
  );
  static const String screenShareChannelId = 'livekit_screen_share';
  static const String screenShareChannelName = 'Screen Share';

  static Future<void> createScreenShareChannel() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('createNotificationChannel', {
        'channelId': screenShareChannelId,
        'channelName': screenShareChannelName,
        'channelDescription': 'Used while screen sharing is active',
        'importance': 3,
      });
    } on PlatformException catch (e) {
      log('NotificationChannelHelper: ${e.message}');
    }
  }
}
