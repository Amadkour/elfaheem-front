// Review renders of the parent's More, link, booking, payments and the child-account pages (Pa2More, Pa2Pay, Pa2Gate
// contact / done&kid=new) with the CAST family, 390x844 and 1360x900, next to
// D:/platform/redesign-ref/ref/parent/019_* … 024_*, 035_*, 037_*. Not a CI suite.
//
//   flutter test test/visual/redesign/pa/pa_more_golden_test.dart --update-goldens [--plain-name book]
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/parent/parent_dashboard_screen.dart';
import 'package:flutter_education_app/features/parent/parent_link_providers.dart';
import 'package:flutter_education_app/features/parent/parent_link_screen.dart';
import 'package:flutter_education_app/features/parent/pay/pa_book_page.dart';
import 'package:flutter_education_app/features/parent/pay/pa_payments_page.dart';
import 'package:flutter_education_app/features/parent/signup/pa_add_child_page.dart';
import 'package:flutter_education_app/features/parent/signup/pa_child_api.dart';
import 'package:flutter_education_app/features/parent/signup/pa_child_code_page.dart';
import 'package:flutter_education_app/features/parent/signup/pa_join_child_fields.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/redesign/pa_fakes.dart';
import '../kit_golden_harness.dart';
import 'pa_golden_harness.dart';

Future<void> _tab(WidgetTester t, String ar, String en) async {
  final f = find.text(ar).evaluate().isNotEmpty ? find.text(ar) : find.text(en);
  await t.tap(f.last, warnIfMissed: false);
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Widget _link() => ChangeNotifierProvider(create: (_) => ParentLinkProvider()..loadAll(), child: const ParentLinkPage());

void main() {
  late StorageService storage;
  setUp(() async => storage = await kitGoldenSetUp());

  testWidgets('pa more', (t) => paRender(t, 'more', () => const ParentDashboardScreen(), storage: storage, act: (t) => _tab(t, 'المزيد', 'More')));
  testWidgets('pa link', (t) => paRender(t, 'link', _link, storage: storage, pushed: true));
  testWidgets('pa link advanced', (t) => paRender(t, 'link_adv', _link, storage: storage, pushed: true, langs: const ['ar'],
      api: paApi(extra: {
        'GET /api/v1/parent/link/config': (_) => {
              'mode': 'advanced',
              'fields': [
                {'key': 'full_name', 'type': 'text', 'label_ar': 'اسم الطالب الرباعي', 'label_en': 'Full name', 'required': true},
                {'key': 'birth', 'type': 'date', 'label_ar': 'تاريخ الميلاد', 'label_en': 'Date of birth', 'required': true},
                {'key': 'phone', 'type': 'phone', 'label_ar': 'جوال الطالب', 'label_en': 'Phone'},
                {'key': 'relation', 'type': 'select', 'label_ar': 'صلتك بالطالب', 'label_en': 'Your relation', 'required': true, 'options': ['father', 'mother', 'guardian']},
              ],
              'documents': [
                {'key': 'id_doc', 'label_ar': 'إثبات الولاية', 'label_en': 'Proof of guardianship', 'required': true},
              ],
            },
      })));
  testWidgets('pa book', (t) => paRender(t, 'book', () => const ParentBookPage(childId: paReem), storage: storage, pushed: true,
      act: (t) => paTap(t, const ValueKey('pa.book.subject.104'))));
  testWidgets('pa payments', (t) => paRender(t, 'payments', () => const ParentPaymentsPage(), storage: storage, pushed: true));
  testWidgets('pa invoice', (t) => paRender(t, 'invoice', () => SingleChildScrollView(child: PaReceiptSheet(payment: PaPayment.tryParse({
        'id': 1191, 'amount': 449, 'status': 'completed', 'payment_method': 'mada', 'transaction_id': 'TX-88213', 'meta_data': {'currency': 'SAR'},
        'paid_at': '2026-11-20T15:00:00Z', 'course_id': 1,
      })!)), storage: storage, pushed: true, langs: const ['ar']));
  testWidgets('pa join child', (t) => paRender(t, 'join_child', () => const SingleChildScrollView(
        padding: EdgeInsets.all(16), child: PaJoinChildFields(country: 'SA', stageId: 3, gradeId: 31, delivery: 'online')),
      storage: storage, pushed: true, langs: const ['ar']));
  testWidgets('pa child code', (t) => paRender(t, 'child_code', () => ParentChildCodePage(
        parentName: 'أحمد',
        child: const PaCreatedChild(id: 9, name: 'فيصل العنزي', firstName: 'فيصل', gradeAr: 'الصف الثاني الثانوي، عن بعد', gradeEn: 'Grade 11, remote'),
        code: PaLoginCode(code: '482917', display: '482 917', ttlSeconds: 172800, expiresAt: DateTime.utc(2026, 11, 29)),
      ), storage: storage, pushed: true));
  testWidgets('pa add child', (t) => paRender(t, 'add_child', () => const ParentAddChildPage(), storage: storage, pushed: true));
}
