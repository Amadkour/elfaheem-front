// The inbox page (lib/features/shared/inbox/inbox_page.dart): the inbox and the notifications on ONE page with the
// tabs To do · Notifications · Announcements & offers · Done. Pure rules (which tabs, the segment → tab mapping, the
// routes, the actionable count), the real page over the fake backend (each entry point on its tab, counts only on
// the actionable tabs, the kill switches, the platform admins, an organization's inbox), and the layout at 320x640
// and 1400x900, Arabic + English, textScaler 1.3, on every tab.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/inbox_badge.dart';
import 'package:flutter_education_app/features/shared/inbox/inbox_page.dart';
import 'package:flutter_education_app/features/shared/inbox/unified_inbox.dart';
import 'package:flutter_education_app/features/shared/notification/notifications_provider.dart';
import 'package:flutter_education_app/features/shared/notification/notifications_screen.dart' show NotificationTile;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'inbox_page_samples.dart';
import 'layout_harness.dart';

const _all = [InboxTab.todo, InboxTab.notifications, InboxTab.announcements, InboxTab.done];

Widget _page({InboxTab initial = InboxTab.todo, int? orgId}) => ChangeNotifierProvider<NotificationsProvider>(
      create: (_) => NotificationsProvider(),
      child: InboxPage(initial: initial, orgId: orgId, title: orgId == null ? null : 'Nile National University'),
    );

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });
  tearDown(() => AppConfig.setDisableList(const []));

  group('tabs', () {
    test('every tab by default; an organization\'s inbox has no Notifications tab', () {
      expect(inboxPageTabs(), _all);
      expect(inboxPageTabs(role: 'student'), _all);
      expect(inboxPageTabs(role: 'teacher', orgId: 4), [InboxTab.todo, InboxTab.announcements, InboxTab.done]);
    });

    test('the platform admins have no inbox: Notifications alone', () {
      for (final r in kInboxlessRoles) {
        expect(inboxPageTabs(role: r), [InboxTab.notifications]);
      }
    });

    test('a kill switch hides its tabs; both off → none', () {
      expect(inboxPageTabs(disabled: const [kNotificationsFeatureKey]), [InboxTab.todo, InboxTab.announcements, InboxTab.done]);
      expect(inboxPageTabs(disabled: const [kInboxFeatureKey]), [InboxTab.notifications]);
      expect(inboxPageTabs(disabled: const [kInboxFeatureKey, kNotificationsFeatureKey]), isEmpty);
    });

    test('the segments map onto the tabs (news + offers share one)', () {
      expect(inboxTabOfSegment(InboxSegment.todo), InboxTab.todo);
      expect(inboxTabOfSegment(InboxSegment.news), InboxTab.announcements);
      expect(inboxTabOfSegment(InboxSegment.offers), InboxTab.announcements);
      expect(inboxTabOfSegment(InboxSegment.done), InboxTab.done);
      expect(inboxTabSegments(InboxTab.announcements), [InboxSegment.news, InboxSegment.offers]);
      expect(inboxTabSegments(InboxTab.announcements, orgScoped: true), [InboxSegment.news]);
      expect(inboxTabSegments(InboxTab.notifications), isEmpty);
      // every segment is on exactly one tab
      for (final s in InboxSegment.values) {
        expect(_all.where((t) => inboxTabSegments(t).contains(s)), [inboxTabOfSegment(s)]);
      }
    });

    test('routes: the old /notifications and /inbox open their tab; others are not the inbox', () {
      expect(inboxRouteTab('/notifications'), InboxTab.notifications);
      expect(inboxRouteTab('/inbox'), InboxTab.todo);
      expect(inboxRouteTab('/inbox', InboxTab.done), InboxTab.done);
      expect(inboxRouteTab('/inbox', 'offers'), InboxTab.announcements);
      expect(inboxRouteTab('/inbox?tab=notifications'), InboxTab.notifications);
      expect(inboxRouteTab('/inbox?tab=nonsense'), InboxTab.todo);
      expect(inboxRouteTab('/calendar'), isNull);
      expect(inboxRouteTab(null), isNull);
      expect(inboxTabFromName('NEWS'), InboxTab.announcements);
      expect(inboxTabFromName('x'), isNull);
    });

    test('a hidden tab asked for opens the first one shown', () {
      expect(inboxStartTab(InboxTab.done, _all), InboxTab.done);
      expect(inboxStartTab(InboxTab.notifications, [InboxTab.todo, InboxTab.done]), InboxTab.todo);
    });
  });

  group('badge rule', () {
    test('only actionable things count: to-dos + unread notifications', () {
      expect(inboxActionableCount(todo: 3, unread: 2), 5);
      expect(inboxActionableCount(todo: -1, unread: 0), 0);
      const k = (todo: 2, overdue: 1, dueSoon: 0, news: 9, offers: 4);
      expect(inboxEntrySummary(k, unread: 3), '2 to do · 3 unread · 1 overdue');
      expect(inboxEntrySummary((todo: 0, overdue: 0, dueSoon: 0, news: 2, offers: 0), unread: 1), '1 unread');
      expect(inboxEntryHasAny((todo: 0, overdue: 0, dueSoon: 0, news: 0, offers: 0), unread: 1), isTrue);
    });

    test('the inbox kill switch hides the homes\' entry', () {
      const k = (todo: 2, overdue: 0, dueSoon: 0, news: 0, offers: 0);
      expect(inboxEntryShown(k), isTrue);
      AppConfig.setDisableList(const [kInboxFeatureKey]);
      expect(inboxEntryShown(k), isFalse);
    });

    testWidgets('the entry\'s count is to-dos + unread, never announcements / offers', (tester) async {
      await tester.pumpWidget(layoutHost(const Center(
          child: InboxEntry(counts: (todo: 2, overdue: 0, dueSoon: 0, news: 7, offers: 3), unread: 3))));
      await tester.pump();
      expect(find.text('5'), findsOneWidget);
      expect(find.text('10'), findsNothing);
    });
  });

  group('the page', () {
    late FakeApi api;
    setUp(() {
      api = FakeApi(inboxRoutes())..install();
      InboxBadge.instance.clear();
    });
    tearDown(() => api.uninstall());

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('the bell\'s route opens Notifications; counts only on To do and Notifications', (tester) async {
      await tester.pumpWidget(layoutHost(_page(initial: InboxTab.notifications)));
      await settle(tester);
      expect(find.byType(InboxTabBar), findsOneWidget);
      expect(find.byType(NotificationTile), findsWidgets);
      expect(find.text('Databases lecture has started'), findsOneWidget);
      final bar = tester.widget<InboxTabBar>(find.byType(InboxTabBar));
      expect(bar.current, InboxTab.notifications);
      expect(bar.counts[InboxTab.todo], 2);
      expect(bar.counts[InboxTab.notifications], 3);
      expect(bar.counts[InboxTab.announcements], isNull);
      expect(bar.counts[InboxTab.done], isNull);
      expect(bar.urgent, isTrue, reason: 'a to-do is overdue');
      // the whole inbox fed the bell's to-do half
      expect(InboxBadge.instance.todo, 2);
      // asked once each: the inbox (for the To do count) and the notifications (this tab)
      expect(api.calls.where((c) => c.path == '/api/v1/me/inbox').length, 1);
      expect(api.calls.where((c) => c.path == '/api/v1/notifications').length, 1);
    });

    testWidgets('the entry opens To do; the notifications are asked for only when their tab is opened', (tester) async {
      await tester.pumpWidget(layoutHost(_page()));
      await settle(tester);
      expect(find.byType(InboxCard), findsNWidgets(2));
      expect(api.calls.where((c) => c.path == '/api/v1/notifications'), isEmpty);
      await tester.tap(find.descendant(of: find.byType(InboxTabBar), matching: find.text('Notifications')));
      await settle(tester);
      expect(api.calls.where((c) => c.path == '/api/v1/notifications').length, 1);
      expect(find.text('Databases lecture has started'), findsOneWidget);
    });

    testWidgets('Announcements & offers: both under their headings; Done: the answered requests', (tester) async {
      await tester.pumpWidget(layoutHost(_page(initial: InboxTab.announcements)));
      await settle(tester);
      expect(find.text('Announcements'), findsOneWidget);
      expect(find.text('Offers'), findsOneWidget);
      expect(find.text('Statistics exam moved'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(InboxTabBar), matching: find.text('Done')));
      await settle(tester);
      expect(find.text('Enrolment letter request'), findsOneWidget);
    });

    testWidgets('one tab left → no tab bar', (tester) async {
      AppConfig.setDisableList(const [kInboxFeatureKey]);
      await tester.pumpWidget(layoutHost(_page()));
      await settle(tester);
      expect(find.byType(InboxTabBar), findsNothing);
      expect(find.byType(NotificationTile), findsWidgets);
      expect(api.calls.where((c) => c.path == '/api/v1/me/inbox'), isEmpty, reason: 'no inbox tab, no inbox call');
    });

    testWidgets('notifications off: the inbox tabs alone', (tester) async {
      AppConfig.setDisableList(const [kNotificationsFeatureKey]);
      await tester.pumpWidget(layoutHost(_page(initial: InboxTab.notifications)));
      await settle(tester);
      final bar = tester.widget<InboxTabBar>(find.byType(InboxTabBar));
      expect(bar.tabs, [InboxTab.todo, InboxTab.announcements, InboxTab.done]);
      expect(bar.current, InboxTab.todo);
    });

    testWidgets('an organization\'s inbox: its own call, no Notifications tab, "Announcements"', (tester) async {
      await tester.pumpWidget(layoutHost(_page(orgId: 4)));
      await settle(tester);
      final bar = tester.widget<InboxTabBar>(find.byType(InboxTabBar));
      expect(bar.tabs, [InboxTab.todo, InboxTab.announcements, InboxTab.done]);
      expect('${api.calls.single.query['org_id']}', '4');
      expect(find.text('Nile National University'), findsWidgets);
    });
  });

  group('layout', () {
    late FakeApi api;
    setUp(() => api = FakeApi(inboxRoutes())..install());
    tearDown(() => api.uninstall());

    for (final t in _all) {
      testWidgets('no overflow on ${t.name}', (tester) async {
        await expectNoLayoutErrors(tester, () => _page(initial: t), frames: 5);
      });
    }

    testWidgets('no overflow: an organization\'s inbox, an empty inbox', (tester) async {
      await expectNoLayoutErrors(tester, () => _page(orgId: 4), frames: 5);
      api.uninstall();
      api = FakeApi(inboxRoutes(empty: true))..install();
      await expectNoLayoutErrors(tester, () => _page(initial: InboxTab.announcements), frames: 5);
    });

    testWidgets('the tab bar with large counts, every tab selected', (tester) async {
      for (final t in _all) {
        await expectNoLayoutErrors(
          tester,
          () => Align(
            alignment: Alignment.topCenter,
            child: InboxTabBar(
              tabs: _all,
              current: t,
              urgent: true,
              counts: const {InboxTab.todo: 1234, InboxTab.notifications: 87},
              onTap: (_) {},
            ),
          ),
        );
      }
    });

    testWidgets('48 px tab targets', (tester) async {
      await tester.pumpWidget(layoutHost(Align(
        alignment: Alignment.topCenter,
        child: InboxTabBar(tabs: _all, current: InboxTab.todo, onTap: (_) {}),
      )));
      await tester.pump();
      for (final ink in tester.widgetList<InkWell>(find.byType(InkWell))) {
        expect(tester.getSize(find.byWidget(ink)).height, greaterThanOrEqualTo(48));
      }
    });
  });
}
