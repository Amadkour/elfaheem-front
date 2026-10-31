// "I approve / reject a request and the badge does not go down": the person who acted is never sent the server's
// `attention_changed` (only the other reviewers are), and the route-pop refresh is throttled to one per 15 s. After
// a successful decision call the app now reloads the badge counts itself (lib/core/attention/decision_refresh.dart →
// AttentionService.onDecision), and the review lists' own badges drop the moment the server said yes.
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart';
import 'package:flutter_education_app/core/attention/decision_refresh.dart';
import 'package:flutter_education_app/features/admin/enrollment_request/teacher_transfers_provider.dart';
import 'package:flutter_education_app/features/teacher/profile/switch_device_requests/teacher_device_requests_provider.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

Future<void> _settle([Duration d = const Duration(milliseconds: 450)]) => Future<void>.delayed(d);

/// Real time (plain `test`): the first request of a run reads the token and the device id first.
Future<void> _until(bool Function() ok, {Duration max = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(max);
  while (!ok() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  group('isDecisionRequest', () {
    test('writes that decide a waiting item', () {
      for (final p in [
        '/api/v1/payments/transfers/7/approve',
        '/api/v1/payments/transfers/7/reject',
        '/api/v1/admin/withdrawals/3/mark-paid',
        '/api/v1/admin/ads/9/approve',
        '/api/v1/admin/orgs/4/suspend',
        '/api/v1/admin/teacher-documents/5/status',
        '/api/v1/admin/points/topups/2/reject',
        '/api/v1/devices/teacher/switch-requests/8/approve',
        '/api/v1/certificate-requests/1/approve',
        '/api/v1/org/orgs/12/join-requests/40/approve',
        '/api/v1/org/orgs/12/requests/41/reject',
        '/api/v1/org/orgs/12/form-responses/77',
        '/api/v1/org/orgs/12/tasks/join:41/approve',
        '/api/v1/org/orgs/12/registrar/decisions/5/accept',
        '/api/v1/org/orgs/12/gov/items/3/decide',
        '/api/v1/complaints/15',
        '/api/v1/complaints/15/replies',
        '/api/v1/live/session/4/lobby/admit-all',
        '/api/v1/org/orgs/12/join-requests/40/approve/', // trailing slash
        '/api/v1/admin/subscriptions/2/approve?x=1', // query
      ]) {
        expect(isDecisionRequest('POST', p), isTrue, reason: p);
      }
      expect(isDecisionRequest('put', '/api/v1/org/orgs/12/form-responses/77'), isTrue);
    });

    test('reads, other writes and foreign URLs are not decisions', () {
      expect(isDecisionRequest('GET', '/api/v1/payments/transfers/7/approve'), isFalse);
      for (final p in [
        '/api/v1/complaints', // a new complaint
        '/api/v1/me/events/ticket',
        '/api/v1/auth/refresh',
        '/api/v1/org/orgs/12/announcements',
        '/api/v1/exam/attempts/3/answers',
        'https://bucket.example/upload/approve', // not the app's API
      ]) {
        expect(isDecisionRequest('POST', p), isFalse, reason: p);
      }
    });
  });

  group('after a decision', () {
    var pending = 2;
    late FakeApi fake;

    Map<String, dynamic> attention() => {
          'counts': {if (pending > 0) 'admin.finance': pending},
          'items': [
            if (pending > 0)
              {'key': 'transfers:pending', 'kind': 'transfers', 'tab': 'admin.finance', 'count': pending},
          ],
        };

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
      pending = 2;
      DecisionRefresh.enabled = true;
      fake = FakeApi({
        'GET /api/v1/me/attention': (_) => attention(),
        'POST /api/v1/payments/transfers/7/approve': (_) {
          pending--;
          return {'id': 7, 'status': 'completed'};
        },
        'POST /api/v1/complaints': (_) => {'id': 1},
        'GET /api/v1/payments/transfers/pending': (_) => {
              'items': [
                for (var i = 0; i < pending; i++) {'payment_id': 7 + i, 'amount': 100, 'course_id': 1, 'student_id': 1, 'student_name': 'S$i'},
              ],
              'total': pending,
            },
      }, latency: Duration.zero); // anything else: 404
      fake.install();
    });
    tearDown(() => fake.uninstall());

    test('the badge counts reload at once — not on the throttled route change or the 5-minute poll', () async {
      final att = AttentionService.instance;
      void l() {}
      att.addListener(l);
      addTearDown(() => att.removeListener(l));
      await _until(() => att.count(AttentionTabs.adminFinance) == 2);
      expect(att.count(AttentionTabs.adminFinance), 2, reason: '${fake.calls} ${fake.unmatched}');
      await _settle(const Duration(milliseconds: 100)); // the first load is done
      int reads() => fake.calls.where((c) => c.key == 'GET /api/v1/me/attention').length;
      final before = reads();

      att.onRouteChanged(); // back from the list right away: throttled, nothing re-read
      await _settle(const Duration(milliseconds: 50));
      expect(reads(), before);

      await ApiClient().post('/api/v1/payments/transfers/7/approve', body: {});
      await _settle();
      expect(reads(), before + 1, reason: 'one reload for one decision');
      expect(att.count(AttentionTabs.adminFinance), 1);

      // a read, a write that decides nothing, a decision the server refused (404): no reload
      await ApiClient().get('/api/v1/payments/transfers/pending');
      await ApiClient().post('/api/v1/complaints', body: {'title': 'x'});
      await expectLater(ApiClient().post('/api/v1/org/orgs/1/join-requests/9/approve', body: {}), throwsA(isA<ApiException>()));
      await _settle();
      expect(reads(), before + 1);
    });

    test('a burst of decisions is one local event', () async {
      final seen = <LiveEvent>[];
      final sub = LiveEvents.instance.listen({LiveEvents.attentionChanged}, seen.add);
      addTearDown(sub.cancel);
      for (var i = 0; i < 3; i++) {
        DecisionRefresh.onSuccess('POST', '/api/v1/admin/ads/$i/approve');
      }
      await _settle();
      expect(seen.length, 1);
      expect(DecisionRefresh.isLocal(seen.single), isTrue);
      expect(seen.single.tab, isNull, reason: 'every tab');
    });

    test('transfers: the services-hub badge drops when the server accepts, even if the card never finishes animating',
        () async {
      final p = TeacherTransfersProvider();
      addTearDown(p.dispose);
      await p.load();
      expect(p.total, 2);
      expect(await p.approve(7), isTrue);
      expect(p.total, 1, reason: 'counted down before the exit animation');
      p.removeItem(7); // the animation ended
      expect(p.total, 1, reason: 'never counted twice');
      expect(p.items.map((t) => t.paymentId), [8]);
    });

    test('transfers: a request decided while its card was still animating never comes back on the next visit',
        () async {
      final p = TeacherTransfersProvider();
      addTearDown(p.dispose);
      await p.load();
      expect(await p.approve(7), isTrue);
      // the screen closed mid-animation: removeItem never ran
      await p.ensureLoaded();
      expect(p.items.map((t) => t.paymentId), isNot(contains(7)));
      expect(p.total, 1);
    });

    test('transfers: another reviewer decided (`transfers_updated`) → the list and the badge reload', () async {
      final p = TeacherTransfersProvider();
      addTearDown(p.dispose);
      await p.load();
      expect(p.total, 2);
      pending = 0; // a colleague handled both
      LiveEvents.instance.emit(LiveEvents.transfers, {'payment_id': '7', 'action': 'approved'});
      await _settle(const Duration(milliseconds: 50));
      expect(p.total, 0);
      expect(p.items, isEmpty);
    });
  });

  test('device-switch requests: the profile badge (pendingCount) drops on a successful decision', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    final fake = FakeApi({
      'GET /api/v1/devices/teacher/switch-requests': (_) => {
            'items': [
              {'id': 1, 'student_name': 'A'},
              {'id': 2, 'student_name': 'B'},
            ],
          },
      'POST /api/v1/devices/teacher/switch-requests/1/approve': (_) => {'ok': true},
    }, latency: Duration.zero);
    fake.install();
    addTearDown(fake.uninstall);
    final p = TeacherDeviceRequestsProvider();
    addTearDown(p.dispose);
    await p.load();
    expect(p.pendingCount, 2);
    expect(await p.approve(1), isTrue);
    expect(p.pendingCount, 1);
    expect(p.items.length, 2, reason: 'the card is still there for its exit animation');
    await p.ensureLoaded(); // next visit, the animation never finished
    expect(p.items.map((e) => e.id), [2]);
    expect(p.pendingCount, 1);
  });
}
