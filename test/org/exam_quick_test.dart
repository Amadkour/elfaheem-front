import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_authoring.dart' show TextItem;
import 'package:flutter_education_app/features/shared/exam_engine/exam_quick.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_quick_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_results_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

QuickQuestion _mcq() => QuickQuestion.mcq()
  ..prompt = 'Which gas do plants take in?'
  ..options[0].text = 'CO2'
  ..options[1].text = 'O2'
  ..correct = 'a';

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('defaults', () {
    test('a quiz: 30 min, results after submit, grades accepted automatically', () {
      final q = QuickExam(kind: QuickKind.quiz, courseId: 9);
      expect(q.durationMinutes, 30);
      expect(q.resultsPolicy, 'after_submit');
      expect(q.highStakes, isFalse);
      expect(q.maxAttempts, 1);
      expect(q.mode, isNull);
    });

    test('a timetabled final takes the sitting as its window and duration', () {
      final s = DateTime.utc(2026, 12, 1, 8), e = DateTime.utc(2026, 12, 1, 10, 30);
      final q = QuickExam(kind: quickKindOf('final'), startsAt: s, endsAt: e, scheduleSlotId: 44);
      expect(q.durationMinutes, 150);
      expect(q.highStakes, isTrue);
      expect(q.resultsPolicy, 'when_published');
      q.mode = QuickMode.online;
      final body = q.toExamDraft().toBody();
      expect(body['starts_at'], startsWith('2026-12-01T08:00'));
      expect((body['settings'] as Map)['schedule_slot_id'], 44);
      expect((body['settings'] as Map)['mode'], 'online');
    });

    test('midterm without a sitting: 60 minutes', () {
      expect(QuickExam(kind: QuickKind.midterm).durationMinutes, 60);
    });
  });

  group('types and delivery', () {
    test('true / false: the engine bodies and the key', () {
      final q = QuickQuestion.ofType('true_false')..prompt = 'The sun is a star';
      expect(q.validate(), contains('bad_answer_key'));
      q.engine!.tfCorrect = true;
      expect(q.validate(), isEmpty);
      final d = q.toDraft();
      expect(d.type, 'true_false');
      expect(d.answer()['correct'], true);
      expect(d.body()['prompt'], 'The sun is a star');
    });

    test('complete: blanks are accepted-answer lists', () {
      final q = QuickQuestion.ofType('fill_blank')..prompt = 'Water is ___ and ___';
      expect(q.validate(), contains('blank_answer_required'));
      q.engine!.blanks
        ..first.text = 'H2O, water'
        ..add(TextItem('liquid'));
      expect(q.validate(), isEmpty);
      expect(q.toDraft().answer()['blanks'], [['H2O', 'water'], ['liquid']]);
    });

    test('matching: pairs become left / right and the pair key', () {
      final q = QuickQuestion.ofType('matching')..prompt = 'Match';
      expect(q.validate(), contains('pair_incomplete'));
      q.engine!.pairs
        ..[0].left = 'Cat'
        ..[0].right = 'Meow'
        ..[1].left = 'Dog'
        ..[1].right = 'Woof';
      expect(q.validate(), isEmpty);
      final d = q.toDraft();
      expect(d.body()['left'], ['Cat', 'Dog']);
      expect(d.answer()['pairs'], {'Cat': 'Meow', 'Dog': 'Woof'});
    });

    test('short answer is an open question with a key; difficulty reaches the bank question', () {
      final q = QuickQuestion.ofType('short_answer')..prompt = 'Name the capital of France';
      expect(q.validate(), contains('essay_key_required'));
      q
        ..keyText = 'Paris'
        ..difficulty = 5;
      expect(q.validate(), isEmpty);
      final create = q.toDraft().toCreate();
      expect(create['type'], 'short_answer');
      expect(create['difficulty'], 5);
      expect((create['answer'] as Map)['model'], 'Paris');
    });

    test('every offered type builds a draft of its own type', () {
      for (final ty in quickQuestionTypes) {
        expect(QuickQuestion.ofType(ty).toDraft().type, ty);
      }
    });

    test('delivery is chosen last and drives the section and the settings', () {
      final q = QuickExam(kind: QuickKind.quiz)..questions.add(_mcq());
      expect(q.validate().$1, ['mode_required']);
      q.mode = QuickMode.offline;
      expect(q.validate().$1, isEmpty);
      expect(q.toSection().mode, 'paper');
      expect((q.toExamDraft().toBody()['settings'] as Map)['mode'], 'offline');
      q.mode = QuickMode.online;
      expect(q.toSection().mode, 'online');
      expect(quickModeTitle(QuickMode.offline), 'Print / export');
    });
  });

  group('validate', () {
    test('mode first, then questions', () {
      final q = QuickExam(kind: QuickKind.quiz);
      expect(q.validate().$1, containsAll(['mode_required', 'no_questions']));
      q
        ..mode = QuickMode.online
        ..questions.add(_mcq());
      expect(q.validate().$1, isEmpty);
      expect(q.validate().$2, isEmpty);
    });

    test('an MCQ needs two choices and the right one picked', () {
      final m = QuickQuestion.mcq()..prompt = 'x';
      expect(m.validate(), containsAll(['options_required', 'pick_correct']));
      m.options[0].text = 'a';
      m.options[1].text = 'b';
      m.correct = 'c';                  // an empty choice is not an answer
      expect(m.validate(), ['pick_correct']);
    });

    test('an auto-graded essay needs a key; a hand-marked one does not', () {
      final e = QuickQuestion.essay()..prompt = 'Explain photosynthesis';
      expect(e.validate(), ['essay_key_required']);
      e.autoGrade = false;
      expect(e.validate(), isEmpty);
      expect(e.toDraft().validate(), isEmpty);       // the full model agrees (auto_grade false needs no model answer)
    });

    test('a file exam needs the file', () {
      final q = QuickExam(kind: QuickKind.quiz)
        ..mode = QuickMode.offline
        ..source = QuickSource.file;
      expect(q.validate().$1, ['file_required']);
      q
        ..fileName = 'paper.pdf'
        ..filePath = '/tmp/paper.pdf';
      expect(q.validate().$1, isEmpty);
    });
  });

  group('essay key → answer key', () {
    test('model paragraph', () {
      final a = (QuickQuestion.essay()
            ..prompt = 'p'
            ..keyText = 'Plants turn light into sugar.')
          .toDraft()
          .answer();
      expect(a['model'], 'Plants turn light into sugar.');
      expect(a.containsKey('rubric'), isFalse);
    });

    test('key points share the points exactly', () {
      final a = (QuickQuestion.essay()
            ..prompt = 'p'
            ..points = 5
            ..keyBy = EssayKey.points
            ..keyText = 'uses light\n\nmakes glucose\nreleases oxygen')
          .toDraft()
          .answer();
      final rubric = a['rubric'] as List;
      expect(rubric.length, 3);
      expect(rubric.map((c) => c['criterion']), ['uses light', 'makes glucose', 'releases oxygen']);
      expect(rubric.fold<double>(0, (s, c) => s + (c['points'] as double)), closeTo(5, 1e-9));
    });

    test('must-have words become keyword criteria with synonyms', () {
      final a = (QuickQuestion.essay()
            ..prompt = 'p'
            ..points = 4
            ..keyBy = EssayKey.keywords
            ..keyText = 'chlorophyll\nlight = sunlight, sun')
          .toDraft()
          .answer();
      final rubric = a['rubric'] as List;
      expect(rubric[1]['keywords'], [
        {'term': 'light', 'synonyms': ['sunlight', 'sun']}
      ]);
      expect(rubric.map((c) => c['points']), [2.0, 2.0]);
    });

    test('auto-grading off sends auto_grade false and no key', () {
      final a = (QuickQuestion.essay()
            ..prompt = 'p'
            ..autoGrade = false
            ..keyText = 'ignored')
          .toDraft()
          .answer();
      expect(a['auto_grade'], isFalse);
      expect(a['model'], '');
    });
  });

  test('splitPoints keeps the total', () {
    expect(splitPoints(10, 3), [3.33, 3.33, 3.34]);
    expect(splitPoints(1, 1), [1.0]);
    expect(splitPoints(5, 0), isEmpty);
  });

  group('sections and questions', () {
    test('online questions: one shuffled online section', () {
      final q = QuickExam(kind: QuickKind.quiz)
        ..mode = QuickMode.online
        ..questions.add(_mcq());
      final s = q.toSection().toBody();
      expect(s['mode'], 'online');
      expect(s['shuffle_questions'], isTrue);
      expect(q.questionDrafts().single.type, 'mcq_single');
    });

    test('offline file: a paper section and one hand-marked question worth the full mark', () {
      final q = QuickExam(kind: QuickKind.finalExam)
        ..mode = QuickMode.offline
        ..source = QuickSource.file
        ..filePoints = 40;
      expect(q.toSection().toBody()['mode'], 'paper');
      expect(q.toSection().toBody()['shuffle_questions'], isFalse);
      final d = q.questionDrafts().single;
      expect(d.type, 'essay');
      expect(d.points, 40);
      expect(d.answer()['auto_grade'], isFalse);
      expect(d.validate(), isEmpty);
    });

    test('online file: students upload their answer', () {
      final q = QuickExam(kind: QuickKind.quiz)
        ..mode = QuickMode.online
        ..source = QuickSource.file;
      expect(q.questionDrafts().single.type, 'file_upload');
      expect(q.questionDrafts().single.validate(), isEmpty);
    });
  });

  test('examForSlot / examsBySlot find the exam made from a slot', () {
    final exams = [
      {'id': 1, 'status': 'draft', 'settings': {'schedule_slot_id': 7}},
      {'id': 2, 'status': 'archived', 'settings': {'schedule_slot_id': 8}},
      {'id': 3, 'status': 'published', 'settings': {}},
    ];
    expect(examForSlot(exams, 7)?['id'], 1);
    expect(examForSlot(exams, 8), isNull);
    expect(examsBySlot(exams).keys, [7]);
  });

  test('results rows: names from the roster, waiting first', () {
    final rows = ResultRow.fromAttempts({
      'items': [
        {'id': 1, 'student_id': 5, 'state': 'graded', 'percentage': 80, 'score': 8, 'max_score': 10, 'needs_review': false},
        {'id': 2, 'student_id': 6, 'state': 'submitted', 'needs_review': true},
        {'id': 3, 'student_id': null, 'state': 'in_progress'},
      ]
    }, {5: 'Zaid', 6: 'Omar'});
    expect(rows.first.name, 'Omar');
    expect(rows.first.needsReview, isTrue);
    expect(rows.firstWhere((r) => r.attemptId == 1).percentage, 80);
    expect(rows.firstWhere((r) => r.attemptId == 3).finished, isFalse);
    expect(averagePercent(rows), 80);
  });

  test('answerSummary', () {
    expect(answerSummary({'text': ' hi '}), 'hi');
    expect(answerSummary({'option': 'b'}), 'b');
    expect(answerSummary({'file': {'name': 'a.pdf'}}), contains('a.pdf'));
    expect(answerSummary({}), '—');
  });

  group('layout', () {
    testWidgets('start chooser', (t) async => expectNoLayoutErrors(t, () => SingleChildScrollView(child: QuickStartChooser(onPick: (_) {}, canGenerate: true))));
    testWidgets('start chooser without a course', (t) async => expectNoLayoutErrors(t, () => SingleChildScrollView(child: QuickStartChooser(onPick: (_) {}, canGenerate: false))));
    testWidgets('delivery chooser', (t) async => expectNoLayoutErrors(t, () => SingleChildScrollView(child: QuickDeliveryChooser(onPick: (_) {}))));

    testWidgets('every question type card', (t) async {
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: Column(children: [
                  for (final ty in quickQuestionTypes)
                    QuickQuestionCard(
                        index: 0,
                        question: QuickQuestion.ofType(ty)..prompt = 'A fairly long question text that has to wrap on a narrow phone ___ screen',
                        errors: const ['pick_correct'],
                        onChanged: () {},
                        onRemove: () {}),
                ]),
              ));
    });

    testWidgets('question cards', (t) async {
      final essay = QuickQuestion.essay()
        ..prompt = 'Explain, in your own words, how photosynthesis and respiration depend on each other in green plants.'
        ..keyBy = EssayKey.keywords;
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: Column(children: [
                  QuickQuestionCard(index: 0, question: _mcq(), errors: const ['pick_correct'], onChanged: () {}, onRemove: () {}),
                  QuickQuestionCard(index: 11, question: essay, errors: const ['essay_key_required'], onChanged: () {}, onRemove: () {}),
                ]),
              ));
    });

    testWidgets('advanced panel and file panel', (t) async {
      final q = QuickExam(kind: QuickKind.finalExam, startsAt: DateTime.utc(2026, 12, 1, 8), endsAt: DateTime.utc(2026, 12, 1, 10))..mode = QuickMode.online;
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: Column(children: [
                  QuickFilePanel(fileName: 'final-exam-biology-and-chemistry-first-term-2026.pdf', points: 40, offline: true, onPick: () {}, onPoints: (_) {}),
                  QuickAdvancedPanel(exam: q, onChanged: () {}),
                ]),
              ),
          act: (t) async {
            await t.tap(find.byType(ExpansionTile));
            await t.pumpAndSettle();
          });
    });

    testWidgets('slot sheet: not created / created', (t) async {
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: Column(children: [
                  SlotExamSheet(courseName: 'Introduction to organic chemistry and biochemistry', when: 'Tue 1 Dec 10:00', canChangeTime: true, onPick: (_) {}),
                  SlotExamSheet(
                      courseName: 'Biology',
                      exam: const {'id': 3, 'title': 'Final exam — Introduction to organic chemistry', 'status': 'published'},
                      onPick: (_) {}),
                ]),
              ));
    });

    testWidgets('results rows and answer cards', (t) async {
      final rows = ResultRow.fromAttempts({
        'items': [
          {'id': 1, 'student_id': 5, 'state': 'graded', 'percentage': 72.5, 'score': 29, 'max_score': 40, 'needs_review': false},
          {'id': 2, 'student_id': 6, 'state': 'submitted', 'needs_review': true},
        ]
      }, {5: 'Abdulrahman Mohammed Al-Hashimi', 6: 'Omar'});
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: Column(children: [
                  for (final r in rows) ResultRowCard(row: r, onTap: () {}),
                  AnswerGradeCard(
                      item: const {'answer_id': 4, 'question_id': 2, 'prompt': 'Explain photosynthesis', 'points': 5, 'auto_score': 3.5,
                        'review_state': 'proposed', 'answer': {'text': 'Plants use light'}},
                      onChange: () {}),
                  AnswerGradeCard(
                      item: const {'answer_id': 5, 'question_id': 3, 'prompt': 'Answer sheet', 'points': 40, 'review_state': 'needs_review',
                        'answer': {'file': {'name': 'my-answer-sheet-scanned-at-home.pdf'}}},
                      onChange: () {},
                      onDownload: () {}),
                ]),
              ));
    });
  });
}
