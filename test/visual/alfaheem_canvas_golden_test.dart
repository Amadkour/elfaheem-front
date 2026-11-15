// ALFAHEEM ONLY (A-007). Visual review of the page canvas: a role shell around a sample home, and a settings page,
// at 1440 × 900 and 390 × 844, Arabic, light and dark, with the live Alfaheem theme
// (test/visual/fixtures/theme_alfaheem.json, GET /api/v1/theme/web of 2026-11-15). Compared by eye:
//
//   flutter test test/visual/alfaheem_canvas_golden_test.dart --update-goldens
//
// → test/visual/goldens/alfaheem_canvas_<page>_<width>_<light|dark>_<after|before>.png ("before" = the plain
// upstream canvas, AlfaheemCanvas.enabled = false).
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
import 'package:flutter_education_app/design/alfaheem_canvas.dart';
import 'package:flutter_education_app/design/app_keyboard.dart' show AppCommandPaletteScope;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart' show BasePage;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_screens_golden_test.dart' show pubspecFonts;

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
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll(r'\', '/');
  final root = Platform.environment['FLUTTER_ROOT'];
  final sdk = root != null && root.isNotEmpty
      ? '$root/bin/cache/artifacts/material_fonts'
      : '${exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

String _tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

final _shot = GlobalKey();

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final g = AppSpace.gutter(box.maxWidth);
        final c = context.colors;
        Widget line(String time, String title) => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
              child: Row(children: [
                SizedBox(width: 64, child: Text(time, style: AppType.label(context).copyWith(color: c.textMedium))),
                Expanded(child: Text(title, style: AppType.row(context))),
              ]),
            );
        return ListView(padding: EdgeInsets.fromLTRB(g, AppSpace.sm, g, AppSpace.xl), children: [
          AppGreetingHero(
            greeting: HomeHeader.greetingLine(_tr('أحمد', 'Ahmed')),
            summary: _tr('لديك جلستان اليوم و٣ مهام تنتظرك', '2 sessions today and 3 things to do'),
            initials: _tr('أ', 'A'),
            ring: 0.7,
            cta: AppGreetingHeroButton(label: _tr('تابع التعلّم', 'Continue learning'), icon: Icons.play_arrow_rounded, onTap: () {}),
          ),
          const SizedBox(height: AppSpace.lg),
          AppKpiGrid(children: [
            AppStatCard(icon: Icons.menu_book_rounded, value: '12', label: _tr('مقررات نشطة', 'Active courses'), tone: AppBlockTone.emerald),
            AppStatCard(icon: Icons.groups_rounded, value: '1,240', label: _tr('طالب', 'Students'), tone: AppBlockTone.peach),
            AppStatCard(icon: Icons.event_available_rounded, value: '94%', label: _tr('نسبة الحضور', 'Attendance'), tone: AppBlockTone.sky),
            AppStatCard(icon: Icons.emoji_events_rounded, value: '320', label: _tr('نقاط مكتسبة', 'Points earned'), tone: AppBlockTone.gold),
          ]),
          const SizedBox(height: AppSpace.lg),
          AppSectionCard(
            title: _tr('يومك', 'Your day'),
            subtitle: _tr('الأحد ١٥ نوفمبر', 'Sunday, 15 November'),
            child: Column(children: [
              line('09:00', _tr('القدرات: الكمي', 'Quantitative')),
              line('11:30', _tr('التحصيلي: الفيزياء', 'Physics')),
              line('14:00', _tr('اللغة الإنجليزية', 'English')),
            ]),
          ),
          const SizedBox(height: AppSpace.lg),
          AppEmpty(icon: Icons.inbox_rounded, title: _tr('لا رسائل جديدة', 'No new messages')),
        ]);
      });
}

class _Settings extends StatelessWidget {
  const _Settings();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BasePage(
      child: AppSettingsPage(
        groups: [
          AppSettingsGroup(title: _tr('الحساب', 'Account'), icon: Icons.account_circle_rounded, children: [
            AppSettingsTile(icon: Icons.manage_accounts_rounded, label: _tr('تحديث الحساب', 'Update account'), onTap: () {}),
            AppSettingsTile(
                icon: Icons.lock_reset_rounded,
                label: _tr('تغيير كلمة المرور', 'Change password'),
                subtitle: _tr('آخر تغيير قبل ٣ أشهر', 'Last changed 3 months ago'),
                onTap: () {}),
            AppSettingsTile(
                icon: Icons.dark_mode_rounded,
                label: _tr('الوضع الداكن', 'Dark mode'),
                trailing: AppSwitch(value: c.isDark, onChanged: (_) {}, semanticLabel: 'dark')),
          ]),
          AppSettingsGroup(title: _tr('التعليم', 'Teaching'), icon: Icons.school_rounded, children: [
            AppSettingsTile(icon: Icons.menu_book_rounded, label: _tr('دوراتي', 'My courses'), badge: 3, onTap: () {}),
            AppSettingsTile(icon: Icons.quiz_rounded, label: _tr('الامتحانات', 'Exams'), color: c.success, onTap: () {}),
          ]),
        ],
      ),
    );
  }
}

void main() {
  late StorageService storage;
  final colors = jsonDecode(File('test/visual/fixtures/theme_alfaheem.json').readAsStringSync()) as Map<String, dynamic>;
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

  Widget host({required bool dark, required double width, required int tab}) {
    final theme = ThemeConfigProvider(api: ApiClient())..debugUseColors(colors);
    final items = [
      DashboardItem(Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'home', null, const _Home(), badge: 3),
      DashboardItem(Icons.settings_outlined, Icons.settings_rounded, 'settings', null, const _Settings()),
      DashboardItem(Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'my_calendar', null, const SizedBox()),
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
          builder: (context, w) => Directionality(textDirection: TextDirection.rtl, child: w!),
          home: RepaintBoundary(
            key: _shot,
            child: AppCommandPaletteScope(
              onOpen: () {},
              child: AppShell(width: width, currentIndex: tab, onTap: (_) {}, items: items, unreadCount: 4),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('alfaheem canvas', (tester) async {
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    try {
      for (final after in const [true, false]) {
        AlfaheemCanvas.enabled = after;
        for (final (tab, page) in const [(0, 'dashboard'), (1, 'settings')]) {
          for (final size in const [Size(1440, 900), Size(390, 844)]) {
            for (final dark in const [false, true]) {
              AppConfig.lang = 'ar';
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = size;
              await tester.pumpWidget(const SizedBox());
              await tester.pumpWidget(host(dark: dark, width: size.width, tab: tab));
              for (var i = 0; i < 12; i++) {
                await tester.pump(const Duration(milliseconds: 100));
              }
              expect(tester.takeException(), isNull);
              await expectLater(
                  find.byKey(_shot),
                  matchesGoldenFile('goldens/alfaheem_canvas_${page}_${size.width.toInt()}_${dark ? 'dark' : 'light'}'
                      '_${after ? 'after' : 'before'}.png'));
            }
          }
        }
      }
    } finally {
      AlfaheemCanvas.enabled = true;
      AppConfig.lang = prevLang;
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
