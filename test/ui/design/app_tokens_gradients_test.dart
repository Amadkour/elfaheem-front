// The design-system tokens (elevation, type scale) and the gradient pieces (AppGradientSurface, AppAccentStrip,
// AppGradientText): no layout error at 320 / 1400 wide, ar + en, textScaler 1.3; the strip follows the reading
// direction; the elevation scale grows with the level; high contrast drops the gradient text shader.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_gradients.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';

void main() {
  setUp(() => AppConfig.lang = 'ar');

  testWidgets('gradient pieces and every type role lay out at every size', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Builder(
        builder: (context) => ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
          const AppAccentStrip(),
          AppSpace.gapMd,
          AppGradientSurface(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('لوحة التحكم الرئيسية للمنصة التعليمية', style: AppType.headline(context)),
              const AppGradientText('12,480'),
            ]),
          ),
          AppSpace.gapMd,
          for (final s in [
            AppType.display(context),
            AppType.headline(context),
            AppType.pageTitle(context),
            AppType.section(context),
            AppType.body(context),
            AppType.bodyStrong(context),
            AppType.row(context),
            AppType.label(context),
            AppType.meta(context),
            AppType.overline(context),
            AppType.figure(context),
            AppType.figureLarge(context),
          ])
            Text('الإيرادات الشهرية Monthly revenue 1,234', style: s),
        ]),
      ),
    );
  });

  testWidgets('the strip runs start → end in both directions', (tester) async {
    late LinearGradient ltr, rtl;
    for (final dir in [TextDirection.ltr, TextDirection.rtl]) {
      await tester.pumpWidget(layoutHost(Directionality(
        textDirection: dir,
        child: Builder(builder: (context) {
          final g = AppGradients.strip(context);
          if (dir == TextDirection.ltr) {
            ltr = g;
          } else {
            rtl = g;
          }
          return const SizedBox();
        }),
      )));
    }
    expect(ltr.begin, AlignmentDirectional.centerStart);
    expect(rtl.begin, AlignmentDirectional.centerStart);
    expect(ltr.colors.length, 3);
  });

  testWidgets('elevation grows with the level; level 0 is flat', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(layoutHost(Builder(builder: (context) {
      ctx = context;
      return const SizedBox();
    })));
    expect(AppElevation.of(ctx, 0), isEmpty);
    double blur(int level) => AppElevation.of(ctx, level).first.blurRadius;
    expect(blur(2) < blur(3), isTrue);
    expect(blur(3) < blur(4), isTrue);
    expect(AppElevation.border(ctx, 2), isNull, reason: 'light mode lifts with the shadow only');
  });

  testWidgets('high contrast: the gradient figure is plain primary text', (tester) async {
    await tester.pumpWidget(layoutHost(const MediaQuery(
      data: MediaQueryData(highContrast: true),
      child: AppGradientText('42'),
    )));
    expect(find.byType(ShaderMask), findsNothing);
    expect(find.text('42'), findsOneWidget);
  });
}
