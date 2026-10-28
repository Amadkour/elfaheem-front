// The free-time limit of a student's live meeting (docs/backend/live-rooms-spec.md §8, §11): the pure countdown
// rules of lib/features/shared/live/live_time_limit.dart.
import 'package:flutter_education_app/features/shared/live/live_time_limit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final end = DateTime.utc(2026, 10, 28, 10, 15);
  DateTime at(int m, [int s = 0]) => DateTime.utc(2026, 10, 28, 10, 0).add(Duration(minutes: m, seconds: s));

  group('parse', () {
    test('naive UTC (the server convention) is read as UTC; offsets are honoured', () {
      expect(parseNaiveUtc('2026-10-28T10:15:00'), end);
      expect(parseNaiveUtc('2026-10-28T10:15:00')!.isUtc, isTrue);
      expect(parseNaiveUtc('2026-10-28T10:15:00Z'), end);
      expect(parseNaiveUtc('2026-10-28T12:15:00+02:00'), end);
      expect(parseNaiveUtc('2026-10-28T10:15:00.123456'), end.add(const Duration(microseconds: 123456)));
      expect(parseNaiveUtc(''), isNull);
      expect(parseNaiveUtc(null), isNull);
      expect(parseNaiveUtc('later'), isNull);
    });

    test('time_limit map → ends_at / free_minutes; null and junk → unlimited', () {
      expect(parseLiveTimeLimit({'ends_at': '2026-10-28T10:15:00', 'free_minutes': 15}), end);
      expect(parseLiveFreeMinutes({'ends_at': '2026-10-28T10:15:00', 'free_minutes': 15}), 15);
      expect(parseLiveTimeLimit(null), isNull);
      expect(parseLiveTimeLimit('x'), isNull);
      expect(parseLiveTimeLimit(const {}), isNull);
      expect(parseLiveFreeMinutes(null), isNull);
    });
  });

  group('countdown', () {
    test('remaining never goes below zero; expired at the end', () {
      final l = LiveTimeLimit(endsAt: end);
      expect(l.remaining(at(0)), const Duration(minutes: 15));
      expect(l.remaining(at(14, 30)), const Duration(seconds: 30));
      expect(l.remaining(at(20)), Duration.zero);
      expect(l.expired(at(14, 59)), isFalse);
      expect(l.expired(at(15)), isTrue);
      // A local DateTime is compared as the same instant.
      expect(l.remaining(at(5).toLocal()), const Duration(minutes: 10));
    });

    test('tone: calm, then warn from 3 minutes left, then over', () {
      final l = LiveTimeLimit(endsAt: end);
      expect(l.tone(at(0)), LiveLimitTone.calm);
      expect(l.tone(at(11, 59)), LiveLimitTone.calm);
      expect(l.tone(at(12)), LiveLimitTone.warn);
      expect(l.tone(at(14, 59)), LiveLimitTone.warn);
      expect(l.tone(at(15)), LiveLimitTone.over);
    });

    test('Upgrade: only the owner, only from 3 minutes left, never after subscribing', () {
      final owner = LiveTimeLimit(endsAt: end, isOwner: true);
      final other = LiveTimeLimit(endsAt: end);
      expect(owner.showUpgrade(at(11, 59)), isFalse);
      expect(owner.showUpgrade(at(12)), isTrue);
      expect(owner.showUpgrade(at(16)), isTrue, reason: 'still in the room after the end: still offered');
      expect(other.showUpgrade(at(14)), isFalse);
      final lifted = owner.copyWith(lifted: true);
      expect(lifted.showUpgrade(at(14)), isFalse);
      expect(lifted.isOwner, isTrue);
    });

    test('the pill: everyone, until the owner subscribes', () {
      expect(LiveTimeLimit(endsAt: end).showPill(at(1)), isTrue);
      expect(LiveTimeLimit(endsAt: end, isOwner: true).showPill(at(14)), isTrue);
      expect(LiveTimeLimit(endsAt: end, isOwner: true, lifted: true).showPill(at(14)), isFalse);
    });

    test('a room deleted near / after the end was the limit; the owner gets "Free time ended"', () {
      final owner = LiveTimeLimit(endsAt: end, isOwner: true);
      final other = LiveTimeLimit(endsAt: end);
      expect(owner.endedByLimit(at(5)), isFalse, reason: 'the host ended it long before the limit');
      expect(owner.endedByLimit(at(13, 31)), isTrue, reason: 'within the slack before the end');
      expect(owner.endedByLimit(at(16)), isTrue);
      expect(owner.showFreeTimeEnded(at(16)), isTrue);
      expect(other.showFreeTimeEnded(at(16)), isFalse, reason: 'others see the usual ended dialog');
      expect(owner.copyWith(lifted: true).showFreeTimeEnded(at(16)), isFalse);
    });

    test('format: mm:ss, h:mm:ss from an hour, zero for negatives', () {
      expect(LiveTimeLimit.format(const Duration(minutes: 14, seconds: 5)), '14:05');
      expect(LiveTimeLimit.format(const Duration(seconds: 9)), '00:09');
      expect(LiveTimeLimit.format(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
      expect(LiveTimeLimit.format(const Duration(seconds: -4)), '00:00');
    });
  });
}
