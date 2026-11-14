// Layout smoke for the curated Q&A screen (lib/features/rag/rag_qa_admin.dart): the list row, the stats
// header, the edit form (as the sheet shows it) and the whole body with data / empty, at 320x640 and 1400x900,
// Arabic and English, textScaler 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';
import 'package:flutter_education_app/features/rag/rag_admin_console.dart';
import 'package:flutter_education_app/features/rag/rag_qa_admin.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _longAr = 'كيف أحمّل محاضرة مسجلة كاملة لمشاهدتها لاحقاً بلا اتصال بالإنترنت من داخل التطبيق على هاتفي أو جهازي اللوحي؟';
const _longEn = 'How do I download a whole recorded lecture so that I can watch it later without an internet connection on my phone or tablet?';

QaPair _pair({bool stale = false, bool enabled = true, int used = 12, String? link}) => QaPair(
      id: 1,
      question: _longAr,
      variants: [_longEn, 'تنزيل محاضرة', 'download lecture offline', 'offline viewing', 'save lecture'],
      answer: 'افتح المحاضرة ثم اضغط «تنزيل».\n- تُحفظ مشفّرة على الجهاز\n- تجدها في «التنزيلات»\n1. افتح\n2. اضغط\n**ملاحظة**: $_longEn',
      lang: 'mixed',
      deepLink: link,
      enabled: enabled,
      usageCount: used,
      lastUsedAt: used > 0 ? DateTime.now().toUtc().subtract(const Duration(hours: 3)).toIso8601String() : null,
      stale: stale,
    );

class _StubQa implements QaApi {
  _StubQa(this.items);
  final List<QaPair> items;

  @override
  Future<EngineResult> list({required String scope, int? orgId}) async => EngineResult.ok({
        'items': [for (final p in items) {...p.toJson(create: true), 'id': p.id, 'usage_count': p.usageCount, 'last_used_at': p.lastUsedAt, 'stale': p.stale}],
        'scope': scope,
        'org_id': orgId,
        'manager': true,
        'embedder': 'multilingual-e5-small@int8',
        'usage': {'pairs': items.length, 'enabled': items.where((p) => p.enabled).length, 'direct': 1234},
      });

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets('a pair row: long texts, every pill, stale, deep link, disabled, working', (tester) async {
    await expectNoLayoutErrors(tester, () => ListView(padding: const EdgeInsets.all(16), children: [
          QaPairCard(pair: _pair(stale: true, link: 'profile.downloads'), onEdit: () {}, onToggle: () {}, onDelete: () {}),
          QaPairCard(pair: _pair(enabled: false, used: 0), working: true, onEdit: () {}, onToggle: () {}, onDelete: () {}),
          QaPairCard(pair: const QaPair(id: 2, question: 'q', answer: 'a')),
        ]));
  });

  testWidgets('the stats header with and without the stale banner', (tester) async {
    await expectNoLayoutErrors(tester, () => ListView(padding: const EdgeInsets.all(16), children: const [
          QaStatsHeader(scope: 'app', pairs: 1234, enabled: 1200, direct: 98765, stale: 7, embedder: 'multilingual-e5-small@int8'),
          SizedBox(height: 12),
          QaStatsHeader(scope: 'org', pairs: 0, enabled: 0, direct: 0),
        ]));
  });

  testWidgets('the edit form as the sheet shows it: a draft with many variants, an error banner, busy', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            QaPairForm(pair: _pair(link: '/downloads'), error: 'The deep link is not valid: a feature key or a route starting with /', onSave: (_) {}),
            const Divider(height: 32),
            QaPairForm(pair: const QaPair(scope: 'org', orgId: 4), busy: true, onSave: (_) {}),
          ]),
        ));
  });

  testWidgets('the sheet itself (as showAppSheet presents it)', (tester) async {
    await expectNoLayoutErrors(tester, () => QaPairSheet(draft: _pair(), api: _StubQa(const [])));
  });

  testWidgets('the whole body: loaded with rows, then empty', (tester) async {
    await expectNoLayoutErrors(tester, () => RagQaAdminBody(scope: 'app', api: _StubQa([_pair(stale: true), _pair(enabled: false)])), frames: 5);
    await expectNoLayoutErrors(tester, () => RagQaAdminBody(scope: 'org', orgId: 4, api: _StubQa(const [])), frames: 5);
  });

  testWidgets('the overview rows with the promote action', (tester) async {
    await expectNoLayoutErrors(tester, () => RagOverviewView(
          overview: RagOverview.fromJson({
            'qa': {'pairs': 3, 'enabled': 3, 'direct': 40, 'example': 2},
            'not_found': [for (var i = 0; i < 3; i++) {'question': _longAr, 'count': 12, 'context': 'app', 'query_id': i + 1}],
            'unhelpful': [{'question': _longEn, 'answer': _longAr, 'comment': 'wrong lecture', 'query_id': 9}],
          }),
          onPromote: (_) {},
        ));
  });
}
