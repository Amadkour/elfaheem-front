// lib/features/live/room/whiteboard/board_video_sink_native.dart
//
// Android: the whiteboard's recording track is an ElFaheemFrameCapturer track (getDisplayMedia with
// `useElFaheemCapturer`, no MediaProjection); its frames are pushed through MainActivity's `pushBoardFrame`.
// iOS / desktop: not supported (null). See board_video_source.dart.
library;

import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' show PlatformType, lkPlatformIs;

import 'package:flutter_education_app/features/live/room/whiteboard/board_video_source.dart';

const _channel = MethodChannel('com.doubley.alfaheem/screen_share');

bool boardVideoSupported() => lkPlatformIs(PlatformType.android);

Future<BoardVideoSource?> createBoardVideoSource({required int width, required int height, required int fps}) async {
  if (!boardVideoSupported()) return null;
  final stream = await rtc.navigator.mediaDevices.getDisplayMedia({
    'video': {'useElFaheemCapturer': true, 'width': width, 'height': height, 'frameRate': fps},
  });
  final tracks = stream.getVideoTracks();
  if (tracks.isEmpty) {
    await stream.dispose();
    return null;
  }
  return _AndroidBoardSource(stream, tracks.first);
}

class _AndroidBoardSource implements BoardVideoSource {
  _AndroidBoardSource(this.stream, this.track);

  @override
  final rtc.MediaStream stream;

  @override
  final rtc.MediaStreamTrack track;

  @override
  Future<void> push(Uint8List rgba, int width, int height) async {
    await _channel.invokeMethod<bool>('pushBoardFrame', {'rgba': rgba, 'width': width, 'height': height});
  }

  @override
  Future<void> dispose() async {
    try {
      await track.stop();
    } catch (_) {}
    try {
      await stream.dispose();
    } catch (_) {}
  }
}
