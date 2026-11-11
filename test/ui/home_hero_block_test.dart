// D-622: a role home's hero is a tinted BLOCK (AppBlock(hero: true)) in the block's charcoal ink — peach for a
// student's or a parent's home, sky for every other role — with the name in the editorial display face, the
// actions as paper chips (ChromeIconButton off a bar) and no gradient anywhere in it. The hero parts (tag, day
// ribbon, figure) draw in the block's ink too. Plus: no layout error at 320 / 1400, ar + en, textScaler 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
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

  test('the hero tone follows the role: students and parents on peach, every other role on sage (D-630)', () {
    for (final r in [null, '', 'student', 'parent']) {
      expect(HomeHeader.toneForRole(r), AppBlockTone.peach, reason: '$r');
    }
    for (final r in ['teacher', 'admin', 'super-admin', 'developer', 'org-admin', 'org-staff']) {
      expect(HomeHeader.toneForRole(r), AppBlockTone.sage, reason: r);
    }
  });

  testWidgets('the header is a block: charcoal ink, the editorial name, paper chips, no gradient', (tester) async {
    AppConfig.lang = 'en';
    await tester.pumpWidget(layoutHost(HomeHeader(name: 'Sara Ali', subtitle: '2 sessions today', actions: _chips())));
    await tester.pump();
    expect(find.byType(AppBlock), findsOneWidget);
    expect(find.byType(AppMeshSurface), findsNothing, reason: 'a hero is a block, not the brand gradient');
    expect(find.byType(ChromeBar), findsNothing, reason: 'the chips are paper, not glass on a bar');
    final c = tester.element(find.byType(AppBlock)).colors;
    final block = tester.widget<Material>(find.descendant(of: find.byType(AppBlock), matching: find.byType(Material)).first);
    expect(block.color, c.blockPeach, reason: 'no role in scope: the learning tone');

    final name = tester.widget<Text>(find.text('Sara Ali')).style!;
    expect(name.color, c.blockInk);
    expect(name.fontFamily, AppFonts.editorial);
    expect(name.fontSize, (32 * AppFonts.editorialScale('en')).roundToDouble(), reason: 'the display role');
    final sub = tester.widget<Text>(find.text('2 sessions today')).style!;
    expect(sub.fontFamily, isNot(AppFonts.editorialFamily), reason: 'the day line is the UI sans');
    expect(contrastRatio(sub.color!, c.blockPeach), greaterThanOrEqualTo(kWcagAaText));

    for (final chip in find.byType(ChromeIconButton).evaluate()) {
      final size = (chip.renderObject! as RenderBox).size;
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    final chip = tester.widget<Material>(find.descendant(of: find.byType(ChromeIconButton).first, matching: find.byType(Material)).first);
    expect(chip.color, c.cardBg, reason: 'a paper chip with ink icons');
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
    for (final m in find.byType(AppBlock).evaluate()) {
      final mat = tester.widget<Material>(find.descendant(of: find.byWidget(m.widget), matching: find.byType(Material)).first);
      expect(mat.color, c.blockSky);
    }
    expect(tester.widget<Text>(find.text('التالي')).style!.color, c.blockInk);
    expect(tester.widget<Text>(find.text('الحصص')).style!.color, c.blockMuted(c.blockSky));
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
