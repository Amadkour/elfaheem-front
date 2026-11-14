// lib/features/live/room/whiteboard/board_video_track.dart
//
// The whiteboard in SERVER recordings (D-090, amends D-087's "Recording"). LiveKit Egress records tracks, and a
// board is vectors on the data channel, so a server recording showed the cameras while a board was presented. Now,
// while (recording_mode == server) AND a server recording runs AND this device presents a board, the page is ALSO
// published as a slow video track: 1280×720, 2 fps, ≤ 500 kbps, one layer, VP8, source screen share, named
// `whiteboard` (kBoardVideoTrackName) so Egress's layout puts it on the stage. Every app that knows the name
// unsubscribes it at once and keeps drawing the board from its vectors (sharp at any zoom, no video cost); an
// older app shows it like a screen share of the board. In client mode nothing changes (the device recorder films
// the room UI, board included). Supported where an app-fed capturer exists: web and Android (see
// board_video_source.dart); elsewhere [BoardVideoPublisher.start] is a no-op.
//
// Cost on the presenter: one page render + readback every 500 ms only while the page changed (else the last frame
// is re-sent once a second for key frames), one 2 fps encoder. Viewers: nothing.
//
// A continuous page (D-107) is drawn from its items ([boardRecordingRgba]): the presenter's view widened to 16:9 over
// what the page has beside it, so a phone presenter's narrow view — or a page grown sideways — fills the frame
// instead of a pillar; the frame is drawn again when the view moves.
library;

import 'dart:async';
import 'dart:developer' show log;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart';

import 'package:flutter_education_app/features/live/live_media_plan.dart' show kBoardVideoTrackName;
import 'package:flutter_education_app/features/live/room/whiteboard/board_controller.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_export.dart' show boardRecordingRgba;
import 'package:flutter_education_app/features/live/room/whiteboard/board_format.dart' show BoardViewportPos;
import 'package:flutter_education_app/features/live/room/whiteboard/board_video_sink_native.dart' if (dart.library.js_interop) 'package:flutter_education_app/features/live/room/whiteboard/board_video_sink_web.dart' as sink;
import 'package:flutter_education_app/features/live/room/whiteboard/board_video_source.dart';

const int kBoardVideoWidth = 1280;
const int kBoardVideoHeight = 720;
const int kBoardVideoFps = 2;
const int kBoardVideoKbps = 500;

/// This device can publish the board as a track.
bool boardVideoSupported() => sink.boardVideoSupported();

/// The page behind [pageKey] as RGBA, exactly [width] × [height] (scaled into the frame, aspect kept). Null when the
/// page is not painted (the room is minimized, the board is not on screen).
Future<Uint8List?> boardPageRgba(GlobalKey pageKey, {int width = kBoardVideoWidth, int height = kBoardVideoHeight}) async {
  final ro = pageKey.currentContext?.findRenderObject();
  if (ro is! RenderRepaintBoundary || ro.size.isEmpty || ro.debugNeedsPaint) return null;
  final page = await ro.toImage(pixelRatio: width / ro.size.width);
  try {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..color = const Color(0xFFFFFFFF));
    final src = Rect.fromLTWH(0, 0, page.width.toDouble(), page.height.toDouble());
    final fit = applyBoxFit(BoxFit.contain, src.size, Size(width.toDouble(), height.toDouble()));
    final dst = Alignment.center.inscribe(fit.destination, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    canvas.drawImageRect(page, src, dst, Paint()..filterQuality = FilterQuality.medium);
    final frame = await rec.endRecording().toImage(width, height);
    try {
      final data = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data?.buffer.asUint8List();
    } finally {
      frame.dispose();
    }
  } finally {
    page.dispose();
  }
}

class BoardVideoPublisher {
  BoardVideoPublisher({required this.room, required this.pageKey, this.board});

  final Room room;
  final GlobalKey pageKey;

  /// The board: a continuous page is drawn from its items around the presenter's view (null: [pageKey] only).
  final BoardController? board;
  BoardViewportPos? _lastView;

  BoardVideoSource? _source;
  LocalVideoTrack? _track;
  Timer? _timer;
  bool _dirty = true;
  bool _busy = false;
  bool _starting = false;
  Uint8List? _last;
  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);

  bool get active => _track != null || _starting;

  /// The page changed: the next tick renders it again.
  void markDirty() => _dirty = true;

  /// Starts or stops so that the track runs exactly while [want].
  Future<void> sync({required bool want}) async {
    if (want && !active) {
      await start();
    } else if (!want && active) {
      await stop();
    }
  }

  Future<void> start() async {
    final local = room.localParticipant;
    if (active || local == null || !boardVideoSupported()) return;
    _starting = true;
    try {
      final source = await sink.createBoardVideoSource(width: kBoardVideoWidth, height: kBoardVideoHeight, fps: kBoardVideoFps);
      if (source == null) return;
      _source = source;
      const encoding = VideoEncoding(maxBitrate: kBoardVideoKbps * 1000, maxFramerate: kBoardVideoFps);
      // ignore: invalid_use_of_internal_member
      final track = LocalVideoTrack(
        TrackSource.screenShareVideo,
        source.stream,
        source.track,
        const ScreenShareCaptureOptions(
          maxFrameRate: kBoardVideoFps * 1.0,
          params: VideoParameters(dimensions: VideoDimensions(kBoardVideoWidth, kBoardVideoHeight), encoding: encoding),
        ),
      );
      _track = track;
      _dirty = true;
      await _tick(); // a first frame before the publish, so Egress never starts on an empty track
      await local.publishVideoTrack(
        track,
        publishOptions: const VideoPublishOptions(
          name: kBoardVideoTrackName,
          videoCodec: 'vp8',
          simulcast: false,
          screenShareEncoding: encoding,
          backupVideoCodec: BackupVideoCodec(enabled: false),
          degradationPreference: DegradationPreference.maintainResolution,
        ),
      );
      _timer = Timer.periodic(const Duration(milliseconds: 1000 ~/ kBoardVideoFps), (_) => unawaited(_tick()));
      log('[BOARD] recording track published ${kBoardVideoWidth}x$kBoardVideoHeight@$kBoardVideoFps');
    } catch (e) {
      log('[BOARD] recording track failed: $e');
      await stop();
    } finally {
      _starting = false;
    }
  }

  Future<void> _tick() async {
    final source = _source;
    if (_busy || source == null) return;
    _busy = true;
    try {
      final now = DateTime.now();
      final b = board;
      final continuous = b != null && b.isContinuous;
      if (continuous && b.localViewport != _lastView) _dirty = true; // the presenter scrolled
      if (_dirty) {
        _lastView = continuous ? b.localViewport : null;
        final rgba = continuous ? await boardRecordingRgba(b) : await boardPageRgba(pageKey);
        if (rgba != null) {
          _last = rgba;
          _dirty = false;
        }
      } else if (now.difference(_lastPush) < const Duration(seconds: 1)) {
        return; // a still page: once a second is enough for key frames
      }
      final frame = _last;
      if (frame == null) return;
      await source.push(frame, kBoardVideoWidth, kBoardVideoHeight);
      _lastPush = now;
    } catch (e) {
      log('[BOARD] frame: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final track = _track;
    final source = _source;
    _track = null;
    _source = null;
    _last = null;
    final local = room.localParticipant;
    if (track != null && local != null) {
      final pub = local.videoTrackPublications.where((p) => p.track == track || p.name == kBoardVideoTrackName).firstOrNull;
      if (pub != null) {
        try {
          await local.removePublishedTrack(pub.sid);
        } catch (e) {
          log('[BOARD] unpublish: $e');
        }
      }
    }
    try {
      await track?.stop();
    } catch (_) {}
    await source?.dispose();
  }
}
