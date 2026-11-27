// AppLiveTag and AppLiveBanner (KIT_SPEC §5.10, §7.2). AppCountBadge's cases belong to the badges step.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_area.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';
import 'redesign_harness.dart';

const _long = 'الرياضيات: الدوال الأسية واللوغاريتمية مراجعة شاملة قبل الاختبار النهائي للفصل الدراسي الأول';

void main() {
  final cases = <String, Widget Function()>{
    'tag': () => const AppLiveTag(),
    'tag on dark': () => const ColoredBox(color: Color(0xFF000000), child: AppLiveTag(onDark: true, label: 'Live · 12:04')),
    'banner': () => AppLiveBanner(
        title: 'Maths: exponential functions', subtitle: 'With Mr Majed · 50 min', tag: 'Live · 12 min',
        hostInitial: 'M', actionLabel: 'Join', onAction: () {}),
    'banner, long title': () => AppLiveBanner(title: _long, subtitle: _long, hostInitial: 'م', actionLabel: 'ادخل الحصة', onAction: () {}),
    'banner, no subtitle, no host': () => AppLiveBanner(title: 'Physics', actionLabel: 'Join', onAction: () {}),
    'home live banner': () => HomeLiveBanner(now: DateTime.utc(2026, 1, 1, 10), items: [
          HomeLiveItem(title: 'Maths', hostName: 'Majed', startedAt: DateTime.utc(2026, 1, 1, 9, 48), onJoin: () {}),
          HomeLiveItem(title: _long, onJoin: () {}),
        ]),
  };

  for (final e in cases.entries) {
    testWidgets('layout: ${e.key}', (tester) async {
      await expectNoLayoutErrors(
          tester, () => AppAreaScope(area: AppArea.home, child: SingleChildScrollView(child: e.value())));
    });
  }

  testWidgets('the banner shows no participant count or avatars other than the host', (tester) async {
    await expectNoLayoutErrors(tester, () => AppLiveBanner(title: 'Room', hostInitial: 'R', actionLabel: 'Join', onAction: () {}));
  });

  testWidgets('the action calls onAction', (tester) async {
    var n = 0;
    await tester.pumpWidget(kitHost(AppLiveBanner(title: 'Room', actionLabel: 'Join', onAction: () => n++), reduce: true));
    await tester.tap(find.text('Join'));
    expect(n, 1);
  });
}
