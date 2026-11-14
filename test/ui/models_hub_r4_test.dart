// AI Models page, OMR e2e round 3 (the hub fixes of omr/r4-hub):
//   * an estimate is rounded the way a person says it: 128 s is "about 2 min", not the "about 3 min" that rounding
//     up gave (hubDuration / hubSpan)
//   * two builds of one model (int8 / fp32) are told apart: the chips, the prompts and the notices carry the variant
//     ("Active: multilingual-e5-small · int8") whenever another model of the role shares the name
//   * Roll back asks first, naming what switches from → to and whether a rebuild is needed; Cancel sends nothing
//   * the Disk / RAM column keeps each size as one unbreakable left-to-right unit ("1.1 GB", never "1.1" … "GB")
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/core/models_hub/model_downloads.dart';
import 'package:flutter_education_app/core/models_hub/models_hub_api.dart';
import 'package:flutter_education_app/features/admin/models/ai_models_page.dart';
import 'package:flutter_education_app/features/admin/models/ai_models_sheets.dart';
import 'package:flutter_education_app/features/admin/models/ai_models_view.dart';
import 'package:flutter_education_app/features/admin/models/models_hub_text.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

Object? hub(String name) =>
    (jsonDecode(File('test/fixtures/payloads/models_hub/$name.json').readAsStringSync()) as Map<String, dynamic>)['payload'];

final _lri = String.fromCharCode(0x2066), _pdi = String.fromCharCode(0x2069), _nbsp = String.fromCharCode(0xA0);

/// [s] without the bidi isolates (what a reader sees).
String _plain(String s) => s.replaceAll(_lri, '').replaceAll(_pdi, '').replaceAll(String.fromCharCode(0x2068), '');

final _connected = ValueNotifier<bool>(false);
LiveStreamHandle _stream() => LiveStreamHandle(connected: _connected, bind: () {}, release: () {});

Future<void> _settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// [child] on a themed page (the kit's colours come from ThemeConfigScope), scrolling, in [rtl] or left to right.
Widget _host(Widget child, {bool rtl = false}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      theme: theme.materialTheme(dark: false),
      home: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  group('estimate rounding', () {
    test('128 s is about 2 min (rounding up said 3); seconds round to 5 / 10 under 90 s', () {
      expect(hubDuration(128), 'about 2 min');
      expect(hubDuration(129), 'about 2 min');
      expect(hubDuration(150), 'about 3 min');
      expect(hubDuration(305), 'about 5 min');
      expect(hubDuration(615), 'about 10 min');
      expect(hubDuration(3), 'about 3 s');
      expect(hubDuration(11), 'about 10 s');
      expect(hubDuration(43), 'about 45 s');
      expect(hubDuration(87), 'about 90 s');
      expect(hubDuration(90), 'about 2 min');
      expect(hubDuration(3725), 'about 1 h 2 min');
      expect(hubDuration(null), 'unknown');
      expect(hubSpan(19), '20 s');
      expect(hubSpan(145), '2 min');
      AppConfig.lang = 'ar';
      expect(hubDuration(128), 'نحو 2 د');
      expect(hubSpan(43), '45 ث');
    });

    test('the estimate texts: a range from one measured model, every vector cached', () {
      expect(reindexTimeText(HubReindex(estimate: const HubEstimate(basis: 'other_models', lowSeconds: 129, highSeconds: 310, models: ['p@int8']))),
          'between 2 min and 5 min (going by another model rebuilt here and both models\' test speeds)');
      expect(reindexTimeText(HubReindex(estimate: const HubEstimate(basis: 'cached', seconds: 6))),
          'about 6 s (every vector is already in the vector cache)');
    });
  });

  group('two builds of one model', () {
    final ov = HubOverview.fromJson(hub('overview_gen_rolled_back'));
    final emb = ov.role('embedding')!, gen = ov.role('generation')!;

    test('the variant comes from the version (the commit hash dropped), else the quantisation', () {
      expect(hubVariant('int8-761b726'), 'int8');
      expect(hubVariant('fp32-2c4055b'), 'fp32');
      expect(hubVariant('q4_k_m-d7f544e'), 'q4_k_m');
      expect(hubVariant('v1'), 'v1');
      expect(hubVariant('', 'int8 (dynamic, Xenova export)'), 'int8');
      expect(hubRefLabel('multilingual-e5-small@fp32-761b726'), 'multilingual-e5-small · fp32');
    });

    test('a name another model of the role shares carries its variant; a unique name stays plain', () {
      expect(hubModelLabel(emb.activeModel, role: emb, ref: emb.active), 'multilingual-e5-small · int8');
      expect(hubModelLabel(emb.byId(2), role: emb), 'multilingual-e5-small · fp32');
      expect(hubModelLabel(emb.byId(6), role: emb), 'multilingual-e5-base');
      expect(hubModelLabel(gen.activeModel, role: gen), 'gen-good');
      expect(hubModelLabel(null, ref: 'qwen3-1.7b@int4-3231b52'), 'qwen3-1.7b · int4');
      AppConfig.lang = 'ar';
      expect(hubModelLabel(emb.activeModel, role: emb), '${_lri}multilingual-e5-small · int8$_pdi');
    });

    testWidgets('the chips: "Active: multilingual-e5-small · int8"', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(AiModelsView(overview: ov)));
      await tester.pump();
      expect(find.textContaining('Active: multilingual-e5-small · int8'), findsOneWidget);
      expect(find.textContaining('Active: gen-good'), findsOneWidget);
      expect(find.textContaining('Previous: gen-later'), findsOneWidget);
    });
  });

  group('Roll back asks first', () {
    Future<(FakeApi, ModelDownloads, List<String>)> page(WidgetTester tester) async {
      final calls = <String>[];
      final api = FakeApi({
        'GET /api/v1/models/alerts': (_) => hub('alerts_none'),
        'GET /api/v1/models/downloads': (_) => hub('downloads_done'),
        'GET /api/v1/models/system': (_) => hub('system'),
        'GET /api/v1/models': (_) => hub(calls.isEmpty ? 'overview_gen_active' : 'overview_gen_rolled_back'),
        'POST /api/v1/models/roles/generation/rollback': (_) {
          calls.add('rollback');
          return hub('rollback');
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(api.uninstall);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await ApiClient().primeSession();
      final dl = ModelDownloads(stream: _stream);
      addTearDown(dl.dispose);
      final theme = ThemeConfigProvider(api: ApiClient());
      await tester.pumpWidget(ThemeConfigScope(
        provider: theme,
        child: MaterialApp(navigatorKey: navigatorKey, theme: theme.materialTheme(dark: false), home: AiModelsPage(downloads: dl, stream: _stream())),
      ));
      await _settle(tester);
      return (api, dl, calls);
    }

    Future<void> finish(WidgetTester tester, ModelDownloads dl) async {
      dl.unwatch();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }

    testWidgets('the confirm names from → to and the cost; Cancel sends nothing, Roll back sends the call', (tester) async {
      final (api, dl, calls) = await page(tester);
      final ov = HubOverview.fromJson(hub('overview_gen_active')).role('generation')!;
      final from = hubModelLabel(ov.activeModel, role: ov, ref: ov.active), to = hubModelLabel(ov.previousModel, role: ov, ref: ov.previous);
      final button = find.byKey(const ValueKey('rollback_generation'));
      await tester.ensureVisible(button);
      await _settle(tester, 3);
      await tester.tap(button);
      await _settle(tester);
      final message = 'Roll Generation back from $from to $to?\nNo rebuild is needed: the previous model serves at once.';
      expect(find.text(message), findsOneWidget);
      expect(calls, isEmpty, reason: 'nothing is sent before the confirm');
      await tester.tap(find.byKey(const ValueKey('app.confirm.cancel')));
      await _settle(tester);
      expect(find.text(message), findsNothing);
      expect(calls, isEmpty, reason: 'Cancel sends nothing');

      await tester.tap(button);
      await _settle(tester);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('app.confirm.ok')), matching: find.text('Roll back')));
      await _settle(tester);
      expect(calls, ['rollback']);
      expect(api.unmatched, isEmpty);
      await finish(tester, dl);
    });
  });

  group('Disk / RAM', () {
    testWidgets('each size is one unbreakable LTR unit (Arabic and English); no layout error', (tester) async {
      final ov = HubOverview.fromJson(hub('overview_gen_rolled_back'));
      for (final lang in const ['ar', 'en']) {
        AppConfig.lang = lang;
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_host(AiModelsView(overview: ov), rtl: lang == 'ar'));
        await tester.pump();
        final cells = [
          for (final w in tester.widgetList<Text>(find.byType(Text)))
            if ((w.data ?? '').contains(' / ') && RegExp(r'[MGK]B|—').hasMatch(w.data ?? '') && !(w.data ?? '').contains('/ s')) w.data!,
        ];
        expect(cells, isNotEmpty, reason: lang);
        for (final cell in cells) {
          final parts = cell.split(' / ');
          expect(parts, hasLength(2), reason: cell);
          for (final p in parts) {
            expect(p.contains(' '), isFalse, reason: 'a break inside "$p" ($lang)');
            if (p != '—') {
              expect(p.startsWith(_lri) && p.endsWith(_pdi), isTrue, reason: 'not an LTR unit: "$p" ($lang)');
              expect(_plain(p), contains(_nbsp));
            }
          }
        }
      }
      AppConfig.lang = 'ar';
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(child: AiModelsView(overview: ov)),
      );
    });
  });
}
