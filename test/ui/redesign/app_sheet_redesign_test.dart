// The sheets (KIT_SPEC §5.8, §7.2): the three modes, the M14 style on phones, the filler, the native-only blur.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';
import 'redesign_harness.dart';

Widget _opener(AppSheetMode mode) => Builder(
      builder: (context) => TextButton(
        onPressed: () => showAppSheet<void>(
          context,
          (ctx) => AppSheetContent(title: 'Filters', children: [
            for (var i = 0; i < 4; i++) ListTile(title: Text('Row $i')),
          ]),
          mode: mode,
        ),
        child: const Text('open'),
      ),
    );

void main() {
  tearDown(() => debugAppSheetForceWeb = null);

  for (final mode in [AppSheetMode.auto, AppSheetMode.side, AppSheetMode.dialog]) {
    testWidgets('layout: ${mode.name}', (tester) async {
      await expectNoLayoutErrors(tester, () => _opener(mode), act: (t) => t.tap(find.text('open')));
    });
  }

  Future<void> openPhone(WidgetTester tester, {bool reduce = false}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(kitHost(_opener(AppSheetMode.auto), reduce: reduce));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the phone sheet uses appPeekSheetStyle and has the filler', (tester) async {
    debugAppSheetForceWeb = false;
    await openPhone(tester);
    final route = ModalRoute.of(tester.element(find.text('Filters')));
    expect(route, isA<ModalBottomSheetRoute<void>>());
    final style = (route! as ModalBottomSheetRoute<void>).sheetAnimationStyle;
    expect(style?.curve, isA<PeekCurve>());
    expect(style?.duration, AppMotionSpec.sheetIn);
    expect(find.byKey(const ValueKey('app.sheet.peek_filler')), findsOneWidget);
    expect(find.byKey(const ValueKey('app.sheet.blur')), findsOneWidget, reason: 'native: the page blurs');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('no BackdropFilter on the web', (tester) async {
    debugAppSheetForceWeb = true;
    await openPhone(tester);
    expect(find.byKey(const ValueKey('app.sheet.blur')), findsNothing);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('no blur and no motion under Reduce motion', (tester) async {
    debugAppSheetForceWeb = false;
    await openPhone(tester, reduce: true);
    expect(find.byKey(const ValueKey('app.sheet.blur')), findsNothing);
    final route = ModalRoute.of(tester.element(find.text('Filters'))) as ModalBottomSheetRoute<void>;
    expect(route.sheetAnimationStyle?.duration, Duration.zero);
  });

  testWidgets('the side panel is flush to the end edge, full height', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(kitHost(_opener(AppSheetMode.side), reduce: true));
    await tester.tap(find.text('open'));
    await tester.pump();
    final r = tester.getRect(find.byKey(const ValueKey('app.side_sheet.panel')));
    expect(r.left, 0, reason: 'RTL: the end edge is the left');
    expect(r.width, 520);
    expect(r.height, 900);
  });
}
