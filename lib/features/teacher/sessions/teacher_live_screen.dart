/// teacher_live_screen.dart
///
/// Full LiveKit-native live session screen for the teacher.
/// No WebView — everything is Flutter widgets via livekit_client SDK.
///
/// pubspec.yaml additions:
///   livekit_client:    ^2.4.0
///   permission_handler: ^11.3.0
///
/// AndroidManifest.xml:
///   <uses-permission android:name="android.permission.CAMERA"/>
///   <uses-permission android:name="android.permission.RECORD_AUDIO"/>
///   <uses-permission android:name="android.permission.INTERNET"/>
///   <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
///   <uses-feature android:name="android.hardware.camera"/>
///
/// ios/Runner/Info.plist:
///   NSCameraUsageDescription
///   NSMicrophoneUsageDescription

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/sessions/sessions_provider.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/features/teacher/shared/attendance_provider.dart';
import 'package:flutter_education_app/features/teacher/shared/live_models.dart';
import '../../../config/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────

class TeacherLiveScreen extends StatefulWidget {
  final String sessionTitle;
  final String wsUrl; // from API: settings.LIVEKIT_PUBLIC_URL
  final String token; // LiveKit JWT for the teacher
  final int sessionId;
  final int courseId;
  final Future<bool> Function() onEndLive; // POST /live-sessions/{id}/end

  const TeacherLiveScreen({
    super.key,
    required this.sessionTitle,
    required this.wsUrl,
    required this.token,
    required this.sessionId,
    required this.courseId,
    required this.onEndLive,
  });

  @override
  State<TeacherLiveScreen> createState() => _TeacherLiveScreenState();
}

class _TeacherLiveScreenState extends State<TeacherLiveScreen> {
  // ── LiveKit ───────────────────────────────────────────────────────────────
  late final Room _room;
  late final EventsListener<RoomEvent> _listener;

  bool _cameraOn = true;
  bool _micOn = true;
  bool _screenShareOn = false;
  bool _connecting = true;
  String? _error;

  final List<RemoteParticipant> _remoteParticipants = [];

  // ── Attendance ────────────────────────────────────────────────────────────
  Timer? _attendanceTimer;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _room = Room();
    _listener = _room.createListener();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void dispose() {
    _attendanceTimer?.cancel();
    _listener.dispose();
    _room.disconnect();
    _room.dispose();
    super.dispose();
  }

  // ── Connect ───────────────────────────────────────────────────────────────

  // Future<void> _connect() async {
  //   await [Permission.microphone, Permission.camera].request();
  //   _setupListeners();
  //
  //   try {
  //     await _room.connect(
  //       widget.wsUrl,
  //       widget.token,
  //       connectOptions: ConnectOptions(
  //         timeouts: Timeouts(
  //           connection: Duration(seconds: 30),
  //           iceRestart: Duration(seconds: 30),
  //           peerConnection: Duration(seconds: 30), debounce: Duration(seconds: 30), publish: Duration(seconds: 30), subscribe: Duration(seconds: 30),
  //         ),
  //         rtcConfiguration: RTCConfiguration(
  //           iceTransportPolicy: RTCIceTransportPolicy.relay,
  //           iceServers: [
  //             RTCIceServer(
  //               urls: [
  //                 'stun:openrelay.metered.ca:80',
  //               ],
  //             ),
  //             RTCIceServer(
  //               urls: [
  //                 'turn:openrelay.metered.ca:80',
  //                 'turn:openrelay.metered.ca:443',
  //                 'turn:openrelay.metered.ca:443?transport=tcp',
  //                 'turns:openrelay.metered.ca:443',
  //               ],
  //               username:   'openrelayproject',
  //               credential: 'openrelayproject',
  //             ),
  //           ],
  //         ),
  //       ),
  //       roomOptions: const RoomOptions(
  //         adaptiveStream: true,
  //         dynacast: true,
  //       ),
  //     );
  //     await _room.localParticipant?.setCameraEnabled(true);
  //     await _room.localParticipant?.setMicrophoneEnabled(true);
  //
  //     if (mounted) setState(() => _connecting = false);
  //
  //     _loadAttendance();
  //     _attendanceTimer =
  //         Timer.periodic(const Duration(seconds: 60), (_) => _loadAttendance());
  //   } catch (e) {
  //     if (mounted) {
  //       setState(() {
  //         _error = e.toString();
  //         _connecting = false;
  //       });
  //     }
  //   }
  // }
  Future<void> _connect() async {
    await [Permission.microphone, Permission.camera].request();
    _setupListeners();

    try {
      await _room.connect(
        widget.wsUrl,
        widget.token,
        connectOptions: ConnectOptions(
          timeouts: Timeouts(
            connection: Duration(seconds: 30),
            iceRestart: Duration(seconds: 30),
            peerConnection: Duration(seconds: 30), debounce: Duration(seconds: 30), publish: Duration(seconds: 30), subscribe: Duration(seconds: 30),
          ),
          rtcConfiguration: RTCConfiguration(
            // ← DO NOT use relay-only — let it try all candidates
            // iceTransportPolicy: RTCIceTransportPolicy.relay,  // REMOVE THIS
            iceServers: [
              // Google STUN
              RTCIceServer(
                urls: ['stun:stun.l.google.com:19302'],
              ),
              // OpenRelay STUN
              RTCIceServer(
                urls: ['stun:openrelay.metered.ca:80'],
              ),
              // OpenRelay TURN — multiple ports for best chance
              RTCIceServer(
                urls: [
                  'turn:openrelay.metered.ca:80',
                  'turn:openrelay.metered.ca:443',
                  'turn:openrelay.metered.ca:443?transport=tcp',
                  'turns:openrelay.metered.ca:443',
                ],
                username: 'openrelayproject',
                credential: 'openrelayproject',
              ),
            ],
          ),
        ),
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultVideoPublishOptions: VideoPublishOptions(simulcast: true),
          defaultAudioPublishOptions: AudioPublishOptions(dtx: true),
        ),
      );

      await _room.localParticipant?.setCameraEnabled(true);
      await _room.localParticipant?.setMicrophoneEnabled(true);

      if (mounted) setState(() => _connecting = false);
      _loadAttendance();
      _attendanceTimer =
          Timer.periodic(const Duration(seconds: 60), (_) => _loadAttendance());
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _connecting = false;
        });
      }
    }
  }
  void _setupListeners() {
    _listener
      ..on<RoomConnectedEvent>((_) {
        if (mounted) {
          setState(() {
            _remoteParticipants
              ..clear()
              ..addAll(_room.remoteParticipants.values);
          });
        }
      })
      ..on<ParticipantConnectedEvent>((e) {
        if (mounted) setState(() => _remoteParticipants.add(e.participant));
      })
      ..on<ParticipantDisconnectedEvent>((e) {
        if (mounted) setState(() => _remoteParticipants.remove(e.participant));
      })
      ..on<TrackSubscribedEvent>((_) {
        if (mounted) setState(() {});
      })
      ..on<TrackUnsubscribedEvent>((_) {
        if (mounted) setState(() {});
      })
      ..on<TrackMutedEvent>((_) {
        if (mounted) setState(() {});
      })
      ..on<TrackUnmutedEvent>((_) {
        if (mounted) setState(() {});
      })
      ..on<RoomDisconnectedEvent>((e) {
        if (mounted && e.reason != DisconnectReason.clientInitiated) {
          print("------------------------------");
          print(e.reason?.name ?? '');
          print(e.reason?.toString() ?? '');

          _snack('انقطع الاتصال', AppTheme.danger);
        }
      });
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  Future<void> _toggleCamera() async {
    await _room.localParticipant?.setCameraEnabled(!_cameraOn);
    if (mounted) setState(() => _cameraOn = !_cameraOn);
  }

  Future<void> _toggleMic() async {
    await _room.localParticipant?.setMicrophoneEnabled(!_micOn);
    if (mounted) setState(() => _micOn = !_micOn);
  }

  Future<void> _toggleScreenShare() async {
    try {
      await _room.localParticipant?.setScreenShareEnabled(!_screenShareOn);
      if (mounted) setState(() => _screenShareOn = !_screenShareOn);
    } catch (e) {
      _snack('تعذّر مشاركة الشاشة', AppTheme.danger);
    }
  }

  // ── End session ───────────────────────────────────────────────────────────

  Future<void> _confirmEnd() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('إنهاء الحصة',
              style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700)),
          content: const Text(
              'هل تريد إنهاء الحصة الآن؟\nسيتم حفظ التسجيل تلقائياً في MinIO.',
              style: TextStyle(
                  color: Colors.white70, fontFamily: 'Cairo', height: 1.6)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء',
                  style: TextStyle(color: Colors.white54, fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إنهاء الحصة',
                  style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    await _room.disconnect();
    final ok=  await context
        .read<TeacherSessionsProvider>()
        .endLive(widget.sessionId, saveRecording: true);
    // final ok = await widget.onEndLive();
    if (mounted) {
      _snack(
        ok
            ? 'تم إنهاء الحصة ✓\nسيتوفر التسجيل قريباً'
            : 'حدث خطأ أثناء الإنهاء',
        ok ? AppTheme.success : AppTheme.danger,
      );
      Navigator.pop(context);
    }
  }

  // ── Attendance ────────────────────────────────────────────────────────────

  Future<void> _loadAttendance() async {
    if (!mounted) return;
    await context.read<AttendanceProvider>().fetchList(widget.sessionId);
  }

  void _showAttendanceSheet() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ChangeNotifierProvider.value(
          value: context.read<AttendanceProvider>(),
          child: _AttendanceSheet(
              sessionId: widget.sessionId, onRefresh: _loadAttendance),
        ),
      );

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final attend = context.watch<AttendanceProvider>();

    if (_connecting) {
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text('جاري الاتصال بالغرفة…',
                    style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
              ])));
    }

    if (_error != null) {
      return Scaffold(
          backgroundColor: Colors.black,
          body: Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                const Icon(Icons.signal_wifi_off_rounded,
                    size: 72, color: Colors.white54),
                const SizedBox(height: 16),
                const Text('تعذّر الاتصال',
                    style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Cairo',
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white54,
                            fontFamily: 'Cairo',
                            fontSize: 12))),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _connecting = true;
                    });
                    _connect();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة',
                      style: TextStyle(fontFamily: 'Cairo')),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white),
                ),
              ])));
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (_) => _confirmEnd(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
            child: Stack(children: [
          // ── Video grid ───────────────────────────────────────────────────
          _VideoGrid(
            local: _room.localParticipant,
            remotes: _remoteParticipants,
          ),

          // ── Top bar ──────────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopBar(
              title: widget.sessionTitle,
              presentCount: attend.presentCount,
              onEnd: _confirmEnd,
              onAttendance: _showAttendanceSheet,
            ),
          ),

          // ── Control bar ──────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _ControlBar(
              cameraOn: _cameraOn,
              micOn: _micOn,
              screenShareOn: _screenShareOn,
              onCamera: _toggleCamera,
              onMic: _toggleMic,
              onScreenShare: _toggleScreenShare,
              onEnd: _confirmEnd,
            ),
          ),
        ])),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Video grid — shows local + all remote participants
// ─────────────────────────────────────────────────────────────────────────────

class _VideoGrid extends StatelessWidget {
  final LocalParticipant? local;
  final List<RemoteParticipant> remotes;

  const _VideoGrid({required this.local, required this.remotes});

  @override
  Widget build(BuildContext context) {
    final all = <Participant>[if (local != null) local!, ...remotes];

    if (all.isEmpty) {
      return const Center(
          child: Text('في انتظار المشاركين…',
              style: TextStyle(
                  color: Colors.white54, fontFamily: 'Cairo', fontSize: 16)));
    }

    return GridView.builder(
      padding: EdgeInsets.only(bottom: 90, top: 64),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: all.length == 1 ? 1 : 2,
        childAspectRatio: all.length == 1 ? 16 / 9 : 1,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: all.length,
      itemBuilder: (_, i) => _ParticipantTile(
        participant: all[i],
        isLocal: all[i] is LocalParticipant,
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final Participant participant;
  final bool isLocal;

  const _ParticipantTile({required this.participant, required this.isLocal});

  @override
  Widget build(BuildContext context) {
    VideoTrack? video;
    for (final pub in participant.videoTrackPublications) {
      if (pub.subscribed && pub.track != null) {
        video = pub.track as VideoTrack;
        break;
      }
    }

    return Container(
      color: const Color(0xFF1A1A2E),
      child: Stack(fit: StackFit.expand, children: [
        video != null
            ? VideoTrackRenderer(video)
            : Center(
                child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isLocal
                            ? AppTheme.primary.withValues(alpha: 0.3)
                            : Colors.white12),
                    child: const Icon(Icons.person_rounded,
                        color: Colors.white60, size: 40))),
        // Name + mic label
        Positioned(
          bottom: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.black54, borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                participant.isMicrophoneEnabled()
                    ? Icons.mic_rounded
                    : Icons.mic_off_rounded,
                color: participant.isMicrophoneEnabled()
                    ? Colors.white
                    : Colors.redAccent,
                size: 12,
              ),
              const SizedBox(width: 4),
              Text(
                participant.name.isNotEmpty
                    ? participant.name
                    : (isLocal ? 'أنت' : 'طالب'),
                style: const TextStyle(
                    color: Colors.white, fontFamily: 'Cairo', fontSize: 11),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Top bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  final int presentCount;
  final VoidCallback onEnd, onAttendance;

  const _TopBar(
      {required this.title,
      required this.presentCount,
      required this.onEnd,
      required this.onAttendance});

  @override
  Widget build(BuildContext ctx) => Container(
        height: 60,
        decoration: BoxDecoration(
            gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.90), Colors.transparent],
        )),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.red, borderRadius: BorderRadius.circular(12)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, color: Colors.white, size: 7),
              SizedBox(width: 5),
              Text('LIVE',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 1.2)),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
          GestureDetector(
            onTap: onAttendance,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: const Color(0xFF1D9E75).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.people_rounded, color: Colors.white, size: 14),
                const SizedBox(width: 4),
                Text('$presentCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ]),
            ),
          ),
          GestureDetector(
            onTap: onEnd,
            child: Container(
              margin: const EdgeInsets.only(left: 4, right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                  color: Colors.red, borderRadius: BorderRadius.circular(10)),
              child: const Text('إنهاء',
                  style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bottom control bar
// ─────────────────────────────────────────────────────────────────────────────

class _ControlBar extends StatelessWidget {
  final bool cameraOn, micOn, screenShareOn;
  final VoidCallback onCamera, onMic, onScreenShare, onEnd;

  const _ControlBar(
      {required this.cameraOn,
      required this.micOn,
      required this.screenShareOn,
      required this.onCamera,
      required this.onMic,
      required this.onScreenShare,
      required this.onEnd});

  @override
  Widget build(BuildContext context) => Container(
        height: 90,
        decoration: BoxDecoration(
            gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.90), Colors.transparent],
        )),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _Btn(
              icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
              label: micOn ? 'كتم' : 'فتح',
              active: micOn,
              onTap: onMic),
          _Btn(
              icon: cameraOn
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_rounded,
              label: 'كاميرا',
              active: cameraOn,
              onTap: onCamera),
          _Btn(
              icon: Icons.screen_share_rounded,
              label: 'مشاركة',
              active: screenShareOn,
              onTap: onScreenShare),
          _Btn(
              icon: Icons.call_end_rounded,
              label: 'إنهاء',
              active: false,
              danger: true,
              onTap: onEnd),
        ]),
      );
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active, danger;
  final VoidCallback onTap;

  const _Btn(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.active = true,
      this.danger = false});

  @override
  Widget build(BuildContext context) {
    final c = danger ? Colors.red : (active ? Colors.white : Colors.white38);
    final bg = danger ? Colors.red.withValues(alpha: 0.2) : Colors.white12;
    return GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
              child: Icon(icon, color: c, size: 24)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(color: c, fontFamily: 'Cairo', fontSize: 10)),
        ]));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Attendance sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AttendanceSheet extends StatelessWidget {
  final int sessionId;
  final VoidCallback onRefresh;

  const _AttendanceSheet({required this.sessionId, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AttendanceProvider>();
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        const SizedBox(height: 10),
        Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 12),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Text('الحضور',
                  style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              _Chip('${prov.presentCount} حضر', const Color(0xFF1D9E75)),
              const SizedBox(width: 8),
              _Chip('${prov.absentCount} غاب', Colors.red),
              const SizedBox(width: 8),
              GestureDetector(
                  onTap: onRefresh,
                  child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.refresh_rounded,
                          color: Colors.white70, size: 18))),
            ])),
        const SizedBox(height: 8),
        prov.listLoading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: CircularProgressIndicator(color: Colors.white)))
            : prov.list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('لا يوجد سجل بعد',
                        style: TextStyle(
                            color: Colors.white54, fontFamily: 'Cairo')))
                : Expanded(
                    child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    physics: const BouncingScrollPhysics(),
                    itemCount: prov.list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) =>
                        _StudentRow(record: prov.list[i], sessionId: sessionId),
                  )),
      ]),
    );
  }
}

class _StudentRow extends StatelessWidget {
  final AttendanceDetail record;
  final int sessionId;

  const _StudentRow({required this.record, required this.sessionId});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: record.isPresent
                      ? const Color(0xFF1D9E75)
                      : Colors.grey.shade700),
              child: const Icon(Icons.person_rounded,
                  color: Colors.white, size: 20)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(record.studentName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                if (record.checkInDate != null)
                  Text('دخل: ${record.checkInLabel}',
                      style: const TextStyle(
                          color: Colors.white54,
                          fontFamily: 'Cairo',
                          fontSize: 11)),
              ])),
          if (!record.isPresent)
            GestureDetector(
                onTap: () => _manualCheckIn(context),
                child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: const Color(0xFF1D9E75).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFF1D9E75)
                                .withValues(alpha: 0.5))),
                    child: const Text('تحضير',
                        style: TextStyle(
                            color: Color(0xFF1D9E75),
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w700,
                            fontSize: 11))))
          else
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: const Color(0xFF1D9E75).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6)),
                child: const Text('حضر',
                    style: TextStyle(
                        color: Color(0xFF1D9E75),
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700,
                        fontSize: 11))),
        ]),
      );

  Future<void> _manualCheckIn(BuildContext ctx) async {
    await ctx
        .read<AttendanceProvider>()
        .manualCheckIn(sessionId, record.studentId);
    if (ctx.mounted)
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content:
              Text('تم تحضير الطالب ✓', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Color(0xFF1D9E75),
          behavior: SnackBarBehavior.floating));
  }
}

class _Chip extends StatelessWidget {
  final String t;
  final Color c;

  const _Chip(this.t, this.c);

  @override
  Widget build(BuildContext ctx) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withValues(alpha: 0.4))),
      child: Text(t,
          style: TextStyle(
              color: c,
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w700)));
}
