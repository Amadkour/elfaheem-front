// recorder_web_impl.dart
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

// ── Single top-level dispatcher ───────────────────────────────────────────────
// recorder_compositor.js exposes window._elfaheemCompositor(cmd, ...args).
// dart:js_interop @JS() can only bind top-level global names (no dots).
@JS('_elfaheemCompositor')
external JSAny? _dispatch(String cmd,
    [JSAny? a1, JSAny? a2, JSAny? a3, JSAny? a4]);

// JS sets this to true once all chunk uploads have finished.
@JS('_ElFaheemCompositorDone')
external bool get _compositorDone;

// JS sets this to true the first time a non-empty chunk was captured.
// Lets us tell "drained, all N chunks uploaded" apart from
// "drained, but N was zero the whole time" (the latter used to be reported
// as success even though nothing was ever actually recorded).
@JS('_ElFaheemCompositorHadRealData')
external bool get _compositorHadRealData;

// Running count of chunks that actually reached the server successfully.
@JS('_ElFaheemCompositorChunksUploaded')
external int get _compositorChunksUploaded;

// JS sets this once every queued/in-flight chunk — including ones still
// uploading in the background when stop() was called — has actually
// reached the server. Distinct from _compositorDone, which now flips as
// soon as the recorder itself has stopped, without waiting for uploads.
@JS('_ElFaheemCompositorUploadsDone')
external bool get _compositorUploadsDone;

@JS('MediaRecorder.isTypeSupported')
external bool _isTypeSupported(String mimeType);

extension _MediaDevicesExt on web.MediaDevices {
  external JSPromise<web.MediaStream> getDisplayMedia();
}

// ── Typed compositor wrappers ─────────────────────────────────────────────────

void _compositorStart(
    int sessionId,
    String apiUrl,
    String authToken, {
      String teacherName = '',
      String sessionTitle = '',
      int participantCount = 0,
    }) {
  // Bundled as JSON rather than adding more positional a5/a6/... params to
  // the dispatcher — keeps the JS-interop surface stable as more placeholder
  // fields get added later.
  final meta = jsonEncode({
    'teacherName': teacherName,
    'sessionTitle': sessionTitle,
    'participantCount': participantCount,
  });
  _dispatch('start', sessionId.toJS, apiUrl.toJS, authToken.toJS, meta.toJS);
}

void _compositorUpdateParticipants(int count) {
  _dispatch('updateParticipants', count.toJS);
}

void _compositorAddStream(web.MediaStream stream, String label) {
  _dispatch('addStream', stream as JSAny, label.toJS);
}

void _compositorRemoveStream(String label) {
  _dispatch('removeStream', label.toJS);
}

void _compositorStop() {
  // JS stop() is async internally; Dart polls _compositorDone below.
  _dispatch('stop');
}

bool _compositorIsActive() {
  final r = _dispatch('isActive');
  return r?.dartify() == true;
}

// ── Public helpers ────────────────────────────────────────────────────────────

bool isTypeSupported(String mime) {
  try { return _isTypeSupported(mime); } catch (_) { return false; }
}

/// Attempts [action] up to [maxAttempts] times with a short backoff.
///
/// getUserMedia can fail with a transient error (most commonly
/// NotReadableError / TrackStartError) when the mic or camera is still
/// momentarily locked by the OS/browser right after a previous session
/// released it. Previously a single failure here was treated as final and
/// the whole session silently fell back to "no media at all", even though
/// the device was usually free again a few hundred ms later.
Future<web.MediaStream?> _withRetries(
    Future<web.MediaStream> Function() action, {
      required String label,
      int maxAttempts = 3,
    }) async {
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      final stream = await action();
      if (attempt > 1) _log('$label succeeded on attempt $attempt/$maxAttempts');
      return stream;
    } catch (e) {
      final isLast = attempt == maxAttempts;
      _log('$label failed (attempt $attempt/$maxAttempts): $e'
          '${isLast ? '' : ' — retrying'}');
      if (isLast) return null;
      await Future.delayed(Duration(milliseconds: 400 * attempt));
    }
  }
  return null;
}

Future<web.MediaStream?> getUserMedia({bool video = true}) async {
  final devices = web.window.navigator.mediaDevices;
  if (video) {
    final ideal = await _withRetries(
          () => devices.getUserMedia(web.MediaStreamConstraints(
        audio: true.toJS,
        video: {
          'width':     {'ideal': 1280},
          'height':    {'ideal': 720},
          'frameRate': {'ideal': 30},
        }.jsify()!,
      )).toDart,
      label: 'getUserMedia (camera+mic, ideal constraints)',
    );
    if (ideal != null) return ideal;

    final basic = await _withRetries(
          () => devices.getUserMedia(
        web.MediaStreamConstraints(audio: true.toJS, video: true.toJS),
      ).toDart,
      label: 'getUserMedia (camera+mic, basic constraints)',
    );
    if (basic != null) return basic;
  }
  return getAudioOnly();
}

Future<web.MediaStream?> getAudioOnly() async {
  return _withRetries(
        () => web.window.navigator.mediaDevices.getUserMedia(
      web.MediaStreamConstraints(audio: true.toJS, video: false.toJS),
    ).toDart,
    label: 'getAudioOnly',
  );
}

Future<web.MediaStream?> getDisplayMedia() async {
  try {
    final opts = web.DisplayMediaStreamOptions(
      video: web.MediaTrackConstraints(
        width: 1280.toJS, height: 720.toJS, frameRate: 30.toJS,
      ),
      audio: true.toJS,
    );
    return await web.window.navigator.mediaDevices
        .getDisplayMedia(opts).toDart;
  } catch (e) {
    _log('getDisplayMedia failed (user cancelled?): $e');
    return null;
  }
}

web.MediaStream? toWebMediaStream(Object? obj) {
  if (obj == null) return null;
  try { return obj as web.MediaStream; }
  catch (e) { _log('toWebMediaStream cast failed: $e'); return null; }
}

Object? streamFromLivekitTrack(Object? lkTrack) => null;

void _log(String msg) {
  // ignore: avoid_print
  print('[web_rec] $msg');
}

// ── WebRecorder ───────────────────────────────────────────────────────────────

class WebRecorder {
  final void Function(int size) onBlob;

  bool    _started       = false;
  Object? _pendingStream;
  // A stream (usually 'camera') that arrived via addStream() BEFORE
  // startCompositor() actually ran — see the race explained in addStream()
  // below. Queued here and flushed once startCompositor() sets _started,
  // instead of being silently dropped.
  final Map<String, Object> _queuedStreams = {};

  WebRecorder({required this.onBlob});

  Future<bool> start(Object? micCamStream, String mimeType) async {
    _pendingStream = micCamStream;
    return true;
  }

  void startCompositor(
      int sessionId,
      String apiUrl,
      String authToken, {
        String teacherName = '',
        String sessionTitle = '',
        int participantCount = 0,
      }) {
    _started = true;
    _log('calling compositor start() sessionId=$sessionId apiUrl=$apiUrl');
    try {
      _compositorStart(
        sessionId,
        apiUrl,
        authToken,
        teacherName: teacherName,
        sessionTitle: sessionTitle,
        participantCount: participantCount,
      );
    } catch (e) {
      _log('compositorStart error: $e — is recorder_compositor.js loaded in index.html?');
      return;
    }

    final s = _pendingStream;
    _pendingStream = null;
    if (s is web.MediaStream) {
      _log('adding initial camera/mic stream to compositor');
      try { _compositorAddStream(s, 'camera'); }
      catch (e) { _log('addStream(camera) error: $e'); }
    } else {
      _log('no initial media stream — compositor in screen-only mode (OK)');
    }

    // Flush anything that raced ahead of us — e.g. camera/mic acquired in
    // the background (room_recorder.dart's _acquireWebMediaInBackground)
    // resolving fast enough to call addStream() before this method had
    // actually run yet. Without this, that stream would have hit the
    // "compositor not started" guard in addStream() below and been
    // silently discarded — meaning the camera might never appear in the
    // recording at all, not just late.
    if (_queuedStreams.isNotEmpty) {
      _log('flushing ${_queuedStreams.length} stream(s) queued before start');
      final queued = Map<String, Object>.from(_queuedStreams);
      _queuedStreams.clear();
      queued.forEach((label, stream) => addStream(stream, label));
    }
  }

  /// Pushes a live participant-count update to the placeholder shown on the
  /// recorded canvas whenever there's no screen share/camera to draw. Safe
  /// to call at any point during (or before) the session.
  void updateParticipantCount(int count) {
    try { _compositorUpdateParticipants(count); }
    catch (e) { _log('updateParticipantCount error: $e'); }
  }

  void addStream(Object? stream, String label) {
    if (!_started) {
      if (stream != null) {
        _log('addStream($label) arrived before compositor started — '
            'queuing, will attach once startCompositor() runs');
        _queuedStreams[label] = stream;
      } else {
        _log('addStream($label) DROPPED — compositor not started and stream is null');
      }
      return;
    }
    if (stream == null) {
      _log('addStream($label) DROPPED — stream is null');
      return;
    }
    try {
      _compositorAddStream(stream as web.MediaStream, label);
      _log('addStream($label) sent');
    } catch (e) { _log('addStream($label) error: $e'); }
  }

  void removeStream(String label) {
    if (!_started) return;
    try { _compositorRemoveStream(label); }
    catch (e) { _log('removeStream($label) error: $e'); }
  }

  Future<void> attachScreenStream(Object? stream) async {
    if (!_started || stream == null) return;
    try { _compositorRemoveStream('screen'); } catch (_) {}
    try {
      _compositorAddStream(stream as web.MediaStream, 'screen');
      _log('screen stream attached to compositor');
    } catch (e) { _log('attachScreenStream error: $e'); }
  }

  Future<void> detachScreenStream() async {
    if (!_started) return;
    try { _compositorRemoveStream('screen'); _log('screen detached'); }
    catch (e) { _log('detachScreenStream error: $e'); }
  }

  void requestData() {}

  /// Whether the compositor ever captured a real (non-empty) chunk this
  /// session. False means the recording is empty — no camera/mic and no
  /// usable screen-share frames were captured before stop().
  bool get hadRealData {
    try { return _compositorHadRealData; } catch (_) { return false; }
  }

  /// Number of chunks that were actually confirmed uploaded to the server.
  int get chunksUploaded {
    try { return _compositorChunksUploaded; } catch (_) { return 0; }
  }

  /// Whether every chunk — including any still uploading in the background
  /// when stop() was called — has now actually reached the server. Check
  /// this (or listen via [waitForBackgroundUploads]) if you need to know
  /// when the recording is *fully* delivered, as opposed to just "the
  /// recorder has stopped" (which [stop] itself no longer waits on).
  bool get uploadsFullyDone {
    try { return _compositorUploadsDone; } catch (_) { return true; }
  }

  /// Stop recording. Returns as soon as the recorder itself has stopped and
  /// the final chunk has been handed off for upload — it does NOT wait for
  /// that upload (or any others still queued) to actually finish. Ending a
  /// session no longer has to stall on a slow connection: remaining chunks
  /// keep uploading in the background via the compositor's own upload
  /// queue, independent of this function returning. Use
  /// [waitForBackgroundUploads] if some other part of the app specifically
  /// needs to know once every chunk has truly landed on the server.
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _log('sending stop to compositor...');

    try {
      _compositorStop();
    } catch (e) {
      _log('compositorStop error: $e');
    }

    // Poll _ElFaheemCompositorDone — the JS now sets this as soon as the
    // recorder has stopped and the final chunk is enqueued, WITHOUT waiting
    // for uploads to finish, so this normally resolves in well under a
    // second. The 5-minute ceiling is just a safety net in case something
    // upstream (e.g. _recorder.stop() itself) never fires its events.
    const timeout = Duration(minutes: 5);
    final deadline = DateTime.now().add(timeout);

    while (!_compositorDone && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (_compositorDone) {
      _log('compositor stopped — any remaining chunks upload in the background');
    } else {
      _log('compositor stop TIMED OUT after 5 min ⚠️');
    }

    // Diagnostic only, and intentionally based on hadRealData rather than
    // chunksUploaded: at this point background chunks may genuinely still
    // be in flight, so chunksUploaded==0 here would NOT mean the session
    // was empty — only hadRealData (set synchronously the moment any real
    // chunk was captured) is safe to check without waiting for the network.
    if (!hadRealData) {
      _log('⚠️ WARNING: session ended with ZERO chunks captured — '
          'nothing was recorded (no camera/mic and no usable screen-share '
          'frames were ever captured).');
    } else {
      _log('recorder captured real data this session — '
          '$chunksUploaded chunk(s) confirmed uploaded so far '
          '(more may still be uploading in the background)');
    }
  }

  /// Optional: resolves once every chunk has actually reached the server,
  /// including any still uploading in the background after [stop] returned.
  /// Nothing in the normal recording flow needs to await this — it's only
  /// useful if some part of the app wants to show/confirm "fully uploaded"
  /// rather than just "recording stopped". Safe to call any time after
  /// [stop]; resolves immediately if uploads were already done.
  Future<void> waitForBackgroundUploads({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!uploadsFullyDone && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    if (uploadsFullyDone) {
      _log('background uploads complete — $chunksUploaded chunk(s) delivered ✅');
    } else {
      _log('waitForBackgroundUploads TIMED OUT after ${timeout.inMinutes} min ⚠️');
    }
  }

  Future<Uint8List?> drainBlobs() async => null;
}