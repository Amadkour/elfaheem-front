import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_flow.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('upload / marks / mapping results parse', () {
    final u = ScanUploadResult.fromJson({'batch_id': 4, 'pages': 12, 'duplicates': 2});
    expect((u.batchId, u.pages, u.duplicates), (4, 12, 2));
    expect(u.summary, contains('12 pages'));
    expect(u.summary, contains('2 duplicates'));
    expect(ScanUploadResult.fromJson({'batch_id': 1, 'pages': 3, 'duplicates': 0}).summary, isNot(contains('duplicates')));
    final m = MarksImportResult.fromJson({'saved': 5, 'attempts': 2, 'errors': [{'row': 3, 'code': 'score_out_of_range', 'max': 4.0}]});
    expect((m.saved, m.attempts), (5, 2));
    expect(m.problems.length, 1);
    expect(MappingResult.fromJson({'assigned': 7, 'errors': []}).assigned, 7);
  });

  test('problem rows read as text in both languages', () {
    final p = parseProblems([
      {'row': 3, 'code': 'score_out_of_range', 'max': 4.0},
      {'row': 5, 'code': 'not_a_student', 'student_id': 99},
      {'row': 0, 'code': 'missing_columns', 'need': ['student_id', 'file_name']},
      {'row': 2, 'code': 'question_not_in_paper', 'question_id': 8},
    ]);
    expect(paperProblemText(p[0]), 'Row 3: Score out of range (maximum 4.0)');
    expect(paperProblemText(p[1]), contains('99'));
    expect(paperProblemText(p[2]), 'Missing columns: student_id, file_name');
    expect(paperProblemText(p[3]), contains('8'));
    AppConfig.lang = 'ar';
    expect(paperProblemText(p[0]), startsWith('الصف 3'));
  });

  test('every route code has text; unknown falls back', () {
    for (final c in ['students_required', 'not_a_student', 'too_many_files', 'upload_too_large', 'no_files', 'unsupported_file', 'grading_busy',
        'bad_mapping_file', 'bad_marks_file', 'too_many_rows', 'scan_not_found', 'scan_not_rendered', 'file_too_large', 'too_many_pages']) {
      expect(paperCodeText(c), isNot(c), reason: c);
    }
    expect(paperCodeText('bad_passcode'), isNot('bad_passcode')); // shared exam codes
    expect(paperCodeText('zzz'), 'zzz');
    expect(paperFailText('unsupported_file', 'x'), contains('Unsupported'));
    expect(paperFailText(null, 'boom'), 'boom');
    expect(paperFailText(null, ''), isNotEmpty);
  });

  test('student ids and roster', () {
    expect(parseStudentIds('12, 15 ٣٢\n40;12 x -3 0'), [12, 15, 32, 40]);
    expect(parseStudentIds(''), isEmpty);
    expect(rosterFromAttempts({'items': [{'student_id': 9}, {'student_id': 3}, {'student_id': 9}, {'student_id': null}]}), [3, 9]);
    expect(rosterFromAttempts({'items': [{'student_id': null}]}), isEmpty);
    expect(batchIdsOf({'items': [{'batch_id': 2}, {'batch_id': 5}, {'batch_id': 2}, {}]}), [5, 2]);
  });

  testWidgets('tools panel has no layout errors, busy and idle', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: PaperToolsPanel(busy: null, onSheets: () {}, onUpload: () {}, onMapping: () {}, onMarks: () {})));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: PaperToolsPanel(busy: 'upload', onSheets: () {}, onUpload: () {}, onMapping: () {}, onMarks: () {})));
  });

  testWidgets('result view with many problems', (tester) async {
    final probs = [for (var i = 1; i <= 60; i++) PaperProblem(row: i, code: 'score_out_of_range', extra: const {'max': 4})];
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: PaperResultView(summary: 'Saved 5 marks for 2 students ' * 4, problems: probs)));
    await expectNoLayoutErrors(tester, () => const PaperResultView(summary: 'ok'));
  });

  testWidgets('sheets options and student picker', (tester) async {
    final ids = TextEditingController(), blank = TextEditingController(text: '0');
    addTearDown(() { ids.dispose(); blank.dispose(); });
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
        child: SheetsOptionsView(roster: [for (var i = 1; i < 60; i++) i * 1000], selected: const {1000}, onToggle: (_) {}, idsController: ids,
            blankController: blank, onSubmit: () {}, onShare: () {})));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
        child: SheetsOptionsView(roster: const [], selected: const {}, onToggle: (_) {}, idsController: ids, blankController: blank, onSubmit: () {}, onShare: () {}, busy: true)));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
        child: StudentPickView(roster: [for (var i = 1; i < 40; i++) i * 111], selected: 111, onSelect: (_) {}, idController: ids)));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: StudentPickView(roster: const [], selected: null, onSelect: (_) {}, idController: ids)));
  });
}
