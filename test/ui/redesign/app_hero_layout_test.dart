// AppHero (KIT_SPEC §5.2, §7.2): every parameter combination of the phone / web table, the student phone height
// budget, and the old Data Lab call shape.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_area.dart';
import 'package:flutter_education_app/design/app_hero.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';
import 'redesign_harness.dart';

const _longAr = 'حصة الرياضيات شغالة الحين والدرس طويل جدًا عن الدوال الأسية واللوغاريتمية وتطبيقاتها في الحياة';
const _longEn = 'The mathematics session is live now and the lesson on exponential and logarithmic functions is long';

List<AppHeroStat> _stats(int n) => [
      for (var i = 0; i < n; i++) AppHeroStat(icon: Icons.star_rounded, value: '${12 * (i + 1)}', label: 'stat $i'),
    ];

final Map<String, Widget Function()> _cases = {
  'title only': () => const AppHero(title: 'الرئيسية'),
  'kicker + squiggle + subtitle': () =>
      const AppHero(kicker: 'صباح الخير يا فيصل', title: 'حصة الرياضيات شغالة الحين', squiggle: 'شغالة', subtitle: 'مع أ. ماجد'),
  '4 stats': () => AppHero(title: 'Home', subtitle: 'Today', stats: _stats(4), statsOnPhone: true),
  '3 stats': () => AppHero(title: 'Home', stats: _stats(3), statsOnPhone: true),
  '2 actions': () => AppHero(title: 'Home', actions: [
        FilledButton(onPressed: () {}, child: const Text('Join')),
        OutlinedButton(onPressed: () {}, child: const Text('Later')),
      ]),
  'trailing': () => const AppHero(title: 'Home', trailing: SizedBox(width: 280, height: 120)),
  'leading': () => const AppHero(title: 'Home', subtitle: 'sub', leading: CircleAvatar(child: Text('F'))),
  'bottom': () => const AppHero(title: 'Home', bottom: SizedBox(height: 42, child: Placeholder())),
  'long ar': () => AppHero(title: _longAr, subtitle: _longAr, kicker: _longAr, stats: _stats(4)),
  'long en': () => AppHero(title: _longEn, subtitle: _longEn, kicker: _longEn, stats: _stats(4)),
  // the old Data Lab call
  'old call': () => AppHero(
      title: 'Data Lab',
      subtitle: 'Everything in one place',
      icon: Icons.science_rounded,
      stats: const [AppHeroStat(icon: Icons.menu_book_rounded, value: '12', label: 'courses')]),
};

void main() {
  for (final e in _cases.entries) {
    testWidgets('layout: ${e.key}', (tester) async {
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: e.value()));
    });
  }
  for (final k in ['kicker + squiggle + subtitle', '4 stats', 'long ar', 'old call']) {
    testWidgets('layout under a student area: $k', (tester) async {
      await expectNoLayoutErrors(
          tester, () => AppAreaScope(area: AppArea.learn, child: SingleChildScrollView(child: _cases[k]!())));
    });
  }

  testWidgets('390 x 844, scale 1.0, home area: hero <= maxStudentPhone and the first card top <= firstCardBy',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final prev = AppConfig.lang;
    addTearDown(() => AppConfig.lang = prev);
    for (final lang in ['ar', 'en']) {
      AppConfig.lang = lang;
      const heroKey = ValueKey('hero');
      const cardKey = ValueKey('card');
      await tester.pumpWidget(kitHost(
        Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            child: AppHeroOverlap(
              hero: AppHero(
                key: heroKey,
                kicker: lang == 'ar' ? 'صباح الخير يا فيصل' : 'Good morning, Faisal',
                // one line in the test font too (its glyphs are as wide as they are tall)
                title: lang == 'ar' ? 'دروسي اليوم' : 'Maths now',
                subtitle: lang == 'ar' ? 'مع أ. ماجد' : 'With Mr Majed',
              ),
              body: const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: SizedBox(key: cardKey, height: 200, child: Placeholder()),
              ),
            ),
          ),
        ),
        area: AppArea.home,
        reduce: true,
        dir: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      ));
      await tester.pump();
      final hero = tester.getSize(find.byKey(heroKey));
      expect(hero.height, lessThanOrEqualTo(AppHeroMetrics.maxStudentPhone), reason: '$lang hero ${hero.height}');
      final top = tester.getTopLeft(find.byKey(cardKey)).dy - tester.getTopLeft(find.byKey(heroKey)).dy;
      expect(top, lessThanOrEqualTo(AppHeroMetrics.firstCardBy), reason: '$lang card top $top');
      expect(top, closeTo(hero.height - AppHeroMetrics.overlapStudentPhone, .5));
    }
  });
}
