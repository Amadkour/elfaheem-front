// recorder_web_stub.dart
// Loaded on mobile/desktop — same public API as recorder_web_impl.dart, all no-ops.
import 'dart:typed_data';

bool isTypeSupported(String mime) => false;

Future<Object?> getDisplayMedia() async => null;
Future<Object?> getUserMedia({bool video = true}) async => null;
Future<Object?> getAudioOnly() async => null;

class WebRecorder {
  WebRecorder({required void Function(int) onBlob});
  Future<bool> start(Object? stream, String mimeType) async => false;
  void requestData() {}
  Future<void> stop() async {}
  Future<Uint8List?> drainBlobs() async => null;
}