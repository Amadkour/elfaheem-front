// The live whiteboard's widgets (D-087) at 320×640 and 1400×900, Arabic and English, text 1.3×: the tool dock (one
// row / two rows, the shapes and style panels, the hand on — D-096), the bar over the page (presenter / viewer / host
// viewer), the page with content and a selection, the text editor, the Board sheet and the share sheet's Whiteboard
// tab. The hand and edge auto-scroll themselves: whiteboard_hand_layout_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_controller.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_painter.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_protocol.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_toolbar.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_view.dart';
import 'package:flutter_education_app/features/live/room/widgets/share_options_sheet.dart';
import 'package:flutter_education_app/features/live/room/widgets/share_presets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

BoardController _board({BoardBackground bg = BoardBackground.grid, bool content = true}) {
  final c = BoardController(localIdentity: 'teacher_1', autoFlush: false, isHost: (id) => id == 'teacher_1');
  c.startPresenting(background: bg);
  if (content) {
    c.beginInk(0.1, 0.1);
    c.moveInk(0.3, 0.4);
    c.endInk();
    c.beginShape(BoardShapeKind.arrow, 0.4, 0.4);
    c.moveShape(0.7, 0.2);
    c.endShape();
    final id = c.createText(0.5, 0.6)!;
    c.updateText(id, text: 'قانون نيوتن الثاني: القوة = الكتلة × التسارع');
    c.endEdit(id);
    c.setTool(BoardTool.select);
    c.select(id);
  }
  return c;
}

Widget _dark(Widget child) => Theme(data: ThemeData.dark(), child: ColoredBox(color: const Color(0xFF101828), child: child));

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  testWidgets('the dock: every tool, both layouts, both panels', (t) async {
    final colors = boardInkColors(BoardBackground.white);
    Widget dock({bool? wide, BoardPanel panel = BoardPanel.none, bool text = false, BoardTool tool = BoardTool.pen}) =>
        WhiteboardToolbar(
          tool: tool,
          color: colors.first,
          colors: colors,
          thickness: 1,
          fontStep: 2,
          textStyle: text,
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
                dock(wide: false, panel: BoardPanel.shapes, tool: BoardTool.arrow),
                dock(wide: false, panel: BoardPanel.style, text: true, tool: BoardTool.text),
                dock(wide: true, panel: BoardPanel.shapes),
                dock(wide: true, text: true),
                dock(wide: false, tool: BoardTool.hand),
                dock(wide: true, tool: BoardTool.hand),
              ]),
            )));
  });

  testWidgets('the bar over the page: presenter, viewer, host viewer', (t) async {
    await expectNoLayoutErrors(
        t,
        () => _dark(Column(children: [
              WhiteboardTopBar(presenting: true, pageIndex: 1, pageCount: 3, onPrevious: () {}, onNext: () {}, onAddPage: () {}, onOptions: () {}, onStop: () {}),
              const WhiteboardTopBar(presenting: false, pageIndex: 0, pageCount: 1, presenterName: 'Dr. Mona Elsayed Abdelrahman', canDraw: true),
              WhiteboardTopBar(presenting: false, pageIndex: 4, pageCount: 12, presenterName: 'سارة أحمد', onStop: () {}),
            ])));
  });

  testWidgets('the room view: presenter with a selection, a viewer', (t) async {
    final presenter = _board();
    final viewer = BoardController(localIdentity: 'student_2', autoFlush: false, isHost: (id) => id == 'teacher_1');
    presenter.send = (topic, bytes, reliable, {to}) async => viewer.receive(topic, bytes, sender: 'teacher_1');
    presenter.sendSnapshot();
    addTearDown(presenter.dispose);
    addTearDown(viewer.dispose);
    await expectNoLayoutErrors(
        t,
        () => _dark(Column(children: [
              Expanded(child: WhiteboardRoomView(controller: presenter, onStop: () {}, onOptions: () {}, keyboard: false)),
              Expanded(child: WhiteboardRoomView(controller: viewer, presenterName: 'Dr. Mona', keyboard: false)),
            ])));
  });

  testWidgets('typing: the text tool opens a box where the page is tapped and sends what is typed', (t) async {
    final c = _board(content: false);
    addTearDown(c.dispose);
    c.setTool(BoardTool.text);
    await t.pumpWidget(layoutHost(_dark(WhiteboardRoomView(controller: c, onStop: () {}, keyboard: false)), scale: 1));
    await t.pump();
    final stage = t.getRect(find.byType(WhiteboardRoomView));
    await t.tapAt(stage.center);
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('board.editor.field')), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('board.editor.field')), 'مرحبا');
    await t.pump();
    final tx = c.scene.items.whereType<BoardText>().single;
    expect(tx.text, 'مرحبا');
    // A tap elsewhere ends the box: it stays, as one undo step.
    await t.tapAt(stage.topLeft + Offset(stage.width * 0.2, stage.height * 0.35));
    await t.pump();
    expect(find.byKey(const ValueKey('board.editor.field')), findsNothing);
    expect(c.canUndo, isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('a pen drag draws; a second finger turns it into a pinch that zooms this view only', (t) async {
    final c = _board(content: false);
    addTearDown(c.dispose);
    c.setTool(BoardTool.pen);
    await t.pumpWidget(layoutHost(_dark(WhiteboardRoomView(controller: c, onStop: () {}, keyboard: false)), scale: 1));
    await t.pump();
    final page = t.getRect(find.byType(WhiteboardRoomView));
    final a = page.center - const Offset(60, 0);
    await t.dragFrom(a, const Offset(120, 30));
    await t.pump();
    expect(c.scene.items.whereType<BoardInk>().length, 1);

    final f1 = await t.startGesture(page.center - const Offset(30, 0), pointer: 7);
    await t.pump();
    final f2 = await t.startGesture(page.center + const Offset(30, 0), pointer: 8);
    await t.pump();
    await f1.moveBy(const Offset(-60, 0));
    await f2.moveBy(const Offset(60, 0));
    await t.pump();
    await f1.up();
    await f2.up();
    await t.pump();
    expect(c.scene.items.whereType<BoardInk>().length, 1, reason: 'the first finger of a pinch leaves no stroke');
    expect(find.byKey(const ValueKey('board.zoom_reset')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('board.zoom_reset')));
    await t.pump();
    expect(find.byKey(const ValueKey('board.zoom_reset')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('the Board sheet and the share sheet\'s Whiteboard tab', (t) async {
    await expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
              child: Column(children: [
                const WhiteboardOptionsLayout(background: BoardBackground.lined, pageIndex: 0, pageCount: 2, isHost: true, allowStudents: true),
                const WhiteboardOptionsLayout(background: BoardBackground.white, pageIndex: 0, pageCount: 1, pageEmpty: true),
                ShareOptionsLayout(
                  quality: ShareQuality.detail,
                  deviceAudio: true,
                  deviceAudioSupported: true,
                  whiteboard: true,
                  tab: ShareTab.whiteboard,
                  onTab: (_) {},
                  onBackground: (_) {},
                  onStartWhiteboard: () {},
                ),
                const ShareOptionsLayout(
                    quality: ShareQuality.detail, deviceAudio: false, deviceAudioSupported: false, whiteboard: true, qualityChoice: false),
                const ShareOptionsLayout(
                    quality: ShareQuality.detail, deviceAudio: false, deviceAudioSupported: false, whiteboard: true, screenAvailable: false, web: true),
              ]),
            ));
  });

  testWidgets('the share sheet hands back the whiteboard and its background', (t) async {
    t.view.physicalSize = const Size(1000, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    ShareChoice? picked;
    await t.pumpWidget(layoutHost(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showShareOptionsSheet(context, deviceAudioSupported: true, whiteboard: true),
            child: const Text('open'),
          ),
        ),
        scale: 1));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('share.tab.whiteboard')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('board.bg.blackboard')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('share.start_whiteboard')));
    await t.pumpAndSettle();
    expect(picked?.isWhiteboard, isTrue);
    expect(picked?.whiteboard, BoardBackground.blackboard);
  });
}
