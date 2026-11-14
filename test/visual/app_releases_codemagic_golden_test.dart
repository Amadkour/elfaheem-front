// Visual review renders of App versions through Codemagic (D-144), compared by eye like the other test/visual files
// (NOT a CI suite):
//
//   flutter test test/visual/app_releases_codemagic_golden_test.dart --update-goldens [--plain-name banner]
//
// → test/visual/goldens/codemagic_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900:
//   form_ready      New version, Android on our website, ready (Codemagic connected)
//   form_not_ready  Android on Google Play while the package is still com.example.* (Create off, what is missing)
//   form_no_setup   the web build while Codemagic itself is not set up
//   release_store   a Codemagic store release that went live (the store review note, the build link)
//   release_site    an Android website release uploading its files
//   list            the list with the Codemagic strip
//   banner_android  the sign-in-like page under the download strip AND the D-143 reload strip
//   sheet_android   Other downloads opened; sheet_ios the iPhone Add to Home Screen steps
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
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/core/release/web_release_watch.dart';
import 'package:flutter_education_app/features/admin/app_releases/app_release_detail.dart';
import 'package:flutter_education_app/features/admin/app_releases/app_release_form.dart';
import 'package:flutter_education_app/features/admin/app_releases/app_releases_models.dart';
import 'package:flutter_education_app/features/admin/app_releases/app_releases_page.dart';
import 'package:flutter_education_app/features/get_app/app_download_banner.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_releases_samples.dart';
import '../support/fake_api.dart';
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
final _stream = LiveStreamHandle(connected: ValueNotifier<bool>(true), bind: () {}, release: () {});

/// [around] wraps the Navigator (MaterialApp.builder), like main.dart's banners.
Widget _host(Widget child, {required bool dark, Widget Function(Widget navigator)? around}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => RepaintBoundary(
        key: _shot,
        child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: around == null ? w! : around(w!)),
      ),
      home: child,
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

Future<void> _render(
  WidgetTester tester,
  String name,
  Widget Function() build, {
  bool grow = true,
  Widget Function(Widget navigator)? around,
  Future<void> Function(WidgetTester)? act,
}) async {
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
          await tester.pumpWidget(_host(build(), dark: dark, around: around));
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (act != null) {
            await act(tester);
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          for (var i = 0; i < 6 && grow; i++) {
            final extra = _hiddenExtent(tester);
            if (extra < 1) break;
            tester.view.physicalSize = Size(size.width, math.min(5000, tester.view.physicalSize.height + extra));
            for (var j = 0; j < 4; j++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/codemagic_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

/// A stand-in for the sign-in page under the strips.
class _Page extends StatelessWidget {
  const _Page();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.school_rounded, size: 56, color: c.primary),
              const SizedBox(height: 16),
              const TextField(decoration: InputDecoration(labelText: 'Email or username')),
              const SizedBox(height: 12),
              const TextField(decoration: InputDecoration(labelText: 'Password')),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: () {}, child: const Text('Sign in'))),
            ]),
          ),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    await _loadFonts();
  });
  setUp(() => AppConfig.disableList = []);

  const b = '/api/v1/admin/app-releases';
  final latest = {for (final r in sampleReleases()) if (r.isLive) r.platform: r};

  testWidgets('form_ready', (t) async {
    await _render(t, 'form_ready',
        () => NewAppReleasePage(latest: latest, config: ReleaseConfig.fromJson(releaseConfigJson()), askPassword: (_) async => null));
  });

  testWidgets('form_not_ready', (t) async {
    await _render(
        t,
        'form_not_ready',
        () => NewAppReleasePage(
            latest: latest,
            initialChannel: 'store',
            config: ReleaseConfig.fromJson(releaseConfigJson(notReady: const {
              'android:store': ['package_name_example'],
            })),
            askPassword: (_) async => null));
  });

  testWidgets('form_no_setup', (t) async {
    await _render(
        t,
        'form_no_setup',
        () => NewAppReleasePage(
            latest: latest, initialPlatform: 'web', config: ReleaseConfig.fromJson(releaseConfigJson(codemagic: false)), askPassword: (_) async => null));
  });

  testWidgets('release_store', (t) async {
    final api = FakeApi({
      'GET $b/21': (_) => codemagicReleaseJson(
          channel: 'store', status: 'live', isLive: true, progress: 100, log: sampleLog(12), config: {'track': 'production', 'package_name': 'com.doubley.alfaheem'}),
      'GET $b/21/log': (_) => {'lines': []},
    }, latency: const Duration(milliseconds: 10))
      ..install();
    addTearDown(api.uninstall);
    await _render(t, 'release_store', () => AppReleaseDetailPage(id: 21, stream: _stream));
  });

  testWidgets('release_site', (t) async {
    final api = FakeApi({
      'GET $b/22': (_) => codemagicReleaseJson(id: 22, status: 'uploading', progress: 92, artifacts: codemagicApkArtifacts, log: sampleLog(30)),
      'GET $b/22/log': (_) => {'lines': []},
    }, latency: const Duration(milliseconds: 10))
      ..install();
    addTearDown(api.uninstall);
    await _render(t, 'release_site', () => AppReleaseDetailPage(id: 22, stream: _stream), grow: false);
  });

  testWidgets('list', (t) async {
    final api = FakeApi({
      'GET $b': (_) => releasesListJson(),
      'GET $b/config': (_) => releaseConfigJson(),
    }, latency: const Duration(milliseconds: 10))
      ..install();
    addTearDown(api.uninstall);
    await ApiClient().primeSession();
    await _render(t, 'list', () => AppReleasesPage(stream: _stream));
  });

  final downloads = parseAppDownloads(downloadsJson(), apiBase: 'https://alfheemacademy.com/api');
  AppDownloadsService service(GetAppOs os) =>
      AppDownloadsService(env: () => GetAppEnv(isWeb: true, os: os, iosSafari: os == GetAppOs.ios), fetch: () async => null, disabled: (_) => false)
        ..debugSet(env: GetAppEnv(isWeb: true, os: os, iosSafari: os == GetAppOs.ios), releases: downloads);

  Widget Function(Widget) strips(GetAppOs os, {bool reload = false}) {
    final watch = WebReleaseWatch(bus: LiveEvents.instance, running: ('1.4.0', 52), reload: () {});
    final s = service(os);
    return (nav) {
      if (reload) {
        watch.start();
        WidgetsBinding.instance.addPostFrameCallback((_) => LiveEvents.instance
            .emit(LiveEvents.appReleaseLive, {'platform': 'web', 'version': '1.4.1', 'build_number': 53, 'policy': 'recommended'}));
      }
      return WebReleaseBanner(enabled: true, watch: watch, child: AppDownloadBanner(enabled: true, service: s, child: nav));
    };
  }

  testWidgets('banner_android', (t) async {
    await _render(t, 'banner_android', () => const _Page(), around: strips(GetAppOs.android, reload: true), grow: false);
  });

  testWidgets('banner_windows', (t) async {
    await _render(t, 'banner_windows', () => const _Page(), around: strips(GetAppOs.windows), grow: false);
  });

  Future<void> openSheet(WidgetTester t) async {
    final ctx = navigatorKey.currentContext!;
    showAppDownloadsSheet(ctx, service: service(GetAppOs.android));
  }

  testWidgets('sheet_android', (t) async {
    await _render(t, 'sheet_android', () => const _Page(), around: strips(GetAppOs.android), grow: false, act: openSheet);
  });

  testWidgets('sheet_ios', (t) async {
    await _render(t, 'sheet_ios', () => const _Page(), around: strips(GetAppOs.ios), grow: false, act: (t) async {
      showAppDownloadsSheet(navigatorKey.currentContext!, service: service(GetAppOs.ios));
    });
  });
}
