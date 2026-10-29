// lib/features/teacher/sessions/live/whiteboard/board_video_source.dart
//
// Where the whiteboard's recording frames go (D-090): a video track fed with RGBA frames of the presented page.
// Web: a <canvas> + captureStream (board_video_sink_web.dart). Android: the flutter_webrtc fork's
// ElFaheemFrameCapturer, fed through the screen-share channel's `pushBoardFrame` (board_video_sink_native.dart).
// iOS has no app-fed capturer in this WebRTC build: no recording track there (the server recording then shows the
// cameras while an iPhone presents a board, as before).
library;

import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

abstract class BoardVideoSource {
  rtc.MediaStream get stream;

  rtc.MediaStreamTrack get track;

  /// One frame: tightly packed RGBA, top-left origin, [width] × [height].
  Future<void> push(Uint8List rgba, int width, int height);

  Future<void> dispose();
}
