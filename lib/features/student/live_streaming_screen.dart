//
// import 'dart:async';
// import 'dart:convert';
//
// import 'package:flutter/material.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:provider/provider.dart';
// import 'package:webview_flutter/webview_flutter.dart';
// import 'package:webview_flutter_android/webview_flutter_android.dart'; // Android-specific
//
// import '../teacher/shared/attendance_provider.dart';
// import '../teacher/shared/exams_provider.dart';
// import '../teacher/shared/live_models.dart';
//
// class StudentLiveScreen extends StatefulWidget {
//   final String sessionTitle;
//   final String meetingUrl;
//   final int sessionId;
//   final int courseId;
//
//   const StudentLiveScreen({
//     super.key,
//     required this.sessionTitle,
//     required this.meetingUrl,
//     required this.sessionId,
//     required this.courseId,
//   });
//
//   @override
//   State<StudentLiveScreen> createState() => _StudentLiveScreenState();
// }
//
// class _StudentLiveScreenState extends State<StudentLiveScreen> {
//   late final WebViewController _wvc;
//
//   bool _loading = true;
//   bool _permissionsGranted = false;
//   String? _error;
//   DateTime? _joinTime;
//
//   Timer? _pollTimer;
//   final Set<int> _shownExams = {};
//   bool _examOpen = false;
//   Timer? _cdTimer;
//   int _cdSeconds = 0;
//   final StreamController<int> _cdCtrl = StreamController<int>.broadcast();
//
//   // ── Lifecycle ──────────────────────────────────────────────────────────────
//
//   @override
//   void initState() {
//     super.initState();
//     // Request permissions FIRST, then init WebView
//     WidgetsBinding.instance.addPostFrameCallback((_) async {
//       final granted = await _requestPermissions();
//       if (mounted) {
//         setState(() => _permissionsGranted = granted);
//         if (granted) {
//           _initWebView();
//           _checkIn();
//           _startPoll();
//         }
//       }
//     });
//   }
//
//   @override
//   void dispose() {
//     _pollTimer?.cancel();
//     _cdTimer?.cancel();
//     _cdCtrl.close();
//     super.dispose();
//   }
//
//   // ── Step 1: Request runtime permissions ────────────────────────────────────
//
//   Future<bool> _requestPermissions() async {
//     // Request camera and microphone together
//     final statuses = await [
//       Permission.camera,
//       Permission.microphone,
//     ].request();
//
//     final camOk = statuses[Permission.camera]?.isGranted ?? false;
//     final micOk = statuses[Permission.microphone]?.isGranted ?? false;
//
//     if (!camOk || !micOk) {
//       if (mounted) {
//         _showPermissionDeniedDialog(camOk: camOk, micOk: micOk);
//       }
//     }
//     // Even if camera is denied but mic is granted (or vice versa),
//     // let the WebView load — Daily.co will handle partial access gracefully.
//     return camOk || micOk;
//   }
//
//   void _showPermissionDeniedDialog({required bool camOk, required bool micOk}) {
//     showDialog(
//       context: context,
//       builder: (_) => Directionality(
//         textDirection: TextDirection.rtl,
//         child: AlertDialog(
//           shape:
//               RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//           title: const Text('إذن الوصول مطلوب',
//               style:
//                   TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
//           content: Column(
//               mainAxisSize: MainAxisSize.min,
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 const Text('للانضمام إلى الحصة المباشرة، يرجى السماح بما يلي:',
//                     style: TextStyle(fontFamily: 'Cairo')),
//                 const SizedBox(height: 12),
//                 _PermRow(
//                     icon: Icons.videocam_rounded,
//                     label: 'الكاميرا',
//                     granted: camOk),
//                 const SizedBox(height: 6),
//                 _PermRow(
//                     icon: Icons.mic_rounded,
//                     label: 'الميكروفون',
//                     granted: micOk),
//               ]),
//           actions: [
//             TextButton(
//               onPressed: () => Navigator.pop(context),
//               child: const Text('لاحقاً',
//                   style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
//             ),
//             ElevatedButton(
//               style: ElevatedButton.styleFrom(
//                   backgroundColor: const Color(0xFF185FA5),
//                   shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(10))),
//               onPressed: () {
//                 Navigator.pop(context);
//                 openAppSettings(); // Opens Android app settings
//               },
//               child: const Text('فتح الإعدادات',
//                   style: TextStyle(
//                       fontFamily: 'Cairo',
//                       color: Colors.white,
//                       fontWeight: FontWeight.w700)),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   // ── Step 2: Init WebView with permission handling ─────────────────────────
//
//   void _initWebView() {
//     _wvc = WebViewController()
//       ..setJavaScriptMode(JavaScriptMode.unrestricted)
//       // Allow media playback without requiring a user gesture
//       ..setBackgroundColor(Colors.black)
//       ..setNavigationDelegate(NavigationDelegate(
//         onPageStarted: (_) => setState(() => _loading = true),
//         onPageFinished: (_) => setState(() {
//           _loading = false;
//           _joinTime = DateTime.now();
//         }),
//         onWebResourceError: (e) => setState(() {
//           _error = e.description;
//           _loading = false;
//         }),
//         onNavigationRequest: (_) => NavigationDecision.navigate,
//       ))
//       ..addJavaScriptChannel('DailyBridge', onMessageReceived: _onDailyMsg)
//       ..loadRequest(Uri.parse(widget.meetingUrl));
//
//     // ── Android-specific: handle WebRTC permission requests ────────────────
//     // This is the KEY FIX — without this, WebView blocks camera/mic even
//     // if Android permissions are granted.
//     final androidController = _wvc.platform;
//     if (androidController is AndroidWebViewController) {
//       AndroidWebViewController.enableDebugging(false);
//
//       androidController.setOnShowFileSelector((_) async => []);
//
//       // Grant WebRTC permissions when the WebView requests them
//       androidController.setGeolocationPermissionsPromptCallbacks();
//
//       // THIS IS THE CRITICAL HANDLER for camera/microphone in WebRTC
//       androidController.setOnPlatformPermissionRequest((request) {
//         // Grant all requested resources (camera, microphone, etc.)
//         request.grant();
//       });
//
//       // Enable hardware acceleration for smooth video
//       androidController.setMediaPlaybackRequiresUserGesture(false);
//     }
//
//     // Inject JS to forward Daily.co events to Flutter
//     _wvc.runJavaScript('''
//       window.addEventListener('message', function(e) {
//         if (e.data && e.data.action === 'left-meeting') {
//           DailyBridge.postMessage(JSON.stringify({event: 'left-meeting'}));
//         }
//       });
//     ''');
//   }
//
//   void _onDailyMsg(JavaScriptMessage msg) {
//     try {
//       final d = jsonDecode(msg.message) as Map<String, dynamic>;
//       if (d['event'] == 'left-meeting') _leave();
//     } catch (_) {}
//   }
//
//   // ── Attendance ─────────────────────────────────────────────────────────────
//
//   Future<void> _checkIn() =>
//       context.read<AttendanceProvider>().checkIn(widget.sessionId);
//
//   Future<void> _leave() async {
//     _pollTimer?.cancel();
//     _cdTimer?.cancel();
//     await context.read<AttendanceProvider>().checkOut(widget.sessionId);
//     if (mounted) Navigator.pop(context);
//   }
//
//   // ── Exam polling ───────────────────────────────────────────────────────────
//
//   void _startPoll() {
//     _poll();
//     _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _poll());
//   }
//
//   Future<void> _poll() async {
//     if (_examOpen || !mounted) return;
//     final exams = await context
//         .read<ExamsProvider>()
//         .fetchActiveExams(widget.courseId, alreadyShownIds: _shownExams);
//     if (exams.isNotEmpty && mounted) {
//       _shownExams.add(exams.first.id);
//       _showExam(exams.first);
//     }
//   }
//
//   void _showExam(ExamModel exam) {
//     _cdSeconds = (exam.duration ?? 10) * 60;
//     _cdTimer?.cancel();
//     setState(() => _examOpen = true);
//
//     _cdTimer = Timer.periodic(const Duration(seconds: 1), (t) {
//       _cdSeconds--;
//       if (!_cdCtrl.isClosed) _cdCtrl.add(_cdSeconds);
//       if (_cdSeconds <= 0) {
//         t.cancel();
//         if (_examOpen && mounted) {
//           Navigator.of(context, rootNavigator: true).pop();
//           _submitExam(exam, {});
//         }
//       }
//     });
//
//     // showDialog<Map<int, String>?>(
//     //   context: context,
//     //   barrierDismissible: false,
//     //   builder: (_) => ExamDialog(
//     //     exam: exam,
//     //     countdownStream: _cdCtrl.stream,
//     //     initialSeconds: _cdSeconds,
//     //     onSubmit: (answers) {
//     //       Navigator.of(context, rootNavigator: true).pop(answers);
//     //     },
//     //   ),
//     // ).then((answers) {
//     //   _cdTimer?.cancel();
//     //   setState(() => _examOpen = false);
//     //   if (answers != null) _submitExam(exam, answers);
//     // });
//   }
//
//   Future<void> _submitExam(ExamModel exam, Map<int, String> answers) async {
//     final ok =
//         await context.read<ExamsProvider>().submitAllAnswers(exam.id, answers);
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(SnackBar(
//       content: Text(ok ? 'تم إرسال الاختبار ✓' : 'حدث خطأ في إرسال الاختبار',
//           style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
//       backgroundColor: ok ? const Color(0xFF1D9E75) : Colors.red,
//       behavior: SnackBarBehavior.floating,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//     ));
//   }
//
//   // ── Build ──────────────────────────────────────────────────────────────────
//
//   @override
//   Widget build(BuildContext context) {
//     return WillPopScope(
//       onWillPop: () async {
//         await _leave();
//         return false;
//       },
//       child: Scaffold(
//         backgroundColor: Colors.black,
//         body: SafeArea(
//             child: _permissionsGranted
//                 ? _buildWebView()
//                 : _buildPermissionWaiting()),
//       ),
//     );
//   }
//
//   Widget _buildPermissionWaiting() => Center(
//           child: Column(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           const CircularProgressIndicator(color: Colors.white),
//           const SizedBox(height: 16),
//           const Text('جاري طلب الأذونات…',
//               style: TextStyle(color: Colors.white70, fontFamily: 'Cairo')),
//           const SizedBox(height: 24),
//           ElevatedButton(
//             onPressed: () async {
//               final ok = await _requestPermissions();
//               if (ok && mounted) {
//                 setState(() => _permissionsGranted = true);
//                 _initWebView();
//                 _checkIn();
//                 _startPoll();
//               }
//             },
//             style: ElevatedButton.styleFrom(
//                 backgroundColor: const Color(0xFF185FA5)),
//             child: const Text('إعادة طلب الإذن',
//                 style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
//           ),
//         ],
//       ));
//
//   Widget _buildWebView() => Stack(children: [
//         // WebView (only rendered after permissions granted + _initWebView called)
//         if (_error == null && _permissionsGranted)
//           WebViewWidget(controller: _wvc),
//
//         // Error screen
//         if (_error != null)
//           _ErrorView(
//               error: _error!,
//               onRetry: () {
//                 setState(() {
//                   _error = null;
//                   _loading = true;
//                 });
//                 _wvc.loadRequest(Uri.parse(widget.meetingUrl));
//               }),
//
//         // Loading overlay
//         if (_loading && _error == null)
//           Container(
//             color: Colors.black,
//             child: const Center(
//                 child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 CircularProgressIndicator(color: Colors.white),
//                 SizedBox(height: 16),
//                 Text('جاري الاتصال بالحصة المباشرة…',
//                     style:
//                         TextStyle(color: Colors.white70, fontFamily: 'Cairo')),
//               ],
//             )),
//           ),
//
//         // Top bar
//         if (_error == null)
//           Positioned(
//             top: 0,
//             left: 0,
//             right: 0,
//             child: _TopBar(title: widget.sessionTitle, onLeave: _leave),
//           ),
//
//         // Attendance strip
//         if (!_loading && _error == null)
//           Positioned(
//             bottom: 16,
//             left: 16,
//             right: 16,
//             child: _AttendanceStrip(
//                 sessionId: widget.sessionId, joinTime: _joinTime),
//           ),
//       ]);
// }
//
// // ── Permission row widget ─────────────────────────────────────────────────────
//
// class _PermRow extends StatelessWidget {
//   final IconData icon;
//   final String label;
//   final bool granted;
//
//   const _PermRow(
//       {required this.icon, required this.label, required this.granted});
//
//   @override
//   Widget build(BuildContext context) => Row(children: [
//         Icon(icon,
//             size: 18, color: granted ? const Color(0xFF1D9E75) : Colors.orange),
//         const SizedBox(width: 8),
//         Text(label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 14)),
//         const Spacer(),
//         Container(
//           padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
//           decoration: BoxDecoration(
//               color: (granted ? const Color(0xFF1D9E75) : Colors.orange)
//                   .withValues(alpha: 0.1),
//               borderRadius: BorderRadius.circular(6)),
//           child: Text(granted ? 'مسموح' : 'مرفوض',
//               style: TextStyle(
//                   fontFamily: 'Cairo',
//                   fontSize: 11,
//                   fontWeight: FontWeight.w700,
//                   color: granted ? const Color(0xFF1D9E75) : Colors.orange)),
//         ),
//       ]);
// }
//
// // ── Reuse TopBar, AttendanceStrip, ErrorView, ExamDialog from previous file ───
// // (Copy them here or import from shared barrel file)
//
// class _TopBar extends StatelessWidget {
//   final String title;
//   final VoidCallback onLeave;
//
//   const _TopBar({required this.title, required this.onLeave});
//
//   @override
//   Widget build(BuildContext context) => Container(
//         height: 56,
//         decoration: BoxDecoration(
//             gradient: LinearGradient(
//                 begin: Alignment.topCenter,
//                 end: Alignment.bottomCenter,
//                 colors: [
//               Colors.black.withValues(alpha: 0.85),
//               Colors.transparent
//             ])),
//         child: Row(children: [
//           IconButton(
//               icon: const Icon(Icons.arrow_back_ios_new,
//                   color: Colors.white, size: 20),
//               onPressed: onLeave),
//           Expanded(
//               child: Text(title,
//                   style: const TextStyle(
//                       color: Colors.white,
//                       fontFamily: 'Cairo',
//                       fontSize: 15,
//                       fontWeight: FontWeight.w600),
//                   maxLines: 1,
//                   overflow: TextOverflow.ellipsis)),
//           Container(
//             margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
//             padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
//             decoration: BoxDecoration(
//                 color: Colors.red, borderRadius: BorderRadius.circular(12)),
//             child: const Row(mainAxisSize: MainAxisSize.min, children: [
//               Icon(Icons.circle, color: Colors.white, size: 7),
//               SizedBox(width: 5),
//               Text('LIVE',
//                   style: TextStyle(
//                       color: Colors.white,
//                       fontSize: 11,
//                       fontWeight: FontWeight.w800,
//                       letterSpacing: 1)),
//             ]),
//           ),
//         ]),
//       );
// }
//
// class _AttendanceStrip extends StatelessWidget {
//   final int sessionId;
//   final DateTime? joinTime;
//
//   const _AttendanceStrip({required this.sessionId, this.joinTime});
//
//   @override
//   Widget build(BuildContext context) {
//     final prov = context.watch<AttendanceProvider>();
//     final checkedIn = prov.isCheckedIn(sessionId);
//     final record = prov.myRecord(sessionId);
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
//       decoration: BoxDecoration(
//           color: Colors.black.withValues(alpha: 0.72),
//           borderRadius: BorderRadius.circular(14),
//           border: Border.all(
//               color: checkedIn ? const Color(0xFF1D9E75) : Colors.white24)),
//       child: Row(children: [
//         Icon(checkedIn ? Icons.wifi_rounded : Icons.wifi_off_rounded,
//             color: checkedIn ? const Color(0xFF1D9E75) : Colors.white54,
//             size: 18),
//         const SizedBox(width: 8),
//         Expanded(
//             child: Text(
//                 checkedIn
//                     ? 'متصل${record?.checkInLabel != null ? " • دخلت ${record!.checkInLabel}" : ""}'
//                     : 'جاري تسجيل الحضور…',
//                 style: const TextStyle(
//                     color: Colors.white, fontFamily: 'Cairo', fontSize: 12))),
//         if (checkedIn)
//           GestureDetector(
//             onTap: () => context.read<AttendanceProvider>().checkOut(sessionId),
//             child: Container(
//               padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
//               decoration: BoxDecoration(
//                   color: Colors.red.withValues(alpha: 0.8),
//                   borderRadius: BorderRadius.circular(8)),
//               child: const Text('مغادرة',
//                   style: TextStyle(
//                       color: Colors.white,
//                       fontFamily: 'Cairo',
//                       fontSize: 11,
//                       fontWeight: FontWeight.w700)),
//             ),
//           ),
//       ]),
//     );
//   }
// }
//
// class _ErrorView extends StatelessWidget {
//   final String error;
//   final VoidCallback onRetry;
//
//   const _ErrorView({required this.error, required this.onRetry});
//
//   @override
//   Widget build(BuildContext context) => Center(
//           child: Padding(
//         padding: const EdgeInsets.all(32),
//         child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
//           const Icon(Icons.signal_wifi_off_rounded,
//               size: 72, color: Colors.white54),
//           const SizedBox(height: 16),
//           const Text('تعذّر الاتصال بالحصة',
//               style: TextStyle(
//                   color: Colors.white,
//                   fontFamily: 'Cairo',
//                   fontSize: 18,
//                   fontWeight: FontWeight.w700)),
//           const SizedBox(height: 8),
//           Text(error,
//               textAlign: TextAlign.center,
//               style: const TextStyle(
//                   color: Colors.white54, fontFamily: 'Cairo', fontSize: 13)),
//           const SizedBox(height: 24),
//           ElevatedButton.icon(
//             onPressed: onRetry,
//             icon: const Icon(Icons.refresh_rounded),
//             label: const Text('إعادة المحاولة',
//                 style: TextStyle(fontFamily: 'Cairo')),
//             style: ElevatedButton.styleFrom(
//                 backgroundColor: const Color(0xFF185FA5),
//                 foregroundColor: Colors.white,
//                 padding:
//                     const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
//                 shape: RoundedRectangleBorder(
//                     borderRadius: BorderRadius.circular(12))),
//           ),
//         ]),
//       ));
// }

// ── ExamDialog  (same as before — kept here for completeness) ─────────────────
// Import from live_models or copy the full ExamDialog class here.
// See student/live_streaming_screen.dart from the previous delivery.


/// student_live_screen.dart
///
/// LiveKit live session screen for students.
/// Call GET /live-sessions/{id}/join → get {ws_url, token} → open this screen.
///
/// Features:
///   • Video grid of all participants
///   • Mute/unmute own mic and camera
///   • Screen share (view teacher's share)
///   • Raise hand (sends data message to teacher)
///   • In-session chat via LiveKit data channel

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../config/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────

class StudentLiveScreen extends StatefulWidget {
  final String sessionTitle;
  final String wsUrl;       // LIVEKIT_PUBLIC_URL from API
  final String token;       // student JWT from /live-sessions/{id}/join
  final int    sessionId;

  const StudentLiveScreen({
    super.key,
    required this.sessionTitle,
    required this.wsUrl,
    required this.token,
    required this.sessionId,
  });

  @override
  State<StudentLiveScreen> createState() => _StudentLiveScreenState();
}

class _StudentLiveScreenState extends State<StudentLiveScreen> {

  // ── LiveKit ───────────────────────────────────────────────────────────────
  late final Room _room;
  late final EventsListener<RoomEvent> _listener;

  bool _cameraOn   = true;
  bool _micOn      = true;
  bool _handRaised = false;
  bool _connecting = true;
  bool _chatOpen   = false;
  String? _error;

  final List<RemoteParticipant> _remoteParticipants = [];

  // ── Chat ──────────────────────────────────────────────────────────────────
  final List<_ChatMsg>         _messages    = [];
  final TextEditingController  _chatCtrl    = TextEditingController();
  final ScrollController       _chatScroll  = ScrollController();

  // ─────────────────────────────────────────────────────────────────────────
  //  Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _room     = Room();
    _listener = _room.createListener();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void dispose() {
    _listener.dispose();
    _room.disconnect();
    _room.dispose();
    _chatCtrl.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Connect
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _connect() async {
    await [Permission.microphone, Permission.camera].request();
    _setupListeners();

    try {
      await _room.connect(
        widget.wsUrl,
        widget.token,
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast:       true,
          defaultVideoPublishOptions: VideoPublishOptions(simulcast: true),
          defaultAudioPublishOptions: AudioPublishOptions(dtx: true),
        ),
      );
      await _room.localParticipant?.setCameraEnabled(true);
      await _room.localParticipant?.setMicrophoneEnabled(true);

      if (mounted) setState(() => _connecting = false);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _connecting = false; });
    }
  }

  void _setupListeners() {
    _listener
      ..on<RoomConnectedEvent>((_) {
        if (mounted) setState(() {
          _remoteParticipants
            ..clear()
            ..addAll(_room.remoteParticipants.values);
        });
      })
      ..on<ParticipantConnectedEvent>((e) {
        if (mounted) setState(() => _remoteParticipants.add(e.participant));
      })
      ..on<ParticipantDisconnectedEvent>((e) {
        if (mounted) setState(() => _remoteParticipants.remove(e.participant));
      })
      ..on<TrackSubscribedEvent>((_) { if (mounted) setState(() {}); })
      ..on<TrackUnsubscribedEvent>((_) { if (mounted) setState(() {}); })
      ..on<TrackMutedEvent>((_) { if (mounted) setState(() {}); })
      ..on<TrackUnmutedEvent>((_) { if (mounted) setState(() {}); })
      ..on<DataReceivedEvent>((e) => _onDataReceived(e))
      ..on<RoomDisconnectedEvent>((e) {
        if (!mounted) return;
        if (e.reason == DisconnectReason.roomDeleted) {
          // Teacher ended the session
          _showSessionEndedDialog();
        } else if (e.reason != DisconnectReason.clientInitiated) {
          _snack('انقطع الاتصال', AppTheme.danger);
        }
      });
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Controls
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _toggleCamera() async {
    await _room.localParticipant?.setCameraEnabled(!_cameraOn);
    if (mounted) setState(() => _cameraOn = !_cameraOn);
  }

  Future<void> _toggleMic() async {
    await _room.localParticipant?.setMicrophoneEnabled(!_micOn);
    if (mounted) setState(() => _micOn = !_micOn);
  }

  Future<void> _toggleHand() async {
    final raised = !_handRaised;
    if (mounted) setState(() => _handRaised = raised);
    // Broadcast to all participants via data channel
    await _room.localParticipant?.publishData(
      utf8.encode(jsonEncode({
        'type':    'raise_hand',
        'raised':  raised,
        'sender':  _room.localParticipant?.name ?? 'طالب',
      })),
      reliable: true,
    );
    if (raised) _snack('تم رفع يدك ✋', AppTheme.primary);
  }

  Future<void> _sendChat() async {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;
    _chatCtrl.clear();

    final msg = _ChatMsg(
      sender:    _room.localParticipant?.name ?? 'أنت',
      text:      text,
      isMe:      true,
      timestamp: DateTime.now(),
    );
    if (mounted) setState(() => _messages.add(msg));
    _scrollChatToBottom();

    await _room.localParticipant?.publishData(
      utf8.encode(jsonEncode({
        'type':   'chat',
        'text':   text,
        'sender': _room.localParticipant?.name ?? 'طالب',
      })),
      reliable: true,
    );
  }

  void _onDataReceived(DataReceivedEvent e) {
    try {
      final d = jsonDecode(utf8.decode(e.data)) as Map<String, dynamic>;
      final type = d['type'] as String?;

      if (type == 'chat' && mounted) {
        setState(() => _messages.add(_ChatMsg(
          sender:    d['sender'] as String? ?? 'مشارك',
          text:      d['text']   as String? ?? '',
          isMe:      false,
          timestamp: DateTime.now(),
        )));
        _scrollChatToBottom();
      }

      if (type == 'raise_hand' && mounted) {
        final name   = d['sender'] as String? ?? 'طالب';
        final raised = d['raised'] as bool? ?? false;
        if (raised) _snack('✋ $name رفع يده', AppTheme.primary);
      }
    } catch (_) {}
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(
          _chatScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve:    Curves.easeOut,
        );
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Leave
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _confirmLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('مغادرة الحصة', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          content: const Text('هل تريد مغادرة الحصة المباشرة؟', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء', style: TextStyle(color: Colors.white54, fontFamily: 'Cairo'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('مغادرة', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await _room.disconnect();
      if (mounted) Navigator.pop(context);
    }
  }

  void _showSessionEndedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('انتهت الحصة', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          content: const Text('أنهى المعلم الحصة المباشرة.\nسيتوفر التسجيل قريباً.',
              style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', height: 1.6)),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () { Navigator.pop(ctx); Navigator.pop(context); },
              child: const Text('حسناً', style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(msg, style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
      backgroundColor: color, behavior: SnackBarBehavior.floating,
      shape:           RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_connecting) {
      return const Scaffold(backgroundColor: Colors.black,
          body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircularProgressIndicator(color: Colors.white), SizedBox(height: 16),
            Text('جاري الانضمام للحصة…', style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
          ])));
    }

    if (_error != null) {
      return Scaffold(backgroundColor: Colors.black,
          body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.signal_wifi_off_rounded, size: 72, color: Colors.white54), const SizedBox(height: 16),
            const Text('تعذّر الاتصال', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.w700)),
            Padding(padding: const EdgeInsets.all(16),
                child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontFamily: 'Cairo', fontSize: 12))),
            ElevatedButton.icon(
              onPressed: () { setState(() { _error = null; _connecting = true; }); _connect(); },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة', style: TextStyle(fontFamily: 'Cairo')),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
            ),
          ])));
    }

    return PopScope(
      canPop: false, onPopInvoked: (_) => _confirmLeave(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(child: Stack(children: [

          // ── Video + optional chat panel ─────────────────────────────────
          Row(children: [
            // Video grid
            Expanded(child: _VideoGrid(
              local:   _room.localParticipant,
              remotes: _remoteParticipants,
            )),
            // Chat slide-in panel
            if (_chatOpen)
              _ChatPanel(
                messages:   _messages,
                controller: _chatCtrl,
                scroll:     _chatScroll,
                onSend:     _sendChat,
              ),
          ]),

          // ── Top bar ─────────────────────────────────────────────────────
          Positioned(top: 0, left: 0, right: 0,
            child: _TopBar(
              title:       widget.sessionTitle,
              chatOpen:    _chatOpen,
              unreadCount: _chatOpen ? 0 : _messages.where((m) => !m.isMe).length,
              onChat:      () { if (mounted) setState(() => _chatOpen = !_chatOpen); },
              onLeave:     _confirmLeave,
            ),
          ),

          // ── Control bar ─────────────────────────────────────────────────
          Positioned(bottom: 0, left: 0, right: 0,
            child: _ControlBar(
              cameraOn:    _cameraOn,
              micOn:       _micOn,
              handRaised:  _handRaised,
              onCamera:    _toggleCamera,
              onMic:       _toggleMic,
              onHand:      _toggleHand,
              onLeave:     _confirmLeave,
            ),
          ),
        ])),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Video Grid
// ─────────────────────────────────────────────────────────────────────────────

class _VideoGrid extends StatelessWidget {
  final LocalParticipant?       local;
  final List<RemoteParticipant> remotes;
  const _VideoGrid({required this.local, required this.remotes});

  @override
  Widget build(BuildContext context) {
    final all = <Participant>[if (local != null) local!, ...remotes];

    if (all.isEmpty) {
      return const Center(child: Text('في انتظار المشاركين…',
          style: TextStyle(color: Colors.white54, fontFamily: 'Cairo', fontSize: 16)));
    }

    // If teacher is sharing screen, show it full-width on top
    final screenTrack = _findScreenShare(remotes);
    if (screenTrack != null) {
      return Column(children: [
        Expanded(flex: 3, child: Container(
          color: Colors.black,
          child: VideoTrackRenderer(screenTrack),
        )),
        SizedBox(height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(4),
            itemCount: all.length,
            itemBuilder: (_, i) => SizedBox(
              width: 80,
              child: _ParticipantTile(participant: all[i], isLocal: all[i] is LocalParticipant),
            ),
          ),
        ),
      ]);
    }

    return GridView.builder(
      padding:      const EdgeInsets.only(bottom: 90, top: 64),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:   all.length == 1 ? 1 : 2,
        childAspectRatio: all.length == 1 ? 16 / 9 : 1,
        crossAxisSpacing: 4, mainAxisSpacing: 4,
      ),
      itemCount:   all.length,
      itemBuilder: (_, i) => _ParticipantTile(
        participant: all[i], isLocal: all[i] is LocalParticipant,
      ),
    );
  }

  VideoTrack? _findScreenShare(List<RemoteParticipant> remotes) {
    for (final p in remotes) {
      for (final pub in p.videoTrackPublications) {
        if (pub.source == TrackSource.screenShareVideo && pub.track != null) {
          return pub.track as VideoTrack;
        }
      }
    }
    return null;
  }
}

class _ParticipantTile extends StatelessWidget {
  final Participant participant; final bool isLocal;
  const _ParticipantTile({required this.participant, required this.isLocal});

  @override
  Widget build(BuildContext context) {
    VideoTrack? video;
    for (final pub in participant.videoTrackPublications) {
      if (pub.subscribed && pub.track != null &&
          pub.source != TrackSource.screenShareVideo) {
        video = pub.track as VideoTrack;
        break;
      }
    }

    return Container(
      color: const Color(0xFF1A1A2E),
      child: Stack(fit: StackFit.expand, children: [
        video != null
            ? VideoTrackRenderer(video)
            : Center(child: Container(
            width: 56, height: 56,
            decoration: BoxDecoration(shape: BoxShape.circle,
                color: isLocal ? AppTheme.primary.withValues(alpha: 0.3) : Colors.white12),
            child: const Icon(Icons.person_rounded, color: Colors.white60, size: 32))),
        Positioned(bottom: 6, left: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                participant.isMicrophoneEnabled()
                    ? Icons.mic_rounded : Icons.mic_off_rounded,
                color: participant.isMicrophoneEnabled() ? Colors.white : Colors.redAccent,
                size: 10,
              ),
              const SizedBox(width: 3),
              Text(
                participant.name.isNotEmpty ? participant.name : (isLocal ? 'أنت' : 'طالب'),
                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 10),
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
  final String title; final bool chatOpen; final int unreadCount;
  final VoidCallback onChat, onLeave;
  const _TopBar({required this.title, required this.chatOpen,
    required this.unreadCount, required this.onChat, required this.onLeave});

  @override
  Widget build(BuildContext context) => Container(
    height: 60,
    decoration: BoxDecoration(gradient: LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Colors.black.withValues(alpha: 0.90), Colors.transparent],
    )),
    child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, color: Colors.white, size: 7), SizedBox(width: 5),
          Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.2)),
        ]),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(title,
          style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.w600),
          maxLines: 1, overflow: TextOverflow.ellipsis)),
      // Chat button with unread badge
      GestureDetector(onTap: onChat,
        child: Stack(children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: chatOpen ? AppTheme.primary.withValues(alpha: 0.4) : Colors.white12,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 18),
          ),
          if (unreadCount > 0 && !chatOpen)
            Positioned(top: 0, right: 2,
              child: Container(
                width: 16, height: 16,
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: Center(child: Text('$unreadCount',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700))),
              ),
            ),
        ]),
      ),
      // Leave button
      GestureDetector(onTap: onLeave,
        child: Container(
          margin: const EdgeInsets.only(left: 4, right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
          child: const Text('مغادرة', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bottom control bar
// ─────────────────────────────────────────────────────────────────────────────

class _ControlBar extends StatelessWidget {
  final bool cameraOn, micOn, handRaised;
  final VoidCallback onCamera, onMic, onHand, onLeave;
  const _ControlBar({required this.cameraOn, required this.micOn, required this.handRaised,
    required this.onCamera, required this.onMic, required this.onHand, required this.onLeave});

  @override
  Widget build(BuildContext context) => Container(
    height: 90,
    decoration: BoxDecoration(gradient: LinearGradient(
      begin: Alignment.bottomCenter, end: Alignment.topCenter,
      colors: [Colors.black.withValues(alpha: 0.90), Colors.transparent],
    )),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _Btn(icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded, label: micOn ? 'كتم' : 'فتح', active: micOn, onTap: onMic),
      _Btn(icon: cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded, label: 'كاميرا', active: cameraOn, onTap: onCamera),
      _Btn(icon: Icons.back_hand_rounded, label: handRaised ? 'خفض' : 'يدي', active: handRaised, onTap: onHand),
      _Btn(icon: Icons.call_end_rounded, label: 'مغادرة', danger: true, onTap: onLeave),
    ]),
  );
}

class _Btn extends StatelessWidget {
  final IconData icon; final String label; final bool active, danger; final VoidCallback onTap;
  const _Btn({required this.icon, required this.label, required this.onTap, this.active = true, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final c  = danger ? Colors.red : (active ? Colors.white : Colors.white38);
    final bg = danger
        ? Colors.red.withValues(alpha: 0.2)
        : (active ? Colors.white12 : Colors.transparent);
    return GestureDetector(onTap: onTap, child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 52, height: 52,
          decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
          child: Icon(icon, color: c, size: 24)),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(color: c, fontFamily: 'Cairo', fontSize: 10)),
    ]));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Chat panel
// ─────────────────────────────────────────────────────────────────────────────

class _ChatPanel extends StatelessWidget {
  final List<_ChatMsg>        messages;
  final TextEditingController controller;
  final ScrollController      scroll;
  final VoidCallback          onSend;
  const _ChatPanel({required this.messages, required this.controller, required this.scroll, required this.onSend});

  @override
  Widget build(BuildContext context) => Container(
    width: 240,
    color: const Color(0xFF111122),
    child: Column(children: [
      const SizedBox(height: 64),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text('الدردشة', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.w700))),
      Expanded(child: messages.isEmpty
          ? const Center(child: Text('ابدأ المحادثة!', style: TextStyle(color: Colors.white38, fontFamily: 'Cairo', fontSize: 12)))
          : ListView.builder(
        controller: scroll,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: messages.length,
        itemBuilder: (_, i) => _ChatBubble(msg: messages[i]),
      )),
      Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          Expanded(child: TextField(
            controller: controller,
            textDirection: TextDirection.rtl,
            style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
            decoration: InputDecoration(
              hintText:      'اكتب رسالة…',
              hintStyle:     const TextStyle(color: Colors.white38, fontFamily: 'Cairo', fontSize: 12),
              filled:        true,
              fillColor:     Colors.white10,
              border:        OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onSubmitted: (_) => onSend(),
          )),
          const SizedBox(width: 6),
          GestureDetector(onTap: onSend,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
            ),
          ),
        ]),
      ),
    ]),
  );
}

class _ChatBubble extends StatelessWidget {
  final _ChatMsg msg;
  const _ChatBubble({required this.msg});

  @override
  Widget build(BuildContext context) => Align(
    alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      constraints: const BoxConstraints(maxWidth: 180),
      decoration: BoxDecoration(
        color: msg.isMe
            ? AppTheme.primary.withValues(alpha: 0.7)
            : Colors.white12,
        borderRadius: BorderRadius.only(
          topLeft:     const Radius.circular(12),
          topRight:    const Radius.circular(12),
          bottomLeft:  Radius.circular(msg.isMe ? 12 : 0),
          bottomRight: Radius.circular(msg.isMe ? 0 : 12),
        ),
      ),
      child: Column(crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        if (!msg.isMe)
          Text(msg.sender, style: const TextStyle(color: Colors.white54, fontFamily: 'Cairo', fontSize: 10)),
        Text(msg.text, style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 12)),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Chat message model
// ─────────────────────────────────────────────────────────────────────────────

class _ChatMsg {
  final String   sender;
  final String   text;
  final bool     isMe;
  final DateTime timestamp;
  const _ChatMsg({required this.sender, required this.text, required this.isMe, required this.timestamp});
}