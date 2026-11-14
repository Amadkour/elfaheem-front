// VISUAL review renders (not a CI suite) of the D-622 kit pieces: the boot splash (light / dark, ar / en), the
// home hero block and hero card for both tones with every part, the brand surfaces (AppHeader band, a primary
// button, a highlighted KPI) and BasePage's "coming soon" page.
//
//   flutter test test/visual/kit_hero_golden_test.dart --update-goldens
//
// → test/visual/goldens/kit_<name>_<width>_<lang>_<light|dark>.png
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/boot_splash.dart';
import 'package:flutter_education_app/design/chrome_button.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_test/flutter_test.dart';

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
String _tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

Widget _host(Widget child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(key: _shot, child: child),
    ),
  );
}

Future<void> _render(WidgetTester tester, String name, Widget Function(bool dark) build, {int frames = 12}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(dark), dark: dark));
          for (var i = 0; i < frames; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          await expectLater(find.byKey(_shot),
              matchesGoldenFile('goldens/kit_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

List<Widget> _chips() => [
      for (final (icon, label, badge) in [(Icons.videocam_outlined, 'meet', 0), (Icons.event_rounded, 'calendar', 0), (Icons.notifications_none_rounded, 'bell', 3)])
        ChromeIconButton(icon: icon, label: label, onTap: () {}, badge: badge),
    ];

List<HomeAgendaItem> _day() => [
      HomeAgendaItem(start: '9:00', end: '10:30', title: _tr('الجبر', 'Algebra'), startMin: 540, endMin: 630),
      HomeAgendaItem(start: '11:00', end: '12:00', title: _tr('معمل الفيزياء', 'Physics lab'), startMin: 660, endMin: 720, live: true),
      HomeAgendaItem(start: '16:00', end: '17:30', title: _tr('ساعات مكتبية', 'Office hours'), startMin: 960, endMin: 1050),
    ];

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });

  testWidgets('kit splash', (tester) async {
    await _render(tester, 'splash', (dark) {
      SplashTheme.dark.value = dark;
      final s = SplashState()
        ..clockOffset = 2.4
        ..steps = 4
        ..expected = 10
        ..step = 'offlineVideos'
        ..appName = _tr('الفهيم', 'Alfaheem')
        ..tagline = _tr('تعلّم في أي مكان، في أي وقت', 'Learn anywhere, any time')
        ..version = '3.4.0'
        ..setFooter(text: _tr('من إنتاج Double Y', 'Powered by Double Y'))
        ..setUser({'name': _tr('أحمد حمدي', 'Ahmed Hamdy')});
      return BootSplash(state: s);
    }, frames: 4);
    SplashTheme.dark.value = null;
  });

  testWidgets('kit hero', (tester) async {
    await _render(tester, 'hero', (dark) {
      return Builder(builder: (context) {
        final c = context.colors;
        return Scaffold(
          backgroundColor: c.background,
          body: ListView(padding: const EdgeInsets.only(bottom: AppSpace.xl), children: [
            for (final tone in [AppBlockTone.peach, AppBlockTone.sky]) ...[
              HomeHeader(
                tone: tone,
                name: _tr('سارة علي الراشد', 'Sara Ali Al-Rashid'),
                subtitle: _tr('٢ حصة اليوم · واحدة الآن · ٣ مهام', '2 sessions today · 1 live now · 3 to do'),
                leading: CircleAvatar(radius: 18, backgroundColor: c.primary, child: Text('S', style: TextStyle(color: c.onHero))),
                actions: _chips(),
                contextSwitcher: AppStatusBadge(label: _tr('الحساب الشخصي', 'Personal account'), tone: AppTone.neutral),
              ),
              HomeHeroCard(
                tone: tone,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  HomeHeroTag(_tr('التالي · 12:40', 'Next up · 12:40'), icon: Icons.schedule_rounded),
                  const SizedBox(height: AppSpace.sm),
                  HomeDayRibbon(items: _day(), nowMin: 700),
                  const SizedBox(height: AppSpace.md),
                  Row(children: [
                    Expanded(child: HomeHeroFigure(value: '12,480', label: _tr('أرباح هذا الشهر', 'Earnings this month'))),
                    const SizedBox(width: AppSpace.md),
                    Expanded(child: HomeHeroFigure(value: '86%', label: _tr('الحضور', 'Attendance'))),
                  ]),
                ]),
              ),
              const SizedBox(height: AppSpace.lg),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md + AppSpace.xxs),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AppHeader(title: _tr('الطلاب', 'Students'), subtitle: _tr('كل الأقسام', 'All departments'), actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.search_rounded))]),
                const SizedBox(height: AppSpace.md),
                FilledButton(onPressed: () {}, child: Text(_tr('متابعة', 'Continue'))),
                const SizedBox(height: AppSpace.md),
                AppKpiGrid(children: [
                  AppKpiCard(label: _tr('الإيرادات · 30 يومًا', 'Revenue · 30 days'), value: '12,480', icon: Icons.payments_rounded, delta: 0.12, highlight: true),
                  AppKpiCard(label: _tr('الطلاب', 'Students'), value: '1,204', icon: Icons.school_rounded, delta: 0.04),
                ]),
              ]),
            ),
          ]),
        );
      });
    });
  });

  testWidgets('kit coming soon', (tester) async {
    await _render(tester, 'soon', (dark) {
      AppConfig.disableList = ['my_courses'];
      return const BasePage(key: ValueKey('my_courses'), child: SizedBox());
    }, frames: 3);
    AppConfig.disableList = [];
  });
}
