// The RAG chat follows the organization's status (Phase 10, A04): 403 orgs_disabled, 423 org_not_approved {status},
// 403 org_inactive get their own bilingual text in the chat, never the raw server message.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult;
import 'package:flutter_education_app/features/shared/rag/rag_chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppConfig.lang = 'ar');

  const raw = 'server raw text';

  test('the three organization codes have their own text in both languages', () {
    for (final code in ['orgs_disabled', 'org_not_approved', 'org_inactive']) {
      for (final lang in ['ar', 'en']) {
        AppConfig.lang = lang;
        final s = ragCodeText(code, raw);
        expect(s, isNot(raw), reason: '$code/$lang');
        expect(s, isNotEmpty);
      }
    }
    AppConfig.lang = 'ar';
    final ar = ragCodeText('org_inactive', raw);
    AppConfig.lang = 'en';
    expect(ragCodeText('org_inactive', raw), isNot(ar), reason: 'English text differs from the Arabic one');
    expect(ragCodeText('orgs_disabled', raw), contains('switched off'));
    expect(ragCodeText('org_inactive', raw), contains('deactivated'));
  });

  test('a 423 carries the org status: suspended, pending and rejected read differently', () {
    AppConfig.lang = 'en';
    String text(String status) =>
        ragChatResultText(EngineResult.fail(423, 'org_not_approved', raw, {'code': 'org_not_approved', 'status': status}));
    expect(text('suspended'), contains('suspended'));
    expect(text('pending'), contains('review'));
    expect(text('rejected'), contains('not approved'));
    expect({text('suspended'), text('pending'), text('rejected'), text('')}.length, 4);
  });

  test('other failures keep the existing texts and fall back to the server message', () {
    expect(ragChatResultText(EngineResult.fail(429, 'too_many_requests', raw)), ragCodeText('too_many_requests', raw));
    expect(ragChatResultText(EngineResult.fail(500, null, raw)), raw);
    expect(ragChatResultText(EngineResult.fail(403, 'orgs_disabled', raw)), ragCodeText('orgs_disabled', raw));
  });

  test('ragOrgBlocked names exactly the organization codes', () {
    expect(['orgs_disabled', 'org_not_approved', 'org_inactive'].every(ragOrgBlocked), isTrue);
    expect(ragOrgBlocked('not_a_member'), isFalse);
    expect(ragOrgBlocked('rag_quota_exceeded'), isFalse);
    expect(ragOrgBlocked(null), isFalse);
  });
}
