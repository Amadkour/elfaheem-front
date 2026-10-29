// The host's "Room locked" pill (lib/features/teacher/sessions/live/widgets/live_locked_pill.dart) at phone and web
// sizes, Arabic and English, text scale 1.3: no overflow; tappable only with onTap.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_locked_pill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Widget _room(Widget child) => Container(
      color: const Color(0xFF0B1020),
      alignment: Alignment.topRight,
      padding: const EdgeInsets.all(14),
      child: child,
    );

void main() {
  testWidgets('locked pill: plain and tappable', (tester) async {
    await expectNoLayoutErrors(tester, () => _room(const LiveLockedPill()), act: (t) async {
      expect(find.byKey(const ValueKey('live_room.locked')), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    });
    var taps = 0;
    await expectNoLayoutErrors(tester, () => _room(LiveLockedPill(onTap: () => taps++)), act: (t) async {
      await t.tap(find.byKey(const ValueKey('live_room.locked')));
      await t.pump();
    });
    expect(taps, greaterThan(0));
  });

  testWidgets('locked pill in a narrow column stays inside it', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _room(const SizedBox(width: 70, child: Align(alignment: Alignment.topRight, child: LiveLockedPill()))),
    );
  });
}
