// Visual review renders of the super admin's AI Models page and the floating download bar (D-152), compared by eye
// like the other test/visual files (NOT a CI suite):
//
//   flutter test test/visual/models_hub_golden_test.dart --update-goldens [--plain-name page]
//
// → test/visual/goldens/models_hub_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900, from the hub's
// real replies (test/fixtures/payloads/models_hub/):
//   page        the real page over FakeApi: a generation model downloading (the row's progress and the floating bar)
//   pending     the embedding role waiting for the confirm, generation's failed health test strip
//   prompt      "Activate this model for Embedding?" with the index warning and the estimate
//   history     the change log
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
import 'package:flutter_education_app/core/models_hub/model_downloads.dart';
import 'package:flutter_education_app/core/models_hub/models_hub_api.dart';
import 'package:flutter_education_app/features/admin/models/ai_models_page.dart';
import 'package:flutter_education_app/features/admin/models/ai_models_sheets.dart';
import 'package:flutter_education_app/features/admin/models/ai_models_view.dart';
import 'package:flutter_education_app/features/admin/models/model_download_bar.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'home_screens_golden_test.dart' show pubspecFonts;

Object? hub(String name) =>
    (jsonDecode(File('test/fixtures/payloads/models_hub/$name.json').readAsStringSync()) as Map<String, dynamic>)['payload'];

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
final _connected = ValueNotifier<bool>(true);
LiveStreamHandle _stream() => LiveStreamHandle(connected: _connected, bind: () {}, release: () {});

Widget _host(Widget child, {required bool dark, ModelDownloads? bar}) {
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
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: bar == null ? w! : ModelDownloadsHost(navigatorKey: navigatorKey, downloads: bar, signedInRole: 'super-admin', child: w!),
        ),
      ),
      home: child,
    ),
  );
}

Widget _framed(Widget body) => BasePage(
      useWebCard: true,
      maxWith: 1240,
      enableFooterWidget: false,
      child: SafeArea(
        child: Column(children: [
          ScreenAppBar(title: AppConfig.lang == 'ar' ? 'نماذج الذكاء الاصطناعي' : 'AI Models'),
          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: body)),
        ]),
      ),
    );

double _hiddenExtent(WidgetTester tester) {
  var extra = 0.0;
  for (final e in find.byType(Scrollable).evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis != Axis.vertical || !s.position.hasContentDimensions) continue;
    extra = math.max(extra, s.position.maxScrollExtent);
  }
  return extra;
}

Future<void> _render(WidgetTester tester, String name, Widget Function() build, {ModelDownloads Function()? bar, bool grow = true}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          final dl = bar?.call();
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), dark: dark, bar: dl));
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          for (var i = 0; i < 6 && grow; i++) {
            final extra = _hiddenExtent(tester);
            if (extra < 1) break;
            tester.view.physicalSize = Size(size.width, math.min(6000, tester.view.physicalSize.height + extra));
            for (var j = 0; j < 4; j++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/models_hub_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
          dl?.unwatch();
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

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    await _loadFonts();
  });
  setUp(() => AppConfig.disableList = []);

  testWidgets('page', (t) async {
    final api = FakeApi({
      'GET /api/v1/models': (_) => hub('overview_downloading'),
      'GET /api/v1/models/alerts': (_) => hub('alerts'),
      'GET /api/v1/models/system': (_) => hub('system'),
      'GET /api/v1/models/downloads': (_) => hub('downloads_running'),
    }, latency: const Duration(milliseconds: 10))
      ..install();
    addTearDown(api.uninstall);
    await ApiClient().primeSession();
    final dls = <ModelDownloads>[];
    addTearDown(() {
      for (final d in dls) {
        d.dispose();
      }
    });
    ModelDownloads make() {
      final d = ModelDownloads(stream: _stream);
      dls.add(d);
      return d;
    }

    late ModelDownloads current;
    await _render(t, 'page', () => AiModelsPage(downloads: current, stream: _stream()), bar: () => current = make());
  });

  testWidgets('pending', (t) async {
    final emb = HubOverview.fromJson(hub('overview_emb_ready'));
    final gen = HubOverview.fromJson(hub('overview_gen_failed'));
    final ov = HubOverview([emb.role('embedding')!, gen.role('generation')!, ...emb.roles.where((r) => r.role != 'embedding' && r.role != 'generation')]);
    await _render(
        t,
        'pending',
        () => _framed(AiModelsView(
              overview: ov,
              system: HubSystem.fromJson(hub('system')),
              actions: AiModelsActions(
                onDownload: (_) {},
                onActivate: (_) {},
                onFallback: (_, _) {},
                onTest: (_) {},
                onDelete: (_) {},
                onRollback: (_) {},
                onLimits: (_) {},
                onReview: (_) {},
                onCancelPending: (_) {},
              ),
            )));
  });

  testWidgets('prompt', (t) async {
    final p = HubStep.fromJson(hub('embedding_activate_ready')).pending!;
    await _render(
      t,
      'prompt',
      () => Scaffold(
        backgroundColor: Colors.black54,
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 700),
            child: Builder(
              builder: (context) => Material(
                color: context.colors.cardBg,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
                child: SafeArea(top: false, child: ActivatePrompt(role: 'embedding', model: 'emb-new', current: 'emb-base', test: p.test, reindex: p.reindex)),
              ),
            ),
          ),
        ),
      ),
      grow: false,
    );
  });

  testWidgets('history', (t) async {
    final audit = [for (final a in (hub('audit_generation') as Map)['audit'] as List) HubAudit.fromJson(a as Map<String, dynamic>)];
    await _render(t, 'history', () => _framed(AiModelsHistory(audit: audit, overview: HubOverview.fromJson(hub('overview')), me: 1)));
  });
}
