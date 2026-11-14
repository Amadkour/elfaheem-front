// LoRA readiness on the Learning page (D-070): the stats' `lora` block and the `lora_ready` suggestion parsed (pure),
// and the readiness cards (progress, sources, last candidate's gate, the offline commands with copy buttons) at
// 320x640 and 1400x900, Arabic and English, textScaler 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/rag/rag_learning.dart';
import 'package:flutter_education_app/features/rag/rag_learning_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _cmds = [
  {'step': 'export', 'command': 'python -m mlops.learning.export_sft --task writer --out MODELS_DIR/_train/sft/writer-2026-11'},
  {'step': 'plan', 'command': 'python -m mlops.learning.train_lora --data MODELS_DIR/_train/sft/writer-2026-11 --dry-run'},
  {
    'step': 'train',
    'command': '.venv-train/Scripts/python -m mlops.learning.train_lora --data MODELS_DIR/_train/sft/writer-2026-11 --r 16 --alpha 32 '
        '--epochs 1 --lr 2e-4 --batch 1 --grad-accum 16 --threads 8',
  },
  {'step': 'evaluate', 'command': 'PYTHONUTF8=1 .venv312/Scripts/python -m mlops.learning.evaluate_writer --kind writer --model MODELS_DIR/writer/<lora-version>'},
  {'step': 'register', 'command': 'PYTHONUTF8=1 python scripts/learning/reranker_registry.py --kind writer promote <lora-version> --by <admin id>'},
  {'step': 'restart', 'command': ''},
];

final _statsJson = {
  'chat': {'votes': 10},
  'exam': {'items': 3},
  'lora': {
    'writer': {
      'ready': 312,
      'needed': 300,
      'reached': true,
      'by_source': {'chat': 250, 'qa': 62, 'correction': 0},
      'holdout': 31,
      'last_export_at': '2026-11-26T03:00:00+00:00',
      'last_candidate': {
        'id': 9,
        'kind': 'writer',
        'version': 'lora-20261128-1a2b3c4d-with-a-long-version-name',
        'status': 'candidate',
        'gate': {
          'passed': false,
          'failures': [
            'correctness 0.7 < the promoted 0.8 by 10.00 points (it may not drop)',
            'latency_p95_s 14 > the promoted 10 × 1.15 (40 % slower)',
            'faithfulness 0.8 < the promoted 0.9 by 10.00 points (at most 1 point(s) allowed)',
            'a fourth failure that is not shown',
          ],
        },
      },
    },
    'examgen': {'ready': 41, 'needed': 300, 'reached': false, 'by_source': {'exam_accept': 30, 'exam_edit': 11}, 'last_candidate': null},
    'last_export_at': '2026-11-26T03:00:00+00:00',
    'checked_at': '2026-11-25T03:00:00Z',
  },
};

final _sugs = suggestionsOf({
  'items': [
    {
      'id': 7,
      'kind': 'lora_ready',
      'status': 'open',
      'support': 312,
      'payload': {'task': 'writer', 'ready': 312, 'needed': 300, 'month': '2026-11', 'commands': _cmds},
    },
    {'id': 8, 'kind': 'lora_ready', 'status': 'accepted', 'payload': {'task': 'examgen', 'commands': _cmds}},
  ]
});

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('pure', () {
    test('the stats lora block', () {
      final l = LearningStats.fromJson(_statsJson).lora!;
      expect(l.kinds.map((k) => k.kind).toList(), ['writer', 'examgen']);
      final w = l.kinds.first;
      expect(w.ready, 312);
      expect(w.reached, isTrue);
      expect(w.progress, 1.0);
      expect(w.bySource.keys.toList(), ['chat', 'qa', 'correction']);
      expect(w.lastCandidate!.passed, isFalse);
      expect(w.lastCandidate!.failures.length, 4);
      final x = l.kinds.last;
      expect(x.reached, isFalse);
      expect(x.progress, closeTo(41 / 300, 1e-9));
      expect(x.lastCandidate, isNull);
      expect(l.lastExportAt, '2026-11-26T03:00:00+00:00');
    });

    test('absent, an error or an older server → null', () {
      expect(LearningStats.fromJson({'chat': {}}).lora, isNull);
      expect(LoraReadiness.fromJson({'error': 'OperationalError'}), isNull);
      expect(LoraReadiness.fromJson({'last_export_at': null}), isNull);
    });

    test('needed falls back to the export minimum', () {
      final k = LoraKindReadiness.fromJson('writer', {'ready': 30, 'needed': 0});
      expect(k.needed, loraNeededDefault);
      expect(k.progress, closeTo(0.1, 1e-9));
    });

    test('lora_ready suggestion: title, commands, the open one per kind', () {
      final s = loraSuggestionFor(_sugs, 'writer')!;
      expect(s.title, contains('312 / 300'));
      final cmds = loraCommandsOf(s);
      expect(cmds.length, 5, reason: 'the empty command is dropped');
      expect(cmds.first.step, 'export');
      expect(loraSuggestionFor(_sugs, 'examgen'), isNull, reason: 'an accepted one is not shown');
      expect(suggestionKinds, contains('lora_ready'));
      AppConfig.lang = 'ar';
      expect(suggestionKindLabel('lora_ready'), isNot('lora_ready'));
      expect(loraSourceLabel('exam_edit'), isNot('exam_edit'));
    });
  });

  group('layout', () {
    final lora = LearningStats.fromJson(_statsJson).lora!;

    testWidgets('readiness view with commands and a failed gate', (tester) async {
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(padding: const EdgeInsets.all(16), child: LoraReadinessView(lora: lora, suggestions: _sugs)));
    });

    testWidgets('a card without candidate or commands', (tester) async {
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: LoraReadinessCard(readiness: lora.kinds.last)));
    });

    testWidgets('copy hands the exact command over', (tester) async {
      final copied = <String>[];
      await expectNoLayoutErrors(
          tester,
          () => SingleChildScrollView(
              child: LoraReadinessCard(readiness: lora.kinds.first, commands: loraCommandsOf(_sugs.first), onCopy: copied.add)),
          act: (tester) async {
            await tester.ensureVisible(find.byIcon(Icons.copy_rounded).first);
            await tester.tap(find.byIcon(Icons.copy_rounded).first);
            await tester.pump();
          });
      expect(copied, isNotEmpty);
      expect(copied.first, startsWith('python -m mlops.learning.export_sft --task writer'));
    });
  });
}
