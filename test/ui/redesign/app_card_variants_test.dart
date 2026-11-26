// AppCard variants (KIT_SPEC §5.3, §7.2).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';

Widget _cards() => AppAreaScope(
      area: AppArea.quran,
      child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        for (final v in AppCardVariant.values)
          for (final tap in [false, true]) ...[
            AppCard(
              variant: v,
              onTap: tap ? () {} : null,
              title: 'Continue where you stopped, a long title that wraps',
              action: AppButton.ghost(label: 'All', onPressed: () {}, size: AppButtonSize.sm),
              child: const Text('Exponential functions · lesson 4'),
            ),
            AppSpace.gapSm,
          ],
        const AppCard(highlight: true, child: Text('The one main card')),
        const AppCard(padding: EdgeInsets.zero, child: Text('old call: own padding')),
      ]),
    );

void main() {
  testWidgets('4 variants × tappable / not, with title + action, lay out', (tester) async {
    await expectNoLayoutErrors(tester, _cards);
  });

  testWidgets('the radius is 20 at 320 and 24 at 1400', (tester) async {
    for (final (size, r) in [(const Size(320, 640), 20.0), (const Size(1400, 900), 24.0)]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpWidget(layoutHost(const AppCard(variant: AppCardVariant.flat, child: Text('x'))));
      final clip = tester.widget<ClipRRect>(find.descendant(of: find.byType(AppCard), matching: find.byType(ClipRRect)).first);
      expect((clip.borderRadius as BorderRadius).topLeft.x, r);
    }
    tester.view.reset();
  });
}
