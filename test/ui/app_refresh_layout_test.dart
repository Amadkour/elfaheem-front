// AppRefresh / AppRefreshAction (lib/design/app_refresh.dart) and the calendar entry (lib/design/calendar_entry.dart)
// at 320x640 and 1400x900, Arabic + English, textScaler 1.3 — plus the behaviour: a pull calls onRefresh even when
// the content is shorter than the screen, and the entry opens '/calendar'.
import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/design/calendar_entry.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Widget _list(int n) => ListView(children: [for (var i = 0; i < n; i++) ListTile(title: Text('row $i'))]);

Future<void> _pull(WidgetTester tester, Finder on) async {
  await tester.fling(on, const Offset(0, 300), 1000);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1)); // the scroll settles
  await tester.pump(const Duration(seconds: 1)); // the indicator settles
  await tester.pump(const Duration(seconds: 1)); // the indicator hides
}

void main() {
  setUp(() => AppConfig.lang = 'ar');

  testWidgets('AppRefresh: long list, short list, non-scrollable child, filled child', (tester) async {
    Future<void> noop() async {}
    await expectNoLayoutErrors(tester, () => AppRefresh(onRefresh: noop, child: _list(40)));
    await expectNoLayoutErrors(tester, () => AppRefresh(onRefresh: noop, child: _list(2)));
    await expectNoLayoutErrors(tester,
        () => AppRefresh(onRefresh: noop, scrollable: false, child: const Center(child: Icon(Icons.inbox_rounded))));
    await expectNoLayoutErrors(
        tester,
        () => AppRefresh(
            onRefresh: noop,
            scrollable: false,
            fill: true,
            child: Column(children: [const Text('head'), Expanded(child: _list(30))])));
  });

  testWidgets('a pull calls onRefresh even when the content is shorter than the screen', (tester) async {
    var calls = 0;
    Future<void> load() async => calls++;
    await tester.pumpWidget(layoutHost(AppRefresh(onRefresh: load, child: _list(2))));
    await tester.pump();
    await _pull(tester, find.text('row 0'));
    expect(calls, 1, reason: 'short ListView (default physics) accepts the pull');

    await tester.pumpWidget(layoutHost(
        AppRefresh(onRefresh: load, scrollable: false, child: const Center(child: Text('empty')))));
    await tester.pump();
    await _pull(tester, find.text('empty'));
    expect(calls, 2, reason: 'non-scrollable child accepts the pull');
  });

  testWidgets('AppRefreshAction: hidden on phones, shown with always, runs onRefresh', (tester) async {
    var calls = 0;
    Future<void> load() async => calls++;
    await expectNoLayoutErrors(tester, () => AppBar(title: const Text('x'), actions: [AppRefreshAction(onRefresh: load)]));
    await expectNoLayoutErrors(tester,
        () => AppBar(title: const Text('x'), actions: [AppRefreshAction(onRefresh: load, always: true)]),
        act: (t) => t.tap(find.byIcon(Icons.refresh_rounded)));
    expect(calls, greaterThan(0));

    // the test platform is Android: no button (phones pull instead)
    await tester.pumpWidget(layoutHost(AppRefreshAction(onRefresh: load)));
    await tester.pump();
    expect(find.byIcon(Icons.refresh_rounded), findsNothing, reason: 'phones pull instead');
    expect(AppRefreshAction.wanted, isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final onDesktop = AppRefreshAction.wanted;
    debugDefaultTargetPlatformOverride = null; // before the framework checks its debug variables
    expect(onDesktop, isTrue);
  });

  testWidgets('calendar entry: header icon, settings tile, hidden by the kill switch', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => const HomeHeader(
            name: 'أحمد حمدي مدكور عبد الرحمن الطويل جداً جداً',
            subtitle: 'home',
            actions: [CalendarEntryIcon(), CalendarEntryIcon()]));
    await expectNoLayoutErrors(tester, () => const Column(children: [CalendarEntryTile(), CalendarEntryTile()]));

    final prev = AppConfig.disableList;
    addTearDown(() => AppConfig.disableList = prev);
    AppConfig.disableList = [calendarEntryFeatureKey];
    await tester.pumpWidget(layoutHost(const Row(children: [CalendarEntryIcon(), CalendarEntryTile()])));
    await tester.pump();
    expect(find.byIcon(Icons.event_rounded), findsNothing);
    AppConfig.disableList = prev;
  });

  testWidgets('tapping the entry opens /calendar', (tester) async {
    final theme = ThemeConfigProvider(api: ApiClient());
    await tester.pumpWidget(ThemeConfigScope(
      provider: theme,
      child: MaterialApp(
        routes: {'/calendar': (_) => const Scaffold(body: Text('CAL'))},
        home: const Scaffold(body: Column(children: [CalendarEntryIcon(), CalendarEntryTile()])),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byType(CalendarEntryTile));
    await tester.pumpAndSettle();
    expect(find.text('CAL'), findsOneWidget);
  });
}
