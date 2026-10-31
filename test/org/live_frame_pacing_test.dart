import 'package:flutter_education_app/features/teacher/sessions/live/widgets/record/live_frame_pacing.dart';
import 'package:flutter_test/flutter_test.dart';

// D-135: the Android recorder's room frames — fast enough for real-time motion, never more than half the time spent
// capturing.
void main() {
  test('a fast capture runs at the target rate (~12 fps, not the old 2 fps)', () {
    final wait = liveFrameDelay(const Duration(milliseconds: 20));
    expect(wait + const Duration(milliseconds: 20), kLiveFrameMinPeriod);
    expect(1000 ~/ kLiveFrameMinPeriod.inMilliseconds, greaterThanOrEqualTo(10));
  });

  test('a slow capture is paced to a 50 % duty cycle', () {
    expect(liveFrameDelay(const Duration(milliseconds: 120)), const Duration(milliseconds: 120));
    expect(liveFrameDelay(const Duration(milliseconds: 300)), const Duration(milliseconds: 300));
  });

  test('never negative', () {
    expect(liveFrameDelay(Duration.zero), kLiveFrameMinPeriod);
    expect(liveFrameDelay(const Duration(milliseconds: 83)), const Duration(milliseconds: 83));
  });
}
