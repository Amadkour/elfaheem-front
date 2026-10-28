// Live room — "joined N min ago" / "stayed N min" (lib/features/teacher/sessions/live/widgets/live_duration.dart).
// The attendance rows are naive UTC; parsed as local time they put the duration off by the UTC offset.
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_duration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('liveParseServerUtc', () {
    test('a naive server string is UTC (str(datetime) with a space and microseconds)', () {
      final d = liveParseServerUtc('2026-10-28 08:00:00.123456')!;
      expect(d.isUtc, isTrue);
      expect(d, DateTime.utc(2026, 10, 28, 8, 0, 0, 123, 456));
    });

    test('a Z or an offset is honoured', () {
      expect(liveParseServerUtc('2026-10-28T08:00:00Z'), DateTime.utc(2026, 10, 28, 8));
      expect(liveParseServerUtc('2026-10-28T10:00:00+02:00'), DateTime.utc(2026, 10, 28, 8));
      expect(liveParseServerUtc('2026-10-28T10:00:00+0200'), DateTime.utc(2026, 10, 28, 8));
    });

    test('a date-only string is midnight UTC; a DateTime is converted', () {
      expect(liveParseServerUtc('2026-10-28'), DateTime.utc(2026, 10, 28));
      final local = DateTime(2026, 10, 28, 10);
      expect(liveParseServerUtc(local), local.toUtc());
    });

    test('empty, None, null and garbage are null', () {
      for (final v in [null, '', '  ', 'None', 'null', 'yesterday']) {
        expect(liveParseServerUtc(v), isNull, reason: '$v');
      }
    });
  });

  group('liveMinutesBetween', () {
    final now = DateTime.utc(2026, 10, 28, 8, 5);

    test('naive UTC join from the server, compared with the clock: no UTC-offset error', () {
      expect(liveMinutesBetween(liveParseServerUtc('2026-10-28 08:02:30'), null, now: now), 2);
    });

    test('a Z string and a local DateTime (LiveKit joinedAt) are the same instant', () {
      expect(liveMinutesBetween(liveParseServerUtc('2026-10-28T08:00:00Z'), null, now: now), 5);
      final joinedLocal = DateTime.utc(2026, 10, 28, 7, 50).toLocal();
      expect(liveMinutesBetween(joinedLocal, null, now: now), 15);
      // and against a local "now" too
      expect(liveMinutesBetween(DateTime.utc(2026, 10, 28, 7, 50), null, now: now.toLocal()), 15);
    });

    test('with a leave date: the stay', () {
      expect(
          liveMinutesBetween(liveParseServerUtc('2026-10-28 06:00:00'), liveParseServerUtc('2026-10-28 07:25:59')), 85);
    });

    test('null start → null; clock skew (start after now) → 0', () {
      expect(liveMinutesBetween(null, null, now: now), isNull);
      expect(liveMinutesBetween(DateTime.utc(2026, 10, 28, 8, 9), null, now: now), 0);
      expect(liveMinutesBetween(DateTime.utc(2026, 10, 28, 9), DateTime.utc(2026, 10, 28, 8)), 0);
    });

    test('defaults to the real clock', () {
      final m = liveMinutesBetween(DateTime.now().toUtc().subtract(const Duration(minutes: 3)), null)!;
      expect(m, inInclusiveRange(2, 3));
    });
  });
}
