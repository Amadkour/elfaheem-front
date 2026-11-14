// Grade review by camera / mark import (contract §5) against a fake server (FakeApi): a page upload answered 202 /
// 422 / 409, the session and row models, the three result lists, and the decisions: apply (old → new, confirmed, the
// body that is sent), 409 value_changed (explained, the list refreshed), keep, assign a student, fix a mark.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/marks/mark_sessions_api.dart';
import 'package:flutter_education_app/features/exams/marks/review/grade_review_capture.dart';
import 'package:flutter_education_app/features/exams/marks/review/grade_review_screen.dart';
import 'package:flutter_education_app/features/exams/marks/review/grade_review_rows.dart';
import 'package:flutter_education_app/features/exams/marks/review/grade_review_start.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

const _b = '/api/v1/exam/mark-sessions';

Map<String, dynamic> _body(dynamic data) => Map<String, dynamic>.from(data is String ? jsonDecode(data) as Map : data as Map);

Map<String, dynamic> _session({String status = 'open', Map<String, int>? counts, String mode = 'import'}) => {
      'session': {
        'id': 7,
        'course_id': 3,
        'template_id': 2,
        'mode': mode,
        'column_key': 'midterm',
        'column_max': 20,
        'paper_max': 50,
        'rounding_step': 0.5,
        'status': status,
      },
      'counts': counts ?? {'match': 1, 'mismatch': 2, 'unreadable': 1, 'pending': 2, 'applied': 0, 'kept': 0},
    };

Map<String, dynamic> _mark(String id, num value, {String status = 'ok', num max = 10}) =>
    {'field_id': id, 'question_no': id, 'value': value, 'conf': 0.97, 'max': max, 'status': status, 'crop_url': null};

Map<String, dynamic> _row(int id, {String? student = 'Sara Ali', int studentId = 11, num used = 40, num? scaled = 16, num? recorded = 14, List<String> issues = const ['scaled'], String status = 'open'}) => {
      'id': id,
      'page_id': id + 100,
      'student': student == null ? null : {'id': studentId, 'name': student},
      'identifier': {'value_masked': '2024***17', 'method': 'qr', 'conf': 0.99},
      'marks': [_mark('q1', 20, max: 25), _mark('q2', 20, max: 25)],
      'paper_total_written': used,
      'paper_total_computed': used,
      'paper_total_used': used,
      'scaled': scaled,
      'recorded': recorded,
      'diff': recorded == null || scaled == null ? null : scaled - recorded,
      'issues': issues,
      'status': status,
    };

Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _frames(tester, 4);
}

Future<void> _pumpScreen(WidgetTester tester, {List<GradeStudent>? students, Size size = const Size(1400, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(layoutHost(GradeReviewScreen(sessionId: 7, students: students ?? const [GradeStudent(11, 'Sara Ali'), GradeStudent(12, 'Omar Nabil')]), scale: 1, scaffold: false));
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
  });
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  group('page upload answers', () {
    Future<MarkPageOutcome> upload(EngineResultProbe p) async {
      final fake = FakeApi({'POST $_b/7/pages': p.handler}, latency: const Duration(milliseconds: 5))..install();
      addTearDown(fake.uninstall);
      final r = await MarkSessionsApi().addPage(7, Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3]));
      return markPageOutcome(r, arabic: false);
    }

    test('202 is queued', () async {
      final o = await upload(EngineResultProbe((_) => const FakeResponse(202, {'page_id': 41, 'status': 'queued'})));
      expect(o.kind, MarkPageKind.queued);
      expect(o.pageId, 41);
    });

    test('422 asks for a retake with the reason and does not count as queued', () async {
      for (final code in ['blurry', 'too_dark', 'glare', 'page_not_found', 'not_this_sheet']) {
        final o = await upload(EngineResultProbe((_) => FakeResponse(422, {'detail': {'code': code, 'message': 'ar', 'message_en': 'The photo is $code'}})));
        expect(o.kind, MarkPageKind.retake, reason: code);
        expect(o.code, code);
        expect(o.message, 'The photo is $code');
        expect(gradeOutcomeText(o), isNot(isEmpty));
      }
      expect(gradeRetakeText('glare'), contains('glare'));
    });

    test('409 page_duplicate is "already scanned"', () async {
      final o = await upload(EngineResultProbe((_) => const FakeResponse(409, {'detail': {'code': 'page_duplicate', 'message': 'dup'}})));
      expect(o.kind, MarkPageKind.duplicate);
      expect(gradeOutcomeText(o), 'This sheet was already scanned');
    });

    test('anything else is a plain error', () async {
      final o = await upload(EngineResultProbe((_) => const FakeResponse(500, {'detail': 'boom'})));
      expect(o.kind, MarkPageKind.error);
    });
  });

  group('models', () {
    test('a session reads its counts and the conversion', () {
      final s = MarkSession.fromJson(_session());
      expect(s.id, 7);
      expect(s.converts, isTrue);
      expect(s.counts.read, 4);
      expect(s.counts.pending, 2);
      expect(gradeConversionText(50, 20), 'Marks will be converted /50 → /20');
      expect(gradeCounterText(12, 9, 2), '12 sheets · 9 read · 2 waiting');
    });

    test('every issue code the server sends has a text, and the server text wins when present', () {
      const codes = [
        'mark_above_max', 'unreadable_mark', 'mark_blank', 'total_unreadable', 'paper_sum_error', 'scaled', 'student_unreadable',
        'unknown_student', 'student_ambiguous', 'name_unconfirmed', 'student_twice', 'not_recorded',
      ];
      for (final lang in ['ar', 'en']) {
        AppConfig.lang = lang;
        for (final code in codes) {
          expect(gradeIssueText(code), isNot(code), reason: '$code ($lang)');
        }
      }
      final withTexts = _row(5, issues: ['name_unconfirmed'])
        ..['issue_texts'] = [
          {'code': 'name_unconfirmed', 'ar': 'نص الخادم', 'en': 'Server text'}
        ];
      final row = MarkRow.fromJson(withTexts);
      AppConfig.lang = 'en';
      expect(gradeRowIssueText(row, 'name_unconfirmed'), 'Server text');
      AppConfig.lang = 'ar';
      expect(gradeRowIssueText(row, 'name_unconfirmed'), 'نص الخادم');
      expect(gradeRowIssueText(MarkRow.fromJson(_row(6)), 'scaled'), gradeIssueText('scaled'), reason: 'an older server: the built-in text');
      AppConfig.lang = 'en';
    });

    test('a clean row has a student, readable marks and only informational issues', () {
      expect(MarkRow.fromJson(_row(1)).clean, isTrue);
      expect(MarkRow.fromJson(_row(2, student: null)).clean, isFalse);
      expect(MarkRow.fromJson(_row(3, issues: ['scaled', 'paper_sum_error'])).clean, isFalse);
      final bad = _row(4)..['marks'] = [_mark('q1', 99, status: 'above_max')];
      expect(MarkRow.fromJson(bad).clean, isFalse);
    });

    test('the live hint answer is mapped to the camera layer shape', () {
      final m = markHintToOmr({'ready': true, 'corners': [[1, 1], [9, 1], [9, 9], [1, 9]], 'tip_code': '', 'tip_en': 'ok'});
      expect(m['ok'], true);
      expect(m['code'], 'ready');
      expect(m['corners_found'], 4);
      expect(markHintToOmr({'ready': false, 'tip_code': 'too_dark'})['code'], 'too_dark');
    });
  });

  group('results and decisions', () {
    late Map<String, Object?> sent;
    late int sessionReads;
    late int listReads;
    var rowsByList = <String, List<Map<String, dynamic>>>{};

    FakeApi serve({FakeHandler? decide}) {
      sent = {};
      sessionReads = 0;
      listReads = 0;
      rowsByList = {
        'match': [_row(1, scaled: 14, recorded: 14)],
        'mismatch': [_row(2), _row(3, student: 'Omar Nabil', studentId: 12, used: 30, scaled: 12, recorded: null, issues: ['scaled', 'not_recorded'])],
        'unreadable': [_row(4, student: null, issues: ['unknown_student'])],
      };
      final fake = FakeApi({
        'GET $_b/7': (_) {
          sessionReads++;
          return _session();
        },
        'GET $_b/7/rows': (o) {
          listReads++;
          return {'items': rowsByList[o.uri.queryParameters['list']] ?? []};
        },
        'POST $_b/7/rows/2/decide': decide ?? (o) {
          sent = _body(o.data);
          return {'ok': true};
        },
        'POST $_b/7/rows/3/decide': (o) {
          sent = _body(o.data);
          return {'ok': true};
        },
        'POST $_b/7/rows/4/decide': (o) {
          sent = _body(o.data);
          return {'ok': true};
        },
      }, latency: const Duration(milliseconds: 5))
        ..install();
      addTearDown(fake.uninstall);
      return fake;
    }

    testWidgets('three lists with live counts; a mismatch row says paper vs recorded', (tester) async {
      serve();
      await _pumpScreen(tester);
      expect(find.text('Match (1)'), findsOneWidget);
      expect(find.text('Mismatch (2)'), findsOneWidget);
      expect(find.text('Unreadable (1)'), findsOneWidget);
      expect(find.byKey(const ValueKey('gr.summary')), findsOneWidget);
      await tester.tap(find.text('Mismatch (2)'));
      await _frames(tester);
      expect(find.byKey(const ValueKey('gr.row.2')), findsOneWidget);
      expect(find.textContaining('Paper 40 → 16 vs recorded 14'), findsOneWidget);
      expect(find.textContaining('not recorded'), findsOneWidget);
      await tester.tap(find.text('Unreadable (1)'));
      await _frames(tester);
      expect(find.textContaining('Unknown student'), findsWidgets);
      await _end(tester);
    });

    testWidgets('apply shows old → new, asks, and sends the proposed value with the reason', (tester) async {
      final fake = serve();
      await _pumpScreen(tester);
      await tester.tap(find.text('Mismatch (2)'));
      await _frames(tester);
      await tester.tap(find.byKey(const ValueKey('gr.row.2')));
      await _frames(tester);
      expect(find.textContaining('Written total'), findsOneWidget);
      await _tapKey(tester, 'gr.act.apply');
      expect(find.byKey(const ValueKey('gr.apply.old')), findsOneWidget);
      expect((tester.widget<Text>(find.byKey(const ValueKey('gr.apply.old')))).data, '14');
      expect((tester.widget<Text>(find.byKey(const ValueKey('gr.apply.new')))).data, '16');
      expect(fake.calls.where((c) => c.path.endsWith('/decide')), isEmpty, reason: 'nothing is written before the confirmation');
      await tester.enterText(find.byType(TextField).last, 'checked by hand');
      await tester.tap(find.text('Confirm and write'));
      await _frames(tester);
      expect(sent['action'], 'apply');
      expect(sent['value'], 16);
      expect(sent['reason'], 'checked by hand');
      await _end(tester);
    });

    testWidgets('409 value_changed is explained and the list is read again', (tester) async {
      serve(decide: (o) => const FakeResponse(409, {'detail': {'code': 'value_changed', 'message': 'changed'}}));
      await _pumpScreen(tester);
      await tester.tap(find.text('Mismatch (2)'));
      await _frames(tester);
      final before = listReads, sBefore = sessionReads;
      await tester.tap(find.byKey(const ValueKey('gr.row.2')));
      await _frames(tester);
      await _tapKey(tester, 'gr.act.apply');
      await tester.tap(find.text('Confirm and write'));
      await _frames(tester);
      expect(listReads, greaterThan(before), reason: 'the rows are refreshed after the conflict');
      expect(sessionReads, greaterThan(sBefore));
      await _end(tester);
    });

    testWidgets('keep recorded sends keep and nothing else', (tester) async {
      serve();
      await _pumpScreen(tester);
      await tester.tap(find.text('Mismatch (2)'));
      await _frames(tester);
      await tester.tap(find.byKey(const ValueKey('gr.row.2')));
      await _frames(tester);
      await _tapKey(tester, 'gr.act.keep');
      expect(sent, {'action': 'keep'});
      await _end(tester);
    });

    testWidgets('assign student picks from the course list', (tester) async {
      serve();
      await _pumpScreen(tester);
      await tester.tap(find.text('Unreadable (1)'));
      await _frames(tester);
      await tester.tap(find.byKey(const ValueKey('gr.row.4')));
      await _frames(tester);
      expect(find.byKey(const ValueKey('gr.act.apply')), findsNothing, reason: 'no student, nothing to write');
      await _tapKey(tester, 'gr.act.assign');
      await tester.tap(find.byKey(const ValueKey('gr.student.12')));
      await _frames(tester);
      expect(sent['action'], 'assign_student');
      expect(sent['student_id'], 12);
      await _end(tester);
    });

    testWidgets('fixing a mark validates against the field max, then sends fix_marks', (tester) async {
      serve();
      await _pumpScreen(tester);
      await tester.tap(find.text('Mismatch (2)'));
      await _frames(tester);
      await tester.tap(find.byKey(const ValueKey('gr.row.2')));
      await _frames(tester);
      await tester.ensureVisible(find.byIcon(Icons.edit_outlined).first);
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await _frames(tester, 4);
      await tester.enterText(find.byType(TextField).last, '30');
      await tester.tap(find.text('Save and recompute'));
      await _frames(tester, 3);
      expect(find.byKey(const ValueKey('gr.fix.error')), findsOneWidget);
      expect(sent, isEmpty);
      await tester.enterText(find.byType(TextField).last, '22.5');
      await tester.tap(find.text('Save and recompute'));
      await _frames(tester);
      expect(sent['action'], 'fix_marks');
      expect((sent['marks'] as Map)['q1'], 22.5);
      await _end(tester);
    });

    testWidgets('bulk apply only takes clean rows of an import and asks first', (tester) async {
      final fake = serve();
      await _pumpScreen(tester);
      await tester.tap(find.text('Mismatch (2)'));
      await _frames(tester);
      expect(find.byKey(const ValueKey('gr.bulk')), findsOneWidget);
      expect(find.textContaining('(2)'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('gr.bulk')));
      await _frames(tester, 4);
      expect(fake.calls.where((c) => c.path.endsWith('/decide')), isEmpty, reason: 'confirmation first');
      await tester.tap(find.text('Apply all (2)'));
      await _frames(tester, 12);
      expect(fake.calls.where((c) => c.path.endsWith('/decide')).length, 2);
      await _end(tester);
    });
  });
}

/// A single route handler, named so the cases above read as "answer X".
class EngineResultProbe {
  EngineResultProbe(this.handler);
  final FakeHandler handler;
}
