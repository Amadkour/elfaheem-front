// Review renders of the hero for each of the 11 areas and 4 role accents (KIT_SPEC §7.3): title + kicker + subtitle,
// and from 700 px 4 stats; plus the student home's hero with the overlapping first card. Not a CI suite.
//
//   flutter test test/visual/redesign/kit_hero_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kit_golden_harness.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

Widget _hero(String name) => AppHero(
      kicker: _t('صباح الخير يا فيصل', 'Good morning, Faisal'),
      title: _t('حصة الرياضيات شغّالة الحين', 'Your maths class is on now'),
      squiggle: _t('شغّالة', 'on'),
      subtitle: _t('مع أ. ماجد الشهري، ٧:٣٠ إلى ٨:٢٠ م ($name)', 'With Mr Majed Alshehri, 7:30 to 8:20 pm ($name)'),
      stats: [
        AppHeroStat(icon: Icons.menu_book_outlined, value: '4', label: _t('دورات', 'courses')),
        AppHeroStat(icon: Icons.trending_up_rounded, value: '62%', label: _t('تقدّمك', 'progress')),
        AppHeroStat(icon: Icons.local_fire_department_outlined, value: '5', label: _t('أيام', 'days')),
        AppHeroStat(icon: Icons.star_outline_rounded, value: '1,240', label: _t('نقاط', 'points')),
      ],
      overlap: false,
    );

Widget _courseTile(BuildContext context, String subject, IconData icon, String ar, String en, String subAr,
    String subEn, double value) {
  final tone = context.colors.kit.subject(subject).tone;
  return AppTile(
    icon: icon,
    tone: tone,
    title: _t(ar, en),
    subtitle: _t(subAr, subEn),
    trailing: AppProgressRing(value: value, tone: tone),
    onTap: () {},
  );
}

Widget _home() => AppAreaScope(
      area: AppArea.home,
      child: Builder(builder: (context) {
        final g = AppSpace.gutter(MediaQuery.sizeOf(context).width);
        return ListView(children: [
          AppHeroOverlap(
            hero: AppHero(
              kicker: _t('صباح الخير يا فيصل', 'Good morning, Faisal'),
              title: _t('حصة الرياضيات شغّالة الحين', 'Your maths class is on now'),
              squiggle: _t('شغّالة', 'on'),
            ),
            body: Padding(
              padding: EdgeInsets.symmetric(horizontal: g),
              child: AppLiveBanner(
                tag: _t('مباشر، من ١٢ دقيقة', 'Live, 12 minutes in'),
                title: _t('الرياضيات: الدوال الأسية', 'Maths: exponential functions'),
                subtitle: _t('مع أ. ماجد الشهري، ٥٠ دقيقة', 'With Mr Majed Alshehri, 50 minutes'),
                hostInitial: _t('م', 'M'),
                actionLabel: _t('ادخل الحصة', 'Join the class'),
                onAction: () {},
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(g),
            child: AppCard(
              title: _t('كمّل من وين وقفت', 'Pick up where you left off'),
              action: AppButton.ghost(label: _t('كل دوراتي', 'All my courses'), onPressed: () {}),
              child: Column(children: [
                _courseTile(context, 'math', Icons.functions_rounded, 'الرياضيات', 'Maths', 'الدوال الأسية',
                    'Exponential functions', .38),
                const SizedBox(height: AppSpace.sm),
                _courseTile(context, 'physics', Icons.science_outlined, 'الفيزياء', 'Physics', 'قوانين نيوتن',
                    "Newton's laws", .64),
                const SizedBox(height: AppSpace.sm),
                _courseTile(context, 'english', Icons.translate_rounded, 'الإنجليزي من الصفر', 'English from zero',
                    'Unit 4: Daily routines', 'Unit 4: Daily routines', .81),
              ]),
            ),
          ),
        ]);
      }),
    );

void main() {
  late StorageService storage;
  setUpAll(() async => storage = await kitGoldenSetUp());

  testWidgets('every area and role', (t) => kitRender(
      t,
      'kit_hero_all',
      () => ListView(children: [
            for (final a in AppArea.values)
              Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: AppSpace.xs),
                  child: AppAreaScope(area: a, child: _hero(a.name))),
            for (final r in AppRoleAccent.values)
              Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: AppSpace.xs),
                  child: AppAreaScope.role(role: r, child: _hero(r.key))),
          ]),
      storage: storage,
      modes: const [false]));

  testWidgets('student home hero with the first card', (t) => kitRender(t, 'kit_hero_home', _home, storage: storage));
}
