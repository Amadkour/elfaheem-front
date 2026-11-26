// D-622 / D-630: a role home's hero is a BLOCK (AppBlock(hero: true)) — the ONE deep forest block for every role,
// cream ink at 7:1 (muted at AA) — with the name in the editorial display face, the actions as translucent cream
// plates (ChromeIconButton inside a ChromeBar) and no gradient anywhere in it (D-649: the block itself is now the static forest → emerald gradient, every
// ink checked on both stops). The hero parts (tag, day ribbon,
// figure) draw in the block's ink too. Plus: no layout error at 320 / 1400, ar + en, textScaler 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_contrast.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/design/chrome_button.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

List<Widget> _chips() => [
      for (final (icon, label) in [(Icons.event_rounded, 'calendar'), (Icons.chat_bubble_outline_rounded, 'chat'), (Icons.notifications_none_rounded, 'bell')])
        ChromeIconButton(icon: icon, label: label, onTap: () {}, badge: label == 'bell' ? 3 : 0),
    ];

List<HomeAgendaItem> _day() => const [
      HomeAgendaItem(start: '9:00', end: '10:30', title: 'Algebra', startMin: 540, endMin: 630),
      HomeAgendaItem(start: '11:00', end: '12:00', title: 'Physics lab', startMin: 660, endMin: 720, live: true),
      HomeAgendaItem(start: '16:00', end: '17:30', title: 'Office hours', startMin: 960, endMin: 1050),
    ];

void main() {
  setUp(() => AppConfig.lang = 'ar');

  test('every role wears the one forest hero', () {
    for (final r in [null, '', 'student', 'parent', 'teacher', 'admin', 'super-admin', 'developer', 'org-admin', 'org-staff']) {
      expect(HomeHeader.toneForRole(r), AppBlockTone.forest, reason: '$r');
    }
  });

  test('the forest is deep: cream ink at 7:1 and the muted ink at AA, in both modes, for any preset', () {
    for (final dark in [false, true]) {
      final p = ThemeConfigProvider(api: ApiClient())..isDark = dark;
      expect(contrastRatio(p.heroInk, p.blockForest), greaterThanOrEqualTo(7), reason: 'dark $dark');
      expect(contrastRatio(p.heroInkMuted, p.blockForest), greaterThanOrEqualTo(kWcagAaText), reason: 'dark $dark');
      expect(contrastRatio(p.heroInkFaint, p.blockForest), greaterThanOrEqualTo(kWcagAaText), reason: 'dark $dark');
    }
    // a light primary_dark is deepened until the cream reads at 7:1
    final f = ThemeConfigProvider.deriveForest(const Color(0xFF6FA8DC), const Color(0xFFFBF7F0));
    expect(contrastRatio(const Color(0xFFFBF7F0), f), greaterThanOrEqualTo(7));
  });

  testWidgets('the header is the forest block: cream ink, the editorial name, glass chips, no gradient', (tester) async {
    AppConfig.lang = 'en';
    await tester.pumpWidget(layoutHost(HomeHeader(name: 'Sara Ali', subtitle: '2 sessions today', actions: _chips())));
    await tester.pump();
    expect(find.byType(AppBlock), findsOneWidget);
    expect(find.byType(AppMeshSurface), findsNothing, reason: 'a hero is a block, not the brand gradient');
    expect(find.byType(ChromeBar), findsOneWidget, reason: 'the chips are translucent cream plates on the forest');
    final c = tester.element(find.byType(AppBlock)).colors;
    final block = tester.widget<Material>(find.descendant(of: find.byType(AppBlock), matching: find.byType(Material)).first);
    // D-649: the forest block paints the brand layer's forest → emerald gradient (its first stop the forest)
    expect(block.color, Colors.transparent);
    final layer = BrandLayer.of(c);
    expect(layer.forest.first, c.blockForest);
    for (final stop in layer.forest) {
      expect(contrastRatio(c.heroInk, stop), greaterThanOrEqualTo(7), reason: '$stop');
    }

    final name = tester.widget<Text>(find.text('Sara Ali')).style!;
    expect(name.color, c.heroInk);
    expect(name.fontFamily, AppFonts.editorial);
    expect(name.fontSize, (32 * AppFonts.editorialScale('en')).roundToDouble(), reason: 'the display role');
    final sub = tester.widget<Text>(find.text('2 sessions today')).style!;
    expect(sub.fontFamily, isNot(AppFonts.editorialFamily), reason: 'the day line is the UI sans');
    for (final stop in BrandLayer.of(c).forest) {
      expect(contrastRatio(sub.color!, stop), greaterThanOrEqualTo(kWcagAaText));
    }

    for (final chip in find.byType(ChromeIconButton).evaluate()) {
      final size = (chip.renderObject! as RenderBox).size;
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    final chip = tester.widget<Material>(find.descendant(of: find.byType(ChromeIconButton).first, matching: find.byType(Material)).first);
    expect(chip.color, c.heroGlass, reason: 'a translucent cream plate');
  });

  testWidgets('an explicit tone wins; the hero parts take the block ink', (tester) async {
    await tester.pumpWidget(layoutHost(ListView(children: [
      const HomeHeader(name: 'أحمد', tone: AppBlockTone.sky),
      HomeHeroCard(
        tone: AppBlockTone.sky,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const HomeHeroTag('التالي', icon: Icons.schedule_rounded),
          HomeDayRibbon(items: _day(), nowMin: 700),
          const HomeHeroFigure(value: '12', label: 'الحصص'),
        ]),
      ),
    ])));
    await tester.pump(const Duration(milliseconds: 100));
    final c = tester.element(find.byType(AppBlock).first).colors;
    // the header keeps its explicit tone; the hero card is drawn on the redesign hero surface (KIT_SPEC 5.2) and its
    // parts take the forest block's on-hero inks
    final header = find.byType(AppBlock).first;
    final mat = tester.widget<Material>(find.descendant(of: header, matching: find.byType(Material)).first);
    expect(mat.color, c.blockSky);
    expect(find.descendant(of: find.byType(HomeHeroCard), matching: find.byType(AppHeroSurface)), findsOneWidget);
    final forest = AppBlockColors.of(tester.element(find.text('التالي')), AppBlockTone.forest);
    expect(tester.widget<Text>(find.text('التالي')).style!.color, forest.ink);
    expect(tester.widget<Text>(find.text('الحصص')).style!.color, forest.muted);
    expect(find.byType(AppTilt), findsNWidgets(2), reason: 'the tilt of D-583 stays on both hero blocks');
  });

  testWidgets('no overflow at any size: the full header and a hero card', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        HomeHeader(
          name: 'Dr. Abdulrahman Mohammed Al-Rashid Al-Otaibi the Third of His Name',
          subtitle: '4 sessions today · 1 live now · next at 1:00 PM · 3 to do · and a payout waiting for you',
          leading: const CircleAvatar(radius: 18, child: Text('A')),
          actions: _chips(),
          shellActions: _chips(),
          contextSwitcher: const SizedBox(height: 40, width: 220),
          wideTrailing: const SizedBox(height: 44, width: double.infinity),
        ),
        HomeHeroCard(
          onTap: () {},
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const HomeHeroTag('A long tag that must flex rather than clip at the end', icon: Icons.schedule_rounded),
            const SizedBox(height: AppSpace.sm),
            HomeDayRibbon(items: _day(), nowMin: 700),
            const SizedBox(height: AppSpace.md),
            const Row(children: [
              Expanded(child: HomeHeroFigure(value: '12,480', label: 'Earnings this month after the platform share')),
              SizedBox(width: AppSpace.md),
              Expanded(child: HomeHeroFigure(value: '86%', label: 'Attendance')),
            ]),
          ]),
        ),
      ]),
    );
  });
}
