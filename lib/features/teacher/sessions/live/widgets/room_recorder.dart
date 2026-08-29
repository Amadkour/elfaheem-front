// // room_recorder.dart
// //
// // iOS two-phase recording flow:
// //
// //   Phase 1 · start() → invokeMethod('startMicRecording')
// //     • Native stores session params (uploadUrl, authToken, chunkSecs)
// //     • Native immediately emits 'screenLoopStarted' → _screenLoopCompleter
// //       resolves → RecState.recording is set
// //     • RPScreenRecorder has NOT started yet — no red pill, no dialog
// //
// //   Phase 2 · room.dart calls invokeMethod('startScreenCaptureService')
// //     • Native calls RPScreenRecorder.startCapture()
// //     • iOS mic-permission dialog appears HERE (first use only)
// //     • Red-pill recording indicator appears (iOS requirement, cannot avoid)
// //     • On success: AVAssetWriter chunk loop begins with H.264 video + AAC audio
// //     • Native emits 'screenLoopStarted' again → upgradeToScreenRecording()
// //       resolves its own _screenLoopCompleter → _screenRecording confirmed
// //
// //   The recorder handles TWO 'screenLoopStarted' events safely:
// //     • First emit (Phase 1): resolves the start() completer
// //     • Second emit (Phase 2): resolves the upgradeToScreenRecording() completer
// //   Both completers are separate instances so there is no double-complete error.
// //
// // Android flow (unchanged):
// //   Phase 1 · start() → startMicRecording → stores params, emits screenLoopStarted
// //   Phase 2 · startScreenCaptureService → MediaProjection dialog
// //   Phase 3 · upgradeToScreenRecording() → waits for screenLoopStarted from service
//
// import 'dart:async';
// import 'dart:developer';
// import 'package:flutter/foundation.dart' show kIsWeb, ChangeNotifier;
// import 'package:flutter/services.dart';
// import 'package:flutter_education_app/core/api_client.dart';
// import 'recorder_web_stub.dart'
// if (dart.library.html) 'recorder_web_impl.dart' as web_rec;
//
// // ── Recording state ───────────────────────────────────────────────────────────
//
// enum RecState {
//   idle,
//   starting,
//   recording,
//   paused,
//   uploading,
//   done,
//   error,
// }
//
// // ── ClientRecorder ────────────────────────────────────────────────────────────
//
// class ClientRecorder extends ChangeNotifier {
//   ClientRecorder({
//     required this.sessionId,
//     required this.apiClient,
//     this.chunkSeconds = 5,
//   });
//
//   final int sessionId;
//   final ApiClient apiClient;
//   final int chunkSeconds;
//
//   RecState _state = RecState.idle;
//   RecState get state => _state;
//
//   int _uploadedChunks = 0;
//   int get uploadedChunks => _uploadedChunks;
//
//   int _totalBytes = 0;
//   int get totalBytes => _totalBytes;
//
//   String? _lastError;
//   String? get lastError => _lastError;
//
//   bool _stopping = false;
//   bool _screenRecording = false;
//   bool get isScreenRecording => _screenRecording;
//
//   bool _isPaused = false;
//   bool get isPaused => _isPaused;
//
//   static const _recChannel = MethodChannel(
//     'com.example.flutter_education_app/native_recorder',
//   );
//   static const _recEventChannel = EventChannel(
//     'com.example.flutter_education_app/rec_events',
//   );
//
//   StreamSubscription<dynamic>? _recEventSub;
//
//   // ── Completers ────────────────────────────────────────────────────────────
//   // _startCompleter:   resolves when Phase-1 'screenLoopStarted' arrives
//   //                    (used inside start() → _startRecording())
//   // _upgradeCompleter: resolves when Phase-2 'screenLoopStarted' arrives
//   //                    (used inside upgradeToScreenRecording())
//   // They are different fields so the two events never collide.
//   Completer<void>? _startCompleter;
//   Completer<void>? _upgradeCompleter;
//
//   // Share-lifecycle completers (Android only)
//   Completer<void>? _micReadyForShareCompleter;
//   Completer<void>? _micLoopStartedCompleter;
//
//   // Pause / resume completers
//   Completer<void>? _pauseCompleter;
//   Completer<void>? _resumeCompleter;
//
//   Completer<void>? get micReadyForShareCompleter => _micReadyForShareCompleter;
//   Completer<void>? get micLoopStartedCompleter   => _micLoopStartedCompleter;
//
//   // ── Broadcast event forwarding ────────────────────────────────────────────
//   //
//   // IMPORTANT: native's FlutterEventChannel only supports ONE active listener
//   // at a time per channel name. ClientRecorder owns the single subscription
//   // to 'rec_events' for the lifetime of a recording session. RoomScreenShareMixin
//   // must NOT open its own EventChannel('.../rec_events').listen(...) — doing so
//   // silently displaces whichever listener (recorder or screen-share) subscribed
//   // first, since native overwrites its single `eventSink` reference on every
//   // new onListen. That displacement is invisible until you notice chunks never
//   // upload or screenLoopStarted never resolves — there is no error, no crash,
//   // just silence on whichever side got displaced.
//   //
//   // Instead, the mixin registers this callback to receive broadcast-related
//   // events ('broadcastFrame' / 'broadcastStopped') routed through the
//   // recorder's single subscription.
//   void Function(Map<dynamic, dynamic> event)? onBroadcastEvent;
//
//   // ── Web: no-camera/mic warning ────────────────────────────────────────────
//   // Called (web only) when BOTH getUserMedia and getAudioOnly failed to
//   // acquire any camera/mic source, even after retries. The session still
//   // proceeds in screen-only mode, but the teacher should know up front that
//   // nothing will be recorded unless/until they start a screen share — this
//   // was previously silent, so the teacher had no idea a whole session could
//   // end up with zero recorded content.
//   void Function()? onNoMediaWarning;
//
//   void prepareMicReadyForShareWait() =>
//       _micReadyForShareCompleter = Completer<void>();
//
//   void prepareMicLoopStartedWait() =>
//       _micLoopStartedCompleter = Completer<void>();
//
//   web_rec.WebRecorder? _webRecorder;
//   web_rec.WebRecorder? get webRecorder => _webRecorder;
//
//   // ── Public API ────────────────────────────────────────────────────────────
//
//   /// Phase 1: store session params and open the EventChannel.
//   /// On iOS: native immediately emits 'screenLoopStarted' → sets RecState.recording.
//   /// On Android: same — native stores params and emits immediately.
//   /// Neither platform starts RPScreenRecorder / MediaProjection here.
//   Future<void> start() async {
//     if (_state != RecState.idle) return;
//     _set(RecState.starting);
//     if (kIsWeb) {
//       await _startWeb();
//     } else {
//       await _startRecording();
//     }
//   }
//
//   Future<void> startWebCompositor({
//     String teacherName = '',
//     String sessionTitle = '',
//     int participantCount = 0,
//   }) async {
//     if (!kIsWeb || _webRecorder == null) return;
//     final token = (await apiClient.accessToken) ?? '';
//     _webRecorder!.startCompositor(
//       sessionId,
//       apiClient.baseUrl,
//       'Bearer $token',
//       teacherName: teacherName,
//       sessionTitle: sessionTitle,
//       participantCount: participantCount,
//     );
//   }
//
//   /// Web only: pushes a live participant-count update to the recorder's
//   /// placeholder (shown on the recorded canvas when there's no screen
//   /// share/camera yet). No-op on mobile/desktop and if the compositor
//   /// hasn't started yet.
//   void updateParticipantCount(int count) {
//     if (!kIsWeb) return;
//     _webRecorder?.updateParticipantCount(count);
//   }
//
//   /// Phase 2 confirmation: called from room.dart AFTER startScreenCaptureService
//   /// has returned (meaning RPScreenRecorder / MediaProjection is running).
//   ///
//   /// Waits for the SECOND 'screenLoopStarted' that AppDelegate emits from
//   /// inside startScreenCaptureService's completion handler — which fires only
//   /// once the AVAssetWriter chunk loop is actually writing frames.
//   ///
//   /// Uses _upgradeCompleter (not _startCompleter) so the two events don't clash.
//   Future<void> upgradeToScreenRecording() async {
//     if (kIsWeb) return;
//
//     // FIX: Do NOT return early because _screenRecording is true.
//     // Phase-1 (screenLoopStarted) no longer sets _screenRecording=true, so
//     // that guard was stale. We must always wait for the Phase-2
//     // 'videoChunksActive' event to confirm the AVAssetWriter is live.
//     // prepareUpgradeWait() in room.dart pre-creates the completer so the
//     // event is never missed even on fast devices.
//     _upgradeCompleter ??= Completer<void>();
//
//     try {
//       // Native emits 'videoChunksActive' from startRPScreenRecorder's
//       // completionHandler — which fires on the main queue after startCapture
//       // succeeds and beginChunkWriter() has started the timer. We wait for it
//       // regardless of whether native returned true or false, since native now
//       // always emits the event (and returns the current recording state).
//       await _recChannel.invokeMethod<bool>('upgradeToScreenRecording');
//       await _upgradeCompleter!.future.timeout(
//         const Duration(seconds: 20),
//         onTimeout: () {
//           log('[REC] upgradeToScreenRecording: timeout — assuming live');
//         },
//       );
//     } catch (e) {
//       log('[REC] upgradeToScreenRecording error: $e');
//     } finally {
//       _upgradeCompleter = null;
//     }
//
//     _screenRecording = true;
//     if (_state != RecState.recording) _set(RecState.recording);
//     notifyListeners();
//     log('[REC] upgradeToScreenRecording: Phase-2 confirmed — video+audio chunks active');
//   }
//
//   /// Call this from room.dart BEFORE calling startScreenCaptureService
//   /// so the Phase-2 'screenLoopStarted' event is never missed.
//   void prepareUpgradeWait() {
//     _upgradeCompleter ??= Completer<void>();
//   }
//
//   Future<void> downgradeToMicOnly() async {
//     if (kIsWeb) return;
//     log('[REC] downgradeToMicOnly: recording continues uninterrupted');
//   }
//
//   Future<void> attachScreenToRecorder(Object? screenStream) async {
//     if (!kIsWeb) return;
//     if (_webRecorder == null) {
//       log('[REC] attachScreenToRecorder: _webRecorder is null — screen '
//           'stream dropped, nothing will be recorded for this share');
//       return;
//     }
//     if (screenStream == null) {
//       log('[REC] attachScreenToRecorder: screenStream is null — nothing to attach');
//       return;
//     }
//     _webRecorder!.addStream(screenStream, 'screen');
//   }
//
//   Future<void> detachScreenFromRecorder() async {
//     if (!kIsWeb || _webRecorder == null) return;
//     _webRecorder!.removeStream('screen');
//   }
//
//   Future<void> pauseRecording() async {
//     if (kIsWeb) {
//       if (_state != RecState.recording) return;
//       log('[REC] pauseRecording (web)');
//       // Synchronous under the hood (MediaRecorder.pause() is not async) —
//       // no completer/timeout needed like the native mobile path below.
//       _webRecorder?.pause();
//       _applyPaused();
//       return;
//     }
//     if (_state != RecState.recording || _stopping) return;
//     log('[REC] pauseRecording');
//     try {
//       _pauseCompleter = Completer<void>();
//       await _recChannel.invokeMethod<void>('pauseRecording');
//       await _pauseCompleter!.future.timeout(
//         const Duration(seconds: 15),
//         onTimeout: () { log('[REC] pauseRecording timeout'); _applyPaused(); },
//       );
//     } catch (e) {
//       log('[REC] pauseRecording error: $e');
//     } finally {
//       _pauseCompleter = null;
//     }
//   }
//
//   Future<void> resumeRecording() async {
//     if (kIsWeb) {
//       if (_state != RecState.paused) return;
//       log('[REC] resumeRecording (web)');
//       _webRecorder?.resume();
//       _applyResumed();
//       return;
//     }
//     if (_state != RecState.paused) return;
//     log('[REC] resumeRecording');
//     try {
//       _resumeCompleter = Completer<void>();
//       await _recChannel.invokeMethod<void>('resumeRecording');
//       await _resumeCompleter!.future.timeout(
//         const Duration(seconds: 15),
//         onTimeout: () { log('[REC] resumeRecording timeout'); _applyResumed(); },
//       );
//     } catch (e) {
//       log('[REC] resumeRecording error: $e');
//     } finally {
//       _resumeCompleter = null;
//     }
//   }
//
//   Future<void> stopRecordingOnly() async {
//     if (_state == RecState.done || _state == RecState.error || _stopping) return;
//     _stopping = true;
//     _set(RecState.uploading);
//     if (kIsWeb) {
//       await _webRecorder?.stop();
//     } else {
//       await _stopMobile(isFinal: true);
//     }
//   }
//
//   Future<void> drainPending() async {
//     if (kIsWeb) {
//       _set(RecState.done);
//       log('[REC] drain complete (web) — chunks=$_uploadedChunks bytes=$_totalBytes');
//       return;
//     }
//     const maxWait = Duration(seconds: 180);
//     final deadline = DateTime.now().add(maxWait);
//     while (_state != RecState.done && DateTime.now().isBefore(deadline)) {
//       await Future.delayed(const Duration(milliseconds: 200));
//     }
//     if (_state != RecState.done) _set(RecState.done);
//     log('[REC] drain complete — chunks=$_uploadedChunks bytes=$_totalBytes');
//   }
//
//   @override
//   Future<void> dispose() async {
//     _recEventSub?.cancel();
//     _recEventSub               = null;
//     _startCompleter            = null;
//     _upgradeCompleter          = null;
//     _micReadyForShareCompleter = null;
//     _micLoopStartedCompleter   = null;
//     _pauseCompleter            = null;
//     _resumeCompleter           = null;
//     onBroadcastEvent           = null;
//     onNoMediaWarning           = null;
//     try { await _webRecorder?.stop(); } catch (_) {}
//     _webRecorder = null;
//     super.dispose();
//   }
//
//   // ── Web ───────────────────────────────────────────────────────────────────
//
//   Future<void> _startWeb() async {
//     try {
//       // IMPORTANT: create _webRecorder and mark the session as recording
//       // IMMEDIATELY, before touching the camera/mic at all.
//       //
//       // room.dart calls startWebCompositor() right after this method
//       // returns. Camera/mic acquisition can take several seconds (multiple
//       // retries with backoff), and if a teacher starts screen-sharing
//       // during that window, attachScreenToRecorder() reaches _webRecorder
//       // while it's still null and the stream is silently dropped — which
//       // is exactly what "record from the start of the session" needs to
//       // never happen. So camera/mic acquisition now happens in the
//       // background and attaches itself later if it ever succeeds; it no
//       // longer blocks compositor startup or screen-share attachment.
//       _webRecorder = web_rec.WebRecorder(
//         onBlob: (size) { _totalBytes += size; notifyListeners(); },
//       );
//       await _webRecorder!.start(null, '');
//       _set(RecState.recording);
//       _screenRecording = true;
//       notifyListeners();
//
//       unawaited(_acquireWebMediaInBackground());
//     } catch (e, st) {
//       log('[REC] Web start error: $e\n$st');
//       _setError('Web recording failed: $e');
//     }
//   }
//
//   /// Acquires camera/mic in the background (with its own retries) and
//   /// attaches it to the already-running compositor if/when it succeeds.
//   /// Runs independently of session start and screen-share attachment.
//   Future<void> _acquireWebMediaInBackground() async {
//     try {
//       // getUserMedia() already falls back to audio-only internally when no
//       // camera is available — do not call getAudioOnly() again here, that
//       // previously ran the whole retry sequence twice.
//       final stream = await web_rec.getUserMedia(video: true);
//
//       if (stream == null) {
//         log('[REC] Web: no camera/mic available after retries — '
//             'continuing with screen-share/placeholder only');
//         onNoMediaWarning?.call();
//         return;
//       }
//
//       log('[REC] Web: camera/mic acquired in background — attaching to compositor');
//       _webRecorder?.addStream(stream, 'camera');
//     } catch (e, st) {
//       log('[REC] Web background media acquisition error: $e\n$st');
//     }
//   }
//
//   /// Web only: whether the session ever captured a real (non-empty) chunk.
//   /// False after the recording has stopped means nothing was recorded —
//   /// worth surfacing to the teacher rather than reporting silent success.
//   bool get webHadRealData => _webRecorder?.hadRealData ?? false;
//
//   /// Web only: number of chunks actually confirmed uploaded to the server.
//   int get webChunksUploaded => _webRecorder?.chunksUploaded ?? 0;
//
//   // ── Mobile: Phase 1 ───────────────────────────────────────────────────────
//
//   Future<void> _startRecording() async {
//     try {
//       final token     = (await apiClient.accessToken) ?? '';
//       final uploadUrl =
//           '${apiClient.baseUrl}/api/v1/live-sessions/$sessionId/recording-chunk';
//
//       // Open EventChannel BEFORE invoking so we never miss events.
//       _recEventSub?.cancel();
//       _recEventSub = _recEventChannel.receiveBroadcastStream().listen(
//         _onNativeEvent,
//         onError: _onNativeError,
//       );
//
//       // Prepare the Phase-1 completer before invoking.
//       _startCompleter = Completer<void>();
//
//       final ok = await _recChannel.invokeMethod<bool>('startMicRecording', {
//         'sessionId':    sessionId,
//         'uploadUrl':    uploadUrl,
//         'authToken':    'Bearer $token',
//         'chunkSeconds': chunkSeconds,
//         'chunkIndex':   0,
//       });
//
//       if (ok == true) {
//         // Wait for Phase-1 'screenLoopStarted'.
//         // iOS: arrives almost immediately (emitted synchronously in the handler).
//         // Android: also immediate (params stored, event emitted).
//         await _startCompleter!.future.timeout(
//           const Duration(seconds: 10),
//           onTimeout: () => log('[REC] Phase-1 screenLoopStarted timeout'),
//         );
//         _startCompleter = null;
//         // State is now RecState.recording (set in _onNativeEvent).
//         log('[REC] Phase-1 complete — params stored, ready for startScreenCaptureService');
//       } else {
//         _startCompleter = null;
//         _setError('startMicRecording returned false');
//       }
//     } on PlatformException catch (e) {
//       _startCompleter = null;
//       _setError('Recording failed: ${e.message}');
//     } catch (e, st) {
//       _startCompleter = null;
//       log('[REC] _startRecording error: $e\n$st');
//       _setError('Recording failed: $e');
//     }
//   }
//
//   Future<void> _stopMobile({required bool isFinal}) async {
//     try {
//       // Native holds this result open until the final upload lands on the
//       // server (or retries are exhausted) — see AppDelegate.stopRecording().
//       // Timeout of 90s covers worst-case 4-retry back-off (3+6+12+24=45s)
//       // plus upload time on a slow connection, with headroom. If we time out
//       // we still proceed — the server's idle watchdog will assemble whatever
//       // chunks arrived.
//       await _recChannel
//           .invokeMethod('stopRecording', {'isFinal': isFinal})
//           .timeout(
//         const Duration(seconds: 90),
//         onTimeout: () {
//           log('[REC] stopRecording timed out — proceeding with onEnd anyway');
//           return null;
//         },
//       );
//     } catch (e) {
//       log('[REC] Mobile stop error: $e');
//     }
//   }
//
//   // ── EventChannel dispatcher ───────────────────────────────────────────────
//
//   void _onNativeEvent(dynamic event) {
//     if (event is! Map) return;
//     final type = event['event'] as String?;
//
//     switch (type) {
//       case 'screenLoopStarted':
//       // Phase-1 ONLY: resolves start() → stores session params on native side.
//       // Native (startMicRecording) emits this immediately and synchronously.
//       // FIX: do NOT set _screenRecording=true here — that belongs to Phase-2.
//       // Previously setting it here caused upgradeToScreenRecording() to see
//       // _screenRecording=true and return early before _upgradeCompleter was
//       // resolved, leaving Phase-2 stuck until a 20-second timeout.
//         log('[REC] screenLoopStarted received (Phase-1)');
//         if (_startCompleter != null && !_startCompleter!.isCompleted) {
//           _startCompleter!.complete();
//           if (_state == RecState.starting) _set(RecState.recording);
//           notifyListeners();
//           return;
//         }
//         // Extra screenLoopStarted after Phase-1 is consumed — ignore.
//         log('[REC] screenLoopStarted: extra event ignored (Phase-1 already consumed)');
//
//       case 'videoChunksActive':
//       // Phase-2 ONLY: AVAssetWriter is writing real video frames.
//       // FIX: Native now emits "videoChunksActive" (not "screenLoopStarted")
//       // from startRPScreenRecorder's completionHandler, so this event is never
//       // confused with the Phase-1 screenLoopStarted and is never swallowed by
//       // the Phase-1 early-return guard above.
//         log('[REC] videoChunksActive received (Phase-2)');
//         if (_upgradeCompleter != null && !_upgradeCompleter!.isCompleted) {
//           _upgradeCompleter!.complete();
//         }
//         _screenRecording = true;
//         if (_state != RecState.recording) _set(RecState.recording);
//         notifyListeners();
//
//       case 'micReadyForShare':
//         if (_micReadyForShareCompleter?.isCompleted == false) {
//           _micReadyForShareCompleter!.complete();
//         }
//         _micReadyForShareCompleter = null;
//
//       case 'micLoopStarted':
//         if (_micLoopStartedCompleter?.isCompleted == false) {
//           _micLoopStartedCompleter!.complete();
//         }
//         _micLoopStartedCompleter = null;
//
//       case 'chunkUploaded':
//         _uploadedChunks++;
//         _totalBytes += (event['bytes'] as int? ?? 0);
//         notifyListeners();
//         log('[REC] chunk #${event['chunkIndex']} uploaded '
//             '(${event['bytes']}B isFinal=${event['isFinal']})');
//         if (event['isFinal'] == true && _stopping) {
//           _set(RecState.done);
//           _recEventSub?.cancel();
//           _recEventSub = null;
//         }
//
//       case 'recordingPaused':
//         _applyPaused();
//         if (_pauseCompleter?.isCompleted == false) _pauseCompleter!.complete();
//
//       case 'recordingResumed':
//         _applyResumed();
//         if (_resumeCompleter?.isCompleted == false) _resumeCompleter!.complete();
//
//       case 'broadcastFrame':
//       case 'broadcastStopped':
//       // Forwarded to RoomScreenShareMixin via onBroadcastEvent — see the
//       // field doc above for why this goes through OUR subscription rather
//       // than a second one opened by the mixin.
//         onBroadcastEvent?.call(event);
//
//       default:
//         log('[REC] unknown event: $type');
//     }
//   }
//
//   void _onNativeError(dynamic error) {
//     log('[REC] Native error: $error');
//     void tryComplete(Completer<void>? c) {
//       if (c?.isCompleted == false) c!.completeError(error ?? 'native error');
//     }
//     tryComplete(_startCompleter);
//     tryComplete(_upgradeCompleter);
//     tryComplete(_micReadyForShareCompleter);
//     tryComplete(_micLoopStartedCompleter);
//     tryComplete(_pauseCompleter);
//     tryComplete(_resumeCompleter);
//     if (!_stopping) _setError(error?.toString() ?? 'Native recorder error');
//   }
//
//   // ── Internal helpers ──────────────────────────────────────────────────────
//
//   void _applyPaused()  { _isPaused = true;  _set(RecState.paused);    }
//   void _applyResumed() { _isPaused = false; _set(RecState.recording); }
//   void _set(RecState s) { _state = s; notifyListeners(); }
//   void _setError(String m) {
//     _lastError = m; _state = RecState.error; notifyListeners();
//   }
// }

// room_recorder.dart
//
// ClientRecorder is a thin orchestrator: it owns session-level state
// (RecState, byte/chunk counters, error) and delegates all actual
// recording work to one of three separate, platform-specific
// implementations:
//
//   • Web    → recorder_web_impl.dart (WebRecorder / the JS compositor)
//   • iOS    → recorder_native_ios.dart    (IosNativeRecorderBackend)
//   • Android→ recorder_native_android.dart (AndroidNativeRecorderBackend)
//
// iOS and Android share the exact same MethodChannel/EventChannel wire
// protocol (see recorder_native_shared.dart's header for the full two-phase
// flow), so their common plumbing lives in one base class,
// NativeRecorderBackend, with each platform file adding only what's
// genuinely different for it — currently just Android's two extra
// share-lifecycle events. This file never talks to MethodChannel/
// EventChannel directly; that's entirely owned by the native backend
// files.
//
// Because dart:io (needed for Platform.isIOS/isAndroid) cannot be
// referenced from anything compiled into a web build, the choice of WHICH
// native backend to construct is made in a separately conditionally-
// imported file, mirroring the existing web-vs-everything-else split below:
//   recorder_native_stub.dart   (web: dart.library.io unavailable — never
//                                 actually called, since native backends
//                                 are only constructed when !kIsWeb)
//   recorder_native_select.dart (iOS/Android/desktop: does the real
//                                 Platform.isIOS/isAndroid check)
//
// The public API on ClientRecorder itself is UNCHANGED from before this
// split — every method/getter used by room.dart, room_screen_share.dart,
// and controls.dart still exists here with the same signature; only the
// implementation moved into the platform-specific files above.

import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, ChangeNotifier;
import 'package:flutter_education_app/core/api_client.dart';

import 'record/recorder_native_android.dart';
import 'record/recorder_native_shared.dart';
import 'record/recorder_types.dart';
import 'recorder_web_stub.dart'
if (dart.library.html) 'recorder_web_impl.dart' as web_rec;
import 'record/recorder_native_stub.dart'
if (dart.library.io) 'record/recorder_native_select.dart' as native_rec;

export 'record/recorder_types.dart';

// ── ClientRecorder ──────────────────────────────────────────────────────────

class ClientRecorder extends ChangeNotifier {
  ClientRecorder({
    required this.sessionId,
    required this.apiClient,
    this.chunkSeconds = 5,
  }) {
    if (!kIsWeb) {
      _native = native_rec.createNativeBackend(
        sessionId: sessionId,
        chunkSeconds: chunkSeconds,
        onStateChange: _onNativeStateChange,
        onChunkUploaded: (bytes, chunkIndex, isFinal) {
          _uploadedChunks++;
          _totalBytes += bytes;
          notifyListeners();
        },
        onError: _setError,
        onScreenRecordingConfirmed: () {
          _screenRecording = true;
          if (_state != RecState.recording) _set(RecState.recording);
          notifyListeners();
        },
      );
    }
  }

  final int sessionId;
  final ApiClient apiClient;
  final int chunkSeconds;

  // The active native backend on iOS/Android — null on web, where
  // _webRecorder is used instead. See the file header for how the
  // concrete iOS-vs-Android choice is made.
  NativeRecorderBackend? _native;

  RecState _state = RecState.idle;
  RecState get state => _state;

  int _uploadedChunks = 0;
  int get uploadedChunks => _uploadedChunks;

  int _totalBytes = 0;
  int get totalBytes => _totalBytes;

  String? _lastError;
  String? get lastError => _lastError;

  // Guards re-entrant stopRecordingOnly()/pauseRecording()/resumeRecording()
  // calls at the orchestration level. Distinct from (and unrelated to) the
  // native backend's own internal _stopping flag, which only exists to
  // decide whether an isFinal 'chunkUploaded' event should transition to
  // RecState.done — each layer owns its own copy of "am I stopping" for
  // what it individually needs it for.
  bool _stopping = false;

  bool _screenRecording = false;
  bool get isScreenRecording => _screenRecording;

  bool _isPaused = false;
  bool get isPaused => _isPaused;

  // ── Android-only share-lifecycle completers ─────────────────────────────
  // These genuinely only exist on Android (see recorder_native_android.dart)
  // — on iOS and web, the getters below simply return null and the prepare
  // calls are no-ops, exactly as calling them did nothing useful on those
  // platforms before this split either.
  Completer<void>? get micReadyForShareCompleter {
    final native = _native;
    return native is AndroidNativeRecorderBackend
        ? native.micReadyForShareCompleter
        : null;
  }

  Completer<void>? get micLoopStartedCompleter {
    final native = _native;
    return native is AndroidNativeRecorderBackend
        ? native.micLoopStartedCompleter
        : null;
  }

  void prepareMicReadyForShareWait() {
    final native = _native;
    if (native is AndroidNativeRecorderBackend) {
      native.prepareMicReadyForShareWait();
    }
  }

  void prepareMicLoopStartedWait() {
    final native = _native;
    if (native is AndroidNativeRecorderBackend) {
      native.prepareMicLoopStartedWait();
    }
  }

  // ── Broadcast event forwarding ──────────────────────────────────────────
  //
  // IMPORTANT: native's FlutterEventChannel only supports ONE active listener
  // at a time per channel name. The native backend owns the single
  // subscription to 'rec_events' for the lifetime of a recording session.
  // RoomScreenShareMixin must NOT open its own EventChannel(.../rec_events)
  // .listen(...) — doing so silently displaces whichever listener (recorder
  // or screen-share) subscribed first, since native overwrites its single
  // `eventSink` reference on every new onListen. That displacement is
  // invisible until you notice chunks never upload or screenLoopStarted
  // never resolves — there is no error, no crash, just silence on whichever
  // side got displaced.
  //
  // Instead, the mixin registers this callback to receive broadcast-related
  // events ('broadcastFrame' / 'broadcastStopped'), forwarded here from
  // whichever native backend is active.
  void Function(Map<dynamic, dynamic> event)? _onBroadcastEvent;
  void Function(Map<dynamic, dynamic> event)? get onBroadcastEvent => _onBroadcastEvent;
  set onBroadcastEvent(void Function(Map<dynamic, dynamic> event)? cb) {
    _onBroadcastEvent = cb;
    _native?.onBroadcastEvent = cb;
  }

  // ── Web: no-camera/mic warning ──────────────────────────────────────────
  // Called (web only) when BOTH getUserMedia and getAudioOnly failed to
  // acquire any camera/mic source, even after retries. The session still
  // proceeds in screen-only mode, but the teacher should know up front that
  // nothing will be recorded unless/until they start a screen share — this
  // was previously silent, so the teacher had no idea a whole session could
  // end up with zero recorded content.
  void Function()? onNoMediaWarning;

  web_rec.WebRecorder? _webRecorder;
  web_rec.WebRecorder? get webRecorder => _webRecorder;

  // ── Public API ───────────────────────────────────────────────────────────

  /// Phase 1: store session params and open the EventChannel (mobile), or
  /// start the compositor immediately in screen-only mode (web). See
  /// recorder_native_shared.dart / recorder_web_impl.dart for the full
  /// platform-specific flow each of these actually runs.
  Future<void> start() async {
    if (_state != RecState.idle) return;
    _set(RecState.starting);
    if (kIsWeb) {
      await _startWeb();
    } else {
      final token     = (await apiClient.accessToken) ?? '';
      final uploadUrl =
          '${apiClient.baseUrl}/api/v1/live-sessions/$sessionId/recording-chunk';
      await _native?.start(uploadUrl: uploadUrl, authToken: 'Bearer $token');
    }
  }

  Future<void> startWebCompositor({
    String teacherName = '',
    String sessionTitle = '',
    int participantCount = 0,
  }) async {
    if (!kIsWeb || _webRecorder == null) return;
    final token = (await apiClient.accessToken) ?? '';
    _webRecorder!.startCompositor(
      sessionId,
      apiClient.baseUrl,
      'Bearer $token',
      teacherName: teacherName,
      sessionTitle: sessionTitle,
      participantCount: participantCount,
    );
  }

  /// Web only: pushes a live participant-count update to the recorder's
  /// placeholder (shown on the recorded canvas when there's no screen
  /// share/camera yet). No-op on mobile/desktop and if the compositor
  /// hasn't started yet.
  void updateParticipantCount(int count) {
    if (!kIsWeb) return;
    _webRecorder?.updateParticipantCount(count);
  }

  /// Web only: sends the same _PremiumWaitingPlaceholder PNG used on
  /// Android (see room.dart's _sendPlaceholderImageToNative) to the web
  /// compositor's canvas placeholder, so all platforms show the identical
  /// placeholder graphic. No-op on mobile/desktop and if the compositor
  /// hasn't started yet.
  void setPlaceholderImage(Uint8List png) {
    if (!kIsWeb) return;
    _webRecorder?.setPlaceholderImage(png);
  }

  /// Phase 2 confirmation: called from room.dart AFTER startScreenCaptureService
  /// has returned (meaning RPScreenRecorder / MediaProjection is running).
  /// No-op on web.
  Future<void> upgradeToScreenRecording() async {
    if (kIsWeb) return;
    await _native?.upgradeToScreenRecording();
  }

  /// Call this from room.dart BEFORE calling startScreenCaptureService so
  /// the Phase-2 event is never missed. Harmless no-op on web.
  void prepareUpgradeWait() {
    _native?.prepareUpgradeWait();
  }

  Future<void> downgradeToMicOnly() async {
    if (kIsWeb) return;
    await _native?.downgradeToMicOnly();
  }

  Future<void> attachScreenToRecorder(Object? screenStream) async {
    if (!kIsWeb) return;
    if (_webRecorder == null) {
      log('[REC] attachScreenToRecorder: _webRecorder is null — screen '
          'stream dropped, nothing will be recorded for this share');
      return;
    }
    if (screenStream == null) {
      log('[REC] attachScreenToRecorder: screenStream is null — nothing to attach');
      return;
    }
    _webRecorder!.addStream(screenStream, 'screen');
  }

  Future<void> detachScreenFromRecorder() async {
    if (!kIsWeb || _webRecorder == null) return;
    _webRecorder!.removeStream('screen');
  }

  Future<void> pauseRecording() async {
    if (kIsWeb) {
      if (_state != RecState.recording) return;
      log('[REC] pauseRecording (web)');
      // Synchronous under the hood (MediaRecorder.pause() is not async) —
      // no completer/timeout needed like the native mobile path.
      _webRecorder?.pause();
      _applyPaused();
      return;
    }
    if (_state != RecState.recording || _stopping) return;
    await _native?.pause();
  }

  Future<void> resumeRecording() async {
    if (kIsWeb) {
      if (_state != RecState.paused) return;
      log('[REC] resumeRecording (web)');
      _webRecorder?.resume();
      _applyResumed();
      return;
    }
    if (_state != RecState.paused) return;
    await _native?.resume();
  }

  Future<void> stopRecordingOnly() async {
    if (_state == RecState.done || _state == RecState.error || _stopping) return;
    _stopping = true;
    _set(RecState.uploading);
    if (kIsWeb) {
      await _webRecorder?.stop();
    } else {
      await _native?.stop(isFinal: true);
    }
  }

  Future<void> drainPending() async {
    if (kIsWeb) {
      _set(RecState.done);
      log('[REC] drain complete (web) — chunks=$_uploadedChunks bytes=$_totalBytes');
      return;
    }
    const maxWait = Duration(seconds: 180);
    final deadline = DateTime.now().add(maxWait);
    while (_state != RecState.done && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (_state != RecState.done) _set(RecState.done);
    log('[REC] drain complete — chunks=$_uploadedChunks bytes=$_totalBytes');
  }

  @override
  Future<void> dispose() async {
    _native?.dispose();
    _native = null;
    onBroadcastEvent = null;
    onNoMediaWarning = null;
    try { await _webRecorder?.stop(); } catch (_) {}
    _webRecorder = null;
    super.dispose();
  }

  /// Web only: whether the session ever captured a real (non-empty) chunk.
  /// False after the recording has stopped means nothing was recorded —
  /// worth surfacing to the teacher rather than reporting silent success.
  bool get webHadRealData => _webRecorder?.hadRealData ?? false;

  /// Web only: number of chunks actually confirmed uploaded to the server.
  int get webChunksUploaded => _webRecorder?.chunksUploaded ?? 0;

  // ── Web ────────────────────────────────────────────────────────────────

  Future<void> _startWeb() async {
    try {
      // IMPORTANT: create _webRecorder and mark the session as recording
      // IMMEDIATELY, before touching the camera/mic at all.
      //
      // room.dart calls startWebCompositor() right after this method
      // returns. Camera/mic acquisition can take several seconds (multiple
      // retries with backoff), and if a teacher starts screen-sharing
      // during that window, attachScreenToRecorder() reaches _webRecorder
      // while it's still null and the stream is silently dropped — which
      // is exactly what "record from the start of the session" needs to
      // never happen. So camera/mic acquisition now happens in the
      // background and attaches itself later if it ever succeeds; it no
      // longer blocks compositor startup or screen-share attachment.
      _webRecorder = web_rec.WebRecorder(
        onBlob: (size) { _totalBytes += size; notifyListeners(); },
      );
      await _webRecorder!.start(null, '');
      _set(RecState.recording);
      _screenRecording = true;
      notifyListeners();

      unawaited(_acquireWebMediaInBackground());
    } catch (e, st) {
      log('[REC] Web start error: $e\n$st');
      _setError('Web recording failed: $e');
    }
  }

  /// Acquires camera/mic in the background (with its own retries) and
  /// attaches it to the already-running compositor if/when it succeeds.
  /// Runs independently of session start and screen-share attachment.
  Future<void> _acquireWebMediaInBackground() async {
    try {
      // getUserMedia() already falls back to audio-only internally when no
      // camera is available — do not call getAudioOnly() again here, that
      // previously ran the whole retry sequence twice.
      final stream = await web_rec.getUserMedia(video: true);

      if (stream == null) {
        log('[REC] Web: no camera/mic available after retries — '
            'continuing with screen-share/placeholder only');
        onNoMediaWarning?.call();
        return;
      }

      log('[REC] Web: camera/mic acquired in background — attaching to compositor');
      _webRecorder?.addStream(stream, 'camera');
    } catch (e, st) {
      log('[REC] Web background media acquisition error: $e\n$st');
    }
  }

  // ── Internal helpers ─────────────────────────────────────────────────────

  void _onNativeStateChange(RecState s) {
    // Mirrors what _applyPaused()/_applyResumed() did when this logic lived
    // inline in the old EventChannel dispatcher — both events the native
    // backend can report ("paused"/"recording") map straight through here,
    // keeping _isPaused in sync with every source of a state change
    // (explicit pause/resume calls, native events, and their timeout
    // fallbacks) without duplicating the bookkeeping in three places.
    if (s == RecState.paused)   { _applyPaused();  return; }
    if (s == RecState.recording) { _applyResumed(); return; }
    _set(s);
  }

  void _applyPaused()  { _isPaused = true;  _set(RecState.paused);    }
  void _applyResumed() { _isPaused = false; _set(RecState.recording); }
  void _set(RecState s) { _state = s; notifyListeners(); }
  void _setError(String m) {
    _lastError = m; _state = RecState.error; notifyListeners();
  }
}