// The paper cards of the kit (AppCard / AppActionCard / AppStatTile / AppListSkeleton / AppSkeletonBox) at 320 / 1400
// wide, ar + en, textScaler 1.3 — plus the colour rules of the Warm Editorial badges: every tone's ink reads at AA
// on its own tint in light and dark mode, and a solid count bubble's ink reads on its fill.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_contrast.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';

const _longAr = 'إدارة شؤون الطلاب والدراسات العليا والبحث العلمي بكلية الهندسة وكل الأقسام';
const _longEn = 'Office of Student Affairs, Graduate Studies and Scientific Research of the whole faculty';

Widget _gallery() => Builder(builder: (context) {
      final c = context.colors;
      return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        AppCard(child: Text(_longAr, style: AppType.body(context))),
        AppSpace.gapSm,
        AppCard(onTap: () {}, onLongPress: () {}, margin: const EdgeInsets.all(AppSpace.xs), padding: EdgeInsets.zero, child: const SizedBox(height: 40)),
        AppSpace.gapSm,
        AppActionCard(icon: Icons.people_alt_rounded, title: _longEn, subtitle: _longAr, badge: 120, onTap: () {}),
        AppSpace.gapSm,
        AppActionCard(icon: Icons.event_rounded, title: 'Timetable', color: c.warning, trailing: AppStatusBadge(label: _longAr, tone: AppTone.warning)),
        AppSpace.gapSm,
        const AppActionCard(icon: Icons.inbox_rounded, title: 'Plain'),
        AppSpace.gapSm,
        AppGrid(padding: EdgeInsets.zero, children: [
          AppStatTile(icon: Icons.school_rounded, label: _longAr, value: 1240000, onTap: () {}),
          AppStatTile(icon: Icons.check_circle_rounded, label: _longEn, value: '98.6%', color: c.success),
          AppStatTile(icon: Icons.error_rounded, label: 'Failed', value: 0, color: c.danger),
          const AppStatTile(icon: Icons.bolt_rounded, label: 'Events', value: null),
        ]),
        AppSpace.gapSm,
        const AppListSkeleton(items: 3),
        const AppListSkeleton(items: 2, withAvatar: false, padding: EdgeInsets.zero),
        const AppSkeletonBox(width: 80),
      ]);
    });

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() => AppConfig.lang = 'en');

  testWidgets('cards, action cards, stat tiles and skeletons lay out', (tester) async {
    await expectNoLayoutErrors(tester, _gallery);
  });

  testWidgets('an action card and a stat tile fire their taps; a stat tile reads "label: value"', (tester) async {
    final h = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(layoutHost(Column(children: [
      AppActionCard(icon: Icons.people_alt_rounded, title: 'People', onTap: () => taps++),
      AppStatTile(icon: Icons.school_rounded, label: 'Students', value: 1240, onTap: () => taps++),
    ])));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('People'));
    await tester.tap(find.bySemanticsLabel('Students: 1240'));
    expect(taps, 2);
    h.dispose();
  });

  testWidgets('a resting card is the white card on one soft shadow with a near-invisible edge (D-632)', (tester) async {
    await tester.pumpWidget(layoutHost(const AppCard(child: Text('x'))));
    await tester.pump(const Duration(milliseconds: 100));
    final m = tester.widget<Material>(find.descendant(of: find.byType(AppCard), matching: find.byType(Material)).first);
    final c = tester.element(find.text('x')).colors;
    expect(m.color, c.cardBg);
    expect(m.elevation, 0);
    expect((m.shape as RoundedRectangleBorder).side.color, c.cardEdge);
    final lift = tester.widget<AppLift>(find.descendant(of: find.byType(AppCard), matching: find.byType(AppLift)));
    expect(lift.radius ?? AppRadius.cardAll, AppRadius.cardAll);
    expect(c.cardShadow, isNotEmpty);
    expect((m.shape as RoundedRectangleBorder).borderRadius, AppRadius.cardAll);
  });

  group('badge ink reads at AA on its tint', () {
    for (final dark in [false, true]) {
      testWidgets(dark ? 'dark' : 'light', (tester) async {
        final theme = ThemeConfigProvider(api: ApiClient())..isDark = dark;
        late BuildContext ctx;
        await tester.pumpWidget(ThemeConfigScope(
          provider: theme,
          child: MaterialApp(
            theme: theme.materialTheme(dark: dark),
            home: Builder(builder: (context) {
              ctx = context;
              return const SizedBox();
            }),
          ),
        ));
        for (final tone in AppTone.values) {
          final tint = appToneTint(ctx, tone);
          final ink = appToneInk(ctx, tone);
          expect(tint.a, 1, reason: '$tone tint is opaque');
          expect(contrastRatio(ink, tint), greaterThanOrEqualTo(kWcagAaText), reason: '$tone dark=$dark');
          final fill = appToneColor(ctx, tone);
          expect(contrastRatio(appInkOnFill(ctx, fill), fill), greaterThanOrEqualTo(3), reason: '$tone bubble dark=$dark');
        }
        await tester.pumpWidget(const SizedBox());
        theme.dispose();
      });
    }
  });
}
