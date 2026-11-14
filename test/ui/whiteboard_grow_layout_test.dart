// A continuous whiteboard that grows sideways (D-107): a grown board — presenter with the dock, a viewer scrolled away
// with "Follow …" and both rails — at 320×640 and 1400×900, Arabic and English, text 1.3× (layout_harness.dart); and
// what the pointer does: a stroke held at the right edge scrolls right while the page grows and the stroke follows
// without a gap (the view goes out with its sideways part), the left edge the same way, growing to the left never
// moves a viewer's lines, a viewer pans a grown page sideways with one finger and "Follow" brings them back.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/live/room/annotation/draw_input_prefs.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_controller.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_edge_scroll.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_format.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_protocol.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_stage.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Widget _dark(Widget child) => Theme(data: ThemeData.dark(), child: ColoredBox(color: const Color(0xFF101828), child: child));

/// A presenter and a viewer on a continuous board, wired together.
(BoardController, BoardController) _pair() {
  late BoardController teacher, viewer;
  teacher = BoardController(localIdentity: 'teacher_1', autoFlush: false, idPrefix: 't1', isHost: (i) => i == 'teacher_1');
  viewer = BoardController(localIdentity: 'student_2', autoFlush: false, idPrefix: 's2', isHost: (i) => i == 'teacher_1');
  teacher.send = (topic, bytes, reliable, {to}) async => viewer.receive(topic, bytes, sender: 'teacher_1');
  teacher.startPresenting(background: BoardBackground.grid, format: BoardFormat.continuous);
  return (teacher, viewer);
}

/// A lesson written across a page grown to the right: the column, then a worked example beside it.
void _grownLesson(BoardController t) {
  final id = t.createText(0.06, 0.004, boxWidth: 0.8)!;
  t.updateText(id, text: 'قانون نيوتن الثاني: F = m · a');
  t.endEdit(id);
  t.beginInk(0.1, 0.02);
  for (var i = 1; i <= 40; i++) {
    t.moveInk(0.1 + i * 0.04, 0.02 + (i % 2) * 0.002);
  }
  t.endInk();
  t.beginShape(BoardShapeKind.rect, 1.15, 0.008);
  t.moveShape(1.8, 0.03);
  t.endShape();
  t.select(null);
  t.flush();
}

Future<Rect> _pump(WidgetTester t, BoardController c, {Size size = const Size(390, 844), String presenter = ''}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(layoutHost(
      _dark(WhiteboardRoomView(controller: c, presenterName: presenter, onStop: c.isLocalPresenting ? () {} : null, keyboard: false)),
      scale: 1));
  await t.pump(const Duration(milliseconds: 100));
  return t.getRect(find.byType(WhiteboardStage));
}

/// Holds a mouse stroke from the stage's middle to [edge] (moved there in 10 steps), then still for [frames].
Future<TestGesture> _holdAt(WidgetTester t, Rect stage, Offset edge, {int frames = 60, int pointer = 61}) async {
  final from = Offset(stage.center.dx, stage.top + stage.height * 0.3);
  final g = await t.startGesture(from, kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton, pointer: pointer);
  for (var i = 1; i <= 10; i++) {
    await t.pump(const Duration(milliseconds: 16));
    await g.moveTo(Offset.lerp(from, edge, i / 10)!);
  }
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
  return g;
}

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
    DrawInputPrefs.stylusOnly.value = false;
    DrawInputPrefs.offered = true;
  });

  testWidgets('a grown board: presenter with the dock, a viewer scrolled sideways with Follow and both rails', (t) async {
    await expectNoLayoutErrors(t, () {
      final (teacher, viewer) = _pair();
      _grownLesson(teacher);
      teacher.reportViewport(const BoardViewportPos(0, 0.04, left: 0.9, width: 1));
      teacher.flushViewport();
      return _dark(Column(children: [
        Expanded(child: WhiteboardRoomView(controller: teacher, onStop: () {}, onOptions: () {}, keyboard: false)),
        Expanded(child: WhiteboardRoomView(controller: viewer, presenterName: 'د. منى السيد', keyboard: false)),
      ]));
    }, act: (t) async {
      // The viewer drags the page back to its left edge: they stop following.
      final stages = find.byType(WhiteboardStage);
      final r = t.getRect(stages.last);
      final g = await t.startGesture(r.center, kind: PointerDeviceKind.touch, pointer: 71);
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 16));
        await g.moveBy(const Offset(60, 0));
      }
      await g.up();
      await t.pump();
    });
  });

  testWidgets('a stroke held at the right edge scrolls right; the page grows and the stroke follows without a gap', (t) async {
    final (teacher, viewer) = _pair();
    addTearDown(teacher.dispose);
    addTearDown(viewer.dispose);
    teacher.setTool(BoardTool.pen);
    final stage = await _pump(t, teacher);
    expect(find.byKey(const ValueKey('board.side_rail')), findsNothing, reason: 'the plain column has no sideways rail');
    final edge = Offset(stage.right - 6, stage.top + stage.height * 0.3);
    final g = await _holdAt(t, stage, edge);
    final ink = teacher.scene.items.whereType<BoardInk>().single;
    final pw = stage.width; // the column fills a phone
    final view = teacher.localViewport!;
    expect(view.left * pw, greaterThan(400), reason: 'the view went right (px)');
    expect(ink.points.last.x, greaterThan(1.9), reason: 'the stroke reached the grown paper');
    // Every step of the stroke in page pixels: never back, never a gap.
    final steps = [for (var i = 1; i < ink.points.length; i++) (ink.points[i].x - ink.points[i - 1].x) * pw];
    for (final (i, s) in steps.indexed) {
      expect(s, greaterThan(-0.5), reason: 'never back (step $i)');
      expect(s, lessThan(45), reason: 'no gap (step $i)');
    }
    for (final s in steps.skip(steps.length - 30)) {
      expect(s, inInclusiveRange(1, kBoardEdgeMaxSpeed / 60 + 2), reason: 'held: one frame of the edge speed per point');
    }
    expect((ink.points.last.x - view.left) * pw, closeTo(stage.width - 6, 24), reason: 'the stroke ends under the pointer');
    expect(find.byKey(const ValueKey('board.side_rail')), findsOneWidget);
    // Held long enough, it stops at the widest page.
    for (var i = 0; i < 120; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(teacher.localViewport!.right, closeTo(1 + kBoardSideMax, 1e-3));
    await g.up();
    await t.pump();
    expect(teacher.isWide, isTrue);
    teacher.flushViewport();
    expect(viewer.presenterViewport.value!.left, closeTo(teacher.localViewport!.left, 1e-4), reason: 'viewers learn where');
    expect(viewer.scene.items.whereType<BoardInk>().single.points.last.x, closeTo(ink.points.last.x, 1e-5));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the left edge grows the page to the left; what was drawn keeps its place on the page', (t) async {
    final (teacher, _) = _pair();
    addTearDown(teacher.dispose);
    teacher.beginInk(0.3, 0.01);
    teacher.moveInk(0.5, 0.012);
    teacher.endInk();
    final before = List.of(teacher.scene.items.whereType<BoardInk>().single.points);
    teacher.setTool(BoardTool.pen);
    final stage = await _pump(t, teacher);
    final g = await _holdAt(t, stage, Offset(stage.left + 6, stage.top + stage.height * 0.3), frames: 40);
    await g.up();
    await t.pump();
    final view = teacher.localViewport!;
    expect(view.left, lessThan(-0.5), reason: 'the view went left of the column');
    final strokes = teacher.scene.items.whereType<BoardInk>().toList();
    expect(strokes.first.points, before, reason: 'the first line was not rewritten');
    expect(strokes.last.points.last.x, lessThan(-0.5));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('growing to the left never moves a viewer\'s lines on screen', (t) async {
    final (teacher, viewer) = _pair();
    addTearDown(teacher.dispose);
    addTearDown(viewer.dispose);
    final id = teacher.createText(0.1, 0.004, boxWidth: 0.6)!;
    teacher.updateText(id, text: 'First line');
    teacher.endEdit(id);
    teacher.flush();
    await _pump(t, viewer, size: const Size(1440, 900), presenter: 'Dr. Mona');
    final text = find.byKey(ValueKey('board.text.$id'));
    final at = t.getRect(text);
    // The presenter writes left of the column (on their phone) — the viewer's page grows to the left.
    teacher.beginInk(0.05, 0.02);
    teacher.moveInk(-0.35, 0.025);
    teacher.endInk();
    teacher.flush();
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 50));
    expect(viewer.scene.items.whereType<BoardInk>().single.points.last.x, -0.35);
    final now = t.getRect(text);
    for (final (a, b) in [(now.left, at.left), (now.top, at.top), (now.right, at.right), (now.bottom, at.bottom)]) {
      expect(a, closeTo(b, 0.01), reason: 'the line stayed where it was');
    }
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a viewer pans a grown page sideways with one finger; Follow brings them back to the presenter', (t) async {
    final (teacher, viewer) = _pair();
    addTearDown(teacher.dispose);
    addTearDown(viewer.dispose);
    _grownLesson(teacher);
    teacher.reportViewport(const BoardViewportPos(0, 0.04, left: 0.9, width: 1));
    teacher.flushViewport();
    final stage = await _pump(t, viewer, presenter: 'Dr. Mona');
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    final pageAt = t.getRect(find.byType(WhiteboardStage));
    expect(find.byKey(const ValueKey('board.side_rail')), findsOneWidget);
    expect(find.byKey(const ValueKey('board.side_rail.presenter')), findsOneWidget);
    expect(find.byKey(const ValueKey('board.follow')), findsNothing, reason: 'following');
    // Where the rectangle beside the column is drawn: in view, since the viewer follows the presenter to x 0.9.
    final g = await t.startGesture(stage.center, pointer: 81);
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 16));
      await g.moveBy(const Offset(50, 0));
    }
    await g.up();
    await t.pump();
    expect(find.byKey(const ValueKey('board.follow')), findsOneWidget, reason: 'they moved away');
    expect(viewer.scene.itemCount, 3, reason: 'a viewer\'s finger draws nothing');
    final thumb = t.getRect(find.byKey(const ValueKey('board.side_rail.thumb')));
    final mark = t.getRect(find.byKey(const ValueKey('board.side_rail.presenter')));
    expect(thumb.center.dx, lessThan(mark.center.dx), reason: 'the view is left of the presenter now');
    await t.tap(find.byKey(const ValueKey('board.follow')));
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    final thumb2 = t.getRect(find.byKey(const ValueKey('board.side_rail.thumb')));
    final mark2 = t.getRect(find.byKey(const ValueKey('board.side_rail.presenter')));
    expect(thumb2.center.dx, closeTo(mark2.center.dx, 3), reason: 'back with the presenter');
    expect(pageAt, t.getRect(find.byType(WhiteboardStage)));
    await t.pumpWidget(const SizedBox());
  });
}
