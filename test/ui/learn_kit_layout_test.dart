// The learn kit (D-1346) on a phone and a wide window, ar / en, text 1.3: question parts, progress, result; plus
// the pure grading helpers.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/learn_kit/learn_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'جملة طويلة جداً تصف خياراً من الخيارات حتى تلتف على أكثر من سطر في شاشة الهاتف الضيقة';

void main() {
  group('grading', () {
    test('stars follow the server rule', () {
      expect(learnStars(9, 10), 3);
      expect(learnStars(6, 10), 2);
      expect(learnStars(3, 10), 1);
      expect(learnStars(2, 10), 0);
      expect(learnStars(1, 0), 0);
      expect(learnPercent(7, 8), 88);
    });

    test('shuffle never returns the original order', () {
      final r = Random(1);
      for (var i = 0; i < 50; i++) {
        final s = learnShuffle([1, 2, 3], random: r);
        expect(s, isNot(equals([1, 2, 3])));
        expect(s.toSet(), {1, 2, 3});
      }
      expect(learnShuffle([1]), [1]);
    });
  });

  testWidgets('question parts', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(padding: const EdgeInsets.all(16), children: [
        const LearnProgressHeader(current: 3, total: 8, score: 2),
        const SizedBox(height: 12),
        const LearnPrompt(text: _long, caption: 'السؤال الثالث', icon: Icons.quiz_rounded),
        const SizedBox(height: 12),
        LearnOptionList(
          options: const [_long, 'B', 'C', 'Very long English option text that wraps across two lines on a phone'],
          marks: const [LearnMark.wrong, LearnMark.missed, LearnMark.idle, LearnMark.selected],
          onSelect: (_) {},
        ),
        const SizedBox(height: 12),
        LearnChoiceChips(
          options: const ['فاعل', 'مفعول به', _long, 'subject'],
          marks: const [LearnMark.correct, LearnMark.wrong, LearnMark.idle, LearnMark.selected],
          onSelect: (_) {},
        ),
        const SizedBox(height: 12),
        LearnFeedback(correct: false, explanation: _long, actionLabel: 'التالي', onAction: () {}),
        const SizedBox(height: 12),
        const LearnFeedback(correct: true),
      ]),
    );
  });

  testWidgets('result', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(padding: const EdgeInsets.all(16), children: [
        LearnResultView(
          score: 7,
          max: 8,
          pointsAwarded: 5,
          badges: const [
            LearnEarned(icon: Icons.play_arrow_rounded, label: 'أول لعبة'),
            LearnEarned(icon: Icons.emoji_events_rounded, label: 'A very long badge name for a perfect score'),
          ],
          saveError: 'تعذّر حفظ النتيجة. تحقق من الاتصال ثم أعد المحاولة.',
          onRetrySave: () {},
          onReplay: () {},
          onDone: () {},
          note: _long,
        ),
        const SizedBox(height: 12),
        const LearnResultView(score: 0, max: 3, saving: true),
        const SizedBox(height: 12),
        const Wrap(children: [
          LearnBadgeChip(icon: Icons.star_rounded, label: 'جامع النجوم', earned: false, caption: 'اجمع ٣٠ نجمة'),
          LearnStars(stars: 2),
        ]),
      ]),
    );
  });
}
