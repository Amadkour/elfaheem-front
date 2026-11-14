// The per-task shapes of the model hub (FRONT_CONTRACTS "Models"): task roles, accuracy, speed, recommended, and the
// older server that has none of them.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/models_hub/hub_activation.dart';
import 'package:flutter_education_app/core/models_hub/models_hub_api.dart';
import 'package:flutter_education_app/features/admin/models/models_hub_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ai_models_fixtures.dart';

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('task roles, recommended and the per-role facts of a model', () {
    final ov = HubOverview.fromJson(aiTaskOverview());
    final chat = ov.role('generation.chat')!;
    expect(chat.task, 'chat');
    expect(chat.isTask, isTrue);
    expect(chat.recommended, 'ollama:qwen3:4b');
    expect(ov.role('embedding')!.isTask, isFalse);

    final m = chat.models.first;
    expect(m.roles, ['generation.chat', 'generation.exam', 'grading']);
    expect(m.usedIn['generation.chat'], ['active']);
    expect(m.accuracy['generation.chat']!.percent, 82);
    expect(m.accuracy['generation.chat']!.dataset, 'chat-ar-40');
    expect(m.accuracy['generation.chat']!.at, isNotNull);
    expect(m.speed!.value, 18.4);
    expect(m.speed!.ttftMs, 640);
    expect(m.speed!.measured, isTrue);
    expect(m.ramMb, 3200);
    expect(m.paramsB, 4.0);
    expect(m.context, 8192);
    expect(m.recommendedFor, ['generation.chat']);
    expect(chat.isRecommended(m), isTrue);
    expect(chat.isRecommended(chat.models.last), isFalse);
  });

  test('a model shared by tasks is active only where the role says so', () {
    final ov = HubOverview.fromJson(aiTaskOverview());
    final m = ov.role('generation.chat')!.models.first; // status "active" (global)
    expect(ov.role('generation.chat')!.isActiveHere(m), isTrue);
    expect(ov.role('generation.exam')!.isActiveHere(m), isFalse);
    expect(ov.role('generation.chat')!.statusOf(m), 'active');
    expect(ov.role('generation.exam')!.statusOf(m), 'ready'); // downloaded, not serving the exam task
  });

  test('an older server without task roles: nothing breaks, nothing is a task', () {
    final ov = HubOverview.fromJson({
      'roles': [
        {
          'role': 'generation',
          'active': 'qwen3',
          'active_id': 3,
          'limits': {},
          'models': [
            {'id': 3, 'role': 'generation', 'name': 'qwen3', 'ref': 'qwen3', 'status': 'active', 'ram_mb': 900},
          ],
        },
      ],
    });
    final r = ov.role('generation')!;
    expect(r.isTask, isFalse);
    expect(r.recommended, isNull);
    final m = r.models.single;
    expect(m.roles, isEmpty);
    expect(m.accuracy, isEmpty);
    expect(m.speed, isNull);
    expect(r.isActiveHere(m), isTrue);
    expect(r.statusOf(m), 'active');
  });

  test('an unmeasured speed and a missing score draw no line', () {
    expect(HubSpeed.fromJson({'value': null, 'ok': false})!.measured, isFalse);
    expect(hubSpeedLine(HubSpeed.fromJson({'value': null, 'ok': false})), '');
    expect(hubSpeedLine(null), '');
    expect(hubAccuracyLine(const HubAccuracy()), '');
    expect(hubSpeedLine(HubSpeed.fromJson({'value': 18.4, 'unit': 'tok/s', 'ttft_ms': 640, 'ok': true})), contains('18 tok/s'));
    expect(hubAccuracyLine(HubAccuracy.fromJson({'score': 0.824, 'dataset': 'chat-ar-40', 'at': '2026-11-03T10:00:00'})), allOf(contains('82%'), contains('chat-ar-40')));
  });

  test('role names exist for the task roles in both languages', () {
    for (final lang in ['ar', 'en']) {
      AppConfig.lang = lang;
      for (final r in ['generation.chat', 'generation.exam', 'grading']) {
        expect(hubRoleName(r), isNot(r));
        expect(hubRoleHint(r), isNotEmpty);
      }
    }
  });

  test('the RAM check of all roles is read with its items', () {
    final c = HubCheck.fromJson({
      'name': 'ram_all_roles',
      'ok': false,
      'need_mb': 15000,
      'budget_mb': 12000,
      'margin_mb': -3000,
      'items': [
        {'ref': 'ollama:qwen3:14b-q4_K_M', 'roles': ['generation.exam'], 'ram_mb': 11000},
        {'ref': 'ollama:qwen3:4b', 'roles': ['generation.chat', 'grading'], 'ram_mb': 3200},
      ],
      'reason': 'too much',
    });
    final ram = HubRamCheck.fromCheck(c);
    expect(ram.overMb, 3000);
    expect(ram.items.length, 2);
    expect(ram.items.first.roles, ['generation.exam']);
    expect(ram.items.last.ramMb, 3200);
  });
}
