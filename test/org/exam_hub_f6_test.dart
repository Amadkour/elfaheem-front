// Exam Hub F6, grade revision (contract B3): the pure logic (results queue, sample verdict, setup body, history text),
// the run screen over a fake camera and FakeApi (a job_updated reads the page once; a match is quiet, a mismatch waits
// for the camera to be between papers, one at a time, and 409 value_changed asks again), and the layout of the main widgets.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/revision/revision_models.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/revision/revision_papers_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/revision/revision_result_panel.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/revision/revision_run_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/revision/revision_wizard_steps.dart';
import 'package:flutter_education_app/features/shared/exam_engine/marks/mark_sessions_api.dart';
import 'package:flutter_education_app/features/shared/exam_engine/marks/mark_templates_api.dart' show MarkKind, MarkTemplate;
import 'package:flutter_education_app/features/shared/exam_engine/marks/review/grade_review_start.dart' show GradeColumn;
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_camera.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

Map<String, dynamic> _rowJson(int id, {String list = 'mismatch', String status = 'open', num? recorded = 14, num scaled = 16, List<String> issues = const [], String? student = 'Sara Ali'}) => {
      'id': id,
      'page_id': id + 100,
      'student': student == null ? null : {'id': 11, 'name': student},
      'identifier': {'value_masked': '2024***17', 'method': 'digits', 'conf': 0.99},
      'marks': [
        {'field_id': 'q1', 'question_no': 1, 'value': 8, 'conf': 0.97, 'max': 10, 'status': 'ok', 'crop_url': null},
        {'field_id': 'q2', 'question_no': 2, 'value': 8, 'conf': 0.91, 'max': 10, 'status': list == 'unreadable' ? 'low' : 'ok', 'crop_url': null},
      ],
      'paper_total_written': scaled,
      'paper_total_computed': scaled,
      'paper_total_used': scaled,
      'scaled': scaled,
      'recorded': recorded,
      'diff': recorded == null ? null : scaled - recorded,
      'issues': issues,
      'list': list,
      'status': status,
    };

RevisionRow _row(int id, {String list = 'mismatch', String status = 'open', num? recorded = 14, List<String> issues = const [], String? student = 'Sara Ali'}) =>
    RevisionRow.fromJson(_rowJson(id, list: list, status: status, recorded: recorded, issues: issues, student: student));

RevisionPageRead _read(RevisionRow? r, {bool ready = true, bool rejected = false, String code = ''}) => RevisionPageRead(ready: ready, rejected: rejected, row: r, code: code);

MarkSession _session() => MarkSession.fromJson({
      'session': {'id': 7, 'course_id': 3, 'template_id': 2, 'mode': 'review', 'column_key': 'midterm', 'column_max': 20, 'paper_max': 20, 'status': 'open'},
      'counts': {'match': 0, 'mismatch': 0, 'unreadable': 0, 'pending': 0, 'applied': 0, 'kept': 0},
    });

RevisionSample _sample({bool ok = true, String status = 'ok', int? student = 11, double conf = .95, String value = '8'}) => RevisionSample.fromJson({
      'ok': ok,
      if (!ok) 'code': 'blurry',
      'identifier': {'value_masked': '2024***17', 'method': 'digits', 'conf': .98, 'student': student == null ? null : {'id': student, 'name': 'Sara Ali'}},
      'fields': [
        {'field_id': 'q1', 'type': 'question_mark', 'question_no': 1, 'value': value, 'conf': conf, 'status': status, 'max': 10, 'box': [0.1, 0.2, 0.2, 0.05]},
        {'field_id': 't', 'type': 'total', 'value': '16', 'conf': .9, 'status': 'ok', 'max': 20, 'box': [0.1, 0.8, 0.2, 0.05]},
      ],
      'sum': {'computed': 16, 'written': 16, 'consistent': true},
    }, lang: 'en');

final _jpeg = Uint8List.fromList(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));

class _Cam implements OmrCamera {
  int photos = 0;
  @override
  Future<void> open({bool front = false}) async {}
  @override
  Widget preview() => const ColoredBox(color: Color(0xFF4A4F57));
  @override
  Future<OmrFrame?> frame({int maxSide = 640, int quality = 70}) async => null;
  @override
  Future<Uint8List?> photo() async => Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 9, 9, 9, ++photos]);
  @override
  bool get canTorch => false;
  @override
  bool get torchOn => false;
  @override
  Future<void> setTorch(bool on) async {}
  @override
  bool get canSwitch => false;
  @override
  Future<void> switchCamera() async {}
  @override
  Future<void> dispose() async {}
}

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
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

  group('RevisionFlow (results queue)', () {
    test('a match is quiet, a mismatch waits, and a still-reading page stays', () {
      final f = RevisionFlow()
        ..shot(1, null)
        ..shot(2, null)
        ..shot(3, null);
      expect(f.take(1, _read(null, ready: false)), RevisionReadKind.stillReading);
      expect(f.waiting, [1, 2, 3], reason: 'a page not ready yet is read again on its next event');
      expect(f.take(1, _read(_row(1, list: 'match'))), RevisionReadKind.matched);
      expect(f.queue, isEmpty);
      expect(f.take(2, _read(_row(2))), RevisionReadKind.needsYou);
      expect(f.take(3, _read(_row(3))), RevisionReadKind.needsYou);
      expect(f.queue.map((a) => a.pageId), [2, 3], reason: 'first in, first out');
      expect(f.take(99, _read(_row(4))), RevisionReadKind.stillReading, reason: 'a page this device did not send is ignored');
    });

    test('never presents while the camera is busy, and only one at a time', () {
      final f = RevisionFlow()..shot(1, null)..shot(2, null);
      f.take(1, _read(_row(1)));
      f.take(2, _read(_row(2)));
      expect(f.canPresent(cameraBusy: true), isFalse);
      expect(f.canPresent(cameraBusy: false), isTrue);
      f.showing = true;
      expect(f.canPresent(cameraBusy: false), isFalse, reason: 'two results never stack');
      f.removeCurrent();
      expect(f.queue.single.pageId, 2);
      expect(f.showing, isFalse);
      f.showing = true;
      f.deferCurrent();
      expect(f.queue, isEmpty);
      expect(f.later.single.pageId, 2, reason: 'decide later keeps the paper, it is offered again');
    });

    test('update: a fixed paper that became a match leaves, otherwise it stays on screen with its new row', () {
      final f = RevisionFlow()..shot(1, null);
      f.take(1, _read(_row(1, list: 'unreadable', student: null)));
      expect(f.update(_row(1)), isFalse);
      expect(f.current!.row!.list, MarkList.mismatch);
      expect(f.update(_row(1, list: 'match')), isTrue);
      expect(f.queue, isEmpty);
    });

    test('a rejected page asks for a retake, and photos are capped', () {
      final f = RevisionFlow();
      for (var i = 0; i < RevisionFlow.maxPhotos + 8; i++) {
        f.shot(i, Uint8List(1));
      }
      f.take(0, _read(null, rejected: true, code: 'blurry'));
      expect(f.current!.rejected, isTrue);
      final kept = f.queue.where((a) => a.photo != null).length + f.waiting.length;
      expect(kept, greaterThan(0));
      expect(f.queue.first.photo, isNull, reason: 'the oldest photos are dropped first');
    });
  });

  group('the sample verdict and comparison', () {
    test('good, partial, bad', () {
      expect(_sample().verdict(), SampleVerdict.good);
      expect(_sample(status: 'low').verdict(), SampleVerdict.partial);
      expect(_sample(student: null).verdict(), SampleVerdict.partial);
      expect(_sample(student: null).verdict(nameOnly: true), SampleVerdict.good, reason: 'a name never links: a value read is enough');
      expect(_sample(ok: false).verdict(), SampleVerdict.bad);
    });

    test('side by side: which value changed', () {
      final rows = compareSamples(_sample(value: '3'), _sample(value: '8'));
      expect(rows.first.changed, isTrue);
      expect(rows.first.before, '3');
      expect(rows.first.after, '8');
      expect(rows.last.changed, isFalse);
    });
  });

  group('the setup', () {
    test('adoptSheet preselects the guesses; an excel body names the sheet and its columns', () {
      final s = RevisionSetup()
        ..source = RevisionSource.excel
        ..template = const RevisionTemplateChoice(id: 4, name: 'Cover', totalMax: 20, identifierSource: 'national_id');
      s.adoptSheet(RevisionSheetPreview.fromJson({
        'sheet_key': 'k1',
        'rows': 3,
        'columns': [
          {'name': 'ID', 'samples': ['1'], 'guess': 'identifier'},
          {'name': 'Mark', 'samples': ['9'], 'guess': 'degree'},
        ],
      }));
      expect(s.matchColumn, 'ID');
      expect(s.degreeColumn, 'Mark');
      expect(s.sourceReady, isTrue);
      s.sheetMax = 40;
      expect(s.converts, isTrue);
      final body = s.createBody();
      expect(body['source'], 'excel');
      expect(body['sheet_key'], 'k1');
      expect(body['sheet_max'], 40);
      expect(body.containsKey('column_key'), isFalse);
      expect(body['rounding_step'], .5);
    });

    test('a gradebook body sends the column, the match override and the styles', () {
      final s = RevisionSetup()
        ..source = RevisionSource.gradebook
        ..courseId = 3
        ..column = const GradeColumn('midterm', 'Midterm', 20)
        ..template = const RevisionTemplateChoice(id: 4, name: 'Cover', totalMax: 20, identifierSource: 'national_id')
        ..match = const RevisionMatch('datalab', 'seat')
        ..styles = const RevisionStyles(degree: RevisionStyle(script: DigitScript.arabic, kind: WriteKind.printed));
      final b = s.createBody(examId: 9);
      expect(b['column_key'], 'midterm');
      expect(b['course_id'], 3);
      expect(b['exam_id'], 9);
      expect(b['match'], {'source': 'datalab', 'key': 'seat'});
      expect(jsonEncode(b['styles']), contains('"arabic"'));
      expect(b.containsKey('rounding_step'), isFalse);
    });

    test('the template decides whether matching can be overridden', () {
      RevisionSetup withTpl(String src) => RevisionSetup()
        ..source = RevisionSource.gradebook
        ..template = RevisionTemplateChoice(id: 1, name: 'x', totalMax: 10, identifierSource: src);
      expect(withTpl('academic_id').matchIsFixed, isFalse);
      expect(withTpl('qr').matchIsFixed, isTrue);
      expect(withTpl('name').matchIsFixed, isTrue);
    });
  });

  test('history: the action and the old to new text', () {
    final apply = RevisionHistoryItem.fromJson({'id': 1, 'action': 'apply', 'old': 12, 'new': 15.5, 'by_name': 'T', 'student': {'id': 1, 'name': 'A'}});
    expect(revisionChangeText(apply), '12 → 15.5');
    expect(revisionActionLabel('retake'), 'Scan to be retaken');
    final fix = RevisionHistoryItem.fromJson({'id': 2, 'action': 'fix_marks', 'old': {'q1': 3}, 'new': {'q1': 8}});
    expect(revisionChangeText(fix), '3 → 8');
    final keep = RevisionHistoryItem.fromJson({'id': 3, 'action': 'keep', 'old': 'open', 'new': 'kept'});
    expect(revisionChangeText(keep), '');
  });

  group('the run over a fake camera and FakeApi', () {
    const b = '/api/v1/exam/mark-sessions';
    late int nextPage;
    late List<Map<String, dynamic>> decided;
    late List<Object> decideReplies;

    RevisionSession info() => RevisionSession.fromJson({
          'session': {'id': 7, 'course_id': 3, 'template_id': 2, 'mode': 'review', 'column_key': 'midterm', 'column_max': 20, 'paper_max': 20, 'status': 'open', 'source': 'gradebook'},
          'counts': {'pages': 0},
        });

    FakeApi fake() => FakeApi({
          'POST $b/7/pages': (_) => FakeResponse(202, {'page_id': nextPage++, 'status': 'queued'}),
          'GET $b/7': (_) => info().session.counts == const MarkCounts() ? {'session': {'id': 7}, 'counts': {'pending': 0}} : {},
          'GET $b/7/rows': (_) => {'items': []},
          'GET $b/7/pages/*': (o) {
            final id = int.parse(o.path.split('/').reversed.elementAt(1));
            final row = switch (id) { 201 => _rowJson(1, list: 'match', recorded: 16), 202 => _rowJson(2), 203 => _rowJson(3, student: 'Omar Said'), _ => _rowJson(id) };
            return {'ready': true, 'rejected': false, 'row': row};
          },
          'POST $b/7/rows/*': (o) {
            decided.add(Map<String, dynamic>.from(o.data is String ? jsonDecode(o.data as String) as Map : o.data as Map));
            return decideReplies.removeAt(0);
          },
        }, latency: const Duration(milliseconds: 20));

    setUp(() {
      nextPage = 201;
      decided = [];
      decideReplies = [];
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final f = fake()..install();
      addTearDown(f.uninstall);
      await tester.pumpWidget(layoutHost(RevisionRunScreen(info: info(), camera: _Cam.new), scale: 1, scaffold: false));
      await _frames(tester, 3);
    }

    Future<void> shoot(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel('Capture the paper'));
      await _frames(tester, 6);
    }

    void read(int page) => LiveEvents.instance.emit(LiveEvents.jobUpdated, {'kind': 'mark_session', 'id': '7', 'page_id': '$page', 'page_status': 'read'});

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 25));
    }

    testWidgets('a match is one quiet line and the camera goes on; a mismatch comes one at a time, in order', (tester) async {
      await open(tester);
      await shoot(tester);
      read(201);
      await _frames(tester, 4);
      expect(find.textContaining('Sara Ali · 16'), findsOneWidget, reason: 'the quiet confirmation');
      expect(find.byKey(const ValueKey('rv.update')), findsNothing);

      await shoot(tester);
      await shoot(tester);
      read(203);
      read(202);
      await _frames(tester, 6);
      expect(find.byKey(const ValueKey('rv.update')), findsOneWidget, reason: 'one result on screen');
      expect(tester.widget<Text>(find.byKey(const ValueKey('rv.name'))).data, 'Omar Said', reason: 'whichever came back first is first');
      expect(find.byKey(const ValueKey('rv.name')), findsOneWidget, reason: 'the second waits, it does not stack');
      expect(find.byKey(const ValueKey('rv.behind')), findsOneWidget);
      expect(find.text('System degree'), findsOneWidget);
      expect(find.text('Scanned degree'), findsOneWidget);

      decideReplies.addAll([
        _rowJson(3, status: 'applied', list: 'match', student: 'Omar Said'),
        _rowJson(2, status: 'kept'),
      ]);
      await tester.tap(find.byKey(const ValueKey('rv.update')));
      await _frames(tester, 6);
      expect(decided.single['action'], 'apply');
      expect(decided.single['value'], 16);
      expect(tester.widget<Text>(find.byKey(const ValueKey('rv.name'))).data, 'Sara Ali', reason: 'the next one opens by itself');
      await tester.tap(find.byKey(const ValueKey('rv.ignore')));
      await _frames(tester, 6);
      expect(decided.last['action'], 'keep');
      expect(find.byKey(const ValueKey('rv.update')), findsNothing);
      await close(tester);
    });

    testWidgets('409 value_changed shows the new value and asks again', (tester) async {
      await open(tester);
      await shoot(tester);
      await shoot(tester);
      read(201);
      read(202);
      await _frames(tester, 6);
      expect(find.byKey(const ValueKey('rv.update')), findsOneWidget);
      decideReplies.add(const FakeResponse(409, {
        'detail': {'code': 'value_changed', 'message': 'x', 'message_en': 'changed', 'current': 13}
      }));
      await tester.tap(find.byKey(const ValueKey('rv.update')));
      await _frames(tester, 8);
      expect(find.byKey(const ValueKey('rv.changed')), findsOneWidget);
      expect(find.textContaining('now 13'), findsOneWidget);
      expect(find.byKey(const ValueKey('rv.update')), findsOneWidget, reason: 'it asks again');
      await close(tester);
    });
  });

  group('layout', () {
    final session = _session();
    final map = <String, Widget Function()>{
      'mismatch panel': () => RevisionResultPanel(row: _row(1), session: session, photo: _jpeg, behind: 2, changedTo: 13, onUpdate: () {}, onIgnore: () {}, onRetake: () {}, onLater: () {}),
      'unreadable panel': () => RevisionResultPanel(row: _row(2, list: 'unreadable', student: null, issues: const ['student_unreadable', 'unreadable_mark']), session: session, onRetake: () {}, onLater: () {}, onAssign: () {}, onFix: (_) {}),
      'rejected panel': () => RevisionResultPanel(row: null, session: session, code: 'blurry', onRetake: () {}, onLater: () {}),
      'finish': () => RevisionFinishBody(counts: const RevisionCounts(match: 20, applied: 4, kept: 1, unreadable: 2, mismatch: 3, pages: 30), excel: true, onDownload: () {}, onReview: () {}, onPapers: () {}, onHistory: () {}, onScanMore: () {}),
      'arrow bar': () => const Align(alignment: Alignment.bottomCenter, child: RevisionArrowBar(index: 3, total: 12)),
      'source step (sheet)': () => SingleChildScrollView(
            child: RevisionSourceStep(
              setup: RevisionSetup()
                ..source = RevisionSource.excel
                ..adoptSheet(const RevisionSheetPreview(sheetKey: 'k', rows: 40, fileName: 'grades-grade-seven-final-2026.xlsx', columns: [
                  RevisionSheetColumn(name: 'National ID', samples: ['29801234', '29805678'], guess: 'identifier'),
                  RevisionSheetColumn(name: 'Final degree out of forty points', samples: ['31', '18.5'], guess: 'degree'),
                ])),
              onSource: (_) {},
              onCourse: (_) {},
              onColumn: (_) {},
              onUpload: () {},
              onMatchColumn: (_) {},
              onDegreeColumn: (_) {},
              onSheetMax: (_) {},
            ),
          ),
      'template step (none yet)': () => RevisionTemplateStep(setup: RevisionSetup(), templates: const [], onPick: (_) {}, onCreate: () {}, onEdit: () {}, onStep: (_) {}),
      'template step (list)': () => RevisionTemplateStep(
            setup: RevisionSetup()..template = const RevisionTemplateChoice(id: 1, name: 'Cover', totalMax: 20, identifierSource: 'qr'),
            templates: const [MarkTemplate(id: 1, familyId: 'a', version: 1, name: 'A cover template with a very long descriptive name', kind: MarkKind.cover, fieldsCount: 5, totalMax: 20)],
            onPick: (_) {},
            onCreate: () {},
            onEdit: () {},
            onStep: (_) {},
          ),
      'sample view': () => SingleChildScrollView(child: RevisionSampleView(sample: _sample(status: 'low'), aspect: .7, identifierBox: const Rect.fromLTWH(.1, .05, .3, .06))),
      'style step': () => SingleChildScrollView(child: RevisionStyleStep(styles: const RevisionStyles(degree: RevisionStyle(kind: WriteKind.printed)), hasPhoto: true, sample: _sample(), previous: _sample(value: '3', conf: .6), onChanged: (_) {}, onRestore: () {})),
    };
    for (final e in map.entries) {
      testWidgets(e.key, (tester) async => expectNoLayoutErrors(tester, e.value));
    }
  });
}
