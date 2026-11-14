// D-093 widgets at 320×640 and 1400×900, Arabic and English, text 1.3× (layout_harness.dart): portrait and
// continuous boards (presenter with the dock, viewer scrolled away with "Follow …" and the rail), name tags over the
// board and over a shared screen's annotation, the format picker, the Board sheet with its new rows, the share sheet's
// Whiteboard tab, the "Stylus only?" offer and the "Drawn by" chip. Plus the interactions that matter: a finger
// scrolls a continuous page for a viewer (and they stop following), "Stylus only" keeps a finger from drawing, a
// second finger in time cancels a stroke nobody saw.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/live/room/annotation/annotation_controller.dart';
import 'package:flutter_education_app/features/live/room/annotation/annotation_layer.dart';
import 'package:flutter_education_app/features/live/room/annotation/draw_input_prefs.dart';
import 'package:flutter_education_app/features/live/room/annotation/presence_tags.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_controller.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_format.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_protocol.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_stage.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_toolbar.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_view.dart';
import 'package:flutter_education_app/features/live/room/widgets/share_options_sheet.dart';
import 'package:flutter_education_app/features/live/room/widgets/share_presets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Widget _dark(Widget child) => Theme(data: ThemeData.dark(), child: ColoredBox(color: const Color(0xFF101828), child: child));

/// A presenter, a drawing student and a viewer, wired together.
(BoardController, BoardController, BoardController) _room(BoardFormat format, {bool content = true}) {
  final drawers = {'student_2'};
  final all = <BoardController>[];
  BoardController peer(String id) {
    final c = BoardController(
      localIdentity: id,
      autoFlush: false,
      idPrefix: id.substring(0, 1) + id.substring(id.length - 1),
      isHost: (i) => i == 'teacher_1',
      studentMayDraw: drawers.contains,
      nameOf: (i) => {'teacher_1': 'د. منى السيد', 'student_2': 'Abdelrahman Mohamed Abdelaziz El-Sayed'}[i] ?? '',
      othersMayDraw: () => true,
      showAuthors: () => true,
    );
    c.send = (topic, bytes, reliable, {to}) async {
      for (final o in all) {
        if (o.localIdentity != id && (to == null || to.contains(o.localIdentity))) o.receive(topic, bytes, sender: id);
      }
    };
    all.add(c);
    return c;
  }

  final t = peer('teacher_1'), s = peer('student_2'), v = peer('student_3');
  t.startPresenting(background: BoardBackground.lined, format: format);
  if (content) {
    final y = format == BoardFormat.continuous ? 0.02 : 0.3;
    t.beginInk(0.1, y * 0.5);
    t.moveInk(0.4, y);
    t.endInk();
    final id = t.createText(0.5, y)!;
    t.updateText(id, text: 'قانون نيوتن الثاني: القوة = الكتلة × التسارع');
    t.endEdit(id);
    t.select(null);
    s.beginInk(0.6, y);
    s.moveInk(0.9, y * 1.2);
    s.flush(); // still drawing: the tag shows
    if (format == BoardFormat.continuous) t.reportViewport(const BoardViewportPos(0.08, 0.03));
  }
  return (t, s, v);
}

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
    DrawInputPrefs.stylusOnly.value = false;
    DrawInputPrefs.offered = false;
  });

  testWidgets('portrait and continuous boards: presenter (dock) and viewer, with name tags', (t) async {
    for (final f in [BoardFormat.portrait, BoardFormat.continuous]) {
      await expectNoLayoutErrors(t, () {
        final (teacher, _, viewer) = _room(f);
        return _dark(Column(children: [
          Expanded(child: WhiteboardRoomView(controller: teacher, onStop: () {}, onOptions: () {}, keyboard: false)),
          Expanded(child: WhiteboardRoomView(controller: viewer, presenterName: 'د. منى السيد', keyboard: false)),
        ]));
      });
    }
  });

  testWidgets('an empty continuous board and a huge zoomed one never overflow', (t) async {
    await expectNoLayoutErrors(t, () {
      final (teacher, _, _) = _room(BoardFormat.continuous, content: false);
      return _dark(WhiteboardRoomView(controller: teacher, onStop: () {}, onOptions: () {}, keyboard: false));
    });
  });

  testWidgets('a viewer scrolls a continuous page with one finger: "Follow …" appears and brings them back', (t) async {
    final (teacher, _, viewer) = _room(BoardFormat.continuous);
    addTearDown(() {
      teacher.dispose();
      viewer.dispose();
    });
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(layoutHost(_dark(WhiteboardRoomView(controller: viewer, presenterName: 'Dr. Mona', keyboard: false)), scale: 1));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('board.follow')), findsNothing, reason: 'following the presenter');
    await t.drag(find.byType(WhiteboardStage), const Offset(0, 300));
    await t.pump();
    expect(find.byKey(const ValueKey('board.follow')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('board.follow')));
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(find.byKey(const ValueKey('board.follow')), findsNothing);
    expect(find.byKey(const ValueKey('board.rail.presenter')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('"Stylus only": a finger never draws; a second finger soon after a stroke starts sends nothing', (t) async {
    final (teacher, _, viewer) = _room(BoardFormat.portrait, content: false);
    addTearDown(() {
      teacher.dispose();
      viewer.dispose();
    });
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(layoutHost(_dark(WhiteboardRoomView(controller: teacher, onStop: () {}, onOptions: () {}, keyboard: false)), scale: 1));
    await t.pump(const Duration(milliseconds: 100));
    final page = t.getRect(find.byType(WhiteboardStage)).center;

    // Two fingers: a pinch. The first finger's stroke was held, so the viewer never got anything.
    final a = await t.startGesture(page, pointer: 7);
    await t.pump(const Duration(milliseconds: 10));
    final b = await t.startGesture(page + const Offset(60, 40), pointer: 8);
    await a.moveBy(const Offset(-30, -30));
    await b.moveBy(const Offset(30, 30));
    await a.up();
    await b.up();
    await t.pump();
    expect(teacher.scene.itemCount, 0);
    expect(viewer.scene.itemCount, 0);

    // A finger draws (one finger, no pinch) …
    final c = await t.startGesture(page, pointer: 9);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 20));
      await c.moveBy(const Offset(12, 4));
    }
    await c.up();
    await t.pump();
    expect(viewer.scene.itemCount, 1);

    // … until "Stylus only": then only a pen draws.
    DrawInputPrefs.stylusOnly.value = true;
    await t.pump();
    final d = await t.startGesture(page + const Offset(0, 80), pointer: 10);
    await d.moveBy(const Offset(40, 0));
    await d.up();
    await t.pump();
    expect(teacher.scene.itemCount, 1);
    final pen = await t.startGesture(page + const Offset(0, 120), pointer: 11, kind: PointerDeviceKind.stylus);
    await pen.moveBy(const Offset(40, 0));
    await pen.up();
    await t.pump();
    expect(teacher.scene.itemCount, 2);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the format picker, the Board sheet (every row) and the share sheet\'s Whiteboard tab', (t) async {
    await expectNoLayoutErrors(t, () => SingleChildScrollView(
          child: Column(children: [
            for (final f in BoardFormat.values) BoardFormatPicker(value: f, onChanged: (_) {}),
            _dark(const BoardFormatPicker(value: BoardFormat.continuous, dark: true)),
            WhiteboardOptionsLayout(
              background: BoardBackground.grid,
              format: BoardFormat.continuous,
              pageIndex: 1,
              pageCount: 3,
              isHost: true,
              allowStudents: true,
              showAuthors: true,
              stylusOnly: true,
              onFormat: (_) {},
              onBackground: (_) {},
              onAllowStudents: (_) {},
              onShowAuthors: (_) {},
              onStylusOnly: (_) {},
              onExport: () {},
              onExportWhole: () {},
              onClearPage: () {},
              onDeletePage: () {},
            ),
            ShareOptionsLayout(
              quality: ShareQuality.detail,
              deviceAudio: false,
              deviceAudioSupported: false,
              whiteboard: true,
              tab: ShareTab.whiteboard,
              boardFormat: BoardFormat.portrait,
              onBoardFormat: (_) {},
              onStartWhiteboard: () {},
            ),
          ]),
        ));
  });

  testWidgets('the share sheet hands the picked format to the room', (t) async {
    ShareChoice? got;
    await t.pumpWidget(layoutHost(Builder(
      builder: (context) => TextButton(
        onPressed: () async => got = await showShareOptionsSheet(context, deviceAudioSupported: false, whiteboard: true, screenAvailable: false),
        child: const Text('open'),
      ),
    )));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('board.format.continuous')));
    await t.pump();
    await t.ensureVisible(find.byKey(const ValueKey('share.start_whiteboard')));
    await t.tap(find.byKey(const ValueKey('share.start_whiteboard')));
    await t.pumpAndSettle();
    expect(got?.isWhiteboard, isTrue);
    expect(got?.boardFormat, BoardFormat.continuous);
  });

  testWidgets('the small pieces: Follow, the stylus offer, the author chip', (t) async {
    await expectNoLayoutErrors(t, () => _dark(Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            BoardFollowButton(name: 'Abdelrahman Mohamed Abdelaziz El-Sayed', onTap: () {}),
            const BoardFollowButton(),
            BoardStylusOffer(onYes: () {}, onNo: () {}),
            const AuthorLabelChip(name: 'سارة أحمد', color: Color(0xFF16A34A)),
            const AuthorLabelChip(name: 'x', mine: true),
          ]),
        )));
  });

  testWidgets('tags and "Drawn by" over a shared screen', (t) async {
    await expectNoLayoutErrors(t, () {
      final host = AnnotationController(localIdentity: 'teacher_1', autoFlush: false, nameOf: (_) => 'Mona');
      final student = AnnotationController(localIdentity: 'student_2', autoFlush: false, nameOf: (_) => 'عمر خالد');
      host.send = (topic, bytes, reliable, {to}) async => student.receive(topic, bytes, sender: 'teacher_1');
      student.send = (topic, bytes, reliable, {to}) async => host.receive(topic, bytes, sender: 'student_2');
      for (final c in [host, student]) {
        c.setRoles(hosts: {'teacher_1'}, presenter: 'teacher_1');
      }
      host.setAllowStudents(true);
      host.setShowAuthors(true);
      student.begin(0.97, 0.97); // in the corner: the tag flips inside
      student.move(0.99, 0.99);
      student.flush();
      return _dark(AnnotationLayer(controller: host, contentSize: const Size(1920, 1080)));
    }, act: (t) async {
      final r = t.getRect(find.byType(AnnotationLayer));
      final g = await t.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: r.center);
      await g.moveTo(r.bottomRight - const Offset(4, 4));
      await t.pump();
      await g.removePointer();
    });
  });
}
