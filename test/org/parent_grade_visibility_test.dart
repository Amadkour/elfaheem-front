// Parent grade visibility (D-244): the super admin's platform default and the org admin's own choice; and the
// exam_notice routing (D-247).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_notice.dart';
import 'package:flutter_education_app/features/shared/exam_engine/parent_grade_visibility.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

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

Map<String, dynamic> _json(dynamic d) => Map<String, dynamic>.from(d is String ? jsonDecode(d) as Map : d as Map);

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });
  setUp(() => AppConfig.lang = 'en');

  test('paths, choices and texts', () {
    expect(parentVisibilityPath(), '/api/v1/admin/grades/visibility');
    expect(parentVisibilityPath(orgId: 4), '/api/v1/org/orgs/4/grades/visibility');
    expect(platformVisibilityChoices, ['always', 'when_published', 'never']);
    expect(orgVisibilityChoices.first, 'inherit');
    for (final v in {...platformVisibilityChoices, ...orgVisibilityChoices}) {
      expect(parentVisibilityLabel(v), isNotEmpty);
      expect(parentVisibilityHint(v), isNotEmpty);
    }
    final v = ParentVisibility.fromJson({'parents_see': 'inherit', 'effective': 'never', 'platform_default': 'never'});
    expect((v.parentsSee, v.effective, v.platformDefault), ('inherit', 'never', 'never'));
  });

  testWidgets('super admin: loads the default and PUTs the pick', (tester) async {
    Map<String, dynamic>? put;
    final fake = FakeApi({
      'GET /api/v1/admin/grades/visibility': (_) => {'parents_see': 'when_published'},
      'PUT /api/v1/admin/grades/visibility': (o) {
        put = _json(o.data);
        return {'parents_see': put!['parents_see']};
      },
    }, latency: const Duration(milliseconds: 20))
      ..install();
    addTearDown(fake.uninstall);
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(layoutHost(const ParentVisibilitySheet(), scale: 1));
    await _frames(tester);

    expect(find.byKey(const ValueKey('pv.inherit')), findsNothing, reason: 'the platform has no inherit');
    expect(find.byKey(const ValueKey('pv.always')), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('pv.never')));
    expect(put, {'parents_see': 'never'});
    await _end(tester);
  });

  testWidgets('org admin: inherit names the platform default; picking sends the org route', (tester) async {
    Map<String, dynamic>? put;
    final fake = FakeApi({
      'GET /api/v1/org/orgs/4/grades/visibility': (_) => {'parents_see': 'inherit', 'effective': 'never', 'platform_default': 'never'},
      'PUT /api/v1/org/orgs/4/grades/visibility': (o) {
        put = _json(o.data);
        return {'parents_see': 'always', 'effective': 'always', 'platform_default': 'never'};
      },
    }, latency: const Duration(milliseconds: 20))
      ..install();
    addTearDown(fake.uninstall);
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(layoutHost(const ParentVisibilitySheet(orgId: 4), scale: 1));
    await _frames(tester);

    expect(find.textContaining('currently: Never'), findsOneWidget);
    expect(find.textContaining('In effect now: Never'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('pv.always')));
    expect(put, {'parents_see': 'always'});
    expect(find.textContaining('In effect now'), findsNothing, reason: 'no longer inheriting');
    await _end(tester);
  });

  testWidgets('layout', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
        child: ParentVisibilityBody(choices: orgVisibilityChoices, value: 'inherit', platformDefault: 'when_published', effective: 'when_published', onPick: (_) {})));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: ParentVisibilityBody(choices: platformVisibilityChoices, value: 'never', onPick: (_) {})));
  });

  group('exam_notice', () {
    test('the live event name matches the backend', () {
      expect(LiveEvents.examNotice, 'exam_notice');
      expect(LiveEvents.serverTypes, contains('exam_notice'));
      expect(LiveEvents.fromNotificationType('exam_notice'), 'exam_notice');
    });

    test('parse flat and nested fields, and the module aliases', () {
      final a = ExamNotice.parse({'kind': 'appeal_created', 'exam_id': '7', 'attempt_id': 3, 'course_id': 2});
      expect((a.kind, a.examId, a.attemptId, a.courseId), ('appeal_created', 7, 3, 2));
      final b = ExamNotice.parse({'data': {'module': 'exam_notice', 'exam_id': 9, 'session_id': 5}, 'kind': 'mark_session_done'});
      expect((b.examId, b.sessionId), (9, 5));
      expect(ExamNotice.parse({'exam_id': 1}, module: 'exam_results').kind, 'results_published');
      expect(ExamNotice.parse({'target_id': 4}, module: 'exam_appeal').examId, 4);
    });

    test('targets: appeal to managers, results to students, hooks, unknown', () {
      ExamNoticeTarget of(String kind, {int? exam = 7, bool teacher = false}) => examNoticeTarget(ExamNotice(kind: kind, examId: exam), teacher: teacher);
      expect(of('appeal_created'), ExamNoticeTarget.appeals);
      expect(of('appeal', teacher: true), ExamNoticeTarget.appeals);
      expect(of('appeal'), ExamNoticeTarget.studentResult);
      expect(of('appeal_decided'), ExamNoticeTarget.studentResult);
      expect(of('results_published'), ExamNoticeTarget.studentResult);
      expect(of('batch_done'), ExamNoticeTarget.batchDone);
      expect(of('mark_session_done'), ExamNoticeTarget.markSession);
      expect(of('something_new'), ExamNoticeTarget.none);
      expect(of('appeal_created', exam: null), ExamNoticeTarget.none);
    });
  });
}
