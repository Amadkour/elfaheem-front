// The "Change status" sheet, the undo confirm and the student's status card never overflow (contract §14 phase 2):
// StatusChangeView loading / error / no options / every option with every field shown and a blocking rule, the
// propose path with its error, UndoStatusView with an error, and MyStatusView full and calm.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/students/my_status_card.dart';
import 'package:flutter_education_app/features/org/students/student_status_models.dart';
import 'package:flutter_education_app/features/org/students/student_status_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _longNote = 'قدّم الطالب شهادة مرضية معتمدة من مستشفى الجامعة تفيد بحاجته إلى راحة تامة لمدة فصل دراسي كامل، مع موافقة ولي الأمر';

StudentStatus _status({bool options = true}) => StudentStatus.fromJson({
      'enrol_status': 'suspended',
      'enrol_until': '2027-09-01',
      'acad_standing': 'final_chance',
      'flags': [
        for (final k in ['struggling', 'special_case', 'transferred_in', 'conscripted', 'excuse_open', 'disciplinary_record', 'affiliated']) {'key': k},
      ],
      'options': [
        if (options)
          for (final k in decisionKeys)
            {
              'decision': k,
              'mode': k == 'suspend' ? 'propose' : 'decide',
              'needs': ['reason', 'decision_no', 'effective_to'],
              'body': k.startsWith('flag.') ? null : 'university_president',
              'danger': decisionDangerous.contains(k),
              'blocked': k == 'cancel' ? {'rule': 'suspension.max_years', 'text_ar': 'تجاوز الطالب الحد الأقصى لسنوات إيقاف القيد المسموح بها في لائحة الكلية', 'text_en': 'The student has passed the longest suspension the faculty\'s regulations allow'} : null,
            },
      ],
    });

Widget _view(String? picked, {bool loading = false, String? loadError, bool options = true, String? error, bool proposes = false, bool override = false}) {
  final s = _status(options: options);
  final o = picked == null ? null : s.option(picked);
  final d = o == null ? null : StatusDraft.forOption(o, current: s, today: DateTime(2026, 11, 21), reason: _longNote);
  if (d != null) {
    d.effectiveTo = DateTime(2027, 9, 1);
    d.decisionDate = DateTime(2026, 11, 18);
    d.accessUntil = DateTime(2027, 2, 19);
    d.override = override;
    d.dropCurrent = true;
  }
  return SingleChildScrollView(
    child: StatusChangeView(
      status: loading || loadError != null ? null : s,
      loading: loading,
      loadError: loadError,
      onRetry: () {},
      picked: picked,
      draft: d,
      note: TextEditingController(text: _longNote),
      decisionNo: TextEditingController(text: 'قرار مجلس الكلية رقم 12/2026 بجلسته رقم 4'),
      error: error,
      errorCode: error == null ? null : 'needs_body',
      block: o?.blocked,
      proposes: proposes || (o?.proposes ?? false),
      onPick: (_) {},
      onEdit: (_) {},
      onPickDate: (_) {},
      onClearDate: (_) {},
      onSubmit: () {},
      onPropose: error == null ? null : () {},
    ),
  );
}

void main() {
  testWidgets('StatusChangeView: loading, error, nothing open', (tester) async {
    await expectNoLayoutErrors(tester, () => _view(null, loading: true));
    await expectNoLayoutErrors(tester, () => _view(null, loadError: 'تعذّر تحميل حالة الطالب، تحقق من الاتصال وحاول مرة أخرى'));
    await expectNoLayoutErrors(tester, () => _view(null, options: false));
    await expectNoLayoutErrors(tester, () => _view(null));
  });

  testWidgets('StatusChangeView: every kind of change with all its fields', (tester) async {
    for (final k in ['suspend', 'dismiss_academic', 'withdraw', 'standing_override', 'flag.struggling', 'flag.conscripted']) {
      await expectNoLayoutErrors(tester, () => _view(k));
    }
  });

  testWidgets('StatusChangeView: a blocking rule with the override, and the propose fallback', (tester) async {
    await expectNoLayoutErrors(tester, () => _view('cancel', override: true));
    await expectNoLayoutErrors(tester, () => _view('reenrol', error: 'هذا التغيير يحتاج موافقة جهة أعلى: أرسله للاعتماد إلى مجلس الجامعة', proposes: false));
  });

  testWidgets('UndoStatusView', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: UndoStatusView(
          title: 'إيقاف القيد بقرار مجلس الكلية رقم 12/2026 اعتباراً من 21 نوفمبر 2026 حتى بداية العام الجامعي القادم',
          reason: TextEditingController(text: _longNote),
          error: 'يوجد تغيير أحدث على هذه الحالة: تراجع عنه أولاً',
          onSubmit: () {},
        ),
      ),
    );
    await expectNoLayoutErrors(tester, () => UndoStatusView(reason: TextEditingController(), busy: true));
  });

  testWidgets('MyStatusView: full and calm', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: MyStatusView(
          status: MyStatus.fromJson({
            'enrol_status': 'disc_suspended',
            'enrol_until': '2027-09-01',
            'acad_standing': 'final_chance',
            'flags': ['conscripted', 'excuse_open', 'transferred_in', 'affiliated', 'struggling'],
            'last': {'title_ar': 'إيقاف تأديبي لمدة فصل دراسي بقرار عميد الكلية', 'title_en': 'Disciplinary suspension for one term by the dean', 'reason': _longNote, 'decision_no': 'ع ك 33/2026', 'at': '2026-11-21T09:30:00'},
          }),
        ),
      ),
    );
    await expectNoLayoutErrors(tester, () => MyStatusView(status: MyStatus.fromJson({'enrol_status': 'enrolled', 'acad_standing': 'regular'})));
  });
}
