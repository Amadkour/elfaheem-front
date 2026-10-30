// VISUAL review renders of listen-only (D-104), compared by eye like the other test/visual files (NOT a CI suite):
//
//   flutter test test/visual/vod_listen_golden_test.dart --update-goldens [--plain-name bar]
//
// → test/visual/goldens/vod_listen_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900, ar / en, with
//   the production theme (test/visual/fixtures/theme_production.json) and real fonts.
//   bar      the real VodListenLayer over a page of the app: the bar under the status bar, the page below it
//   states   the bar paused at 1.5×, opening the audio track (spinner), at the end (replay), while scrubbing
//   player   the real VideoPlayerScreen chrome with the "Listen" button in its top bar
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/media_focus.dart';
import 'package:flutter_education_app/design/app_kit.dart' show appText;
import 'package:flutter_education_app/features/shared/session/material/session_material_model.dart';
import 'package:flutter_education_app/features/shared/session/video/video_player_screen.dart';
import 'package:flutter_education_app/features/shared/session/video/vod_listen.dart';
import 'package:flutter_education_app/features/shared/session/video/vod_listen_bar.dart';
import 'package:flutter_education_app/features/shared/session/video/vod_listen_layer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart' show DurationRange;

import '../ui/vod_listen_test.dart' show FakeVc;
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

SessionMaterialModel _lecture() => SessionMaterialModel(
      id: 11,
      sessionId: 4,
      name: _tr('المحاضرة الثالثة — التكامل بالتجزئة وتطبيقاته', 'Lecture 3 — Integration by parts and its uses'),
      description: _tr('التفاضل والتكامل ٢ · د. سارة أحمد', 'Calculus II · Dr. Sara Ahmed'),
      type: SessionMaterialType.video,
      order: 0,
      createdAt: DateTime(2026),
      completed: false,
      urlHigh: 'https://media.test/high.mp4',
      urlMedium: 'https://media.test/medium.mp4',
      urlLow: 'https://media.test/low.mp4',
      rawUrlHigh: 'https://media.test/high.mp4',
      rawUrlMedium: 'https://media.test/medium.mp4',
      rawUrlLow: 'https://media.test/low.mp4',
    );

Widget _host(Widget Function(BuildContext) page, {required bool dark, required double statusBar, GlobalKey<NavigatorState>? nav}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  theme.debugUseColors(
      jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>);
  final rtl = AppConfig.lang == 'ar';
  final key = nav ?? GlobalKey<NavigatorState>();
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      navigatorKey: key,
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => RepaintBoundary(
        key: _shot,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(padding: EdgeInsets.only(top: statusBar), viewPadding: EdgeInsets.only(top: statusBar)),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: VodListenLayer(navigatorKey: key, child: w!),
          ),
        ),
      ),
      home: Builder(builder: page),
    ),
  );
}

/// A page of the app under the bar: a header and a few course rows.
Widget _appPage(BuildContext context) {
  final c = context.colors;
  final rows = [
    (_tr('التفاضل والتكامل ٢', 'Calculus II'), 0.62),
    (_tr('الفيزياء العامة', 'General physics'), 0.35),
    (_tr('مقدمة في البرمجة', 'Intro to programming'), 0.9),
    (_tr('الإحصاء الحيوي', 'Biostatistics'), 0.12),
  ];
  return Scaffold(
    backgroundColor: c.background,
    appBar: AppBar(
      backgroundColor: c.background,
      surfaceTintColor: c.background,
      title: Text(_tr('كورساتي', 'My courses'), style: appText(18, w: FontWeight.w600, c: c.textDark)),
      actions: [IconButton(onPressed: () {}, icon: Icon(Icons.notifications_none_rounded, color: c.textMedium))],
    ),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      for (final r in rows)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.divider),
          ),
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.menu_book_rounded, color: c.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.$1, style: appText(14.5, w: FontWeight.w600, c: c.textDark)),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: r.$2, color: c.primary, backgroundColor: c.divider, minHeight: 4),
              ]),
            ),
          ]),
        ),
    ]),
  );
}

void _startSession({Duration at = const Duration(minutes: 12, seconds: 3), double speed = 1.0}) {
  final m = _lecture();
  final vc = FakeVc(duration: const Duration(minutes: 48, seconds: 20), at: at, playing: true);
  vc.value = vc.value.copyWith(buffered: [DurationRange(Duration.zero, const Duration(minutes: 21))]);
  VodListenSession.instance.start(
    VodListenHandoff(controller: vc, material: m, current: m, variant: m.videoVariants.first, speed: speed),
    play: true,
  );
}

Future<void> _render(WidgetTester tester, String name, Widget Function(bool phone, bool dark) build,
    {void Function()? before}) async {
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
          MediaFocus.reset();
          VodListenSession.instance.debugReset();
          before?.call();
          await tester.pumpWidget(build(size.width < 600, dark));
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          await expectLater(find.byKey(_shot),
              matchesGoldenFile('goldens/vod_listen_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    VodListenSession.instance.debugReset();
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
    // package:floating (Android PiP) has no test side: its dispose call would fail after the render.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('floating'), (_) async => null);
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VodListenLayer.debugSignedIn = (_) => true;
  });
  tearDown(() => VodListenLayer.debugSignedIn = null);

  testWidgets('bar', (t) async {
    await _render(t, 'bar', (phone, dark) => _host(_appPage, dark: dark, statusBar: phone ? 44 : 0),
        before: () => _startSession(speed: 1.5));
  });

  testWidgets('states', (t) async {
    Widget bar(Duration at, {bool playing = false, bool busy = false, double speed = 1}) => VodListenBar(
          title: _lecture().name,
          position: at,
          duration: const Duration(minutes: 48, seconds: 20),
          buffered: 0.5,
          playing: playing,
          busy: busy,
          speed: speed,
          onPlayPause: () {},
          onSeekBy: (_) {},
          onSeekTo: (_) {},
          onExpand: () {},
          onClose: () {},
        );
    await _render(
      t,
      'states',
      (phone, dark) => _host(
        (context) => Scaffold(
          backgroundColor: context.colors.background,
          body: ListView(children: [
            bar(const Duration(minutes: 7, seconds: 41), speed: 1.5),
            const SizedBox(height: 16),
            bar(const Duration(minutes: 7, seconds: 41), playing: true, busy: true),
            const SizedBox(height: 16),
            bar(const Duration(minutes: 48, seconds: 20)),
          ]),
        ),
        dark: dark,
        statusBar: 0,
      ),
    );
  });

  testWidgets('player', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS; // no Android PiP timer in tests
    try {
      await _render(t, 'player', (phone, dark) {
        final m = _lecture();
        final vc = FakeVc(duration: const Duration(minutes: 48, seconds: 20), at: const Duration(minutes: 12, seconds: 3));
        return _host(
          (_) => VideoPlayerScreen(
            material: m,
            resume: VodListenHandoff(controller: vc, material: m, current: m, variant: m.videoVariants.last),
          ),
          dark: dark,
          statusBar: phone ? 44 : 0,
        );
      });
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
