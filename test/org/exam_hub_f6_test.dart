// Exam Hub F6, grade revision (contract B3): the pure logic (results queue, sample verdict, setup body, history text),
// the run screen over a fake camera and FakeApi (a job_updated reads the page once; a match is quiet, a mismatch waits
// for the camera to be between papers, one at a time, and 409 value_changed asks again), and the layout of the main widgets.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/hub/revision/revision_builtin.dart';
import 'package:flutter_education_app/features/exams/hub/revision/revision_choose_student.dart';
import 'package:flutter_education_app/features/exams/hub/revision/revision_models.dart';
import 'package:flutter_education_app/features/exams/hub/revision/revision_papers_screen.dart';
import 'package:flutter_education_app/features/exams/hub/revision/revision_result_panel.dart';
import 'package:flutter_education_app/features/exams/hub/revision/revision_run_screen.dart';
import 'package:flutter_education_app/features/exams/hub/revision/revision_wizard_steps.dart';
import 'package:flutter_education_app/features/exams/marks/mark_sessions_api.dart';
import 'package:flutter_education_app/features/exams/marks/mark_templates_api.dart';
import 'package:flutter_education_app/features/exams/marks/review/grade_review_start.dart' show GradeColumn;
import 'package:flutter_education_app/features/exams/marks/templates/mark_canvas.dart';
import 'package:flutter_education_app/features/exams/marks/templates/mark_editor_model.dart';
import 'package:flutter_education_app/features/exams/marks/templates/mark_field_form.dart';
import 'package:flutter_education_app/features/exams/marks/templates/mark_strip.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_camera.dart';
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

// the booklet's real line (exam_engine/data/builtin_templates/menoufia_cover/spec.json)
const _menoufia = MarkStrip(p1: Offset(.23541, .30712), p2: Offset(.48011, .13694), height: .021, search: .03);
const _aspect = 1141 / 1600;

const _candidatesJson = [
  {'id': 21, 'name': 'Mona Adel', 'score': .92, 'already_matched': true},
  {'id': 22, 'name': 'Sara Ali', 'score': .71, 'already_matched': false},
  {'id': 23, 'name': 'Omar Said', 'score': .83, 'already_matched': false},
  {'id': 24, 'name': 'Hana Fathy', 'score': .4, 'already_matched': false},
];

Map<String, dynamic> _unconfirmedJson(int id, {List<Map<String, Object>> candidates = _candidatesJson, String reason = 'weak_margin', String? crop = '/api/v1/exam/mark-sessions/7/crops/1/sid?exp=1&sig=x'}) => {
      ..._rowJson(id, list: 'unreadable', student: null, issues: const ['student_unconfirmed']),
      'identifier': {
        'value_masked': '****17',
        'method': 'digits',
        'conf': .4,
        'candidates': candidates,
        'roster': {'margin': .02, 'gap': .1, 'reason': reason},
        'crop_url': crop,
      },
    };

RevisionSample _coverSample({List<Map<String, Object>> candidates = _candidatesJson, String? reason = 'weak_margin', int? student, Uint8List? strip, bool blankQ2 = true}) => RevisionSample.fromJson({
      'ok': true,
      'identifier': {
        'value_masked': '****17',
        'method': 'digits',
        'conf': .4,
        'student': student == null ? null : {'id': student, 'name': 'Sara Ali'},
        'candidates': candidates,
        'roster': reason == null ? null : {'margin': 0, 'gap': null, 'reason': reason},
        'strip': {'rule_found': false, 'angle': -34.0, 'mode': 'blue'},
        'strip_b64': strip == null ? null : base64Encode(strip),
      },
      'fields': [
        {'field_id': 'q1', 'type': 'question_mark', 'question_no': 1, 'value': '8', 'conf': .9, 'status': 'ok', 'max': 100, 'box': [.2, .4, .08, .02]},
        {'field_id': 'q2', 'type': 'question_mark', 'question_no': 2, 'value': null, 'conf': 0, 'status': blankQ2 ? 'blank' : 'ok', 'max': 100, 'box': [.2, .43, .08, .02]},
      ],
      'sum': {'computed': 8, 'written': 8, 'consistent': true},
    }, lang: 'en', optional: const {'q2'});

const _builtin = MarkBuiltin(key: 'menoufia_cover', kind: MarkKind.cover, nameAr: 'غلاف كراسة جامعة المنوفية', nameEn: 'Menoufia University answer booklet cover', noteAr: 'رقم الجلوس على الخط المائل السفلي', noteEn: 'Seat number on the lower slanted line', fieldsCount: 14, totalMax: 100);

MarkTemplate _tplRow(int id, String name, {double? total = 100, String status = 'published'}) => MarkTemplate(id: id, familyId: 'f$id', version: 1, name: name, kind: MarkKind.cover, totalMax: total, status: status);

MarkSheetSpec _stripSpec() => MarkSheetSpec(
      kind: MarkKind.cover,
      page: const {'ref_w': 1141, 'ref_h': 1600},
      fields: [
        MarkField(id: 'sid', type: FieldType.identifier, source: 'academic_id', box: _menoufia.enclosingBox(_aspect), strip: _menoufia),
        const MarkField(id: 'q1', type: FieldType.questionMark, box: Rect.fromLTWH(.3, .12, .05, .02), questionNo: 1, max: 10, optional: true),
        const MarkField(id: 't', type: FieldType.total, box: Rect.fromLTWH(.2, .8, .1, .03), max: 10),
      ],
    );

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

  group('the slanted strip (pure maths)', () {
    test('the band lies above the rule, in page heights, however wide the page is', () {
      final b = _menoufia.band(_aspect);
      expect(b.first, _menoufia.p1);
      expect(b[1], _menoufia.p2);
      final top = b[3];
      expect(top.dy, lessThan(_menoufia.p1.dy), reason: 'the writing is above the line');
      expect(top.dx, lessThan(_menoufia.p1.dx), reason: 'a rule rising to the right leans its band to the left');
      final measured = Offset((top.dx - _menoufia.p1.dx) * _aspect, top.dy - _menoufia.p1.dy).distance;
      expect(measured, closeTo(.021, 1e-9), reason: 'height is a fraction of the page height');
      final flipped = _menoufia.flipped();
      expect(flipped.p1, _menoufia.p2);
      expect(flipped.band(_aspect)[3].dy, greaterThan(flipped.p1.dy), reason: 'the other reading direction is the other side');
    });

    test('the box encloses the strip and its search margin, and survives the 4-decimal rounding', () {
      final box = _menoufia.enclosingBox(_aspect);
      for (final q in [..._menoufia.outer(_aspect), _menoufia.p1, _menoufia.p2]) {
        expect(box.inflate(1e-9).contains(q), isTrue, reason: '$q in $box');
      }
      const edge = MarkStrip(p1: Offset(.9, .99), p2: Offset(1, .99), height: .05, search: .05);
      final b = edge.enclosingBox(_aspect);
      expect(b.right, lessThanOrEqualTo(1));
      expect(b.bottom, lessThanOrEqualTo(1));
      final sent = boxToJson(b);
      expect(sent[0] + sent[2], lessThanOrEqualTo(1 + 1e-6), reason: 'the server refuses a box past the page');
      expect(sent[1] + sent[3], lessThanOrEqualTo(1 + 1e-6));
    });

    test('dragging: an end stays on the page and never makes the line too short, a shift keeps the shape', () {
      final a = _menoufia.withEnd(1, const Offset(-.5, 2), _aspect);
      expect(a.p1, const Offset(0, 1));
      final tooShort = _menoufia.withEnd(2, _menoufia.p1 + const Offset(.005, .005), _aspect);
      expect(tooShort.p2, _menoufia.p2, reason: 'the move is ignored');
      final moved = _menoufia.shifted(const Offset(5, 0));
      expect(moved.p2.dx, closeTo(1, 1e-9), reason: 'stops at the edge');
      expect(moved.p2.dx - moved.p1.dx, closeTo(_menoufia.p2.dx - _menoufia.p1.dx, 1e-9));
      final tall = _menoufia.withHeightAt(_menoufia.heightHandle(_aspect) + const Offset(-.01, -.02), _aspect);
      expect(tall.height, greaterThan(_menoufia.height));
      expect(_menoufia.withHeightAt(_menoufia.p1, _aspect).height, MarkStrip.minHeight);
    });

    test('a point is inside the slanted band, not merely inside its bounding box', () {
      final inside = Offset((_menoufia.p1.dx + _menoufia.p2.dx) / 2, (_menoufia.p1.dy + _menoufia.p2.dy) / 2 - .005);
      expect(_menoufia.contains(inside, _aspect), isTrue);
      expect(_menoufia.bandBounds(_aspect).contains(const Offset(.45, .29)), isTrue);
      expect(_menoufia.contains(const Offset(.45, .29), _aspect), isFalse);
    });

    test('JSON and the server rules', () {
      final j = _menoufia.toJson();
      expect(j['p1'], [.23541, .30712]);
      expect(MarkStrip.fromJson(j)!.height, .021);
      expect(MarkStrip.fromJson({'p1': [0, 0]}), isNull);
      expect(_menoufia.errorCodes, isEmpty);
      expect(const MarkStrip(p1: Offset(.5, .5), p2: Offset(.505, .5), height: .001, search: .4).errorCodes, ['strip_short', 'strip_height', 'strip_search']);
    });

    test('a field carries strip and optional through the spec; a type change drops the strip', () {
      final f = MarkField.fromJson({'id': 'sid', 'type': 'identifier', 'source': 'academic_id', 'box': [.1, .1, .5, .3], 'strip': _menoufia.toJson()}, fallbackId: 'x');
      expect(f.strip, isNotNull);
      expect(f.extra.containsKey('strip'), isFalse);
      expect(f.toJson()['strip'], _menoufia.toJson());
      expect(f.asType(FieldType.total).strip, isNull);
      final q = MarkField.fromJson({'id': 'q', 'type': 'question_mark', 'question_no': 1, 'max': 5, 'box': [.1, .1, .1, .1], 'optional': true}, fallbackId: 'x');
      expect(q.optional, isTrue);
      expect(q.toJson()['optional'], isTrue);
      expect(q.copyWith(optional: false).toJson().containsKey('optional'), isFalse);
    });

    test('validation: a strip is exempt from overlap, and a strip on a QR is refused', () {
      final spec = _stripSpec();
      expect(spec.field('sid')!.box.overlaps(spec.field('q1')!.box), isTrue, reason: 'the box of a diagonal line covers other fields');
      expect(validateSpec(spec).where((i) => i.code == 'overlap'), isEmpty);
      final qr = spec.copyWith(fields: [for (final f in spec.fields) f.id == 'sid' ? f.copyWith(source: 'qr') : f]);
      expect(validateSpec(qr).map((i) => i.code), contains('strip_source'));
    });

    test('the editor: a strip drag is one undo step and its box follows; a tap beside the line selects what is really there', () {
      final m = MarkEditorModel(_stripSpec());
      expect(m.hit(const Offset(.32, .13)), 'q1', reason: 'inside the diagonal bounding box but off the line');
      expect(m.hit(_menoufia.midpoint() + const Offset(0, -.003)), 'sid');
      m.select('sid');
      m.beginDrag();
      final moved = _menoufia.shifted(const Offset(.05, .05));
      m.dragStrip('sid', moved);
      m.endDrag(changed: true);
      expect(m.selected!.strip!.p1, moved.p1);
      expect(m.selected!.box, moved.enclosingBox(_aspect));
      m.undo();
      expect(m.selected!.strip!.p1, _menoufia.p1);
      m.update(m.selected!.copyWith(strip: _menoufia.copyWith(search: 0)));
      expect(m.selected!.box, _menoufia.copyWith(search: 0).enclosingBox(_aspect), reason: 'the form changes the margin, the box follows');
    });
  });

  group('built-in covers', () {
    test('the server row, and a copy is found again rather than made twice', () {
      final b = MarkBuiltin.fromJson({'key': 'menoufia_cover', 'kind': 'cover', 'name_ar': 'غلاف', 'name_en': 'Cover', 'note_ar': 'ن', 'note_en': 'n', 'fields_count': 14, 'total_max': 100.0, 'image_url': '/api/v1/exam/mark-templates/builtins/menoufia_cover/image'});
      expect(b.kind, MarkKind.cover);
      expect(b.fieldsCount, 14);
      expect(b.note, 'n');
      expect(b.copyName(50), 'Cover · 50');
      final mine = [_tplRow(1, 'Other', total: 50), _tplRow(2, 'Cover · 100'), _tplRow(3, 'غلاف · 50', total: 50), _tplRow(4, 'Cover', total: 75, status: 'retired')];
      expect(b.copyFor(mine, 100)!.id, 2);
      expect(b.copyFor(mine, 50)!.id, 3, reason: 'the copy made while the app was in the other language');
      expect(b.copyFor(mine, 75), isNull, reason: 'a retired copy is not reused');
      expect(b.copyFor(mine, 20), isNull, reason: 'another full mark needs its own copy: every field maximum differs');
    });

    test('the full mark as typed', () {
      expect(parseFullMark(' 50 '), 50);
      expect(parseFullMark('٧٥'), 75);
      expect(parseFullMark('12,5'), 12.5);
      expect(parseFullMark('0'), isNull);
      expect(parseFullMark('1001'), isNull);
      expect(parseFullMark('x'), isNull);
    });
  });

  group('matching a seat number', () {
    test('the teacher\'s own naming decides, the Data Lab number next, otherwise nothing is guessed', () {
      expect(looksLikeSeatNumber('رقم الجلوس'), isTrue);
      expect(looksLikeSeatNumber('Seat No'), isTrue);
      expect(looksLikeSeatNumber('Midterm'), isFalse);
      const cols = [(key: 'a', label: 'Phone'), (key: 'b', label: 'رقم الجلوس')];
      expect(revisionSeatMatch(identifiers: 9, columns: cols), const RevisionMatch('datalab', 'b'));
      expect(revisionSeatMatch(identifiers: 9, columns: const []), kRevisionDataLabIdentifier);
      expect(revisionSeatMatch(identifiers: 0, columns: const []), isNull);
      const sheet = RevisionSheetPreview(sheetKey: 'k', rows: 2, columns: [RevisionSheetColumn(name: 'Name'), RevisionSheetColumn(name: 'Seat number'), RevisionSheetColumn(name: 'Degree')]);
      expect(revisionSeatColumn(sheet), 'Seat number');
      expect(revisionSeatColumn(sheet, degreeColumn: 'Seat number'), isNull);
    });
  });

  group('an unsure number', () {
    test('calibration: "we will ask" is a normal verdict that does not block, an empty allowed box is no problem', () {
      expect(_coverSample().verdict(strip: true), SampleVerdict.willAsk);
      expect(_coverSample(candidates: const []).verdict(strip: true), SampleVerdict.willAsk, reason: 'a strip with no candidates: still asked, still fine');
      expect(_coverSample(candidates: const []).verdict(), SampleVerdict.partial);
      expect(_coverSample(student: 22).verdict(strip: true), SampleVerdict.good);
      final s = _coverSample();
      expect(s.problems, isEmpty);
      expect(s.accuracy, closeTo(.9, 1e-9), reason: 'the empty box says nothing about accuracy');
      expect(s.candidates.map((c) => c.id), [23, 22, 24], reason: 'the closest first, an already-matched student cut or last');
      expect(s.ruleFound, isFalse);
      expect(_coverSample(reason: 'no_candidates', candidates: const []).rosterEmpty, isTrue);
      expect(s.rosterEmpty, isFalse);
    });

    test('run: the candidates are ordered, already-matched last; a written name becomes one choice', () {
      final r = RevisionRow.fromJson(_unconfirmedJson(1));
      expect(r.needsStudent, isTrue);
      expect(r.identifierCropUrl, contains('/crops/'));
      expect(r.rosterReason, 'weak_margin');
      expect(orderRevisionCandidates(const [
        RevisionCandidate(id: 1, name: 'A', score: .9, alreadyMatched: true),
        RevisionCandidate(id: 2, name: 'B', score: .3),
        RevisionCandidate(id: 3, name: 'C', score: .5),
      ]).map((c) => c.id), [3, 2, 1]);
      final byName = RevisionRow.fromJson({
        ..._rowJson(2, list: 'unreadable', student: null),
        'identifier': {'value_masked': '', 'candidate': {'id': 5, 'name': 'Laila'}, 'candidates': []},
      });
      expect(byName.choices.single.fromName, isTrue);
      expect(byName.choices.single.id, 5);
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
    late Map<int, Map<String, dynamic>> pageRows;

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
            final row = pageRows[id] ?? switch (id) { 201 => _rowJson(1, list: 'match', recorded: 16), 202 => _rowJson(2), 203 => _rowJson(3, student: 'Omar Said'), _ => _rowJson(id) };
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
      pageRows = {};
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

    testWidgets('choosing a student goes through assign_student, then the same compare: a match is quiet', (tester) async {
      pageRows[201] = _unconfirmedJson(1);
      await open(tester);
      await shoot(tester);
      read(201);
      await _frames(tester, 6);
      expect(find.text('Whose paper is this?'), findsOneWidget);
      expect(find.byKey(const ValueKey('rv.choice.taken')), findsNothing, reason: 'three choices, the already-matched one is cut by the closer ones');
      expect(tester.getTopLeft(find.text('Omar Said')).dy, lessThan(tester.getTopLeft(find.text('Sara Ali')).dy), reason: 'the closest first');
      decideReplies.add(_rowJson(1, list: 'match', recorded: 16, student: 'Omar Said'));
      await tester.tap(find.byKey(const ValueKey('rv.choice.23')));
      await _frames(tester, 6);
      expect(decided.single['action'], 'assign_student');
      expect(decided.single['student_id'], 23);
      expect(find.byKey(const ValueKey('rv.choice.23')), findsNothing);
      expect(find.textContaining('Omar Said · 16'), findsOneWidget, reason: 'the degree matched: one quiet line');
      expect(find.byKey(const ValueKey('rv.update')), findsNothing);
      await close(tester);
    });

    testWidgets('a chosen student whose degree differs moves on to the System / Scanned decision', (tester) async {
      pageRows[201] = _unconfirmedJson(1);
      await open(tester);
      await shoot(tester);
      read(201);
      await _frames(tester, 6);
      decideReplies.add(_rowJson(1, student: 'Sara Ali'));
      await tester.tap(find.byKey(const ValueKey('rv.choice.22')));
      await _frames(tester, 6);
      expect(decided.single['student_id'], 22);
      expect(find.byKey(const ValueKey('rv.update')), findsOneWidget, reason: 'same paper, now a real comparison');
      expect(find.text('System degree'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('rv.name'))).data, 'Sara Ali');
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
      'built-in card': () => RevisionBuiltinCard(builtin: _builtin, onTap: () {}, load: (_) async => _jpeg, selected: true),
      'built-in full mark': () => SingleChildScrollView(child: RevisionBuiltinMarkSheet(builtin: _builtin, initial: 20, columnMax: 20, load: (_) async => _jpeg, onDone: (_) {})),
      'template step (built-ins, none of mine)': () => SingleChildScrollView(child: RevisionTemplateStep(setup: RevisionSetup(), templates: const [], builtins: const [_builtin], onBuiltin: (_) {}, onPick: (_) {}, onCreate: () {}, onEdit: () {}, onStep: (_) {})),
      'template step (built-ins + mine)': () => SingleChildScrollView(child: RevisionTemplateStep(setup: RevisionSetup(), templates: [_tplRow(1, 'Cover')], builtins: const [_builtin], builtinBusy: 'menoufia_cover', onPick: (_) {}, onCreate: () {}, onEdit: () {}, onStep: (_) {})),
      'match step (steered)': () => SingleChildScrollView(
            child: RevisionMatchStep(
              setup: RevisionSetup()
                ..source = RevisionSource.gradebook
                ..template = const RevisionTemplateChoice(id: 1, name: 'x', totalMax: 20, identifierSource: 'academic_id', strip: _menoufia),
              options: {null: 'Academic number', kRevisionDataLabIdentifier: 'Seat number in Data Lab', const RevisionMatch('datalab', 'x'): 'A long column name that goes on and on and on'},
              onPick: (_) {},
              identifiers: 12,
            ),
          ),
      'match step (a sheet column)': () => SingleChildScrollView(
            child: RevisionMatchStep(
              setup: RevisionSetup()
                ..source = RevisionSource.excel
                ..template = const RevisionTemplateChoice(id: 1, name: 'x', totalMax: 20, identifierSource: 'academic_id', strip: _menoufia)
                ..adoptSheet(const RevisionSheetPreview(sheetKey: 'k', rows: 4, columns: [RevisionSheetColumn(name: 'Seat number', samples: ['1001', '1002'], guess: 'identifier'), RevisionSheetColumn(name: 'Degree', samples: ['12'], guess: 'degree')])),
              options: const {},
              onPick: (_) {},
              onSheetColumn: (_) {},
            ),
          ),
      'sample (strip, we will ask)': () => SingleChildScrollView(child: RevisionSampleView(sample: _coverSample(strip: _jpeg), aspect: _aspect, strip: _menoufia, onChangeMatch: () {})),
      'sample (strip, nobody has this number)': () => SingleChildScrollView(child: RevisionSampleView(sample: _coverSample(strip: _jpeg, reason: 'no_candidates', candidates: const []), aspect: _aspect, strip: _menoufia, onChangeMatch: () {})),
      'choose student': () => Center(child: SingleChildScrollView(child: RevisionChooseStudent(row: RevisionRow.fromJson(_unconfirmedJson(1)), behind: 2, loadCrop: (_) async => _jpeg, onChoose: (_) {}, onSearch: () {}, onRetake: () {}, onLater: () {}))),
      'choose student (panel)': () => RevisionResultPanel(row: RevisionRow.fromJson(_unconfirmedJson(1)), session: session, photo: _jpeg, behind: 1, busy: true, pendingStudentId: 23, loadCrop: (_) async => _jpeg, onChoose: (_) {}, onAssign: () {}, onRetake: () {}, onLater: () {}),
      'choose student (nobody close)': () => RevisionResultPanel(row: RevisionRow.fromJson(_unconfirmedJson(1, candidates: const [], reason: 'no_candidates', crop: null)), session: session, onAssign: () {}, onRetake: () {}, onLater: () {}),
      'strip form': () => SingleChildScrollView(child: MarkFieldForm(field: _stripSpec().field('sid')!, issues: const [], onType: (_) {}, onChanged: (_, {coalesce}) {}, onDelete: () {})),
      'optional mark form': () => SingleChildScrollView(child: MarkFieldForm(field: _stripSpec().field('q1')!, issues: const [], onType: (_) {}, onChanged: (_, {coalesce}) {}, onDelete: () {})),
      'canvas with a selected strip': () => MarkCanvas(model: MarkEditorModel(_stripSpec())..select('sid'), aspect: _aspect, image: _jpeg),
      'style step': () => SingleChildScrollView(child: RevisionStyleStep(styles: const RevisionStyles(degree: RevisionStyle(kind: WriteKind.printed)), hasPhoto: true, sample: _sample(), previous: _sample(value: '3', conf: .6), onChanged: (_) {}, onRestore: () {})),
    };
    for (final e in map.entries) {
      testWidgets(e.key, (tester) async => expectNoLayoutErrors(tester, e.value));
    }
  });
}
