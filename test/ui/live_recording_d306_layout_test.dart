// D-306: the new plain-values pieces at 320×640 and 1400×900, Arabic and English, text 1.3× (layout_harness.dart):
// the Record sheet's "What the recording holds" (video and audio only), full view's turn hint, the touch scrollbar
// (idle and held, down and across), and a fixed page in full view with the hint over it.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/live/meeting_recording_sheets.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/annotation/draw_input_prefs.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_controller.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_protocol.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_scrollbar.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_stage.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Widget _dark(Widget child) => Theme(data: ThemeData.dark(), child: ColoredBox(color: const Color(0xFF101828), child: child));

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
    DrawInputPrefs.stylusOnly.value = false;
  });

  testWidgets('What the recording holds: video and audio only', (t) async {
    await expectNoLayoutErrors(t, () => const SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(children: [
            RecordingIncludes(),
            SizedBox(height: 12),
            RecordingIncludes(audioOnly: true),
          ]),
        ), act: (t) async => expect(find.byKey(const ValueKey('record_setup.includes')), findsNWidgets(2)));
  });

  testWidgets('the turn hint, wide and upright pages', (t) async {
    await expectNoLayoutErrors(t, () => _dark(const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              BoardTurnHint(),
              SizedBox(height: 12),
              BoardTurnHint(portraitPage: true),
            ]),
          ),
        )));
  });

  testWidgets('the touch scrollbar: down and across, idle and held, with its grip', (t) async {
    await expectNoLayoutErrors(t, () {
      Widget rail(bool vertical, bool grabbed) => SizedBox(
            width: vertical ? BoardRailLook.touch.box : 300,
            height: vertical ? 300 : BoardRailLook.touch.box,
            child: BoardScrollRail(
                vertical: vertical, lo: 0, hi: 3, start: 0.4, length: 0.5, grabbed: grabbed, look: BoardRailLook.touch),
          );
      return _dark(Center(
        child: Wrap(spacing: 16, runSpacing: 16, children: [rail(true, false), rail(true, true), rail(false, false), rail(false, true)]),
      ));
    }, act: (t) async => expect(find.byKey(const ValueKey('board.rail.grip')), findsWidgets));
  });

  testWidgets('a fixed page in full view: no gutter, the page as wide as the screen allows', (t) async {
    final c = BoardController(localIdentity: 'teacher_1', autoFlush: false, idPrefix: 't1', isHost: (i) => i == 'teacher_1');
    addTearDown(c.dispose);
    c.startPresenting(background: BoardBackground.white, format: BoardFormat.landscape);
    await expectNoLayoutErrors(t, () => _dark(WhiteboardRoomView(controller: c, fullView: true, showTopBar: false, keyboard: false)));
    t.view.physicalSize = const Size(844, 390);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(layoutHost(_dark(WhiteboardRoomView(controller: c, fullView: true, showTopBar: false, keyboard: false)), scale: 1));
    await t.pump();
    final stage = t.getRect(find.byType(WhiteboardStage));
    expect(stage.width, 844, reason: 'full view: the page has every pixel of the width (no side gutter)');
  });
}
