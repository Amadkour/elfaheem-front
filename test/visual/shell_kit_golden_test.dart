// Visual review renders of the role shell kit (Warm Editorial Blocks): the paper sidebar / rail / bottom bar with
// the emerald selected pill and the badge tones, the context pill with its exit button, an attention badge and the
// language switch on the open tab — compared by eye like the other test/visual files:
//
//   flutter test test/visual/shell_kit_golden_test.dart --update-goldens
//
// → test/visual/goldens/shell_kit_home_<width>_<lang>_<light|dark>.png at 390×844 (bottom bar), 800×900 (rail)
//   and 1440×900 (sidebar).
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
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_language_switch.dart';
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
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

const Map<String, dynamic> _org = {
  'id': 4,
  'status': 'approved',
  'type': 'university',
  'name_en': 'Cairo Modern University',
  'name_ar': 'جامعة القاهرة الحديثة',
  'logo_url': '',
};

void main() {
  late StorageService storage;
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.getInstance();
    await storage.saveUser({'id': 7, 'name': 'أحمد حمدي', 'gmail': 'ahmed@example.test', 'role': 'student'});
    AppConfig.disableList = [];
    AppConfig.orgsEnabled = true;
    AppModeController.applyContext = (_) {};
    AppModeController.instance.debugSet({
      'items': [
        {'organization': _org, 'roles': ['student'], 'manage': null, 'pending': 2},
      ],
      'default_org_id': 4,
    }, mode: AppMode.organization, orgId: 4);
    AttentionService.instance.bumpLocal(AttentionTabs.chat, 3);
  });
  tearDown(() => AttentionService.instance.bumpLocal(AttentionTabs.chat, -3));

  Widget host({required bool dark}) {
    final theme = ThemeConfigProvider(api: ApiClient());
    final rtl = AppConfig.lang == 'ar';
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
          navigatorObservers: [topRouteObserver],
          builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
          home: RepaintBoundary(key: _shot, child: const _ShellScene()),
        ),
      ),
    );
  }

  testWidgets('shell kit home', (tester) async {
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    try {
      for (final size in const [Size(390, 844), Size(800, 900), Size(1440, 900)]) {
        for (final lang in const ['ar', 'en']) {
          for (final dark in const [false, true]) {
            AppConfig.lang = lang;
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size;
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(host(dark: dark));
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            expect(tester.takeException(), isNull);
            await expectLater(find.byKey(_shot),
                matchesGoldenFile('goldens/shell_kit_home_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
          }
        }
      }
    } finally {
      AppConfig.lang = prevLang;
      debugDisableShadows = true;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}

class _ShellScene extends StatefulWidget {
  const _ShellScene();

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
      DashboardItem(Icons.analytics_outlined, Icons.analytics_rounded, 'analysis', null, const SizedBox(),
          badge: 1, badgeTone: ShellBadgeTone.reward),
      DashboardItem(Icons.person_outline_rounded, Icons.person_rounded, 'my_profile', null, const SizedBox(), badge: 120),
    ];
    return LayoutBuilder(
      builder: (context, c) => AppShell(
          width: c.maxWidth, currentIndex: _index, onTap: (i) => setState(() => _index = i), items: items, unreadCount: 3),
    );
  }
}

/// The open tab: the kit pieces this job restyled, on the canvas.
class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.md),
        children: [
          Text(_tr('أين أنا', 'Where am I'), style: AppType.section(context)),
          AppSpace.gapSm,
          const Align(alignment: AlignmentDirectional.centerStart, child: ContextSwitcher()),
          AppSpace.gapMd,
          const Align(alignment: AlignmentDirectional.centerStart, child: ContextSwitcher(compact: true)),
          Padding(
            padding: AppSpace.sectionHead,
            child: Text(_tr('شارات', 'Badges'), style: AppType.section(context)),
          ),
          Row(children: [
            AttentionBadge(
              tabKey: AttentionTabs.chat,
              child: AppIconButton(icon: Icons.forum_rounded, tooltip: _tr('الرسائل', 'Messages'), onPressed: () {}),
            ),
            AppSpace.gapMd,
            const AppCountBadge(count: 7),
            AppSpace.gapMd,
            AppStatusBadge(label: _tr('نشط', 'Active'), tone: AppTone.success, dot: true),
          ]),
          Padding(
            padding: AppSpace.sectionHead,
            child: Text(_tr('اللغة', 'Language'), style: AppType.section(context)),
          ),
          AppCard(
            child: Column(children: [
              const AppLanguageTile(),
              AppSpace.gapSm,
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppLanguageSegmented(current: AppConfig.lang == 'en' ? 'ar' : 'en', onChanged: (_) {}),
              ),
            ]),
          ),
          AppSpace.gapLg,
          AppBlock(
            tone: AppBlockTone.peach,
            hero: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_tr('درس اليوم', "Today's lesson"), style: AppType.headline(context)),
              AppSpace.gapXs,
              Text(_tr('المتجهات في المستوى — ٤٥ دقيقة', 'Vectors in the plane — 45 min'), style: AppType.body(context)),
            ]),
          ),
        ],
      ),
    );
  }
}
