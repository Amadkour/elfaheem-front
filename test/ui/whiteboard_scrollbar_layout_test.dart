// The continuous whiteboard's rails as scrollbars (D-109): the rails (idle and grabbed, down and across) and a grown
// board whose thumb is held, at 320×640 and 1400×900, Arabic and English, text 1.3× (layout_harness.dart); and what
// the pointer does: a long press grabs the vertical thumb and a drag moves the view (no stroke, the presenter's view
// goes out), a finger that moves at once still draws, the mouse drags without waiting, a tap on the track moves a
// page, and a viewer who drags the sideways thumb stops following.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/annotation/draw_input_prefs.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_controller.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_format.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_protocol.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_stage.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Widget _dark(Widget child) => Theme(data: ThemeData.dark(), child: ColoredBox(color: const Color(0xFF101828), child: child));

(BoardController, BoardController) _pair() {
  late BoardController teacher, viewer;
  teacher = BoardController(localIdentity: 'teacher_1', autoFlush: false, idPrefix: 't1', isHost: (i) => i == 'teacher_1');
  viewer = BoardController(localIdentity: 'student_2', autoFlush: false, idPrefix: 's2', isHost: (i) => i == 'teacher_1');
  teacher.send = (topic, bytes, reliable, {to}) async => viewer.receive(topic, bytes, sender: 'teacher_1');
  teacher.startPresenting(background: BoardBackground.grid, format: BoardFormat.continuous);
  return (teacher, viewer);
}

/// A long lesson (down to 0.2 of the page) with a worked example right of the column.
void _lesson(BoardController t) {
  t.beginInk(0.1, 0.02);
  t.moveInk(0.6, 0.2);
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

final _vThumb = find.byKey(const ValueKey('board.rail.thumb'));
final _hThumb = find.byKey(const ValueKey('board.side_rail.thumb'));

Future<void> _frames(WidgetTester t, int n) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
    DrawInputPrefs.stylusOnly.value = false;
    DrawInputPrefs.offered = true;
  });

  testWidgets('the rails: down and across, idle and grabbed, with the presenter\'s mark', (t) async {
    await expectNoLayoutErrors(t, () {
      Widget rail(bool vertical, bool grabbed) => SizedBox(
            width: vertical ? BoardScrollRail.thickness : 300,
            height: vertical ? 300 : BoardScrollRail.thickness,
            child: BoardScrollRail(
                vertical: vertical, lo: -0.5, hi: 2, start: 0.3, length: 0.6, presenter: (1.2, 0.5), grabbed: grabbed),
          );
      return _dark(Center(
        child: Wrap(spacing: 16, runSpacing: 16, children: [
          rail(true, false),
          rail(true, true),
          rail(false, false),
          rail(false, true),
          // Degenerate: nothing to scroll, a zero-length track.
          const SizedBox(width: 16, height: 0, child: BoardScrollRail(vertical: true, lo: 0, hi: 1, start: 0, length: 0.5)),
          const SizedBox(width: 16, height: 80, child: BoardScrollRail(vertical: true, lo: 0, hi: 1, start: 0, length: 1)),
        ]),
      ));
    });
  });

  testWidgets('a grown board with its vertical thumb held (presenter) and the sideways one held (viewer)', (t) async {
    await expectNoLayoutErrors(t, () {
      final (teacher, viewer) = _pair();
      _lesson(teacher);
      teacher.reportViewport(const BoardViewportPos(0, 0.04, left: 0.9, width: 1));
      teacher.flushViewport();
      return _dark(Column(children: [
        Expanded(child: WhiteboardRoomView(controller: teacher, onStop: () {}, onOptions: () {}, keyboard: false)),
        Expanded(child: WhiteboardRoomView(controller: viewer, presenterName: 'د. منى السيد', keyboard: false)),
      ]));
    }, act: (t) async {
      final g = await t.startGesture(t.getCenter(_vThumb.first), kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
      await _frames(t, 3);
      await g.moveBy(const Offset(0, 40));
      await _frames(t, 10);
      await g.up();
      await t.pump();
    });
  });

  testWidgets('long press on the vertical thumb grabs it; a drag moves the view; nothing is drawn', (t) async {
    final (teacher, viewer) = _pair();
    addTearDown(teacher.dispose);
    addTearDown(viewer.dispose);
    _lesson(teacher);
    teacher.setTool(BoardTool.pen);
    await _pump(t, teacher);
    final items = teacher.scene.itemCount;
    final before = teacher.localViewport!;
    final idle = t.getRect(_vThumb);
    final g = await t.startGesture(idle.center, pointer: 91);
    await t.pump(const Duration(milliseconds: 300));
    expect(teacher.scene.items.whereType<BoardInk>().length, 1, reason: 'held back: no stroke while it may still grab');
    await t.pump(const Duration(milliseconds: 300)); // past the long press
    await _frames(t, 12); // the grow animation
    final held = t.getRect(_vThumb);
    expect(held.width, greaterThan(idle.width + 3), reason: 'the grabbed thumb grows');
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, 20));
      await t.pump(const Duration(milliseconds: 16));
    }
    await t.pump();
    final after = teacher.localViewport!;
    expect(after.top, greaterThan(before.top + 1e-3), reason: 'the view went down the page');
    expect(t.getRect(_vThumb).center.dy, closeTo(held.center.dy + 200, 6), reason: 'the thumb stays under the finger');
    await g.up();
    await _frames(t, 12);
    expect(t.getRect(_vThumb).width, closeTo(idle.width, 0.5), reason: 'let go: thin again');
    expect(teacher.scene.itemCount, items, reason: 'the grab drew nothing');
    teacher.flushViewport();
    expect(viewer.presenterViewport.value!.top, closeTo(after.top, 1e-4), reason: 'the presenter\'s view went out');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a finger that moves at once on the thumb still draws', (t) async {
    final (teacher, _) = _pair();
    addTearDown(teacher.dispose);
    teacher.setTool(BoardTool.pen);
    await _pump(t, teacher);
    final at = t.getRect(_vThumb).center;
    final before = teacher.localViewport!;
    final g = await t.startGesture(at, pointer: 92);
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 16));
      await g.moveBy(const Offset(-12, 6));
    }
    await g.up();
    await t.pump(const Duration(milliseconds: 100));
    final ink = teacher.scene.items.whereType<BoardInk>().toList();
    expect(ink, hasLength(1), reason: 'the stroke that started on the rail');
    expect(ink.single.points.length, greaterThan(3));
    expect(teacher.localViewport!.top, closeTo(before.top, 1e-6), reason: 'the view did not move');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the mouse drags the thumb without a long press; a click on the track moves a page', (t) async {
    final (teacher, _) = _pair();
    addTearDown(teacher.dispose);
    _lesson(teacher);
    teacher.setTool(BoardTool.pen);
    await _pump(t, teacher, size: const Size(1440, 900));
    final idle = t.getRect(_vThumb);
    final g = await t.startGesture(idle.center, kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
    await t.pump();
    await g.moveBy(const Offset(0, 60));
    await t.pump();
    await g.up();
    await _frames(t, 12);
    final dragged = teacher.localViewport!;
    expect(dragged.top, greaterThan(0.001));
    expect(teacher.scene.items.whereType<BoardInk>().length, 1, reason: 'no new stroke');
    // A click on the track below the thumb: a page down (90 % of what one screen shows).
    final thumb = t.getRect(_vThumb);
    final track = Offset(thumb.center.dx, thumb.bottom + 60);
    await t.tapAt(track, kind: PointerDeviceKind.mouse);
    await t.pump();
    final paged = teacher.localViewport!;
    expect(paged.top - dragged.top, closeTo(dragged.height * 0.9, 0.02 * dragged.height));
    expect(teacher.scene.items.whereType<BoardInk>().length, 1, reason: 'the click drew nothing');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a viewer drags the sideways thumb: the view moves across and they stop following', (t) async {
    final (teacher, viewer) = _pair();
    addTearDown(teacher.dispose);
    addTearDown(viewer.dispose);
    _lesson(teacher);
    teacher.reportViewport(const BoardViewportPos(0, 0.04, left: 0.9, width: 1));
    teacher.flushViewport();
    await _pump(t, viewer, presenter: 'Dr. Mona');
    await _frames(t, 20);
    expect(find.byKey(const ValueKey('board.follow')), findsNothing);
    final idle = t.getRect(_hThumb);
    final g = await t.startGesture(idle.center, pointer: 93);
    await t.pump(const Duration(milliseconds: 600));
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(-20, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await _frames(t, 12);
    expect(t.getRect(_hThumb).center.dx, closeTo(idle.center.dx - 120, 6));
    expect(find.byKey(const ValueKey('board.follow')), findsOneWidget, reason: 'they moved away');
    expect(viewer.scene.itemCount, 2, reason: 'a viewer draws nothing');
    await t.pumpWidget(const SizedBox());
  });
}
