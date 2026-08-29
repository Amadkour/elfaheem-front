// recorder_web_stub.dart — mobile/desktop no-ops
import 'dart:typed_data';

bool isTypeSupported(String mime) => false;
Future<Object?> getUserMedia({bool video = true}) async => null;
Future<Object?> getAudioOnly() async => null;
Future<Object?> getDisplayMedia() async => null;
Object? toWebMediaStream(Object? obj) => null;
Object? streamFromLivekitTrack(Object? track) => null;

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
      }) {}
  void updateParticipantCount(int count) {}
  void pause() {}
  void resume() {}
  void addStream(Object? stream, String label) {}
  void removeStream(String label) {}
  void setPlaceholderImage(Uint8List png) {}
  void requestData() {}
  bool get hadRealData => false;
  int get chunksUploaded => 0;
  Future<void> stop() async {}
  Future<void> attachScreenStream(Object? s) async {}
  Future<void> detachScreenStream() async {}
  Future<Uint8List?> drainBlobs() async => null;
}