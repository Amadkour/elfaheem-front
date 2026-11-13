// Visual review of accent2 candidates (D-860): the production palette (fixtures/theme_production.json) with only
// `accent2` swapped, drawn on the surfaces where accent2 shows (the home hero's gold glow, the gold highlight CTA,
// gold stat / KPI / ring / shortcut cards, gold badges, gradient glyphs), light and dark. Compared by eye:
//
//   flutter test test/visual/accent2_candidates_golden_test.dart --update-goldens
//
// → test/visual/goldens/accent2_<hex>_<light|dark>.png at 420×900.
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
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_screens_golden_test.dart' show pubspecFonts;

const _candidates = ['#C98A3D', '#D9A21B', '#D6A80E', '#C9A227', '#D46A4C', '#A23B72'];

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

/// The production colours with every accent2 occurrence (scalar and gradient stops) replaced by [hex].
Map<String, dynamic> _colors(String hex) {
  final raw = File('test/visual/fixtures/theme_production.json').readAsStringSync();
  return jsonDecode(raw.replaceAll('#C98A3D', hex)) as Map<String, dynamic>;
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
    AppConfig.disableList = [];
  });

  Widget host(String hex, bool dark) {
    final theme = ThemeConfigProvider(api: ApiClient())..debugUseColors(_colors(hex));
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
          home: RepaintBoundary(key: _shot, child: _Panel(hex: hex)),
        ),
      ),
    );
  }

  testWidgets('accent2 candidates', (tester) async {
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    try {
      AppConfig.lang = 'en';
      for (final hex in _candidates) {
        for (final dark in const [false, true]) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(420, 900);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(host(hex, dark));
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          await expectLater(find.byKey(_shot),
              matchesGoldenFile('goldens/accent2_${hex.substring(1)}_${dark ? 'dark' : 'light'}.png'));
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
  });
}

class _Panel extends StatelessWidget {
  const _Panel({required this.hex});

  final String hex;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const gap = SizedBox(height: 12);
    return Scaffold(
      backgroundColor: c.background,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Text('accent2 $hex', style: appText(15, w: FontWeight.w700, c: c.textDark)),
          gap,
          AppHero(
            title: 'Welcome, Sara',
            subtitle: '4 sessions today',
            icon: Icons.auto_awesome_rounded,
            stats: const [
              AppHeroStat(icon: Icons.local_fire_department_rounded, value: '12', label: 'Day streak'),
              AppHeroStat(icon: Icons.emoji_events_rounded, value: '5', label: 'Badges'),
            ],
          ),
          gap,
          AppButton.accent(label: 'Go live', icon: Icons.videocam_rounded, onPressed: () {}),
          gap,
          Row(children: [
            Expanded(
              child: AppStatCard(
                  icon: Icons.local_fire_department_rounded,
                  value: '12',
                  label: 'Day streak',
                  tone: AppBlockTone.gold,
                  footer: 'best 21',
                  delta: 0.12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppStatCard(
                  icon: Icons.menu_book_rounded, value: '8', label: 'Courses', tone: AppBlockTone.emerald),
            ),
          ]),
          gap,
          Row(children: [
            Expanded(
              child: AppRingStat(label: 'Top marks', value: '86%', progress: 0.86, tone: AppBlockTone.gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppShortcutTile(
                  icon: Icons.emoji_events_rounded, label: 'Achievements', onTap: () {}, tone: AppBlockTone.gold),
            ),
          ]),
          gap,
          AppKpiSpark(
              label: 'Points',
              value: '1,240',
              values: const [3, 5, 4, 7, 6, 9, 11],
              icon: Icons.star_rounded,
              tone: AppBlockTone.gold),
          gap,
          Wrap(spacing: 8, runSpacing: 8, children: const [
            AppStatusBadge(label: 'Top mark', tone: AppTone.gold, icon: Icons.emoji_events_rounded),
            AppStatusBadge(label: 'Streak', tone: AppTone.gold, dot: true),
            AppStatusBadge(label: 'Warning', tone: AppTone.warning),
            AppStatusBadge(label: 'Failed', tone: AppTone.danger),
            AppStatusBadge(label: 'Passed', tone: AppTone.success),
          ]),
          gap,
          Row(children: [
            const AppGradientIcon(Icons.school_rounded, size: 34),
            const SizedBox(width: 12),
            Icon(Icons.star_rounded, color: c.accent2, size: 30),
            const SizedBox(width: 6),
            Text('Gold ink', style: appText(14, w: FontWeight.w600, c: c.accent2)),
            const SizedBox(width: 12),
            Container(width: 28, height: 28, decoration: BoxDecoration(color: c.accent2Base, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Container(width: 28, height: 28, decoration: BoxDecoration(color: c.warningBase, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Container(width: 28, height: 28, decoration: BoxDecoration(color: c.dangerBase, shape: BoxShape.circle)),
          ]),
        ],
      ),
    );
  }
}
