import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

import '../../config/app_config.dart';

/// ─────────────────────────────────────────────────────────────────────────────
///  StudentLiveSessionScreen
///
///  APIs:
///    GET /api/v1/live-sessions/{session_id}/join  → { ws_url, token }
///    GET /api/v1/courses/{course_id}/students     → List<EnrolledStudent>
///
///  Screen-share fix (Android):
///    Call Helper.requestCapturePermission() FIRST while the app is in the
///    foreground. This fires the system picker without backgrounding the app.
///    Then createScreenShareTrack() runs with permission already granted —
///    no second picker, app stays alive.
/// ─────────────────────────────────────────────────────────────────────────────

// ── Model ─────────────────────────────────────────────────────────────────────

class _EnrolledStudent {
  final int id;
  final String name;
  final String? imageUrl;

  _EnrolledStudent({required this.id, required this.name, this.imageUrl});

  factory _EnrolledStudent.fromJson(Map<String, dynamic> j) => _EnrolledStudent(
    id: j['id'] as int,
    name: j['name'] as String? ?? '',
    imageUrl: j['image_url'] as String?,
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class StudentLiveSessionScreen extends StatefulWidget {
  final int sessionId;
  final int courseId;       // needed to fetch enrolled students
  final String sessionName;
  final String authToken;

  const StudentLiveSessionScreen({
    super.key,
    required this.sessionId,
    required this.courseId,
    required this.sessionName,
    required this.authToken,
  });

  @override
  State<StudentLiveSessionScreen> createState() =>
      _StudentLiveSessionScreenState();
}

class _StudentLiveSessionScreenState extends State<StudentLiveSessionScreen>
    with WidgetsBindingObserver {
  // ── LiveKit ───────────────────────────────────────────────────────────────
  Room? _room;
  LocalParticipant? _localParticipant;
  final List<RemoteParticipant> _remoteParticipants = [];

  // ── Local tracks ──────────────────────────────────────────────────────────
  LocalVideoTrack? _localVideoTrack;
  LocalVideoTrack? _screenShareTrack;

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _isConnecting = true;
  bool _isMicMuted = false;
  bool _isCameraOff = false;
  bool _isFrontCamera = true;
  bool _isScreenSharing = false;
  bool _showParticipantsList = false;
  String? _errorMessage;

  // ── Enrolled students (participants panel) ────────────────────────────────
  List<_EnrolledStudent> _enrolledStudents = [];
  final Set<String> _liveIdentities = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchJoinUrlAndConnect();
    _fetchEnrolledStudents();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disconnect();
    super.dispose();
  }

  // ── API ───────────────────────────────────────────────────────────────────

  Future<void> _fetchJoinUrlAndConnect() async {
    try {
      final res = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/api/v1/live-sessions/${widget.sessionId}/join'),
        headers: {'Authorization': 'Bearer ${widget.authToken}'},
      );
      if (res.statusCode != 200) {
        setState(() {
          _isConnecting = false;
          _errorMessage =
          'Failed to join (${res.statusCode}). Session may not be live yet.';
        });
        return;
      }
      final data = json.decode(res.body);
      await _connectToRoom(
          data['ws_url'] as String, data['token'] as String);
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _errorMessage = 'Network error: $e';
      });
    }
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
              list.map((j) => _EnrolledStudent.fromJson(j)).toList();
        });
      }
    } catch (_) {
      // non-fatal — panel still shows live participants
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

    try {
      await room.connect(wsUrl, token,
          connectOptions: const ConnectOptions(autoSubscribe: true));

      _localParticipant = room.localParticipant;
      await _localParticipant?.setCameraEnabled(true);
      await _localParticipant?.setMicrophoneEnabled(true);

      _localVideoTrack = _localParticipant?.videoTrackPublications
          .firstWhereOrNull((p) => p.source == TrackSource.camera)
          ?.track;

      setState(() {
        _room = room;
        _isConnecting = false;
        _remoteParticipants.addAll(room.remoteParticipants.values);
        _syncIdentities();
      });
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _errorMessage = 'Could not connect: $e';
      });
    }
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
    if (_localParticipant != null) {
      _liveIdentities.add(_localParticipant!.identity);
    }
  }

  Future<void> _disconnect() async {
    _room?.removeListener(_onRoomUpdate);
    await _room?.disconnect();
    _room = null;
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
  //  WHY THE APP WAS CLOSING:
  //  createScreenShareTrack() on Android fires MediaProjection intent which
  //  moves the app to background while the picker shows → Android kills it.
  //
  //  FIX:
  //  Call Helper.requestCapturePermission() first — this fires the picker
  //  synchronously while the app is still in the FOREGROUND and returns
  //  true/false. Then createScreenShareTrack() finds permission already
  //  granted and creates the track immediately without any picker/background.

  Future<void> _toggleScreenShare() async {
    _isScreenSharing ? await _stopScreenShare() : await _startScreenShare();
  }

  Future<void> _startScreenShare() async {
    try {
      if (Platform.isAndroid) {
        // Step 1: request permission NOW, while in foreground
        final granted = await webrtc.Helper.requestCapturePermission();
        if (!granted) {
          _showSnack('Screen share permission denied.', Colors.redAccent);
          return;
        }
        // Step 2: create track — permission already held, no picker shown
        _screenShareTrack = await LocalVideoTrack.createScreenShareTrack(
          const ScreenShareCaptureOptions(
            useiOSBroadcastExtension: false,
            maxFrameRate: 15,
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
          const ScreenShareCaptureOptions(maxFrameRate: 15),
        );
      }

      await _localParticipant?.publishVideoTrack(_screenShareTrack!);
      setState(() => _isScreenSharing = true);
    } on PlatformException catch (e) {
      debugPrint('Screen share PlatformException: $e');
      _showSnack('Screen share permission was denied.', Colors.redAccent);
    } catch (e) {
      debugPrint('Screen share error: $e');
      _showSnack('Could not start screen share.', Colors.redAccent);
    }
  }

  Future<void> _stopScreenShare() async {
    try {
      if (_screenShareTrack != null) {
        await _localParticipant?.unpublishAllTracks();
        await _screenShareTrack!.stop();
        _screenShareTrack = null;
      }
    } catch (e) {
      debugPrint('Stop screen share error: $e');
    } finally {
      setState(() => _isScreenSharing = false);
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

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2235),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Leave Session',
            style:
            TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to leave?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
              const Text('Stay', style: TextStyle(color: Colors.blue))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      await _disconnect();
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  int get _participantCount =>
      (_room != null ? 1 : 0) + _remoteParticipants.length;

  bool _isInRoom(_EnrolledStudent s) => _liveIdentities.any((id) =>
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
        await _confirmLeave();
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0F1A),
        body: _isConnecting
            ? _buildConnecting()
            : _errorMessage != null
            ? _buildError()
            : _buildLiveUI(),
      ),
    );
  }

  Widget _buildConnecting() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const CircularProgressIndicator(color: Color(0xFF4F8EF7)),
      const SizedBox(height: 20),
      Text('Joining "${widget.sessionName}"…',
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
              _isConnecting = true;
              _errorMessage = null;
            });
            _fetchJoinUrlAndConnect();
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
    if (_showParticipantsList)
      Positioned(top: 80, right: 12, child: _buildParticipantsPanel()),
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
          child: Text(widget.sessionName,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis),
        ),
        _LiveBadge(),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => setState(
                  () => _showParticipantsList = !_showParticipantsList),
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
                const SizedBox(width: 5),
                Container(width: 1, height: 12, color: Colors.white30),
                const SizedBox(width: 5),
                Text('${_enrolledStudents.length} enrolled',
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 11)),
              ],
            ]),
          ),
        ),
      ]),
    ),
  );

  // ── Video grid ────────────────────────────────────────────────────────────

  Widget _buildVideoGrid() {
    final tiles = <Widget>[
      for (final rp in _remoteParticipants)
        _RemoteParticipantTile(participant: rp),
      _buildLocalPreview(),
    ];
    if (tiles.length == 1) return tiles.first;
    return GridView.count(
      crossAxisCount: tiles.length <= 2 ? 1 : 2,
      childAspectRatio: 3 / 4,
      children: tiles,
    );
  }

  Widget _buildLocalPreview() {
    if (_isCameraOff || _localParticipant == null) {
      return _AvatarTile(name: 'You', isMuted: _isMicMuted);
    }
    return _LocalParticipantTile(
        participant: _localParticipant!, isMuted: _isMicMuted);
  }

  // ── Participants panel ────────────────────────────────────────────────────
  //
  //  Shows ALL enrolled students of the course (from API).
  //  Each row shows live "in room" status matched against LiveKit identities.
  //  Extra live participants not in the enrolled list (e.g. teacher) appear
  //  at the bottom.

  Widget _buildParticipantsPanel() {
    final enrolledIds =
    _enrolledStudents.map((s) => s.id.toString()).toSet();
    final extraLive = _remoteParticipants
        .where((rp) => !enrolledIds.contains(rp.identity))
        .toList();

    return Container(
      width: 240,
      constraints: const BoxConstraints(maxHeight: 400),
      decoration: BoxDecoration(
        color: const Color(0xEE1E2235),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            const Icon(Icons.people, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(
              'Students (${_enrolledStudents.length})',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () =>
                  setState(() => _showParticipantsList = false),
              child: const Icon(Icons.close,
                  color: Colors.white54, size: 18),
            ),
          ]),
        ),
        const Divider(color: Colors.white12, height: 1),
        Flexible(
          child: ListView(shrinkWrap: true, children: [
            // Self
            _ParticipantRow(
              name: 'You',
              imageUrl: null,
              isInRoom: true,
              isTeacher: false,
              isSelf: true,
              isMuted: _isMicMuted,
            ),
            // All enrolled students from the course
            ..._enrolledStudents.map((s) {
              final inRoom = _isInRoom(s);
              final liveRp = _remoteParticipants.firstWhereOrNull((rp) =>
              rp.identity
                  .toLowerCase()
                  .contains(s.name.toLowerCase()) ||
                  rp.identity == s.id.toString());
              return _ParticipantRow(
                name: s.name,
                imageUrl: s.imageUrl,
                isInRoom: inRoom,
                isTeacher: false,
                isSelf: false,
                isMuted:
                liveRp != null ? !liveRp.isMicrophoneEnabled() : null,
              );
            }),
            // Extra live participants not in the enrolled list (teacher, etc.)
            ...extraLive.map((rp) => _ParticipantRow(
              name: rp.name ?? rp.identity,
              imageUrl: null,
              isInRoom: true,
              isTeacher:
              rp.metadata?.contains('"role":"teacher"') ?? false,
              isSelf: false,
              isMuted: !rp.isMicrophoneEnabled(),
            )),
          ]),
        ),
      ]),
    );
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  Widget _buildControls() => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
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
          icon: Icons.call_end,
          label: 'Leave',
          backgroundColor: Colors.redAccent,
          onTap: _confirmLeave,
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.circular(6)),
    child: const Text('LIVE',
        style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold)),
  );
}

class _ParticipantRow extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final bool isInRoom;
  final bool isTeacher;
  final bool isSelf;
  final bool? isMuted; // null = not in room

  const _ParticipantRow({
    required this.name,
    required this.imageUrl,
    required this.isInRoom,
    required this.isTeacher,
    required this.isSelf,
    required this.isMuted,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Row(children: [
      CircleAvatar(
        radius: 16,
        backgroundColor: isTeacher
            ? const Color(0xFF4F8EF7)
            : const Color(0xFF2C3154),
        backgroundImage:
        imageUrl != null ? NetworkImage(imageUrl!) : null,
        child: imageUrl == null
            ? Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
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
              Text(isSelf ? 'You' : name,
                  style:
                  const TextStyle(color: Colors.white, fontSize: 13),
                  overflow: TextOverflow.ellipsis),
              Row(children: [
                if (isTeacher)
                  const Text('Teacher · ',
                      style: TextStyle(
                          color: Color(0xFF4F8EF7), fontSize: 10)),
                Text(
                  isInRoom ? '● In room' : '○ Not joined',
                  style: TextStyle(
                      color: isInRoom
                          ? Colors.greenAccent
                          : Colors.white38,
                      fontSize: 10),
                ),
              ]),
            ]),
      ),
      if (isMuted != null)
        Icon(
          isMuted! ? Icons.mic_off : Icons.mic,
          size: 15,
          color: isMuted! ? Colors.redAccent : Colors.green,
        ),
    ]),
  );
}

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
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: backgroundColor ?? const Color(0x554F8EF7),
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            color: active ? activeColor : Colors.white, size: 24),
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
        .firstWhereOrNull((p) => p.source == TrackSource.camera)
        ?.track as VideoTrack?;
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
  const _LocalParticipantTile(
      {required this.participant, required this.isMuted});

  @override
  Widget build(BuildContext context) {
    final track = participant.videoTrackPublications
        .firstWhereOrNull((p) => p.source == TrackSource.camera)
        ?.track as VideoTrack?;
    return Stack(children: [
      track != null
          ? VideoTrackRenderer(track)
          : _AvatarTile(name: 'You', isMuted: isMuted),
      Positioned(
          bottom: 8,
          left: 8,
          child: _NameBadge(name: 'You', isMuted: isMuted)),
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

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}