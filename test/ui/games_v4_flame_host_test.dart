// FlameHost (Games v4 T11): no layout errors at every size / language, pauses with the app lifecycle, and tilt is
// empty off-device.
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/games/core/flame_host.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void main() {
  testWidgets('FlameHost has no layout errors', (tester) async {
    await expectNoLayoutErrors(tester, () => FlameHost(game: FlameGame(), semanticLabel: 'Game'));
  });

  testWidgets('FlameHost pauses when the app is backgrounded and resumes', (tester) async {
    final game = FlameGame();
    await tester.pumpWidget(layoutHost(FlameHost(game: game, semanticLabel: 'Game')));
    await tester.pump();
    expect(game.paused, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(game.paused, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(game.paused, isFalse);
  });

  testWidgets('FlameHost reports Reduce motion', (tester) async {
    final seen = <bool>[];
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: layoutHost(FlameHost(game: FlameGame(), semanticLabel: 'Game', onReduceMotion: seen.add)),
    ));
    await tester.pump();
    expect(seen, [true]);
  });

  test('tiltStream is empty on desktop', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(await tiltStream().toList(), isEmpty);
  });
}
