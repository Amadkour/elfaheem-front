// Exam grading model source on the AI Models page (D-252) over FakeApi: the role shares the generation model by
// default, the super admin switches it to its own model or off (PUT /models/roles/exam_grading/mode), an older server
// without `mode` shows no control, and the cards have no overflow at any size.
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
import 'package:flutter_education_app/features/admin/models/ai_models_view.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_education_app/utils/top_route_observer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

Object? hub(String name) =>
    (jsonDecode(File('test/fixtures/payloads/models_hub/$name.json').readAsStringSync()) as Map<String, dynamic>)['payload'];

/// The recorded overview plus the exam_grading row and the task, as the D-252 server sends them (built here so the
/// recorded fixtures stay as the backend captured them).
Map<String, dynamic> overviewWith({String? mode, String? active, String? sharedActive = 'qwen3-1.7b@int4-3231b52'}) {
  final base = Map<String, dynamic>.from(hub('overview') as Map);
  final roles = [for (final r in base['roles'] as List) Map<String, dynamic>.from(r as Map)];
  roles.removeWhere((r) => r['role'] == 'exam_grading');
  roles.add({
    'role': 'exam_grading', 'active': active, 'active_id': null, 'previous': null, 'previous_id': null, 'fallback': null, 'fallback_id': null,
    'pending': null, 'models': <Object>[],
    'limits': {'threads': 2, 'max_concurrency': 1, 'priority': 'grading', 'idle_unload_s': 600, 'ram_mb': 0},
    if (mode != null) ...{
      'mode': mode, 'shared_from': 'generation', 'shared_active': sharedActive,
      'effective': mode == 'shared' ? sharedActive : (mode == 'own' ? active : null),
    },
  });
  return {
    ...base,
    'roles': roles,
    'tasks': [
      {'task': 'exam_grading', 'roles': ['exam_grading', 'nli', 'embedding']},
    ],
  };
}

final _connected = ValueNotifier<bool>(false);
LiveStreamHandle _stream() => LiveStreamHandle(connected: _connected, bind: () {}, release: () {});

Future<void> _settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _app(Widget home) {
  final theme = ThemeConfigProvider(api: ApiClient());
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(navigatorKey: navigatorKey, theme: theme.materialTheme(dark: false), navigatorObservers: [topRouteObserver], home: home),
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

  test('the mode fields are parsed; an older server sends none', () {
    final ov = HubOverview.fromJson(overviewWith(mode: 'shared'));
    final r = ov.role('exam_grading')!;
    expect(kHubRoles.last, 'exam_grading');
    expect((r.mode, r.sharedFrom, r.sharedActive, r.effective), ('shared', 'generation', 'qwen3-1.7b@int4-3231b52', 'qwen3-1.7b@int4-3231b52'));
    expect(r.hasMode, isTrue);
    final old = HubOverview.fromJson(overviewWith()).role('exam_grading')!;
    expect((old.mode, old.sharedActive, old.effective), (null, null, null));
    expect(old.hasMode, isFalse);
  });

  for (final mode in const ['shared', 'own', 'off', null]) {
    testWidgets('the exam_grading card with mode $mode has no overflow', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AiModelsView(
            overview: HubOverview.fromJson(overviewWith(mode: mode, active: mode == 'own' ? 'grader-a@1' : null)),
            actions: AiModelsActions(onGradingMode: (_, _) {}, onLimits: (_) {}),
          ),
        ),
      );
    });
  }

  testWidgets('switching the source sends the mode and reloads', (tester) async {
    var mode = 'shared';
    final bodies = <Object?>[];
    final api = FakeApi({
      'GET /api/v1/models/alerts': (_) => hub('alerts_none'),
      'GET /api/v1/models/downloads': (_) => hub('downloads_done'),
      'GET /api/v1/models/system': (_) => hub('system'),
      'GET /api/v1/models': (_) => overviewWith(mode: mode),
      'PUT /api/v1/models/roles/exam_grading/mode': (o) {
        bodies.add(o.data);
        mode = (o.data as Map)['mode'] as String;
        return {'role': 'exam_grading', 'mode': mode, 'shared_from': 'generation'};
      },
    }, latency: const Duration(milliseconds: 20))
      ..install();
    addTearDown(api.uninstall);
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await ApiClient().primeSession();
    final dl = ModelDownloads(stream: _stream);
    addTearDown(dl.dispose);

    await tester.pumpWidget(_app(AiModelsPage(downloads: dl, stream: _stream())));
    await _settle(tester);
    final box = find.byKey(const ValueKey('grading_mode'));
    await tester.ensureVisible(box);
    await _settle(tester, 3);
    expect(find.text('Shared with the generation model'), findsWidgets);
    expect(find.textContaining('with no second copy in memory'), findsOneWidget);

    await tester.tap(box);
    await _settle(tester, 4);
    await tester.tap(find.text('Off').last);
    await _settle(tester);
    expect(bodies, [
      {'mode': 'off'},
    ]);
    expect(find.text('The grader does not consult a generation model'), findsOneWidget);
    expect(api.unmatched, isEmpty);

    dl.unwatch();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('an older server (no mode) shows no source control', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(Scaffold(
      body: SingleChildScrollView(
        child: AiModelsView(overview: HubOverview.fromJson(overviewWith()), actions: AiModelsActions(onGradingMode: (_, _) {})),
      ),
    )));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('grading_mode')), findsNothing);
    expect(find.text('Exam grading'), findsWidgets);
  });
}
