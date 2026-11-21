// The ask sheet and the requests inbox never overflow (contract §14 phase 4): StudentAskView for every kind with
// long texts, the busy card and an error, the missing-data loading / error states; StudentRequestsView loading,
// error, empty per tab and full with every verb and an overdue row; AskReviewView answered, open and with an error.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/students/student_ask_sheet.dart';
import 'package:flutter_education_app/features/org/students/student_asks_models.dart';
import 'package:flutter_education_app/features/org/students/student_requests_page.dart';
import 'package:flutter_education_app/features/org/students/students_models.dart' show StudentMissing;
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'يرجى الحضور إلى مكتب شؤون الطلاب لمناقشة ما ورد في الشكوى المقدمة بخصوص نتيجة مقرر الرياضيات المتقدمة وإحضار ما يثبت ذلك';

StudentMissing _missing() => StudentMissing.fromJson({
      'case_id': 5,
      'fields': [
        for (final k in ['guardian_phone', 'national_address_with_a_very_long_label', 'birth_place'])
          {'key': k, 'label_ar': 'رقم هاتف ولي الأمر الثاني للتواصل في حالات الطوارئ', 'label_en': 'Second guardian phone for emergencies', 'kind': 'phone'},
      ],
      'documents': [
        for (final k in ['birth_cert', 'military', 'photo'])
          {'key': k, 'label_ar': 'شهادة الميلاد المميكنة الأصلية', 'label_en': 'Original computerised birth certificate', 'why_ar': 'مطلوب لكل الطلاب', 'why_en': 'Required for every student'},
      ],
    });

AskDraft _draft(String kind) {
  final d = AskDraft(kind: kind, presentation: 'fullscreen', title: _long);
  d.dueAt = DateTime.utc(2026, 11, 25, 21);
  d.remindDays = [3, 1];
  if (kind == 'meeting') {
    d.startsAt = DateTime.utc(2026, 11, 24, 8);
    d.minutes = 90;
  }
  if (kind == 'data') {
    d.toggleCaseField(const AskPickable('guardian_phone', 'Second guardian phone for emergencies'));
    final q = d.addQuestion();
    q.labelAr = _long;
    q.kind = 'choice';
    q.options = ['الفصل الدراسي الأول', 'الفصل الدراسي الثاني', 'الصيفي'];
  }
  if (kind == 'documents') d.docKeys = ['birth_cert'];
  return d;
}

Widget _sheet(String kind, {bool busy = false, String? error, bool loading = false, String? missingError, StudentMissing? missing}) {
  final d = _draft(kind);
  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: StudentAskView(
      draft: d,
      title: TextEditingController(text: _long),
      body: TextEditingController(text: _long),
      place: TextEditingController(text: 'مبنى الإدارة، الدور الثالث، مكتب شؤون الطلاب رقم 312'),
      name: 'عبد الرحمن محمد عبد الله الشريف',
      missing: loading || missingError != null ? null : (missing ?? _missing()),
      missingLoading: loading,
      missingError: missingError,
      onRetryMissing: () {},
      busy: busy
          ? AskBusy.listOf({
              'busy': [
                {
                  'user': {'name': 'عبد الرحمن محمد عبد الله الشريف'},
                  'items': [
                    {'title': 'محاضرة الرياضيات المتقدمة للفرقة الثالثة', 'starts_at': '2026-11-24T08:00:00', 'ends_at': '2026-11-24T09:30:00'},
                    {'title': 'اجتماع الإرشاد الأكاديمي', 'starts_at': '2026-11-24T09:00:00'},
                  ],
                },
              ],
            })
          : const [],
      error: error,
      onKind: (_) {},
      onPresentation: (_) {},
      onEdit: (_) {},
      onPickStart: () {},
      onPickDue: () {},
      onClearDue: () {},
      onSubmit: () {},
      onForce: () {},
    ),
  );
}

Map<String, dynamic> _askJson({String status = 'answered', String kind = 'data'}) => {
      'id': 31,
      'kind': kind,
      'presentation': 'popup',
      'title': _long,
      'body': _long,
      'fields': [
        {'key': 'guardian_phone', 'label_ar': 'رقم هاتف ولي الأمر الثاني للتواصل في حالات الطوارئ', 'label_en': 'Second guardian phone', 'kind': 'text', 'case_field': true},
        {'key': 'q1', 'label_ar': _long, 'label_en': _long, 'kind': 'long_text'},
      ],
      'status': status,
      'answer': status == 'open' ? null : {'values': {'guardian_phone': '+20 100 123 4567', 'q1': _long}},
      'answered_at': status == 'open' ? null : '2026-11-21T10:00:00',
      'due_at': '2026-11-20T00:00:00',
      'review_note': status == 'returned' ? _long : null,
      'created_by': {'id': 44, 'name': 'منى السيد عبد العزيز'},
      'student': {'id': 812, 'name': 'عبد الرحمن محمد عبد الله الشريف'},
      'meeting': kind == 'meeting' ? {'id': 9, 'starts_at': '2026-11-25T08:00:00', 'mode': 'offline', 'location': 'مبنى الإدارة، الدور الثالث، مكتب 312'} : null,
    };

InboxPage _inbox({bool empty = false}) => InboxPage.fromJson({
      'tab': 'waiting',
      'counts': {'decide': 123, 'waiting': 45, 'done': 6},
      'items': empty
          ? []
          : [
              for (final s in ['ask', 'case', 'decision'])
                {
                  'id': '$s:31',
                  'source': s,
                  'source_id': 31,
                  'student': {'id': 812, 'name': 'عبد الرحمن محمد عبد الله الشريف الحسيني'},
                  'title_ar': 'طلب بيانات: $_long',
                  'title_en': 'Information request: $_long',
                  'at': '2026-11-21T10:00:00',
                  'status': s == 'ask' ? 'open' : 'under_review',
                  'can': {'accept': true, 'return': true, 'reject': true, 'meeting': true, 'ask': true},
                },
            ],
      'page': 1,
      'size': 1,
      'total': 3,
    });

Widget _requests({InboxPage? data, bool loading = false, String? error, String tab = 'waiting'}) => StudentRequestsView(
      data: data,
      loading: loading,
      error: error,
      tab: tab,
      openAsks: {31: StudentAsk.fromJson(_askJson(status: 'open'))},
      acting: const {'case:31'},
      now: DateTime.utc(2026, 11, 22),
      onTab: (_) {},
      onRetry: () {},
      onPage: (_) {},
      onOpen: (_) {},
      onAccept: (_) {},
      onReturn: (_) {},
      onReject: (_) {},
      onMeeting: (_) {},
      onAsk: (_) {},
    );

Widget _review(String status, {String kind = 'data', String? error}) => SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: AskReviewView(
        ask: StudentAsk.fromJson(_askJson(status: status, kind: kind)),
        note: TextEditingController(text: _long),
        error: error,
        now: DateTime.utc(2026, 11, 22),
        onAccept: () {},
        onReturn: () {},
        onRemind: () {},
        onCancel: () {},
      ),
    );

void main() {
  testWidgets('StudentAskView: every kind, full screen with a due date', (tester) async {
    for (final k in askKinds) {
      await expectNoLayoutErrors(tester, () => _sheet(k));
    }
  });

  testWidgets('StudentAskView: busy, error, missing loading / error / nothing missing', (tester) async {
    await expectNoLayoutErrors(tester, () => _sheet('meeting', busy: true, error: 'الطالب مشغول في هذا الوقت، اختر وقتاً آخر أو احجز رغم ذلك'));
    await expectNoLayoutErrors(tester, () => _sheet('data', loading: true));
    await expectNoLayoutErrors(tester, () => _sheet('documents', missingError: 'تعذّر تحميل ما ينقص الملف، تحقق من الاتصال وحاول مرة أخرى'));
    await expectNoLayoutErrors(tester, () => _sheet('documents', missing: StudentMissing.fromJson(const {})));
    await expectNoLayoutErrors(tester, () => _sheet('data', missing: StudentMissing.fromJson(const {'case_id': 5})));
  });

  testWidgets('StudentRequestsView: loading, error, empty tabs, full with an overdue row', (tester) async {
    await expectNoLayoutErrors(tester, () => _requests(loading: true));
    await expectNoLayoutErrors(tester, () => _requests(error: 'تعذّر تحميل طلبات الطلاب، تحقق من الاتصال وحاول مرة أخرى'));
    for (final tab in inboxTabs) {
      await expectNoLayoutErrors(tester, () => _requests(data: _inbox(empty: true), tab: tab));
    }
    await expectNoLayoutErrors(tester, () => _requests(data: _inbox()));
  });

  testWidgets('the overdue ask comes first and wears its badge', (tester) async {
    await tester.pumpWidget(layoutHost(_requests(data: _inbox())));
    await tester.pump();
    expect(find.byKey(const ValueKey('students.requests.row.ask:31.overdue')), findsOneWidget);
    expect(find.byKey(const ValueKey('students.requests.row.case:31.overdue')), findsNothing);
  });

  testWidgets('AskReviewView: answered, open, returned, a meeting, an error', (tester) async {
    await expectNoLayoutErrors(tester, () => _review('answered'));
    await expectNoLayoutErrors(tester, () => _review('open', error: 'تم تذكير الطالب خلال آخر 24 ساعة'));
    await expectNoLayoutErrors(tester, () => _review('returned'));
    await expectNoLayoutErrors(tester, () => _review('answered', kind: 'meeting'));
  });
}
