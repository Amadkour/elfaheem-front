// VISUAL review renders of the inbox page (lib/features/shared/inbox/inbox_page.dart): the inbox and the
// notifications on ONE page with tabs, the real page over the fake backend (test/ui/inbox_page_samples.dart), opened
// on each tab, at 390x844 and 1440x900, ar / en, light / dark, into test/visual/goldens/inbox_<tab>_*.png. Not a CI
// suite; compared by eye (times follow the clock).
//
//   flutter test test/visual/inbox_golden_test.dart --update-goldens [--plain-name notifications]
//   INBOX_ONLY=390_ar_light,1440_en_dark   renders only those variants
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/inbox/inbox_page.dart';
import 'package:flutter_education_app/features/shared/notification/notifications_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/inbox_page_samples.dart';
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
  // the app bar's back arrow is CupertinoIcons.back (package font)
  final cfg = jsonDecode(File('.dart_tool/package_config.json').readAsStringSync()) as Map<String, dynamic>;
  for (final p in (cfg['packages'] as List).cast<Map<String, dynamic>>()) {
    if (p['name'] != 'cupertino_icons') continue;
    final root = Uri.parse('${p['rootUri']}');
    final dir = root.isAbsolute ? root.toFilePath() : File('.dart_tool/${p['rootUri']}').absolute.path;
    final font = File('$dir/assets/CupertinoIcons.ttf');
    if (font.existsSync()) await load('packages/cupertino_icons/CupertinoIcons', [font.path]);
  }
}

final _shot = GlobalKey();

bool _wanted(String variant) {
  final only = Platform.environment['INBOX_ONLY'];
  return only == null || only.isEmpty || only.split(',').contains(variant);
}

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
      home: RepaintBoundary(
        key: _shot,
        child: ChangeNotifierProvider<NotificationsProvider>(create: (_) => NotificationsProvider(), child: child),
      ),
    ),
  );
}

double _hiddenExtent(WidgetTester tester) {
  var extra = 0.0;
  for (final e in find.byType(Scrollable).evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis != Axis.vertical || !s.position.hasContentDimensions) continue;
    extra = math.max(extra, s.position.maxScrollExtent);
  }
  return extra;
}

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _render(WidgetTester tester, String name, Widget Function() build) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          final variant = '${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}';
          if (!_wanted(variant)) continue;
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), dark: dark));
          await _frames(tester);
          for (var i = 0; i < 3; i++) {
            final extra = _hiddenExtent(tester);
            if (extra < 1) break;
            tester.view.physicalSize = Size(size.width, math.min(4000, tester.view.physicalSize.height + extra));
            await _frames(tester, 4);
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name $variant: $e');
          await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/${name}_$variant.png'));
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

void main() {
  late FakeApi api;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    api = FakeApi(inboxRoutes(), latency: const Duration(milliseconds: 20))..install();
  });
  tearDown(() => api.uninstall());

  for (final t in InboxTab.values) {
    testWidgets('inbox ${t.name}', (tester) async {
      await _render(tester, 'inbox_${t.name}', () => InboxPage(initial: t));
    });
  }

  testWidgets('inbox org (an organization\'s own inbox)', (tester) async {
    await _render(tester, 'inbox_org', () => InboxPage(orgId: 4, title: AppConfig.lang == 'ar' ? 'جامعة النيل الأهلية' : 'Nile National University'));
  });
}
