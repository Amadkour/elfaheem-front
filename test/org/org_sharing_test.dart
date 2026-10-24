// Phase 3 — cross-organization sharing: the pure logic (draft bodies, identifier parsing, result summary) and the
// presentational widgets on every screen size and language.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/org_sharing.dart';
import 'package:flutter_education_app/features/org/org_sharing_pages.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

final share = <String, dynamic>{
  'id': 7,
  'resource_type': 'department',
  'resource_id': 3,
  'title': 'Student affairs — exchange desk',
  'methods': ['request', 'invite'],
  'scope': <String, dynamic>{},
  'status': 'active',
  'state': 'active',
  'expires_at': '2099-01-01T00:00:00',
  'max_grantees': 5,
  'code_hint': 'K7Q',
  'has_code': true,
  'grants': 2,
  'pending': 1,
  'resource': {'type': 'department', 'id': 3, 'name_ar': 'شؤون الطلاب', 'name_en': 'Student affairs'},
};

final gradShare = <String, dynamic>{
  'id': 8, 'resource_type': 'graduates', 'resource_id': null, 'title': 'Graduate verification', 'methods': ['auto'],
  'scope': {'year': true}, 'status': 'active', 'state': 'active', 'grants': 0, 'pending': 0,
  'grantor': {'id': 1, 'name_ar': 'جامعة القاهرة', 'name_en': 'Cairo University', 'type': 'university'},
};

final grant = <String, dynamic>{
  'id': 11, 'share_id': 7, 'org_id': 1, 'grantee_org_id': 2, 'status': 'pending', 'state': 'pending', 'via': 'request',
  'note': 'Exchange programme 2026', 'share': share, 'grantee': {'id': 2, 'name_ar': 'جامعة الإسكندرية', 'name_en': 'Alexandria University'},
};

final verifyResult = <String, dynamic>{
  'count': 3, 'matched': 1, 'year_included': true,
  'results': [
    {'ref': '1', 'graduate': true, 'year': 2024},
    {'ref': '2', 'graduate': false, 'year': null},
    {'ref': '3', 'graduate': null, 'error': 'no_identifier'},
  ],
};

void main() {
  setUp(() => AppConfig.lang = 'ar');

  test('share dates: naive UTC from the server, end of the chosen day for expiry', () {
    final d = ShareDraft.fromShare({'resource_type': 'department', 'methods': ['invite'], 'scope': {}, 'expires_at': '2026-11-01T21:59:59'});
    expect(d.expiresAt!.toUtc(), DateTime.utc(2026, 11, 1, 21, 59, 59));
    expect(shareExpiryInstant(DateTime(2026, 11, 1)), DateTime(2026, 11, 1, 23, 59, 59));
    expect(shareExpiryInstant(DateTime(2026, 11, 1, 10, 30)), DateTime(2026, 11, 1, 10, 30));
    expect(shareExpiryInstant(null), isNull);
    final a = ShareDraft()..methods.addAll(['invite', 'request']);
    final b = ShareDraft()..methods.addAll(['request', 'invite']);
    expect(a.patch(b.toBody()..['resource_type'] = 'department'), isNot(contains('methods')));
  });

  test('share draft: body, validation, patch of changed fields only', () {
    final d = ShareDraft(resourceType: 'department', resourceId: 3, methods: {'invite', 'request'}, title: ' Desk ');
    expect(d.validate(), isNull);
    final body = d.toBody();
    expect(body['resource_type'], 'department');
    expect(body['resource_id'], 3);
    expect(body['title'], 'Desk');
    expect(body['methods'], ['invite', 'request']); // server order, whatever the set order
    expect(body['scope'], <String, dynamic>{});

    final g = ShareDraft(resourceType: 'graduates', methods: {'auto'}, year: true);
    expect(g.toBody().containsKey('resource_id'), isFalse);
    expect(g.toBody()['scope'], {'year': true});
    expect(g.validate(), isNull);

    expect(ShareDraft(resourceType: 'course', methods: {'auto'}).validate(), isNotNull, reason: 'a course needs a resource');
    expect(ShareDraft(resourceType: 'graduates', methods: {}).validate(), isNotNull, reason: 'at least one method');
    final past = ShareDraft(resourceType: 'graduates', methods: {'auto'}, expiresAt: DateTime(2000));
    expect(past.validate(), isNotNull);

    final fromServer = ShareDraft.fromShare(share);
    expect(fromServer.methods, {'request', 'invite'});
    expect(fromServer.maxGrantees, 5);
    fromServer.methods.add('public');
    fromServer.title = 'Student affairs — exchange desk';   // unchanged
    final patch = fromServer.patch(share);
    expect(patch.keys.toList(), ['methods']);
    expect(patch['methods'], ['invite', 'request', 'public']);
    for (final lang in ['ar', 'en']) {
      AppConfig.lang = lang;
      expect(shareTitleOf({'resource_type': 'department', 'resource': {'name_ar': 'شؤون', 'name_en': 'Affairs'}}), lang == 'ar' ? 'شؤون' : 'Affairs');
      expect(shareTitleOf({'resource_type': 'graduates'}), shareResourceLabel('graduates'));
      expect(shareMethodLabel('public'), isNot('public'));
      expect(grantStateText('share_revoked'), isNot('share_revoked'));
    }
  });

  test('identifier parsing and verification summary', () {
    final qs = parseIdentifiers('Grad@X.io\n+20 100 123 4567, S-100;\n\n01001234567');
    expect(qs.length, 4);
    expect(qs[0], {'ref': '1', 'email': 'grad@x.io'});
    expect(qs[1], {'ref': '2', 'phone': '+20 100 123 4567'});
    expect(qs[2], {'ref': '3', 'student_code': 'S-100'});
    expect(qs[3], {'ref': '4', 'phone': '01001234567'});
    expect(parseIdentifiers('   '), isEmpty);
    expect(verificationSummary(verifyResult), (1, 1, 1));
    AppConfig.lang = 'en';
    expect(verificationLine({'graduate': true, 'year': 2024}, yearIncluded: true), 'Graduate — 2024');
    expect(verificationLine({'graduate': true, 'year': 2024}, yearIncluded: false), 'Graduate');
    expect(verificationLine({'graduate': false}, yearIncluded: true), 'Not a graduate');
    expect(verificationLine({'graduate': null}, yearIncluded: true), 'No identifier');
  });

  testWidgets('share, grant and result widgets lay out everywhere', (tester) async {
    await expectNoLayoutErrors(tester, () => ListView(children: [
          ShareCard(share: share, onTap: () {}),
          ShareCard(share: gradShare, grantorName: 'Cairo University'),
          GrantCard(grant: grant, actions: [TextButton(onPressed: () {}, child: const Text('Reject')), FilledButton(onPressed: () {}, child: const Text('Approve'))]),
          GrantCard(grant: {...grant, 'grantee': null, 'state': 'active', 'share': gradShare}),
          VerifyResultsList(result: verifyResult, labels: const {'1': 'grad@x.io', '2': 'nongrad@x.io'}),
        ]));
  });

  testWidgets('share form lays out for a resource and for graduates', (tester) async {
    final d1 = ShareDraft(resourceType: 'department', methods: {'request'});
    final d2 = ShareDraft(resourceType: 'graduates', methods: {'auto', 'invite'}, year: true, expiresAt: DateTime(2030, 1, 1));
    final title = TextEditingController(), desc = TextEditingController(), max = TextEditingController();
    await expectNoLayoutErrors(tester, () => ListView(children: [
          ShareFormBody(
            draft: d1,
            resources: const [{'id': 3, 'name_ar': 'شؤون الطلاب', 'name_en': 'Student affairs'}, {'id': 4, 'name_ar': 'المكتبة', 'name_en': 'Library'}],
            onChanged: () {},
            titleController: title,
            descriptionController: desc,
            maxController: max,
          ),
          ShareFormBody(draft: d2, resources: const [], editing: true, onChanged: () {}),
        ]));
  });
}
