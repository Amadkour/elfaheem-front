// Cancel a question (D-245) and the item analysis (per-option bars, unused distractor, key_suspect).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_grading.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_grading_widgets.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_insights.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_insights_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

const _b = '/api/v1/exam';

Map<String, dynamic> _analytics({bool voided = false}) => {
      'state': 'ready', 'computed_at': '2026-11-04T10:00:00Z',
      'data': {
        'attempts': 20,
        'distribution': {'n': 20, 'mean': 60, 'median': 60, 'pass_rate': 0.7, 'histogram': [0, 1, 1, 2, 3, 4, 4, 3, 1, 1]},
        'items': [
          {
            'question_id': 9, 'type': 'mcq_single', 'points': 2, 'answered': 20, 'difficulty': 0.4, 'discrimination': -0.1, 'voided': voided,
            'flags': ['key_suspect', 'unused_distractor'], 'unused_distractors': ['d'],
            'option_stats': [
              {'key': 'a', 'label': 'Cairo', 'count': 6, 'share': 0.3, 'is_correct': true, 'upper_share': 0.2, 'lower_share': 0.4},
              {'key': 'b', 'label': 'Giza', 'count': 12, 'share': 0.6, 'is_correct': false, 'upper_share': 0.8, 'lower_share': 0.3},
              {'key': 'c', 'label': 'Luxor', 'count': 2, 'share': 0.1, 'is_correct': false, 'upper_share': 0.0, 'lower_share': 0.3},
              {'key': 'd', 'label': 'Aswan', 'count': 0, 'share': 0.0, 'is_correct': false, 'upper_share': 0.0, 'lower_share': 0.0},
            ],
          },
        ],
        'risk': <String, dynamic>{},
      },
    };

Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await _frames(tester, 2);
  await tester.tap(f);
  await _frames(tester);
}

Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });
  setUp(() => AppConfig.lang = 'en');

  test('item analysis parses the option rows, flags and the old map shape', () {
    final d = ExamAnalytics.fromJson(_analytics());
    final it = d.items.single;
    expect(it.optionStats.length, 4);
    expect(it.optionStats.first.isCorrect, isTrue);
    expect(it.optionStats[1].upperShare, 0.8);
    expect(it.unusedDistractors, ['d']);
    expect(it.options['b'], 12, reason: 'the count map is derived for older callers');
    expect(it.flags, ['key_suspect', 'unused_distractor']);
    expect(itemFlagText('key_suspect'), isNot('key_suspect'));
    expect(itemFlagExplain('unused_distractor'), isNotNull);
    expect(itemFlagExplain('too_hard'), isNull);
    final old = ItemStat.fromJson({'question_id': 1, 'options': {'a': 3}});
    expect(old.optionStats, isEmpty);
    expect(old.options['a'], 3);
    expect(ExamAnalytics.fromJson(_analytics(voided: true)).items.single.voided, isTrue);
  });

  test('void errors are plain', () {
    expect(voidErrorText('reason_required', 'x'), isNot('x'));
    expect(voidErrorText('weird', 'server text'), 'server text');
    expect(voidModeHint('remove'), isNot(voidModeHint('full_marks')));
  });

  testWidgets('analytics: bars, plain-language flags, cancel with a reason and a mode, then analytics refresh', (tester) async {
    Map<String, dynamic>? sent;
    var voided = false;
    var refreshed = 0;
    final fake = FakeApi({
      'GET $_b/exams/7/analytics': (_) => _analytics(voided: voided),
      'POST $_b/exams/7/analytics/refresh': (_) {
        refreshed++;
        return {'state': 'queued'};
      },
      'POST $_b/exams/7/questions/9/void': (o) {
        sent = Map<String, dynamic>.from(o.data is String ? jsonDecode(o.data as String) as Map : o.data as Map);
        voided = true;
        return {'voided': true, 'recalculated_attempts': 20};
      },
    }, latency: const Duration(milliseconds: 20))
      ..install();
    addTearDown(fake.uninstall);

    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(layoutHost(const ExamAnalyticsScreen(examId: 7, examTitle: 'Midterm'), scale: 1, scaffold: false));
    await _frames(tester);

    expect(find.byType(OptionBars), findsOneWidget);
    expect(find.textContaining('No student chose this wrong option'), findsOneWidget);
    expect(find.textContaining('chosen by more of the top scorers'), findsOneWidget);
    expect(find.text('Nobody chose it'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('item.void.9')));
    await _tap(tester, find.byKey(const ValueKey('void.mode.full_marks')));
    expect(find.textContaining('Every student gets the question'), findsOneWidget);
    // a too short reason is refused before anything is sent
    await tester.enterText(find.byKey(const ValueKey('void.reason')), 'x');
    await _tap(tester, find.byKey(const ValueKey('void.submit')));
    expect(find.textContaining('3 to 500'), findsOneWidget);
    expect(sent, isNull);

    await tester.enterText(find.byKey(const ValueKey('void.reason')), 'The key was wrong');
    await _tap(tester, find.byKey(const ValueKey('void.submit')));
    await _tap(tester, find.byKey(const ValueKey('app.confirm.ok')));
    expect(sent, {'reason': 'The key was wrong', 'mode': 'full_marks'});
    expect(refreshed, 1, reason: 'the analytics are recomputed after the recalculation');
    expect(find.byKey(const ValueKey('item.restore.9')), findsOneWidget);
    await _end(tester);
  });

  testWidgets('restore sends the reason only', (tester) async {
    Map<String, dynamic>? sent;
    final fake = FakeApi({
      'GET $_b/exams/7/analytics': (_) => _analytics(voided: true),
      'POST $_b/exams/7/analytics/refresh': (_) => {'state': 'queued'},
      'POST $_b/exams/7/questions/9/void/restore': (o) {
        sent = Map<String, dynamic>.from(o.data is String ? jsonDecode(o.data as String) as Map : o.data as Map);
        return {'voided': false};
      },
    }, latency: const Duration(milliseconds: 20))
      ..install();
    addTearDown(fake.uninstall);
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(layoutHost(const ExamAnalyticsScreen(examId: 7, examTitle: 'Midterm'), scale: 1, scaffold: false));
    await _frames(tester);

    await _tap(tester, find.byKey(const ValueKey('item.restore.9')));
    expect(find.byKey(const ValueKey('void.mode.remove')), findsNothing, reason: 'restoring asks only for a reason');
    await tester.enterText(find.byKey(const ValueKey('void.reason')), 'Cancelled by mistake');
    await _tap(tester, find.byKey(const ValueKey('void.submit')));
    await _tap(tester, find.byKey(const ValueKey('app.confirm.ok')));
    expect(sent, {'reason': 'Cancelled by mistake'});
    await _end(tester);
  });

  testWidgets('layout', (tester) async {
    await expectNoLayoutErrors(tester, () => VoidQuestionSheet(questionLabel: 'Question #9', onSubmit: (_, _) async => null));
    await expectNoLayoutErrors(tester, () => VoidQuestionSheet(questionLabel: 'Question #9', restoring: true, onSubmit: (_, _) async => null));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: OptionBars(options: ExamAnalytics.fromJson(_analytics()).items.single.optionStats, unused: const ['d'])));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: ExamAnalyticsBody(data: ExamAnalytics.fromJson(_analytics()), onVoid: (_) {}, onRestore: (_) {})));
  });
}
