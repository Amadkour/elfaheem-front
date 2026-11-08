// D-313: the web recording's board frames — the pacer (board_rec_pacing.dart) and the cached renderer
// (board_export.dart BoardRecordingFrames).
//
// BOARD_REC_BENCH=1 flutter test test/org/board_rec_pacing_test.dart prints what a frame costs on this machine
// (host Skia; in Chrome with CanvasKit: flutter test --platform chrome --dart-define=BOARD_REC_BENCH=1 …).
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_controller.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_export.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_protocol.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_rec_pacing.dart';
import 'package:flutter_test/flutter_test.dart';

BoardController _board() {
  final c = BoardController(
    localIdentity: 'meet_1',
    autoFlush: false,
    idPrefix: 'm1',
    isHost: (_) => true,
    mayPresent: (_) => true,
    studentMayDraw: (_) => true,
  );
  c.send = (topic, bytes, reliable, {to}) async {};
  c.startPresenting(background: BoardBackground.grid);
  return c;
}

void _strokes(BoardController c, int n) {
  for (var i = 0; i < n; i++) {
    final y = 0.05 + (i % 40) * 0.022;
    c.beginInk(0.05, y);
    for (var k = 1; k <= 30; k++) {
      c.moveInk(0.05 + k * 0.028, y + (k.isEven ? 0.006 : -0.006));
    }
    c.endInk();
  }
}

void main() {
  final t0 = DateTime(2026, 11, 8, 10);

  group('BoardRecPacer', () {
    test('starts at 30 fps full size and keeps at most one start per period', () {
      final p = BoardRecPacer();
      expect(p.tier.fps, 30);
      expect(p.tier.scale, 1);
      expect(p.waitFrom(t0), Duration.zero);
      p.started(t0);
      expect(p.waitFrom(t0.add(const Duration(milliseconds: 10))), const Duration(microseconds: 23333));
      expect(p.waitFrom(t0.add(const Duration(milliseconds: 40))), Duration.zero);
    });

    test('cheap frames stay on top', () {
      final p = BoardRecPacer();
      for (var i = 0; i < 200; i++) {
        expect(p.finished(const Duration(milliseconds: 4)), isFalse);
      }
      expect(p.tierIndex, 0);
    });

    test('slow captures step down (fps first, then size) and never below the last tier', () {
      final p = BoardRecPacer();
      final seen = <int>[];
      for (var i = 0; i < 100; i++) {
        if (p.finished(const Duration(milliseconds: 60))) seen.add(p.tierIndex);
      }
      expect(seen, [1, 2, 3, 4, 5, 6]);
      expect(p.tier, kBoardRecTiers.last);
      expect(p.tier.fps, greaterThanOrEqualTo(5));
    });

    test('one slow frame (a GC) does not move the tier; a few in a row do', () {
      final p = BoardRecPacer();
      for (var i = 0; i < 10; i++) {
        p.finished(const Duration(milliseconds: 5));
      }
      expect(p.finished(const Duration(milliseconds: 25)), isFalse, reason: 'EMA 5 → 11 ms, under 35 % of 33 ms');
      expect(p.tierIndex, 0);
      var steps = 0;
      for (var i = 0; i < 4; i++) {
        if (p.finished(const Duration(milliseconds: 25))) steps++;
      }
      expect(steps, greaterThan(0));
    });

    test('climbs one tier after upAfter cheap frames in a row, reset by a dearer one', () {
      final p = BoardRecPacer(upAfter: 5);
      for (var i = 0; i < 30 && p.tierIndex < 3; i++) {
        p.finished(const Duration(milliseconds: 80));
      }
      final low = p.tierIndex;
      expect(low, greaterThan(0));
      // Cheap frames: the average must fall first (it lags), then 5 cheap ones in a row per step up.
      for (var i = 0; i < 100 && p.tierIndex >= low; i++) {
        p.finished(const Duration(milliseconds: 1));
      }
      expect(p.tierIndex, low - 1);
      // A dearer frame resets the run: 4 cheap + 1 middling + 4 cheap is no step.
      final at = p.tierIndex;
      for (var i = 0; i < 4; i++) {
        p.finished(const Duration(milliseconds: 1));
      }
      p.finished(Duration(microseconds: (p.tier.period.inMicroseconds * 0.7).round()));
      for (var i = 0; i < 3; i++) {
        p.finished(const Duration(milliseconds: 1));
      }
      expect(p.tierIndex, at);
    });

    test('frame sizes are even and follow the scale', () {
      expect(BoardRecPacer.sizeFor(const BoardRecTier(30, 1)), (1280, 720));
      expect(BoardRecPacer.sizeFor(const BoardRecTier(24, 0.75)), (960, 540));
      expect(BoardRecPacer.sizeFor(const BoardRecTier(8, 0.5)), (640, 360));
    });

    test('stats: one line a second', () {
      final s = BoardRecStats();
      const tier = BoardRecTier(30, 1);
      expect(s.add(const Duration(milliseconds: 8), t0, tier), isNull);
      expect(s.add(const Duration(milliseconds: 12), t0.add(const Duration(milliseconds: 500)), tier), isNull);
      final line = s.add(const Duration(milliseconds: 10), t0.add(const Duration(seconds: 1)), tier);
      expect(line, contains('capture avg 10.0 ms, max 12.0 ms'));
      expect(line, contains('3.0/s'));
    });
  });

  group('BoardRecordingFrames', () {
    testWidgets('a frame is the requested size; finished strokes are cached while one is drawn', (t) async {
      await t.runAsync(() async {
        final c = _board();
        _strokes(c, 20);
        final f = BoardRecordingFrames();
        var rgba = await f.render(c, width: 640, height: 360);
        expect(rgba, isNotNull);
        expect(rgba!.length, 640 * 360 * 4);
        expect(f.rebuilt, isTrue);
        // Drawing: the cache stays, only the open stroke is painted on top.
        c.beginInk(0.2, 0.9);
        for (var k = 0; k < 5; k++) {
          c.moveInk(0.2 + k * 0.05, 0.9);
          rgba = await f.render(c, width: 640, height: 360);
          expect(f.rebuilt, isFalse);
        }
        // The stroke ends: one rebuild, then the cache again.
        c.endInk();
        await f.render(c, width: 640, height: 360);
        expect(f.rebuilt, isTrue);
        await f.render(c, width: 640, height: 360);
        expect(f.rebuilt, isFalse);
        // A new size rebuilds.
        await f.render(c, width: 1280, height: 720);
        expect(f.rebuilt, isTrue);
        f.dispose();
      });
    });

    testWidgets('bench (BOARD_REC_BENCH=1)', (t) async {
      const onWeb = bool.fromEnvironment('BOARD_REC_BENCH');
      if (!(kIsWeb ? onWeb : Platform.environment['BOARD_REC_BENCH'] != null)) return;
      await t.runAsync(() async {
        for (final n in [10, 100, 400]) {
          final c = _board();
          _strokes(c, n);
          for (final tier in [kBoardRecTiers[0], kBoardRecTiers[2], kBoardRecTiers[4]]) {
            final (w, h) = BoardRecPacer.sizeFor(tier);
            final f = BoardRecordingFrames();
            await f.render(c, width: w, height: h); // warm-up + the cache
            c.beginInk(0.1, 0.95);
            final sw = Stopwatch()..start();
            const frames = 30;
            for (var k = 0; k < frames; k++) {
              c.moveInk(0.1 + k * 0.02, 0.95);
              await f.render(c, width: w, height: h);
            }
            sw.stop();
            c.endInk();
            final uncached = Stopwatch()..start();
            final full = BoardRecordingFrames();
            await full.render(c, width: w, height: h);
            uncached.stop();
            full.dispose();
            f.dispose();
            // ignore: avoid_print
            print('strokes $n  ${w}x$h  drawing frame ${(sw.elapsedMicroseconds / frames / 1000).toStringAsFixed(1)} ms'
                '  full render ${(uncached.elapsedMicroseconds / 1000).toStringAsFixed(1)} ms');
          }
        }
      });
    });
  });
}
