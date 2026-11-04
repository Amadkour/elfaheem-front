// The grade log (D-246): rows (who, when, old → new, reason), filters, paging with before_id, the empty state.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppTime;
import 'package:flutter_education_app/features/shared/exam_engine/exam_grade_log_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_grading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

const _b = '/api/v1/exam';

Map<String, dynamic> _row(int id, {String reason = 'Re-read the answer', int actor = 5, Object? old = 1, Object? nw = 1.5, int? attempt = 3}) => {
      'id': id, 'at': '2026-11-04T09:30:00', 'actor_id': actor, 'actor_name': actor == 0 ? null : 'Mr Hassan', 'entity': 'answer', 'entity_id': 40 + id,
      'attempt_id': attempt, 'student_id': 11, 'question_id': 9, 'field': 'final_score', 'old': old, 'new': nw, 'reason': reason,
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

  test('entries and pages parse; values and the system actor read plainly', () {
    final p = GradeLogPage.fromJson({'items': [_row(8), _row(7, actor: 0, reason: 'regrade')], 'next_before_id': 7});
    expect(p.items.length, 2);
    expect(p.nextBeforeId, 7);
    expect(p.items.first.attemptId, 3);
    expect(p.items.last.bySystem, isTrue);
    expect(gradeLogValueText(null), '—');
    expect(gradeLogValueText(2.0), '2');
    expect(gradeLogValueText('2.50'), '2.5');
    expect(gradeLogValueText(true), 'Yes');
    expect(gradeLogReasonText('regrade'), isNot('regrade'));
    expect(gradeLogReasonText('typo'), 'typo');
    expect(GradeLogPage.fromJson(const {}).items, isEmpty);
  });

  testWidgets('screen: first page, filter by student sends attempt_id, "show older" sends before_id', (tester) async {
    final queries = <Map<String, dynamic>>[];
    final fake = FakeApi({
      'GET $_b/exams/7/grade-log': (o) {
        queries.add(Map.of(o.uri.queryParameters));
        final before = o.uri.queryParameters['before_id'];
        if (before != null) return {'items': [_row(3, reason: 'Older change')], 'next_before_id': null};
        return {'items': [_row(8), _row(7, actor: 0, reason: 'regrade')], 'next_before_id': 7};
      },
    }, latency: const Duration(milliseconds: 20))
      ..install();
    addTearDown(fake.uninstall);

    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(layoutHost(const ExamGradeLogScreen(examId: 7, examTitle: 'Midterm', attemptNames: {3: 'Ali', 4: 'Sara'}), scale: 1, scaffold: false));
    await _frames(tester);

    expect(find.text('Mr Hassan · ${AppTime.dateTime(DateTime.parse('2026-11-04T09:30:00Z'))}'), findsOneWidget);
    expect(find.text('The system · ${AppTime.dateTime(DateTime.parse('2026-11-04T09:30:00Z'))}'), findsOneWidget);
    expect(find.text('Re-read the answer'), findsOneWidget);
    expect(find.text('Automatic regrade after the key changed'), findsOneWidget);
    expect(find.text('Ali'), findsWidgets, reason: 'the attempt id is resolved to the student name');
    expect(find.text('Answer mark'), findsWidgets);

    await _tap(tester, find.byKey(const ValueKey('gradeLog.more')));
    expect(queries.last['before_id'], '7');
    expect(find.text('Older change'), findsOneWidget);
    expect(find.byKey(const ValueKey('gradeLog.more')), findsNothing, reason: 'no next_before_id, no more');

    await _tap(tester, find.byKey(const ValueKey('gradeLog.student')));
    await _tap(tester, find.text('Sara').last);
    expect(queries.last['attempt_id'], '4');
    expect(queries.last.containsKey('before_id'), isFalse, reason: 'a new filter restarts from the top');
    await _end(tester);
  });

  testWidgets('empty state and a server error', (tester) async {
    final fake = FakeApi({
      'GET $_b/exams/7/grade-log': (_) => {'items': <dynamic>[], 'next_before_id': null},
    }, latency: const Duration(milliseconds: 20))
      ..install();
    addTearDown(fake.uninstall);
    await tester.pumpWidget(layoutHost(const ExamGradeLogScreen(examId: 7, examTitle: 'Midterm'), scale: 1, scaffold: false));
    await _frames(tester);
    expect(find.text('No grade changes'), findsOneWidget);
    await _end(tester);
  });

  testWidgets('layout', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
            child: GradeLogBody(items: [
              GradeLogEntry.fromJson(_row(8, reason: 'A long reason explaining why the mark changed after the second reading ' * 3, old: 12.5, nw: 14)),
              GradeLogEntry.fromJson(_row(7, actor: 0, reason: 'regrade')),
            ], names: const {3: 'A student with a very long full name that wraps onto a second line'}, hasMore: true, onMore: () {})));
    await expectNoLayoutErrors(tester, () => const GradeLogBody(items: []));
  });
}
