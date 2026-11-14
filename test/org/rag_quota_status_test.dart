// Phase 10: the RAG library quota (usage, 409 rag_quota_exceeded) and the organization-status codes the exam engine
// and the RAG service answer like the core (403 orgs_disabled · 423 org_not_approved {status} · 403 org_inactive).
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';
import 'package:flutter_education_app/features/exams/exam_taking.dart' show examCodeText;
import 'package:flutter_education_app/features/shared/rag/rag_library.dart';
import 'package:flutter_education_app/features/shared/rag/rag_library_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('quota parsing', () {
    test('usage with limits: "12 / 200 documents", bytes against the cap, fill of the tighter limit', () {
      final q = RagQuota.fromJson({'docs': 12, 'bytes': 1024 * 1024, 'max_docs': 200, 'max_bytes': 2 * 1024 * 1024, 'override': {}})!;
      expect(q.docsText, '12 / 200 documents');
      expect(q.bytesText, '1.0 MB / 2.0 MB');
      expect(q.limited, isTrue);
      expect(q.fill, closeTo(0.5, 1e-9));
      expect(q.full, isFalse);
      expect(q.nearlyFull, isFalse);
      AppConfig.lang = 'ar';
      expect(q.docsText, '12 / 200 مستند');
    });

    test('null / zero limits are unlimited; no quota object means the server sent none', () {
      final q = RagQuota.fromJson({'docs': 3, 'bytes': 500, 'max_docs': null, 'max_bytes': 0})!;
      expect(q.limited, isFalse);
      expect(q.fill, isNull);
      expect(q.full, isFalse);
      expect(q.docsText, '3 documents');
      expect(q.bytesText, '500 B');
      expect(RagQuota.fromJson(null), isNull);
      expect(RagQuota.fromJson('x'), isNull);
    });

    test('full and nearly full', () {
      expect(RagQuota.fromJson({'docs': 200, 'bytes': 0, 'max_docs': 200})!.full, isTrue);
      expect(RagQuota.fromJson({'docs': 181, 'bytes': 0, 'max_docs': 200})!.nearlyFull, isTrue);
      expect(RagQuota.fromJson({'docs': 1, 'bytes': 95, 'max_docs': 200, 'max_bytes': 100})!.nearlyFull, isTrue);
      expect(RagQuota.fromJson({'docs': 250, 'bytes': 0, 'max_docs': 200})!.fill, 1.0);
    });

    test('the library list carries the quota for managers only when the server sends it', () {
      expect(RagLibrary.fromJson({'items': [], 'manager': true, 'quota': {'docs': 2, 'bytes': 10, 'max_docs': 5}}).quota!.maxDocs, 5);
      expect(RagLibrary.fromJson({'items': [], 'manager': false}).quota, isNull);
    });
  });

  group('codes → text', () {
    test('rag_quota_exceeded names the limit and the usage', () {
      final docs = EngineResult.fail(409, 'rag_quota_exceeded', 'امتلأت', {
        'code': 'rag_quota_exceeded', 'limit': 'docs', 'quota': {'docs': 200, 'bytes': 9, 'max_docs': 200}
      });
      expect(ragResultText(docs), contains('200 / 200 documents'));
      final bytes = EngineResult.fail(409, 'rag_quota_exceeded', 'x', {
        'limit': 'bytes', 'quota': {'docs': 3, 'bytes': 1024 * 1024, 'max_bytes': 2 * 1024 * 1024}
      });
      expect(ragResultText(bytes), contains('1.0 MB / 2.0 MB'));
      expect(ragResultText(EngineResult.fail(409, 'rag_quota_exceeded', 'x')), contains('library is full'));
      AppConfig.lang = 'ar';
      expect(ragResultText(docs), contains('امتلأت المكتبة'));
    });

    test('organization status in the library: by status, and the switch-off / deactivated codes', () {
      expect(ragResultText(EngineResult.fail(423, 'org_not_approved', 'x', {'status': 'suspended'})), contains('suspended'));
      expect(ragResultText(EngineResult.fail(423, 'org_not_approved', 'x', {'status': 'pending'})), contains('under review'));
      expect(ragResultText(EngineResult.fail(423, 'org_not_approved', 'x', {'status': 'rejected'})), contains('not approved'));
      expect(ragResultText(EngineResult.fail(423, 'org_not_approved', 'x')), contains('not active'));
      expect(ragLibraryCodeText('orgs_disabled', 'x'), contains('Organizations are currently unavailable'));
      expect(ragLibraryCodeText('org_inactive', 'x'), contains('deactivated'));
      expect(ragLibraryCodeText('super_admin_required', 'x'), contains('Super Admin'));
      AppConfig.lang = 'ar';
      expect(ragResultText(EngineResult.fail(423, 'org_not_approved', 'x', {'status': 'suspended'})), contains('موقوفة'));
      expect(ragLibraryCodeText('orgs_disabled', 'x'), contains('غير متاحة'));
    });

    test('exam engine: the same organization codes in both languages', () {
      for (final code in ['orgs_disabled', 'org_not_approved', 'org_inactive']) {
        AppConfig.lang = 'en';
        final en = examCodeText(code);
        AppConfig.lang = 'ar';
        final ar = examCodeText(code);
        expect(en, isNot(code), reason: code);
        expect(ar, isNot(code), reason: code);
        expect(ar, isNot(en), reason: code);
      }
    });
  });

  group('layout', () {
    testWidgets('RagQuotaBar: limited, nearly full, full and unlimited — no overflow', (tester) async {
      for (final q in [
        const RagQuota(docs: 12, bytes: 40 * 1024 * 1024, maxDocs: 200, maxBytes: 500 * 1024 * 1024),
        const RagQuota(docs: 190, bytes: 10, maxDocs: 200),
        const RagQuota(docs: 200000, bytes: 999 * 1024 * 1024 * 1024, maxDocs: 200000, maxBytes: 999 * 1024 * 1024 * 1024),
        const RagQuota(docs: 7, bytes: 1234),
      ]) {
        await expectNoLayoutErrors(tester, () => RagQuotaBar(quota: q));
      }
    });
  });
}
