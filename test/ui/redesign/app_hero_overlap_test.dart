// AppHeroOverlap (KIT_SPEC §5.2, §7.2): the overlapped part of the first card takes taps; in a ListView the body's
// height is counted once.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_area.dart';
import 'package:flutter_education_app/design/app_hero.dart';
import 'package:flutter_test/flutter_test.dart';

import 'redesign_harness.dart';

void main() {
  testWidgets('a tap on the overlapped top 20 px of the first card reaches it', (tester) async {
    var taps = 0;
    await tester.pumpWidget(kitHost(
      Align(
        alignment: Alignment.topCenter,
        child: AppHeroOverlap(
          overlap: 60,
          hero: const SizedBox(height: 200, child: ColoredBox(color: Color(0xFF000000))),
          body: GestureDetector(
            key: const ValueKey('card'),
            onTap: () => taps++,
            child: const SizedBox(height: 120, child: ColoredBox(color: Color(0x22000000))),
          ),
        ),
      ),
      area: AppArea.home,
    ));
    final card = tester.getRect(find.byKey(const ValueKey('card')));
    expect(card.top, closeTo(tester.getTopLeft(find.byType(AppHeroOverlap)).dy + 140, .5));
    await tester.tapAt(Offset(card.center.dx, card.top + 10));
    expect(taps, 1);
  });

  testWidgets('in a ListView the body is counted once', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(kitHost(SizedBox(
      height: 600,
      child: ListView(controller: controller, children: [
        AppHeroOverlap(
          overlap: 60,
          hero: const SizedBox(height: 200),
          body: const SizedBox(height: 900),
        ),
      ]),
    )));
    expect(tester.getSize(find.byType(AppHeroOverlap)).height, 200 - 60 + 900);
    expect(controller.position.maxScrollExtent, 200 - 60 + 900 - 600);
  });

  testWidgets('a body shorter than the overlap keeps the hero height', (tester) async {
    await tester.pumpWidget(kitHost(Align(
      alignment: Alignment.topCenter,
      child: AppHeroOverlap(overlap: 60, hero: const SizedBox(height: 200), body: const SizedBox(height: 20)),
    )));
    expect(tester.getSize(find.byType(AppHeroOverlap)).height, 200);
  });
}
