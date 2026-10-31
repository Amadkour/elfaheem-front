// Drawing on the whiteboard in full view (D-108, round 7): the page alone fills the room (no dock under it), and
// whoever may draw keeps drawing — a tap on the page is a dot of ink and never reaches the room's "show the bars"
// tap, a stroke stays whole; a viewer's tap still reaches the room. The tool dock comes with the room's bars
// (WhiteboardDock in LiveFocusChrome's bottom, with the Controls chip, no overflow at 320×640 and 1400×900, Arabic
// and English, text 1.3×), and the pen keeps the tool picked there after the bars hide.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_controller.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_protocol.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_stage.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_view.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_focus_chrome.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

(BoardController, BoardController) _pair() {
  late BoardController teacher, viewer;
  teacher = BoardController(localIdentity: 'teacher_1', autoFlush: false, idPrefix: 't1', isHost: (i) => i == 'teacher_1');
  viewer = BoardController(localIdentity: 'student_2', autoFlush: false, idPrefix: 's2', isHost: (i) => i == 'teacher_1');
  teacher.send = (topic, bytes, reliable, {to}) async => viewer.receive(topic, bytes, sender: 'teacher_1');
  teacher.startPresenting(background: BoardBackground.grid);
  teacher.setTool(BoardTool.pen);
  teacher.setDrawMode(true);
  return (teacher, viewer);
}

/// The room's stage in full view: a tap on it would show the bars.
Future<void> _pump(WidgetTester t, BoardController c, {required VoidCallback onRoomTap}) async {
  t.view.physicalSize = const Size(1280, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(layoutHost(
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (_) => onRoomTap(),
        child: WhiteboardRoomView(controller: c, showTopBar: false, fullView: true, keyboard: false),
      ),
      scale: 1));
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('the presenter in full view: no dock under the page, a tap is a dot, a stroke stays whole', (t) async {
    final (teacher, _) = _pair();
    var room = 0;
    await _pump(t, teacher, onRoomTap: () => room++);
    expect(find.byKey(const ValueKey('board.toolbar')), findsNothing, reason: 'the dock comes with the bars');
    final page = t.getRect(find.byType(WhiteboardStage));
    final before = teacher.scene.items.length;
    await t.tapAt(page.center);
    await t.pump(const Duration(milliseconds: 200));
    expect(teacher.scene.items.length, before + 1, reason: 'a dot of ink');
    expect(room, 0, reason: 'the tap was ink, not "show the bars"');
    final g = await t.startGesture(page.center + const Offset(-120, -60));
    for (var i = 1; i <= 8; i++) {
      await g.moveBy(const Offset(18, 6));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await t.pump(const Duration(milliseconds: 200));
    expect(teacher.scene.items.length, before + 2, reason: 'one whole stroke');
    expect(room, 0);
  });

  testWidgets('a viewer in full view: the tap reaches the room (the bars)', (t) async {
    final (_, viewer) = _pair();
    var room = 0;
    await _pump(t, viewer, onRoomTap: () => room++);
    await t.tapAt(t.getRect(find.byType(WhiteboardStage)).center);
    await t.pump(const Duration(milliseconds: 200));
    expect(room, 1);
    expect(viewer.scene.items, isEmpty);
  });

  testWidgets('the dock with the bars: a tool picked there stays when the bars hide', (t) async {
    final (teacher, _) = _pair();
    Widget chrome(bool shown) => LiveFocusChrome(
          shown: shown,
          handle: true,
          onHandle: () {},
          top: const SizedBox(height: 48),
          bottom: Column(mainAxisSize: MainAxisSize.min, children: [
            WhiteboardDock(controller: teacher),
            const SizedBox(height: 64),
          ]),
        );
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(layoutHost(chrome(true), scale: 1));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('board.tool.highlighter')).hitTestable());
    await t.pump();
    expect(teacher.tool, BoardTool.highlighter);
    await t.pumpWidget(layoutHost(chrome(false), scale: 1));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('board.tool.highlighter')).hitTestable(), findsNothing);
    expect(teacher.tool, BoardTool.highlighter);
    expect(teacher.drawMode, isTrue);
  });

  testWidgets('layout: the dock over the bar in full view, shown, no overflow', (t) async {
    final (teacher, _) = _pair();
    await expectNoLayoutErrors(
      t,
      () => Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: Color(0xFFF6F7FB)),
        LiveFocusChrome(
          shown: true,
          handle: true,
          onHandle: () {},
          top: const SizedBox(height: 48),
          bottom: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: WhiteboardDock(controller: teacher)),
            Container(height: 64, margin: const EdgeInsets.symmetric(horizontal: 12), color: const Color(0xFF1B2233)),
          ]),
        ),
      ]),
      act: (t) async {
        final dock = t.getRect(find.byKey(const ValueKey('board.toolbar')));
        expect(dock.bottom <= t.view.physicalSize.height - 64, isTrue, reason: 'above the bar: $dock');
      },
    );
  });
}
