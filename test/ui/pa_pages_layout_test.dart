// The parent redesign's pages (group P, Pa2*) at 320x640 and 1400x900, Arabic + English, textScaler 1.3, over the
// CAST family (test/support/redesign/pa_fakes.dart): the child's page and course page, Children, Reports (all and one
// child), Alerts, the link page, booking for a child, payments and the receipt, the child-account pages, the sheets.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_models.dart';
import 'package:flutter_education_app/features/parent/pa_child_pages.dart';
import 'package:flutter_education_app/features/parent/pa_kit.dart';
import 'package:flutter_education_app/features/parent/pa_more_page.dart';
import 'package:flutter_education_app/features/parent/parent_alerts_page.dart';
import 'package:flutter_education_app/features/parent/parent_children_page.dart';
import 'package:flutter_education_app/features/parent/parent_consent.dart';
import 'package:flutter_education_app/features/parent/parent_link_providers.dart';
import 'package:flutter_education_app/features/parent/parent_link_screen.dart';
import 'package:flutter_education_app/features/parent/parent_reports_page.dart';
import 'package:flutter_education_app/features/parent/pay/pa_book_page.dart';
import 'package:flutter_education_app/features/parent/pay/pa_payments_page.dart';
import 'package:flutter_education_app/features/parent/signup/pa_add_child_page.dart';
import 'package:flutter_education_app/features/parent/signup/pa_child_api.dart';
import 'package:flutter_education_app/features/parent/signup/pa_child_code_page.dart';
import 'package:flutter_education_app/features/parent/signup/pa_join_child_fields.dart';
import 'package:flutter_education_app/features/profile/profile_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/redesign/pa_fakes.dart';
import 'layout_harness.dart';

const _long = 'إدارة شؤون الطلاب والدراسات العليا والبحث العلمي بكلية الهندسة Office of Student Affairs and Research';

void main() {
  late MyAuthProvider auth;
  setUp(() async {
    AppConfig.disableList = [];
    auth = await paSetUp(paApi());
  });

  Widget withKids(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => PaKids()..setKids(const [PaKid(id: paReem, name: 'ريم العنزي', status: 'on_track'), PaKid(id: paFaisal, name: _long, status: 'watch')])),
          ChangeNotifierProvider(create: (_) => ParentLinkProvider()..loadAll()),
          ChangeNotifierProvider(create: (_) => ParentAlertsProvider()..load()),
        ],
        child: paRole(child),
      );

  testWidgets('kids: list, child page, course page', (t) async {
    await expectNoLayoutErrors(t, () => withKids(ParentChildrenPage(onOpenLinkTab: () {}, onAddChild: () {})), frames: 8);
    await expectNoLayoutErrors(t, () => withKids(const ParentChildPage(childId: paReem)), frames: 8);
    final course = DlCourseBlock.fromJson({
      ...(paProfile(paReem)['courses'] as List).first as Map<String, dynamic>,
      'course': {'id': 1, 'title': _long},
    });
    await expectNoLayoutErrors(t, () => withKids(ParentChildCoursePage(childId: paReem, childName: _long, course: course)), frames: 6);
  });

  testWidgets('reports: all children, one child, the score sheet', (t) async {
    await expectNoLayoutErrors(t, () => withKids(const ParentReportsPage()), frames: 8);
    await expectNoLayoutErrors(t, () => withKids(const ParentChildReportScreen(studentId: paReem, studentName: _long)), frames: 8);
    await expectNoLayoutErrors(t, () => SingleChildScrollView(child: paRole(PaScoreSheet(score: paReport()['score'] as Map))));
  });

  testWidgets('alerts and link pages', (t) async {
    await expectNoLayoutErrors(t, () => withKids(const ParentAlertsPage()), frames: 8);
    await expectNoLayoutErrors(t, () => withKids(const ParentLinkPage()), frames: 8);
  });

  testWidgets('more page', (t) async {
    final storage = await StorageService.getInstance();
    await expectNoLayoutErrors(
      t,
      () => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider(create: (_) => ProfileProvider(storage: storage)),
          ChangeNotifierProvider(create: (_) => LangProvider(storage: storage)),
        ],
        child: withKids(ParentMorePage(onOpenLink: () {}, onBook: () {}, onPayments: () {})),
      ),
      frames: 8,
    );
  });

  testWidgets('book, payments, receipt', (t) async {
    await expectNoLayoutErrors(t, () => withKids(const ParentBookPage(childId: paReem)), frames: 8);
    await expectNoLayoutErrors(t, () => paRole(const ParentPaymentsPage()), frames: 8);
    await expectNoLayoutErrors(t, () => SingleChildScrollView(
          child: paRole(PaReceiptSheet(payment: PaPayment.tryParse({'id': 123456789, 'amount': 123456.75, 'status': 'refunded', 'payment_method': _long, 'transaction_id': _long})!)),
        ));
  });

  testWidgets('child account: join fields, add child, the code page', (t) async {
    await expectNoLayoutErrors(t, () => const SingleChildScrollView(child: PaJoinChildFields(country: 'SA', stageId: 3, gradeId: 31)));
    await expectNoLayoutErrors(t, () => paRole(const ParentAddChildPage()), frames: 8);
    await expectNoLayoutErrors(t, () => ParentChildCodePage(
          parentName: _long,
          child: const PaCreatedChild(id: 9, name: _long, firstName: _long, gradeAr: _long, gradeEn: _long),
          code: const PaLoginCode(code: '482917', display: '482 917', ttlSeconds: 172800),
        ));
  });

  testWidgets('consent: sheet, withdraw sheet, locked view; the switcher', (t) async {
    await expectNoLayoutErrors(t, () => const SingleChildScrollView(child: ParentConsentSheet(childName: _long, grade: _long)));
    await expectNoLayoutErrors(t, () => const SingleChildScrollView(child: ParentRevokeSheet(childName: _long)));
    await expectNoLayoutErrors(t, () => ConsentRequiredView(childName: _long, onGive: () {}));
    await expectNoLayoutErrors(t, () => PaKidSwitcher(
          kids: const [PaKid(id: 1, name: _long, status: 'needs_you'), PaKid(id: 2, name: 'S')],
          selected: 1,
          onSelect: (_) {},
          onAdd: () {},
        ));
  });

  test('the child draft keeps only a named child with a grade', () {
    expect(PaChildDraft(firstName: 'سارة').ready, isFalse);
    expect(PaChildDraft(firstName: 'سارة', stageId: 1, gradeId: 13).ready, isTrue);
    expect(PaChildDraft(firstName: ' سارة ', lastName: '', stageId: 1, gradeId: 13, country: 'SA').toBody(),
        containsPair('first_name', 'سارة'));
    final c = PaCreatedChild.tryParse({
      'child': {'id': 381, 'name': 'سارة أحمد', 'first_name': 'سارة', 'grade_name_ar': 'الصف الرابع الابتدائي'},
      'login_code': {'code': '482917', 'code_display': '482 917', 'ttl_seconds': 172800, 'share_text_ar': 'نص'},
    })!;
    expect(c.code!.display, '482 917');
    expect(c.code!.hours, 48);
  });
}
