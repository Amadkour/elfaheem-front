import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/engine_exams_section.dart' show EngineExamCard;
import 'package:flutter_education_app/features/shared/exam_engine/exam_consent_screen.dart' show ConsentBody;
import 'package:flutter_education_app/features/shared/exam_engine/exam_integrity.dart' show IntegrityDedupe;
import 'package:flutter_education_app/features/shared/exam_engine/exam_result_screen.dart' show ExamResultBody;
import 'package:flutter_education_app/features/shared/exam_engine/exam_taking.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_taking_screen.dart'
    show ExamNavBar, ExamProgressBar, ExamQuestionCard, ExamQuestionGrid, ExamTimerChip;
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> _paperJson() => {
      'sections': [
        {
          'section_id': 1, 'title': 'Objective', 'mode': 'online', 'navigation': 'free', 'time_box_minutes': null,
          'questions': [
            {'question_id': 1, 'type': 'mcq_single', 'points': 2, 'body': {'prompt': '2+2?', 'options': [{'id': 'a', 'text': '3'}, {'id': 'b', 'text': '4'}]}, 'answer': null, 'save_seq': 0},
            {'question_id': 2, 'type': 'mcq_multi', 'points': 2, 'body': {'prompt': 'primes', 'options': [{'id': 'a', 'text': '2'}, {'id': 'b', 'text': '3'}, {'id': 'c', 'text': '4'}]}, 'answer': {'options': ['a']}, 'save_seq': 3},
            {'question_id': 3, 'type': 'fill_blank', 'points': 1, 'body': {'prompt': 'capital ___ of ___', 'blanks_count': 2}, 'answer': null, 'save_seq': 0},
          ],
        },
        {
          'section_id': 2, 'title': 'Essay', 'mode': 'online', 'navigation': 'one_way', 'time_box_minutes': 10,
          'questions': [
            {'question_id': 4, 'type': 'essay', 'points': 5, 'body': {'prompt': 'explain gravity in a very long prompt ' * 6}, 'answer': null, 'save_seq': 0},
            {'question_id': 5, 'type': 'numeric', 'points': 1, 'body': {'prompt': 'g?', 'units': ['m/s^2', 'cm/s^2']}, 'answer': null, 'save_seq': 0},
            {'question_id': 6, 'type': 'ordering', 'points': 3, 'body': {'prompt': 'order', 'items': ['first', 'second', 'third']}, 'answer': null, 'save_seq': 0},
            {'question_id': 7, 'type': 'matching', 'points': 2, 'body': {'prompt': 'match', 'left': ['l1', 'l2'], 'right': ['r1', 'r2']}, 'answer': null, 'save_seq': 0},
          ],
        },
        {'section_id': 3, 'title': 'Paper', 'mode': 'paper', 'navigation': 'free', 'questions': []},
      ],
    };

void main() {
  setUp(() => AppConfig.lang = 'ar');

  test('server clock counts down from the server\'s remaining seconds, never from the device clock', () {
    final t0 = DateTime(2026, 1, 1, 12, 0, 0);
    final clock = ServerClock.fromAttempt({'remaining_seconds': 100, 'deadline_at': '2026-01-01T10:01:40'}, t0)!;
    expect(clock.remainingAt(t0.add(const Duration(seconds: 30))), 70);
    expect(clock.remainingAt(t0.add(const Duration(seconds: 500))), 0);
    expect(ServerClock.fromAttempt({'remaining_seconds': null}, t0)!.timed, isFalse);
    expect(clockText(59), '00:59');
    expect(clockText(3661), '1:01:01');
  });

  test('paper: sections, answered count, one-way navigation', () {
    final p = Paper.fromJson(_paperJson());
    expect(p.sections.length, 3);
    expect(p.all.length, 7);
    expect(p.onlineCount, 7);
    expect(p.answeredCount, 1);
    final q1 = p.all[0], q2 = p.all[1], e1 = p.all[3], e2 = p.all[4];
    expect(p.canNavigate(q2, q1), isTrue, reason: 'free section: back is allowed');
    expect(p.canNavigate(e2, e1), isFalse, reason: 'one-way section: no going back');
    expect(p.canNavigate(e1, e2), isTrue);
    expect(p.canNavigate(e1, q1), isFalse, reason: 'leaving a one-way section backwards is refused');
    expect(p.canNavigate(q2, e1), isTrue);
  });

  test('autosave queue: monotonic save_seq per question, ack removes only the acknowledged sequence', () {
    final p = Paper.fromJson(_paperJson());
    final q = AutosaveQueue();
    final a = p.all[0], b = p.all[1];
    q.put(a, encodeSingle('b'));
    q.put(b, encodeMulti(['c', 'a']));
    expect(a.saveSeq, 1);
    expect(b.saveSeq, 4, reason: 'continues after the server\'s last sequence');
    expect(b.answer, {'options': ['a', 'c']});
    final batch = q.batch();
    expect(batch.length, 2);
    q.put(a, encodeSingle('a'));                  // a newer answer while the batch is in flight
    q.ack(batch, [1, 2]);
    expect(q.length, 1, reason: 'the newer save for question 1 is still pending');
    expect(q.batch().single['save_seq'], 2);
    q.ack(q.batch(), [1]);
    expect(q.isEmpty, isTrue);
    q.put(a, encodeSingle('b'));
    q.put(b, encodeMulti(['a']));
    q.drop(a.questionId);
    expect(q.length, 1, reason: 'a permanently refused item is dropped, the other stays');
    expect(encodeNumeric('  ', unit: 'm/s^2'), isEmpty, reason: 'a blank value is no answer, whatever the unit');
    expect(encodeNumeric('9.8', unit: 'm/s^2'), {'value': '9.8', 'unit': 'm/s^2'});
  });

  test('integrity: one tab_switch per visibility + blur burst; events re-queued keep their order', () {
    final d = IntegrityDedupe();
    final t0 = DateTime(2026, 1, 1, 12);
    expect(d.accept('tab_switch', t0), isTrue);
    expect(d.accept('tab_switch', t0.add(const Duration(milliseconds: 40))), isFalse, reason: 'blur right after hidden is the same switch');
    expect(d.accept('tab_switch', t0.add(const Duration(seconds: 3))), isTrue);
    expect(d.accept('copy_paste', t0), isTrue);
    expect(d.accept('copy_paste', t0), isTrue, reason: 'only tab / full-screen bursts are de-duplicated');
    final buf = EventBuffer();
    buf.add('tab_switch');
    buf.add('other_app');
    final drained = buf.drain();
    buf.add('copy_paste');
    buf.requeue(drained);
    expect(buf.drain().map((e) => e['kind']).toList(), ['tab_switch', 'other_app', 'copy_paste']);
  });

  test('events and actions', () {
    final buf = EventBuffer();
    buf.add('tab_switch');
    expect(buf.hasUrgent, isFalse);
    buf.add('other_app', meta: {'x': 1});
    expect(buf.hasUrgent, isTrue);
    final drained = buf.drain();
    expect(drained.length, 2);
    expect(buf.isEmpty, isTrue);
    final actions = actionsOf({'actions': [{'consequence': 'lock', 'category': 'other_app'}, {'consequence': 'warn', 'category': 'no_face'}]});
    expect(actions.first.locks, isTrue);
    expect(actions.last.warns, isTrue);
    expect(monitoringText({'camera': false}), isNull);
    expect(monitoringText({'camera': true, 'mic': true}), contains('الكاميرا'));
    AppConfig.lang = 'en';
    expect(examCodeText('deadline_passed'), contains('Time is up'));
    expect(examCodeText('unknown_code'), 'unknown_code');
  });

  testWidgets('taking-flow widgets never overflow (every question type, timer, nav, grid, consent, result)', (tester) async {
    final p = Paper.fromJson(_paperJson());
    for (final q in p.all) {
      await expectNoLayoutErrors(tester, () => ExamQuestionCard(question: q, section: p.sections[q.sectionIndex], enabled: true, onAnswer: (_) {}));
    }
    await expectNoLayoutErrors(tester, () => AppBar(title: const Text('Midterm with a long long title'), actions: const [ExamTimerChip(remainingSeconds: 299, timed: true)]));
    await expectNoLayoutErrors(tester, () => const ExamProgressBar(index: 2, total: 7, answered: 1, locked: true, lockReason: 'other_app', pendingSaves: 2));
    await expectNoLayoutErrors(tester, () => ExamNavBar(index: 6, total: 7, canBack: true, submitting: false, onBack: () {}, onNext: () {}, onJump: (_) {},
        answered: const {1: true, 2: false}, questionIds: const [1, 2, 3, 4, 5, 6, 7], onSubmit: () {}));
    await expectNoLayoutErrors(tester, () => ExamQuestionGrid(answered: const {1: true}, questionIds: List.generate(40, (i) => i + 1), current: 3, onJump: (_) {}));
    await expectNoLayoutErrors(tester, () => ConsentBody(title: 'إقرار قبل الاختبار', body: 'نص الإقرار ' * 40, version: 2,
        requires: const {'camera': true, 'mic': false, 'screen': false}, capabilities: const ['a', 'b'], accepted: false, busy: false, onAccept: () {}));
    await expectNoLayoutErrors(tester, () => const ExamResultBody(examTitle: 'Midterm', result: {'visible': true, 'state': 'auto_submitted', 'score': 7.5, 'max_score': 10, 'percentage': 75.0, 'passed': true, 'needs_review': true, 'questions': [{'question_id': 1, 'score': 2}, {'question_id': 2, 'score': null}]}));
    await expectNoLayoutErrors(tester, () => const ExamResultBody(examTitle: 'Midterm', result: {'visible': false, 'state': 'submitted', 'needs_review': true}));
    await expectNoLayoutErrors(tester, () => EngineExamCard(onOpen: () {}, exam: const {
      'title': 'A very long midterm examination title that wraps on narrow phones for sure', 'duration_minutes': 90, 'attempts_used': 1, 'attempts_allowed': 2,
      'starts_at': '2026-03-01T09:00:00', 'can_start': true, 'open_attempt_id': null, 'status': 'published',
      'results': [{'visible': true, 'percentage': 72.5, 'passed': true}],
    }));
  });
}
