// The free-time countdown pill and the owner's "Free time ended" card (lib/features/live/live_time_limit.dart)
// at phone and web sizes, Arabic and English, text scale 1.3: no overflow.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/live/live_time_limit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Widget _room(Widget child) => Container(
      color: const Color(0xFF0B1020),
      alignment: Alignment.topRight,
      padding: const EdgeInsets.all(14),
      child: child,
    );

void main() {
  testWidgets('pill: calm · warn with Upgrade · busy · over', (tester) async {
    await expectNoLayoutErrors(tester, () => _room(const LiveTimeLimitPill(remaining: Duration(minutes: 12, seconds: 4), tone: LiveLimitTone.calm)),
        act: (t) async {
      expect(find.byKey(const ValueKey('live_room.time_limit')), findsOneWidget);
      expect(find.byKey(const ValueKey('live_room.time_limit.upgrade')), findsNothing);
    });
    var tapped = 0;
    await expectNoLayoutErrors(
      tester,
      () => _room(LiveTimeLimitPill(remaining: const Duration(minutes: 2, seconds: 9), tone: LiveLimitTone.warn, showUpgrade: true, onUpgrade: () => tapped++)),
      act: (t) async {
        await t.tap(find.byKey(const ValueKey('live_room.time_limit.upgrade')));
        await t.pump();
      },
    );
    expect(tapped, greaterThan(0));
    await expectNoLayoutErrors(tester,
        () => _room(LiveTimeLimitPill(remaining: Duration.zero, tone: LiveLimitTone.over, showUpgrade: true, busy: true, onUpgrade: () {})));
  });

  testWidgets('"Free time ended" card, with and without the minutes', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Container(
        color: const Color(0xFF0B1020),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(child: LiveFreeTimeEndedCard(onSubscribe: () {}, onClose: () {}, freeMinutes: 15)),
      ),
      act: (t) async {
        expect(find.byKey(const ValueKey('live_room.free_time_ended.subscribe')), findsOneWidget);
        expect(find.byKey(const ValueKey('live_room.free_time_ended.close')), findsOneWidget);
      },
    );
    await expectNoLayoutErrors(
      tester,
      () => Center(child: SingleChildScrollView(child: LiveFreeTimeEndedCard(onSubscribe: () {}, onClose: () {}))),
    );
  });
}
