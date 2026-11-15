// UX v3 phase 5 (performance):
//   • one request for two callers at once (InFlight, AttentionFlowStore.load)
//   • the badge poll: 60 s / 5 min with the live stream / none in the background, paused and resumed with the app
//   • optimistic mark-read: the dot goes at once, a failed PUT puts it back
//   • long lists are lazy: 500 rows build only the visible ones (action inbox, notifications)
//   • the action inbox loads more (a longer `limit`: the server has no offset) and its search is debounced
//   • a vote's reply patches the session in place (no second GET)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart';
import 'package:flutter_education_app/core/in_flight.dart';
import 'package:flutter_education_app/features/messaging/notification/notifications_provider.dart';
import 'package:flutter_education_app/features/messaging/notification/notifications_screen.dart';
import 'package:flutter_education_app/features/org/governance/gov_models.dart';
import 'package:flutter_education_app/features/org/governance/gov_session_screen.dart' show sessionWithAgendaReply;
import 'package:flutter_education_app/features/org/needs_my_action_page.dart';
import 'package:flutter_education_app/features/org/org_attention_flow.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

Map<String, dynamic> _inbox(int i) => {
      'key': 'org_work:$i',
      'kind': 'work_item',
      'action': 'approve',
      'title': 'Request $i',
      'reason_en': 'Waiting for your decision',
      'module': 'org_work',
      'id': 100 + i,
      'org_id': 7,
      'urgency': 1,
    };

Map<String, dynamic> _notif(int id, {bool read = false}) => {
      'id': id,
      'title': 't$id',
      'message': 'm$id',
      'type': 'general',
      'is_read': read,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  group('one request for two callers', () {
    test('InFlight shares the running future, then asks again', () async {
      final f = InFlight<int, int>();
      var started = 0;
      final gate = Completer<int>();
      Future<int> start() {
        started++;
        return gate.future;
      }

      final a = f.run(1, start);
      final b = f.run(1, start);
      expect(identical(a, b), isTrue);
      expect(started, 1);
      gate.complete(5);
      expect(await a, 5);
      expect(await b, 5);
      expect(f.isRunning(1), isFalse);
      f.run(1, () async => 6);
      expect(started, 1, reason: 'the second start is the inline one');
    });

    test('a failed request frees its key', () async {
      final f = InFlight<String, int>();
      await expectLater(f.run('k', () async => throw StateError('x')), throwsStateError);
      expect(f.isRunning('k'), isFalse);
      expect(await f.run('k', () async => 2), 2);
    });

    test('AttentionFlowStore.load twice at once = one GET', () async {
      final api = FakeApi({
        'GET ${orgAttentionFlowPath(4)}': (_) => {'counts': {'total': 1, 'votes': 1}},
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(api.uninstall);
      AttentionFlowStore.instance.reset();
      final both = await Future.wait([AttentionFlowStore.instance.load(4), AttentionFlowStore.instance.load(4)]);
      expect(api.calls.where((c) => c.path == orgAttentionFlowPath(4)).length, 1);
      expect(identical(both[0], both[1]), isTrue);
      await AttentionFlowStore.instance.load(4);
      expect(api.calls.where((c) => c.path == orgAttentionFlowPath(4)).length, 2, reason: 'nothing is cached once answered');
    });
  });

  group('the badge poll', () {
    test('60 s, 5 min with the live stream, none in the background', () {
      expect(attentionPollEvery(inFront: true, streamConnected: false), AttentionService.pollEvery);
      expect(AttentionService.pollEvery, const Duration(seconds: 60));
      expect(attentionPollEvery(inFront: true, streamConnected: true), AttentionService.pollEveryLive);
      expect(AttentionService.pollEveryLive, const Duration(minutes: 5));
      expect(attentionPollEvery(inFront: false, streamConnected: false), isNull);
      expect(attentionPollEvery(inFront: false, streamConnected: true), isNull);
    });

    testWidgets('paused in the background, back on resume; nothing once no badge listens', (tester) async {
      final api = FakeApi({'GET /api/v1/me/attention': (_) => {'items': []}}, latency: Duration.zero)..install();
      addTearDown(api.uninstall);
      final svc = AttentionService.instance;
      void l() {}
      svc.addListener(l);
      expect(svc.pollingEvery, AttentionService.pollEvery);
      svc.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(svc.pollingEvery, AttentionService.pollEvery, reason: 'inactive is still on screen');
      svc.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(svc.pollingEvery, isNull);
      svc.didChangeAppLifecycleState(AppLifecycleState.hidden);
      expect(svc.pollingEvery, isNull);
      svc.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(svc.pollingEvery, AttentionService.pollEvery);
      svc.removeListener(l);
      expect(svc.pollingEvery, isNull);
      await tester.pump(const Duration(seconds: 6));
    });
  });

  group('optimistic mark-read', () {
    test('the dot goes at once; a failed PUT puts it back', () async {
      final api = FakeApi({
        'GET /api/v1/notifications': (_) => {'items': [_notif(1), _notif(2)], 'total': 2, 'unread': 2},
        'PUT /api/v1/notifications/*': (_) => const FakeResponse(500, {'detail': 'boom'}),
      }, latency: Duration.zero)
        ..install();
      addTearDown(api.uninstall);
      final p = NotificationsProvider();
      await p.fetchNotifications();
      expect(p.unreadCount, 2);
      final done = p.markAsRead('1');
      expect(p.allNotifs.firstWhere((n) => n.id == '1').isRead, isTrue, reason: 'before the server answered');
      expect(p.unreadCount, 1);
      expect(p.isLoading, isFalse, reason: 'a tap never flips the list into loading');
      expect(await done, isFalse);
      expect(p.allNotifs.firstWhere((n) => n.id == '1').isRead, isFalse, reason: 'rolled back');
      expect(p.unreadCount, 2);
      expect(api.calls.where((c) => c.method == 'PUT').length, 1, reason: 'no retry behind the person\'s back');
    });
  });

  group('lazy lists', () {
    testWidgets('500 inbox rows build only the visible ones', (tester) async {
      final items = [for (var i = 0; i < 500; i++) ActionInboxItem.fromJson(_inbox(i))];
      await tester.pumpWidget(layoutHost(CustomScrollView(slivers: [NeedsMyActionList.sliver(items: items)])));
      final built = find.byType(NeedsMyActionRow).evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(40));
    });

    testWidgets('500 notifications build only the visible ones', (tester) async {
      final rows = [
        for (var i = 0; i < 500; i++)
          NotificationModel(id: '$i', title: 'Title $i', body: 'Body', group: NotifGroup.today, sourceId: 0, type: 'general', relatedType: ''),
      ];
      await tester.pumpWidget(layoutHost(NotificationsStateBody(
        loading: false,
        empty: false,
        error: null,
        onRefresh: () async {},
        gap: 0,
        children: notificationGroupRows(rows, title: 'Today'),
      )));
      await tester.pump(const Duration(seconds: 2));
      final built = find.byType(NotificationTile).evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(40));
    });

    testWidgets('wide: two tiles a row, every tile once', (tester) async {
      final rows = [
        for (var i = 0; i < 3; i++)
          NotificationModel(id: '$i', title: 'Title $i', body: 'Body', group: NotifGroup.yesterday, sourceId: 0, type: 'general', relatedType: ''),
      ];
      final flat = notificationGroupRows(rows, title: 'Yesterday', twoUp: true);
      expect(flat.length, 1 + 2 + 1, reason: 'header, two rows (2 + 1 tiles), the closing space');
      expect(notificationGroupRows(const [], title: 'x'), isEmpty);
    });
  });

  group('action inbox: load more, search', () {
    test('the next limit while rows are missing, up to the server\'s 200', () {
      expect(actionInboxNextLimit(limit: 50, loaded: 50, total: 120), 100);
      expect(actionInboxNextLimit(limit: 100, loaded: 100, total: 120), 150);
      expect(actionInboxNextLimit(limit: 150, loaded: 120, total: 120), isNull);
      expect(actionInboxNextLimit(limit: 50, loaded: 30, total: 30), isNull);
      expect(actionInboxNextLimit(limit: 200, loaded: 200, total: 900), isNull);
    });

    testWidgets('scrolling to the end asks for a longer list; typing asks once', (tester) async {
      final api = FakeApi({
        'GET $kActionInboxPath': (o) {
          final limit = int.parse('${o.queryParameters['limit']}');
          final n = limit < 120 ? limit : 120;
          return {'items': [for (var i = 0; i < n; i++) _inbox(i)], 'total': 120};
        },
      }, latency: const Duration(milliseconds: 10))
        ..install();
      addTearDown(api.uninstall);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(layoutHost(const NeedsMyActionPage(embedded: true)));
      await tester.pump(const Duration(milliseconds: 50));
      List<String> limits() => [for (final c in api.calls) '${c.query['limit']}'];
      expect(limits(), ['50']);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -30000));
      await tester.pump(const Duration(milliseconds: 50));
      expect(limits(), ['50', '100']);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -30000));
      await tester.pump(const Duration(milliseconds: 50));
      expect(limits(), ['50', '100', '150']);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -30000));
      await tester.pump(const Duration(milliseconds: 50));
      expect(limits(), ['50', '100', '150'], reason: 'all 120 are in');

      api.reset();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 90000));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump(const Duration(milliseconds: 500));
      expect([for (final c in api.calls) c.query['q']], ['abc'], reason: 'one request per pause in typing');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  test('a vote\'s reply patches the session in place', () {
    Map<String, dynamic> row(int id, {String? mine, int approve = 0}) => {
          'id': id,
          'order': id,
          'status': 'voting',
          'item': {'id': 900 + id, 'title': 'Item $id'},
          'my_vote': ?mine,
          'live': {'approve': approve},
        };
    final s = CouncilSession.fromJson({
      'id': 3,
      'status': 'voting',
      'agenda': [row(1), row(2)],
      'my_votes': <String, dynamic>{},
      'can': {'vote': true},
    });
    expect(s.pendingMyVotes, 2);
    final next = sessionWithAgendaReply(s, row(2, mine: 'approve', approve: 1), myVote: 'approve')!;
    expect(next.agenda.firstWhere((a) => a.id == 2).myVote, 'approve');
    expect(next.myVotes[2], 'approve');
    expect(next.pendingMyVotes, 1);
    expect(next.agenda.length, 2);
    expect(sessionWithAgendaReply(s, {'id': 2, 'status': 'voting'}), isNull, reason: 'not a whole row: reload');
    expect(sessionWithAgendaReply(s, row(7)), isNull, reason: 'not a row of this session');
  });
}
