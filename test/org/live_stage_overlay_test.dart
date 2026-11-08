// D-313: when a meeting's shared content takes the overlay layout, and the per-meeting memory of the controls'
// shown / hidden choice (live_stage_overlay.dart).
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_stage_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(LiveOverlayMemory.clear);

  test('a meeting with the board or a shared screen on the stage; never a course session, a parked room or no share', () {
    expect(liveStageOverlayOn(isMeeting: true, board: true, screen: false), isTrue);
    expect(liveStageOverlayOn(isMeeting: true, board: false, screen: true), isTrue);
    expect(liveStageOverlayOn(isMeeting: true, board: false, screen: false), isFalse, reason: 'cameras only');
    expect(liveStageOverlayOn(isMeeting: false, board: true, screen: true), isFalse, reason: 'course sessions keep their layout');
    expect(liveStageOverlayOn(isMeeting: true, board: true, screen: false, parked: true), isFalse);
  });

  test('controls are shown by default and the choice is remembered per meeting', () {
    expect(LiveOverlayMemory.shownFor('meeting:7'), isTrue);
    LiveOverlayMemory.remember('meeting:7', false);
    expect(LiveOverlayMemory.shownFor('meeting:7'), isFalse);
    expect(LiveOverlayMemory.shownFor('meeting:8'), isTrue, reason: 'another meeting starts shown');
    LiveOverlayMemory.remember('meeting:7', true);
    expect(LiveOverlayMemory.shownFor('meeting:7'), isTrue);
  });
}
