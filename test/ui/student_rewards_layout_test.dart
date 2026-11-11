// The student's achievements page (RewardsScreen, editorial theme): the gold trophy block, the course covers and the
// detail view's achievements, leaderboard and tips, at 320x640 and 1400x900, Arabic + English, textScaler 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/reward/rewards_provider.dart';
import 'package:flutter_education_app/features/student/reward/rewards_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'layout_harness.dart';

Widget page(RewardsProvider p) => ChangeNotifierProvider<RewardsProvider>.value(value: p, child: const RewardsScreen());

void main() {
  testWidgets('overview (no courses) and the detail view', (tester) async {
    await expectNoLayoutErrors(tester, () => page(RewardsProvider()), scaffold: false);
    await expectNoLayoutErrors(tester, () => page(RewardsProvider()..openDetail()), scaffold: false);
  });
}
