// The live-session control bar (LiveControlBar) at phone and web sizes, in Arabic and English, text scale 1.3,
// with 8 actions: no overflow, the End button is always last, extra actions move into the "More" sheet on phones.
// Recording is not on the bar any more (D-095): Record / Pause / Resume / Stop and the REC time live in the room's
// top row — test/ui/live_top_row_layout_test.dart.
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
          key: const ValueKey('live_room.hand'),
          icon: Icons.back_hand_outlined,
          label: 'Raise hand',
          shortcut: 'H',
          onTap: () {}),
    ];

LiveControlAction _end() => LiveControlAction(key: const ValueKey('live_room.end'), icon: Icons.call_end_rounded, label: 'End', shortcut: 'E', onTap: () {});

Widget _bar(List<LiveControlAction> a) => Align(
      alignment: Alignment.bottomCenter,
      child: LiveControlBar(
        primary: a.take(4).toList(),
        secondary: a.skip(4).toList(),
        groups: [a.take(2).toList(), [a[4], a[5], a[6]], [a[2], a[7]], [a[3]]],
        end: _end(),
      ),
    );

void main() {
  testWidgets('8 actions never overflow (phone / web, ar / en, 1.3x)', (tester) async {
    await expectNoLayoutErrors(tester, () => _bar(_eight()));
    await expectNoLayoutErrors(tester, () => _bar(_eight(busy: true)));
  });

  testWidgets('phone: extras go into the More sheet, End is last; sheet opens without overflow', (tester) async {
    await expectNoLayoutErrors(tester, () => _bar(_eight()), act: (t) async {
      final size = t.view.physicalSize;
      final more = find.byKey(const ValueKey('live_room.more'));
      if (size.width < kLiveControlsMobileBreakpoint) {
        expect(more, findsOneWidget);
        expect(find.byKey(const ValueKey('live_room.hand')), findsNothing);
        final endX = t.getCenter(find.byKey(const ValueKey('live_room.end'))).dx;
        final micX = t.getCenter(find.byKey(const ValueKey('live_room.mic'))).dx;
        expect(endX, greaterThan(micX));
        await t.tap(more);
        await t.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const ValueKey('live_room.hand.sheet')), findsOneWidget);
        expect(find.byKey(const ValueKey('live_room.speaker.sheet')), findsOneWidget);
        expect(find.text('Headphones'), findsOneWidget);
      } else {
        expect(more, findsNothing);
        for (final k in ['live_room.mic', 'live_room.camera', 'live_room.share', 'live_room.reactions', 'live_room.flip_camera', 'live_room.speaker', 'live_room.audio_output', 'live_room.hand', 'live_room.end']) {
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

  // ── D-095: no recording on the bar — no REC chip, no Pause / Resume, no meeting Record / Stop ──
  testWidgets('a host bar with the lobby: nothing recording-related, in the pill or in More', (tester) async {
    await expectNoLayoutErrors(tester, () {
      final a = _eight();
      final chat = LiveControlAction(
          key: const ValueKey('live_room.chat'), icon: Icons.chat_bubble_outline_rounded, label: 'Chat', badge: 3, shortcut: 'C', pinned: true, onTap: () {});
      return Align(
        alignment: Alignment.bottomCenter,
        child: LiveControlBar(
          primary: [a[0], a[1], a[2], a[3], chat],
          secondary: [a[4], a[5], a[6]],
          groups: [
            [a[0], a[1], a[4], a[5], a[6]],
            [a[2]],
            [a[3], chat],
          ],
          end: _end(),
          onLobby: () {},
          waitingCount: 2,
        ),
      );
    }, act: (t) async {
      const gone = ['live_room.rec_badge', 'live_room.pause_recording', 'live_room.meeting_record'];
      for (final k in gone) {
        expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
      }
      expect(find.byKey(const ValueKey('live_room.lobby')), findsOneWidget);
      expect(find.byKey(const ValueKey('live_room.chat')), findsOneWidget, reason: 'the chat is pinned');
      final more = find.byKey(const ValueKey('live_room.more'));
      if (more.evaluate().isNotEmpty) {
        await t.tap(more);
        await t.pump(const Duration(milliseconds: 400));
        for (final k in gone) {
          expect(find.byKey(ValueKey('$k.sheet')), findsNothing, reason: '$k.sheet');
        }
        expect(find.byIcon(Icons.pause_circle_outline_rounded), findsNothing);
        expect(find.byIcon(Icons.fiber_manual_record_rounded), findsNothing);
      }
    });
  });

  // ── Annotate (D-079): beside Share; the label follows the toolbar ──
  group('Annotate beside Share', () {
    test('the action: null without a callback; Annotate / Stop drawing', () {
      AppConfig.lang = 'en';
      expect(ControlsWidgetState.annotateAction(onTap: null), isNull);
      final idle = ControlsWidgetState.annotateAction(onTap: () {})!;
      final open = ControlsWidgetState.annotateAction(onTap: () {}, open: true)!;
      expect(idle.label, 'Annotate');
      expect(open.label, 'Stop drawing');
      expect(open.active, isTrue);
      expect(idle.icon, isNot(open.icon));
    });

    testWidgets('a full bar with Annotate (open and closed), 320 px included: no overflow', (tester) async {
      for (final open in [false, true]) {
        await expectNoLayoutErrors(tester, () {
          final a = _eight();
          final annotate = ControlsWidgetState.annotateAction(onTap: () {}, open: open)!;
          return Align(
            alignment: Alignment.bottomCenter,
            child: LiveControlBar(
              primary: [a[0], a[1], a[2], annotate, a[3]],
              secondary: [a[4], a[5], a[6], a[7]],
              groups: [
                [a[0], a[1], a[4], a[5], a[6]],
                [a[2], annotate, a[7]],
                [a[3]],
              ],
              end: _end(),
            ),
          );
        }, act: (t) async {
          expect(find.byKey(const ValueKey('live_room.end')), findsOneWidget);
        });
      }
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
