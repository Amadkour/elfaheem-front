// recorder_web_stub.dart — mobile/desktop no-ops
import 'dart:typed_data';

import '../whiteboard/board_rec_ink.dart';

bool isTypeSupported(String mime) => false;
Future<Object?> getUserMedia({bool video = true}) async => null;
Future<Object?> getAudioOnly() async => null;
Future<Object?> getDisplayMedia() async => null;
Object? toWebMediaStream(Object? obj) => null;
Object? streamFromLivekitTrack(Object? track) => null;

// Mirrors recorder_web_impl.dart's nativeAudioStreamFromTrack. Never actually
// called on mobile/desktop — every call site is gated behind `if (kIsWeb)` —
// but it must exist here so room.dart's conditional import (see
// room.dart's `import 'widgets/recorder_web_stub.dart' if (...) '...impl.dart'`)
// resolves this name on every platform, not just web.
Object? nativeAudioStreamFromTrack(Object? lkTrack) => null;

// Mirror recorder_web_impl.dart's screen-share helpers (only called on web).
bool setTrackContentHint(Object? lkTrack, String hint) => false;
bool displayAudioSupported() => false;

class WebRecorder {
  WebRecorder({required void Function(int) onBlob});
  Future<bool> start(Object? stream, String mimeType) async => false;
  void startCompositor(
      int sessionId,
      String apiUrl,
      String authToken, {
        String teacherName = '',
        String sessionTitle = '',
        int participantCount = 0,
        String? uploadUrl,
        int? videoBitsPerSecond,
        int? canvasHeight,
        bool audioOnly = false,
        String? epoch,
      }) {}
  Future<void> waitForBackgroundUploads({Duration timeout = const Duration(minutes: 5)}) async {}
  void updateParticipantCount(int count) {}
  void pause() {}
  void resume() {}
  void addStream(Object? stream, String label) {}
  void removeStream(String label) {}
  void setPlaceholderImage(Uint8List png) {}
  void setLayout(String json) {}
  void addTrack(Object? lkTrack, String label) {}
  bool pushBoardFrame(String label, BoardRecFrame frame) => true;
  void requestData() {}
  bool get hadRealData => false;
  int get chunksUploaded => 0;
  Future<void> stop() async {}
  Future<void> attachScreenStream(Object? s) async {}
  Future<void> detachScreenStream() async {}
  Future<Uint8List?> drainBlobs() async => null;
}