// Host controls in the live room: every presentational widget of lib/features/shared/live/live_participant_controls
// .dart at phone and web sizes, in Arabic and English, text scale 1.3 — no overflow, no layout exception — plus the
// tap targets / labels guidelines and the callbacks.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/live/live_controls_api.dart';
import 'package:flutter_education_app/features/shared/live/live_participant_controls.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_palette.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = LiveControlTarget(
  identity: 'student_9',
  name: 'Mohamed Abdelrahman Elsayed Ibrahim Abdelaziz',
  micOn: true,
  cameraOn: true,
  screenSharing: true,
  drawingAllowed: true,
  permissions: LivePublishPermissions(sources: {LivePublishSource.microphone, LivePublishSource.screenShare}),
);

const _guest = LiveControlTarget(identity: 'guest:ab12cd', name: 'زائر من رابط المشاركة الطويل جداً جداً');

Widget _sheet(LiveControlTarget target, {LiveHostAction? busy, bool disabled = false, String? note, ValueChanged<LiveHostAction>? onAction}) =>
    LiveParticipantActionsBody(
      target: target,
      actions: liveHostActionsFor(target, viewerIsHost: true, drawingAvailable: true),
      busy: busy,
      disabled: disabled,
      note: note,
      onAction: onAction ?? (_) {},
    );

/// The host bar sits in the room's 300 px participants panel on the dark backdrop.
Widget _panel(Widget child) => ColoredBox(
      color: LivePalette.surfaceHi,
      child: Align(alignment: AlignmentDirectional.topEnd, child: SizedBox(width: 300, child: child)),
    );

Widget _bar({bool? locked, bool muteAllBusy = false, bool lockBusy = false, bool endBusy = false, bool lock = true, bool end = true, bool enabled = true}) =>
    _panel(LiveHostControlsBar(
      locked: locked,
      muteAllBusy: muteAllBusy,
      lockBusy: lockBusy,
      endBusy: endBusy,
      enabled: enabled,
      onMuteAll: () {},
      onLockChanged: lock ? (_) {} : null,
      onEndForAll: end ? () {} : null,
    ));

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('participant sheet', () {
    testWidgets('every action, long name', (t) => expectNoLayoutErrors(t, () => _sheet(_long)));
    testWidgets('a guest with nothing on', (t) => expectNoLayoutErrors(t, () => _sheet(_guest)));
    testWidgets('busy row', (t) => expectNoLayoutErrors(t, () => _sheet(_long, busy: LiveHostAction.revokeScreenShare)));
    testWidgets('disabled with a note',
        (t) => expectNoLayoutErrors(t, () => _sheet(_long, disabled: true, note: 'The room is not live right now. Wait for the host to start it again.')));
    testWidgets('no actions (another host)',
        (t) => expectNoLayoutErrors(t, () => _sheet(const LiveControlTarget(identity: 'teacher_1', name: 'T', isHost: true))));

    testWidgets('a tap reports its action; a busy sheet ignores taps', (tester) async {
      final got = <LiveHostAction>[];
      await tester.pumpWidget(layoutHost(_sheet(_long, onAction: got.add)));
      await tester.tap(find.byKey(const ValueKey('live_controls.action.remove')));
      await tester.tap(find.byKey(const ValueKey('live_controls.action.muteMic')));
      expect(got, [LiveHostAction.remove, LiveHostAction.muteMic]);
      got.clear();
      await tester.pumpWidget(layoutHost(_sheet(_long, busy: LiveHostAction.muteMic, onAction: got.add)));
      await tester.tap(find.byKey(const ValueKey('live_controls.action.remove')));
      expect(got, isEmpty);
    });

    testWidgets('tap targets and labels', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(layoutHost(_sheet(_long), scale: 1));
      await tester.pump();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(find.bySemanticsLabel('Remove from room'), findsOneWidget);
      handle.dispose();
    });
  });

  group('host bar', () {
    testWidgets('unlocked, unknown lock', (t) => expectNoLayoutErrors(t, () => _bar()));
    testWidgets('locked', (t) => expectNoLayoutErrors(t, () => _bar(locked: true)));
    testWidgets('everything busy', (t) => expectNoLayoutErrors(t, () => _bar(locked: true, muteAllBusy: true, lockBusy: true, endBusy: true)));
    testWidgets('no lock, no end (older server)', (t) => expectNoLayoutErrors(t, () => _bar(lock: false, end: false)));
    testWidgets('disabled', (t) => expectNoLayoutErrors(t, () => _bar(enabled: false)));
    testWidgets('participant ⋮ button', (t) => expectNoLayoutErrors(
        t,
        () => _panel(Row(children: [
              const Expanded(child: Text('Mona')),
              LiveParticipantControlsButton(name: 'Mona', onPressed: () {}),
              const LiveParticipantControlsButton(name: 'Ali', onPressed: null, busy: true),
            ]))));

    testWidgets('callbacks and lock state', (tester) async {
      var muted = 0, ended = 0;
      final lock = <bool>[];
      await tester.pumpWidget(layoutHost(_panel(LiveHostControlsBar(
        locked: false,
        onMuteAll: () => muted++,
        onLockChanged: lock.add,
        onEndForAll: () => ended++,
      ))));
      await tester.tap(find.byKey(const ValueKey('live_controls.mute_all')));
      await tester.tap(find.byKey(const ValueKey('live_controls.end_for_all')));
      await tester.tap(find.byKey(const ValueKey('live_controls.lock')));
      expect((muted, ended), (1, 1));
      expect(lock, [true]);
      expect(find.text('Open: invited people can join'), findsOneWidget);

      await tester.pumpWidget(layoutHost(_panel(LiveHostControlsBar(locked: true, muteAllBusy: true, onMuteAll: () => muted++, onLockChanged: lock.add))));
      await tester.tap(find.byKey(const ValueKey('live_controls.mute_all')));
      expect(muted, 1, reason: 'busy: no second mute all');
      expect(find.text('Locked: nobody new can join'), findsOneWidget);
      expect(find.byKey(const ValueKey('live_controls.end_for_all')), findsNothing);
    });

    testWidgets('the bar in Arabic', (tester) async {
      AppConfig.lang = 'ar';
      await tester.pumpWidget(layoutHost(_bar(locked: true)));
      expect(find.text('كتم الجميع'), findsOneWidget);
      expect(find.text('قفل الغرفة'), findsOneWidget);
    });

    testWidgets('tap targets and labels', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(layoutHost(_bar(locked: false), scale: 1));
      await tester.pump();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });

  group('kill switches', () {
    late List<String> before;
    setUp(() => before = AppConfig.disableList);
    tearDown(() => AppConfig.disableList = before);

    testWidgets('live.room_lock hides only the lock; live.teacher_controls hides the rest', (tester) async {
      AppConfig.disableList = const [kLiveRoomLockFeatureKey];
      await tester.pumpWidget(layoutHost(_bar()));
      expect(find.byKey(const ValueKey('live_controls.lock')), findsNothing);
      expect(find.byKey(const ValueKey('live_controls.mute_all')), findsOneWidget);
      AppConfig.disableList = const [kLiveTeacherControlsFeatureKey];
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(layoutHost(_bar()));
      expect(find.byKey(const ValueKey('live_controls.mute_all')), findsNothing);
      expect(find.byKey(const ValueKey('live_controls.lock')), findsOneWidget);
    });
  });
}
