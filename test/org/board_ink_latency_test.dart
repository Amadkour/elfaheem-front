// The ink keeps up with the pen (D-317): the filter's lag behind it, and what a pen-down costs on a full page.
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/annotation/annotation_ink.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_controller.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_protocol.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_stage.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

/// The worst distance (px) between the pen and the last point given out, over a straight stroke at [v] px/s.
double _worstLag(AnnotInkFilter f, double v, double hz) {
  f.start(0, 0, 0, .5);
  var last = 0.0, worst = 0.0;
  for (var i = 1; i <= 0.6 * hz; i++) {
    final t = i / hz, x = v * t;
    final s = f.add(x, 0, t, .5);
    if (s != null) last = s.x;
    worst = math.max(worst, x - last);
  }
  return worst;
}

/// RMS (px) of what is left of a digitiser's ±[noise] px sideways jitter on a slow stroke (the raw value is noise / √3).
double _jitterLeft(AnnotInkFilter f, double noise) {
  final r = math.Random(7);
  f.start(0, 0, 0, .5);
  var sum = 0.0, n = 0;
  for (var i = 1; i < 120; i++) {
    final t = i / 60;
    final s = f.add(30 * t + (r.nextDouble() - .5) * 2 * noise, (r.nextDouble() - .5) * 2 * noise, t, .5);
    if (s == null) continue;
    sum += s.y * s.y;
    n++;
  }
  return math.sqrt(sum / n);
}

void main() {
  group('the filter does not trail the pen', () {
    test('a quick stroke is at most a few px behind from its first sample on', () {
      for (final hz in [60.0, 120.0]) {
        for (final v in [120.0, 400.0, 1000.0]) {
          expect(_worstLag(boardInkFilter(pressure: true), v, hz), lessThan(3.5), reason: '$v px/s at $hz Hz');
        }
      }
    });

    test('the jitter of a slow stroke is still smoothed', () {
      expect(_jitterLeft(boardInkFilter(pressure: true), .5), lessThan(0.289 * 0.7));
    });
  });

  testWidgets('a pen-down on a full page rebuilds nothing and repaints no finished stroke', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = BoardController(localIdentity: 'teacher_1', autoFlush: false, deferInkSettle: true, idPrefix: 't1', isHost: (i) => true);
    addTearDown(c.dispose);
    c.send = (topic, bytes, reliable, {to}) async {};
    c.startPresenting(format: BoardFormat.landscape);
    final r = math.Random(3);
    for (var s = 0; s < 120; s++) {
      final x0 = r.nextDouble() * 0.8 + 0.1, y0 = r.nextDouble() * 0.8 + 0.05;
      c.beginInk(x0, y0, stylus: true);
      for (var i = 1; i < 200; i++) {
        c.moveInk(x0 + 0.05 * math.sin(i / 10) + i * 0.0003, y0 + 0.05 * math.cos(i / 7), p: 0.4 + 0.2 * math.sin(i / 13));
      }
      c.endInk();
    }
    await t.pumpWidget(layoutHost(WhiteboardRoomView(controller: c, onStop: () {}, keyboard: false), scale: 1));
    await t.pump(const Duration(milliseconds: 100));
    final at = t.getRect(find.byType(WhiteboardStage)).center;
    // The first stylus touch may show the one-time "stylus only?" offer.
    final first = await t.startGesture(at, kind: PointerDeviceKind.stylus, pointer: 7);
    await first.moveBy(const Offset(4, 2));
    await t.pump(const Duration(milliseconds: 16));
    await first.up();
    await t.pump(const Duration(milliseconds: 100));

    var rebuilds = 0, settled = 0;
    c.scene.settled.addListener(() => settled++);
    debugOnRebuildDirtyWidget = (e, builtOnce) => rebuilds++;
    final sw = Stopwatch()..start();
    final g = await t.startGesture(at + const Offset(40, 40), kind: PointerDeviceKind.stylus, pointer: 8);
    await t.pump(const Duration(milliseconds: 16));
    sw.stop();
    final downMs = sw.elapsedMicroseconds / 1000, down = rebuilds, downSettled = settled;
    rebuilds = 0;
    await g.moveBy(const Offset(4, 2));
    await t.pump(const Duration(milliseconds: 16));
    rebuilds = 0;
    sw
      ..reset()
      ..start();
    await g.up();
    await t.pump(const Duration(milliseconds: 16));
    sw.stop();
    debugOnRebuildDirtyWidget = null;
    // ignore: avoid_print
    print('D-317 pen-down: ${downMs.toStringAsFixed(1)} ms, $down rebuilds · pen-up: ${(sw.elapsedMicroseconds / 1000).toStringAsFixed(1)} ms, $rebuilds rebuilds');
    expect(c.scene.items.whereType<BoardInk>().where((s) => s.open), isEmpty);
    expect(downSettled, 0, reason: 'nothing finished changed');
    expect(down, lessThanOrEqualTo(4));
    expect(rebuilds, lessThanOrEqualTo(4), reason: 'a pen-up paints the finished ink, the layout waits for a pause');
    expect(settled, 0);
    await t.pump(kBoardInkSettleDelay + const Duration(milliseconds: 20));
    expect(settled, 1, reason: 'the pen paused');
  });

  testWidgets('the layout never lands in the middle of the next stroke', (t) async {
    final c = BoardController(localIdentity: 'teacher_1', autoFlush: false, deferInkSettle: true, idPrefix: 't1', isHost: (i) => true);
    c.send = (topic, bytes, reliable, {to}) async {};
    c.startPresenting();
    var settled = 0;
    c.scene.settled.addListener(() => settled++);
    c.beginInk(0.1, 0.1);
    c.endInk();
    await t.pump(const Duration(milliseconds: 100));
    c.beginInk(0.2, 0.2); // the next letter, while the first one's layout waits
    await t.pump(const Duration(seconds: 1));
    expect(settled, 0);
    c.endInk();
    await t.pump(kBoardInkSettleDelay);
    expect(settled, 1);
    c.dispose();
  });
}
