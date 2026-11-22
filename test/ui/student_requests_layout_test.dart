// Student lifecycle phase 6 (D-1400): the student's requests page and form, the reviewer's request detail (every
// mode) and the transfer-credit panel through the layout harness (320×640 and 1400×900, ar / en, text × 1.3).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/org/students/my_requests.dart';
import 'package:flutter_education_app/features/org/students/student_request_detail.dart';
import 'package:flutter_education_app/features/org/students/student_requests_api.dart';
import 'package:flutter_education_app/features/org/students/transfer_credits_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/student_requests_test.dart' show myRequestsJson;
import 'layout_harness.dart';

const _long = 'سبب طويل جداً يشرح ظروف الطالب العائلية والصحية بالتفصيل — a very long reason that explains everything in detail';

LifecycleRequest staffRequest({String stage = 'review', bool dataUpdate = false, RequestCan can = const RequestCan(accept: true, reject: true, council: true)}) =>
    LifecycleRequest.fromJson({
      'id': 4,
      'ref': 'REQ-2026-000123',
      'request': dataUpdate ? 'data_update' : 'transfer_out',
      'label_ar': dataUpdate ? 'تحديث بياناتي' : 'التحويل إلى جهة أخرى',
      'label_en': dataUpdate ? 'Update my details' : 'Transfer to another faculty',
      'status': stage == 'review' ? 'open' : stage,
      'stage': stage,
      'origin': 'student',
      'reason': _long,
      'reason_code': dataUpdate ? null : 'transfer_other_univ',
      'effective_from': '2026-12-01',
      'effective_to': '2027-06-30',
      'changes': dataUpdate ? {'address': '15 شارع النيل، المنصورة، الدقهلية — 15 Nile Street, a long address'} : null,
      'decision_no': stage == 'approved' ? '1234/2026' : null,
      'applied': stage == 'approved',
      'note': stage == 'rejected' ? 'لا يوجد خطاب قبول من الجهة الأخرى — no acceptance letter' : null,
      'created_at': '2026-11-20T08:00:00',
      'decided_at': stage == 'approved' || stage == 'rejected' ? '2026-11-21T08:00:00' : null,
      'title': 'التحويل: عبد الرحمن محمد عبد الله السيد الشرقاوي',
      'params': dataUpdate ? <String, dynamic>{} : {'decision': 'transfer_out'},
      'body_key': dataUpdate ? null : 'faculty_council',
      'needs_decision_no': !dataUpdate,
      'councils': [
        {'dept_id': 5, 'name_ar': 'مجلس كلية الهندسة والتكنولوجيا', 'name_en': 'The Council of the Faculty of Engineering and Technology'},
        {'dept_id': 6, 'name_ar': 'مجلس الجامعة', 'name_en': 'University council'},
      ],
      'can': {'accept': can.accept, 'reject': can.reject, 'council': can.council},
    });

TransferCredits credits({bool canDecide = true}) => TransferCredits.fromJson({
      'items': [
        {
          'id': 1, 'source_institution': 'جامعة القاهرة — كلية الهندسة، قسم الهندسة الكهربية', 'source_course': 'Calculus and Analytic Geometry I with a long title',
          'source_code': 'MTH-101-A', 'source_grade': 'B+', 'source_credits': 3,
          'course': {'id': 40, 'code': 'MATH101', 'name_ar': 'التفاضل والتكامل والهندسة التحليلية', 'name_en': 'Calculus and analytic geometry', 'credit_hours': 3},
          'counted_hours': 3, 'decision': 'credited', 'counts_in_gpa': true, 'note': 'وافقت لجنة المقاصة في جلستها الثالثة',
        },
        {'id': 2, 'source_course': 'Physics', 'source_grade': 'D', 'source_credits': 2.5, 'course': null, 'decision': 'pending', 'below_min': true},
        {'id': 3, 'source_course': 'Chemistry', 'decision': 'not_credited'},
      ],
      'settings': {'counts_in_gpa': false, 'min_letter': 'C'},
      'summary': {'pending': 1, 'credited': 1, 'credited_hours': 3, 'gpa_hours': 3},
      'can': {'edit': true, 'decide': canDecide},
    });

void main() {
  setUp(() => AppConfig.lang = 'en');

  testWidgets('my requests page: loading, error, data', (tester) async {
    final data = MyRequests.fromJson(myRequestsJson());
    await expectNoLayoutErrors(tester, () => const MyRequestsView(loading: true));
    await expectNoLayoutErrors(tester, () => MyRequestsView(error: 'Could not load', onRetry: () {}));
    await expectNoLayoutErrors(tester, () => MyRequestsView(data: data, busy: const {12}, onStart: (_) {}, onWithdraw: (_) {}, onRefresh: () async {}));
    await expectNoLayoutErrors(tester, () => const MyRequestsView(data: MyRequests()));
  });

  testWidgets('a request card in every stage', (tester) async {
    for (final s in ['review', 'council', 'approved', 'rejected', 'withdrawn']) {
      final r = staffRequest(stage: s);
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: MyRequestCard(request: r, onWithdraw: () {})));
    }
    final u = staffRequest(dataUpdate: true);
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: MyRequestCard(request: u, labels: const {'address': 'Home address'})));
  });

  testWidgets('the request form: dated, serious, data update', (tester) async {
    final data = MyRequests.fromJson(myRequestsJson());
    for (final k in ['suspend', 'withdraw', 'data_update']) {
      final o = data.option(k)!;
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: MyRequestForm(option: o, onSubmit: (_) async => null, onAddDocument: () async => null)));
    }
    final o = data.option('suspend')!;
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: MyRequestForm(option: o, onSubmit: (_) async => null)), act: (tester) async {
      await tester.ensureVisible(find.byKey(const ValueKey('my_requests.send')));
      await tester.tap(find.byKey(const ValueKey('my_requests.send')));
      await tester.pump();
      expect(find.text(t('اكتب السبب في سطر أو أكثر', 'Write the reason in a line or more')), findsOneWidget);
    });
  });

  testWidgets('the reviewer detail: every mode and state', (tester) async {
    final r = staffRequest();
    for (final m in ['view', 'accept', 'reject', 'council']) {
      await expectNoLayoutErrors(
          tester,
          () => SingleChildScrollView(
              child: StudentRequestDetailView(request: r, initialMode: m, canOverride: m == 'accept', error: m == 'reject' ? 'One of the institution\'s rules stops this change' : null,
                  onAccept: (_) async => true, onReject: (_) async => true, onCouncil: (_, _) async => true)));
    }
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: StudentRequestDetailView(request: staffRequest(dataUpdate: true), initialMode: 'accept', busy: 'accept')));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: StudentRequestDetailView(request: staffRequest(stage: 'council', can: const RequestCan()))));
    for (final s in ['approved', 'rejected']) {
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: StudentRequestDetailView(request: staffRequest(stage: s))));
    }
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: StudentRequestDetailView(request: r, onAccept: (_) async => true)), act: (tester) async {
      await tester.ensureVisible(find.byKey(const ValueKey('students.request.accept')));
      await tester.tap(find.byKey(const ValueKey('students.request.accept')));
      await tester.pump();
      expect(find.byKey(const ValueKey('students.request.decision_no')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('students.request.confirm')));
      await tester.tap(find.byKey(const ValueKey('students.request.confirm')));
      await tester.pump();
      expect(find.text(t('اكتب رقم القرار وتاريخه', 'Enter the decision number and its date')), findsOneWidget);
    });
  });

  testWidgets('transfer credits: the list, the forms', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
            child: TransferCreditsView(data: credits(), busy: const {2}, onAdd: () {}, onEdit: (_) {}, onDecide: (_, _) {}, onDelete: (_) {}, onSettings: () {})));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: TransferCreditsView(data: credits(canDecide: false), onAdd: () {}, onEdit: (_) {})));
    await expectNoLayoutErrors(tester, () => const SingleChildScrollView(child: TransferCreditsView(data: TransferCredits())));
    final c = credits().items.first;
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: TransferCreditForm(initial: CreditDraft.of(c), onPickCourse: () async => null, onSave: (_) async => null)));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: TransferCreditForm(onSave: (_) async => 'A value is not valid')), act: (tester) async {
      await tester.ensureVisible(find.byKey(const ValueKey('students.credits.f.save')));
      await tester.tap(find.byKey(const ValueKey('students.credits.f.save')));
      await tester.pump();
      expect(find.text(t('اكتب اسم المقرر', 'Write the course name')), findsOneWidget);
    });
    await expectNoLayoutErrors(
        tester, () => SingleChildScrollView(child: TransferCreditSettingsForm(initial: const TransferCreditSettings(countsInGpa: true, minLetter: 'C'), onSave: (_) async => null)));
  });
}
