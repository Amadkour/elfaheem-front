// The Privacy policy and the Terms of service (D-308): the legal document's parser, and every new part (At a glance,
// the closing actions, the auth links row, the admin's document card, the sign-up row with the privacy link, the
// auth page with its footer) at 320x640 and 1400x900, Arabic and English, text 1.3, with no overflow.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/routing/app_routes.dart';
import 'package:flutter_education_app/features/admin/admin_legal_page.dart' show LegalDocCard;
import 'package:flutter_education_app/features/auth/auth_shell.dart';
import 'package:flutter_education_app/features/auth/register_screen.dart' show AuthTermsRow;
import 'package:flutter_education_app/features/profile/legal/legal_links.dart';
import 'package:flutter_education_app/features/profile/about/about_terms_model.dart';
import 'package:flutter_education_app/features/profile/about/about_terms_parts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'لا نبيع بياناتك أبدًا ولا نستخدمها للإعلانات الموجهة، ويمكنك حذف حسابك في أي وقت. '
    'We never sell your data, and you can delete your account at any time.';

void main() {
  group('TermsPageModel.fromLegal', () {
    test('a legal document in one language', () {
      final m = TermsPageModel.fromLegal({
        'doc': 'privacy',
        'version': '2.0',
        'effective_date': '2026-11-08',
        'effective_label': '8 November 2026',
        'title': 'Privacy Policy',
        'intro': 'Intro',
        'highlights': ['One', ' ', 'Two'],
        'sections': [
          {'id': 'who', 'icon_name': 'info', 'title': 'Who we are', 'body': 'Body'},
          {'id': 'empty', 'icon_name': 'info', 'title': '', 'body': ''},
          {'id': 'google', 'icon_name': 'verified', 'title': 'Google user data', 'body': '- drive.file'},
        ],
        'contact_email': 'alfaheem.2y@gmail.com',
        'url': 'https://alfheemacademy.com/en/privacy/',
      });
      expect(m.title, 'Privacy Policy');
      expect(m.highlights, ['One', 'Two']);
      expect([for (final s in m.sections) s.title], ['Who we are', 'Google user data'], reason: 'an empty section is dropped');
      expect([for (final s in m.sections) s.id], [1, 2]);
      expect(m.sections.last.iconName, 'verified');
      expect(m.meta!.lastUpdated, '8 November 2026');
      expect(m.meta!.version, '2.0');
      expect(m.contactEmail, 'alfaheem.2y@gmail.com');
      expect(m.url, 'https://alfheemacademy.com/en/privacy/');
    });

    test('missing fields never throw', () {
      final m = TermsPageModel.fromLegal(const {});
      expect(m.sections, isEmpty);
      expect(m.meta, isNull);
      expect(m.highlights, isEmpty);
    });
  });

  test('the two pages are public routes', () {
    expect(AppRoutes.match('/privacy')!.id, 'legal.privacy');
    expect(AppRoutes.match('/terms')!.id, 'legal.terms');
    expect(AppRoutes.privacy.signIn, isFalse);
    expect(AppRoutes.terms.signIn, isFalse);
    expect(kPrivacyRoute, '/privacy');
    expect(kTermsRoute, '/terms');
  });

  testWidgets('the legal parts never overflow', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const ReadingHighlights(title: 'باختصار At a glance', items: [_long, 'Short', _long]),
          const SizedBox(height: 16),
          ReadingLegalActions(
            otherLabel: 'شروط الاستخدام Terms of service',
            otherIcon: Icons.gavel_rounded,
            onOther: () {},
            email: 'alfaheem.2y@gmail.com',
            onEmail: () {},
            onCopyLink: () {},
          ),
          ReadingLegalActions(otherLabel: 'Privacy', otherIcon: Icons.privacy_tip_outlined, onOther: () {}),
          const SizedBox(height: 16),
          LegalLinksRow(onPrivacy: () {}, onTerms: () {}),
          const SizedBox(height: 16),
          for (final customized in [false, true])
            LegalDocCard(
              privacy: !customized,
              title: 'سياسة الخصوصية — a long document title that wraps',
              version: '12.0.3',
              effectiveDate: '2026-11-08',
              sections: 17,
              customized: customized,
              onEdit: () {},
              onPreview: () {},
              onRestore: () {},
            ),
          AuthTermsRow(accepted: false, onReadTap: () {}, onCheckChanged: (_) {}, onPrivacyTap: () {}),
          AuthTermsRow(accepted: true, onReadTap: () {}, onCheckChanged: (_) {}, onPrivacyTap: () {}),
        ]),
      ),
    );
  });

  testWidgets('the auth page with the legal links under its card', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => AuthLayout(
        title: 'تسجيل الدخول Sign in',
        showBack: false,
        footer: LegalLinksRow(onPrivacy: () {}, onTerms: () {}),
        body: (context, wide) => const Text(_long),
      ),
    );
  });
}
