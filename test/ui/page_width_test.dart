// The page-width roles (D-304): AppWidth's widths and gutters, the BasePage web card measured against the room the
// page really has (no more fixed 650 px between 900 and 1100), AppWidthBox, and no layout errors at any size.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_responsive.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _probe = Key('probe');

Future<double> _cardWidth(WidgetTester tester, double window, Widget page) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(window, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(layoutHost(page, scale: 1, scaffold: false));
  await tester.pump();
  return tester.getSize(find.byKey(_probe)).width;
}

Widget _page({AppWidth? width, double? maxWith}) => BasePage(
      useWebCard: true,
      width: width,
      maxWith: maxWith,
      enableFooterWidget: false,
      child: const SizedBox.expand(key: _probe),
    );

void main() {
  test('roles: form < reading < content < wide < full', () {
    expect(AppWidth.form.max, 600);
    expect(AppWidth.reading.max, Breakpoints.contentMax);
    expect(AppWidth.content.max, 1120);
    expect(AppWidth.wide.max, 1440);
    expect(AppWidth.full.max, double.infinity);
  });

  test('inside: the role max, never wider than the room between the gutters', () {
    expect(AppWidth.reading.inside(1920), 860);
    expect(AppWidth.wide.inside(1700), 1440);
    expect(AppWidth.content.inside(1000), 1000 - 2 * 24);
    expect(AppWidth.form.inside(390), 390 - 2 * 16);
    expect(AppWidth.full.inside(1920), 1920 - 2 * 24);
    expect(AppWidth.content.inside(1920, max: 760), 760, reason: 'a page that still names its own width keeps it');
  });

  testWidgets('BasePage card: a 1000 px window gets the room, not a fixed 650', (tester) async {
    expect(await _cardWidth(tester, 1000, _page(width: AppWidth.wide)), 1000 - 2 * 24);
    expect(await _cardWidth(tester, 1050, _page(maxWith: 1360)), 1050 - 2 * 24);
  });

  testWidgets('BasePage card: each role caps at its width on a wide window', (tester) async {
    expect(await _cardWidth(tester, 1920, _page(width: AppWidth.reading)), 860);
    expect(await _cardWidth(tester, 1920, _page(width: AppWidth.wide)), 1440);
    expect(await _cardWidth(tester, 1920, _page()), 1120, reason: 'no role and no maxWith = content');
    expect(await _cardWidth(tester, 1920, _page(maxWith: 900)), 900);
  });

  testWidgets('BasePage card: a phone keeps the whole width', (tester) async {
    expect(await _cardWidth(tester, 390, _page(width: AppWidth.form)), 390);
  });

  testWidgets('AppWidthBox: role width with gutters, centred', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(layoutHost(
        const AppWidthBox(width: AppWidth.reading, child: SizedBox(key: _probe, height: 40)),
        scale: 1));
    final r = tester.getRect(find.byKey(_probe));
    expect(r.width, 860);
    expect(r.center.dx, 960);
  });

  testWidgets('no layout errors: BasePage roles and AppWidthBox at every size', (tester) async {
    for (final role in AppWidth.values) {
      await expectNoLayoutErrors(
        tester,
        () => BasePage(
          useWebCard: true,
          width: role,
          enableFooterWidget: false,
          child: ListView(children: [
            AppWidthBox(width: role, child: const Text('A row of text that wraps on a phone at 1.3 text scale')),
          ]),
        ),
        scaffold: false,
      );
    }
  });
}
