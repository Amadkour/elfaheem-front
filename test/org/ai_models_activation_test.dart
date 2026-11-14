// The activation state machine over FakeApi: 202 downloading -> progress -> active; 409 checks_failed with the RAM
// table; 422 role_mismatch; the role travels in the request body; "Use the recommended models".
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/models_hub/hub_activation.dart';
import 'package:flutter_education_app/core/models_hub/models_hub_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'ai_models_fixtures.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });
  setUp(() => AppConfig.lang = 'en');

  Future<FakeApi> backend(Map<String, FakeHandler> routes) async {
    final api = FakeApi(routes, latency: const Duration(milliseconds: 1))..install();
    addTearDown(api.uninstall);
    await ApiClient().primeSession();
    return api;
  }

  const hub = ModelsHubApi();

  test('202 downloading -> progress from the downloads -> active', () async {
    Object? sentBody;
    await backend({
      'POST /api/v1/models/2/activate': (o) {
        sentBody = o.data;
        return const FakeResponse(202, {
          'stage': 'downloading',
          'download_id': 7,
          'pending': {'model_id': 2, 'ref': 'ollama:qwen3:14b-q4_K_M', 'stage': 'downloading', 'download_id': 7},
        });
      },
    });
    final out = await hubActivate(hub, 2, role: 'generation.exam');
    expect(sentBody, containsPair('role', 'generation.exam'));
    expect(out, isA<ActivationDownloading>());
    expect((out as ActivationDownloading).downloadId, 7);

    // 1) downloading with a live download row
    final pending = {'model_id': 2, 'ref': 'x', 'stage': 'downloading', 'download_id': 7};
    var ov = HubOverview.fromJson(aiTaskOverview(examPending: pending));
    final dl = HubDownload.fromJson({'id': 7, 'model_id': 2, 'status': 'running', 'bytes_done': 4000, 'bytes_total': 10000, 'percent': 40, 'speed_bps': 2e6, 'eta_s': 90})!;
    var st = hubActivationState(ov, {2: dl}, 2, 'generation.exam');
    expect(st.phase, ActivationPhase.downloading);
    expect(st.fraction, closeTo(0.4, 0.01));
    expect(st.etaS, 90);
    expect(st.busy, isTrue);

    // 2) the download is done, the hub tests it
    ov = HubOverview.fromJson(aiTaskOverview(examPending: {...pending, 'stage': 'testing'}));
    expect(hubActivationState(ov, const {}, 2, 'generation.exam').phase, ActivationPhase.testing);

    // 3) the hub switched by itself: the role's active_id is the model
    final raw = aiTaskOverview();
    final exam = (raw['roles'] as List).firstWhere((r) => (r as Map)['role'] == 'generation.exam') as Map<String, dynamic>;
    exam['active_id'] = 2;
    exam['active'] = 'ollama:qwen3:14b-q4_K_M';
    ov = HubOverview.fromJson(raw);
    expect(hubActivationState(ov, const {}, 2, 'generation.exam').phase, ActivationPhase.active);
    // ...and only for that role
    expect(hubActivationState(ov, const {}, 2, 'grading').phase, ActivationPhase.idle);
  });

  test('a failed pending step is the failed phase', () {
    final ov = HubOverview.fromJson(aiTaskOverview(examPending: {'model_id': 2, 'ref': 'x', 'stage': 'failed', 'reason': 'health_test_failed'}));
    expect(hubActivationState(ov, const {}, 2, 'generation.exam').phase, ActivationPhase.failed);
  });

  test('200 active is the active outcome', () async {
    await backend({'POST /api/v1/models/1/activate': (_) => {'stage': 'active', 'active': 'ollama:qwen3:4b'}});
    final out = await hubActivate(hub, 1, role: 'generation.chat');
    expect(out, isA<ActivationActive>());
  });

  test('409 checks_failed on the RAM of all roles carries the models and their RAM', () async {
    await backend({
      'POST /api/v1/models/2/activate': (_) => const FakeResponse(409, {
            'detail': {
              'code': 'checks_failed',
              'message': 'لا يناسب',
              'message_en': 'Does not fit',
              'checks': [
                {
                  'name': 'ram_all_roles',
                  'ok': false,
                  'need_mb': 15000,
                  'budget_mb': 12000,
                  'margin_mb': -3000,
                  'items': [
                    {'ref': 'ollama:qwen3:14b-q4_K_M', 'roles': ['generation.exam'], 'ram_mb': 11000},
                    {'ref': 'ollama:qwen3:4b', 'roles': ['generation.chat'], 'ram_mb': 3200},
                  ],
                },
                {'name': 'disk', 'ok': true},
              ],
            },
          }),
    });
    final out = await hubActivate(hub, 2, role: 'generation.exam');
    expect(out, isA<ActivationBlocked>());
    final ram = (out as ActivationBlocked).ram!;
    expect(ram.needMb, 15000);
    expect(ram.budgetMb, 12000);
    expect(ram.overMb, 3000);
    expect(ram.items.map((i) => i.ref), ['ollama:qwen3:14b-q4_K_M', 'ollama:qwen3:4b']);
    expect(out.failure.message, 'Does not fit');
  });

  test('409 checks_failed without a RAM check is blocked with no ram table', () async {
    await backend({
      'POST /api/v1/models/2/activate': (_) => const FakeResponse(409, {
            'detail': {'code': 'checks_failed', 'message_en': 'Disk is full', 'checks': [{'name': 'disk', 'ok': false}]},
          }),
    });
    final out = await hubActivate(hub, 2, role: 'grading');
    expect(out, isA<ActivationBlocked>());
    expect((out as ActivationBlocked).ram, isNull);
  });

  test('422 role_mismatch', () async {
    await backend({
      'POST /api/v1/models/9/activate': (_) => const FakeResponse(422, {
            'detail': {'code': 'role_mismatch', 'message': 'لا يصلح', 'message_en': 'This model cannot serve that role'},
          }),
    });
    final out = await hubActivate(hub, 9, role: 'generation.chat');
    expect(out, isA<ActivationRoleMismatch>());
    expect((out as ActivationRoleMismatch).failure.message, 'This model cannot serve that role');
  });

  test('other errors are an error outcome with the server words', () async {
    await backend({
      'POST /api/v1/models/5/activate': (_) => const FakeResponse(403, {'detail': {'code': 'super_admin_required', 'message_en': 'Super admins only'}}),
    });
    final out = await hubActivate(hub, 5, role: 'grading');
    expect(out, isA<ActivationError>());
    expect((out as ActivationError).failure.code, 'super_admin_required');
  });

  test('the recommended models: POST /models/defaults/apply', () async {
    final api = await backend({'POST /api/v1/models/defaults/apply': (_) => {'applied': 3}});
    final r = await hub.applyDefaults();
    expect(r['applied'], 3);
    expect(api.calls.single.key, 'POST /api/v1/models/defaults/apply');
  });
}
