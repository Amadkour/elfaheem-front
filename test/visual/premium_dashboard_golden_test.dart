// Visual review renders of the premium dashboard (D-631): the role shell (grouped paper sidebar, paper top bar with
// search · ghost buttons · the person, the page head with its breadcrumb; the phone's bottom bar) around a sample
// home built only from the shared pieces — AppGreetingHero, AppStatCard, AppKpiSpark, AppRingStat, AppShortcutTile,
// AppSectionCard and the course card. Compared by eye like the other test/visual files:
//
//   flutter test test/visual/premium_dashboard_golden_test.dart --update-goldens
//
// → test/visual/goldens/premium_dashboard_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900. The sample is
// also the layout the role homes follow (docs/premium_dashboard_handoff.md).
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_keyboard.dart' show AppCommandPaletteScope;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/courses/course_list_card.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart' show ScreenAppBar;
import 'package:flutter_education_app/utils/widget/base_page.dart' show BasePage;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_screens_golden_test.dart' show pubspecFonts;

String _sdkFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/cache/artifacts/material_fonts';
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll('\\', '/');
  return '${exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await loader.load();
  }

  for (final (family, assets) in pubspecFonts(File('pubspec.yaml').readAsStringSync())) {
    await load(family, assets);
  }
  final sdk = _sdkFonts();
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

final _shot = GlobalKey();

/// `VISUAL_THEME=production` paints with the production theme (test/visual/fixtures/theme_production.json) instead
/// of the built-in palette; the files then end in `_prod`.
final _prodTheme = Platform.environment['VISUAL_THEME'] == 'production';

String get _prodTag => _prodTheme ? '_prod' : '';

String _tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// The sample home: desktop = hero + side card, 4 stats, KPI / ring cards, a section card with period tabs and the
/// course tiles; phone = hero, 2×2 shortcuts, a horizontal course list, stats.
class _SampleHome extends StatelessWidget {
  const _SampleHome();

  List<Widget> _stats() => [
        AppStatCard(icon: Icons.menu_book_rounded, value: '12', label: _tr('مقررات نشطة', 'Active courses'), tone: AppBlockTone.emerald, delta: 0.08, footer: _tr('هذا الشهر', 'this month')),
        AppStatCard(icon: Icons.groups_rounded, value: '1,240', label: _tr('طالب', 'Students'), tone: AppBlockTone.peach, delta: 0.12, footer: _tr('هذا الأسبوع', 'this week')),
        AppStatCard(icon: Icons.event_available_rounded, value: '94%', label: _tr('نسبة الحضور', 'Attendance'), tone: AppBlockTone.sky, delta: -0.02, footer: _tr('عن الأسبوع الماضي', 'vs last week')),
        AppStatCard(icon: Icons.emoji_events_rounded, value: '320', label: _tr('نقاط مكتسبة', 'Points earned'), tone: AppBlockTone.gold, footer: _tr('أعلى درجة: 98', 'Top mark: 98')),
      ];

  Widget _course(String title, String teacher, int lessons, String price, int seed) => CourseListCard(
        shape: CourseCardShape.tile,
        title: title,
        imageUrl: '',
        meta: [teacher, courseLessonsLabel(lessons)],
        footer: CoursePriceFooter(price: price),
        onTap: () {},
      );

  List<Widget> _courses() => [
        _course(_tr('الرياضيات المتقدمة', 'Advanced mathematics'), _tr('د. منى عادل', 'Dr. Mona Adel'), 12, _tr('٤٥٠ ج.م', 'EGP 450'), 1),
        _course(_tr('الفيزياء: الحركة والقوة', 'Physics: motion and force'), _tr('أ. كريم سامي', 'Karim Samy'), 9, _tr('مجاني', 'Free'), 2),
        _course(_tr('الكيمياء العضوية', 'Organic chemistry'), _tr('د. سارة نبيل', 'Dr. Sara Nabil'), 14, _tr('٣٠٠ ج.م', 'EGP 300'), 3),
        _course(_tr('اللغة العربية: البلاغة', 'Arabic rhetoric'), _tr('أ. هدى فؤاد', 'Hoda Fouad'), 8, _tr('٢٠٠ ج.م', 'EGP 200'), 4),
      ];

  Widget _hero({required bool centered}) => AppGreetingHero(
        greeting: HomeHeader.greetingLine(_tr('أحمد', 'Ahmed')),
        summary: _tr('لديك جلستان اليوم و٣ مهام تنتظرك — أنهيت ٧٠٪ من هدف الأسبوع', '2 sessions today and 3 things to do — 70% of this week\'s goal done'),
        initials: _tr('أ', 'A'),
        ring: 0.7,
        centered: centered,
        cta: AppGreetingHeroButton(label: _tr('تابع التعلّم', 'Continue learning'), icon: Icons.play_arrow_rounded, onTap: () {}),
      );

  Widget _today(BuildContext context) {
    final c = context.colors;
    Widget line(String time, String title, String place, {bool live = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: Row(children: [
            SizedBox(width: 64, child: Text(time, style: AppType.label(context).copyWith(color: c.textMedium))),
            Container(width: 8, height: 8, decoration: BoxDecoration(color: live ? c.danger : c.primary, shape: BoxShape.circle)),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
            Text(place, style: AppType.meta(context).copyWith(color: c.textLight)),
          ]),
        );
    return AppSectionCard(
      title: _tr('يومك', 'Your day'),
      subtitle: _tr('الأربعاء ١١ نوفمبر', 'Wednesday, 11 November'),
      actions: [AppButton.ghost(label: _tr('التقويم', 'Calendar'), onPressed: () {})],
      child: Column(children: [
        line('09:00', _tr('الرياضيات المتقدمة', 'Advanced mathematics'), _tr('قاعة ٣', 'Room 3'), live: true),
        line('11:30', _tr('الفيزياء', 'Physics'), _tr('معمل ٢', 'Lab 2')),
        line('14:00', _tr('مراجعة الكيمياء', 'Chemistry review'), _tr('أونلاين', 'Online')),
        line('16:00', _tr('ساعات مكتبية', 'Office hours'), _tr('مكتب ٤', 'Office 4')),
      ]),
    );
  }

  Widget _overview(BuildContext context) => AppSectionCard(
        title: _tr('نظرة عامة', 'Overview'),
        subtitle: _tr('آخر ٧ أيام', 'Last 7 days'),
        tabs: AppTabs(
          items: [AppTabItem(_tr('يومي', 'Daily')), AppTabItem(_tr('أسبوعي', 'Weekly')), AppTabItem(_tr('شهري', 'Monthly'))],
          index: 1,
          onChanged: (_) {},
        ),
        child: AppBarChart(
          height: 200,
          series: [
            AppChartSeries(_tr('حضور', 'Attended'), const [42, 55, 48, 61, 58, 66, 70]),
            AppChartSeries(_tr('غياب', 'Absent'), const [8, 6, 9, 4, 5, 3, 2]),
          ],
          labels: [for (final d in _tr('سبت أحد اثنين ثلاثاء أربعاء خميس جمعة', 'Sat Sun Mon Tue Wed Thu Fri').split(' ')) d],
        ),
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final phone = box.maxWidth < 700;
        final g = AppSpace.gutter(box.maxWidth);
        if (phone) {
          return ListView(padding: EdgeInsets.fromLTRB(g, AppSpace.sm, g, AppSpace.xl), children: [
            _hero(centered: false),
            const SizedBox(height: AppSpace.lg),
            AppShortcutGrid(maxColumns: 2, children: [
              AppShortcutTile(icon: Icons.school_rounded, label: _tr('كل الفصول', 'All classes'), tone: AppBlockTone.emerald, onTap: () {}),
              AppShortcutTile(icon: Icons.menu_book_rounded, label: _tr('مقرراتي', 'My courses'), tone: AppBlockTone.peach, badge: 2, onTap: () {}),
              AppShortcutTile(icon: Icons.bookmarks_rounded, label: _tr('المحفوظات', 'My shelf'), tone: AppBlockTone.sky, onTap: () {}),
              AppShortcutTile(icon: Icons.insights_rounded, label: _tr('تقدّمي', 'My progress'), tone: AppBlockTone.gold, onTap: () {}),
            ]),
            Padding(
              padding: AppSpace.sectionHead,
              child: Text(_tr('أكمل التعلّم', 'Continue learning'), style: AppType.section(context)),
            ),
            SizedBox(
              height: CourseListCard.tileHeight(context, 220),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 4,
                separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
                itemBuilder: (_, i) => SizedBox(width: 220, child: _courses()[i]),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            AppKpiGrid(children: _stats()),
          ]);
        }
        return ListView(padding: EdgeInsets.fromLTRB(g, AppSpace.sm, g, AppSpace.xl), children: [
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 5, child: _hero(centered: true)),
              const SizedBox(width: AppSpace.lg),
              Expanded(flex: 6, child: _today(context)),
            ]),
          ),
          const SizedBox(height: AppSpace.lg),
          AppKpiGrid(children: _stats()),
          const SizedBox(height: AppSpace.lg),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 7, child: _overview(context)),
            const SizedBox(width: AppSpace.lg),
            Expanded(
              flex: 4,
              child: Column(children: [
                AppKpiSpark(label: _tr('دقائق التعلّم', 'Minutes learned'), value: '1,284', values: const [30, 42, 38, 55, 49, 62, 70], icon: Icons.timer_rounded, delta: 0.14),
                const SizedBox(height: AppSpace.md),
                AppRingStat(label: _tr('هدف الأسبوع', 'Weekly goal'), value: _tr('7 من 10', '7 of 10'), progress: 0.7, caption: _tr('٣ دروس متبقية', '3 lessons to go'), tone: AppBlockTone.peach),
              ]),
            ),
          ]),
          const SizedBox(height: AppSpace.lg),
          AppSectionCard(
            title: _tr('مقرراتي', 'My courses'),
            actions: [AppButton.ghost(label: _tr('عرض الكل', 'See all'), onPressed: () {})],
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final (i, w) in _courses().indexed) ...[
                if (i > 0) const SizedBox(width: AppSpace.md),
                Expanded(child: w),
              ],
            ]),
          ),
        ]);
      });
}

void main() {
  late StorageService storage;
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.getInstance();
    await storage.saveUser({'id': 7, 'name': 'أحمد حمدي', 'gmail': 'ahmed@example.test', 'role': 'teacher'});
    AppConfig.disableList = [];
  });

  Widget host({required bool dark, required double width}) {
    final theme = ThemeConfigProvider(api: ApiClient());
    if (_prodTheme) {
      theme.debugUseColors(
          jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>);
    }
    final rtl = AppConfig.lang == 'ar';
    final items = [
      DashboardItem(Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'home', null, const _SampleHome(), badge: 3),
      DashboardItem(Icons.menu_book_outlined, Icons.menu_book_rounded, 'my_courses', null, const SizedBox(), badge: 2),
      DashboardItem(Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'my_calendar', null, const SizedBox()),
      DashboardItem(Icons.analytics_outlined, Icons.analytics_rounded, 'analysis', null, const SizedBox()),
      DashboardItem(Icons.person_outline_rounded, Icons.person_rounded, 'my_profile', null, const SizedBox()),
    ];
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MyAuthProvider(storage: storage)..loadCachedUser()),
        ChangeNotifierProvider(create: (_) => LangProvider(storage: storage)),
      ],
      child: ThemeConfigScope(
        provider: theme,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.materialTheme(dark: false),
          darkTheme: theme.materialTheme(dark: true),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
          home: RepaintBoundary(
            key: _shot,
            child: AppCommandPaletteScope(
              onOpen: () {},
              child: AppShell(width: width, currentIndex: 0, onTap: (_) {}, items: items, unreadCount: 4),
            ),
          ),
        ),
      ),
    );
  }

  // The floating chrome (D-648): teacher and student shells at 1440 × 900 and 390 × 844, Arabic, light and dark, and
  // a page pushed inside a tab (its own floating bar with Back) → goldens/shell_chrome_<role>_<w>_ar_<theme>.png.
  testWidgets('shell chrome per role', (tester) async {
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    try {
      for (final role in const ['teacher', 'student']) {
        await storage.saveUser({'id': 7, 'name': 'أحمد حمدي', 'gmail': 'ahmed@example.test', 'role': role});
        for (final size in const [Size(1440, 900), Size(390, 844)]) {
          for (final dark in const [false, true]) {
            for (final pushed in const [false, true]) {
              AppConfig.lang = 'ar';
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = size;
              await tester.pumpWidget(const SizedBox());
              await tester.pumpWidget(host(dark: dark, width: size.width));
              await tester.pump(const Duration(milliseconds: 300));
              if (pushed) {
                final nav = tester.state<NavigatorState>(
                    find.descendant(of: find.byType(LazyTabStack), matching: find.byWidgetPredicate((w) => w is Navigator)).first);
                nav.push(MaterialPageRoute<void>(
                  builder: (_) => BasePage(
                    appBar: ScreenAppBar(title: _tr('تفاصيل الجلسة', 'Session details'), helpPageId: 'inbox'),
                    child: const Padding(padding: EdgeInsets.all(AppSpace.lg), child: _SampleHome()),
                  ),
                ));
              }
              for (var i = 0; i < 12; i++) {
                await tester.pump(const Duration(milliseconds: 100));
              }
              expect(tester.takeException(), isNull);
              final tag = pushed ? '${role}_pushed' : role;
              await expectLater(find.byKey(_shot),
                  matchesGoldenFile('goldens/shell_chrome_${tag}_${size.width.toInt()}_ar_${dark ? 'dark' : 'light'}$_prodTag.png'));
            }
          }
        }
      }
    } finally {
      AppConfig.lang = prevLang;
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  testWidgets('premium dashboard', (tester) async {
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    try {
      for (final size in const [Size(390, 844), Size(1440, 1300)]) {
        for (final lang in const ['ar', 'en']) {
          for (final dark in const [false, true]) {
            AppConfig.lang = lang;
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(host(dark: dark, width: size.width));
            for (var i = 0; i < 12; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            expect(tester.takeException(), isNull);
            await expectLater(find.byKey(_shot),
                matchesGoldenFile('goldens/premium_dashboard_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
          }
        }
      }
    } finally {
      AppConfig.lang = prevLang;
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
