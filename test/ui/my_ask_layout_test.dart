// Student lifecycle phase 4 (D-1400): the student's ask form (every kind, a returned ask, a closed one, the full-screen
// and popup frames), the home's "Waiting for your answer" row and the complaint thread's student strip through the
// layout harness (320×640 and 1400×900, ar / en, text × 1.3).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/home/home_application_card.dart';
import 'package:flutter_education_app/features/org/org_services_pages.dart' show ComplaintStudentStrip;
import 'package:flutter_education_app/features/org/students/my_ask_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'طلب من شؤون الطلاب بخصوص استكمال بيانات الملف الأكاديمي قبل نهاية الفصل — a long title that wraps';

Map<String, dynamic> ask(String kind, {String status = 'open', String? note, Map<String, dynamic>? answer}) => {
      'id': 5,
      'org_id': 1,
      'kind': kind,
      'presentation': 'notice',
      'title': _long,
      'body': 'نرجو الرد في أقرب وقت. Please answer as soon as you can, the committee meets next week.',
      'fields': [
        {'key': 'phone', 'label_ar': 'رقم هاتف ولي الأمر', 'label_en': 'Guardian phone number', 'kind': 'text', 'required': true},
        {'key': 'why', 'label_ar': 'اشرح الظروف', 'label_en': 'Explain the circumstances in a few lines', 'kind': 'long_text', 'required': false},
        {'key': 'level', 'label_ar': 'المستوى', 'label_en': 'Level', 'kind': 'choice', 'options': ['الأول', 'الثاني', 'الثالث — with a long option']},
        {'key': 'many', 'label_ar': 'المحافظة', 'label_en': 'Governorate', 'kind': 'choice', 'options': [for (var i = 0; i < 12; i++) 'Governorate number $i']},
        {'key': 'born', 'label_ar': 'تاريخ الميلاد', 'label_en': 'Date of birth', 'kind': 'date'},
        {'key': 'kids', 'label_ar': 'عدد الإخوة', 'label_en': 'Brothers and sisters', 'kind': 'number'},
        {'key': 'works', 'label_ar': 'هل تعمل؟', 'label_en': 'Do you work?', 'kind': 'yes_no'},
      ],
      'doc_keys': ['secondary_certificate_with_a_very_long_key_name', 'birth_cert', 'photo'],
      'status': status,
      'answer': answer,
      'due_at': '2026-12-01T10:00:00',
      'review_note': note,
      'org': {'id': 1, 'name': 'جامعة المنصورة الأهلية للعلوم والتكنولوجيا', 'name_en': 'Mansoura National University of Science and Technology'},
      'created_by': {'id': 3, 'name': 'مكتب شؤون الطلاب والخريجين'},
      'meeting': {'id': 2, 'starts_at': '2026-11-25T09:00:00', 'ends_at': '2026-11-25T09:30:00', 'mode': 'offline', 'location': 'مبنى الإدارة، الدور الثالث، مكتب ٣٠٢ — Admin building, third floor'},
      'can': {'answer': status == 'open' || status == 'returned'},
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  testWidgets('every kind of ask: no layout error', (tester) async {
    for (final k in ['meeting', 'data', 'documents', 'confirm']) {
      final a = MyAsk.fromJson(ask(k))!;
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: MyAskView(ask: a, onSubmit: (_, _) {}, onUpload: (_) {})));
    }
  });

  testWidgets('returned, busy, error, uploaded and closed asks: no layout error', (tester) async {
    final returned = MyAsk.fromJson(ask('data', status: 'returned', note: 'رقم الهاتف غير صحيح، اكتب رقماً من ١١ خانة — the phone number is wrong', answer: {'values': {'phone': '0100'}}))!;
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: MyAskView(ask: returned, busy: true, error: 'Complete the required answers', onSubmit: (_, _) {})));
    final docs = MyAsk.fromJson(ask('documents', answer: {'documents': {'birth_cert': 4}}))!;
    expect(docs.uploaded.keys, ['birth_cert']);
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: MyAskView(ask: docs, uploading: const {'photo'}, onUpload: (_) {}, onLater: () {})));
    for (final s in ['answered', 'accepted', 'cancelled', 'expired']) {
      final a = MyAsk.fromJson(ask('meeting', status: s))!;
      expect(a.canAnswer, isFalse);
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: MyAskView(ask: a)));
    }
  });

  testWidgets('the meeting decline step and the data check', (tester) async {
    final a = MyAsk.fromJson(ask('meeting'))!;
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: MyAskView(ask: a, onSubmit: (_, _) {})), act: (tester) async {
      await tester.ensureVisible(find.byKey(const ValueKey('my_ask.decline')));
      await tester.tap(find.byKey(const ValueKey('my_ask.decline')));
      await tester.pump();
      expect(find.byKey(const ValueKey('my_ask.send_decline')), findsOneWidget);
    });
    final d = MyAsk.fromJson(ask('data'))!;
    expect(myAskMissing(d, {}), ['phone', 'level', 'many', 'born', 'kids', 'works']);
    expect(myAskValuesOut(d, {'phone': ' 0100 ', 'kids': '3', 'why': ''}), {'phone': '0100', 'kids': 3});
  });

  testWidgets('the full-screen and popup frames: no layout error', (tester) async {
    final a = MyAsk.fromJson(ask('confirm'))!;
    for (final full in [true, false]) {
      await expectNoLayoutErrors(
          tester, () => MyAskCardFrame(fullscreen: full, child: MyAskView(ask: a, onSubmit: (_, _) {}, onLater: full ? null : () {})),
          scaffold: false);
    }
  });

  testWidgets('home: Waiting for your answer', (tester) async {
    final items = homeAsksOf({
      'asks': [
        {'id': 1, 'org_id': 1, 'org_name': 'جامعة المنصورة الأهلية للعلوم والتكنولوجيا', 'kind': 'documents', 'title': _long, 'due_at': '2026-12-01T10:00:00', 'presentation': 'notice'},
        {'id': 2, 'org_id': 1, 'org_name': 'Faculty', 'kind': 'meeting', 'title': '', 'due_at': null, 'presentation': 'popup'},
        'junk',
      ],
    });
    expect(items.length, 2);
    expect(items.first.dueAt, isNotNull);
    expect(homeAsksOf(const {}), isEmpty);
    await expectNoLayoutErrors(tester, () => HomeAsksCard(items: items, onOpen: (_) {}));
    await expectNoLayoutErrors(tester, () => const HomeAsksCard(items: []));
  });

  testWidgets('complaint thread: the student strip', (tester) async {
    final st = {
      'id': 9,
      'name': 'سارة محمود عبد الرحمن إبراهيم — a very long student name for the strip',
      'image_url': null,
      'student_code': '2026-ENG-000123',
      'enrol_status': 'enrolled',
      'chip': {'dimension': 'standing', 'value': 'warning'},
      'can': {'open_file': true, 'status': true, 'ask': true},
    };
    await expectNoLayoutErrors(tester, () => ComplaintStudentStrip(student: st, onOpenFile: () {}, onMeeting: () {}, onStatus: () {}));
  });
}
