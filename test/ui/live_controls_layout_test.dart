// The live-session control bar (LiveControlBar) at phone and web sizes, in Arabic and English, text scale 1.3,
// with 8 actions: no overflow, the End button is always last, extra actions move into the "More" sheet on phones.
import 'package:flutter/material.dart';
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
