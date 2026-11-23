import 'package:flutter_education_app/features/games/breaks/play_now_card.dart';
import 'package:flutter_education_app/features/games/breaks/study_timer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

void main() {
  group('StudyTimer', () {
    test('counts only while running and suggests once', () {
      var t = DateTime(2026);
      final s = StudyTimer(limit: const Duration(minutes: 20), now: () => t);
      s.resume();
      t = t.add(const Duration(minutes: 15));
      s.pause();
      t = t.add(const Duration(minutes: 30));
      expect(s.elapsed, const Duration(minutes: 15));
      expect(s.due, isFalse);
      s.resume();
      t = t.add(const Duration(minutes: 5));
      expect(s.due, isTrue);
      expect(s.consumeDue(), isTrue);
      expect(s.consumeDue(), isFalse);
      t = t.add(const Duration(hours: 2));
      expect(s.consumeDue(), isFalse);
    });

    test('a zero limit is never due', () {
      final s = StudyTimer(limit: Duration.zero)..resume();
      expect(s.due, isFalse);
    });
  });

  testWidgets('PlayNowCardView lays out', (tester) async {
    await expectNoLayoutErrors(tester, () => PlayNowCardView(onPlay: () {}));
  });
}
