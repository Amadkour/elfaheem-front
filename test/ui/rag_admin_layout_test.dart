// Layout harness (320x640 and 1400x900, ar/en, textScaler 1.3) for the RAG admin additions.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/rag/admin/rag_cache_card.dart';
import 'package:flutter_education_app/features/shared/rag/admin/rag_console_settings.dart';
import 'package:flutter_education_app/features/shared/rag/admin/rag_feedback_review.dart';
import 'package:flutter_education_app/features/shared/rag/rag_admin_console.dart';
import 'package:flutter_education_app/features/shared/rag/rag_learning.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/rag_admin_fixtures.dart';
import 'layout_harness.dart';

Widget _scroll(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

void main() {
  final page = FeedbackPage.fromJson(feedbackPage([
    feedbackCluster('c1', verified: {'qa_id': 5, 'enabled': true, 'version': 2}),
    feedbackCluster('c2', scope: 'org', dislikes: 1),
  ], total: 40));

  testWidgets('feedback review list (admin, with the organization filter)', (tester) async {
    await expectNoLayoutErrors(tester, () => _scroll(FeedbackReviewList(page: page, days: 30, minDislikes: 1, showOrg: true, onFilters: (_, _) {}, onVerify: (_) {}, onMore: () {})));
  });

  testWidgets('feedback review list: empty', (tester) async {
    await expectNoLayoutErrors(tester, () => _scroll(FeedbackReviewList(page: const FeedbackPage(), days: 7, minDislikes: 3, onFilters: (_, _) {})));
  });

  testWidgets('a cluster card with a very long question and answer', (tester) async {
    final long = feedbackCluster('c3')
      ..['question'] = 'ازاي اغير كلمة السر بتاعتي لو نسيت البريد الإلكتروني اللي سجلت بيه ' * 4
      ..['comments'] = [
        {'text': 'تعليق طويل جداً ' * 20},
      ];
    await expectNoLayoutErrors(tester, () => _scroll(FeedbackClusterCard(cluster: FeedbackCluster.fromJson(long), onVerify: () {})));
  });

  testWidgets('the verified-answer editor sheet', (tester) async {
    await expectNoLayoutErrors(tester, () => _scroll(VerifyAnswerSheet(cluster: page.items.first)));
  });

  testWidgets('the cache card', (tester) async {
    await expectNoLayoutErrors(tester, () => _scroll(RagCacheCard(stats: RagCacheStats.fromJson(cacheStatsJson()), onSave: (_) {}, onClearAll: () {}, onClearOrg: (_) {})));
  });

  testWidgets('the cache card with the env switch off and many organizations', (tester) async {
    final j = cacheStatsJson()
      ..['env_enabled'] = false
      ..['per_org'] = [for (var i = 1; i < 12; i++) {'org_id': i * 1000, 'entries': i * 100, 'bytes': i * 100000, 'hits': i}];
    await expectNoLayoutErrors(tester, () => _scroll(RagCacheCard(stats: RagCacheStats.fromJson(j), onSave: (_) {}, onClearAll: () {}, onClearOrg: (_) {})));
  });

  testWidgets('the D-190 settings card', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => _scroll(RagExtraSettingsCard(
            settings: const RagExtraSettings(present: true, ocrScanned: true, answerMode: 'retrieval'),
            onSave: (_) {},
            onTrain: () {},
            job: const EmbedderJob(state: 'running', detail: 'epoch 2 of 4 with a long detail text that should wrap'))));
  });

  testWidgets('the platform settings form with the Manage models link', (tester) async {
    await expectNoLayoutErrors(tester, () => _scroll(RagPlatformSettingsForm(settings: const RagAdminSettings(), onSave: (_) {}, onManageModels: () {})));
  });
}
