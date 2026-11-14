// VISUAL review renders of the organization dashboard's Insights section and command palette (D-103): realistic
// data (test/ui/org_insights_samples.dart, shaped like the real captures), real fonts, 390x844 and 1440x900, ar / en,
// light / dark, into test/visual/goldens/org_insights_*.png and org_palette_*.png. Not a CI suite; compared by eye.
// At 1440 the section sits in a 600 px column, as in the home's two-column desktop split.
//
//   flutter test test/visual/org_insights_golden_test.dart --update-goldens [--plain-name palette]
@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/org/insights/org_insights.dart';
import 'package:flutter_education_app/features/org/insights/org_insights_section.dart';
import 'package:flutter_education_app/features/org/org_command_palette.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/org_insights_samples.dart';
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

Widget _host(Widget child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return RepaintBoundary(
    key: _shot,
    child: ThemeConfigScope(
      provider: theme,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.materialTheme(dark: false),
        darkTheme: theme.materialTheme(dark: true),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
        home: Builder(
          builder: (context) => Scaffold(backgroundColor: context.colors.background, body: SafeArea(child: child)),
        ),
      ),
    ),
  );
}

Future<void> _render(WidgetTester tester, String name, Widget Function(Size size) build,
    {Future<void> Function(WidgetTester tester)? act}) async {
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
          await tester.pumpWidget(_host(build(size), dark: dark));
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (act != null) {
            await act(tester);
            for (var i = 0; i < 6; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

/// The section as it sits on the home: full width on a phone, a 600 px column on a desktop.
Widget _column(Size size, Widget child) => SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: size.width < 700
          ? child
          : Align(alignment: AlignmentDirectional.topStart, child: SizedBox(width: 600, child: child)),
    );

void main() {
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('insights', (tester) async {
    await _render(
      tester,
      'org_insights',
      (size) => _column(size, OrgInsightsView(data: sampleInsights(), selected: OrgPeriodKind.last30, onPick: (_) {}, onOpenLink: (_) {})),
    );
  });

  testWidgets('insights touched', (tester) async {
    await _render(
      tester,
      'org_insights_touched',
      (size) => _column(size, OrgInsightsView(data: sampleInsights(scoped: true, fewMetrics: true), selected: OrgPeriodKind.last30, onPick: (_) {})),
      act: (tester) async {
        final chart = find.byType(OrgInsightChart).first;
        final r = tester.getRect(chart);
        await tester.tapAt(Offset(r.left + r.width * 0.4, r.bottom - 10));
      },
    );
  });

  testWidgets('insights suggestions', (tester) async {
    final full = sampleInsights();
    final d = OrgInsights(
      period: full.period,
      terms: full.terms,
      metrics: [full.metric('completion')!, full.metric('grades')!, full.metric('pending')!],
      suggestions: full.suggestions,
    );
    await _render(
      tester,
      'org_insights_suggestions',
      (size) => _column(size, OrgInsightsView(data: d, selected: OrgPeriodKind.last30, onPick: (_) {}, onOpenLink: (_) {})),
    );
  });

  testWidgets('insights states', (tester) async {
    await _render(
      tester,
      'org_insights_states',
      (size) => _column(
        size,
        Column(children: [
          const OrgInsightsView(loading: true),
          const SizedBox(height: 24),
          OrgInsightsView(error: AppConfig.lang == 'ar' ? 'تعذّر الاتصال بالخادم' : 'Couldn\'t reach the server', onRetry: () {}),
        ]),
      ),
    );
  });

  testWidgets('palette', (tester) async {
    await _render(
      tester,
      'org_palette',
      (size) => Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showOrgCommandPalette(context,
                orgId: 1, pages: samplePalettePages(AppConfig.lang == 'ar'), search: (q) async => sampleSearch),
            child: const Text('open'),
          ),
        ),
      ),
      act: (tester) async {
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.enterText(find.byType(TextField), AppConfig.lang == 'ar' ? 'علوم' : 'com');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      },
    );
  });

  testWidgets('palette recent', (tester) async {
    await _render(
      tester,
      'org_palette_recent',
      (size) => SizedBox(
        height: size.height,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
            child: Material(
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Builder(
                builder: (context) => ColoredBox(
                  color: context.colors.cardBg,
                  child: OrgCommandPalettePanel(
                    controller: OrgPaletteController(pages: samplePalettePages(AppConfig.lang == 'ar'), recents: samplePaletteRecents),
                    onSelect: (_) {},
                    wide: size.width >= 700,
                    autofocus: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  });
}
