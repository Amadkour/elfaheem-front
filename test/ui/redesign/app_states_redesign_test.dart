// The states (KIT_SPEC §5.9, §7.2): empty, error, offline, loading (5 shapes), success with and without a burst.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_area.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';
import 'redesign_harness.dart';

void main() {
  final cases = <String, Widget Function()>{
    'empty': () => AppEmpty(
        icon: Icons.inbox_rounded, title: 'Nothing here yet', message: 'Add your first course', actionLabel: 'Add', onAction: () {}),
    'empty, no action': () => const AppEmpty(icon: Icons.inbox_rounded, title: 'لا شيء بعد'),
    'error': () => AppErrorState(message: 'Check your connection and try again.', onRetry: () {}),
    'error compact': () => AppErrorState(compact: true, message: 'Failed', onRetry: () {}),
    'offline': () => AppNeedsConnection(onRetry: () {}),
    for (final shape in AppLoadingShape.values) 'loading ${shape.name}': () => AppLoadingState(shape: shape),
    'success': () => AppSuccess(
        title: 'Booked', message: 'See you on Sunday', actionLabel: 'Done', onAction: () {},
        secondary: AppButton.ghost(label: 'Add to calendar', onPressed: () {})),
    'success with burst': () => AppSuccess(title: 'Passed!', burst: BurstMoment.examPassed, actionLabel: 'OK', onAction: () {}),
  };

  for (final e in cases.entries) {
    testWidgets('layout: ${e.key}', (tester) async {
      await expectNoLayoutErrors(tester, () => AppAreaScope(area: AppArea.exam, child: e.value()), frames: 12);
    });
  }

  testWidgets('the plate takes the area tint under a scope', (tester) async {
    await tester.pumpWidget(kitHost(const AppStatePlate(icon: Icons.inbox_rounded), area: AppArea.learn, reduce: true));
    final box = tester.widget<Container>(
        find.descendant(of: find.byType(AppStatePlate), matching: find.byType(Container)).first);
    final deco = box.decoration! as BoxDecoration;
    final ctx = tester.element(find.byType(AppStatePlate));
    expect(deco.color, AppAreaScope.of(ctx).tint);
    expect(deco.borderRadius, AppRadius.plate);
  });

  testWidgets('success with a burst fires once and leaves nothing behind', (tester) async {
    await tester.pumpWidget(
        kitHost(AppSuccess(title: 'Level up', burst: BurstMoment.levelUp, actionLabel: 'OK', onAction: () {}), area: AppArea.games));
    await tester.pump(const Duration(milliseconds: 900));
    expect(AppBurst.debugLive, 1);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(AppBurst.debugLive, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('success under Reduce motion: no burst, no timer left after dispose', (tester) async {
    await tester.pumpWidget(kitHost(AppSuccess(title: 'Done', burst: BurstMoment.attendanceDone), area: AppArea.home, reduce: true));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(AppBurst.debugLive, 0);
  });
}
