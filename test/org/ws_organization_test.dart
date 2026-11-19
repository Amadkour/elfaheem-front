// The admin workspace's Organization tab (D-1180, lib/features/org/workspace/ws_organization.dart): the identity
// card's pure helpers (brand colour, status, official details in order, empty ones left out), the card under the
// layout harness (320 / 1400, ar / en, text 1.3) with a long name, every detail and the "add" prompts, and Edit
// details only when the person may edit.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/workspace/ws_organization.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('brand colour: a #RRGGBB hex, anything else is none', () {
    expect(orgBrandColor('#1F6F5C'), const Color(0xFF1F6F5C));
    expect(orgBrandColor('1F6F5C'), isNull);
    expect(orgBrandColor(null), isNull);
    expect(orgBrandColor('#12345'), isNull);
  });

  test('status: only what needs saying', () {
    expect(orgStatusLabel('approved'), '');
    expect(orgStatusLabel(null), '');
    expect(orgStatusLabel('pending'), isNotEmpty);
    expect(orgStatusLabel('suspended'), isNotEmpty);
  });

  test('details: reading order, blanks left out', () {
    final d = orgDetailsOf({
      'contact_email': ' office@uni.edu ',
      'contact_phone': '',
      'website': 'https://uni.edu',
      'address': null,
      'license_no': '42/2026',
    });
    expect(d.map((e) => e.$1), [Icons.mail_outline_rounded, Icons.language_rounded, Icons.verified_outlined]);
    expect(d.first.$2, 'office@uni.edu');
    expect(d.last.$2, endsWith('42/2026'));
    expect(orgDetailsOf(null), isEmpty);
  });

  testWidgets('Edit details only for someone who may edit', (tester) async {
    var edits = 0;
    await tester.pumpWidget(layoutHost(OrgIdentityCard(name: 'Uni', onEdit: () => edits++)));
    expect(find.byKey(const ValueKey('org.identity.edit')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('org.identity.edit')));
    expect(edits, 1);
    await tester.pumpWidget(layoutHost(const OrgIdentityCard(name: 'Uni')));
    expect(find.byKey(const ValueKey('org.identity.edit')), findsNothing);
  });

  testWidgets('identity card: no overflow with a long name, every detail and the prompts', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
          child: OrgIdentityCard(
            name: 'كلية الدراسات العليا للعلوم الإنسانية والاجتماعية والتربوية بجامعة القاهرة',
            type: 'University',
            status: orgStatusLabel('pending'),
            color: orgBrandColor('#EA580C'),
            details: orgDetailsOf({
              'contact_email': 'graduate.studies.office@very-long-university-domain.edu.eg',
              'contact_phone': '+20 100 000 0000',
              'website': 'https://www.very-long-university-domain.edu.eg/graduate-studies',
              'address': 'شارع الجامعة، الجيزة، جمهورية مصر العربية، بجوار البوابة الرئيسية',
              'license_no': '1234/2026',
            }),
            onEdit: () {},
          ),
        ));
  });
}
