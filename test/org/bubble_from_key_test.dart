// A bubble correction started from the model answer (D-671), against the REAL engine reply recorded by back
// tests/exam_engine/e2e_bubble_from_key.py with BUBBLE_DUMP into test/fixtures/payloads/bubble/run_from_key.json:
// the run, what the model answer gave, and the banner that says it (no overflow at any size, both languages).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/paper/bubble/bubble_flow.dart';
import 'package:flutter_education_app/features/exams/paper/bubble/bubble_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> _fx(String name) => Map<String, dynamic>.from(jsonDecode(File('test/fixtures/payloads/bubble/$name.json').readAsStringSync()) as Map);

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('the run made from the model answer: own sheet, the key for every question it marks', () {
    final j = _fx('run_from_key');
    final run = BubbleRun.fromJson(j);
    expect(run.ownSheet, isTrue);
    expect(run.hasKey, isTrue);
    expect(run.questions, hasLength(60));
    expect(run.forms.single.key, hasLength(60));
    final read = BubbleKeyRead.fromJson(Map<String, dynamic>.from(j['key_read'] as Map));
    expect(read.questions, 60);
    expect(read.printed, 150);
    expect(read.keyed, 60);
    expect(read.check, isEmpty);
  });

  test('rows to check are parsed with their state and letters', () {
    final read = BubbleKeyRead.fromJson({
      'questions': 3, 'printed': 3, 'keyed': 1,
      'check': [
        {'n': 2, 'state': 'multiple', 'letters': ['A', 'C']},
        {'n': 3, 'state': 'blank', 'letters': []},
      ],
    });
    expect(read.check.map((x) => x.n), [2, 3]);
    expect(read.check.first.letters, ['A', 'C']);
    expect(read.check.last.state, 'blank');
  });

  testWidgets('the banner fits: all read, and many rows to check', (tester) async {
    final ok = BubbleKeyRead(questions: 100, printed: 150, keyed: 100, check: const []);
    final many = BubbleKeyRead(
      questions: 150,
      printed: 150,
      keyed: 130,
      check: [for (var n = 101; n <= 120; n++) BubbleKeyCheck(n: n, state: 'uncertain', letters: const [])],
    );
    for (final read in [ok, many]) {
      await expectNoLayoutErrors(tester, () => BubbleKeyReadBanner(read: read, onCheck: () {}));
    }
  });

  testWidgets('the banner says what to do, in both languages', (tester) async {
    final read = BubbleKeyRead(questions: 100, printed: 150, keyed: 98, check: [BubbleKeyCheck(n: 12, state: 'multiple', letters: const ['A', 'B'])]);
    await tester.pumpWidget(layoutHost(BubbleKeyReadBanner(read: read, onCheck: () {}), scale: 1.0));
    expect(find.textContaining('100 questions'), findsOneWidget);
    expect(find.textContaining('of 150 on the sheet'), findsOneWidget);
    expect(find.textContaining('12'), findsWidgets);
    expect(find.text('Check the key'), findsOneWidget);
    AppConfig.lang = 'ar';
    await tester.pumpWidget(layoutHost(BubbleKeyReadBanner(read: read, onCheck: () {}), scale: 1.0));
    expect(find.textContaining('100 سؤالًا'), findsOneWidget);
    expect(find.text('مراجعة المفتاح'), findsOneWidget);
  });
}
