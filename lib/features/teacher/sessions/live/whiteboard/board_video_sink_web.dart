// lib/features/teacher/sessions/live/whiteboard/board_video_sink_web.dart
//
// Web: the whiteboard's recording track is a <canvas>'s captureStream; each frame is put on the canvas as
// ImageData (the browser encodes only when the canvas changes, so the publisher repaints a still page every
// second to keep key frames coming). See board_video_source.dart.
library;

import 'dart:js_interop';
import 'dart:typed_data';

// flutter_webrtc re-exports dart_webrtc on the web only; the analyzer reads this file with the native exports.
// ignore: depend_on_referenced_packages
import 'package:dart_webrtc/dart_webrtc.dart' show MediaStreamWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:web/web.dart' as web;

import 'board_video_source.dart';

bool boardVideoSupported() => true;

Future<BoardVideoSource?> createBoardVideoSource({required int width, required int height, required int fps}) async {
  final canvas = web.HTMLCanvasElement()
    ..width = width
    ..height = height;
  final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
  if (ctx == null) return null;
  ctx.fillStyle = '#ffffff'.toJS;
  ctx.fillRect(0, 0, width, height);
  final js = canvas.captureStream(fps);
  final stream = MediaStreamWeb(js, 'local');
  final tracks = stream.getVideoTracks();
  if (tracks.isEmpty) return null;
  return _WebBoardSource(canvas, ctx, stream, tracks.first);
}

class _WebBoardSource implements BoardVideoSource {
  _WebBoardSource(this._canvas, this._ctx, this.stream, this.track);

  final web.HTMLCanvasElement _canvas;
  final web.CanvasRenderingContext2D _ctx;

  @override
  final rtc.MediaStream stream;

  @override
  final rtc.MediaStreamTrack track;

  @override
  Future<void> push(Uint8List rgba, int width, int height) async {
    if (width != _canvas.width || height != _canvas.height) return;
    final data = web.ImageData(Uint8ClampedList.sublistView(rgba).toJS, width, height.toJS);
    _ctx.putImageData(data, 0, 0);
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
