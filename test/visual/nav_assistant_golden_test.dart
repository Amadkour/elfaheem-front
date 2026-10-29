// Visual review renders of the per-tab navigation (D-081) and the floating assistant's controls, compared by eye
// like the other test/visual files:
//
//   flutter test test/visual/nav_assistant_golden_test.dart --update-goldens
//
// → test/visual/goldens/nav_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900:
//   page     a page pushed from the Home tab (the bar / sidebar stays) with the bubble at its resting place
//   menu     the bubble's long-press menu (Open assistant · Hide button)
//   drag     the bubble dragged onto the hide target
//   settings the settings group with "App assistant" and the "Floating assistant button" switch
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
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_shell.dart';
import 'package:flutter_education_app/design/app_shell_nav.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/shared/rag/app_assistant.dart';
import 'package:flutter_education_app/utils/top_route_observer.dart';
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
String _tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

enum _Scene { page, menu, drag, settings }

void main() {
  late StorageService storage;
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.getInstance();
    AppConfig.disableList = [];
  });

  Widget host(_Scene scene, {required bool dark}) {
    final theme = ThemeConfigProvider(api: ApiClient());
    final rtl = AppConfig.lang == 'ar';
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MyAuthProvider(storage: storage)),
        ChangeNotifierProvider(create: (_) => LangProvider(storage: storage)),
      ],
      child: ThemeConfigScope(
        provider: theme,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.materialTheme(dark: false),
          darkTheme: theme.materialTheme(dark: true),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          navigatorObservers: [topRouteObserver],
          builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
          home: RepaintBoundary(
            key: _shot,
            child: scene == _Scene.settings ? const _SettingsScene() : _ShellScene(scene: scene),
          ),
        ),
      ),
    );
  }

  Future<void> render(WidgetTester tester, _Scene scene) async {
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
            await tester.pumpWidget(host(scene, dark: dark));
            for (var i = 0; i < 6; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            if (scene != _Scene.settings) {
              AppShellNav.pushTarget()?.push(MaterialPageRoute<void>(builder: (_) => const _CoursePage()));
              for (var i = 0; i < 10; i++) {
                await tester.pump(const Duration(milliseconds: 100));
              }
            }
            expect(tester.takeException(), isNull);
            await expectLater(find.byKey(_shot),
                matchesGoldenFile('goldens/nav_${scene.name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
          }
        }
      }
    } finally {
      AppConfig.lang = prevLang;
      debugDisableShadows = true;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  }

  for (final s in _Scene.values) {
    testWidgets('nav ${s.name}', (t) => render(t, s));
  }
}

/// A role shell (student-like tabs) with the bubble layer drawn the way AppAssistantHost places it.
class _ShellScene extends StatefulWidget {
  const _ShellScene({required this.scene});
  final _Scene scene;

  @override
  State<_ShellScene> createState() => _ShellSceneState();
}

class _ShellSceneState extends State<_ShellScene> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final items = [
      DashboardItem(Icons.home_outlined, Icons.home_rounded, 'home', () async {}, const _HomeTab(), badge: 2),
      DashboardItem(Icons.menu_book_outlined, Icons.menu_book_rounded, 'my_courses', null, const SizedBox()),
      DashboardItem(Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'my_schedule', null, const SizedBox()),
      DashboardItem(Icons.analytics_outlined, Icons.analytics_rounded, 'analysis', null, const SizedBox()),
      DashboardItem(Icons.person_outline_rounded, Icons.person_rounded, 'my_profile', null, const SizedBox(), badge: 1),
    ];
    return Stack(children: [
      LayoutBuilder(
        builder: (context, c) => AppShell(
            width: c.maxWidth, currentIndex: _index, onTap: (i) => setState(() => _index = i), items: items, unreadCount: 3),
      ),
      Positioned.fill(child: ListenableBuilder(listenable: AppShellNav.changes, builder: (context, _) => _bubbleLayer(context))),
    ]);
  }

  Widget _bubbleLayer(BuildContext context) {
    final mq = MediaQuery.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final bar = AppShellNav.bottomBarHeight();
    final side = AppShellNav.sideChromeWidth();
    final pad = mq.padding + EdgeInsets.only(left: rtl ? 0 : side, right: rtl ? side : 0);
    final band = appAssistantBand(mq.size, pad,
        bottomBar: bar, topClear: side > 0 ? 64 : kToolbarHeight, bottomClear: appAssistantBottomClear);
    var pos = AppAssistantSpot.fallback(rtl: side > 0 ? !rtl : rtl).toOffset(mq.size, pad, band);
    final target = appAssistantDismissCenter(mq.size, mq.padding, bottomBar: bar);
    if (widget.scene == _Scene.drag) pos = target - const Offset(appAssistantBubbleSize / 2 - 6, appAssistantBubbleSize / 2 - 4);
    final left = pos.dx + appAssistantBubbleSize / 2 < mq.size.width / 2;
    return Stack(children: [
      if (widget.scene == _Scene.drag) Positioned.fill(child: AppAssistantDismissTarget(center: target, active: true)),
      Positioned(
        left: pos.dx,
        top: pos.dy,
        child: Transform.scale(scale: widget.scene == _Scene.drag ? 0.82 : 1, child: AppAssistantBubble(onTap: () {})),
      ),
      if (widget.scene == _Scene.menu)
        Positioned(
          left: left ? pos.dx + appAssistantBubbleSize + 8 : pos.dx - 208 - 8,
          top: pos.dy + appAssistantBubbleSize / 2 - 52,
          width: 208,
          child: AppAssistantBubbleMenu(onOpen: () {}, onHide: () {}),
        ),
    ]);
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

/// A pushed page (what used to cover the tab bar).
class _CoursePage extends StatelessWidget {
  const _CoursePage();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget card(IconData icon, String title, String sub) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: AppCard(
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: c.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: c.label.copyWith(color: c.textDark, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(sub, style: c.caption),
                ]),
              ),
            ]),
          ),
        );
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: Text(_tr('تفاصيل الدورة', 'Course details'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        card(Icons.play_circle_rounded, _tr('المحاضرة ٣: المتجهات', 'Lecture 3: Vectors'), _tr('٤٥ دقيقة · شوهدت ٦٠٪', '45 min · 60% watched')),
        card(Icons.quiz_rounded, _tr('اختبار قصير', 'Short quiz'), _tr('يغلق غداً ٩:٠٠ م', 'Closes tomorrow 9:00 PM')),
        card(Icons.description_rounded, _tr('ملخص الوحدة الأولى', 'Unit 1 summary'), _tr('PDF · ٢٫٤ ميجابايت', 'PDF · 2.4 MB')),
        card(Icons.forum_rounded, _tr('إعلانات الدورة', 'Course announcements'), _tr('إعلانان جديدان', '2 new')),
      ]),
    );
  }
}

class _SettingsScene extends StatelessWidget {
  const _SettingsScene();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(title: Text('settings'.tr)),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: AppSettingsGroup(title: 'settings'.tr, icon: Icons.settings_rounded, children: [
                AppSettingsTile(icon: Icons.language_rounded, color: context.colors.primaryLight, label: 'change_language'.tr, onTap: () {}),
                const AppAssistantOpenTile(),
                const AppAssistantBubbleTile(),
                AppSettingsTile(
                    icon: Icons.dark_mode_rounded,
                    color: context.colors.textDark,
                    label: 'dark_mode'.tr,
                    trailing: AppSwitch(value: false, onChanged: (_) {})),
              ]),
            ),
          ),
        ),
      );
}
