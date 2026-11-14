// The Super Admin's per-organization RAG library quota (PUT /api/v1/rag/orgs/{id}/quota, A04): the body follows
// the server's contract — both keys always sent, null = platform default, 0 = unlimited, bytes from MB — and the sheet
// loads, saves and degrades when the route is missing.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';
import 'package:flutter_education_app/features/exams/exam_review.dart' show flagText;
import 'package:flutter_education_app/features/rag/rag_library.dart';
import 'package:flutter_education_app/features/rag/rag_quota_admin.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

const _mib = 1024 * 1024;

class _FakeRag implements RagLibraryApi {
  _FakeRag(this.get, [this.put]);
  EngineResult get;
  EngineResult? put;
  final saved = <Map<String, dynamic>>[];

  @override
  Future<EngineResult> quota(int orgId) async => get;

  @override
  Future<EngineResult> saveQuota(int orgId, Map<String, dynamic> body) async {
    saved.add(body);
    return put ?? EngineResult.ok({...get.map, 'override': body});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Map<String, dynamic> _quota({Object? oDocs, Object? oBytes, Object? maxDocs = 200, Object? maxBytes = 500 * _mib}) =>
    {'org_id': 7, 'docs': 12, 'bytes': 40 * _mib, 'max_docs': maxDocs, 'max_bytes': maxBytes, 'override': {'max_docs': oDocs, 'max_bytes': oBytes}};

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('override draft', () {
    test('reads the override: null = platform default, 0 = unlimited, a number = its own limit', () {
      final d = RagQuotaOverrideDraft.fromOverride({'max_docs': null, 'max_bytes': 0});
      expect(d.docsMode, RagLimitMode.platform);
      expect(d.bytesMode, RagLimitMode.unlimited);
      final c = RagQuotaOverrideDraft.fromOverride({'max_docs': 300, 'max_bytes': 1536 * _mib});
      expect(c.docsMode, RagLimitMode.custom);
      expect(c.docs, '300');
      expect(c.bytesMode, RagLimitMode.custom);
      expect(c.mb, '1536');
      expect(RagQuotaOverrideDraft.fromOverride(null).body(), {'max_docs': null, 'max_bytes': null});
    });

    test('the PUT body always carries both keys (the PUT replaces both)', () {
      expect(RagQuotaOverrideDraft().body(), {'max_docs': null, 'max_bytes': null});
      expect(RagQuotaOverrideDraft(docsMode: RagLimitMode.unlimited, bytesMode: RagLimitMode.unlimited).body(), {'max_docs': 0, 'max_bytes': 0});
      final d = RagQuotaOverrideDraft(docsMode: RagLimitMode.custom, docs: '1,000', bytesMode: RagLimitMode.custom, mb: '2.5');
      expect(d.validate(), isNull);
      expect(d.body(), {'max_docs': 1000, 'max_bytes': (2.5 * _mib).round()});
      expect(RagQuotaOverrideDraft(docsMode: RagLimitMode.custom, docs: '٢٠').body()['max_docs'], 20);
    });

    test('a limit of its own must be a positive number within the server bounds', () {
      for (final v in ['', '0', '-1', '2.5', 'abc', '10000001']) {
        expect(RagQuotaOverrideDraft(docsMode: RagLimitMode.custom, docs: v).validate(), 'bad_docs', reason: v);
      }
      for (final v in ['', '0', '-3', 'x', '12,5']) {
        expect(RagQuotaOverrideDraft(bytesMode: RagLimitMode.custom, mb: v).validate(), 'bad_size', reason: v);
      }
      expect(RagQuotaOverrideDraft(bytesMode: RagLimitMode.custom, mb: '0.5').validate(), isNull);
      // a value typed for a mode that is not "its own" is ignored
      expect(RagQuotaOverrideDraft(docsMode: RagLimitMode.platform, docs: 'junk').validate(), isNull);
      expect(ragQuotaDraftErrorText('bad_docs'), isNot(ragQuotaDraftErrorText('bad_size')));
      AppConfig.lang = 'ar';
      expect(ragLimitModeText(RagLimitMode.unlimited), 'بلا حد');
    });
  });

  group('sheet', () {
    testWidgets('loads usage, saves a new override and shows what the server stored', (t) async {
      final api = _FakeRag(EngineResult.ok(_quota(oDocs: 300)));
      await t.pumpWidget(layoutHost(RagQuotaAdminSheet(orgId: 7, orgName: 'Uni', api: api), scale: 1));
      await t.pumpAndSettle();
      expect(find.textContaining('12 / 200 documents'), findsOneWidget);
      expect(find.text('300'), findsOneWidget);           // the custom docs field
      await t.enterText(find.byType(TextField).first, '450');
      await t.tap(find.text('Save'));
      await t.pump();
      expect(api.saved.single, {'max_docs': 450, 'max_bytes': null});
      await t.pump(const Duration(seconds: 4));             // the toast
    });

    testWidgets('a refused save shows the server code as text; a missing route says the server needs an update', (t) async {
      final api = _FakeRag(EngineResult.ok(_quota()), EngineResult.fail(403, 'super_admin_required', 'x'));
      await t.pumpWidget(layoutHost(RagQuotaAdminSheet(orgId: 7, api: api), scale: 1));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text(ragLibraryCodeText('super_admin_required', '')), findsOneWidget);

      final missing = _FakeRag(EngineResult.fail(404, null, 'Not Found'));
      await t.pumpWidget(layoutHost(RagQuotaAdminSheet(key: const ValueKey('missing'), orgId: 7, api: missing), scale: 1));
      await t.pumpAndSettle();
      expect(find.textContaining('needs a server update'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('layout: form in every mode, loaded sheet, error sheet', (t) async {
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
              child: RagQuotaOverrideForm(
                  initial: RagQuotaOverrideDraft(docsMode: RagLimitMode.custom, docs: '10000000', bytesMode: RagLimitMode.custom, mb: '953674316.43'),
                  onSave: (_) {})));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: RagQuotaOverrideForm(initial: RagQuotaOverrideDraft(), busy: true, onSave: (_) {})));
      await expectNoLayoutErrors(
          t, () => RagQuotaAdminSheet(orgId: 7, orgName: 'A university with a really long name for a phone', api: _FakeRag(EngineResult.ok(_quota(oDocs: 0, oBytes: 3 * _mib)))));
      await expectNoLayoutErrors(t, () => RagQuotaAdminSheet(orgId: 7, api: _FakeRag(EngineResult.fail(0, null, 'network down'))));
    });
  });

  test('grading flag labels: role_swap and llm_disagrees have text in both languages', () {
    expect(flagText('role_swap'), 'Roles swapped between concepts');
    expect(flagText('llm_disagrees'), isNot('llm_disagrees'));
    AppConfig.lang = 'ar';
    expect(flagText('role_swap'), 'تبديل الأدوار بين المفاهيم');
    expect(flagText('unknown_flag'), 'unknown_flag');
  });
}
