// Round 3, pack FL (D-197): ONE "New exam" entry without losing a feature.
//   - the quick exam carries the session it locks (settings.session_id), unlimited attempts (0), a description and the
//     questions drawn per student (the section's pool_size);
//   - the teacher hub's button opens the quick builder; the legacy sheet stays reachable from its quiet "Classic exam"
//     link and when the engine is unavailable;
//   - an engine gate on a session opens the engine exam; the results export; the Excel import report.
import 'dart:typed_data';

import 'package:dio/dio.dart' show FormData;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart' show bilingualExport;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/exams/exam_authoring.dart';
import 'package:flutter_education_app/features/exams/exam_authoring_screen.dart';
import 'package:flutter_education_app/features/exams/exam_quick.dart';
import 'package:flutter_education_app/features/exams/exam_quick_screen.dart';
import 'package:flutter_education_app/features/exams/exam_results_screen.dart';
import 'package:flutter_education_app/features/exams/exam_review_screen.dart' show SessionLockChip;
import 'package:flutter_education_app/features/shared/session/material/components/session_exam_tile.dart';
import 'package:flutter_education_app/features/student/courses/details/session_exam_gate.dart';
import 'package:flutter_education_app/features/exams/legacy/teacher/teacher_exam_hub_screen.dart';
import 'package:flutter_education_app/utils/top_route_observer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

QuickQuestion _mcq() => QuickQuestion.mcq()
  ..prompt = 'Which gas do plants take in?'
  ..options[0].text = 'CO2'
  ..options[1].text = 'O2'
  ..correct = 'a';

Map<String, dynamic> _map(Object? data) => Map<String, dynamic>.from(data as Map);

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    ExamAuthoringApi.forgetScopes();
  });

  Future<void> frames(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget app(Widget home) => ThemeConfigScope(
        provider: ThemeConfigProvider(api: ApiClient()),
        child: MaterialApp(navigatorObservers: [topRouteObserver], home: home),
      );

  group('what the quick exam sends', () {
    test('the session, unlimited attempts, the description and the draw per student', () {
      final q = QuickExam(kind: QuickKind.quiz, courseId: 1, sessionId: 4)
        ..mode = QuickMode.online
        ..maxAttempts = 0
        ..description = ' Chapter 3 '
        ..poolSize = 2
        ..questions.addAll([_mcq(), _mcq(), _mcq()]);
      expect(q.validate().$1, isEmpty);
      final body = q.toExamDraft().toBody();
      expect((body['settings'] as Map)['session_id'], 4);
      expect(body['max_attempts'], 0);
      expect(body['description'], 'Chapter 3');
      expect(q.toSection().toBody()['pool_size'], 2);
    });

    test('no session: the key is absent; a draw larger than the list is refused; 0 attempts is fine, -1 is not', () {
      final q = QuickExam(kind: QuickKind.quiz, courseId: 1)
        ..mode = QuickMode.online
        ..questions.add(_mcq());
      expect((q.toExamDraft().toBody()['settings'] as Map).containsKey('session_id'), isFalse);
      q.poolSize = 5;
      expect(q.validate().$1, contains('bad_pool'));
      q.poolSize = null;
      q.maxAttempts = 0;
      expect(q.validate().$1, isEmpty);
      q.maxAttempts = -1;
      expect(q.validate().$1, contains('bad_attempts'));
    });

    test('the full editor keeps the session and unlimited attempts through a copy', () {
      final d = ExamDraft.fromJson({'id': 1, 'title': 'x', 'max_attempts': 0, 'settings': {'session_id': 8}});
      expect(d.sessionId, 8);
      expect(d.validate(), isEmpty);
      d.sessionId = null;
      expect(d.mergedSettings()['session_id'], isNull);
      expect(d.mergedSettings().containsKey('session_id'), isTrue);       // an explicit null clears the lock
      expect(ExamDraft().mergedSettings().containsKey('session_id'), isFalse);
    });

    test('createQuickExam POSTs settings.session_id and max_attempts 0', () async {
      Map<String, dynamic>? created, section;
      final fake = FakeApi({
        'POST /api/v1/exam/exams': (o) {
          created = _map(o.data);
          return {'id': 5};
        },
        'POST /api/v1/exam/exams/5/sections': (o) {
          section = _map(o.data);
          return {'id': 7};
        },
        'POST /api/v1/exam/questions': (_) => {'id': 11},
        'POST /api/v1/exam/exams/5/sections/7/questions': (_) => {'id': 1},
        'POST /api/v1/exam/exams/5/publish': (_) => {'id': 5},
      }, latency: Duration.zero)
        ..install();
      addTearDown(fake.uninstall);
      final q = QuickExam(kind: QuickKind.quiz, courseId: 1, orgId: 3, sessionId: 4)
        ..mode = QuickMode.online
        ..maxAttempts = 0
        ..poolSize = 1
        ..questions.addAll([_mcq(), _mcq()]);
      final r = await createQuickExam(ExamAuthoringApi(), q);
      expect(r.ok, isTrue, reason: r.error);
      expect((created!['settings'] as Map)['session_id'], 4);
      expect(created!['max_attempts'], 0);
      expect(section!['pool_size'], 1);
    });
  });

  group('the teacher hub has ONE entry', () {
    Map<String, FakeHandler> hubRoutes({bool engine = true}) => {
          if (engine) 'GET /api/v1/exam/exams': (_) => {'items': const <Object>[]},
          'GET /api/v1/courses/1/exams/all': (_) => const <Object>[],
          'GET /api/v1/courses/1/sessions': (_) => const {'items': <Object>[]},
        };

    Future<void> pumpHub(WidgetTester tester, {bool engine = true}) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = FakeApi(hubRoutes(engine: engine), latency: Duration.zero)..install();
      addTearDown(fake.uninstall);
      await tester.pumpWidget(app(const TeacherExamHubScreen(courseId: 1, courseTitle: 'CS101')));
      await frames(tester, 12);
    }

    // the legacy sheet has the duration field (translation keys show as themselves in tests)
    final legacySheet = find.text('field_duration_label');

    testWidgets('the engine section has no second "+": the button is the only way in', (tester) async {
      await pumpHub(tester);
      expect(find.byTooltip('New exam'), findsNothing);
      expect(find.byKey(const ValueKey('teacher_exam_float')), findsOneWidget);
    });

    testWidgets('the button opens the quick builder, not the legacy sheet', (tester) async {
      await pumpHub(tester);
      await tester.tap(find.byKey(const ValueKey('teacher_exam_float')));
      await frames(tester, 12);
      expect(find.byType(QuickExamScreen), findsOneWidget);
      expect(legacySheet, findsNothing);
      expect(find.byKey(const ValueKey('exam.quick.classic')), findsOneWidget);
    });

    testWidgets('the classic link closes the builder and opens the legacy sheet', (tester) async {
      await pumpHub(tester);
      await tester.tap(find.byKey(const ValueKey('teacher_exam_float')));
      await frames(tester, 12);
      await tester.tap(find.byKey(const ValueKey('exam.quick.classic')));
      await frames(tester, 20);
      expect(find.byType(QuickExamScreen), findsNothing);
      expect(legacySheet, findsOneWidget);
    });

    testWidgets('engine unavailable: the button opens the legacy sheet', (tester) async {
      await pumpHub(tester, engine: false);                 // an unrouted engine answers FastAPI\'s bare 404
      await tester.tap(find.byKey(const ValueKey('teacher_exam_float')));
      await frames(tester, 20);
      expect(find.byType(QuickExamScreen), findsNothing);
      expect(legacySheet, findsOneWidget);
    });
  });

  group('the session menu', () {
    testWidgets('openQuickExam carries the session into the builder and its picker', (tester) async {
      final fake = FakeApi({
        'GET /api/v1/courses/1/sessions': (_) => {
              'items': [
                {'id': 4, 'name': 'Lesson 1', 'order': 1},
                {'id': 5, 'name': 'Lesson 2', 'order': 2},
              ]
            },
      }, latency: Duration.zero)
        ..install();
      addTearDown(fake.uninstall);
      await tester.pumpWidget(app(Builder(
          builder: (ctx) => TextButton(
              onPressed: () => openQuickExam(ctx, courseId: 1, orgId: 3, sessionId: 5, onClassic: () {}),
              child: const Text('go')))));
      await tester.tap(find.text('go'));
      await frames(tester, 12);
      final screen = tester.widget<QuickExamScreen>(find.byType(QuickExamScreen));
      expect(screen.exam.sessionId, 5);
      expect(find.byKey(const ValueKey('exam.quick.classic')), findsOneWidget);
    });

    testWidgets('without onClassic (a timetable slot, My exams) the chooser has no classic link', (tester) async {
      await tester.pumpWidget(app(Scaffold(body: QuickStartChooser(onPick: (_) {}, canGenerate: true))));
      expect(find.byKey(const ValueKey('exam.quick.classic')), findsNothing);
    });
  });

  group('session gates', () {
    test('an engine entry opens the engine exam; unlimited attempts are never exhausted', () {
      final g = SessionExamGate.fromJson([
        {'id': 0, 'engine': true, 'engine_exam_id': 31, 'name': 'Quiz', 'passed': false, 'max_submissions': 0, 'remaining_submissions': 0},
      ]);
      final e = g.firstPending!;
      expect((e.engine, e.engineId, e.attemptsExhausted, e.canStart), (true, 31, false, true));
      final legacy = SessionExamGate.fromJson([
        {'id': 9, 'name': 'Old', 'passed': false}
      ]).firstPending!;
      expect((legacy.engine, legacy.engineId), (false, 9));
    });

    test('startable and passcode-free goes to the engine exam; everything else to the Exams tab', () {
      final open = {'id': 31, 'status': 'published', 'attempts_left': 1, 'open_attempt_id': 77};
      expect(engineGateTarget(open), EngineGateTarget.engineExam);
      expect(engineGateTarget(null), EngineGateTarget.examsTab);
      expect(engineGateTarget({...open, 'paper_only': true}), EngineGateTarget.examsTab);
      expect(engineGateTarget({...open, 'offline': true}), EngineGateTarget.examsTab);
      expect(engineGateTarget({'id': 31, 'has_passcode': true}), isNot(EngineGateTarget.engineExam));
    });

    testWidgets('layout: the gate tile for an engine exam, student and teacher', (tester) async {
      final gate = SessionExamGate.fromJson([
        {'id': 0, 'engine': true, 'engine_exam_id': 31, 'name': 'A long engine quiz name that has to wrap on a narrow phone', 'passed': false, 'max_submissions': 0, 'passing_score': 60},
      ]);
      await expectNoLayoutErrors(tester, () => Column(children: [
            SessionExamTile(gate: gate, isTeacher: false),
            SessionExamTile(gate: gate, isTeacher: true),
          ]));
    });

    testWidgets('a held result: "waiting for results", no start button, nothing about pass / fail', (tester) async {
      final gate = SessionExamGate.fromJson([
        {'id': 0, 'engine': true, 'engine_exam_id': 31, 'name': 'Quiz', 'passed': false, 'awaiting_results': true,
         'attempted': true, 'max_submissions': 0, 'passing_score': 60},
      ]);
      final e = gate.firstPending!;
      expect(e.awaitingResults, isTrue);
      expect(SessionExamGate.fromJson([{'id': 1, 'name': 'Old', 'passed': false}]).firstPending!.awaitingResults, isFalse);
      await tester.pumpWidget(app(Scaffold(body: SessionExamTile(gate: gate, isTeacher: false, enrolled: true))));
      expect(find.text('session_exam_awaiting_results'.tr), findsOneWidget);
      expect(find.text('session_exam_retry'.tr), findsNothing);
      expect(find.text('session_exam_start'.tr), findsNothing);
      await expectNoLayoutErrors(tester, () => SessionExamTile(gate: gate, isTeacher: false, enrolled: true));
    });
  });

  group('results export and Excel import', () {
    final rows = [
      ResultRow(attemptId: 1, studentId: 1, name: 'Ali', state: 'graded', percentage: 80, score: 8, maxScore: 10, passed: true, needsReview: false),
      ResultRow(attemptId: 2, studentId: 2, name: 'Mona', state: 'submitted', percentage: 30, score: 3, maxScore: 10, passed: false, needsReview: false),
      ResultRow(attemptId: 3, studentId: 3, name: 'Omar', state: 'in_progress', needsReview: false),
    ];

    test('the table has the student, score, percentage and a status', () {
      final e = examResultsExport(title: 'Quiz 1', rows: rows);
      expect(e.columns.map((c) => c.id), ['name', 'score', 'max', 'percentage', 'status']);
      expect(e.rows.map((r) => r['name']), ['Ali', 'Mona', 'Omar']);
      expect(e.rows.map((r) => r['status']), ['passed', 'failed', 'not_submitted']);
      expect(e.rows.first['percentage'], 80);
    });

    test('an English export has English headers while the app is Arabic', () {
      AppConfig.lang = 'ar';
      final e = bilingualExport(() => examResultsExport(title: 'Quiz 1', rows: rows));
      expect(e.columns.first.labelIn('en'), 'Student');
      expect(e.columns.first.labelIn('ar'), 'الطالب');
    });

    test('the import report keeps the refused rows', () {
      final r = ImportReport.fromJson({
        'created': 3,
        'errors': [
          {'row': 5, 'code': 'bad_correct', 'message': 'x'},
          {'row': 9, 'code': 'weird', 'message': 'Column F is empty'},
        ],
      });
      expect(r.created, 3);
      expect(r.errors.map((e) => e.row), [5, 9]);
      expect(importRowText(r.errors[0]), 'The correct answer is not among the choices');
      expect(importRowText(r.errors[1]), 'Column F is empty');
    });

    test('the import calls hit the routes the plan names', () async {
      Object? sectionField;
      final fake = FakeApi({
        'GET /api/v1/exam/questions/import-template': (_) => 'xlsx-bytes',
        'POST /api/v1/exam/exams/5/questions/import': (o) {
          sectionField = o.data is FormData ? (o.data as FormData).fields.where((f) => f.key == 'section_id').map((f) => f.value).firstOrNull : null;
          return {'created': 2, 'errors': const <Object>[]};
        },
      }, latency: Duration.zero)
        ..install();
      addTearDown(fake.uninstall);
      final api = ExamAuthoringApi();
      final r = await api.importQuestions(5, fileName: 'q.xlsx', bytes: Uint8List.fromList([1, 2, 3]), sectionId: 7);
      expect(r.ok, isTrue);
      expect(sectionField, '7');
      expect(fake.calls.map((c) => c.path), contains('/api/v1/exam/exams/5/questions/import'));
      await api.importTemplate('en');
      expect(fake.calls.last.query['lang'], 'en');
    });
  });

  group('layout', () {
    testWidgets('chooser with the classic link', (t) async =>
        expectNoLayoutErrors(t, () => SingleChildScrollView(child: QuickStartChooser(onPick: (_) {}, canGenerate: true, onClassic: () {}))));

    testWidgets('advanced panel with the session picker, unlimited attempts and the draw', (t) async {
      final q = QuickExam(kind: QuickKind.quiz, courseId: 1, sessionId: 2)
        ..mode = QuickMode.online
        ..maxAttempts = 0
        ..poolSize = 2
        ..questions.add(_mcq());
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                  child: QuickAdvancedPanel(exam: q, onChanged: () {}, sessions: const [
                LockSession(id: 1, name: 'Lesson 1', order: 1),
                LockSession(id: 2, name: 'A very long lesson name that has to be cut on a phone-sized screen', order: 2),
              ])),
          act: (t) async {
            await t.tap(find.text(AppConfig.lang == 'ar' ? 'متقدم' : 'Advanced'));
          });
    });

    testWidgets('session picker and the chip on engine cards', (t) async => expectNoLayoutErrors(t, () => Column(children: [
          SessionLockPicker(sessions: const [LockSession(id: 1, name: 'Lesson 1', order: 1)], selected: 1, onChanged: (_) {}),
          const SessionLockChip(name: 'A very long lesson name that has to be cut on a phone-sized screen'),
          const SessionLockChip(),
        ])));

    testWidgets('Excel import: empty, with a report and error rows', (t) async {
      for (final report in [
        null,
        ImportReport.fromJson({
          'created': 2,
          'errors': [
            for (var i = 0; i < 6; i++) {'row': i + 3, 'code': 'x', 'message': 'A long refusal message for this row that has to wrap on a narrow screen'},
          ],
        }),
      ]) {
        await expectNoLayoutErrors(
            t,
            () => SingleChildScrollView(
                  child: ExcelImportBody(
                    sections: const [(1, 'Part one'), (2, 'Part two')],
                    sectionId: 1,
                    onSection: (_) {},
                    fileName: 'questions-chapter-three-final-version.xlsx',
                    report: report,
                    busy: false,
                    error: null,
                    onTemplate: () {},
                    onPick: () {},
                    onUpload: () {},
                    onDone: () {},
                  ),
                ));
      }
    });
  });
}
