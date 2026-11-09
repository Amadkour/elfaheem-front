// Exam Hub, F5 (get result): the merge of any exam's sources, the sentences that say what publishing will do, the Data Lab
// preview parse, the export's per-question columns, and the screen's plain-value widgets under the layout harness.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/result/exam_get_result_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/result/exam_result_data.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/result/exam_result_sheets.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/result/parent_grades_link.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> _exam({int? course = 7, String policy = 'when_published', String? published, Map<String, dynamic> settings = const {}, bool anon = false}) => {
      'id': 9,
      'title': 'Physics midterm',
      'course_id': course,
      'status': 'closed',
      'results_policy': policy,
      'results_published_at': published,
      'anonymous_grading': anon,
      'settings': settings,
      'max_score': 20,
      'sections': [
        {
          'title': 'A',
          'mode': 'online',
          'questions': [
            {'id': 100, 'type': 'mcq', 'points': 10, 'body': {'prompt': 'What is force?'}},
            {'id': 101, 'type': 'mcq', 'points': 10, 'body': {'prompt': 'What is mass?'}},
          ],
        },
      ],
    };

Map<String, dynamic> _attempt(int id, int? student, String state, {double? score, double max = 20, bool? passed, bool review = false}) => {
      'id': id,
      'student_id': student,
      'state': state,
      'score': score,
      'max_score': max,
      'percentage': score == null ? null : score * 100 / max,
      'passed': passed,
      'needs_review': review,
    };

ResultsBoard _partialBoard({int? course = 7, bool hub = true, bool anon = false}) => ResultsBoard.fromSources(
      exam: _exam(course: course, anon: anon),
      attempts: {
        'items': [
          _attempt(1, 11, 'graded', score: 18, passed: true),
          _attempt(2, 12, 'graded', score: 8, passed: false),
          _attempt(3, 13, 'submitted'),
          _attempt(4, 14, 'in_progress'),
        ]
      },
      names: const {11: 'سارة أحمد', 12: 'Omar Khaled', 13: 'Laila Mahmoud'},
      hubServer: hub,
    );

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  group('the board', () {
    test('the last settled attempt counts, in-progress is not a result, and the numbers follow', () {
      final b = ResultsBoard.fromSources(exam: _exam(), attempts: {
        'items': [
          _attempt(1, 11, 'graded', score: 4, passed: false),
          _attempt(5, 11, 'graded', score: 16, passed: true),
          _attempt(2, 12, 'graded', score: 10, passed: true),
          _attempt(3, 13, 'submitted'),
          _attempt(4, 14, 'in_progress'),
        ]
      });
      final s = b.stats;
      expect(s.students, 3);
      expect(s.graded, 2);
      expect(s.openStudents, 1);
      expect(s.inProgress, 1);
      expect(s.average, 65);
      expect(s.highest, 80);
      expect(s.lowest, 50);
      expect(s.passRate, 100);
      expect(s.bins[8].count, 1);
      expect(s.bins[5].count, 1);
      expect(s.partial, isTrue);
    });

    test('imported totals fill in the students with no marked attempt, never over a held one', () {
      final b = ResultsBoard.fromSources(
        exam: _exam(),
        attempts: {
          'items': [
            _attempt(1, 11, 'graded', score: 15, passed: true),
            _attempt(2, 12, 'submitted', review: true),
          ]
        },
        degrees: {
          'items': [
            {'student_id': 11, 'name': 'A', 'score': 1, 'max_score': 20},
            {'student_id': 12, 'name': 'B', 'score': 2, 'max_score': 20},
            {'student_id': 13, 'name': 'C', 'score': 10, 'max_score': 20},
            {'student_id': 14, 'name': 'D', 'score': 5, 'max_score': 20},
          ]
        },
      );
      final by = {for (final e in b.stats.entries) e.studentId: e};
      expect(by[11]!.score, 15);
      expect(by[11]!.imported, isFalse);
      expect(by[12]!.open, isTrue);
      expect(by[13]!.imported, isTrue);
      expect(by[13]!.passed, isTrue);
      expect(by[14]!.passed, isFalse);
      expect(b.onlyImported, isFalse);
    });

    test('an exam with only imported totals says so and publishes nothing', () {
      final b = ResultsBoard.fromSources(exam: _exam(), attempts: {'items': []}, degrees: {
        'items': [
          {'student_id': 13, 'name': 'C', 'score': 10, 'max_score': 20},
        ]
      });
      expect(b.onlyImported, isTrue);
      expect(b.sourceLabel, 'Totals from Excel');
      final p = publishPlanOf(b, students: true, parents: true);
      expect(p.button, isNull);
      expect(p.note, contains('Data Lab'));
    });

    test('a scanned exam brings forms, open items, per-question marks and the hardest questions', () {
      final b = ResultsBoard.fromSources(
        exam: _exam(),
        attempts: {
          'items': [_attempt(1, 11, 'graded', score: 15, passed: true)]
        },
        omr: {
          'exam_id': 9,
          'summary': {'open_review_items': 2},
          'students': [
            {
              'attempt_id': 1,
              'student_id': 11,
              'name': 'Salma',
              'state': 'graded',
              'graded': true,
              'form': 'B',
              'open_review': 0,
              'questions': [
                {'n': 1, 'score': 10, 'max': 10},
                {'n': 2, 'score': 5, 'max': 10},
              ],
            }
          ],
          'questions': [
            {'n': 1, 'question_id': 100, 'scored': 5, 'difficulty': 0.9, 'distribution': {}},
            {'n': 2, 'question_id': 101, 'scored': 5, 'difficulty': 0.2, 'most_chosen_wrong': 'C', 'most_chosen_wrong_count': 3, 'distribution': {}},
          ],
        },
      );
      final e = b.stats.entries.single;
      expect(e.name, 'Salma');
      expect(e.form, 'B');
      expect(e.questions.length, 2);
      expect(b.stats.openScanItems, 2);
      expect(b.hardest.first.n, 2);
      expect(b.hardest.first.prompt, 'What is mass?');
      expect(b.hardest.first.wrong, 'C');
    });

    test('an online exam takes the hardest questions from the analysis, as a mean mark', () {
      final b = ResultsBoard.fromSources(
        exam: _exam(),
        attempts: {'items': []},
        analytics: {
          'state': 'ready',
          'data': {
            'items': [
              {'question_id': 101, 'answered': 8, 'difficulty': 0.3, 'points': 10},
              {'question_id': 100, 'answered': 8, 'difficulty': 1.0, 'points': 10},
            ]
          },
        },
      );
      expect(b.hardest.length, 1);
      expect(b.hardest.single.n, 2);
      expect(b.hardest.single.isMeanMark, isTrue);
    });
  });

  group('what publishing will do', () {
    test('says who sees it, who is held, and whether parents are told', () {
      final b = _partialBoard();
      final off = publishPlanOf(b, students: true, parents: false);
      expect(off.text, contains('2 students'));
      expect(off.text, contains('1 student not fully marked'));
      expect(off.text, contains('Parents get no notice'));
      expect(off.button, 'Publish what is graded…');
      expect(publishPlanOf(b, students: true, parents: true).text, contains('Their parents get a notice'));
      expect(publishPlanOf(b, students: false, parents: false).button, isNull);
    });

    test('once published, only telling the parents is left; an old server never offers it', () {
      final published = ResultsBoard.fromSources(exam: _exam(published: '2026-11-09T10:00:00'), attempts: {'items': [_attempt(1, 11, 'graded', score: 15, passed: true)]});
      expect(publishPlanOf(published, students: true, parents: false).button, isNull);
      expect(publishPlanOf(published, students: true, parents: true).button, 'Tell the parents');
      final old = ResultsBoard.fromSources(exam: _exam(published: '2026-11-09T10:00:00'), attempts: {'items': [_attempt(1, 11, 'graded', score: 15, passed: true)]}, hubServer: false);
      expect(publishPlanOf(old, students: true, parents: true).button, isNull);
    });

    test('an exam whose policy decides for itself has nothing to publish', () {
      final b = ResultsBoard.fromSources(exam: _exam(policy: 'after_submit'), attempts: {'items': [_attempt(1, 11, 'graded', score: 15, passed: true)]});
      expect(b.publishable, isFalse);
      expect(publishPlanOf(b, students: true, parents: true).button, isNull);
    });
  });

  group('the Data Lab', () {
    test('the tile explains or hides', () {
      expect(labAccessOf(hubServer: true, disabled: const [], courseId: 7, anonymous: false), LabAccess.ready);
      expect(labAccessOf(hubServer: true, disabled: const [], courseId: null, anonymous: false), LabAccess.noCourse);
      expect(labAccessOf(hubServer: true, disabled: const [], courseId: 7, anonymous: true), LabAccess.anonymous);
      expect(labAccessOf(hubServer: true, disabled: const [kResultsDataLabKey], courseId: 7, anonymous: false), LabAccess.hidden);
      expect(labAccessOf(hubServer: false, disabled: const [], courseId: 7, anonymous: false), LabAccess.hidden);
    });

    test('preview parse, overwrites and scale', () {
      final p = LabPreviewData.fromJson({
        'column': {'key': 'mid', 'label_ar': 'نصفي', 'label_en': 'Midterm', 'max': 40},
        'scale': 2,
        'matched': 3,
        'unchanged': 1,
        'held': 1,
        'changes': [
          {'student_id': 1, 'name': 'A', 'old': null, 'new': 30},
          {'student_id': 2, 'name': 'B', 'old': 10, 'new': 20},
        ],
        'unmatched': [
          {'student_id': 3, 'name': null},
        ],
      });
      expect(p.label, 'Midterm');
      expect(p.overwrites, 1);
      expect(p.scaled, isTrue);
      expect(p.examMax, 20);
      expect(p.unmatched.single, 'Student #3');
    });

    test('the column offered first, and the body sends exactly one target', () {
      const cols = [LabColumnChoice('a', 'Quiz', 10), LabColumnChoice('b', 'Physics midterm', 20)];
      expect(labDefaultColumn(cols, lastWritten: 'a', title: 'Physics midterm'), 'a');
      expect(labDefaultColumn(cols, lastWritten: 'gone', title: 'physics MIDTERM'), 'b');
      expect(labDefaultColumn(cols, title: 'Other'), isNull);
      expect(labBody(columnKey: 'a'), {'column_key': 'a'});
      expect(labBody(newLabel: 'X', newMax: 20), {'new_column': {'label_ar': 'X', 'label_en': 'X', 'max': 20.0}});
    });
  });

  test('the export carries a column per question, and folds them away when there are too many', () {
    ResultsBoard withQuestions(int count) => ResultsBoard(
          examId: 9,
          title: 'T',
          stats: ResultStats([
            ResultEntry(key: 'a1', name: 'A', state: ResultState.graded, attemptId: 1, score: 5, maxScore: 10, percent: 50, questions: [for (var i = 1; i <= count; i++) ResultQuestionMark(i, 1, 2)]),
          ]),
        );
    final few = examHubResultsExport(withQuestions(3));
    expect(few.columns.where((c) => c.id.startsWith('q')).length, 3);
    expect(few.columns.firstWhere((c) => c.id == 'q2').visible, isTrue);
    expect(few.rows.single['q3'], 1);
    final many = examHubResultsExport(withQuestions(kExportQuestionsVisible + 1));
    expect(many.columns.firstWhere((c) => c.id == 'q1').visible, isFalse);
  });

  test('the parent link opens the named child, else the only child, else asks', () {
    final one = [<String, dynamic>{'id': 5, 'name': 'A'}];
    final two = [...one, <String, dynamic>{'id': 6, 'name': 'B'}];
    expect(parentGradesChild(two, 6)!['name'], 'B');
    expect(parentGradesChild(one, null)!['id'], 5);
    expect(parentGradesChild(two, null), isNull);
    expect(parentGradesChild(two, 99), isNull);
  });

  group('layout', () {
    ResultsBoard big() => ResultsBoard.fromSources(
          exam: _exam(settings: const {'data_lab_column': 'mid'}),
          attempts: {
            'items': [
              for (var i = 1; i <= 14; i++) _attempt(i, 100 + i, i == 3 ? 'submitted' : 'graded', score: i == 3 ? null : 6.0 + i, passed: i > 5),
            ]
          },
          names: {for (var i = 1; i <= 14; i++) 100 + i: i.isEven ? 'عبد الرحمن محمد عبد الله الشافعي $i' : 'Student with quite a long full name $i'},
          analytics: {
            'state': 'ready',
            'data': {
              'items': [
                {'question_id': 101, 'answered': 8, 'difficulty': 0.3, 'points': 10},
              ]
            },
          },
        );

    testWidgets('the whole board, phone and desktop', (tester) async {
      // `wide` follows the width, as the screen decides it
      await expectNoLayoutErrors(tester, () => LayoutBuilder(builder: (_, box) => ListView(children: [ResultBoardView(board: big(), wide: box.maxWidth >= 1000, columnLabel: 'الامتحان النصفي للفصل الدراسي', callbacks: ResultBoardCallbacks(onExport: () {}, onStudio: () {}, onImport: () {}))])));
    });

    testWidgets('nothing yet, refusals, the old server', (tester) async {
      final empty = ResultsBoard.fromSources(exam: _exam(), attempts: {'items': []});
      await expectNoLayoutErrors(tester, () => ListView(children: [ResultBoardView(board: empty, wide: false, callbacks: ResultBoardCallbacks(onCorrect: () {}, onImport: () {}))]));
      await expectNoLayoutErrors(tester, () => ListView(children: [ResultBoardView(board: _partialBoard(course: null), wide: false)]));
      await expectNoLayoutErrors(tester, () => ListView(children: [ResultBoardView(board: _partialBoard(anon: true), wide: false)]));
      await expectNoLayoutErrors(tester, () => ListView(children: [ResultBoardView(board: _partialBoard(hub: false), wide: false)]));
    });

    testWidgets('the diff and the import summary', (tester) async {
      final p = LabPreviewData(
        key: 'mid',
        label: 'الامتحان النصفي للفصل الدراسي الأول',
        max: 40,
        scale: 2,
        held: 2,
        unchanged: 4,
        changes: [for (var i = 0; i < 12; i++) LabChange('عبد الرحمن محمد عبد الله الشافعي $i', i.isEven ? 10 : null, 20.5)],
        unmatched: [for (var i = 0; i < 8; i++) 'Student number $i'],
      );
      await expectNoLayoutErrors(tester, () => ListView(padding: const EdgeInsets.all(16), children: [ResultLabDiff(preview: p)]));
    });

    testWidgets('the published state keeps its status and export card', (tester) async {
      final b = ResultsBoard.fromSources(exam: _exam(published: '2026-11-09T10:00:00', settings: const {'notify_parents': true}), attempts: {'items': [_attempt(1, 11, 'graded', score: 15, passed: true)]});
      await expectNoLayoutErrors(tester, () => ListView(children: [ResultBoardView(board: b, wide: false, callbacks: ResultBoardCallbacks(onExport: () {}, onStudio: () {}))]), act: (t) async {
        expect(find.byKey(const ValueKey('result.export.studio')), findsOneWidget);
      });
    });
  });
}
