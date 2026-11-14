// Layout for the widgets of the org-flow overhaul, agent f2 (320x640 and 1400x900, ar/en, textScaler 1.3).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/org_access_joining.dart';
import 'package:flutter_education_app/features/org/org_effective_access.dart';
import 'package:flutter_education_app/features/org/org_invitations.dart';
import 'package:flutter_education_app/features/org/org_invitations_pages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

OrgInvitation _i(int id, String contact, String status, {String role = 'student', String? link}) => OrgInvitation.fromJson({
      'id': id, 'channel': id.isEven ? 'phone' : 'email', 'contact': contact, 'role': role, 'status': status,
      'expires_at': '2099-01-01T00:00:00', 'invited_by': {'id': 1, 'name': 'Dr Administrator Long Name'}, 'sent_count': 3, 'link': link,
    });

final _lookup = InviteLookup(orgId: 4, nameAr: 'جامعة النيل للعلوم والتكنولوجيا', nameEn: 'Nile University of Science and Technology', role: 'teacher', status: 'pending', contactMasked: 'a***@mail.com', expiresAt: DateTime(2099));

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });

  testWidgets('invitation cards and list states', (tester) async {
    await expectNoLayoutErrors(tester, () => ListView(children: [
          OrgInvitationCard(invitation: _i(1, 'a-very-long-address.of.somebody@a-long-university-domain.edu.eg', 'pending', role: 'staff'), onResend: () {}, onCancel: () {}),
          OrgInvitationCard(invitation: _i(2, '+201001234567', 'accepted')),
          OrgInvitationCard(invitation: _i(3, 'c@x.org', 'pending'), now: DateTime(2100), onResend: () {}),
          InvitationsList(items: const [], loading: false, onInvite: () {}),
          InvitationsList(items: const [], loading: true),
          InvitationsList(items: const [], loading: false, error: Exception('x'), onRetry: () {}),
        ].map((w) => w is InvitationsList ? SizedBox(height: 300, child: w) : w).toList()));
  });

  testWidgets('invite result with links and skipped', (tester) async {
    final r = InviteResult([_i(1, 'long.long.long.long.address@university.edu.eg', 'pending', link: 'https://alfheemacademy.com/i/AAAAAAAA'), _i(2, '+201001234567', 'pending', link: 'https://alfheemacademy.com/i/BBBBBBBB')],
        const [InviteSkip('someone.else@university.edu.eg', 'already_member'), InviteSkip('x@y.z', 'already_invited')]);
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(padding: const EdgeInsets.all(16), child: InviteResultView(result: r, orgName: 'Nile')));
  });

  testWidgets('invitee page states', (tester) async {
    await expectNoLayoutErrors(tester, () => InviteeView(lookup: _lookup, signedIn: true, onAccept: () {}, onDecline: () {}));
    await expectNoLayoutErrors(tester, () => InviteeView(lookup: _lookup, signedIn: false, onSignIn: () {}, onRegister: () {}));
    await expectNoLayoutErrors(tester, () => InviteeView(lookup: _lookup, signedIn: true, mismatchMasked: 'a***@mail.com', myContact: 'me@another-domain.example.org', error: 'Some error'));
    await expectNoLayoutErrors(tester, () => InviteeView(lookup: _lookup, doneText: 'You are now a member', onClose: () {}));
    await expectNoLayoutErrors(tester, () => const InviteeView(error: 'This invitation does not exist'));
    await expectNoLayoutErrors(tester, () => const InviteeView(loading: true));
  });

  testWidgets('my invitations, join link, effective access', (tester) async {
    final mine = [
      MyInvitation(id: 1, orgId: 4, orgName: 'Nile University of Science and Technology', role: 'student', expiresAt: DateTime(2099)),
      MyInvitation(id: 2, orgId: 5, orgName: 'Faculty', role: 'staff'),
    ];
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: MyInvitationsView(items: mine, busyId: 2)));
    await expectNoLayoutErrors(tester, () => const JoinLinkSignedOut(code: 'ABCD2345XYZ1'));
    final catalog = {
      'actions': [{'key': 'view', 'label_ar': 'عرض', 'label_en': 'View'}, {'key': 'insert', 'label_ar': 'إضافة', 'label_en': 'Add'}],
      'groups': [{'key': 'g', 'label_ar': 'مجموعة', 'label_en': 'Group'}],
      'modules': [for (var i = 0; i < 6; i++) {'key': 'm$i', 'group': 'g', 'scope': 'dept', 'label_ar': 'وحدة طويلة جداً $i', 'label_en': 'A rather long module name $i', 'actions': ['view', 'insert']}],
    };
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: OrgEffectiveAccessView(catalog: catalog, orgWide: {'m0': {'view', 'insert'}, 'm1': {'view'}}, perDept: {3: {'m2': {'view'}}}, deptName: (_) => 'Computer Science Department')));
  });

  testWidgets('the invite sheet', (tester) async {
    final fake = FakeApi({
      'GET /api/v1/org/orgs/4/departments': (_) => {'items': [{'id': 1, 'name_ar': 'علوم', 'name_en': 'Science'}]},
    }, latency: const Duration(milliseconds: 10))
      ..install();
    addTearDown(fake.uninstall);
    await expectNoLayoutErrors(tester, () => const SingleChildScrollView(child: OrgInviteSheet(orgId: 4, orgName: 'Nile')), act: (t) async {
      await t.enterText(find.byType(TextField).first, 'a@x.org, bad, b@x.org');
    });
    AppConfig.lang = 'en';
  });

  testWidgets('the join page (parent, no scanner)', (tester) async {
    final fake = FakeApi({
      'GET /api/v1/org/public/search': (_) => {'items': <dynamic>[]},
      'GET /api/v1/org/public/me/join-status': (_) => {'organizations': <dynamic>[], 'units': <dynamic>[]},
    }, latency: const Duration(milliseconds: 10))
      ..install();
    addTearDown(fake.uninstall);
    await expectNoLayoutErrors(tester, () => const OrgJoinPage(isParent: true), scaffold: false);
    await expectNoLayoutErrors(tester, () => const OrgJoinPage(isParent: false, scannerAvailable: false), scaffold: false);
  });
}
