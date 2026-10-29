// The annotation layer over the shared video (annotation_layer.dart + annotation_painter.dart, D-079): every size,
// both languages, text 1.3x, with strokes / highlighter / pressure / laser and a letterboxed 16:9 frame — no
// layout error; a drag lands at the right normalised spot through the `contain` fit; outside draw mode the
// video below gets the taps; palm-safe (touches ignored while a stylus is down, a stylus beats a drawing touch).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/annotation/annotation_controller.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/annotation/annotation_painter.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/annotation/annotation_layer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

AnnotationController _controller({bool draw = true}) {
  final c = AnnotationController(localIdentity: 'teacher_1', autoFlush: false);
  c.setRoles(hosts: {'teacher_1'});
  c.setDrawMode(draw);
  return c;
}

Widget _stage(AnnotationController c, {Size? content = const Size(1600, 900), VoidCallback? onVideoTap}) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('video'),
            onTap: onVideoTap,
            child: const ColoredBox(color: Color(0xFF101418)),
          ),
        ),
        Positioned.fill(child: AnnotationLayer(controller: c, contentSize: content)),
      ],
    );

void _host(WidgetTester t, Size size) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  test('contain fit: letterbox / pillarbox, round trip', () {
    final r = AnnotFit.contain(const Size(1600, 900), const Size(320, 640));
    expect(r.width, 320);
    expect(r.height, 180);
    expect(r.top, 230);
    final p = AnnotFit.contain(const Size(1080, 2400), const Size(1400, 900));
    expect(p.height, 900);
    expect(p.left, closeTo((1400 - 405) / 2, 0.01));
    final n = AnnotFit.toNormal(AnnotFit.toLocal(0.25, 0.75, p), p);
    expect(n.dx, closeTo(0.25, 1e-9));
    expect(n.dy, closeTo(0.75, 1e-9));
    expect(AnnotFit.contain(null, const Size(10, 20)), const Rect.fromLTWH(0, 0, 10, 20));
  });

  testWidgets('layout: strokes, highlighter, pressure, laser; drawing and not; letterboxed and full', (t) async {
    final c = _controller();
    addTearDown(c.dispose);
    c.begin(0.1, 0.1, p: 0.2);
    for (var i = 1; i < 30; i++) {
      c.move(0.1 + i / 40, 0.1 + (i % 5) / 20, p: (i % 10) / 10);
    }
    c.end();
    c.setTool(AnnotTool.highlighter);
    c.begin(0.1, 0.8);
    c.move(0.9, 0.8);
    c.end();
    c.begin(0.5, 0.5); // a single dot
    c.end();
    c.setTool(AnnotTool.laser);
    c.begin(0.6, 0.4);
    c.end();
    final viewer = _controller(draw: false);
    addTearDown(viewer.dispose);
    await expectNoLayoutErrors(
      t,
      () => Column(children: [
        Expanded(child: _stage(c)),
        Expanded(child: _stage(viewer, content: null)),
        SizedBox(height: 120, child: _stage(c, content: const Size(1080, 2400))),
      ]),
    );
  });

  testWidgets('a drag lands at the right normalised spot through the contain fit (letterboxed 16:9 on a phone)', (t) async {
    _host(t, const Size(320, 640));
    final c = _controller();
    addTearDown(c.dispose);
    await t.pumpWidget(layoutHost(_stage(c), scaffold: false, scale: 1));
    // The frame is 320 x 180 at y 230. From 25 % / 50 % to 75 % / 50 %.
    final g = await t.startGesture(const Offset(80, 320), kind: PointerDeviceKind.touch);
    for (var x = 90.0; x <= 240; x += 10) {
      await g.moveTo(Offset(x, 320));
    }
    await g.up();
    await t.pump();
    final s = c.board.strokes.single;
    expect(s.points.first.x, closeTo(0.25, 0.001));
    expect(s.points.first.y, closeTo(0.5, 0.001));
    expect(s.points.last.x, closeTo(0.75, 0.001));
    expect(s.points.length, 2); // a straight line: simplified to its ends
    // A press in the black band above the frame draws nothing.
    final g2 = await t.startGesture(const Offset(100, 100));
    await g2.moveTo(const Offset(150, 120));
    await g2.up();
    expect(c.board.strokeCount, 1);
  });

  testWidgets('outside draw mode the video below gets the taps', (t) async {
    _host(t, const Size(800, 600));
    final c = _controller(draw: false);
    addTearDown(c.dispose);
    var taps = 0;
    await t.pumpWidget(layoutHost(_stage(c, onVideoTap: () => taps++), scaffold: false, scale: 1));
    await t.tapAt(const Offset(400, 300));
    expect(taps, 1);
    c.setDrawMode(true);
    await t.pump();
    await t.tapAt(const Offset(400, 300));
    await t.pump();
    expect(taps, 1, reason: 'the layer takes the pointer while drawing');
    expect(c.board.strokeCount, 1);
    // A student without permission: draw mode cannot turn on, the video keeps the taps.
    final s = AnnotationController(localIdentity: 'student_2', autoFlush: false)..setRoles(hosts: {'teacher_1'});
    addTearDown(s.dispose);
    s.setDrawMode(true);
    await t.pumpWidget(layoutHost(_stage(s, onVideoTap: () => taps++), scaffold: false, scale: 1));
    await t.tapAt(const Offset(400, 300));
    expect(taps, 2);
  });

  testWidgets('palm-safe: touches are ignored while a stylus draws; a stylus replaces a drawing touch', (t) async {
    _host(t, const Size(800, 450));
    final c = _controller();
    addTearDown(c.dispose);
    await t.pumpWidget(layoutHost(_stage(c), scaffold: false, scale: 1));

    final pen = await t.startGesture(const Offset(100, 100), kind: PointerDeviceKind.stylus, pointer: 1);
    final palm = await t.startGesture(const Offset(600, 400), kind: PointerDeviceKind.touch, pointer: 2);
    await palm.moveTo(const Offset(650, 420));
    await pen.moveTo(const Offset(300, 100));
    await palm.up();
    await pen.up();
    await t.pump();
    expect(c.board.strokeCount, 1);
    expect(c.board.strokes.single.points.every((p) => p.y < 0.3), isTrue);

    // A touch right after the stylus lifted is still taken as the palm.
    final late = await t.startGesture(const Offset(500, 300), kind: PointerDeviceKind.touch, pointer: 3);
    await late.moveTo(const Offset(550, 300));
    await late.up();
    expect(c.board.strokeCount, 1);

    await t.pump(const Duration(seconds: 1));
    // A touch starts drawing (the palm landed first), then the stylus comes down: the touch stroke goes away.
    final c2 = _controller();
    addTearDown(c2.dispose);
    await t.pumpWidget(layoutHost(_stage(c2), scaffold: false, scale: 1));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600))); // past the palm guard (wall clock)
    final touch = await t.startGesture(const Offset(600, 400), kind: PointerDeviceKind.touch, pointer: 4);
    await touch.moveTo(const Offset(620, 410));
    expect(c2.board.strokeCount, 1);
    final pen2 = await t.startGesture(const Offset(100, 100), kind: PointerDeviceKind.stylus, pointer: 5);
    await pen2.moveTo(const Offset(200, 120));
    await touch.up();
    await pen2.up();
    await t.pump();
    expect(c2.board.strokeCount, 1);
    expect(c2.board.strokes.single.points.first.x, closeTo(100 / 800, 0.002));
  });

  testWidgets('the stylus eraser end erases; pressure reaches the stroke', (t) async {
    _host(t, const Size(800, 450));
    final c = _controller();
    addTearDown(c.dispose);
    await t.pumpWidget(layoutHost(_stage(c), scaffold: false, scale: 1));
    const stylus = PointerDeviceKind.stylus;
    await t.sendEventToBinding(const PointerDownEvent(
        pointer: 11, device: 3, kind: stylus, position: Offset(100, 200), pressure: 0.9, pressureMin: 0, pressureMax: 1));
    await t.sendEventToBinding(const PointerMoveEvent(
        pointer: 11, device: 3, kind: stylus, position: Offset(300, 200), delta: Offset(200, 0), pressure: 0.2,
        pressureMin: 0, pressureMax: 1, buttons: kPrimaryStylusButton));
    await t.sendEventToBinding(const PointerUpEvent(pointer: 11, device: 3, kind: stylus, position: Offset(300, 200)));
    await t.pump();
    final s = c.board.strokes.single;
    expect(s.points.first.p, closeTo(0.9, 0.001));
    expect(s.points.last.p, closeTo(0.2, 0.001));
    final e = TestPointer(2, PointerDeviceKind.invertedStylus);
    await t.sendEventToBinding(e.down(const Offset(200, 200)));
    await t.sendEventToBinding(e.up());
    await t.pump();
    expect(c.board.isEmpty, isTrue);
    expect(c.tool, AnnotTool.pen, reason: 'the eraser end does not change the picked tool');
  });
}
