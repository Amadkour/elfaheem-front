import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

import '../../../config/app_config.dart';

/// ─────────────────────────────────────────────────────────────────────────────
///  TeacherLiveSessionScreen
///
///  APIs:
///    POST /api/v1/live-sessions/start?session_id=…  → { ws_url, token }
///    GET  /api/v1/live-sessions/{id}/join           → { ws_url, token }
///    POST /api/v1/live-sessions/{id}/end
///    GET  /api/v1/courses/{course_id}/students      → List<EnrolledStudent>
///
///  AndroidManifest.xml required additions:
///    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
///    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION"/>
///    <service
///      android:name="io.livekit.android.screencapture.ScreenCaptureService"
///      android:foregroundServiceType="mediaProjection"
///      android:exported="false"/>
/// ─────────────────────────────────────────────────────────────────────────────

// ── Model ─────────────────────────────────────────────────────────────────────

class EnrolledStudent {
  final int id;
  final String name;
  final String? imageUrl;

  EnrolledStudent({required this.id, required this.name, this.imageUrl});

  factory EnrolledStudent.fromJson(Map<String, dynamic> j) => EnrolledStudent(
    id: j['id'] as int,
    name: j['name'] as String? ?? '',
    imageUrl: j['image_url'] as String?,
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class TeacherLiveSessionScreen extends StatefulWidget {
  final int sessionId;
  final int courseId;
  final String sessionName;
  final String authToken;
  final bool enableRecording;
  final int? maxParticipants;

  const TeacherLiveSessionScreen({
    super.key,
    required this.sessionId,
    required this.courseId,
    required this.sessionName,
    required this.authToken,
    this.enableRecording = true,
    this.maxParticipants,
  });

  @override
  State<TeacherLiveSessionScreen> createState() =>
      _TeacherLiveSessionScreenState();
}

class _TeacherLiveSessionScreenState extends State<TeacherLiveSessionScreen>
    with WidgetsBindingObserver {
  // ── LiveKit ───────────────────────────────────────────────────────────────
  Room? _room;
  LocalParticipant? _localParticipant;
  final List<RemoteParticipant> _remoteParticipants = [];

  // ── Local tracks ──────────────────────────────────────────────────────────
  LocalVideoTrack? _localVideoTrack;
  LocalVideoTrack? _screenShareTrack;

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _isStarting = true;
  bool _isMicMuted = false;
  bool _isCameraOff = false;
  bool _isFrontCamera = true;
  bool _isScreenSharing = false;
  bool _isPipCameraMain = false;  // false = screen share is main, camera is PiP
  bool _showAttendancePanel = false;
  bool _isEndingSession = false;
  String? _errorMessage;

  // ── Enrolled students & attendance ────────────────────────────────────────
  List<EnrolledStudent> _enrolledStudents = [];
  final Map<int, bool> _attendanceMap = {};   // studentId → isPresent
  final Set<String> _liveIdentities = {};

  // ── Timer ─────────────────────────────────────────────────────────────────
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startSessionAndConnect();
    _fetchEnrolledStudents();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _room?.removeListener(_onRoomUpdate);
    _room?.disconnect();
    super.dispose();
  }

  // ── API ───────────────────────────────────────────────────────────────────

  Future<void> _startSessionAndConnect() async {
    try {
      final startRes = await http.post(
        Uri.parse(
          '${AppConfig.baseUrl}/api/v1/live-sessions/start'
              '?session_id=${widget.sessionId}'
              '&enable_recording=${widget.enableRecording}'
              '&duration_hours=24'
              '${widget.maxParticipants != null ? "&max_participants=${widget.maxParticipants}" : ""}',
        ),
        headers: {'Authorization': 'Bearer ${widget.authToken}'},
      );

      if (startRes.statusCode != 200) {
        await _joinExistingRoom();
        return;
      }

      final data = json.decode(startRes.body);
      await _connectToRoom(
          data['ws_url'] as String, data['token'] as String);
    } catch (e) {
      setState(() {
        _isStarting = false;
        _errorMessage = 'Failed to start session: $e';
      });
    }
  }

  Future<void> _joinExistingRoom() async {
    final res = await http.get(
      Uri.parse(
          '${AppConfig.baseUrl}/api/v1/live-sessions/${widget.sessionId}/join'),
      headers: {'Authorization': 'Bearer ${widget.authToken}'},
    );
    if (res.statusCode != 200) {
      setState(() {
        _isStarting = false;
        _errorMessage = 'Could not join room (${res.statusCode})';
      });
      return;
    }
    final data = json.decode(res.body);
    await _connectToRoom(data['ws_url'] as String, data['token'] as String);
  }

  Future<void> _fetchEnrolledStudents() async {
    try {
      // GET /api/v1/courses/{course_id}/students
      // → List<{ id, name, image_url, enrolled_at, status, ... }>
      final res = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/api/v1/courses/${widget.courseId}/students'),
        headers: {'Authorization': 'Bearer ${widget.authToken}'},
      );
      if (res.statusCode == 200) {
        final list = json.decode(res.body) as List<dynamic>;
        setState(() {
          _enrolledStudents =
              list.map((j) => EnrolledStudent.fromJson(j)).toList();
          for (final s in _enrolledStudents) {
            _attendanceMap[s.id] = false; // default absent
          }
        });
      }
    } catch (_) {
      // non-fatal
    }
  }

  Future<void> _connectToRoom(String wsUrl, String token) async {
    final room = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultVideoPublishOptions: VideoPublishOptions(simulcast: true),
      ),
    );
    room.addListener(_onRoomUpdate);

    await room.connect(wsUrl, token,
        connectOptions: const ConnectOptions(autoSubscribe: true));

    _localParticipant = room.localParticipant;
    await _localParticipant?.setCameraEnabled(true);
    await _localParticipant?.setMicrophoneEnabled(true);

    _localVideoTrack = _localParticipant?.videoTrackPublications
        .where((p) => p.source == TrackSource.camera)
        .map((p) => p.track)
        .whereType<LocalVideoTrack>()
        .firstOrNull;

    _timer = Timer.periodic(
        const Duration(seconds: 1),
            (_) => setState(() => _elapsed += const Duration(seconds: 1)));

    setState(() {
      _room = room;
      _isStarting = false;
      _remoteParticipants.addAll(room.remoteParticipants.values);
      _syncIdentities();
    });
  }

  void _onRoomUpdate() {
    if (!mounted) return;
    setState(() {
      _remoteParticipants
        ..clear()
        ..addAll(_room?.remoteParticipants.values ?? []);
      _syncIdentities();
    });
  }

  void _syncIdentities() {
    _liveIdentities
      ..clear()
      ..addAll(_remoteParticipants.map((p) => p.identity));

    // Auto-mark present when a matching student joins the room
    for (final s in _enrolledStudents) {
      final inRoom = _liveIdentities.any((id) =>
      id.toLowerCase().contains(s.name.toLowerCase()) ||
          id == s.id.toString());
      if (inRoom && _attendanceMap[s.id] == false) {
        _attendanceMap[s.id] = true;
      }
    }
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  Future<void> _toggleMic() async {
    await _localParticipant?.setMicrophoneEnabled(_isMicMuted);
    setState(() => _isMicMuted = !_isMicMuted);
  }

  Future<void> _toggleCamera() async {
    await _localParticipant?.setCameraEnabled(_isCameraOff);
    setState(() => _isCameraOff = !_isCameraOff);
  }

  Future<void> _switchCamera() async {
    if (_localVideoTrack == null) return;
    try {
      final devices =
      await webrtc.navigator.mediaDevices.enumerateDevices();
      final cameras = devices.where((d) => d.kind == 'videoinput').toList();
      if (cameras.length < 2) return;

      final currentId = _localVideoTrack!.mediaStreamTrack.id;
      final next = cameras.firstWhere(
            (d) => d.deviceId != currentId,
        orElse: () => cameras.first,
      );
      await _localVideoTrack!.switchCamera(next.deviceId);
      setState(() => _isFrontCamera = !_isFrontCamera);
    } catch (e) {
      debugPrint('Switch camera error: $e');
    }
  }

  // ── Screen share ──────────────────────────────────────────────────────────
  //
  //  livekit_client ^2.7.0 verified API (from official pub.dev docs):
  //
  //  START:  Helper.requestCapturePermission() → bool   (flutter_webrtc)
  //          LocalVideoTrack.createScreenShareTrack(options) → LocalVideoTrack
  //          localParticipant.publishVideoTrack(track)
  //
  //  STOP:   localParticipant.setScreenShareEnabled(false)
  //          — this is the simplest, officially documented stop method.
  //          — it internally finds and unpublishes the screen share track.
  //          — we then call stop() on our track reference to release hardware.
  //
  //  The SID-based unpublishTrack(sid) also exists but requires finding the
  //  publication object first, which adds complexity with no benefit here.

  Future<void> _toggleScreenShare() async {
    _isScreenSharing ? await _stopScreenShare() : await _startScreenShare();
  }

  Future<void> _startScreenShare() async {
    try {
      if (Platform.isAndroid) {
        // Must call requestCapturePermission() FIRST while in foreground.
        // If skipped, createScreenShareTrack() fires the MediaProjection dialog
        // internally which moves the app to background → Android kills it.
        final granted = await webrtc.Helper.requestCapturePermission();
        if (!granted) {
          _showSnack('Screen share permission denied.', Colors.redAccent);
          return;
        }
        _screenShareTrack = await LocalVideoTrack.createScreenShareTrack(
          const ScreenShareCaptureOptions(
            useiOSBroadcastExtension: false,
            captureScreenAudio: true,
            maxFrameRate: 30,
            preferCurrentTab: true
          ),
        );
      } else if (Platform.isIOS) {
        _showSnack(
          'iOS screen share requires a Broadcast Extension. '
              'Contact your developer to add one.',
          Colors.orange,
        );
        return;
      } else {
        _screenShareTrack = await LocalVideoTrack.createScreenShareTrack(
          const ScreenShareCaptureOptions(
            captureScreenAudio: true,
            maxFrameRate: 15,
          ),
        );
      }

      // Publish the screen share track.
      // Camera stays ENABLED — both tracks are published simultaneously.
      // The recording (RoomCompositeEgress / speaker-dark layout) will show
      // the screen share as the dominant track with camera as a small overlay.
      await _localParticipant?.publishVideoTrack(_screenShareTrack!);

      // Ensure camera is on (it should be, but confirm)
      if (_isCameraOff) {
        await _localParticipant?.setCameraEnabled(true);
        setState(() => _isCameraOff = false);
      }

      setState(() {
        _isScreenSharing = true;
        _isPipCameraMain = false; // screen share fills main frame by default
      });
    } on PlatformException catch (e) {
      debugPrint('Screen share PlatformException: $e');
      _screenShareTrack = null;
      _showSnack('Screen share permission was denied.', Colors.redAccent);
    } catch (e) {
      debugPrint('Screen share error: $e');
      _screenShareTrack = null;
      _showSnack('Could not start screen share: $e', Colors.redAccent);
    }
  }

  Future<void> _stopScreenShare() async {
    try {
      await _localParticipant?.setScreenShareEnabled(false);
      await _screenShareTrack?.stop();
    } catch (e) {
      debugPrint('Stop screen share error: $e');
    } finally {
      _screenShareTrack = null;
      setState(() {
        _isScreenSharing = false;
        _isPipCameraMain = false;
      });
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      duration: const Duration(seconds: 4),
    ));
  }

  // ── Attendance ────────────────────────────────────────────────────────────

  void _toggleAttendance(int studentId) {
    setState(() {
      _attendanceMap[studentId] = !(_attendanceMap[studentId] ?? false);
    });
  }

  Future<void> _submitAttendance() async {
    final body = _attendanceMap.entries
        .map((e) => {'student_id': e.key, 'is_present': e.value})
        .toList();
    try {
      await http.post(
        Uri.parse(
            '${AppConfig.baseUrl}/api/v1/sessions/${widget.sessionId}/attendance'),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Content-Type': 'application/json',
        },
        body: json.encode(body),
      );
    } catch (_) {}
  }

  Future<void> _confirmEndSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2235),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('End Session',
            style:
            TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'This will end the session for all participants and save the recording.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.blue))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End Now'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isEndingSession = true);
    await _submitAttendance();

    try {
      await http.post(
        Uri.parse(
            '${AppConfig.baseUrl}/api/v1/live-sessions/${widget.sessionId}/end'),
        headers: {'Authorization': 'Bearer ${widget.authToken}'},
      );
    } catch (_) {}

    _timer?.cancel();
    _room?.removeListener(_onRoomUpdate);
    await _room?.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  int get _participantCount =>
      (_room != null ? 1 : 0) + _remoteParticipants.length;
  int get _presentCount => _attendanceMap.values.where((v) => v).length;

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '$h:$m:$s' : '$m:$s';
  }

  bool _isInRoom(EnrolledStudent s) => _liveIdentities.any((id) =>
  id.toLowerCase().contains(s.name.toLowerCase()) ||
      id == s.id.toString());

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    return WillPopScope(
      onWillPop: () async {
        await _confirmEndSession();
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0F1A),
        body: _isStarting
            ? _buildLoading('Starting live session…')
            : _errorMessage != null
            ? _buildError()
            : _isEndingSession
            ? _buildLoading('Ending session & saving recording…',
            color: Colors.redAccent)
            : _buildLiveUI(),
      ),
    );
  }

  Widget _buildLoading(String msg, {Color color = const Color(0xFF4F8EF7)}) =>
      Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(color: color),
          const SizedBox(height: 20),
          Text(msg,
              style: const TextStyle(color: Colors.white70, fontSize: 16)),
        ]),
      );

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child:
      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
        const SizedBox(height: 16),
        Text(_errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F8EF7)),
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
          onPressed: () {
            setState(() {
              _isStarting = true;
              _errorMessage = null;
            });
            _startSessionAndConnect();
          },
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Go Back',
              style: TextStyle(color: Colors.white54)),
        ),
      ]),
    ),
  );

  Widget _buildLiveUI() => Stack(children: [
    _buildVideoGrid(),
    _buildTopBar(),
    Positioned(bottom: 0, left: 0, right: 0, child: _buildControls()),
    if (_showAttendancePanel)
      Positioned(top: 80, right: 12, child: _buildAttendancePanel()),
  ]);

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() => Positioned(
    top: 0,
    left: 0,
    right: 0,
    child: Container(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.sessionName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                Text('Duration: ${_formatDuration(_elapsed)}',
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 12)),
              ]),
        ),
        // LIVE badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(6)),
          child: const Text('LIVE',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 10),
        // Participants + attendance badge
        GestureDetector(
          onTap: () => setState(
                  () => _showAttendancePanel = !_showAttendancePanel),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: const Color(0x884F8EF7),
                borderRadius: BorderRadius.circular(20)),
            child: Row(children: [
              const Icon(Icons.people, color: Colors.white, size: 16),
              const SizedBox(width: 4),
              Text('$_participantCount',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
              if (_enrolledStudents.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(width: 1, height: 14, color: Colors.white30),
                const SizedBox(width: 6),
                const Icon(Icons.checklist,
                    color: Colors.greenAccent, size: 14),
                const SizedBox(width: 2),
                Text('$_presentCount/${_enrolledStudents.length}',
                    style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ],
            ]),
          ),
        ),
      ]),
    ),
  );

  // ── Video grid ────────────────────────────────────────────────────────────

  Widget _buildVideoGrid() {
    // ── Screen share active → PiP layout ─────────────────────────────────
    if (_isScreenSharing && _screenShareTrack != null) {
      // Get the live camera track (camera stays ON during screen share)
      final VideoTrack? cameraTrack = _localParticipant?.videoTrackPublications
          .where((p) => p.source == TrackSource.camera)
          .map((p) => p.track)
          .whereType<VideoTrack>()
          .firstOrNull;

      // Decide which goes in the main frame and which is the PiP corner
      final Widget mainWidget = _isPipCameraMain
          ? _buildCameraMainWidget(cameraTrack)   // camera is main
          : _buildScreenShareMainWidget();          // screen share is main

      final Widget pipWidget = _isPipCameraMain
          ? _buildScreenSharePip()                 // screen share in corner
          : _buildCameraPip(cameraTrack);          // camera in corner

      return Stack(children: [
        // Main frame fills the entire area
        Positioned.fill(child: mainWidget),

        // PiP corner — draggable, tappable to swap
        Positioned(
          right: 12,
          bottom: 120, // above the controls bar
          child: GestureDetector(
            onTap: () => setState(() => _isPipCameraMain = !_isPipCameraMain),
            child: Container(
              width: 110,
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white38, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(fit: StackFit.expand, children: [
                  pipWidget,
                  // Tap hint overlay
                  Positioned(
                    bottom: 4, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Tap to swap',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 8)),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),

        // Screen share badge (top-left of main frame)
        if (!_isPipCameraMain)
          Positioned(
            top: 8, left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withOpacity(0.85),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.screen_share, color: Colors.white, size: 12),
                SizedBox(width: 4),
                Text('Screen Share',
                    style: TextStyle(color: Colors.white, fontSize: 11)),
              ]),
            ),
          ),
      ]);
    }

    // ── Normal camera grid (no screen share) ─────────────────────────────
    final tiles = <Widget>[
      _buildLocalTile(),
      for (final rp in _remoteParticipants)
        _RemoteParticipantTile(participant: rp),
    ];
    if (tiles.length == 1) return tiles.first;
    return GridView.count(
      crossAxisCount: tiles.length <= 2 ? 1 : 2,
      childAspectRatio: 3 / 4,
      children: tiles,
    );
  }

  // Screen share fills full frame
  Widget _buildScreenShareMainWidget() {
    return Container(
      color: Colors.black,
      child: VideoTrackRenderer(_screenShareTrack!),
    );
  }

  // Screen share as tiny PiP
  Widget _buildScreenSharePip() {
    return Container(
      color: Colors.black,
      child: VideoTrackRenderer(_screenShareTrack!),
    );
  }

  // Camera fills full frame (when user swapped)
  Widget _buildCameraMainWidget(VideoTrack? cameraTrack) {
    if (cameraTrack == null || _isCameraOff) {
      return _AvatarTile(name: 'Camera Off', isMuted: _isMicMuted);
    }
    return Stack(children: [
      Positioned.fill(child: VideoTrackRenderer(cameraTrack)),
      Positioned(
        top: 8, left: 8,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.8),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.videocam, color: Colors.white, size: 12),
            SizedBox(width: 4),
            Text('Camera', style: TextStyle(color: Colors.white, fontSize: 11)),
          ]),
        ),
      ),
    ]);
  }

  // Camera as tiny PiP corner widget
  Widget _buildCameraPip(VideoTrack? cameraTrack) {
    if (cameraTrack == null || _isCameraOff) {
      return Container(
        color: const Color(0xFF1A1D2E),
        child: const Center(
          child: Icon(Icons.videocam_off, color: Colors.white54, size: 28),
        ),
      );
    }
    return VideoTrackRenderer(cameraTrack);
  }

  Widget _buildLocalTile() {
    if (_isCameraOff || _localParticipant == null) {
      return _AvatarTile(name: 'You (Teacher)', isMuted: _isMicMuted);
    }
    return _LocalParticipantTile(
      participant: _localParticipant!,
      isMuted: _isMicMuted,
      label: 'You (Teacher)',
    );
  }

  // Small thumbnail for teacher's camera — shown in screen-share strip
  Widget _buildCameraThumbnail() {
    final VideoTrack? track = _localParticipant?.videoTrackPublications
        .where((p) => p.source == TrackSource.camera)
        .map((p) => p.track)
        .whereType<VideoTrack>()
        .firstOrNull;

    return _ThumbnailBox(
      track: track,
      label: 'You',
    );
  }

  // Small thumbnail for a remote participant's camera
  Widget _buildRemoteThumbnail(RemoteParticipant rp) {
    final VideoTrack? track = rp.videoTrackPublications
        .where((p) => p.source == TrackSource.camera)
        .map((p) => p.track)
        .whereType<VideoTrack>()
        .firstOrNull;

    return _ThumbnailBox(
      track: track,
      label: rp.name ?? rp.identity,
    );
  }

  // ── Attendance panel ──────────────────────────────────────────────────────
  //
  //  Shows ALL enrolled students of the course (from API).
  //  Real-time "In room / Not joined" matched from LiveKit identities.
  //  Teacher can manually toggle Present / Absent per student.

  Widget _buildAttendancePanel() {
    return Container(
      width: 260,
      constraints: const BoxConstraints(maxHeight: 460),
      decoration: BoxDecoration(
        color: const Color(0xEE1A1D2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Icon(Icons.checklist, color: Colors.greenAccent, size: 18),
            const SizedBox(width: 6),
            Text(
              'Attendance  ($_presentCount / ${_enrolledStudents.length})',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () =>
                  setState(() => _showAttendancePanel = false),
              child:
              const Icon(Icons.close, color: Colors.white54, size: 18),
            ),
          ]),
        ),
        const Divider(color: Colors.white12, height: 1),

        // Student list — ALL enrolled students of this course
        Flexible(
          child: _enrolledStudents.isEmpty
              ? const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No enrolled students found.',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          )
              : ListView.builder(
            shrinkWrap: true,
            itemCount: _enrolledStudents.length,
            itemBuilder: (_, i) {
              final s = _enrolledStudents[i];
              final inRoom = _isInRoom(s);
              final isPresent = _attendanceMap[s.id] ?? false;
              return _AttendanceTile(
                student: s,
                isPresent: isPresent,
                isInRoom: inRoom,
                onToggle: () => _toggleAttendance(s.id),
              );
            },
          ),
        ),

        // Bulk actions
        if (_enrolledStudents.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.greenAccent,
                    side: const BorderSide(color: Colors.greenAccent),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => setState(() {
                    for (final s in _enrolledStudents) {
                      _attendanceMap[s.id] = true;
                    }
                  }),
                  child: const Text('All Present',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => setState(() {
                    for (final s in _enrolledStudents) {
                      _attendanceMap[s.id] = false;
                    }
                  }),
                  child: const Text('All Absent',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  Widget _buildControls() => Container(
    padding: const EdgeInsets.fromLTRB(8, 12, 8, 32),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [Color(0xDD000000), Colors.transparent],
      ),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ControlButton(
          icon: _isMicMuted ? Icons.mic_off : Icons.mic,
          label: _isMicMuted ? 'Unmute' : 'Mute',
          active: _isMicMuted,
          onTap: _toggleMic,
        ),
        _ControlButton(
          icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
          label: _isCameraOff ? 'Cam On' : 'Cam Off',
          active: _isCameraOff,
          onTap: _toggleCamera,
        ),
        _ControlButton(
          icon: Icons.flip_camera_ios,
          label: _isFrontCamera ? 'Rear' : 'Front',
          onTap: _switchCamera,
        ),
        _ControlButton(
          icon: _isScreenSharing
              ? Icons.stop_screen_share
              : Icons.screen_share,
          label: _isScreenSharing ? 'Stop' : 'Share',
          active: _isScreenSharing,
          activeColor: Colors.orangeAccent,
          onTap: _toggleScreenShare,
        ),
        _ControlButton(
          icon: Icons.checklist,
          label: 'Attendance',
          activeColor: Colors.greenAccent,
          active: _showAttendancePanel,
          onTap: () => setState(
                  () => _showAttendancePanel = !_showAttendancePanel),
        ),
        _ControlButton(
          icon: Icons.call_end,
          label: 'End',
          backgroundColor: Colors.redAccent,
          onTap: _confirmEndSession,
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Attendance tile
// ─────────────────────────────────────────────────────────────────────────────

class _AttendanceTile extends StatelessWidget {
  final EnrolledStudent student;
  final bool isPresent;
  final bool isInRoom;
  final VoidCallback onToggle;

  const _AttendanceTile({
    required this.student,
    required this.isPresent,
    required this.isInRoom,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    child: Row(children: [
      CircleAvatar(
        radius: 18,
        backgroundColor: const Color(0xFF2C3154),
        backgroundImage: student.imageUrl != null
            ? NetworkImage(student.imageUrl!)
            : null,
        child: student.imageUrl == null
            ? Text(
          student.name.isNotEmpty
              ? student.name[0].toUpperCase()
              : '?',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold),
        )
            : null,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(student.name,
                  style:
                  const TextStyle(color: Colors.white, fontSize: 13),
                  overflow: TextOverflow.ellipsis),
              Text(
                isInRoom ? '● In room' : '○ Not joined',
                style: TextStyle(
                    color:
                    isInRoom ? Colors.greenAccent : Colors.white38,
                    fontSize: 10),
              ),
            ]),
      ),
      // Present / Absent toggle
      GestureDetector(
        onTap: onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 76,
          height: 28,
          decoration: BoxDecoration(
            color: isPresent
                ? Colors.green.withOpacity(0.25)
                : Colors.red.withOpacity(0.20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isPresent ? Colors.greenAccent : Colors.redAccent,
            ),
          ),
          child: Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(isPresent ? Icons.check : Icons.close,
                  size: 12,
                  color: isPresent
                      ? Colors.greenAccent
                      : Colors.redAccent),
              const SizedBox(width: 3),
              Text(
                isPresent ? 'Present' : 'Absent',
                style: TextStyle(
                  color: isPresent
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ]),
          ),
        ),
      ),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final Color? backgroundColor;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.activeColor = Colors.redAccent,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: backgroundColor ?? const Color(0x554F8EF7),
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            color: active ? activeColor : Colors.white, size: 22),
      ),
      const SizedBox(height: 4),
      Text(label,
          style: const TextStyle(color: Colors.white70, fontSize: 10)),
    ]),
  );
}

class _AvatarTile extends StatelessWidget {
  final String name;
  final bool isMuted;
  const _AvatarTile({required this.name, required this.isMuted});

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFF1A1D2E),
    child: Center(
      child:
      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: const Color(0xFF2C3154),
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 8),
        Text(name,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 4),
        Icon(isMuted ? Icons.mic_off : Icons.mic,
            color: isMuted ? Colors.redAccent : Colors.green, size: 18),
      ]),
    ),
  );
}

class _RemoteParticipantTile extends StatelessWidget {
  final RemoteParticipant participant;

  const _RemoteParticipantTile({required this.participant});

  @override
  Widget build(BuildContext context) {
    final track = participant.videoTrackPublications
        .where((p) => p.source == TrackSource.camera)
        .map((p) => p.track)
        .whereType<VideoTrack>()
        .firstOrNull;
    return Stack(children: [
      track != null
          ? VideoTrackRenderer(track)
          : _AvatarTile(
          name: participant.name ?? participant.identity,
          isMuted: !participant.isMicrophoneEnabled()),
      Positioned(
        bottom: 8,
        left: 8,
        child: _NameBadge(
          name: participant.name ?? participant.identity,
          isMuted: !participant.isMicrophoneEnabled(),
        ),
      ),
    ]);
  }
}
  class _LocalParticipantTile extends StatelessWidget {
  final LocalParticipant participant;
  final bool isMuted;
  final String label;
  const _LocalParticipantTile(
  {required this.participant,
  required this.isMuted,
  this.label = 'You'});

  @override
  Widget build(BuildContext context) {
  final track = participant.videoTrackPublications
      .where((p) => p.source == TrackSource.camera)
      .map((p) => p.track)
      .whereType<VideoTrack>()
      .firstOrNull;
  return Stack(children: [
  track != null
  ? VideoTrackRenderer(track)
      : _AvatarTile(name: label, isMuted: isMuted),
  Positioned(
  bottom: 8,
  left: 8,
  child: _NameBadge(name: label, isMuted: isMuted)),
  ]);
  }
  }

  class _NameBadge extends StatelessWidget {
  final String name;
  final bool isMuted;
  const _NameBadge({required this.name, required this.isMuted});

  @override
  Widget build(BuildContext context) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  decoration: BoxDecoration(
  color: const Color(0xAA000000),
  borderRadius: BorderRadius.circular(8)),
  child: Row(mainAxisSize: MainAxisSize.min, children: [
  Icon(isMuted ? Icons.mic_off : Icons.mic,
  color: isMuted ? Colors.redAccent : Colors.green, size: 13),
  const SizedBox(width: 4),
  Text(name,
  style: const TextStyle(color: Colors.white, fontSize: 12)),
  ]),
  );
  }

// Reusable small camera thumbnail for the screen-share strip
  class _ThumbnailBox extends StatelessWidget {
  final VideoTrack? track;
  final String label;

  const _ThumbnailBox({required this.track, required this.label});

  @override
  Widget build(BuildContext context) => Container(
  width: 72,
  margin: const EdgeInsets.only(right: 6),
  decoration: BoxDecoration(
  color: const Color(0xFF1A1D2E),
  borderRadius: BorderRadius.circular(8),
  border: Border.all(color: Colors.white24),
  ),
  child: ClipRRect(
  borderRadius: BorderRadius.circular(8),
  child: Stack(fit: StackFit.expand, children: [
  track != null
  ? VideoTrackRenderer(track!)
      : const Center(
  child: Icon(Icons.videocam_off,
  color: Colors.white54, size: 20)),
  Positioned(
  bottom: 2, left: 0, right: 0,
  child: Center(
  child: Text(label,
  style: const TextStyle(color: Colors.white, fontSize: 9),
  overflow: TextOverflow.ellipsis),
  ),
  ),
  ]),
  ),
  );
  }

  extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
  for (final e in this) {
  if (test(e)) return e;
  }
  return null;
  }
  }