// The 'quiz' LiveKit packet (lib/features/live/room/widgets/live_quiz.dart): encode / decode and the
// teacher → room hook.
import 'package:flutter_education_app/features/live/room/widgets/live_quiz.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encode / decode round-trip, with and without a course', () {
    final a = LiveQuizBroadcast.decode(LiveQuizBroadcast.encode(const LiveQuizStart(examId: 12, courseId: 3)));
    expect(a?.examId, 12);
    expect(a?.courseId, 3);
    final b = LiveQuizBroadcast.decode(LiveQuizBroadcast.encode(const LiveQuizStart(examId: 7)));
    expect(b?.examId, 7);
    expect(b?.courseId, isNull);
  });

  test('anything else on the topic is ignored', () {
    expect(LiveQuizBroadcast.decode('{"type":"hand","up":true}'.codeUnits), isNull);
    expect(LiveQuizBroadcast.decode('{"type":"quiz_started"}'.codeUnits), isNull, reason: 'no exam id');
    expect(LiveQuizBroadcast.decode('not json'.codeUnits), isNull);
    expect(LiveQuizBroadcast.decode(const [0xff, 0xfe]), isNull);
  });

  test('started() re-fires even for the same exam', () {
    var fired = 0;
    void onChange() {
      if (LiveQuizBroadcast.latest.value != null) fired++;
    }

    LiveQuizBroadcast.latest.addListener(onChange);
    LiveQuizBroadcast.started(examId: 1, courseId: 2);
    LiveQuizBroadcast.started(examId: 1, courseId: 2);
    expect(fired, 2);
    expect(LiveQuizBroadcast.latest.value?.courseId, 2);
    LiveQuizBroadcast.latest.removeListener(onChange);
    LiveQuizBroadcast.latest.value = null;
  });
}
