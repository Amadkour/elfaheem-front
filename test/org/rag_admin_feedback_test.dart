// Feedback review: cluster parsing, paging, the verify body, the admin and the org routes, and the verify flow in the
// widget (prefilled editor -> POST -> notice with cache_purged).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/rag/admin/rag_feedback_review.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';
import 'rag_admin_fixtures.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  test('a page parses clusters, counts and the verified badge', () {
    final p = FeedbackPage.fromJson(feedbackPage([
      feedbackCluster('c1', verified: {'qa_id': 5, 'enabled': true, 'version': 2}),
      feedbackCluster('c2', scope: 'org'),
    ], total: 45));
    expect(p.items.length, 2);
    expect(p.total, 45);
    expect(p.hasMore, isTrue);
    expect(p.helpful, 12);
    expect(p.unhelpful, 7);
    final k = p.items.first;
    expect(k.isVerified, isTrue);
    expect(k.verified!.qaId, 5);
    expect(k.verified!.version, 2);
    expect(k.questions.length, 3);
    expect(k.answer!.citations.single.label, 'Terms and Conditions · Account · p.3');
    expect(k.comments.single.text, contains('button'));
    expect(p.items.last.scope, 'org');
    expect(p.items.last.orgId, 5);
    expect(p.items.last.isVerified, isFalse);
  });

  test('paging appends the next slice and stops at the total', () {
    final a = FeedbackPage.fromJson(feedbackPage([feedbackCluster('c1')], total: 2));
    final b = FeedbackPage.fromJson(feedbackPage([feedbackCluster('c2')], total: 2, offset: 1));
    final all = a.append(b);
    expect(all.items.map((k) => k.key), ['c1', 'c2']);
    expect(all.hasMore, isFalse);
  });

  test('the verify body leaves out what is empty', () {
    final body = feedbackVerifyBody(answer: '  Go to Settings.  ', question: ' ', variants: ['a', ' ', 'b'], deepLink: '', lang: 'en');
    expect(body, {
      'answer': 'Go to Settings.',
      'variants': ['a', 'b'],
      'lang': 'en',
      'enabled': true,
    });
    final full = feedbackVerifyBody(
        answer: 'x y z', question: 'Q?', deepLink: 'account.subscription', enabled: false, citations: const [FeedbackCitation(title: 'T', section: 'S', documentId: 3)]);
    expect(full['deep_link'], 'account.subscription');
    expect(full['enabled'], false);
    expect(full['citations'], [
      {'title': 'T', 'section': 'S', 'document_id': 3},
    ]);
  });

  test('an older cluster payload (no answer, no verified) still parses', () {
    final k = FeedbackCluster.fromJson({'key': 'c9', 'question': 'q', 'dislikes': 1});
    expect(k.answer, isNull);
    expect(k.questions, isEmpty);
    expect(k.scope, 'app');
    expect(k.isVerified, isFalse);
  });

  test('the platform and the organization use their own routes', () async {
    final api = FakeApi({
      'GET /api/v1/rag/admin/feedback/clusters': (_) => feedbackPage([feedbackCluster('c1')]),
      'GET /api/v1/rag/orgs/5/answers/feedback/clusters': (_) => feedbackPage([feedbackCluster('c2', scope: 'org')]),
      'POST /api/v1/rag/admin/feedback/clusters/c1/verify': (_) => const FakeResponse(404, {'detail': {'code': 'cluster_not_found', 'message': 'gone'}}),
    }, latency: const Duration(milliseconds: 1))
      ..install();
    addTearDown(api.uninstall);
    await ApiClient().primeSession();
    final admin = await FeedbackReviewApi().clusters(days: 7, minDislikes: 2, orgFilter: 5);
    expect(admin.ok, isTrue);
    final call = api.calls.first;
    expect(call.query, containsPair('days', '7'));
    expect(call.query, containsPair('min_dislikes', '2'));
    expect(call.query, containsPair('org_id', '5'));
    final org = await FeedbackReviewApi(orgId: 5).clusters(orgFilter: 99);
    expect(org.ok, isTrue);
    expect(api.calls.last.path, '/api/v1/rag/orgs/5/answers/feedback/clusters');
    expect(api.calls.last.query.containsKey('org_id'), isFalse); // an org manager never filters by organization
    final v = await FeedbackReviewApi().verify('c1', {'answer': 'x'});
    expect(v.ok, isFalse);
    expect(feedbackErrorText(v), contains('no longer exists'));
  });

  testWidgets('verify flow: the editor is prefilled, saving POSTs the body and says how many cached answers went', (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    Object? posted;
    var verified = false;
    final api = FakeApi({
      'GET /api/v1/rag/admin/feedback/clusters': (_) =>
          feedbackPage([feedbackCluster('c1', verified: verified ? {'qa_id': 5, 'enabled': true, 'version': 1} : null)]),
      'POST /api/v1/rag/admin/feedback/clusters/c1/verify': (o) {
        posted = o.data;
        verified = true;
        return {'id': 5, 'created': true, 'cache_purged': 4};
      },
    }, latency: const Duration(milliseconds: 5))
      ..install();
    addTearDown(api.uninstall);
    await ApiClient().primeSession();

    await tester.pumpWidget(ThemeConfigScope(
        provider: ThemeConfigProvider(api: ApiClient()),
        child: MaterialApp(navigatorKey: navigatorKey, home: Scaffold(body: FeedbackReviewBody(api: FeedbackReviewApi())))));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('How do I change my password?'), findsOneWidget);
    expect(find.text('Write the verified answer'), findsOneWidget);
    expect(find.text('Verified'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('verify_c1')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // prefilled with the answer that was shown
    expect(find.widgetWithText(TextField, 'Open Settings, then Security.'), findsOneWidget);
    expect(find.byKey(const ValueKey('variant_change pwd')), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Open Settings, then Security.'), 'Settings > Security > Change password.');
    await tester.ensureVisible(find.text('Save and verify'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Save and verify'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(posted, isA<Map>());
    final body = posted as Map;
    expect(body['answer'], 'Settings > Security > Change password.');
    expect(body['question'], 'How do I change my password?');
    expect(body['variants'], ['forgot password how to reset', 'change pwd']);
    expect(body['enabled'], true);
    expect(body['citations'], isNotEmpty);
    expect(find.textContaining('4 cached answers were cleared'), findsOneWidget);
    // the list reloaded: the cluster now wears the badge
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Edit the verified answer'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('an empty answer is refused in the editor', (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final k = FeedbackCluster.fromJson(feedbackCluster('c1')..['answer'] = null);
    await tester.pumpWidget(layoutHost(Builder(builder: (c) => TextButton(onPressed: () => showModalBottomSheet<void>(context: c, builder: (_) => VerifyAnswerSheet(cluster: k)), child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('Save and verify'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Save and verify'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Write the verified answer'), findsWidgets);
  });
}
