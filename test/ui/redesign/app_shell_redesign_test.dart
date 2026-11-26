// The redesigned shells (KIT_SPEC §6, §7.2): the phone bar's ONE blob (M13) sits under the open slot in Arabic and
// English, under a group slot while one of its members is open, and takes the open tab's area tint; the sidebar and
// the rail draw the open tab's bar on the window's start edge; AppShell takes its role accent from `accent:` or from
// the role it is drawn for (View as first); every shell lays out at both harness sizes.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_area.dart';
import 'package:flutter_education_app/design/app_shell.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/utils/widget/view_as_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../layout_harness.dart';

void main() {
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.getInstance();
    AppConfig.lang = 'ar';
    ShellBadge.source = () => ValueNotifier(0);
    ShellBadge.countOf = (_, _) => 0;
  });

  const learn = ShellMobileGroup('learn', Icons.school_outlined, Icons.school_rounded, 'learn');

  List<DashboardItem> tabs(int n, {AppArea? area, bool group = false}) => [
        for (var i = 0; i < n; i++)
          DashboardItem(Icons.circle_outlined, Icons.circle, 'tab$i', null, Text('page $i'),
              area: i == 1 ? area : null, badge: i == 2 ? 3 : 0, mobileGroup: group && i >= 2 && i <= 4 ? learn : null),
      ];

  Widget host(Widget child, {bool rtl = true, double scale = 1}) => ThemeConfigScope(
        provider: ThemeConfigProvider(api: ApiClient()),
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => MyAuthProvider(storage: storage)),
            ChangeNotifierProvider(create: (_) => LangProvider(storage: storage)),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            builder: (context, w) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true, textScaler: TextScaler.linear(scale)),
              child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
            ),
            home: child,
          ),
        ),
      );

  Future<void> size(WidgetTester tester, Size s) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = s;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// The blob's painted box.
  Rect blob(WidgetTester tester) => tester.getRect(find
      .descendant(of: find.byKey(const ValueKey('app.shell.blob')), matching: find.byType(AnimatedContainer))
      .first);

  BoxDecoration blobPaint(WidgetTester tester) => tester
      .widget<AnimatedContainer>(
          find.descendant(of: find.byKey(const ValueKey('app.shell.blob')), matching: find.byType(AnimatedContainer)).first)
      .decoration! as BoxDecoration;

  testWidgets('phone bar: the blob sits under the open slot (3 / 5 / 8 tabs, ar + en)', (tester) async {
    await size(tester, const Size(390, 844));
    for (final rtl in const [true, false]) {
      AppConfig.lang = rtl ? 'ar' : 'en';
      for (final n in const [3, 5]) {
        for (final open in [0, n - 1]) {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(host(MobileShell(currentIndex: open, onTap: (_) {}, dashboardItems: tabs(n)), rtl: rtl));
          await tester.pump();
          final tab = tester.getRect(find.text('tab$open'));
          final b = blob(tester);
          expect((b.center.dx - tab.center.dx).abs(), lessThan(1), reason: '$n tabs, open $open, rtl $rtl');
          expect(b.height, closeTo(50, 0.5), reason: 'the row is 50 high');
        }
      }
      // 8 tabs fold into five slots: tab 6 is in "More", the last slot
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(host(MobileShell(currentIndex: 6, onTap: (_) {}, dashboardItems: tabs(8)), rtl: rtl));
      await tester.pump();
      final more = tester.getRect(find.byKey(const ValueKey('shell.group.more')));
      expect((blob(tester).center.dx - more.center.dx).abs(), lessThan(1), reason: 'under More, rtl $rtl');
      // a group slot is open while a member is: tab 3 of the Learn group
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
          host(MobileShell(currentIndex: 3, onTap: (_) {}, dashboardItems: tabs(8, group: true)), rtl: rtl));
      await tester.pump();
      final group = tester.getRect(find.byKey(const ValueKey('shell.group.learn')));
      expect((blob(tester).center.dx - group.center.dx).abs(), lessThan(1), reason: 'under the group, rtl $rtl');
    }
  });

  testWidgets('phone bar: the blob takes the open tab\'s area tint, else the shell set\'s', (tester) async {
    await size(tester, const Size(390, 844));
    await tester.pumpWidget(host(MobileShell(currentIndex: 1, onTap: (_) {}, dashboardItems: tabs(5, area: AppArea.games))));
    await tester.pump();
    final kit = tester.element(find.byType(MobileShell)).colors.kit;
    expect(blobPaint(tester).color, kit.area(AppArea.games).tint);
    await tester.pumpWidget(host(AppAreaScope.role(
        role: AppRoleAccent.teacher,
        budget: false,
        child: MobileShell(currentIndex: 0, onTap: (_) {}, dashboardItems: tabs(5, area: AppArea.games)))));
    await tester.pump();
    expect(blobPaint(tester).color, kit.role(AppRoleAccent.teacher).tint, reason: 'no area on tab 0: the role set');
  });

  testWidgets('sidebar (1400) and rail (800): the open tab\'s bar is on the window\'s start edge', (tester) async {
    for (final rtl in const [true, false]) {
      AppConfig.lang = rtl ? 'ar' : 'en';
      for (final w in const [1400.0, 800.0]) {
        await size(tester, Size(w, 900));
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(host(
            w >= 1000
                ? WideShell(currentIndex: 1, onTap: (_) {}, dashboardItems: tabs(5), unreadCount: 2)
                : RailShell(currentIndex: 1, onTap: (_) {}, dashboardItems: tabs(5), unreadCount: 2),
            rtl: rtl));
        await tester.pump();
        final bar = tester.getRect(find.byKey(const ValueKey('app.shell.edge')));
        final side = tester.getRect(find.byKey(const ValueKey('app.shell.side')));
        if (rtl) {
          expect(bar.right, closeTo(w, 0.5), reason: 'Arabic: the right edge at $w');
          expect(side.right, closeTo(w, 0.5));
        } else {
          expect(bar.left, closeTo(0, 0.5), reason: 'English: the left edge at $w');
          expect(side.left, closeTo(0, 0.5));
        }
        expect(side.height, 900, reason: 'flush, full height');
        expect(side.width, w >= 1000 ? 260 : 72);
      }
    }
  });

  testWidgets('AppShell: accent from the parameter, else the role it is drawn for (View as first)', (tester) async {
    await size(tester, const Size(1400, 900));
    AppRoleAccent? scopeRole() {
      final f = find.byType(AppAreaScope);
      if (f.evaluate().isEmpty) return null;
      return AppAreaScope.roleOf(tester.element(find.text('page 0')));
    }

    Widget shell({AppRoleAccent? accent}) =>
        host(AppShell(width: 1400, currentIndex: 0, onTap: (_) {}, items: tabs(3), accent: accent));
    await tester.pumpWidget(shell(accent: AppRoleAccent.parent));
    await tester.pump();
    expect(scopeRole(), AppRoleAccent.parent);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(shell());
    await tester.pump();
    expect(scopeRole(), isNull, reason: 'no one signed in: a student shell sets no scope');

    ViewAsState.instance.start(id: 9, name: 'x', role: 'teacher');
    addTearDown(ViewAsState.instance.stop);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(shell());
    await tester.pump();
    expect(scopeRole(), AppRoleAccent.teacher, reason: 'View as a teacher');
    ViewAsState.instance.stop();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('three redesigned shells × the harness: no overflow', (tester) async {
    Widget wrap(Widget w) => MultiProvider(providers: [
          ChangeNotifierProvider(create: (_) => MyAuthProvider(storage: storage)),
          ChangeNotifierProvider(create: (_) => LangProvider(storage: storage)),
        ], child: w);
    await expectNoLayoutErrors(
        tester, () => wrap(WideShell(currentIndex: 1, onTap: (_) {}, dashboardItems: tabs(8), unreadCount: 120)),
        scaffold: false);
    await expectNoLayoutErrors(
        tester, () => wrap(RailShell(currentIndex: 2, onTap: (_) {}, dashboardItems: tabs(8), unreadCount: 3)),
        scaffold: false);
    await expectNoLayoutErrors(
        tester, () => wrap(MobileShell(currentIndex: 1, onTap: (_) {}, dashboardItems: tabs(8, area: AppArea.learn))),
        scaffold: false);
    await tester.pumpWidget(const SizedBox());
  });
}
