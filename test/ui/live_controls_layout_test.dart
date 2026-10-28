// The live-session control bar (LiveControlBar) at phone and web sizes, in Arabic and English, text scale 1.3,
// with 8 actions: no overflow, the End button is always last, extra actions move into the "More" sheet on phones.
// Plus the recorder controls of a meeting creator who is not a teacher (showsRecorderControls): Pause while recording,
// Resume while paused, nothing while not recording.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/controls.dart' show ControlsWidgetState;
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_control_bar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

List<LiveControlAction> _eight({bool busy = false}) => [
      LiveControlAction(
          key: const ValueKey('live_room.mic'),
          icon: Icons.mic_off_rounded,
          label: 'Unmute microphone now',
          off: true,
          shortcut: 'M',
          onTap: () {},
          menuTitle: 'Microphone',
          menu: [
            LiveDeviceOption(label: 'Built-in microphone (Realtek High Definition Audio)', selected: true, onTap: () {}),
            LiveDeviceOption(label: 'USB headset', onTap: () {}),
          ]),
      LiveControlAction(
          key: const ValueKey('live_room.camera'),
          icon: Icons.videocam_rounded,
          label: 'الكاميرا الأمامية',
          active: true,
          loading: busy,
          shortcut: 'V',
          onTap: () {},
          menu: [LiveDeviceOption(label: 'FaceTime HD', selected: true, onTap: () {})]),
      LiveControlAction(key: const ValueKey('live_room.share'), icon: Icons.screen_share_rounded, label: 'Share screen', shortcut: 'S', onTap: () {}),
      LiveControlAction(key: const ValueKey('live_room.reactions'), icon: Icons.add_reaction_outlined, label: 'تفاعل', active: true, shortcut: 'R', onTap: () {}),
      LiveControlAction(key: const ValueKey('live_room.flip_camera'), icon: Icons.camera_rear_rounded, label: 'Back camera', onTap: () {}),
      LiveControlAction(key: const ValueKey('live_room.speaker'), icon: Icons.speaker_phone_rounded, label: 'مكبر الصوت', active: true, onTap: () {}),
      LiveControlAction(
          key: const ValueKey('live_room.audio_output'),
          icon: Icons.volume_up_rounded,
          label: 'Output',
          menuTitle: 'Select audio output',
          menu: [LiveDeviceOption(label: 'Speakers', selected: true, onTap: () {}), LiveDeviceOption(label: 'Headphones', onTap: () {})]),
      LiveControlAction(
          key: const ValueKey('live_room.pause_recording'),
          icon: Icons.pause_circle_outline_rounded,
          label: 'Pause recording',
          active: true,
          color: Colors.amber,
          onTap: () {}),
    ];

LiveControlAction _end() => LiveControlAction(key: const ValueKey('live_room.end'), icon: Icons.call_end_rounded, label: 'End', shortcut: 'E', onTap: () {});

Widget _bar(List<LiveControlAction> a, {LiveRecBadge rec = LiveRecBadge.recording}) => Align(
      alignment: Alignment.bottomCenter,
      child: LiveControlBar(
        primary: a.take(4).toList(),
        secondary: a.skip(4).toList(),
        groups: [a.take(2).toList(), [a[4], a[5], a[6]], [a[2], a[7]], [a[3]]],
        end: _end(),
        rec: rec,
      ),
    );

void main() {
  testWidgets('8 actions + REC never overflow (phone / web, ar / en, 1.3x)', (tester) async {
    await expectNoLayoutErrors(tester, () => _bar(_eight()));
    await expectNoLayoutErrors(tester, () => _bar(_eight(busy: true), rec: LiveRecBadge.paused));
    await expectNoLayoutErrors(tester, () => _bar(_eight(), rec: LiveRecBadge.none));
  });

  testWidgets('phone: extras go into the More sheet, End is last; sheet opens without overflow', (tester) async {
    await expectNoLayoutErrors(tester, () => _bar(_eight()), act: (t) async {
      final size = t.view.physicalSize;
      final more = find.byKey(const ValueKey('live_room.more'));
      if (size.width < kLiveControlsMobileBreakpoint) {
        expect(more, findsOneWidget);
        expect(find.byKey(const ValueKey('live_room.pause_recording')), findsNothing);
        final endX = t.getCenter(find.byKey(const ValueKey('live_room.end'))).dx;
        final micX = t.getCenter(find.byKey(const ValueKey('live_room.mic'))).dx;
        expect(endX, greaterThan(micX));
        await t.tap(more);
        await t.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const ValueKey('live_room.pause_recording.sheet')), findsOneWidget);
        expect(find.byKey(const ValueKey('live_room.speaker.sheet')), findsOneWidget);
        expect(find.text('Headphones'), findsOneWidget);
      } else {
        expect(more, findsNothing);
        for (final k in ['live_room.mic', 'live_room.camera', 'live_room.share', 'live_room.reactions', 'live_room.flip_camera', 'live_room.speaker', 'live_room.audio_output', 'live_room.pause_recording', 'live_room.end', 'live_room.rec_badge']) {
          expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
        }
        final endX = t.getCenter(find.byKey(const ValueKey('live_room.end'))).dx;
        final reactX = t.getCenter(find.byKey(const ValueKey('live_room.reactions'))).dx;
        expect(endX, greaterThan(reactX));
        // device chevron opens the picker
        await t.tap(find.byKey(const ValueKey('live_room.mic.devices')));
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('USB headset'), findsOneWidget);
        await t.tapAt(const Offset(5, 5));
        await t.pump(const Duration(milliseconds: 400));
      }
    });
  });

  // ── Recorder controls on a meeting creator's bar (not a teacher) ─────────
  // ControlsWidget derives these from `recordsHere` (showsRecorderControls) and hands the bar the pause / resume
  // action plus the REC chip; the bar itself is pumped here with exactly what a creator's bar gets.
  group('recorder controls for a host who is not a teacher', () {
    LiveControlAction pauseResume({required bool paused}) => LiveControlAction(
          key: const ValueKey('live_room.pause_recording'),
          icon: paused ? Icons.play_circle_outline_rounded : Icons.pause_circle_outline_rounded,
          label: paused ? 'Resume' : 'Pause',
          active: true,
          color: paused ? Colors.green : Colors.amber,
          onTap: () {},
        );

    Widget hostBar({required LiveRecBadge rec, LiveControlAction? record}) {
      final a = _eight();
      final mic = a[0], cam = a[1], react = a[3];
      final chat = LiveControlAction(key: const ValueKey('live_room.chat'), icon: Icons.chat_bubble_outline_rounded, label: 'Chat', badge: 3, shortcut: 'C', onTap: () {});
      // No share action: only teachers share; the record group is empty when nothing records here.
      return Align(
        alignment: Alignment.bottomCenter,
        child: LiveControlBar(
          primary: [mic, cam, react, chat],
          secondary: [?record],
          groups: [
            [mic, cam],
            [?record],
            [react, chat],
          ],
          end: _end(),
          rec: rec,
          onLobby: () {},
          waitingCount: 2,
        ),
      );
    }

    test('showsRecorderControls: a teacher follows the record switch, anyone else follows recordsHere', () {
      expect(showsRecorderControls(isTeacher: true, recordingEnabled: true, recordsHere: false), isTrue);
      expect(showsRecorderControls(isTeacher: true, recordingEnabled: true, recordsHere: true), isTrue);
      expect(showsRecorderControls(isTeacher: true, recordingEnabled: false, recordsHere: true), isFalse);
      expect(showsRecorderControls(isTeacher: true, recordingEnabled: false, recordsHere: false), isFalse);
      expect(showsRecorderControls(isTeacher: false, recordingEnabled: true, recordsHere: true), isTrue);
      expect(showsRecorderControls(isTeacher: false, recordingEnabled: false, recordsHere: true), isTrue);
      expect(showsRecorderControls(isTeacher: false, recordingEnabled: true, recordsHere: false), isFalse);
    });

    testWidgets('recording: Pause + REC chip, no share button', (tester) async {
      await expectNoLayoutErrors(tester, () => hostBar(rec: LiveRecBadge.recording, record: pauseResume(paused: false)), act: (t) async {
        expect(find.byKey(const ValueKey('live_room.rec_badge')), findsOneWidget);
        expect(find.byKey(const ValueKey('live_room.share')), findsNothing);
        expect(find.byKey(const ValueKey('live_room.lobby')), findsOneWidget);
        if (t.view.physicalSize.width < kLiveControlsMobileBreakpoint) {
          await t.tap(find.byKey(const ValueKey('live_room.more')));
          await t.pump(const Duration(milliseconds: 400));
          expect(find.byKey(const ValueKey('live_room.pause_recording.sheet')), findsOneWidget);
          expect(find.byIcon(Icons.pause_circle_outline_rounded), findsOneWidget);
        } else {
          expect(find.byKey(const ValueKey('live_room.more')), findsNothing);
          expect(find.byKey(const ValueKey('live_room.pause_recording')), findsOneWidget);
          expect(find.byIcon(Icons.pause_circle_outline_rounded), findsOneWidget);
        }
      });
    });

    testWidgets('paused: Resume + paused chip', (tester) async {
      await expectNoLayoutErrors(tester, () => hostBar(rec: LiveRecBadge.paused, record: pauseResume(paused: true)), act: (t) async {
        expect(find.byKey(const ValueKey('live_room.rec_badge')), findsOneWidget);
        expect(find.byIcon(Icons.pause_rounded), findsOneWidget, reason: 'the chip shows the pause glyph');
        if (t.view.physicalSize.width < kLiveControlsMobileBreakpoint) {
          await t.tap(find.byKey(const ValueKey('live_room.more')));
          await t.pump(const Duration(milliseconds: 400));
          expect(find.byKey(const ValueKey('live_room.pause_recording.sheet')), findsOneWidget);
          expect(find.byIcon(Icons.play_circle_outline_rounded), findsOneWidget);
          expect(find.byIcon(Icons.pause_circle_outline_rounded), findsNothing);
        } else {
          expect(find.byKey(const ValueKey('live_room.pause_recording')), findsOneWidget);
          expect(find.byIcon(Icons.play_circle_outline_rounded), findsOneWidget);
          expect(find.byIcon(Icons.pause_circle_outline_rounded), findsNothing);
        }
      });
    });

    testWidgets('not recording: no Pause / Resume anywhere and no chip', (tester) async {
      await expectNoLayoutErrors(tester, () => hostBar(rec: LiveRecBadge.none), act: (t) async {
        expect(find.byKey(const ValueKey('live_room.rec_badge')), findsNothing);
        expect(find.byKey(const ValueKey('live_room.pause_recording')), findsNothing);
        final more = find.byKey(const ValueKey('live_room.more'));
        if (more.evaluate().isNotEmpty) {
          await t.tap(more);
          await t.pump(const Duration(milliseconds: 400));
          expect(find.byKey(const ValueKey('live_room.pause_recording.sheet')), findsNothing);
          expect(find.byIcon(Icons.pause_circle_outline_rounded), findsNothing);
          expect(find.byIcon(Icons.play_circle_outline_rounded), findsNothing);
        }
        expect(find.byKey(const ValueKey('live_room.end')), findsOneWidget);
      });
    });
  });

  // ── The meeting creator's red Record / Stop (live-rooms-spec §11): primary group, pinned in the phone pill ──
  group('meeting Record / Stop in the primary group', () {
    Widget creatorBar({required bool recording, bool busy = false}) {
      final a = _eight();
      final mic = a[0], cam = a[1], react = a[3], flip = a[4], speaker = a[5], output = a[6];
      final chat = LiveControlAction(key: const ValueKey('live_room.chat'), icon: Icons.chat_bubble_outline_rounded, label: 'Chat', badge: 3, shortcut: 'C', onTap: () {});
      final hand = LiveControlAction(key: const ValueKey('live_room.hand'), icon: Icons.back_hand_outlined, label: 'Raise hand', onTap: () {});
      // Exactly what ControlsWidget hands the bar for a meeting creator (no share: only teachers share).
      final rec = ControlsWidgetState.meetingRecordAction(onTap: () {}, recording: recording, busy: busy)!;
      return Align(
        alignment: Alignment.bottomCenter,
        child: LiveControlBar(
          primary: [mic, cam, rec, react, hand, chat],
          secondary: [flip, speaker, output, if (recording) a[7]],
          groups: [
            [mic, cam, flip, speaker, output],
            [rec, if (recording) a[7]],
            [react, hand, chat],
          ],
          end: _end(),
          rec: recording ? LiveRecBadge.recording : LiveRecBadge.none,
          onLobby: () {},
          waitingCount: 4,
        ),
      );
    }

    test('the action: null without a callback; Record / Stop, red, pinned', () {
      AppConfig.lang = 'en';
      expect(ControlsWidgetState.meetingRecordAction(onTap: null), isNull);
      final idle = ControlsWidgetState.meetingRecordAction(onTap: () {})!;
      final on = ControlsWidgetState.meetingRecordAction(onTap: () {}, recording: true)!;
      final busy = ControlsWidgetState.meetingRecordAction(onTap: () {}, busy: true)!;
      expect(idle.pinned, isTrue);
      expect(idle.label, 'Record');
      expect(on.label, 'Stop');
      expect(idle.icon, isNot(on.icon));
      expect(idle.color, isNotNull);
      expect(busy.loading, isTrue);
      expect(busy.onTap, isNull);
    });

    testWidgets('always on the bar, never in More — 320 px with the lobby too, no overflow', (tester) async {
      for (final recording in [false, true]) {
        await expectNoLayoutErrors(tester, () => creatorBar(recording: recording), act: (t) async {
          final rec = find.byKey(const ValueKey('live_room.meeting_record'));
          expect(rec, findsOneWidget);
          expect(find.byKey(const ValueKey('live_room.lobby')), findsOneWidget);
          final endX = t.getCenter(find.byKey(const ValueKey('live_room.end'))).dx;
          expect(endX, greaterThan(t.getCenter(rec).dx));
          if (t.view.physicalSize.width < kLiveControlsMobileBreakpoint) {
            await t.tap(find.byKey(const ValueKey('live_room.more')));
            await t.pump(const Duration(milliseconds: 400));
            expect(find.byKey(const ValueKey('live_room.meeting_record.sheet')), findsNothing);
          }
        });
      }
      await expectNoLayoutErrors(tester, () => creatorBar(recording: true, busy: true));
    });
  });

  testWidgets('no secondary actions and few primaries: no More button', (tester) async {
    await expectNoLayoutErrors(tester, () {
      final a = _eight();
      return Align(
        alignment: Alignment.bottomCenter,
        child: LiveControlBar(primary: [a[0], a[1], a[3]], end: _end()),
      );
    }, act: (t) async {
      expect(find.byKey(const ValueKey('live_room.more')), findsNothing);
    });
  });
}
