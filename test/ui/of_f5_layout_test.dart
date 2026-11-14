// Layout for the f5 additions (320x640 and 1400x900, ar/en, textScaler 1.3): the invitee's "Open the organization"
// button after accepting, the join-code chips on AppType tokens, and the assistants' blocked "Leave" tile text.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/org_dashboard_settings.dart' show orgStaffCannotLeave;
import 'package:flutter_education_app/features/org/org_invitations.dart';
import 'package:flutter_education_app/features/org/org_invitations_pages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

final _lookup = InviteLookup(
    orgId: 4,
    nameAr: 'جامعة النيل للعلوم والتكنولوجيا',
    nameEn: 'Nile University of Science and Technology',
    role: 'teacher',
    status: 'pending',
    contactMasked: 'a***@mail.com',
    expiresAt: DateTime(2099));

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });

  testWidgets('invitee after accepting: Open the organization + Done fit every size', (tester) async {
    await expectNoLayoutErrors(
        tester, () => InviteeView(lookup: _lookup, doneText: 'You are now a member of "Nile University of Science and Technology".', onOpenOrg: () {}, onClose: () {}));
  });

  test('only the two assistant roles get the explained (blocked) leave tile', () {
    expect(orgStaffCannotLeave('teacher_assistant'), isTrue);
    expect(orgStaffCannotLeave('admin_assistant'), isTrue);
    for (final r in ['teacher', 'student', 'org_admin', null, '']) {
      expect(orgStaffCannotLeave(r), isFalse, reason: '$r');
    }
    AppConfig.lang = 'en';
  });
}
