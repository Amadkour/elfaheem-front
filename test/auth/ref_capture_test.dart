// Games v3 (CONTRACT §8): the `ref` of a start link is kept for a sign-up — first touch wins, for 30 days.
import 'package:flutter_education_app/features/rewards/ref_capture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 1, 10);

  test('parse: only a positive user id', () {
    expect(RefCapture.parse('123'), 123);
    expect(RefCapture.parse(' 7 '), 7);
    expect(RefCapture.parse('0'), isNull);
    expect(RefCapture.parse('-4'), isNull);
    expect(RefCapture.parse('abc'), isNull);
    expect(RefCapture.parse(null), isNull);
  });

  test('first touch wins while it is valid, a later link replaces an expired one', () {
    final first = RefCapture.next(null, 5, t0)!;
    expect(RefCapture.validAt(first, t0), 5);
    // a second link 10 days later changes nothing
    expect(RefCapture.next(first, 9, t0.add(const Duration(days: 10))), first);
    // 30 days is still kept, past it the ref is gone and the next link wins
    expect(RefCapture.validAt(first, t0.add(const Duration(days: 30))), 5);
    expect(RefCapture.validAt(first, t0.add(const Duration(days: 30, minutes: 1))), isNull);
    final later = RefCapture.next(first, 9, t0.add(const Duration(days: 31)))!;
    expect(RefCapture.validAt(later, t0.add(const Duration(days: 31))), 9);
    // no incoming ref and nothing valid: nothing to keep
    expect(RefCapture.next(first, null, t0.add(const Duration(days: 40))), isNull);
  });

  test('a damaged or future-dated value is not a ref', () {
    expect(RefCapture.validAt('garbage', t0), isNull);
    expect(RefCapture.validAt('5|x', t0), isNull);
    expect(RefCapture.validAt(RefCapture.encode(5, t0.add(const Duration(days: 2))), t0), isNull);
  });

  test('capture / current / clear on the device store', () async {
    SharedPreferences.setMockInitialValues({});
    await RefCapture.capture(12, now: t0);
    await RefCapture.capture(13, now: t0.add(const Duration(days: 1)));
    expect(await RefCapture.current(now: t0.add(const Duration(days: 2))), 12);
    // expired: current drops it
    expect(await RefCapture.current(now: t0.add(const Duration(days: 60))), isNull);
    expect((await SharedPreferences.getInstance()).getString(RefCapture.prefKey), isNull);
    await RefCapture.capture(14, now: t0);
    await RefCapture.clear();
    expect(await RefCapture.current(now: t0), isNull);
  });
}
