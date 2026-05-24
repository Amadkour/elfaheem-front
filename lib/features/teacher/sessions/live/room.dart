import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:livekit_client/livekit_client.dart';
import '../components/exts.dart';
import 'widgets/controls.dart';
import 'widgets/participant.dart';
import 'widgets/participant_info.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared Design System  (mirrors PreJoinPage exactly)
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
// Data models for enrolled students & quiz
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

  factory EnrolledStudent.fromJson(Map<String, dynamic> j, List<int> studentsId,
      List<String> studentsJoinDate, List<String> studentsLeaveDate) {
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
        leaveDate: leaveDate != null ? DateTime.parse(leaveDate) : null);
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

  factory ActiveQuiz.fromJson(Map<String, dynamic> j) =>
      ActiveQuiz(
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
// FIX: HD audio quality options
//
// livekit_client ^2.7.0 defaults to ~32 kbps mono Opus.
// Explicitly publishing with AudioPublishOptions raises it to 128 kbps stereo,
// which makes voices and content audio noticeably clearer for all participants.
// ─────────────────────────────────────────────────────────────────────────────

/// HD audio publish options — 128 kbps via AudioEncoding, dtx off.
/// Correct API in livekit_client ^2.7.0:
///   AudioPublishOptions({ String? name, String? stream,
///                         AudioEncoding? encoding, bool dtx, bool? red, ... })
/// audioBitrate is NOT a top-level param — it lives inside AudioEncoding.
const _hdAudioPublishOptions = AudioPublishOptions(
  encoding: AudioEncoding(maxBitrate: 128000), // 128 kbps — was ~32 kbps default
  dtx: false,   // disable discontinuous transmission for continuous quality
  red: true,    // redundant audio encoding — improves quality on lossy networks
);

/// HD microphone capture options — stereo, noise suppression on, echo cancel on.
const _hdAudioCaptureOptions = AudioCaptureOptions(
  noiseSuppression: true,
  echoCancellation: true,
  autoGainControl: true,
  highPassFilter: true,
  typingNoiseDetection: true,
);

/// Upgrade the local microphone track to HD audio.
/// Call once after joining the room.
Future<void> _enableHdAudio(LocalParticipant local) async {
  try {
    // Re-enable mic with HD capture options + HD publish options
    await local.setMicrophoneEnabled(
      true,
      audioCaptureOptions: _hdAudioCaptureOptions,
    );
    // Upgrade existing audio track publications to HD bitrate
    for (final pub in local.audioTrackPublications) {
      if (pub.track is LocalAudioTrack) {
        await local.publishAudioTrack(
          pub.track as LocalAudioTrack,
          publishOptions: _hdAudioPublishOptions,
        );
      }
    }
  } catch (e) {
    // Non-fatal — default audio quality will still work
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RoomPage
// ─────────────────────────────────────────────────────────────────────────────
class RoomPage extends StatefulWidget {
  final Room room;
  final EventsListener<RoomEvent> listener;
  final bool fastConnection;
  final Future<dynamic> Function() onEnd;
  final Future<void> Function(bool)? onToggleRecording;
  final bool isTeacher;
  final int courseId;
  final int sessionId;
  final ApiClient apiClient;

  RoomPage(this.room, this.listener,
      {this.fastConnection = false,
        super.key,
        required this.onEnd,
        required this.isTeacher,
        required this.courseId,
        required this.sessionId,
        this.onToggleRecording,
        ApiClient? api})
      : apiClient = api ?? ApiClient();

  @override
  State<StatefulWidget> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> with TickerProviderStateMixin {
  List<ParticipantTrack> participantTracks = [];

  EventsListener<RoomEvent> get _listener => widget.listener;

  bool get fastConnection => widget.fastConnection;

  bool _isRecording = false;
  bool _recordingLoading = false;

  // Participant panel
  bool _showParticipants = false;
  List<EnrolledStudent> _enrolledStudents = [];
  bool _loadingStudents = false;

  // Quiz
  ActiveQuiz? _activeQuiz;
  bool _quizVisible = false;
  Timer? _quizPollTimer;
  int _currentQuestionIndex = 0;
  Map<int, int> _selectedAnswers = {}; // questionId → optionIndex
  bool _quizSubmitted = false;
  Timer? _quizTimer;
  int _quizSecondsLeft = 0;

  // Draggable PiP
  double _pipRight = 16;
  double _pipBottom = 100;
  static const double _pipW = 120;
  static const double _pipH = 90;

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

  static const _screenShareChannel =
  MethodChannel('com.example.flutter_education_app/screen_share');

  @override
  void initState() {
    super.initState();

    // Thumbnail bar
    _thumbBarAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _thumbBarFade =
        CurvedAnimation(parent: _thumbBarAnim, curve: Curves.easeOut);

    // REC dot
    _recDotAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _recDotOpacity = Tween<double>(begin: 1.0, end: 0.25).animate(
      CurvedAnimation(parent: _recDotAnim, curve: Curves.easeInOut),
    );

    // Aurora background
    _auroraAnim =
    AnimationController(vsync: this, duration: const Duration(seconds: 8))
      ..repeat();

    // Entry animation
    _entryAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _entryFade = CurvedAnimation(parent: _entryAnim, curve: Curves.easeOut);
    _entrySlide = CurvedAnimation(
        parent: _entryAnim,
        curve: const Interval(0.15, 1.0, curve: Curves.easeOutCubic));
    _entryAnim.forward();

    // Participant panel slide
    _panelAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _panelSlide =
        CurvedAnimation(parent: _panelAnim, curve: Curves.easeOutCubic);

    // Quiz overlay slide
    _quizAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _quizSlide = CurvedAnimation(parent: _quizAnim, curve: Curves.easeOutBack);

    _isRecording = widget.room.isRecording;
    widget.room.addListener(_onRoomDidUpdate);
    _setUpListeners();
    _sortParticipants();

    if (lkPlatformIs(PlatformType.android)) {
      unawaited(Hardware.instance.setSpeakerphoneOn(true));
    }

    // Load enrolled students + start quiz polling
    _fetchEnrolledStudents();
    _startQuizPolling();

    // FIX: upgrade microphone to HD audio quality
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final local = widget.room.localParticipant;
      if (local != null) await _enableHdAudio(local);
    });
  }

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
    super.dispose();
  }

  Future<void> _disposeRoomAsync() async {
    await _listener.dispose();
    await widget.room.dispose();
  }

  Future<void> _fetchEnrolledStudents() async {
    if (_loadingStudents) return;
    if(mounted) setState(() => _loadingStudents = true);
    try {
      // Use the attendance-results endpoint which returns attendance flags
      // final uri = Uri.parse(
      //     '${widget.apiBaseUrl}/api/v1/exams/0/attendance-results'
      //         .replaceFirst('/exams/0', ''));
      // Actually call the enrolled-students-with-attendance endpoint
      final resp = await widget.apiClient
          .get('/api/v1/courses/${widget.courseId}/students');
      List<dynamic> participant = await widget.apiClient
          .get('/api/v1/live-sessions/${widget.sessionId}/participants');
      List<int> studentsId = [];
      List<String> studentsJoinDate = [];
      List<String> studentsLeaveDate = [];
      for (int i = 0; i < participant.length; i++) {
        studentsId.add(participant[i]['student_id']);
        studentsJoinDate.add(participant[i]['join_date']);
        studentsLeaveDate.add(participant[i]['leave_date']);
      }
      print(
          "================================================[students]============================");
      print(resp);
      print(
          "=====================================================================");
      if (resp['students'] != null && resp['students'] is List) {
        setState(() {
          _enrolledStudents = resp['students']
              .map((e) =>
              EnrolledStudent.fromJson(e as Map<String, dynamic>,
                  studentsId, studentsJoinDate, studentsLeaveDate))
              .toList()
              .cast<EnrolledStudent>();
        });
      }
      print(_enrolledStudents.length);
    } catch (e) {
      log('fetchEnrolledStudents error: $e');
    } finally {
      if (mounted) if(mounted) setState(() => _loadingStudents = false);
    }
  }

  // ── Quiz polling ───────────────────────────────────────────────────────────

  void _startQuizPolling() {
    // Poll every 30 s for active quiz (mirrors the existing exam endpoint)
    _quizPollTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _pollActiveQuiz());
    _pollActiveQuiz(); // immediate first call
  }

  Future<void> _pollActiveQuiz() async {
    if (!mounted) return;
    try {
      final data = await widget.apiClient
          .get('/api/v1/courses/${widget.courseId}/exams/active');
      if (data == null || data is! List || data.isEmpty) return;

      // Pick the first active exam that has questions
      final examJson = data.first as Map<String, dynamic>;
      final examId = examJson['id'] as int? ?? 0;

      // Fetch questions for this exam
      final qData =
      await widget.apiClient.get('/api/v1/exams/$examId/questions');
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
        if(mounted) setState(() => _quizSecondsLeft--);
      }
    });
  }

  Future<void> _submitQuiz({bool autoSubmit = false}) async {
    if (_activeQuiz == null || _quizSubmitted) return;
    if(mounted) setState(() => _quizSubmitted = true);
    _quizTimer?.cancel();

    // Submit each answered question
    for (final entry in _selectedAnswers.entries) {
      await widget.apiClient.post('/api/v1/exam-answers', body: {
        'exam_id': _activeQuiz!.examId,
        'question_id': entry.key,
        'selected_option': entry.value,
      });
    }

    if (!mounted) return;
    _showSnack(
        autoSubmit ? 'Quiz auto-submitted (time up).' : 'Quiz submitted!');
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) _dismissQuiz();
  }

  void _dismissQuiz() {
    _quizAnim.reverse().then((_) {
      if (mounted) if(mounted) setState(() => _quizVisible = false);
    });
  }

  // ── Listeners ──────────────────────────────────────────────────────────────

  void _setUpListeners() =>
      _listener..on<RoomDisconnectedEvent>((event) async {
        if (event.reason != null) {
          log('Room disconnected: reason => ${event.reason}');
        }
        WidgetsBindingCompatible.instance?.addPostFrameCallback(
                (_) => Navigator.popUntil(context, (r) => r.isFirst));
      })..on<ParticipantEvent>((_) => _sortParticipants())..on<
          RoomRecordingStatusChanged>((event) {
        if(mounted) setState(() => _isRecording = event.activeRecording);
        unawaited(
            context.showRecordingStatusChangedDialog(event.activeRecording));
      })..on<RoomAttemptReconnectEvent>(
              (e) => log('Reconnect ${e.attempt}/${e.maxAttemptsRetry}'))..on<
          LocalTrackPublishedEvent>((_) => _sortParticipants())..on<
          LocalTrackUnpublishedEvent>((_) => _sortParticipants())..on<
          TrackSubscribedEvent>((_) => _sortParticipants())
      // ── AUTO DISCONNECT: when local participant's track is unsubscribed (student removed) ──
        ..on<TrackUnsubscribedEvent>((event) {
          _sortParticipants();
          // If the local participant lost subscription on their own track it means
          // the teacher removed them — end the session automatically.
          if (!widget.isTeacher &&
              event.participant.sid == widget.room.localParticipant?.sid) {
            log('Local track unsubscribed — auto-ending session');
            unawaited(_autoEndSession());
          }
        })..on<TrackE2EEStateEvent>((e) => log('e2ee: $e'))..on<
          ParticipantNameUpdatedEvent>((e) {
        log('Name: ${e.participant.identity} → ${e.name}');
        _sortParticipants();
      })..on<DataReceivedEvent>((event) {
        String decoded = 'Failed to decode';
        try {
          decoded = utf8.decode(event.data);
        } catch (e) {
          log('Decode: $e');
        }
        unawaited(context.showDataReceivedDialog(decoded));
      })..on<AudioPlaybackStatusChanged>((event) async {
        if (!widget.room.canPlaybackAudio) {
          final yesNo = await context.showPlayAudioManuallyDialog();
          if (yesNo == true) await widget.room.startAudio();
        }
      });

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
        if (!_hasVideoTrack(t)) continue;
        if (t.isScreenShare) {
          screenTracks.add(ParticipantTrack(
              participant: p, type: ParticipantTrackType.kScreenShare));
        } else {
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
        if (!_hasVideoTrack(t)) continue;
        if (t.isScreenShare) {
          localScreen.add(ParticipantTrack(
              participant: widget.room.localParticipant!,
              type: ParticipantTrackType.kScreenShare));
        } else {
          localCamera =
              ParticipantTrack(participant: widget.room.localParticipant!);
        }
      }
    }

    final allScreen = [...screenTracks, ...localScreen];
    final ordered = allScreen.isNotEmpty
        ? [...allScreen, if (localCamera != null) localCamera, ...userMedia]
        : [if (localCamera != null) localCamera, ...userMedia];

    if(mounted) setState(() => participantTracks = ordered);
    if (ordered.length > 1) {
      _thumbBarAnim.forward();
    } else {
      _thumbBarAnim.reverse();
    }
  }

  VideoTrack? _resolveScreenTrack(Participant p) {
    for (final pub in p.videoTrackPublications) {
      if (pub.isScreenShare && _hasVideoTrack(pub)) return _getVideoTrack(pub);
    }
    return null;
  }

  VideoTrack? _resolveCameraTrack(Participant p) {
    for (final pub in p.videoTrackPublications) {
      if (!pub.isScreenShare && _hasVideoTrack(pub)) return _getVideoTrack(pub);
    }
    return null;
  }

  bool get _isScreenShareMain =>
      participantTracks.isNotEmpty &&
          participantTracks.first.type == ParticipantTrackType.kScreenShare;

  // ── Recording ──────────────────────────────────────────────────────────────
  Future<void> _handleRecordingToggle() async {
    if (widget.onToggleRecording == null) {
      _showSnack('Recording not configured.');
      return;
    }
    if (_isRecording) {
      final ok = await _showConfirmDialog(
          title: 'Stop recording?',
          message: 'Recording will be saved.',
          confirmLabel: 'Stop',
          isDanger: true);
      if (ok != true) return;
    }
    if(mounted) setState(() => _recordingLoading = true);
    try {
      await widget.onToggleRecording!(!_isRecording);
      final was = _isRecording;
      await Future.delayed(const Duration(seconds: 3));
      if (mounted && _isRecording == was) if(mounted) setState(() => _isRecording = !was);
    } catch (e) {
      log('Recording error: $e');
      _showSnack('Recording failed: $e');
    } finally {
      if (mounted) if(mounted) setState(() => _recordingLoading = false);
    }
  }

  // ── Screen share ──────────────────────────────────────────────────────────
  Future<void> toggleScreenShare() async {
    final local = widget.room.localParticipant;
    if (local == null) return;
    final isSharing = local.isScreenShareEnabled();

    if (lkPlatformIs(PlatformType.android)) {
      if (!isSharing) {
        try {
          await local.setCameraEnabled(false);
          await Future.delayed(const Duration(milliseconds: 200));
          final granted = await _screenShareChannel
              .invokeMethod<bool>('startScreenCaptureService');
          if (granted != true) {
            await local.setCameraEnabled(true);
            return;
          }
          await local.setScreenShareEnabled(
            true,
            captureScreenAudio: true,
            screenShareCaptureOptions: const ScreenShareCaptureOptions(
              captureScreenAudio: true,
              maxFrameRate: 30, // FIX: was 15fps
            ),
          );

          // FIX: publish the screen-share system audio track with HD options
          // so it is captured in recordings and heard by all participants.
          // After setScreenShareEnabled the SDK creates a separate audio track
          // for system audio — upgrade it immediately.
          await Future.delayed(const Duration(milliseconds: 300));
          for (final pub in local.audioTrackPublications) {
            if (pub.source == TrackSource.screenShareAudio &&
                pub.track is LocalAudioTrack) {
              await local.publishAudioTrack(
                pub.track as LocalAudioTrack,
                publishOptions: _hdAudioPublishOptions,
              );
            }
          }

          await Future.delayed(const Duration(milliseconds: 200));
          await local.setCameraEnabled(true);
        } catch (e) {
          log('Screen share error: $e');
          await _stopScreenShare();
          await local.setCameraEnabled(true);
          _showSnack('Screen sharing failed: $e');
        }
      } else {
        try {
          await local.setScreenShareEnabled(false);
          await _stopScreenShare();
          await Future.delayed(const Duration(milliseconds: 300));
          await local.setCameraEnabled(true);
        } catch (e) {
          log('Screen share stop error: $e');
          await _stopScreenShare();
          await local.setCameraEnabled(true);
        }
      }
    } else if (lkPlatformIs(PlatformType.iOS)) {
      try {
        await local.setScreenShareEnabled(
          !isSharing,
          captureScreenAudio: true, // FIX: capture system audio on iOS too
          screenShareCaptureOptions: const ScreenShareCaptureOptions(
            useiOSBroadcastExtension: true,
            maxFrameRate: 30, // FIX: was default 15fps
          ),
        );
        // FIX: upgrade screen-share audio track to HD after enabling
        if (!isSharing) {
          await Future.delayed(const Duration(milliseconds: 300));
          for (final pub in local.audioTrackPublications) {
            if (pub.source == TrackSource.screenShareAudio &&
                pub.track is LocalAudioTrack) {
              await local.publishAudioTrack(
                pub.track as LocalAudioTrack,
                publishOptions: _hdAudioPublishOptions,
              );
            }
          }
        }
      } catch (e) {
        _showSnack('Screen sharing on iOS requires a broadcast extension.');
      }
    } else {
      try {
        await local.setScreenShareEnabled(
          !isSharing,
          captureScreenAudio: true, // FIX: capture system audio on desktop
        );
        // FIX: upgrade screen-share audio track to HD
        if (!isSharing) {
          await Future.delayed(const Duration(milliseconds: 300));
          for (final pub in local.audioTrackPublications) {
            if (pub.source == TrackSource.screenShareAudio &&
                pub.track is LocalAudioTrack) {
              await local.publishAudioTrack(
                pub.track as LocalAudioTrack,
                publishOptions: _hdAudioPublishOptions,
              );
            }
          }
        }
      } catch (e) {
        if (mounted) await context.showErrorDialog(e);
      }
    }
  }

  Future<void> _stopScreenShare() async {
    try {
      await _screenShareChannel.invokeMethod('stopScreenCaptureService');
    } catch (e) {
      log('stopScreenCaptureService: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: _textHigh)),
      backgroundColor: _surfaceHi,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 4),
    ));
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool isDanger = false,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) =>
            _StyledDialog(
              title: title,
              message: message,
              confirmLabel: confirmLabel,
              isDanger: isDanger,
            ),
      );

  // ── Participant panel helpers ──────────────────────────────────────────────
  Future<void> _toggleParticipantPanel() async {
    if (_showParticipants) {
      _panelAnim.reverse().then((_) {
        if (mounted) if(mounted) setState(() => _showParticipants = false);
      });
    } else {
      if(mounted) setState(() => _showParticipants = true);
      _panelAnim.forward();
      await _fetchEnrolledStudents();
    }
  }

  // Check if a LiveKit participant identity matches an enrolled student
  bool _isStudentOnline(EnrolledStudent s) {
    return widget.room.remoteParticipants.values
        .any((p) => p.identity == s.id.toString() || p.name == s.name);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(),
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Aurora background
            AnimatedBuilder(
              animation: _auroraAnim,
              builder: (_, __) =>
                  CustomPaint(
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
                    // Main video area
                    Expanded(
                      child: LayoutBuilder(
                        builder: (ctx, constraints) =>
                            Stack(
                              fit: StackFit.expand,
                              children: [
                                // Main video
                                ClipRRect(
                                  borderRadius:
                                  const BorderRadius.all(Radius.circular(20)),
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
                                              horizontal: 12),
                                          scrollDirection: Axis.horizontal,
                                          itemCount: participantTracks.length -
                                              1,
                                          itemBuilder: (_, i) =>
                                              _ThumbnailCard(
                                                track: participantTracks[i + 1],
                                                resolveScreenTrack: _resolveScreenTrack,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),

                                // PiP (screen share mode)
                                _buildDraggablePip(constraints),

                                // REC indicator
                                _buildRecordingIndicator(),

                                // Participant count badge — tappable to open panel
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
                                      '${widget.room.remoteParticipants.length +
                                          1}',
                                      color: _showParticipants ? _cyan : null,
                                    ),
                                  ),
                                ),

                                // Quiz overlay (freeze screen)
                                if (_quizVisible && _activeQuiz != null)
                                  _buildQuizOverlay(),
                              ],
                            ),
                      ),
                    ),

                    // Controls bar
                    SlideTransition(
                      position: Tween<Offset>(
                          begin: const Offset(0, 1), end: Offset.zero)
                          .animate(_entrySlide),
                      child: _buildControlsBar(),
                    ),
                  ],
                ),
              ),
            ),

            // Participant panel drawer (slides from right)
            if (_showParticipants) _buildParticipantPanel(),
          ],
        ),
      ),
    );
  }

  // ── Main video ─────────────────────────────────────────────────────────────
  Widget _buildMainVideo() {
    if (participantTracks.isEmpty) return const _WaitingPlaceholder();

    final main = participantTracks.first;
    if (main.type == ParticipantTrackType.kScreenShare) {
      return _PremiumScreenShareView(
        participant: main.participant,
        resolveScreenTrack: _resolveScreenTrack,
        auroraAnim: _auroraAnim,
      );
    }

    return ParticipantWidget.widgetFor(main, showStatsLayer: false);
  }

  // ── PiP ───────────────────────────────────────────────────────────────────
  Widget _buildDraggablePip(BoxConstraints constraints) {
    if (!_isScreenShareMain) return const SizedBox.shrink();

    final localEntry = participantTracks
        .skip(1)
        .where((t) =>
    t.participant == widget.room.localParticipant &&
        t.type != ParticipantTrackType.kScreenShare)
        .firstOrNull;
    if (localEntry == null) return const SizedBox.shrink();

    final cameraTrack = _resolveCameraTrack(localEntry.participant);

    return Positioned(
      right: _pipRight,
      bottom: _pipBottom,
      child: GestureDetector(
        onPanUpdate: (d) =>
            setState(() {
              _pipRight = (_pipRight - d.delta.dx)
                  .clamp(8.0, constraints.maxWidth - _pipW - 8.0);
              _pipBottom = (_pipBottom - d.delta.dy)
                  .clamp(8.0, constraints.maxHeight - _pipH - 8.0);
            }),
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
                  offset: const Offset(0, 4)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12.5),
            child: Stack(fit: StackFit.expand, children: [
              if (cameraTrack != null)
                AbsorbPointer(
                  child: VideoTrackRenderer(cameraTrack,
                      renderMode: VideoRenderMode.texture,
                      fit: VideoViewFit.contain),
                )
              else
                Container(
                  color: _surface,
                  child: Icon(Icons.videocam_off_rounded,
                      size: 22, color: _cyan.withValues(alpha: 0.4)),
                ),
              Positioned(
                top: 5,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 28,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── REC indicator ─────────────────────────────────────────────────────────
  Widget _buildRecordingIndicator() {
    if (!_isRecording) return const SizedBox.shrink();
    return Positioned(
      top: 14,
      right: 14,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        FadeTransition(
          opacity: _recDotOpacity,
          child: Container(
            width: 8,
            height: 8,
            decoration:
            const BoxDecoration(color: _recRed, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _recRed.withValues(alpha: 0.4), width: 1),
          ),
          child: const Text('REC',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _recRed,
                  letterSpacing: 1.2)),
        ),
      ]),
    );
  }

  // ── Controls bar ──────────────────────────────────────────────────────────
  Widget _buildControlsBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _surfaceHi.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _glassBdr, width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, -4)),
          BoxShadow(color: _cyan.withValues(alpha: 0.05), blurRadius: 20),
        ],
      ),
      child: Row(
        children: [
          if (widget.room.localParticipant != null)
            Expanded(
              child: ControlsWidget(
                widget.room,
                widget.room.localParticipant!,
                onEndSession: widget.onEnd,
                isTeacher: widget.isTeacher,
                onToggleScreenShare: toggleScreenShare,
              ),
            ),
          if (widget.isTeacher && widget.onToggleRecording != null)
            _RecordingButton(
              isRecording: _isRecording,
              loading: _recordingLoading,
              onTap: _handleRecordingToggle,
              recDotOpacity: _recDotOpacity,
            ),
        ],
      ),
    );
  }

  // ── Participant panel ──────────────────────────────────────────────────────
  Widget _buildParticipantPanel() {
    // Determine connected livekit identities for matching
    final liveIdentities =
    widget.room.remoteParticipants.values.map((p) => p.identity).toSet();

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
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(_panelSlide),
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
                      Text(
                        'Participants',
                        style: const TextStyle(
                            color: _textHigh,
                            fontWeight: FontWeight.w700,
                            fontSize: 15),
                      ),
                      const Spacer(),
                      if (_loadingStudents)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _cyan),
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
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: _textMid),
                        ),
                      ),
                    ],
                  ),
                ),

                // Teacher row (self)
                _ParticipantRow(
                  name: widget.room.localParticipant?.name ?? 'You',
                  isOnline: true,
                  isTeacher: true,
                  isAttended: true,
                  micOn: widget.room.localParticipant?.isMicrophoneEnabled() ??
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
                            color: _textLow,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _emerald.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _emerald.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '${_enrolledStudents
                              .where((s) => s.isAttended)
                              .length} attended',
                          style: TextStyle(
                              color: _emerald,
                              fontSize: 10,
                              fontWeight: FontWeight.w600),
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
                        Icon(Icons.school_outlined,
                            color: _textLow, size: 32),
                        const SizedBox(height: 8),
                        Text('No students enrolled',
                            style:
                            TextStyle(color: _textLow, fontSize: 13)),
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
                      // Find matching remote participant for mic/cam
                      final rp = widget.room.remoteParticipants.values
                          .firstWhereOrNull((p) =>
                      p.identity == s.id.toString() ||
                          p.name == s.name);
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
                      color: _cyan.withValues(alpha: 0.35), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                        color: _cyan.withValues(alpha: 0.12), blurRadius: 40),
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 20),
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
        // Quiz header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_cyan.withValues(alpha: 0.15), Colors.transparent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(23)),
          ),
          child: Row(
            children: [
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _cyan.withValues(alpha: 0.4)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.quiz_rounded, size: 13, color: _cyan),
                  SizedBox(width: 5),
                  Text('LIVE QUIZ',
                      style: TextStyle(
                          color: _cyan,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1)),
                ]),
              ),
              const Spacer(),
              // Timer
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.timer_rounded,
                      size: 13,
                      color: _quizSecondsLeft < 30 ? _rose : _textMid),
                  const SizedBox(width: 4),
                  Text(timerStr,
                      style: TextStyle(
                          color: _quizSecondsLeft < 30 ? _rose : _textMid,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text(
            quiz.name,
            style: const TextStyle(
                color: _textHigh, fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),

        // Progress indicator
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(children: [
            Text(
              'Question ${_currentQuestionIndex + 1} of ${quiz.questions
                  .length}',
              style: TextStyle(color: _textLow, fontSize: 11),
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
          ]),
        ),

        // Question text
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Text(
            q.text,
            style: const TextStyle(
                color: _textHigh,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.4),
          ),
        ),

        // Options
        ...List.generate(q.options.length, (idx) {
          final selected = _selectedAnswers[q.id] == idx;
          return GestureDetector(
            onTap: () { if(mounted) setState(() => _selectedAnswers[q.id] = idx);},
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
                      blurRadius: 12)
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
                          color: selected ? _cyan : _glassBdr, width: 1.5),
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
                          color: selected ? _textHigh : _textMid,
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),

        // Navigation buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Row(children: [
            if (_currentQuestionIndex > 0)
              Expanded(
                child: GestureDetector(
                  onTap: () { if(mounted) setState(() => _currentQuestionIndex--);},
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
                        Icon(Icons.arrow_back_rounded,
                            size: 16, color: _textMid),
                        SizedBox(width: 6),
                        Text('Back',
                            style: TextStyle(
                                color: _textMid, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            if (_currentQuestionIndex > 0) const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: isLast
                    ? () => _submitQuiz()
                    : () { if(mounted) setState(() => _currentQuestionIndex++);},
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [_cyan, _indigo],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                          color: _cyan.withValues(alpha: 0.3), blurRadius: 16)
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
                            fontSize: 14),
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
          ]),
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
              border:
              Border.all(color: _emerald.withValues(alpha: 0.4), width: 2),
            ),
            child: const Icon(Icons.check_rounded, color: _emerald, size: 36),
          ),
          const SizedBox(height: 18),
          const Text('Quiz Submitted!',
              style: TextStyle(
                  color: _textHigh, fontWeight: FontWeight.w800, fontSize: 20)),
          const SizedBox(height: 8),
          Text(
            'You answered $answered of ${quiz.questions.length} questions.',
            style: TextStyle(color: _textMid, fontSize: 14),
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
                  BoxShadow(color: _cyan.withValues(alpha: 0.3), blurRadius: 14)
                ],
              ),
              child: const Text('Back to Room',
                  style: TextStyle(
                      color: _textHigh,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}

// Helper extension for layered Positioned children without nesting
extension _WidgetEx on Widget {
  Widget withChild(Widget child) => Stack(children: [this, child]);
}

// ─────────────────────────────────────────────────────────────────────────────
// _ParticipantRow  (used inside the panel)
// ─────────────────────────────────────────────────────────────────────────────
class _ParticipantRow extends StatelessWidget {
  _ParticipantRow({
    required this.name,
    required this.isOnline,
    required this.isTeacher,
    required this.isAttended,
    required this.micOn,
    required this.camOn,
    this.joinDate,
    this.leaveDate,
  }){
    print(joinDate?.day);
    print("jjjjjjjjjjjjjjjjjjjjjjjjj");
  }

  final String name;
  final bool isOnline;
  final bool isTeacher;
  final bool isAttended;
  final bool micOn;
  final bool camOn;
  final DateTime? joinDate;
  final DateTime? leaveDate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isTeacher ? _cyan.withValues(alpha: 0.05) : Colors.transparent,
        border:
        Border(bottom: BorderSide(color: _glassBdr.withValues(alpha: 0.4))),
      ),
      child: Row(
        children: [
          // Avatar + online dot
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: isTeacher
                      ? [
                    _cyan.withValues(alpha: 0.8),
                    _indigo.withValues(alpha: 0.8)
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
                    color: isTeacher ? _bg : _textMid,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            // Online dot
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
          ]),
          const SizedBox(width: 10),

          // Name + badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                      color: _textHigh,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(children: [
                  if (isTeacher)
                    _MiniTag(label: 'Teacher', color: _cyan)
                  else
                    ...[
                      _MiniTag(
                        label: isAttended ? 'Attended' : 'Absent',
                        color: isAttended ? _emerald : _rose,
                      ),
                      if (isOnline) ...[
                        const SizedBox(width: 4),
                        _MiniTag(label: 'Online', color: _emerald),
                      ],
                    ],
                ]),
                Row(
                  children: [
                    if(joinDate != null)
                      ...[Text(DateTime
                          .now()
                          .difference(joinDate!)
                          .inMinutes
                          .toString()),
                        Text('-', style: TextStyle(
                            color: Colors.green
                        ),),
                        if(joinDate != null)
                          Text(DateTime
                              .now()
                              .difference(joinDate!)
                              .inMinutes
                              .toString())
                      ]
                  ],
                )
              ],
            ),
          ),

          // Mic / cam icons
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
  Widget build(BuildContext context) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 9, fontWeight: FontWeight.w700)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _RecordingButton
// ─────────────────────────────────────────────────────────────────────────────
class _RecordingButton extends StatelessWidget {
  const _RecordingButton({
    required this.isRecording,
    required this.loading,
    required this.onTap,
    required this.recDotOpacity,
  });

  final bool isRecording;
  final bool loading;
  final VoidCallback onTap;
  final Animation<double> recDotOpacity;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 48,
        height: 48,
        margin: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isRecording ? _recRed.withValues(alpha: 0.15) : _glass10,
          border: Border.all(
              color: isRecording ? _recRed.withValues(alpha: 0.5) : _glassBdr,
              width: 1),
          boxShadow: isRecording
              ? [
            BoxShadow(
                color: _recRed.withValues(alpha: 0.3), blurRadius: 16)
          ]
              : [],
        ),
        child: loading
            ? const Padding(
          padding: EdgeInsets.all(13),
          child:
          CircularProgressIndicator(strokeWidth: 2, color: _recRed),
        )
            : isRecording
            ? FadeTransition(
          opacity: recDotOpacity,
          child: const Icon(Icons.stop_circle_rounded,
              color: _recRed, size: 24),
        )
            : const Icon(Icons.fiber_manual_record_rounded,
            color: _textLow, size: 22),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ThumbnailCard
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
              offset: const Offset(0, 3)),
          if (isScreen || isSpeaking)
            BoxShadow(
                color: _cyan.withValues(alpha: isSpeaking ? 0.25 : 0.15),
                blurRadius: 16),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(fit: StackFit.expand, children: [
          if (isScreen && screenTrack != null)
            AbsorbPointer(
              child: VideoTrackRenderer(
                  key: ValueKey(screenTrack.sid),
                  screenTrack,
                  renderMode: VideoRenderMode.auto,
                  fit: VideoViewFit.contain),
            )
          else
            ParticipantWidget.widgetFor(track, showStatsLayer: false),

          // Bottom name bar
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
                    Colors.transparent
                  ],
                ),
              ),
              child: Row(children: [
                if (isScreen)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.screen_share_rounded,
                        size: 10, color: _cyan),
                  ),
                Expanded(
                  child: Text(
                    track.participant.name.isNotEmpty
                        ? track.participant.name
                        : track.participant.identity,
                    style: const TextStyle(
                        fontSize: 10,
                        color: _textMid,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Speaking indicator dot
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
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PremiumScreenShareView — premium screen-share display for students
// ─────────────────────────────────────────────────────────────────────────────

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
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _borderGlow = CurvedAnimation(
        parent: _borderGlowAnim, curve: Curves.easeInOut);
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
        // ── Deep background with subtle aurora ──────────────────────────────
        Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.3),
              radius: 1.2,
              colors: [Color(0xFF0D1533), Color(0xFF060810)],
            ),
          ),
        ),

        // Subtle animated aurora behind content
        AnimatedBuilder(
          animation: widget.auroraAnim,
          builder: (_, __) {
            final t = widget.auroraAnim.value * 2 * 3.14159;
            return CustomPaint(
              painter: _ScreenShareAuroraPainter(t),
              child: const SizedBox.expand(),
            );
          },
        ),

        // ── Video content with glowing animated border ─────────────────────
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
                        alpha: 0.25 + 0.35 * _borderGlow.value),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _cyan.withValues(
                          alpha: 0.08 + 0.14 * _borderGlow.value),
                      blurRadius: 32,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: _indigo.withValues(
                          alpha: 0.06 + 0.08 * _borderGlow.value),
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
                  // FIX: use .auto for hardware-accelerated rendering
                  renderMode: VideoRenderMode.auto,
                  fit: VideoViewFit.contain,
                )
                    : _ScreenShareLoadingPlaceholder(
                    presenterName: presenterName),
              ),
            ),
          ),
        ),

        // ── Top-left: presenter identity badge ─────────────────────────────
        Positioned(
          top: 20,
          left: 20,
          child: _PresenterBadge(
            name: presenterName,
            isSpeaking: isSpeaking,
          ),
        ),

        // ── Top-right: LIVE / screen-share label ───────────────────────────
        Positioned(
          top: 20,
          right: 20,
          child: _ScreenShareLiveBadge(),
        ),

        // ── Bottom bar with presenter info + audio level ────────────────────
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

// ── Presenter identity badge ──────────────────────────────────────────────────
class _PresenterBadge extends StatelessWidget {
  final String name;
  final bool isSpeaking;

  const _PresenterBadge({required this.name, required this.isSpeaking});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isSpeaking
            ? _cyan.withValues(alpha: 0.22)
            : Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: isSpeaking
              ? _cyan.withValues(alpha: 0.7)
              : _glassBdr,
          width: 1,
        ),
        boxShadow: isSpeaking
            ? [BoxShadow(color: _cyan.withValues(alpha: 0.25), blurRadius: 16)]
            : [],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // Animated speaking dot
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
        Icon(Icons.person_rounded,
            size: 13,
            color: isSpeaking ? _cyan : _textMid),
        const SizedBox(width: 6),
        Text(
          name,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSpeaking ? _cyan : _textMid,
          ),
        ),
      ]),
    );
  }
}

// ── LIVE badge ────────────────────────────────────────────────────────────────
class _ScreenShareLiveBadge extends StatelessWidget {
  const _ScreenShareLiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.screen_share_rounded, size: 13, color: Colors.white),
        const SizedBox(width: 6),
        const Text(
          'SCREEN',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
      ]),
    );
  }
}

// ── Bottom info bar ───────────────────────────────────────────────────────────
class _ScreenShareBottomBar extends StatelessWidget {
  final Participant participant;
  final String presenterName;

  const _ScreenShareBottomBar({
    required this.participant,
    required this.presenterName,
  });

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
          // Avatar circle
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
                BoxShadow(
                    color: _cyan.withValues(alpha: 0.35), blurRadius: 10)
              ],
            ),
            child: Center(
              child: Text(
                presenterName.isNotEmpty
                    ? presenterName[0].toUpperCase()
                    : '?',
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
                    color: _cyan.withValues(alpha: 0.8),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Mic / Cam status pills
          Row(children: [
            _StatusPill(
              icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
              color: micOn ? _emerald : _rose,
              active: micOn,
            ),
            const SizedBox(width: 6),
            _StatusPill(
              icon: camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              color: camOn ? _emerald : _textLow,
              active: camOn,
            ),
          ]),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool active;

  const _StatusPill({
    required this.icon,
    required this.color,
    required this.active,
  });

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

// ── Loading placeholder while screen share track connects ─────────────────────
class _ScreenShareLoadingPlaceholder extends StatelessWidget {
  final String presenterName;

  const _ScreenShareLoadingPlaceholder({required this.presenterName});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0A0F20),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _indigo.withValues(alpha: 0.12),
            border: Border.all(color: _indigo.withValues(alpha: 0.3), width: 1.5),
          ),
          child: const Icon(Icons.screen_share_rounded,
              size: 32, color: _indigo),
        ),
        const SizedBox(height: 18),
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _cyan,
          ),
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
            color: _cyan.withValues(alpha: 0.6),
            fontSize: 11,
          ),
        ),
      ]),
    );
  }
}

// ── Aurora painter for screen-share background ────────────────────────────────
class _ScreenShareAuroraPainter extends CustomPainter {
  _ScreenShareAuroraPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    _blob(
        canvas,
        Offset(size.width * (0.15 + 0.05 * math.sin(t * 0.7)),
            size.height * (0.2 + 0.06 * math.cos(t * 0.5))),
        size.width * 0.45,
        _indigo.withValues(alpha: 0.06));
    _blob(
        canvas,
        Offset(size.width * (0.82 + 0.04 * math.cos(t * 0.9)),
            size.height * (0.75 + 0.05 * math.sin(t * 0.6))),
        size.width * 0.4,
        _cyan.withValues(alpha: 0.04));
  }

  void _blob(Canvas canvas, Offset center, double r, Color color) {
    canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(colors: [color, Colors.transparent])
              .createShader(Rect.fromCircle(center: center, radius: r)));
  }

  @override
  bool shouldRepaint(_ScreenShareAuroraPainter old) => old.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
// _WaitingPlaceholder
// ─────────────────────────────────────────────────────────────────────────────
class _WaitingPlaceholder extends StatelessWidget {
  const _WaitingPlaceholder({this.message = 'Waiting for participants…'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _glass10,
            border: Border.all(color: _glassBdr, width: 1),
          ),
          child: Icon(Icons.videocam_rounded,
              size: 34, color: _cyan.withValues(alpha: 0.35)),
        ),
        const SizedBox(height: 16),
        Text(message,
            style: TextStyle(
                color: _textLow, fontSize: 14, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GlassBadge
// ─────────────────────────────────────────────────────────────────────────────
class _GlassBadge extends StatelessWidget {
  const _GlassBadge({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color ?? _textMid),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color ?? _textMid)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StyledDialog
// ─────────────────────────────────────────────────────────────────────────────
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
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _surfaceHi,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: _glassBdr, width: 1),
      ),
      title: Text(title,
          style:
          const TextStyle(color: _textHigh, fontWeight: FontWeight.w700)),
      content: Text(message,
          style: TextStyle(color: _textMid.withValues(alpha: 0.8))),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: TextStyle(color: _textLow)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel,
              style: TextStyle(
                color: isDanger ? _recRed : _cyan,
                fontWeight: FontWeight.w700,
              )),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Aurora background painter
// ─────────────────────────────────────────────────────────────────────────────
class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final a = t * 2 * math.pi;
    _blob(
        canvas,
        Offset(size.width * (0.12 + 0.07 * math.sin(a)),
            size.height * (0.13 + 0.06 * math.cos(a * 0.7))),
        size.width * 0.58,
        const Color(0xFF00D4FF).withValues(alpha: 0.07));
    _blob(
        canvas,
        Offset(size.width * (0.84 + 0.06 * math.cos(a * 1.3)),
            size.height * (0.24 + 0.08 * math.sin(a * 0.9))),
        size.width * 0.52,
        const Color(0xFF6B6EF9).withValues(alpha: 0.06));
    _blob(
        canvas,
        Offset(size.width * (0.16 + 0.05 * math.sin(a * 0.6)),
            size.height * (0.77 + 0.05 * math.cos(a * 0.5))),
        size.width * 0.48,
        const Color(0xFF00E5A0).withValues(alpha: 0.04));
    _blob(
        canvas,
        Offset(size.width * (0.87 + 0.04 * math.cos(a * 1.1)),
            size.height * (0.83 + 0.04 * math.sin(a * 0.8))),
        size.width * 0.44,
        const Color(0xFFFF4F72).withValues(alpha: 0.04));
  }

  void _blob(Canvas canvas, Offset center, double r, Color color) {
    canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(colors: [color, Colors.transparent])
              .createShader(Rect.fromCircle(center: center, radius: r)));
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
// NotificationChannelHelper
// ─────────────────────────────────────────────────────────────────────────────
class NotificationChannelHelper {
  static const _channel =
  MethodChannel('com.example.flutter_education_app/notifications');
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