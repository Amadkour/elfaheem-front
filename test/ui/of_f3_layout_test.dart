// Org flow overhaul, agent f3: no overflow on any screen size (320x640 and 1400x900, ar / en, textScaler 1.3) for the
// new and redesigned widgets: the organization detail panel, the profile and transfer sheets, the typed-name dialog,
// the setup checklist card, the billing view, the application form and the creation-fee error.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_organizations_page.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/org/home/org_setup_checklist.dart';
import 'package:flutter_education_app/features/org/org_application_screen.dart';
import 'package:flutter_education_app/features/org/org_billing_page.dart';
import 'package:flutter_education_app/features/org/org_creation_fee.dart';
import 'package:flutter_education_app/features/org/org_danger_zone.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

late MyAuthProvider _auth;

Widget _wrap(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<MyAuthProvider>.value(value: _auth),
        ChangeNotifierProvider<OrgSession>(create: (_) => OrgSession()),
      ],
      child: child,
    );

const _org = {
  'id': 5,
  'name_ar': 'جامعة النيل للعلوم والتكنولوجيا والدراسات العليا',
  'name_en': 'Nile University for Science, Technology and Postgraduate Studies',
  'description': 'A long description of the organization that wraps over several lines on a phone screen.',
  'status': 'approved',
  'type': 'university',
  'contact_email': 'registrar@very-long-university-domain-name.example.edu.eg',
  'counts': {'members': 1200, 'departments': 14, 'sub_organizations': 3},
  'creator': {'name': 'Sara Ali Hassan', 'email': 'sara.ali.hassan@example.com'},
};

void main() {
  late FakeApi api;

  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    final storage = await StorageService.getInstance();
    await storage.saveUser({'id': 7, 'name': 'Boss', 'gmail': 'boss@example.test', 'role': 'super-admin'});
    _auth = MyAuthProvider(storage: storage)..loadCachedUser();
    AppConfig.disableList = [];
    api = FakeApi({
      'GET /api/v1/org/orgs/5/members': (o) => {
            'items': [
              for (var i = 0; i < 4; i++) {'id': i, 'user': {'id': 100 + i, 'name': 'A member with a rather long display name $i', 'email': 'member$i@example-university.edu.eg'}},
            ],
          },
      'GET /api/v1/org/creation-fee': (o) => const FakeResponse(500, {'detail': 'boom'}),
      'GET /api/v1/admin/orgs/stats': (o) => {'pending': 3, 'approved': 10, 'total': 16},
      'GET /api/v1/admin/orgs': (o) => {
            'items': [_org, {..._org, 'id': 6, 'status': 'pending'}],
            'total': 2,
            'page': 1,
            'pages': 1,
          },
    }, latency: const Duration(milliseconds: 5))
      ..install();
  });
  tearDown(() => api.uninstall());

  final setup = OrgSetupData.fromJson({
    'dismissed': false,
    'steps': [
      for (final k in orgSetupOrder) {'key': k, 'done': k == 'profile' || k == 'departments', 'count': 2},
    ],
  });

  testWidgets('organization detail panel: approved, pending, deleted', (tester) async {
    for (final status in ['approved', 'pending', 'deleted']) {
      await expectNoLayoutErrors(tester, () => _wrap(SingleChildScrollView(child: OrgReviewPanel(org: {..._org, 'status': status}, onChanged: () async {}))));
    }
  });

  testWidgets('profile edit sheet and transfer-admin sheet', (tester) async {
    await expectNoLayoutErrors(tester, () => _wrap(SingleChildScrollView(child: OrgProfileEditSheet(org: _org))));
    await expectNoLayoutErrors(tester, () => _wrap(SingleChildScrollView(child: OrgTransferAdminSheet(orgId: 5, orgName: 'Nile University', platform: true))), frames: 6);
  });

  testWidgets('the typed-name dialog', (tester) async {
    await expectNoLayoutErrors(tester, () => _wrap(Builder(builder: (context) => Center(child: AppButton.primary(label: 'Open', onPressed: () => askTypedNameConfirm(context, org: _org, title: 'Delete the organization', body: 'The organization is hidden from its members; its data is kept.', confirmLabel: 'Delete the organization'))))),
        act: (t) async {
      await t.tap(find.text('Open'));
    });
  });

  testWidgets('setup checklist card: partial, and with nothing done', (tester) async {
    await expectNoLayoutErrors(tester, () => _wrap(SingleChildScrollView(child: OrgSetupCard(data: setup, onOpen: (_) {}, onDismiss: () {}))));
    final none = OrgSetupData.fromJson({'dismissed': false, 'steps': [for (final k in orgSetupOrder) {'key': k, 'done': false}]});
    await expectNoLayoutErrors(tester, () => _wrap(SingleChildScrollView(child: OrgSetupCard(data: none, onOpen: (_) {}, onDismiss: () {}, dismissing: true))));
  });

  testWidgets('billing view: configured, unset default notice, empty', (tester) async {
    final full = OrgBillingData.fromJson({
      'configured': false,
      'plans': [
        for (final p in ['monthly', 'yearly']) {'code': p, 'label_ar': 'خطة اشتراك طويلة الاسم $p', 'label_en': 'A long subscription plan name $p', 'price': 1234.5, 'currency': 'EGP'},
      ],
      'applies_to': {'students': 'per_account', 'staff': 'charged', 'admins': 'free'},
      'notice': 'unset_yearly_default',
      'creation_fee': {'paid': true, 'amount': 500, 'currency': 'EGP', 'paid_at': '2026-10-01T10:00:00', 'method': 'bank_transfer'},
      'payments': [
        for (var i = 0; i < 3; i++) {'id': i, 'kind': 'creation_fee', 'amount': 500, 'currency': 'EGP', 'status': i == 0 ? 'paid' : 'pending', 'method': 'bank_transfer', 'created_at': '2026-10-0${i + 1}T10:00:00'},
      ],
    });
    await expectNoLayoutErrors(tester, () => _wrap(OrgBillingView(data: full)));
    final empty = OrgBillingData.fromJson({'configured': true, 'plans': [], 'applies_to': {}, 'creation_fee': null, 'payments': []});
    await expectNoLayoutErrors(tester, () => _wrap(OrgBillingView(data: empty)));
  });

  testWidgets('creation-fee panel with its error and Retry', (tester) async {
    await expectNoLayoutErrors(tester, () => _wrap(SingleChildScrollView(child: OrgCreationFeePanel(onReady: (_, _) {}))), frames: 8);
  });

  testWidgets('application form', (tester) async {
    await expectNoLayoutErrors(tester, () => _wrap(const OrgApplicationScreen()), scaffold: false, frames: 6);
  });

  testWidgets('Super Admin organizations page', (tester) async {
    await expectNoLayoutErrors(tester, () => _wrap(const AdminOrganizationsPage()), scaffold: false, frames: 8);
  });
}
