// The AI Models page and the floating download bar (D-152) over FakeApi, answering with the hub's REAL replies
// (test/fixtures/payloads/models_hub/, recorded from ../back tests/modelhub/e2e_modelhub.py):
//   * Activate on a downloaded model → the health test passed (ready_to_confirm) → "Activate this model for
//     Generation?" with the test's result → Activate sends {confirm: true}
//   * Embedding: the prompt carries the index warning and the server's estimate; Later sends {confirm, reindex: later}
//   * Delete on the active model shows the server's own words ("This model is active. Activate another model first.")
//   * the floating bar shows % · speed · time left, stays above a pushed route, follows a model_download event without
//     a request, minimises to a pill, and opens the AI Models page on a tap
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/core/models_hub/model_downloads.dart';
import 'package:flutter_education_app/features/admin/models/ai_models_page.dart';
import 'package:flutter_education_app/features/admin/models/ai_models_sheets.dart';
import 'package:flutter_education_app/features/admin/models/model_download_bar.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_education_app/utils/top_route_observer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

Object? hub(String name) =>
    (jsonDecode(File('test/fixtures/payloads/models_hub/$name.json').readAsStringSync()) as Map<String, dynamic>)['payload'];

final _connected = ValueNotifier<bool>(false);
LiveStreamHandle _stream() => LiveStreamHandle(connected: _connected, bind: () {}, release: () {});

Future<void> _settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls [f] into the middle of the page and lets the scroll land.
Future<void> _reveal(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await _settle(tester, 3);
}

Widget _app(Widget home, {ModelDownloads? host}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      navigatorKey: navigatorKey,
      theme: theme.materialTheme(dark: false),
      navigatorObservers: [topRouteObserver],
      builder: host == null
          ? null
          : (context, child) => ModelDownloadsHost(navigatorKey: navigatorKey, downloads: host, signedInRole: 'super-admin', child: child!),
      home: home,
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

  Future<(FakeApi, ModelDownloads)> backend(WidgetTester tester, Map<String, FakeHandler> routes, {Size size = const Size(1440, 900)}) async {
    final api = FakeApi({
      'GET /api/v1/models/alerts': (_) => hub('alerts_none'),
      'GET /api/v1/models/downloads': (_) => hub('downloads_done'),
      'GET /api/v1/models/system': (_) => hub('system'),
      ...routes,
    }, latency: const Duration(milliseconds: 20))
      ..install();
    addTearDown(api.uninstall);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await ApiClient().primeSession();
    final dl = ModelDownloads(stream: _stream);
    addTearDown(dl.dispose);
    return (api, dl);
  }

  Future<void> finish(WidgetTester tester, ModelDownloads dl) async {
    dl.unwatch();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5)); // the notices' timers
  }

  testWidgets('activate → the health test passed → "Activate this model for Generation?" → Activate confirms', (tester) async {
    var stage = 0;
    final bodies = <Object?>[];
    final (api, dl) = await backend(tester, {
      'GET /api/v1/models': (_) => hub(['overview_before_gen_activate', 'overview_gen_ready', 'overview_gen_active'][stage]),
      'POST /api/v1/models/23/activate': (o) {
        bodies.add(o.data);
        final confirm = o.data is Map && (o.data as Map)['confirm'] == true;
        stage = confirm ? 2 : 1;
        return hub(confirm ? 'activate_confirm' : 'activate_ready');
      },
    });
    await tester.pumpWidget(_app(AiModelsPage(downloads: dl, stream: _stream())));
    await _settle(tester);

    final activate = find.byKey(const ValueKey('activate_23'));
    await _reveal(tester, activate);
    await tester.tap(activate);
    await _settle(tester);
    // ignore: avoid_print
    expect(find.text('Activate this model for Generation?'), findsOneWidget);
    expect(find.textContaining('Health test: Passed · 500 / s · '), findsOneWidget);
    expect(find.text('Active now: qwen3-1.7b — kept so you can roll back.'), findsOneWidget);
    expect(find.byKey(const ValueKey('embedding_warning')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('confirm_activate')));
    await _settle(tester);
    expect(bodies, [<String, dynamic>{}, {'confirm': true}]);
    expect(find.text('gen-good is now active for Generation — qwen3-1.7b is kept for rollback.'), findsOneWidget);
    expect(api.unmatched, isEmpty);
    await finish(tester, dl);
  });

  testWidgets('embedding: the prompt warns that the RAG index must be rebuilt, with the estimate; Later is sent', (tester) async {
    var stage = 0;
    final bodies = <Object?>[];
    final (_, dl) = await backend(tester, {
      'GET /api/v1/models': (_) => hub(['overview_before_emb_activate', 'overview_emb_ready', 'overview_reindex_later'][stage]),
      'POST /api/v1/models/38/activate': (o) {
        bodies.add(o.data);
        final confirm = o.data is Map && (o.data as Map)['confirm'] == true;
        stage = confirm ? 2 : 1;
        return hub(confirm ? 'reindex_later' : 'embedding_activate_ready');
      },
    });
    await tester.pumpWidget(_app(AiModelsPage(downloads: dl, stream: _stream())));
    await _settle(tester);
    final activate = find.byKey(const ValueKey('activate_38'));
    await _reveal(tester, activate);
    await tester.tap(activate);
    await _settle(tester);

    expect(find.text('Activate this model for Embedding?'), findsOneWidget);
    expect(find.byKey(const ValueKey('embedding_warning')), findsOneWidget);
    expect(find.text('This changes how documents are indexed. The RAG index must be rebuilt. Rebuild now in the background or later?'),
        findsOneWidget);
    expect(find.text('1230 items (1200 chunks + 30 saved answers) · time not known yet — measured on this model\'s first rebuild here'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reindex_now')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reindex_later')));
    await _settle(tester);
    expect(bodies, [<String, dynamic>{}, {'confirm': true, 'reindex': 'later'}]);
    expect(find.textContaining('The switch waits for the index rebuild'), findsOneWidget);
    await finish(tester, dl);
  });

  testWidgets('embedding, vectors already built (B6 round 2): no rebuild warning, a plain Activate switches at once', (tester) async {
    var stage = 0;
    final bodies = <Object?>[];
    final (api, dl) = await backend(tester, {
      'GET /api/v1/models': (_) => hub(['overview_before_kept_activate', 'overview_vectors_ready', 'overview_vectors_ready'][stage]),
      'POST /api/v1/models/43/activate': (o) {
        bodies.add(o.data);
        final confirm = o.data is Map && (o.data as Map)['confirm'] == true;
        stage = confirm ? 2 : 1;
        return hub(confirm ? 'activate_vectors_ready_confirm' : 'embedding_activate_vectors_ready');
      },
    });
    await tester.pumpWidget(_app(AiModelsPage(downloads: dl, stream: _stream())));
    await _settle(tester);
    final activate = find.byKey(const ValueKey('activate_43'));
    await _reveal(tester, activate);
    await tester.tap(activate);
    await _settle(tester);

    expect(find.text('Activate this model for Embedding?'), findsOneWidget);
    expect(find.byKey(const ValueKey('embedding_warning')), findsNothing);
    expect(find.byKey(const ValueKey('reindex_now')), findsNothing);
    expect(find.byKey(const ValueKey('vectors_ready')), findsOneWidget);
    expect(find.textContaining('already built for every document (1200 chunks + 30 saved answers)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('confirm_activate')));
    await _settle(tester);
    expect(bodies, [<String, dynamic>{}, {'confirm': true}]);
    expect(find.textContaining('emb-kept is now active for Embedding'), findsOneWidget);
    expect(api.unmatched, isEmpty);
    await finish(tester, dl);
  });

  testWidgets('a waiting switch whose vectors turned out built: Rebuild now answers active, and the notice says no rebuild ran', (tester) async {
    final (api, dl) = await backend(tester, {
      'GET /api/v1/models': (_) => hub('overview_reindex_later'),
      'POST /api/v1/models/roles/embedding/reindex': (_) => hub('activate_vectors_ready_confirm'),
    });
    await tester.pumpWidget(_app(AiModelsPage(downloads: dl, stream: _stream())));
    await _settle(tester);
    final rebuild = find.text('Rebuild now');
    await _reveal(tester, rebuild);
    await tester.tap(rebuild);
    await _settle(tester);
    expect(find.text('emb-new is now active for Embedding — no rebuild was needed.'), findsOneWidget);
    expect(find.textContaining('rebuild started in the background'), findsNothing);
    expect(api.unmatched, isEmpty);
    await finish(tester, dl);
  });

  testWidgets('Arabic: the embedding warning in Arabic', (tester) async {
    AppConfig.lang = 'ar';
    expect(embeddingWarningText(), 'هذا يغيّر طريقة فهرسة المستندات. يجب إعادة بناء فهرس المستندات (RAG). إعادة البناء الآن في الخلفية أم لاحقاً؟');
  });

  testWidgets('Delete on the active model shows the server\'s message', (tester) async {
    final (_, dl) = await backend(tester, {
      'GET /api/v1/models': (_) => hub('overview_gen_rolled_back'),
      'DELETE /api/v1/models/23': (_) => FakeResponse(409, hub('delete_active')),
    });
    await tester.pumpWidget(_app(AiModelsPage(downloads: dl, stream: _stream())));
    await _settle(tester);
    final menu = find.byKey(const ValueKey('menu_23'));
    await _reveal(tester, menu);
    await tester.tap(menu);
    await _settle(tester, 4);
    await tester.tap(find.text('Delete').last);
    await _settle(tester);
    expect(find.text('This model is active. Activate another model first.'), findsOneWidget);
    await finish(tester, dl);
  });

  testWidgets('the floating bar: % · speed · time left, above a pushed route, live without a request, pill, opens the page',
      (tester) async {
    final (api, dl) = await backend(tester, {
      'GET /api/v1/models/downloads': (_) => hub('downloads_running'),
      'GET /api/v1/models': (_) => hub('overview_downloading'),
    }, size: const Size(390, 844));
    final prev = ModelDownloads.instance;
    ModelDownloads.instance = dl; // the page the bar opens reads the same rows
    addTearDown(() => ModelDownloads.instance = prev);
    await tester.pumpWidget(_app(const Scaffold(body: Center(child: Text('home'))), host: dl));
    await _settle(tester);

    final line = find.byKey(const ValueKey('model_download_line'));
    expect(line, findsOneWidget);
    expect(tester.widget<Text>(line).data, 'Downloading… 18% · 259 KB/s · 19 s left');
    expect(find.text('gen-next'), findsOneWidget);

    navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Center(child: Text('second page')))));
    await _settle(tester);
    expect(find.text('second page'), findsOneWidget);
    expect(line, findsOneWidget, reason: 'the bar stays while moving around the app');

    // a live progress event moves the bar in place: no request for it (the stream is up: the fallback poll is slow)
    _connected.value = true;
    addTearDown(() => _connected.value = false);
    await _settle(tester, 2);
    final before = api.calls.where((c) => c.path == '/api/v1/models/downloads').length;
    final events = (hub('live_events') as List).cast<Map<String, dynamic>>();
    final last = events.lastWhere((e) => e['event'] == LiveEvents.modelDownload && (e['data'] as Map)['status'] == 'running');
    final data = Map<String, dynamic>.from(last['data'] as Map);
    LiveEvents.instance.emit(LiveEvents.modelDownload, data);
    await _settle(tester, 2);
    expect(tester.widget<Text>(line).data, startsWith('Downloading… ${(data['percent'] as num).floor()}%'));
    expect(api.calls.where((c) => c.path == '/api/v1/models/downloads').length, before);

    await tester.tap(find.bySemanticsLabel('Minimise'));
    await _settle(tester, 4);
    expect(find.byKey(const ValueKey('model_download_pill')), findsOneWidget);
    expect(line, findsNothing);
    await tester.tap(find.byKey(const ValueKey('model_download_pill')));
    await _settle(tester, 4);

    await tester.tap(find.byKey(const ValueKey('model_download_card')));
    await _settle(tester);
    expect(find.text('AI Models'), findsOneWidget);
    await finish(tester, dl);
  });
}
