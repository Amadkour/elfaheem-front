import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:livekit_client/livekit_client.dart';
import '../components/exts.dart';
import 'widgets/controls.dart';
import 'widgets/participant.dart';
import 'widgets/participant_info.dart';
import 'widgets/room_recorder.dart';
import 'package:permission_handler/permission_handler.dart';
import 'widgets/room_screen_share.dart';
import 'widgets/recorder_web_stub.dart'
if (dart.library.html) 'widgets/recorder_web_impl.dart' as web_rec;

// ─────────────────────────────────────────────────────────────────────────────
// Design System
// ─────────────────────────────────────────────────────────────────────────────
const _bg = Color(0xFF060810);
const _surface = Color(0xFF0E1120);
const _surfaceHi = Color(0xFF151826);
const _cyan = Color(0xFF00D4FF);
const _indigo = Color(0xFF6B6EF9);
const _emerald = Color(0xFF00E5A0);
const _rose = Color(0xFFFF4F72);
const _textHigh = Color(0xFFFFFFFF);
const _textMid = Color(0xB3FFFFFF);
const _textLow = Color(0x66FFFFFF);
const _glass10 = Color(0x1AFFFFFF);
const _glass15 = Color(0x26FFFFFF);
const _glassBdr = Color(0x30FFFFFF);
const _recRed = Color(0xFFFF4F72);

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
      List<String> studentsJoinDate,
      List<String> studentsLeaveDate,
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
      joinDate: presentDate != null ? DateTime.parse(presentDate) : null,
      leaveDate: leaveDate != null ? DateTime.parse(leaveDate) : null,
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
const _hdAudioPublishOptions = AudioPublishOptions(
  encoding: AudioEncoding(maxBitrate: 128000),
  dtx: false,
  red: true,
);

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

  // Called by RoomScreenShareMixin when iOS broadcast starts/stops.
  @override
  void onIOSBroadcastStateChanged(bool active) {
    if (!mounted) return;
    setState(() => _isBroadcastingIOS = active);
    if (active) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.screen_share_rounded, color: Colors.white, size: 16),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'يمكنك الآن فتح أي تطبيق للمشاركة',
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: _cyan,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        ),
      );
    }
  }

  bool _isBroadcastingIOS = false;

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

    _audioTapCancel = micTrack.addAudioRenderer(
      onFrame: (frame) {
        // Fire-and-forget: don't await, this fires on every audio frame
        // (dropping the returned Future rather than awaiting keeps this
        // callback from ever blocking on channel round-trip time).
        _audioFrameChannel.invokeMethod('sendAudioFrame', {
          'data': frame.data,
          'sampleRate': frame.sampleRate,
          'channels': frame.channels,
          'format': frame.format.name,
        });
      },
    );
    _tappedAudioTrack = micTrack;
    log('[REC] LiveKit audio tap: started');
  }

  void _stopLiveKitAudioTap() {
    _audioTapCancel?.call();
    _audioTapCancel = null;
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
  DateTime? _recClockStart; // wall-clock when the current run started

  // ── Total session clock ────────────────────────────────────────────────
  // Separate from the recording clock above: starts once when the room
  // connects and runs continuously for the whole session — never paused,
  // never reset, regardless of recording pause/resume/stop. Visible to
  // every participant (not gated by isTeacher like the recording badge),
  // since "how long has this session been going" is meaningful to
  // everyone, not just whoever's recording.
  Timer? _sessionClockTimer;
  int _sessionElapsedSeconds = 0;

  void _startSessionClock() {
    if (_sessionClockTimer != null) return; // already ticking — RoomConnectedEvent shouldn't fire twice, but be safe
    _sessionClockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) { _sessionClockTimer?.cancel(); _sessionClockTimer = null; return; }
      setState(() => _sessionElapsedSeconds++);
    });
  }

  String get _sessionElapsedLabel => _formatElapsed(_sessionElapsedSeconds);

  // Participant panel
  bool _showParticipants = false;
  List<EnrolledStudent> _enrolledStudents = [];
  bool _loadingStudents = false;

  // Quiz
  ActiveQuiz? _activeQuiz;
  bool _quizVisible = false;
  Timer? _quizPollTimer;
  int _currentQuestionIndex = 0;
  Map<int, int> _selectedAnswers = {};
  bool _quizSubmitted = false;
  Timer? _quizTimer;
  int _quizSecondsLeft = 0;

  // Draggable PiP
  double _pipRight = 16;
  double _pipBottom = 100;
  static const double _pipW = 120;
  static const double _pipH = 90;
  // When true, camera is the main view and the main participant is in the PiP.
  bool _pipSwapped = false;

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
    _setUpListeners();

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
    widget.room.addListener(_onRoomDidUpdate);
    _sortParticipants();

    if (lkPlatformIs(PlatformType.android)) {
      unawaited(Hardware.instance.setSpeakerphoneOn(true));
    }

    _fetchEnrolledStudents();
    if (!widget.isTeacher) _startQuizPolling();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // ── Step 1: request runtime permissions ───────────────────────────────
      // CAMERA and MICROPHONE are dangerous permissions on Android 6+.
      // PixelCopy itself needs no permission, but camera PiP and mic
      // recording require these to be granted at runtime.
      if (widget.isTeacher) {
        await _requestPermissions();
      }

      // ── Step 2: enable HD audio ────────────────────────────────────────────
      final local = widget.room.localParticipant;
      if (local != null) await _enableHdAudio(local);

      // ── Step 3: start recorder if room is already connected ────────────────
      // Handles the race where the room connected before initState() ran.
      if (widget.isTeacher &&
          widget.room.connectionState == ConnectionState.connected) {
        await _startRecorderOnce();
      }
    });
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
    _recClockStart = DateTime.now();
    _recClockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) { _recClockTimer?.cancel(); _recClockTimer = null; return; }
      setState(() => _recElapsedSeconds++);
    });
  }

  void _stopRecClock({bool pause = false}) {
    _recClockTimer?.cancel();
    _recClockTimer = null;
    if (!pause) {
      // Full stop — reset counter so next recording starts from 0.
      _recElapsedSeconds = 0;
      _recClockStart = null;
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

  @override
  void dispose() {
    widget.room.removeListener(_onRoomDidUpdate);
    unawaited(_disposeRoomAsync());
    _thumbBarAnim.dispose();
    _recDotAnim.dispose();
    _auroraAnim.dispose();
    _entryAnim.dispose();
    _panelAnim.dispose();
    _quizAnim.dispose();
    _quizPollTimer?.cancel();
    _quizTimer?.cancel();
    _recClockTimer?.cancel();
    _sessionClockTimer?.cancel();
    _liveScreenCaptureTimer?.cancel();
    _webPlaceholderDebounce?.cancel();
    // Recorder: if user exits without pressing End Session (e.g. back-swipe),
    // stop the camera fast and drain remaining uploads in the background.
    if (_recorder != null) {
      final rec = _recorder!;
      _recorder = null;
      _stopLiveKitAudioTap();
      unawaited(_drainAndDispose(rec));
    }
    super.dispose();
  }

  Future<void> _disposeRoomAsync() async {
    await _listener.dispose();
    await widget.room.dispose();
  }

  // ── End session ───────────────────────────────────────────────────────────
  //
  // Mobile: stopRecordingOnly() → ACTION_STOP (fast, < 200ms) → pop immediately.
  //   The native FGS drains remaining uploads independently and calls stopSelf()
  //   only after all pendingUploads reach zero (up to 120s).
  //   _drainAndDispose runs unawaited and waits for RecState.done via polling.
  //
  // Web: stopRecordingOnly() now only stops the LOCAL recorder/compositor —
  //   it no longer waits for chunk uploads to finish (see WebRecorder.stop()
  //   in recorder_web_impl.dart), so this resolves in well under a second.
  //   Any chunks still queued/uploading, AND the widget.onEnd() call itself
  //   (which hits the server's /live-sessions/{id}/end endpoint — an
  //   endpoint that can itself wait up to ~150s server-side for the
  //   recording to finish processing), both run in the background below
  //   instead of blocking this function. The server tolerates the client
  //   moving on before the final chunk lands (see local_recorder.py's
  //   assembly pipeline), so there's nothing left that genuinely needs the
  //   teacher's screen to stay frozen while waiting on either of them.
  Future<dynamic> _endSessionWithRecording() async {
    if (_endingSession) return null;
    if (mounted) setState(() => _endingSession = true);

    final rec = _recorder;
    _recorder = null; // detach so dispose() never interferes

    if (widget.isTeacher &&
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
          'لم يتم حفظ أي تسجيل لهذه الجلسة بسبب مشكلة تقنية في التسجيل، '
              'حتى لو تمت مشاركة الشاشة أو الكاميرا. يرجى إبلاغ الدعم الفني.',
        );
      }

      // Drains any remaining chunk uploads / native state and disposes the
      // recorder, entirely in the background — the teacher's screen has
      // already moved on by the time this finishes.
      unawaited(_drainAndDispose(rec));
    }

    // Fire the end-session call but do NOT let the UI wait on it — see the
    // comment above the function for why awaiting it here would freeze the
    // screen. Errors are only logged; there's no UI left waiting to react
    // to them since the teacher has already left this screen.
    unawaited(
      widget.onEnd().catchError((e) {
        log('[REC] onEnd error: $e');
      }),
    );

    if (mounted) Navigator.pop(context);
    if (mounted) Navigator.pop(context);
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
    if (_loadingStudents) return;
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
          .map<String>((p) => p['join_date'] as String)
          .toList();
      final leaves = participants
          .map<String>((p) => p['leave_date'] as String)
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

  // ── Quiz polling ───────────────────────────────────────────────────────────
  void _startQuizPolling() {
    _quizPollTimer = Timer.periodic(
      const Duration(seconds: 30),
          (_) => _pollActiveQuiz(),
    );
    _pollActiveQuiz();
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
      autoSubmit ? 'Quiz auto-submitted (time up).' : 'Quiz submitted!',
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

  /// Whoever currently has isSpeaking==true, preferring the loudest
  /// (highest audioLevel) if more than one. Falls back to the teacher
  /// (local participant) when nobody is actively speaking, since the
  /// teacher is the default presenter. Used by _PremiumWaitingPlaceholder's
  /// live call site — its value flows into the recording "for free" since
  /// the recording now screenshots that exact widget on every capture tick.
  String _activeSpeakerName() {
    final local = widget.room.localParticipant;
    final all = <Participant>[
      if (local != null) local,
      ...widget.room.remoteParticipants.values,
    ];
    final speaking = all.where((p) => p.isSpeaking).toList()
      ..sort((a, b) => b.audioLevel.compareTo(a.audioLevel));
    final speaker = speaking.firstOrNull ?? local;
    final name = speaker?.name ?? '';
    return name.isNotEmpty ? name : (speaker?.identity ?? '');
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
      if (widget.isTeacher) await _startRecorderOnce();
    })
    ..on<RoomDisconnectedEvent>((event) async {
      log('Room disconnected: reason => ${event.reason}');
      final isTeacherEnd =
          event.reason == DisconnectReason.roomDeleted ||
              event.reason == DisconnectReason.serverShutdown;
      WidgetsBindingCompatible.instance?.addPostFrameCallback((_) async {
        if (isTeacherEnd && !widget.isTeacher && mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const _SessionEndedDialog(),
          );
        }
        if (mounted) Navigator.pop(context);
        if (mounted) Navigator.pop(context);
      });
    })
    ..on<ParticipantEvent>((_) {
      _sortParticipants();
      _maybeSyncLiveScreenCapture();
      _maybeRefreshWebPlaceholder();
    })
    ..on<RoomRecordingStatusChanged>((event) {
      if (mounted) setState(() => _serverRecording = event.activeRecording);
      unawaited(
        context.showRecordingStatusChangedDialog(event.activeRecording),
      );
    })
    ..on<RoomAttemptReconnectEvent>(
          (e) => log('Reconnect ${e.attempt}/${e.maxAttemptsRetry}'),
    )
    ..on<LocalTrackPublishedEvent>((_) {
      _sortParticipants();
      // Cheap no-op if already bound to the current mic track (see
      // _startLiveKitAudioTap's identical() check) — but if screen-share
      // negotiation (or anything else) caused LiveKit to republish the mic
      // as a new LocalAudioTrack instance, this is what catches it and
      // rebinds, instead of the recording silently losing mic audio for
      // the rest of the session with no error anywhere.
      if (widget.isTeacher) _startLiveKitAudioTap();
    })
    ..on<LocalTrackUnpublishedEvent>((_) => _sortParticipants())
    ..on<TrackSubscribedEvent>((event) {
      _sortParticipants();
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
      if (kIsWeb && widget.isTeacher && event.track is RemoteAudioTrack) {
        final nativeStream = web_rec.nativeAudioStreamFromTrack(
          (event.track as RemoteAudioTrack).mediaStreamTrack,
        );
        _recorder?.addRemoteAudioStream(event.participant.sid, nativeStream);
      }
    })
    ..on<TrackUnsubscribedEvent>((event) {
      _sortParticipants();
      if (kIsWeb && widget.isTeacher && event.track is RemoteAudioTrack) {
        _recorder?.removeRemoteAudioStream(event.participant.sid);
      }
      if (!widget.isTeacher &&
          event.participant.sid == widget.room.localParticipant?.sid) {
        log('Local track unsubscribed — auto-ending session');
        unawaited(_autoEndSession());
      }
    })
    ..on<TrackMutedEvent>((_) => _sortParticipants())
    ..on<TrackUnmutedEvent>((_) => _sortParticipants())
    ..on<TrackE2EEStateEvent>((e) => log('e2ee: $e'))
    ..on<ParticipantNameUpdatedEvent>((e) {
      log('Name: ${e.participant.identity} → ${e.name}');
      _sortParticipants();
    })
    ..on<DataReceivedEvent>((event) {
      String decoded = 'Failed to decode';
      try {
        decoded = utf8.decode(event.data);
      } catch (e) {
        log('Decode: $e');
      }
      unawaited(context.showDataReceivedDialog(decoded));
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
    if (!kIsWeb || !widget.isTeacher) return;
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
    if (!kIsWeb || !widget.isTeacher) return;
    _webPlaceholderDebounce?.cancel();
    _webPlaceholderDebounce = Timer(
      const Duration(milliseconds: 1200),
          () => unawaited(_sendLiveScreenPlaceholderWeb()),
    );
  }

  Future<void> _startRecorderOnce() async {
    if (_recorderStarted) return;
    _recorderStarted = true;

    _recorder = ClientRecorder(
      sessionId: widget.sessionId,
      apiClient: widget.apiClient,
    );
    _recorder!.addListener(_onRecorderUpdate);
    _recorder!.onNoMediaWarning = () {
      if (!mounted) return;
      _showSnack(
        'تعذر الوصول إلى الكاميرا أو الميكروفون — سيتم تسجيل مشاركة الشاشة '
            'فقط عند بدئها. تأكد من عدم استخدام الكاميرا/الميكروفون في تطبيق آخر.',
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
      final sessionTitle = widget.sessionName ?? 'حصة مباشرة';
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

  Future<void> _autoEndSession() async {
    try {
      await widget.onEnd();
      await widget.room.disconnect();
    } catch (e) {
      log('autoEndSession error: $e');
    }
  }

  void _onRoomDidUpdate() => _sortParticipants();

  bool _hasVideoTrack(TrackPublication pub) => pub.track is VideoTrack;

  VideoTrack? _getVideoTrack(TrackPublication pub) {
    final t = pub.track;
    return t is VideoTrack ? t : null;
  }

  void _sortParticipants() {
    final userMedia = <ParticipantTrack>[];
    final screenTracks = <ParticipantTrack>[];

    for (final p in widget.room.remoteParticipants.values) {
      for (final t in p.videoTrackPublications) {
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

    userMedia.sort((a, b) {
      if (a.participant.isSpeaking && b.participant.isSpeaking) {
        return a.participant.audioLevel > b.participant.audioLevel ? -1 : 1;
      }
      final as_ = a.participant.lastSpokeAt?.millisecondsSinceEpoch ?? 0;
      final bs_ = b.participant.lastSpokeAt?.millisecondsSinceEpoch ?? 0;
      if (as_ != bs_) return as_ > bs_ ? -1 : 1;
      if (a.participant.hasVideo != b.participant.hasVideo) {
        return a.participant.hasVideo ? -1 : 1;
      }
      return a.participant.joinedAt.millisecondsSinceEpoch -
          b.participant.joinedAt.millisecondsSinceEpoch;
    });

    ParticipantTrack? localCamera;
    final localScreen = <ParticipantTrack>[];
    final localPubs = widget.room.localParticipant?.videoTrackPublications;
    if (localPubs != null) {
      for (final t in localPubs) {
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

    final allScreen = [...screenTracks, ...localScreen];
    final ordered = allScreen.isNotEmpty
    ? [...allScreen, ?localCamera, ...userMedia]
        : [?localCamera, ...userMedia];

    if (mounted) setState(() => participantTracks = ordered);
    if (ordered.length > 1) {
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
      if (pub.isScreenShare) {
        final t = pub.track;
        if (t is VideoTrack) return t;
      }
    }
    return null;
  }

  VideoTrack? _resolveCameraTrack(Participant p) {
    for (final pub in p.videoTrackPublications) {
      if (!pub.isScreenShare) {
        final t = pub.track;
        if (t is VideoTrack) return t;
      }
    }
    return null;
  }

  bool get _isScreenShareMain =>
      participantTracks.isNotEmpty &&
          participantTracks.first.type == ParticipantTrackType.kScreenShare;

  // ── Helpers ────────────────────────────────────────────────────────────────
  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: _textHigh)),
        backgroundColor: _surfaceHi,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool isDanger = false,
  }) => showDialog<bool>(
    context: context,
    builder: (ctx) => _StyledDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      isDanger: isDanger,
    ),
  );

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

  bool _isStudentOnline(EnrolledStudent s) => widget
      .room
      .remoteParticipants
      .values
      .any((p) => p.identity == s.id.toString() || p.name == s.name);

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Defensive: also ensured here, not just from the RoomConnectedEvent
    // handler — idempotent (no-ops once already running), and safe to call
    // during build since it only schedules a Timer, it doesn't call
    // setState() synchronously. Guards against any edge case where that
    // event fires before this State object's listeners are fully wired up.
    _startSessionClock();
    return Theme(
      data: ThemeData.dark(),
      child: Scaffold(
        backgroundColor: _bg,
        // RepaintBoundary around the WHOLE body (not just the video area)
        // is what makes the Android recording placeholder an actual
        // screenshot of the entire live screen — aurora background,
        // recording indicator, thumbnail strip, PiP, the main video/
        // waiting card, AND the controls bar — instead of just the video
        // stage. See _captureAndSendLiveScreen.
        body: RepaintBoundary(
          key: _liveScreenCaptureKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Aurora background
              AnimatedBuilder(
                animation: _auroraAnim,
                builder: (_, _) => CustomPaint(
                  painter: _AuroraPainter(_auroraAnim.value),
                  child: const SizedBox.expand(),
                ),
              ),

              // Main content
              SafeArea(
                child: FadeTransition(
                  opacity: _entryFade,
                  child: Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (ctx, constraints) => Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(20),
                                ),
                                child: _buildMainVideo(),
                              ),

                              // Thumbnail strip
                              if (participantTracks.length > 1 &&
                                  !_isScreenShareMain)
                                FadeTransition(
                                  opacity: _thumbBarFade,
                                  child: Positioned(
                                    top: 12,
                                    left: 0,
                                    right: 0,
                                    child: SizedBox(
                                      height: 108,
                                      child: ListView.builder(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        scrollDirection: Axis.horizontal,
                                        itemCount: participantTracks.length - 1,
                                        itemBuilder: (_, i) => _ThumbnailCard(
                                          track: participantTracks[i + 1],
                                          resolveScreenTrack: _resolveScreenTrack,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                              // PiP
                              _buildDraggablePip(constraints),

                              // Recording indicators
                              _buildRecordingIndicator(),

                              // iOS broadcast share banner + stop button
                              if (widget.isTeacher)
                                _buildIOSShareBanner(),

                              // Participant count badge
                              Positioned(
                                bottom: 14,
                                right: _isScreenShareMain
                                    ? _pipRight + _pipW + 8
                                    : 14,
                                child: GestureDetector(
                                  onTap: _toggleParticipantPanel,
                                  child: _GlassBadge(
                                    icon: Icons.people_rounded,
                                    label:
                                    '${widget.room.remoteParticipants.length + 1}',
                                    color: _showParticipants ? _cyan : null,
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

                      // Controls bar
                      if(widget.room.localParticipant!=null)
                        SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 1),
                            end: Offset.zero,
                          ).animate(_entrySlide),
                          child: _buildControlsBar(),
                        ),
                    ],
                  ),
                ),
              ),

              // Participant panel
              if (_showParticipants) _buildParticipantPanel(),

              // ── Ending-session overlay ───────────────────────────────────────
              // Shown while we wait for the final recording chunk to upload
              // before calling onEnd(). Prevents teacher from navigating away
              // prematurely and blocks UI interaction during the wait.
              if (_endingSession)
                Container(
                  color: Colors.black.withValues(alpha: 0.72),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 28,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
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
                          const CircularProgressIndicator(
                            color: _cyan,
                            strokeWidth: 2.5,
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'جارٍ حفظ التسجيل…',
                            style: TextStyle(
                              fontFamily: 'tajawal',
                              color: Colors.white,
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
                                'الجزء ${r.uploadedChunks} · $mb MB',
                                style: TextStyle(
                                  fontFamily: 'tajawal',
                                  color: Colors.white.withValues(alpha: 0.55),
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
    final local = widget.room.localParticipant;

    if (_pipSwapped && widget.isTeacher) {
      // Swapped: show teacher's own camera in the main area.
      final localEntry = participantTracks
          .where((t) =>
      t.participant == local &&
          t.type != ParticipantTrackType.kScreenShare)
          .firstOrNull;
      if (localEntry != null) {
        final cameraTrack = _resolveCameraTrack(localEntry.participant);
        if (cameraTrack != null) {
          return VideoTrackRenderer(
            cameraTrack,
            renderMode: VideoRenderMode.texture,
            fit: VideoViewFit.contain,
          );
        }
      }
    }

    // For teacher: filter out local camera from the main track list so the
    // main area always shows remote participants or a placeholder.
    final mainTracks = widget.isTeacher
        ? participantTracks.where((t) =>
    !(t.participant == local &&
        t.type != ParticipantTrackType.kScreenShare)).toList()
        : participantTracks;

    if (mainTracks.isEmpty) {
      // Mirror the recording's fallback order (see recorder_compositor.js's
      // draw loop): screen share > full-screen camera > placeholder. Before
      // this, an enabled camera never appeared here at all — only in the
      // small PiP corner — so the placeholder showed even while the
      // teacher's own camera was live. Now, with no screen share and no
      // other participant showing video, an enabled camera fills the main
      // view instead; the placeholder is reserved for when nothing at all
      // is available, same as the recorded output.
      final isMicOn = local?.isMicrophoneEnabled() ?? false;
      final isCamOn = local?.isCameraEnabled() ?? false;

      if (!_pipSwapped && isCamOn) {
        final cameraTrack = local != null ? _resolveCameraTrack(local) : null;
        if (cameraTrack != null) {
          return VideoTrackRenderer(
            cameraTrack,
            renderMode: VideoRenderMode.texture,
            fit: VideoViewFit.cover,
          );
        }
      }

      // Premium placeholder — shown only when there's truly nothing to
      // display: no screen share, no other participant's video, and no
      // (or not-yet-ready) local camera.
      final teacherName = local?.name ?? local?.identity ?? 'Teacher';
      return _PremiumWaitingPlaceholder(
        teacherName: teacherName,
        isMicOn: isMicOn,
        isCamOn: isCamOn,
        auroraAnim: _auroraAnim,
        sessionTitle: widget.sessionName,
        speakerName: _activeSpeakerName(),
        participants: _enrolledStudents.where((s) => s.isAttended).toList(),
        // Shown live too now (not just in the recording) — since the
        // recording is a direct screenshot of this exact widget, true
        // parity means whatever appears in the recording appears live,
        // and vice versa. A small corner logo live is a reasonable,
        // unobtrusive touch; revert to the default (false) if you'd
        // rather keep it recording-only.
        showLogo: true,
      );
    }

    final main = mainTracks.first;
    if (main.type == ParticipantTrackType.kScreenShare) {
      return _PremiumScreenShareView(
        participant: main.participant,
        resolveScreenTrack: _resolveScreenTrack,
        auroraAnim: _auroraAnim,
      );
    }
    return ParticipantWidget.widgetFor(main, showStatsLayer: false);
  }

  // ── PiP ────────────────────────────────────────────────────────────────────
  //
  // Always shows the teacher's own camera feed in the corner (PiP).
  // Tapping PiP swaps main and PiP content (camera ↔ remote/placeholder).
  // Draggable to any corner of the screen.
  Widget _buildDraggablePip(BoxConstraints constraints) {
    final local = widget.room.localParticipant;

    // For teacher: always show local camera in PiP.
    // For student: only show PiP if local camera track is available.
    final localEntry = participantTracks
        .where((t) =>
    t.participant == local &&
        t.type != ParticipantTrackType.kScreenShare)
        .firstOrNull;

    final cameraTrack = localEntry != null
        ? _resolveCameraTrack(localEntry.participant)
        : null;

    // For teacher, show PiP even when camera track is null (shows off icon).
    // For student, hide PiP if no camera track.
    if (cameraTrack == null && !widget.isTeacher) return const SizedBox.shrink();
    // Hide entirely if teacher has no camera and not swapped.
    if (cameraTrack == null && !_pipSwapped) return const SizedBox.shrink();

    // In swapped mode: PiP shows the remote/main content;
    // In normal mode: PiP shows the local camera.
    final mainTracks = widget.isTeacher
        ? participantTracks.where((t) =>
    !(t.participant == local &&
        t.type != ParticipantTrackType.kScreenShare)).toList()
        : participantTracks;

    // When there's no screen share/remote content, an enabled camera is
    // already shown full-screen as the main view's fallback (see
    // _buildMainVideo) — showing that same feed again in the small PiP
    // corner would just be a redundant duplicate, so the PiP hides itself
    // in exactly that state instead.
    //
    // BUG FIX: mainTracks deliberately excludes the local participant's
    // own non-screen-share track, but it never counted the local
    // participant's own screen-share track either (participantTracks
    // doesn't surface "your own share" as a tile to yourself) — so while
    // actively sharing with no other participants' video around,
    // mainTracks came back empty and this fired even though the main view
    // was NOT showing the camera at all (it shows a "sharing" placeholder
    // instead), hiding the only place the camera was visible. isSharing
    // must be part of this check, not just whether other tracks exist.
    final isSharing = local?.isScreenShareEnabled() == true;
    if (!_pipSwapped && !isSharing && mainTracks.isEmpty && cameraTrack != null) {
      return const SizedBox.shrink();
    }

    final pipTrack = _pipSwapped && mainTracks.isNotEmpty ? mainTracks.first : null;

    return Positioned(
      right: _pipRight,
      bottom: _pipBottom,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _pipRight = (_pipRight - d.delta.dx).clamp(
            8.0,
            constraints.maxWidth - _pipW - 8.0,
          );
          _pipBottom = (_pipBottom - d.delta.dy).clamp(
            8.0,
            constraints.maxHeight - _pipH - 8.0,
          );
        }),
        onTap: () => setState(() => _pipSwapped = !_pipSwapped),
        child: Container(
          width: _pipW,
          height: _pipH,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _cyan.withValues(alpha: 0.5), width: 1.5),
            boxShadow: [
              BoxShadow(color: _cyan.withValues(alpha: 0.18), blurRadius: 20),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12.5),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Video content
                if (_pipSwapped && pipTrack != null)
                  AbsorbPointer(
                    child: ParticipantWidget.widgetFor(
                      pipTrack,
                      showStatsLayer: false,
                    ),
                  )
                else if (!_pipSwapped && cameraTrack != null)
                  AbsorbPointer(
                    child: VideoTrackRenderer(
                      cameraTrack,
                      renderMode: VideoRenderMode.texture,
                      fit: VideoViewFit.contain,
                    ),
                  )
                else
                  Container(
                    color: _surface,
                    child: Icon(
                      Icons.videocam_off_rounded,
                      size: 22,
                      color: _cyan.withValues(alpha: 0.4),
                    ),
                  ),

                // Swap icon — always visible so intent is clear
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.swap_calls_rounded,
                      size: 13,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),

                // Drag handle — subtle bar at top-centre
                Positioned(
                  top: 5,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 28,
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ],
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
            color: const Color(0xFF0E1120),
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
                    decoration: const BoxDecoration(
                      color: _cyan,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.screen_share_rounded, color: _cyan, size: 16),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'جارٍ مشاركة الشاشة',
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              // Elapsed recording time shown here too
              if (_recElapsedSeconds > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    _recElapsedLabel,
                    style: const TextStyle(
                      fontFamily: 'tajawal',
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
                  child: const Text(
                    'إيقاف المشاركة',
                    style: TextStyle(
                      fontFamily: 'tajawal',
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

  // ── Recording indicator ────────────────────────────────────────────────────
  //
  // Top-right corner, stacked vertically:
  //   1. Server REC badge  — LiveKit egress, visible to all participants
  //   2. Client REC badge  — teacher only, shows live elapsed time + state
  Widget _buildRecordingIndicator() {
    final badges = <Widget>[];

    // ── Total session time — everyone, always (not just teacher/recording) ──
    if (_sessionClockTimer != null) {
      badges.add(
        _RecBadge(
          dotColor: _textMid,
          dotOpacity: 1.0,
          pulsing: false,
          icon: Icons.schedule_rounded,
          children: [
            Text(
              _sessionElapsedLabel,
              style: const TextStyle(
                fontFamily: 'tajawal',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _textMid,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      );
    }

    // ── Server egress badge ───────────────────────────────────────────────────
    if (_serverRecording) {
      badges.add(
        AnimatedBuilder(
          animation: _recDotAnim,
          builder: (_, _) => _RecBadge(
            dotColor: _recRed,
            dotOpacity: _recDotOpacity.value,
            pulsing: true,
            children: const [
              Text(
                'REC',
                style: TextStyle(
                  fontFamily: 'tajawal',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _recRed,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Client recorder badge (teacher only) ──────────────────────────────────
    if (widget.isTeacher && _recorder != null) {
      final rec   = _recorder!;
      final state = rec.state;

      if (state != RecState.idle) {
        final Color  dotColor;
        final bool   pulsing;
        final String stateLabel;
        final String timeLabel  = _recElapsedLabel;
        final String chunkLabel = '${rec.uploadedChunks}↑';
        final String mbLabel    =
            '${(rec.totalBytes / 1024 / 1024).toStringAsFixed(1)}MB';

        switch (state) {
          case RecState.starting:
            dotColor   = _textLow;
            pulsing    = false;
            stateLabel = 'جارٍ البدء…';
          case RecState.recording:
            dotColor   = _emerald;
            pulsing    = true;
            stateLabel = 'تسجيل';
          case RecState.paused:
            dotColor   = const Color(0xFFFFB800);
            pulsing    = false;
            stateLabel = '⏸ متوقف';
          case RecState.uploading:
            dotColor   = const Color(0xFFFFB800);
            pulsing    = false;
            stateLabel = 'رفع…';
          case RecState.done:
            dotColor   = _emerald;
            pulsing    = false;
            stateLabel = '✓ محفوظ';
          case RecState.error:
            dotColor   = _rose;
            pulsing    = false;
            stateLabel = 'خطأ';
          default:
            dotColor   = _textLow;
            pulsing    = false;
            stateLabel = '';
        }

        badges.add(
          AnimatedBuilder(
            animation: _recDotAnim,
            builder: (_, _) => _RecBadge(
              dotColor:   dotColor,
              dotOpacity: pulsing ? _recDotOpacity.value : 1.0,
              pulsing:    pulsing,
              children: [
                // State label
                Text(
                  stateLabel,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: dotColor,
                    letterSpacing: 0.3,
                  ),
                ),
                // Elapsed time — shown while recording or paused
                if (state == RecState.recording || state == RecState.paused) ...[
                  Container(
                    width: 1,
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    color: dotColor.withValues(alpha: 0.35),
                  ),
                  Text(
                    timeLabel,
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: dotColor,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
                // Upload progress — always shown when not idle/error
                if (state != RecState.starting &&
                    state != RecState.done &&
                    state != RecState.error) ...[
                  Container(
                    width: 1,
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    color: dotColor.withValues(alpha: 0.25),
                  ),
                  Text(
                    '$chunkLabel $mbLabel',
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: dotColor.withValues(alpha: 0.7),
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }
    }

    if (badges.isEmpty) return const SizedBox.shrink();
    return Positioned(
      top: 14,
      right: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: badges
            .map((w) => Padding(padding: const EdgeInsets.only(bottom: 6), child: w))
            .toList(),
      ),
    );
  }

  // ── Controls bar ──────────────────────────────────────────────────────────
  Widget _buildControlsBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
      decoration: BoxDecoration(
        color: _surfaceHi.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _glassBdr, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
          BoxShadow(color: _cyan.withValues(alpha: 0.05), blurRadius: 20),
        ],
      ),
      child:
      ControlsWidget(
        widget.room,
        widget.room.localParticipant!,
        // End session goes through our recorder-aware wrapper
        onEndSession: _endSessionWithRecording,
        isTeacher: widget.isTeacher,
        onToggleScreenShare: toggleScreenShare,
        // ── NEW: pause / resume ──────────────────────────────────
        // Null when the action is not available (wrong state, or
        // a transition is already in flight) — ControlsWidget
        // disables the button automatically when the callback is null.
        onPauseRecording: (widget.isTeacher &&
            _recorder?.state == RecState.recording &&
            !_isPausingRecording &&
            !_endingSession)
            ? _pauseRecording
            : null,
        onResumeRecording: (widget.isTeacher &&
            _recorder?.state == RecState.paused &&
            !_isResumingRecording &&
            !_endingSession)
            ? _resumeRecording
            : null,
        recorderState: widget.isTeacher ? _recorder?.state : null,
      ),
    );
  }

  // ── Participant panel ──────────────────────────────────────────────────────
  Widget _buildParticipantPanel() {
    final liveIdentities = widget.room.remoteParticipants.values
        .map((p) => p.identity)
        .toSet();

    return Positioned.fill(
      child: GestureDetector(
        onTap: _toggleParticipantPanel,
        child: Container(color: Colors.black.withValues(alpha: 0.45)),
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: _glassBdr)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.people_rounded, color: _cyan, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'Participants',
                        style: TextStyle(
                          fontFamily: 'tajawal',
                          color: _textHigh,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      if (_loadingStudents)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _cyan,
                          ),
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

                // Teacher row
                _ParticipantRow(
                  name: widget.room.localParticipant?.name ?? 'You',
                  isOnline: true,
                  isTeacher: true,
                  isAttended: true,
                  micOn:
                  widget.room.localParticipant?.isMicrophoneEnabled() ??
                      false,
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
                        'Students (${_enrolledStudents.length})',
                        style: TextStyle(
                          fontFamily: 'tajawal',
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
                          '${_enrolledStudents.where((s) => s.isAttended).length} attended',
                          style: TextStyle(
                            fontFamily: 'tajawal',
                            color: _emerald,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Student list
                Expanded(
                  child: _enrolledStudents.isEmpty
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
                          'No students enrolled',
                          style: TextStyle(
                            fontFamily: 'tajawal',
                            color: _textLow,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                      : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _enrolledStudents.length,
                    itemBuilder: (ctx, i) {
                      final s = _enrolledStudents[i];
                      final online =
                          liveIdentities.contains(s.id.toString()) ||
                              liveIdentities.contains(s.name);
                      final rp = widget.room.remoteParticipants.values
                          .firstWhereOrNull(
                            (p) =>
                        p.identity == s.id.toString() ||
                            p.name == s.name,
                      );
                      return _ParticipantRow(
                        name: s.name,
                        isOnline: online,
                        isTeacher: false,
                        isAttended: s.isAttended,
                        joinDate: s.joinDate,
                        leaveDate: s.leaveDate,
                        micOn: rp?.isMicrophoneEnabled() ?? false,
                        camOn: rp?.isCameraEnabled() ?? false,
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
        color: Colors.black.withValues(alpha: 0.80),
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
                      color: Colors.black.withValues(alpha: 0.6),
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
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.quiz_rounded, size: 13, color: _cyan),
                    SizedBox(width: 5),
                    Text(
                      'LIVE QUIZ',
                      style: TextStyle(
                        fontFamily: 'tajawal',
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
                        fontFamily: 'tajawal',
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
                'Question ${_currentQuestionIndex + 1} of ${quiz.questions.length}',
                style: TextStyle(
                  fontFamily: 'tajawal',
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
                    valueColor: const AlwaysStoppedAnimation(_cyan),
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
                        ? const Icon(Icons.check_rounded, size: 13, color: _bg)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      q.options[idx],
                      style: TextStyle(
                        fontFamily: 'tajawal',
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
                      child: const Row(
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
                              fontFamily: 'tajawal',
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
                      gradient: const LinearGradient(
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
            child: const Icon(Icons.check_rounded, color: _emerald, size: 36),
          ),
          const SizedBox(height: 18),
          const Text(
            'Quiz Submitted!',
            style: TextStyle(
              fontFamily: 'tajawal',
              color: _textHigh,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You answered $answered of ${quiz.questions.length} questions.',
            style: TextStyle(
              fontFamily: 'tajawal',
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
                gradient: const LinearGradient(colors: [_cyan, _indigo]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _cyan.withValues(alpha: 0.3),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: const Text(
                'Back to Room',
                style: TextStyle(
                  fontFamily: 'tajawal',
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
// _RecBadge — compact glass pill used in the recording indicator
// ─────────────────────────────────────────────────────────────────────────────
class _RecBadge extends StatelessWidget {
  const _RecBadge({
    required this.dotColor,
    required this.dotOpacity,
    required this.pulsing,
    required this.children,
    this.icon,
  });

  final Color        dotColor;
  final double       dotOpacity;   // 0..1, driven by _recDotOpacity animation
  final bool         pulsing;
  final List<Widget> children;
  // When set, shown instead of the dot — for badges that aren't a
  // recording/live status indicator (e.g. the total session-time badge).
  final IconData?    icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dotColor.withValues(
            alpha: pulsing ? (0.28 + 0.38 * dotOpacity) : 0.40,
          ),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: dotColor.withValues(alpha: pulsing ? 0.12 * dotOpacity : 0.08),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 11, color: dotColor.withValues(alpha: 0.9))
          else
          // Pulsing / static dot
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor.withValues(
                  alpha: pulsing ? (0.38 + 0.62 * dotOpacity) : 0.9,
                ),
              ),
            ),
          const SizedBox(width: 6),
          ...children,
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
  });

  final String name;
  final bool isOnline;
  final bool isTeacher;
  final bool isAttended;
  final bool micOn;
  final bool camOn;
  final DateTime? joinDate;
  final DateTime? leaveDate;

  String _fmtDuration(DateTime? from, DateTime? to) {
    if (from == null) return '';
    final end = to ?? DateTime.now();
    final mins = end.difference(from).inMinutes;
    if (mins < 60) return '${mins}m';
    return '${mins ~/ 60}h ${mins % 60}m';
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
                      fontFamily: 'tajawal',
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
                      _MiniTag(label: 'Teacher', color: _cyan)
                    else ...[
                      _MiniTag(
                        label: isAttended ? 'Attended' : 'Absent',
                        color: isAttended ? _emerald : _rose,
                      ),
                      if (isOnline) ...[
                        const SizedBox(width: 4),
                        _MiniTag(label: 'Online', color: _emerald),
                      ],
                    ],
                  ],
                ),
                // Join → leave duration (clean, no debug prints)
                if (joinDate != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    isOnline
                        ? 'Joined ${_fmtDuration(joinDate, null)} ago'
                        : leaveDate != null
                        ? 'Stayed ${_fmtDuration(joinDate, leaveDate)}'
                        : '',
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      color: _textLow,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Mic / cam
          if (isOnline && !isTeacher) ...[
            Icon(
              micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
              size: 14,
              color: micOn ? Colors.white54 : _rose.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 6),
            Icon(
              camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              size: 14,
              color: camOn ? Colors.white54 : _rose.withValues(alpha: 0.7),
            ),
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
        fontFamily: 'tajawal',
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
  const _ThumbnailCard({required this.track, required this.resolveScreenTrack});

  final ParticipantTrack track;
  final VideoTrack? Function(Participant) resolveScreenTrack;

  @override
  Widget build(BuildContext context) {
    final isScreen = track.type == ParticipantTrackType.kScreenShare;
    final screenTrack = isScreen ? resolveScreenTrack(track.participant) : null;
    final isSpeaking = track.participant.isSpeaking;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 152,
      height: 108,
      margin: const EdgeInsets.only(right: 8),
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
            color: Colors.black.withValues(alpha: 0.45),
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
            if (isScreen && screenTrack != null)
              AbsorbPointer(
                child: VideoTrackRenderer(
                  key: ValueKey(screenTrack.sid),
                  screenTrack,
                  renderMode: VideoRenderMode.auto,
                  fit: VideoViewFit.contain,
                ),
              )
            else
              ParticipantWidget.widgetFor(track, showStatsLayer: false),
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
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    if (isScreen)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
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
                        margin: const EdgeInsets.only(left: 4),
                        decoration: const BoxDecoration(
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

  const _PremiumScreenShareView({
    required this.participant,
    required this.resolveScreenTrack,
    required this.auroraAnim,
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
    _borderGlowAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
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
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.3),
              radius: 1.2,
              colors: [Color(0xFF0D1533), Color(0xFF060810)],
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
                    ? VideoTrackRenderer(
                  screenTrack,
                  renderMode: VideoRenderMode.auto,
                  fit: VideoViewFit.contain,
                )
                    : _ScreenShareLoadingPlaceholder(
                  presenterName: presenterName,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 20,
          left: 20,
          child: _PresenterBadge(name: presenterName, isSpeaking: isSpeaking),
        ),
        Positioned(top: 20, right: 20, child: const _ScreenShareLiveBadge()),
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
          : Colors.black.withValues(alpha: 0.55),
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
        Text(
          name,
          style: TextStyle(
            fontFamily: 'tajawal',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSpeaking ? _cyan : _textMid,
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
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.screen_share_rounded, size: 13, color: Colors.white),
        SizedBox(width: 6),
        Text(
          'SCREEN',
          style: TextStyle(
            fontFamily: 'tajawal',
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.white,
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
            Colors.black.withValues(alpha: 0.85),
            Colors.black.withValues(alpha: 0.55),
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
              gradient: const LinearGradient(
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
                  color: Colors.white,
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
                  'Sharing screen',
                  style: TextStyle(
                    fontFamily: 'tajawal',
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
    color: const Color(0xFF0A0F20),
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
          child: const Icon(
            Icons.screen_share_rounded,
            size: 32,
            color: _indigo,
          ),
        ),
        const SizedBox(height: 18),
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: _cyan),
        ),
        const SizedBox(height: 14),
        Text(
          '$presenterName is sharing their screen',
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
            fontFamily: 'tajawal',
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
// _PremiumWaitingPlaceholder  — Teams-style no-content placeholder
// Shows teacher avatar, name, A/V status chips, and a "Waiting for students"
// message with animated aurora + pulse ring — all matching the room design.
//
// Also reused, unchanged, as the frozen recording placeholder on Android
// (see _captureAndSendLiveScreen / _sendLiveScreenPlaceholderWeb) — this is the single source of truth for
// "what does the app show when there's nothing else to display", so the
// recorded video and the live in-app view are guaranteed to look the same,
// and both match what iOS's own screen recording captures naturally (iOS
// just screen-records whatever's actually on screen, which is this same
// widget in the equivalent state).
// ─────────────────────────────────────────────────────────────────────────────
class _PremiumWaitingPlaceholder extends StatefulWidget {
  const _PremiumWaitingPlaceholder({
    required this.teacherName,
    required this.isMicOn,
    required this.isCamOn,
    required this.auroraAnim,
    this.sessionTitle,
    this.speakerName,
    this.participants = const [],
    this.showLogo = false,
  });

  final String teacherName;
  final bool isMicOn;
  final bool isCamOn;
  final AnimationController auroraAnim;
  // Everything below is optional — omitted (as at the live in-app call
  // site) they simply don't render, so the original "waiting for
  // students" look is unchanged there unless callers opt in.
  final String? sessionTitle;
  final String? speakerName;
  final List<EnrolledStudent> participants;
  // Live in-app use doesn't need the corner logo (it's already in the
  // app chrome around this tile); the recording capture sets this true
  // since the recorded frame has no surrounding chrome at all.
  final bool showLogo;

  @override
  State<_PremiumWaitingPlaceholder> createState() =>
      _PremiumWaitingPlaceholderState();
}

class _PremiumWaitingPlaceholderState
    extends State<_PremiumWaitingPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _ringAnim;
  late Animation<double> _ringScale;
  late Animation<double> _ringOpacity;

  @override
  void initState() {
    super.initState();
    _ringAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _ringScale = Tween<double>(begin: 1.0, end: 1.55).animate(
      CurvedAnimation(parent: _ringAnim, curve: Curves.easeOut),
    );
    _ringOpacity = Tween<double>(begin: 0.45, end: 0.0).animate(
      CurvedAnimation(parent: _ringAnim, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ringAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initials = widget.teacherName.isNotEmpty
        ? widget.teacherName
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join()
        : '?';

    return Container(
      color: _bg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Aurora background
          AnimatedBuilder(
            animation: widget.auroraAnim,
            builder: (_, _) => CustomPaint(
              painter: _AuroraPainter(widget.auroraAnim.value),
              child: const SizedBox.expand(),
            ),
          ),

          if (widget.showLogo)
            Positioned(
              top: 24,
              left: 24,
              child: Image.asset(
                // Confirmed against pubspec.yaml: this is the actual
                // pre-composited logo (used for the launcher icon), and
                // assets/images/ is registered as a full asset folder —
                // no more guessing at a filename here.
                'assets/images/app_icon.png',
                height: 40,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),

          // Center content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Avatar with pulsing ring
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Pulse ring
                      AnimatedBuilder(
                        animation: _ringAnim,
                        builder: (_, _) => Transform.scale(
                          scale: _ringScale.value,
                          child: Opacity(
                            opacity: _ringOpacity.value,
                            child: Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _cyan,
                                  width: 2.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Avatar
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF00D4FF), Color(0xFF6B6EF9)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _cyan.withValues(alpha: 0.35),
                              blurRadius: 28,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Name
                Text(
                  widget.teacherName,
                  style: const TextStyle(
                    fontFamily: 'tajawal',
                    color: _textHigh,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 6),

                // Role chip
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _cyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _cyan.withValues(alpha: 0.35), width: 1),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.school_rounded,
                          color: _cyan, size: 12),
                      SizedBox(width: 5),
                      Text(
                        'Teacher',
                        style: TextStyle(
                          fontFamily: 'tajawal',
                          color: _cyan,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                if (widget.sessionTitle != null &&
                    widget.sessionTitle!.trim().isNotEmpty) ...[
                  Text(
                    widget.sessionTitle!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'tajawal',
                      color: _textMid,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                // A/V status row
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AVChip(
                      icon: widget.isMicOn
                          ? Icons.mic_rounded
                          : Icons.mic_off_rounded,
                      label: widget.isMicOn ? 'Mic On' : 'Mic Off',
                      active: widget.isMicOn,
                      activeColor: const Color(0xFF00E5A0),
                      inactiveColor: _rose,
                    ),
                    const SizedBox(width: 10),
                    _AVChip(
                      icon: widget.isCamOn
                          ? Icons.videocam_rounded
                          : Icons.videocam_off_rounded,
                      label: widget.isCamOn ? 'Cam On' : 'Cam Off',
                      active: widget.isCamOn,
                      activeColor: const Color(0xFF00E5A0),
                      inactiveColor: _textLow,
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                // Currently-speaking badge — only shown when someone other
                // than the person this tile represents is talking, so it
                // never duplicates the "Teacher" role chip above.
                if (widget.speakerName != null &&
                    widget.speakerName!.trim().isNotEmpty &&
                    widget.speakerName!.trim() != widget.teacherName.trim()) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: _emerald.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border:
                      Border.all(color: _emerald.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.graphic_eq,
                            size: 16, color: _emerald),
                        const SizedBox(width: 8),
                        Text(
                          'يتحدث الآن: ${widget.speakerName}',
                          style: const TextStyle(
                            fontFamily: 'tajawal',
                            color: _emerald,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                // Waiting message OR real participants — once anyone has
                // actually joined there's no reason to keep saying "waiting
                // for students", so real names/avatars replace it.
                if (widget.participants.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: _glass10,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _glassBdr, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: _cyan.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Waiting for students to join…',
                          style: TextStyle(
                            fontFamily: 'tajawal',
                            color: _textMid,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final p in widget.participants.take(6))
                        Padding(
                          padding:
                          const EdgeInsets.symmetric(horizontal: 5),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: _surfaceHi,
                                backgroundImage: (p.imageUrl != null &&
                                    p.imageUrl!.isNotEmpty)
                                    ? NetworkImage(p.imageUrl!)
                                    : null,
                                child: (p.imageUrl == null ||
                                    p.imageUrl!.isEmpty)
                                    ? Text(
                                  p.name.trim().isNotEmpty
                                      ? p.name.trim()[0].toUpperCase()
                                      : '؟',
                                  style: const TextStyle(
                                    color: _cyan,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                                    : null,
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: 56,
                                child: Text(
                                  p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontFamily: 'tajawal',
                                    color: _textMid,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (widget.participants.length > 6)
                        Padding(
                          padding:
                          const EdgeInsets.symmetric(horizontal: 5),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: _surfaceHi,
                            child: Text(
                              '+${widget.participants.length - 6}',
                              style: const TextStyle(
                                color: _textMid,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AVChip extends StatelessWidget {
  const _AVChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.inactiveColor,
  });

  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    final color = active ? activeColor : inactiveColor;
    return Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border:
        Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'tajawal',
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Old _WaitingPlaceholder kept as fallback ──────────────────────────────────
class _WaitingPlaceholder extends StatelessWidget {
  const _WaitingPlaceholder() : message = 'Waiting for participants…';

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    color: _bg,
    alignment: Alignment.center,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _glass10,
            border: Border.all(color: _glassBdr, width: 1),
          ),
          child: Icon(
            Icons.videocam_rounded,
            size: 34,
            color: _cyan.withValues(alpha: 0.35),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          message,
          style: TextStyle(
            fontFamily: 'tajawal',
            color: _textLow,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
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
          : Colors.black.withValues(alpha: 0.5),
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
            fontFamily: 'tajawal',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color ?? _textMid,
          ),
        ),
      ],
    ),
  );
}

class _StyledDialog extends StatelessWidget {
  const _StyledDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.isDanger = false,
  });

  final String title, message, confirmLabel;
  final bool isDanger;

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: _surfaceHi,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: _glassBdr, width: 1),
    ),
    title: Text(
      title,
      style: const TextStyle(color: _textHigh, fontWeight: FontWeight.w700),
    ),
    content: Text(
      message,
      style: TextStyle(
        fontFamily: 'tajawal',
        color: _textMid.withValues(alpha: 0.8),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text(
          'Cancel',
          style: TextStyle(fontFamily: 'tajawal', color: _textLow),
        ),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, true),
        child: Text(
          confirmLabel,
          style: TextStyle(
            fontFamily: 'tajawal',
            color: isDanger ? _recRed : _cyan,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
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
          BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 20),
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
            child: const Icon(
              Icons.meeting_room_rounded,
              color: _rose,
              size: 34,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Session Ended',
            style: TextStyle(
              fontFamily: 'tajawal',
              color: _textHigh,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'The teacher has ended this session.\nThank you for joining!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'tajawal',
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
                gradient: const LinearGradient(
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
              child: const Text(
                'OK',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'tajawal',
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
      const Color(0xFF00D4FF).withValues(alpha: 0.07),
    );
    _blob(
      canvas,
      Offset(
        size.width * (0.84 + 0.06 * math.cos(a * 1.3)),
        size.height * (0.24 + 0.08 * math.sin(a * 0.9)),
      ),
      size.width * 0.52,
      const Color(0xFF6B6EF9).withValues(alpha: 0.06),
    );
    _blob(
      canvas,
      Offset(
        size.width * (0.16 + 0.05 * math.sin(a * 0.6)),
        size.height * (0.77 + 0.05 * math.cos(a * 0.5)),
      ),
      size.width * 0.48,
      const Color(0xFF00E5A0).withValues(alpha: 0.04),
    );
    _blob(
      canvas,
      Offset(
        size.width * (0.87 + 0.04 * math.cos(a * 1.1)),
        size.height * (0.83 + 0.04 * math.sin(a * 0.8)),
      ),
      size.width * 0.44,
      const Color(0xFFFF4F72).withValues(alpha: 0.04),
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