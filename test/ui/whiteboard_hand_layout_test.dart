// The whiteboard's hand tool and edge auto-scroll (D-096): the dock with the hand (both layouts, every tool on the
// phone's first row) at 320×640 and 1400×900, Arabic and English, text 1.3× (layout_harness.dart); and what the
// pointer does — the hand (mouse, finger), Space held, the middle mouse button and the select tool on empty paper move
// the view without drawing, a viewer's mouse scrolls too (and stops following), dragging a selected item still moves
// it, and a stroke held near the bottom scrolls a continuous page while the stroke follows without a gap (the
// presenter's view goes out).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/live/room/annotation/draw_input_prefs.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_controller.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_edge_scroll.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_format.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_painter.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_protocol.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_stage.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_toolbar.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Widget _dark(Widget child) => Theme(data: ThemeData.dark(), child: ColoredBox(color: const Color(0xFF101828), child: child));

/// A presenter and a viewer on a board of [format], wired together.
(BoardController, BoardController) _pair(BoardFormat format) {
  late BoardController teacher, viewer;
  teacher = BoardController(localIdentity: 'teacher_1', autoFlush: false, idPrefix: 't1', isHost: (i) => i == 'teacher_1');
  viewer = BoardController(localIdentity: 'student_2', autoFlush: false, idPrefix: 's2', isHost: (i) => i == 'teacher_1');
  teacher.send = (topic, bytes, reliable, {to}) async => viewer.receive(topic, bytes, sender: 'teacher_1');
  teacher.startPresenting(background: BoardBackground.lined, format: format);
  return (teacher, viewer);
}

Future<Rect> _pump(WidgetTester t, BoardController c, {String presenter = ''}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(layoutHost(
      _dark(WhiteboardRoomView(controller: c, presenterName: presenter, onStop: c.isLocalPresenting ? () {} : null, keyboard: false)),
      scale: 1));
  await t.pump(const Duration(milliseconds: 100));
  return t.getRect(find.byType(WhiteboardStage));
}

/// Drags [from] by [by] in [steps] moves of 16 ms with a [kind] pointer.
Future<void> _drag(WidgetTester t, Offset from, Offset by,
    {PointerDeviceKind kind = PointerDeviceKind.touch, int buttons = kPrimaryButton, int steps = 8, int pointer = 21}) async {
  final g = await t.startGesture(from, kind: kind, buttons: buttons, pointer: pointer);
  for (var i = 0; i < steps; i++) {
    await t.pump(const Duration(milliseconds: 16));
    await g.moveBy(by / steps.toDouble());
  }
  await g.up();
  await t.pump();
}

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
    DrawInputPrefs.stylusOnly.value = false;
    DrawInputPrefs.offered = true;
  });

  testWidgets('the dock with the hand: both layouts, hand selected, never overflows', (t) async {
    final colors = boardInkColors(BoardBackground.white);
    Widget dock({bool? wide, BoardTool tool = BoardTool.hand, Color? color, BoardPanel panel = BoardPanel.none}) => WhiteboardToolbar(
          tool: tool,
          color: color ?? colors.first,
          colors: colors,
          thickness: 1,
          fontStep: 1,
          canUndo: true,
          wide: wide,
          panel: panel,
          onTool: (_) {},
          onColor: (_) {},
          onThickness: (_) {},
          onFontStep: (_) {},
          onUndo: () {},
          onRedo: () {},
          onPanel: (_) {},
        );
    await expectNoLayoutErrors(
        t,
        () => _dark(SingleChildScrollView(
              child: Column(children: [
                dock(),
                dock(wide: false),
                dock(wide: false, tool: BoardTool.select, color: colors[4]),
                dock(wide: false, panel: BoardPanel.shapes),
                dock(wide: true),
              ]),
            )));
  });

  testWidgets('on a 390 px phone every page tool is on the first row, the hand among them, and labelled', (t) async {
    final (teacher, _) = _pair(BoardFormat.continuous);
    addTearDown(teacher.dispose);
    teacher.setTool(BoardTool.hand);
    await _pump(t, teacher);
    final dock = t.getRect(find.byKey(const ValueKey('board.toolbar')));
    for (final k in ['select', 'hand', 'pen', 'highlighter', 'text', 'eraser', 'laser']) {
      final r = t.getRect(find.byKey(ValueKey('board.tool.$k')));
      expect(r.left >= dock.left - 0.5 && r.right <= dock.right + 0.5, isTrue, reason: '$k is fully on screen ($r in $dock)');
    }
    final hand = t.getRect(find.byKey(const ValueKey('board.tool.hand')));
    final pen = t.getRect(find.byKey(const ValueKey('board.tool.pen')));
    expect(hand.center.dy, closeTo(pen.center.dy, 0.5), reason: 'the hand sits with the drawing tools');
    expect(find.bySemanticsLabel(RegExp('Hand: move the page')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('board.tool.pen')));
    await t.pump();
    expect(teacher.tool, BoardTool.pen);
    await t.tap(find.byKey(const ValueKey('board.tool.hand')));
    await t.pump();
    expect(teacher.tool, BoardTool.hand);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the hand: a finger and the mouse move the page and draw nothing; the view goes out', (t) async {
    final (teacher, viewer) = _pair(BoardFormat.continuous);
    addTearDown(teacher.dispose);
    addTearDown(viewer.dispose);
    teacher.setTool(BoardTool.hand);
    final stage = await _pump(t, teacher);
    final top0 = teacher.localViewport?.top ?? 0;
    await _drag(t, stage.center, const Offset(0, -240));
    await t.pump();
    expect(teacher.scene.itemCount, 0);
    final top1 = teacher.localViewport!.top;
    expect(top1, greaterThan(top0), reason: 'a finger scrolled the page down');
    await _drag(t, stage.center, const Offset(0, -240), kind: PointerDeviceKind.mouse);
    await t.pump();
    expect(teacher.scene.itemCount, 0);
    expect(teacher.localViewport!.top, greaterThan(top1), reason: 'so did the mouse');
    teacher.flushViewport();
    expect(viewer.presenterViewport.value?.top, closeTo(teacher.localViewport!.top, 1e-4), reason: 'viewers follow it');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('select: a drag on empty paper moves the view, a drag on an item moves the item', (t) async {
    final (teacher, _) = _pair(BoardFormat.continuous);
    addTearDown(teacher.dispose);
    teacher.beginShape(BoardShapeKind.rect, 0.3, 0.004);
    teacher.moveShape(0.7, 0.012);
    teacher.endShape();
    teacher.setTool(BoardTool.select);
    final stage = await _pump(t, teacher);
    final shape = teacher.scene.items.whereType<BoardShape>().single;
    // The rectangle's left side, on screen.
    final page = t.getRect(find.byType(WhiteboardStage));
    final colW = page.width; // the column fills a phone
    final edge = Offset(page.left + (page.width - colW) / 2 + 0.3 * colW, page.top + 0.008 * colW * kBoardContinuousLength);
    await _drag(t, edge, const Offset(40, 0), kind: PointerDeviceKind.mouse);
    final moved = teacher.scene.item(shape.id) as BoardShape;
    expect(moved.x1, greaterThan(shape.x1 + 0.05), reason: 'the item moved');
    expect(teacher.localViewport?.top ?? 0, 0, reason: 'the view did not');
    await _drag(t, stage.center + const Offset(0, 120), const Offset(0, -200));
    expect(teacher.localViewport!.top, greaterThan(0), reason: 'empty paper: the view moved');
    expect(teacher.scene.itemCount, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Space held and the middle mouse button move the view with the pen on', (t) async {
    final (teacher, _) = _pair(BoardFormat.continuous);
    addTearDown(teacher.dispose);
    teacher.setTool(BoardTool.pen);
    final stage = await _pump(t, teacher);
    await t.sendKeyDownEvent(LogicalKeyboardKey.space);
    await t.pump();
    await _drag(t, stage.center, const Offset(0, -200), kind: PointerDeviceKind.mouse);
    await t.sendKeyUpEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(teacher.scene.itemCount, 0);
    final top1 = teacher.localViewport!.top;
    expect(top1, greaterThan(0));
    await _drag(t, stage.center, const Offset(0, -200), kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
    expect(teacher.scene.itemCount, 0);
    expect(teacher.localViewport!.top, greaterThan(top1));
    // Space let go: the pen draws again.
    await _drag(t, stage.center, const Offset(80, 20), kind: PointerDeviceKind.mouse);
    expect(teacher.scene.itemCount, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a viewer drags the page with the mouse: it scrolls and "Follow" appears', (t) async {
    final (teacher, viewer) = _pair(BoardFormat.continuous);
    addTearDown(teacher.dispose);
    addTearDown(viewer.dispose);
    teacher.sendSnapshot();
    teacher.reportViewport(const BoardViewportPos(0, 0.04));
    teacher.flushViewport();
    final stage = await _pump(t, viewer, presenter: 'Dr. Mona');
    expect(find.byKey(const ValueKey('board.follow')), findsNothing);
    await _drag(t, stage.center, const Offset(0, -240), kind: PointerDeviceKind.mouse);
    expect(find.byKey(const ValueKey('board.follow')), findsOneWidget);
    expect(viewer.scene.itemCount, 0);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a stroke held near the bottom scrolls the page down; the stroke follows without a gap', (t) async {
    final (teacher, viewer) = _pair(BoardFormat.continuous);
    addTearDown(teacher.dispose);
    addTearDown(viewer.dispose);
    teacher.setTool(BoardTool.pen);
    final stage = await _pump(t, teacher);
    final g = await t.startGesture(stage.center, kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton, pointer: 31);
    final target = Offset(stage.center.dx, stage.bottom - 6);
    for (var i = 1; i <= 10; i++) {
      await t.pump(const Duration(milliseconds: 16));
      await g.moveTo(Offset.lerp(stage.center, target, i / 10)!);
    }
    final topAtEdge = teacher.localViewport?.top ?? 0;
    // Held still at the edge for a second: the view keeps going down.
    for (var i = 0; i < 60; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    final ink = teacher.scene.items.whereType<BoardInk>().single;
    final pageH = stage.width * kBoardContinuousLength; // the column fills a phone
    final scrolled = (teacher.localViewport!.top - topAtEdge) * pageH;
    expect(scrolled, greaterThan(400), reason: 'the page came up under the pen (px)');
    // Every step of the stroke in page pixels: the approach is the pointer's own ~35 px moves, the hold one frame of
    // the edge speed each — never a gap, never back.
    final steps = [for (var i = 1; i < ink.points.length; i++) (ink.points[i].y - ink.points[i - 1].y) * pageH];
    for (final (i, s) in steps.indexed) {
      expect(s, greaterThan(-0.5), reason: 'the stroke never jumps back (step $i)');
      expect(s, lessThan(45), reason: 'no gap (step $i)');
    }
    final hold = steps.skip(steps.length - 40);
    for (final s in hold) {
      expect(s, inInclusiveRange(1, kBoardEdgeMaxSpeed / 60 + 2), reason: 'held: one frame of the edge speed per point');
    }
    final ys = [for (final p in ink.points) p.y];
    final lastOnScreen = (ys.last - teacher.localViewport!.top) * pageH;
    expect(lastOnScreen, closeTo(stage.height - 6, 24), reason: 'the stroke ends under the pointer');
    await g.up();
    await t.pump();
    expect(teacher.scene.items.whereType<BoardInk>().single.open, isFalse);
    teacher.flushViewport();
    expect(viewer.presenterViewport.value?.top, closeTo(teacher.localViewport!.top, 1e-4), reason: 'the auto-scroll went out');
    // Let go: no more scrolling.
    final settled = teacher.localViewport!.top;
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(teacher.localViewport!.top, settled);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a stroke written along the bottom does not scroll', (t) async {
    final (teacher, _) = _pair(BoardFormat.continuous);
    addTearDown(teacher.dispose);
    teacher.setTool(BoardTool.pen);
    final stage = await _pump(t, teacher);
    final start = Offset(stage.left + 30, stage.bottom - 20);
    final g = await t.startGesture(start, kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton, pointer: 41);
    for (var i = 1; i <= 20; i++) {
      await t.pump(const Duration(milliseconds: 16));
      await g.moveTo(start + Offset(i * 15.0, (i % 2) * 6.0));
    }
    await g.up();
    await t.pump();
    expect(teacher.localViewport?.top ?? 0, 0);
    expect(teacher.scene.itemCount, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a zoomed portrait page: the hand moves it around, a stroke held at the edge pans it', (t) async {
    final (teacher, _) = _pair(BoardFormat.portrait);
    addTearDown(teacher.dispose);
    teacher.setTool(BoardTool.pen);
    final stage = await _pump(t, teacher);
    // Pinch to zoom in (this device only).
    final a = await t.startGesture(stage.center - const Offset(20, 0), pointer: 51);
    final b = await t.startGesture(stage.center + const Offset(20, 0), pointer: 52);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 16));
      await a.moveBy(const Offset(-20, 0));
      await b.moveBy(const Offset(20, 0));
    }
    await a.up();
    await b.up();
    await t.pump();
    expect(find.byKey(const ValueKey('board.zoom_reset')), findsOneWidget);
    expect(teacher.scene.itemCount, 0);

    // The pen: a stroke to the bottom-right corner, held — the page slides, the stroke keeps going.
    final g = await t.startGesture(stage.center, kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton, pointer: 53);
    final corner = stage.bottomRight - const Offset(6, 6);
    for (var i = 1; i <= 8; i++) {
      await t.pump(const Duration(milliseconds: 16));
      await g.moveTo(Offset.lerp(stage.center, corner, i / 8)!);
    }
    final atEdge = teacher.scene.items.whereType<BoardInk>().single.points.last;
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    final held = teacher.scene.items.whereType<BoardInk>().single.points.last;
    expect(held.x, greaterThan(atEdge.x + 0.01));
    expect(held.y, greaterThan(atEdge.y + 0.01));
    await g.up();
    await t.pump();

    // The hand drags it back; nothing is drawn.
    teacher.setTool(BoardTool.hand);
    await t.pump();
    await _drag(t, stage.center, const Offset(120, 160), kind: PointerDeviceKind.mouse);
    expect(teacher.scene.itemCount, 1);
    await t.pumpWidget(const SizedBox());
  });
}
