// D-811: the drawing on a shared screen reaches the web recording (annotation/annot_rec_frames.dart, the stage tile's
// overlay in live_recording_layout.dart, drawn by web/recorder_compositor.js).
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_education_app/features/live/live_recording_layout.dart';
import 'package:flutter_education_app/features/live/room/annotation/annot_rec_frames.dart';
import 'package:flutter_education_app/features/live/room/annotation/annotation_controller.dart';
import 'package:flutter_education_app/features/live/room/annotation/annotation_ink.dart';
import 'package:flutter_test/flutter_test.dart';

/// The extent of every point a stroke's path passes through.
class _Bounds implements AnnotPathSink {
  double minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;

  void _add(double x, double y) {
    minX = math.min(minX, x);
    minY = math.min(minY, y);
    maxX = math.max(maxX, x);
    maxY = math.max(maxY, y);
  }

  @override
  void moveTo(double x, double y) => _add(x, y);
  @override
  void lineTo(double x, double y) => _add(x, y);
  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x, double y) => _add(x, y);
  @override
  void arc(double cx, double cy, double r, double start, double sweep) => _add(cx, cy);
  @override
  void circle(double cx, double cy, double r) {
    _add(cx - r, cy - r);
    _add(cx + r, cy + r);
  }

  @override
  void close() {}
}

void main() {
  var clock = DateTime(2026, 11, 13, 10);

  AnnotationController host() {
    final c = AnnotationController(localIdentity: 'teacher_1', now: () => clock, autoFlush: false, idPrefix: 't_');
    c.setRoles(hosts: {'teacher_1'}, presenter: 'student_2');
    return c;
  }

  group('the share stage carries the drawing', () {
    test('a stage with an overlay names it on its tile and among the sources', () {
      const cam = RecSource(label: 'rcam_1', kind: RecSourceKind.camera, name: 'Sara');
      for (final cams in [const <RecSource>[], const [cam]]) {
        final layout = recordingLayout(
          stage: const RecSource(label: 'rscreen_9', kind: RecSourceKind.screen, overlay: kAnnotRecLabel),
          cameras: cams,
        );
        final stage = layout.tiles.firstWhere((t) => t.main);
        expect(stage.overlay, kAnnotRecLabel);
        expect(layout.labels, contains(kAnnotRecLabel));
        final json = jsonDecode(layout.toJson()) as Map<String, dynamic>;
        final tiles = (json['tiles'] as List).cast<Map<String, dynamic>>();
        expect(tiles.first['o'], kAnnotRecLabel);
        expect(tiles.skip(1).every((t) => !t.containsKey('o')), isTrue, reason: 'cameras carry no drawing');
      }
    });

    test('no overlay: the tile is unchanged on the wire', () {
      final layout = recordingLayout(stage: const RecSource(label: 'screen', kind: RecSourceKind.screen));
      final json = jsonDecode(layout.toJson()) as Map<String, dynamic>;
      expect((json['tiles'] as List).first, isNot(contains('o')));
      expect(layout.labels, {'screen'});
    });
  });

  group('annotRecSize', () {
    test('the share shape at the recording width', () {
      expect(annotRecSize(16 / 9), (1920, 1080));
      expect(annotRecSize(null), (1920, 1080));
      expect(annotRecSize(4 / 3), (1920, 1440));
      expect(annotRecSize(9 / 16), (1080, 1920));
      expect(annotRecSize(double.nan), (1920, 1080));
    });
  });

  group('AnnotRecFrames', () {
    test('an empty board is an empty frame', () {
      final f = AnnotRecFrames().frame(host().board, aspect: 16 / 9);
      expect(f.open, isEmpty);
      expect((f.width, f.height), (1920, 1080));
    });

    test('a stroke lands where it was drawn on the share, in frame pixels', () {
      final c = host();
      expect(c.begin(0.1, 0.2), isTrue);
      c.move(0.3, 0.4);
      c.move(0.5, 0.6);
      c.end();
      final f = AnnotRecFrames().frame(c.board, aspect: 16 / 9);
      expect(f.open, hasLength(1));
      final b = _Bounds();
      f.open.single.replay(b);
      expect(b.minX, closeTo(0.1 * 1920, 2));
      expect(b.maxX, closeTo(0.5 * 1920, 2));
      expect(b.minY, closeTo(0.2 * 1080, 2));
      expect(b.maxY, closeTo(0.6 * 1080, 2));
      expect(f.clip, const Rect.fromLTWH(0, 0, 1920, 1080));
    });

    test('an unchanged stroke is traced once; a new point traces it again; an undone one is forgotten', () {
      final c = host();
      final frames = AnnotRecFrames();
      c.begin(0.1, 0.1);
      c.move(0.2, 0.2);
      frames.frame(c.board, aspect: 16 / 9);
      expect(frames.traced, 1);
      frames.frame(c.board, aspect: 16 / 9);
      expect(frames.traced, 1, reason: 'nothing changed');
      c.move(0.3, 0.3);
      frames.frame(c.board, aspect: 16 / 9);
      expect(frames.traced, 2, reason: 'the open stroke grew');
      c.end();
      frames.frame(c.board, aspect: 16 / 9);
      final afterEnd = frames.traced;
      frames.frame(c.board, aspect: 4 / 3);
      expect(frames.traced, afterEnd + 1, reason: 'a new share shape traces again');
      c.undo();
      expect(frames.frame(c.board, aspect: 4 / 3).open, isEmpty);
    });

    test('the laser dot is in the recording while it shows, gone once it faded', () {
      final c = host();
      c.setTool(AnnotTool.laser);
      c.begin(0.5, 0.5);
      final frames = AnnotRecFrames();
      final f = frames.frame(c.board, aspect: 16 / 9, laserOpacity: c.laserOpacity);
      expect(f.open, hasLength(2), reason: 'a glow and the dot');
      clock = clock.add(c.laserTtl);
      expect(frames.frame(c.board, aspect: 16 / 9, laserOpacity: c.laserOpacity).open, isEmpty);
    });
  });
}
