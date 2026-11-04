// VISUAL review renders of the Finance hub (Super Admin redesign): Payouts (requests) and Payment history, Arabic,
// 390x844 and 1440x900, with real fonts, the production palette and realistic data from a FakeApi, into
// test/visual/goldens/fin_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/fin_payouts_payments_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_finance_page.dart';
import 'package:flutter_education_app/features/admin/admin_payouts_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../ui/admin_ds/fin_support.dart';
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

final _prodColors =
    jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>;

Widget _host(Widget child) {
  final theme = ThemeConfigProvider(api: ApiClient())..debugUseColors(_prodColors);
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: ThemeMode.light,
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(key: _shot, child: child),
    ),
  );
}

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    await _loadFonts();
  });

  Future<void> shoot(WidgetTester tester, String name, Widget Function() page) async {
    final api = FakeApi(finRoutes(withdrawals: 9, payments: 14), latency: const Duration(milliseconds: 30));
    final auth = await finSetUp(api);
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    try {
      AppConfig.lang = 'ar';
      for (final size in const [Size(390, 844), Size(1440, 900)]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_host(finProviders(auth, page())));
        await _frames(tester);
        final e = tester.takeException();
        expect(e, isNull, reason: '$name ${size.width.toInt()}: $e');
        await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/fin_${name}_${size.width.toInt()}_ar_light.png'));
      }
    } finally {
      AppConfig.lang = prevLang;
      await tester.pumpWidget(const SizedBox());
      debugDisableShadows = true;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  }

  testWidgets('Payouts: requests', (tester) async {
    await shoot(tester, 'payouts', () => const AdminPayoutsPage());
  });

  testWidgets('Payment history', (tester) async {
    await shoot(tester, 'payments', () => const AdminFinancePage(initialTab: 1));
  });
}
