// The weak-network UI (D-090, lib/features/live/live_net_pill.dart): the "video quality lowered" pill in the
// room's badge column and the audio-only card with Show video, at 320×640 and 1400×900, ar + en, text scale 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/live/live_net_pill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Widget _badges(Widget child) => Container(
      color: const Color(0xFF0B1020),
      alignment: AlignmentDirectional.topEnd,
      padding: const EdgeInsets.all(14),
      child: child,
    );

Widget _stage(Widget child) => Container(
      color: const Color(0xFF0B1020),
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 64),
      child: child,
    );

void main() {
  testWidgets('pill: lowered and recovering', (tester) async {
    await expectNoLayoutErrors(tester, () => _badges(const LiveNetPill()), act: (t) async {
      expect(find.byKey(const ValueKey('live_room.net_pill')), findsOneWidget);
      expect(find.byIcon(Icons.speed_rounded), findsOneWidget);
    });
    await expectNoLayoutErrors(tester, () => _badges(const LiveNetPill(recovering: true)), act: (t) async {
      expect(find.byIcon(Icons.network_check_rounded), findsOneWidget);
    });
  });

  testWidgets('pill in a narrow column stays inside it', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _badges(const SizedBox(width: 90, child: Align(alignment: AlignmentDirectional.topEnd, child: LiveNetPill()))),
    );
  });

  testWidgets('audio-only card: Show video is tappable at every size', (tester) async {
    var taps = 0;
    await expectNoLayoutErrors(tester, () => _stage(LiveAudioOnlyCard(onShowVideo: () => taps++)), act: (t) async {
      expect(find.byKey(const ValueKey('live_room.audio_only')), findsOneWidget);
      final button = find.byKey(const ValueKey('live_room.audio_only.show_video'));
      expect(t.getSize(button).height, greaterThanOrEqualTo(44));
      await t.tap(button);
      await t.pump();
    });
    expect(taps, greaterThan(0));
  });

  testWidgets('audio-only card with a screen share kept', (tester) async {
    await expectNoLayoutErrors(tester, () => _stage(LiveAudioOnlyCard(onShowVideo: () {}, keepsScreen: true)));
  });
}
