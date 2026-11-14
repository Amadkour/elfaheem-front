import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/attendance/relay_link.dart' show isReply, isRequest;
import 'package:flutter_education_app/features/exams/engine_exams_section.dart' show EngineExamCard;
import 'package:flutter_education_app/features/exams/exam_taking.dart' show Paper;
import 'package:flutter_education_app/features/exams/offline/offline_exam_core.dart';
import 'package:flutter_education_app/features/exams/offline/offline_exam_screen.dart' show OfflineExamCard, OfflineStepsView;
import 'package:flutter_education_app/features/exams/offline/offline_exam_teacher.dart'
    show OfflineSubmissionTile, OfflineSummaryRow, offlineFlagText, offlineStepText;
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

// Vectors made by the server code (exam_engine/services/offline.py, SECRET_KEY=vector-secret): exam 7 package 2 with a
// fixed nonce, the sealing key of student 42 and a receipt for bundle "abcdef0123456789" → attempt 99.
const _vOpen = 'vObTbD8SQNRps/0nyLxlklxf+R54Dfgw6MnFrwoj6lU=';
const _vPackage = {
  'package_id': '7.2', 'exam_id': 7, 'n': 2, 'title': 'اختبار', 'questions': 1,
  'hash': '5710a9f3c46e71148e43370f0bb8db3275dbc089d779d2c8ea6ab120a57fe5a4',
  'nonce': 'AAECAwQFBgcICQoL',
  'data': '+VswP5tEeAOhVRWyUHxj+p9y6qcfQTykOJxFZVUtZbf1GSK2mXJo8A1qs9lyROEfi9B9l+rZnaNJCkpRWpNOGangOzAWsVVT0omW0xXuatvDFwqf1Wi6RKRQxbJCzjBxJzbaQqlZ1thOjEoX5CmnOSOYi3pca3fd9zfqm6oRCBbMKmbds7PPd6hDpgDnVsxWse2JcOlgemHDAJ7xxCx3b0z634m2PTE2OJIVqzwTwqan4uE+KjYjFjEotgaqo/ugYpQjdGWHXxnKscME8UlhLVfDc8aO0gmyV35h/koisrvAgWhNbprc7xf1ixkVF3sR2uaz0Aj1NpisH51PO73EnJZQJuoIZfrq9Vyp0WappB20APBxEPcRg2ffiICFbHg3PKaEVrkbthbOfDAWCHdfnNWE',
};
const _vSeal = '67040bfa02bcb6e6cc438734af935f775f2552e4f64b889de803d6a9a9903aed';
const _vWrap = 'AAECAwQFBgcICQoLXjJBtl6+47cltT4jw5nOLpbVmsTTj6S+w07WONdkXaMiVWGr2/G3VzL9p0n8QhyR';
const _vReceipt = '365718423514e74dfb5c1af3ecc8ceccc32d3b96175e717b53d61cf3e5604861';

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('package', () {
    test('a server package opens with its key, its hash names the bytes, and the paper parses', () async {
      final p = OfflinePackage.fromJson(Map<String, dynamic>.from(_vPackage));
      expect(p.intact, isTrue);
      final content = await openPackage(p, base64Decode(_vOpen));
      expect(content['title'], 'اختبار');
      final paper = Paper.fromJson(Map<String, dynamic>.from(content['paper'] as Map));
      expect(paper.all.single.questionId, 5);
    });

    test('a wrong key or swapped bytes are refused', () async {
      final p = OfflinePackage.fromJson(Map<String, dynamic>.from(_vPackage));
      await expectLater(openPackage(p, List.filled(32, 1)), throwsA(anything));
      final raw = base64Decode('${_vPackage['data']}')..[3] ^= 1;
      final bad = OfflinePackage.fromJson({..._vPackage, 'data': base64Encode(raw)});
      expect(bad.intact, isFalse, reason: 'the header hash no longer matches');
      await expectLater(openPackage(bad, base64Decode(_vOpen)), throwsA(anything));
    });

    test('openAt follows the window', () {
      final p = OfflinePackage.fromJson({..._vPackage, 'starts_at': '2026-10-26T09:00:00', 'ends_at': '2026-10-26T11:00:00'});
      expect(p.openAt(DateTime.utc(2026, 10, 26, 8, 59)), isFalse);
      expect(p.openAt(DateTime.utc(2026, 10, 26, 9)), isTrue);
      expect(p.openAt(DateTime.utc(2026, 10, 26, 11)), isFalse);
    });
  });

  group('bundle', () {
    test('sealed with the student key: AAD binds bundle, exam and student; the server receipt verifies', () async {
      final b = await sealBundle(bundleId: 'abcdef0123456789', examId: 7, studentId: 42, n: 2, payload: {'answers': []}, studentKeyHex: _vSeal);
      expect(b['enc'], 'k1');
      expect(b.containsKey('payload'), isFalse, reason: 'nothing readable travels');
      final all = base64Decode('${b['data']}');
      final box = SecretBox(all.sublist(0, all.length - 16), nonce: base64Decode('${b['nonce']}'), mac: Mac(all.sublist(all.length - 16)));
      final plain = await AesGcm.with256bits().decrypt(box, secretKey: SecretKey(hexBytes(_vSeal)), aad: utf8.encode('abcdef0123456789|7|42'));
      expect(jsonDecode(utf8.decode(plain)), {'answers': []});
      await expectLater(AesGcm.with256bits().decrypt(box, secretKey: SecretKey(hexBytes(_vSeal)), aad: utf8.encode('abcdef0123456789|7|43')),
          throwsA(anything), reason: 'relabelled for another student → refused');
      expect(verifyReceipt(studentKeyHex: _vSeal, bundleId: 'abcdef0123456789', attemptId: 99, receipt: _vReceipt), isTrue);
      expect(verifyReceipt(studentKeyHex: _vSeal, bundleId: 'abcdef0123456789', attemptId: 98, receipt: _vReceipt), isFalse);
    });

    test('no key → unsealed (only the student or the teacher may upload it)', () async {
      final b = await sealBundle(bundleId: 'b1b1b1b1', examId: 1, studentId: 2, n: 1, payload: {'x': 1});
      expect(b['enc'], 'none');
      expect(b['payload'], {'x': 1});
    });

    test('answers file round trip; junk is ignored', () {
      final b = {'bundle_id': 'x1x1x1x1', 'exam_id': 1, 'student_id': 2, 'enc': 'k1'};
      expect(bundlesInFile(answersFile([b])), [b]);
      expect(bundlesInFile(jsonEncode(b)), [b]);
      expect(bundlesInFile('not json'), isEmpty);
      expect(bundlesInFile(jsonEncode({'bundles': [{'a': 1}]})), isEmpty);
    });
  });

  group('sitting', () {
    test('answers keep a per-question sequence; the payload carries timing and the delivery chain', () {
      final s = OfflineSitting(examId: 7, n: 2, packageHash: 'h', studentId: 42, bundleId: newBundleId(),
          clock: OfflineClock(startedWallMs: DateTime.utc(2026, 10, 26, 9).millisecondsSinceEpoch, elapsedMs: 90000))
        ..put(5, {'value': true})
        ..put(5, {'value': false})
        ..step('package', from: 'peer', by: 12);
      final p = s.payload();
      expect(p['answers'], [
        {'question_id': 5, 'answer': {'value': false}, 'seq': 2}
      ]);
      expect(p['elapsed_seconds'], 90);
      expect(p['started_at'], '2026-10-26T09:00:00.000Z');
      expect((p['delivery'] as List).single, containsPair('by', 12));
      final back = OfflineSitting.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.answers[5], {'value': false});
      expect(back.seq[5], 2);
      expect(back.clock!.elapsedSeconds, 90);
      expect(s.bundleId, matches(RegExp(r'^[0-9a-f]{32}$')));
    });
  });

  group('clock', () {
    const t0 = 1800000000000;
    test('counts monotonic time; moving the phone clock does not add or remove time, it is reported', () {
      final c = OfflineClock(startedWallMs: t0);
      expect(c.tick(monoDeltaMs: 1000, wallNowMs: t0 + 1000), isNull);
      final ev = c.tick(monoDeltaMs: 1000, wallNowMs: t0 - 3600 * 1000);      // set back an hour
      expect(ev?['kind'], 'clock_changed');
      expect(c.elapsedSeconds, 2);
    });

    test('closed app: forward gap counts, backward gap is reported and not counted', () {
      final c = OfflineClock(startedWallMs: t0, elapsedMs: 60000, lastWallMs: t0 + 60000);
      expect(c.resume(wallNowMs: t0 + 360000), isNull);
      expect(c.elapsedSeconds, 360);
      expect(c.resume(wallNowMs: t0)?['kind'], 'clock_changed');
      expect(c.elapsedSeconds, 360);
    });

    test('remaining: the duration and the exam end, whichever comes first', () {
      final c = OfflineClock(startedWallMs: t0, elapsedMs: 25 * 60000);
      final now = DateTime.fromMillisecondsSinceEpoch(t0, isUtc: true);
      expect(c.remainingSeconds(durationMinutes: 30, wallNow: now), 300);
      expect(c.remainingSeconds(durationMinutes: 30, endsAt: now.add(const Duration(minutes: 2)), wallNow: now), 120);
      expect(c.remainingSeconds(durationMinutes: 20, wallNow: now), 0);
      expect(c.remainingSeconds(wallNow: now), isNull);
    });
  });

  test('parts: a package travels in pieces under the Nearby limit and joins back', () {
    final s = 'x' * 30001;
    final parts = splitParts(s);
    expect(parts.length, 3);
    expect(parts.every((p) => p.length <= kExamPartChars), isTrue);
    expect(parts.join(), s);
  });

  test('the relay link routes the exam messages (requests to the host, replies to the waiting client)', () {
    for (final t in ['exam_hello', 'exam_part', 'exam_key', 'exam_submit']) {
      expect(isRequest({'t': t}), isTrue, reason: t);
      expect(isReply({'t': t}), isFalse, reason: t);
    }
    for (final t in ['exam_offer', 'exam_chunk', 'exam_keyed', 'exam_ack', 'exam_receipt']) {
      expect(isReply({'t': t}), isTrue, reason: t);
      expect(isRequest({'t': t}), isFalse, reason: t);
    }
  });

  test('texts exist in both languages', () {
    for (final lang in ['ar', 'en']) {
      AppConfig.lang = lang;
      for (final s in OfflineStage.values) {
        expect(offlineStageText(s), isNotEmpty);
      }
      expect(offlineCodeText('no_attempts_left'), isNot('no_attempts_left'));
      expect(offlineFlagText('clock_changed'), isNot('clock_changed'));
      expect(offlineStepText({'step': 'package', 'from': 'peer'}), contains(lang == 'ar' ? 'زميل' : 'classmate'));
    }
  });

  group('a paper per student (same algorithm as the server, vectors from offline.py)', () {
    test('seeded shuffle', () {
      expect(seededShuffle('abcdefgh'.split(''), '7.2|42', 'o|5'), ['d', 'h', 'b', 'e', 'a', 'g', 'f', 'c']);
    });

    test('pool with a required question, shuffled questions and options', () {
      final paper = {
        'sections': [
          {
            'section_id': 3, 'mode': 'online', 'navigation': 'free', 'shuffle_questions': true, 'shuffle_options': true, 'pool_size': 3,
            'questions': [
              for (final q in [10, 11, 12, 13, 14])
                {'question_id': q, 'type': 'mcq_single', 'points': 1, 'required': q == 10,
                 'body': {'prompt': 'q$q', 'options': [for (final o in 'abcd'.split('')) {'id': o, 'text': o}]}},
            ],
          },
        ],
      };
      final mine = studentPaper(paper, '7.2', 42)['sections'] as List;
      final got = [
        for (final q in (mine.first as Map)['questions'] as List)
          [q['question_id'], [for (final o in (q['body'] as Map)['options'] as List) (o as Map)['id']]],
      ];
      expect(got, [
        [12, ['b', 'a', 'd', 'c']],
        [10, ['b', 'd', 'a', 'c']],
        [14, ['b', 'a', 'd', 'c']],
      ]);
      final other = studentPaper(paper, '7.2', 43);
      expect(jsonEncode(other), isNot(jsonEncode(studentPaper(paper, '7.2', 42))), reason: 'another student, another paper');
      expect(jsonEncode(studentPaper(paper, '7.2', 42)), jsonEncode(studentPaper(paper, '7.2', 42)), reason: 'stable after an app restart');
    });

    test('a section without shuffle or pool is left as authored', () {
      final paper = {
        'sections': [
          {'section_id': 1, 'mode': 'online', 'navigation': 'one_way', 'questions': [
            {'question_id': 1, 'body': {'options': [{'id': 'a'}, {'id': 'b'}]}},
            {'question_id': 2, 'body': {'prompt': 'x'}},
          ]},
        ],
      };
      final q = ((studentPaper(paper, '1.1', 5)['sections'] as List).first as Map)['questions'] as List;
      expect([for (final x in q) (x as Map)['question_id']], [1, 2]);
      expect(((q.first as Map)['body'] as Map)['options'], [{'id': 'a'}, {'id': 'b'}]);
    });
  });

  group('nothing readable on the air', () {
    test('the server wrap opens with the student key only, and gives the exam key', () async {
      final key = await openWrap(wrap: _vWrap, examId: 7, n: 2, studentId: 42, studentKeyHex: _vSeal);
      expect(base64Encode(key!), _vOpen);
      expect(await openWrap(wrap: _vWrap, examId: 7, n: 2, studentId: 43, studentKeyHex: _vSeal), isNull, reason: 'bound to the student');
      expect(await openWrap(wrap: _vWrap, examId: 7, n: 2, studentId: 42, studentKeyHex: 'ab' * 32), isNull, reason: 'a classmate key fails');
    });

    test('the link: both sides derive one key; a listener with its own key reads nothing', () async {
      final a = await ExamLink.create(), b = await ExamLink.create(), eve = await ExamLink.create();
      final box = await a.seal(b.pub, '{"key":"secret"}');
      expect(box.contains('secret'), isFalse);
      expect(await b.open(a.pub, box), '{"key":"secret"}');
      expect(await a.open(b.pub, await b.seal(a.pub, 'back')), 'back');
      await expectLater(eve.open(a.pub, box), throwsA(anything));
      final raw = base64Decode(box)..[20] ^= 1;
      await expectLater(b.open(a.pub, base64Encode(raw)), throwsA(anything), reason: 'changed on the way');
    });
  });

  group('layout', () {
    testWidgets('offline exam card in every stage', (tester) async {
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: Column(children: [
            for (final s in OfflineStage.values)
              OfflineExamCard(title: 'A long offline exam title that wraps onto two lines ' * 2, stage: s, hasKey: s.index.isOdd, questions: 40,
                  durationMinutes: 90, startsAt: DateTime.utc(2026, 10, 26, 9)),
          ])));
    });

    testWidgets('steps with a refusal and with a pending note', (tester) async {
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: Column(children: [
            const OfflineStepsView(stage: OfflineStage.rejected, code: 'no_attempts_left'),
            const OfflineStepsView(stage: OfflineStage.waitingToSync, code: 'held'),
            const OfflineStepsView(stage: OfflineStage.submitted),
          ])));
    });

    testWidgets('teacher tiles and counters', (tester) async {
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: Column(children: [
            const OfflineSummaryRow(summary: {'total': 120, 'graded': 100, 'to_review': 15, 'flagged': 5}),
            OfflineSubmissionTile(item: const {
              'student_id': 123456, 'percentage': 87.5, 'open_answers': 0, 'sealed': false,
              'integrity': ['clock_changed', 'over_time', 'package_mismatch', 'late'],
            }),
            OfflineSubmissionTile(item: const {'student_id': null, 'open_answers': 3, 'sealed': true, 'integrity': []}),
          ])));
    });

    testWidgets('exam card with the saved-for-offline pill', (tester) async {
      await expectNoLayoutErrors(tester, () => EngineExamCard(
          exam: const {'title': 'Midterm with a rather long title', 'can_start': true, 'attempts_used': 0, 'attempts_allowed': 1, 'duration_minutes': 60},
          onOpen: () {}, offlineSaved: true));
    });
  });
}
