// Student lifecycle phase 7 (D-1400): the Students report's plain-values view through the layout harness (320×640 and
// 1400×900, ar / en, text × 1.3) — loading, error, empty, small and large data, and the programme / level table alone.
import 'package:flutter_education_app/features/org/students/student_report_models.dart';
import 'package:flutter_education_app/features/org/students/student_report_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/student_report_test.dart' show countsJson, reportJson;
import 'layout_harness.dart';

const _long = 'برنامج البكالوريوس في هندسة الحاسبات والتحكم الآلي والذكاء الاصطناعي — Bachelor of Computer and Control Engineering';

Map<String, dynamic> _large() {
  final j = reportJson();
  j['at_to'] = {
    'total': 123456,
    'enrolment': {
      for (final k in ['enrolled', 'suspended', 'postponed', 'disc_suspended', 'outside', 'withdrawn', 'cancelled', 'dismissed', 'transferred_out', 'graduated', 'deceased'])
        k: 9876,
    },
    'standing': {for (final k in ['regular', 'carrying', 'repeating', 'warning', 'final_chance']) k: 24691},
    'flags': {for (final k in ['struggling', 'special_case', 'transferred_in', 'conscripted', 'excuse_open', 'disciplinary_record', 'affiliated']) k: 1234},
    'attention': 45678,
    'movements': 99999,
  };
  j['movements'] = {
    'total': 99999,
    'by_dimension': {'enrolment': 50000, 'standing': 30000, 'flag': 19999},
    'by_via': {'auto': 40000, 'manual': 30000, 'request': 20000, 'undo': 5000, 'system': 4999, 'import': 12},
    'by_decision': [
      for (final k in ['suspend', 'postpone', 'resume', 'dismiss_academic', 'withdraw', 'transfer_out', 'final_chance', 'flag.struggling', 'unknown_decision_key_that_is_long'])
        {'key': k, 'count': 1111},
    ],
  };
  j['top_reasons'] = [for (final k in ['military', 'illness', 'abroad_work', 'fees', 'gpa', 'chances_exhausted', 'max_duration', 'own_request', 'other', 'mystery']) {'code': k, 'count': 321}];
  j['pending'] = {
    'total': 777,
    'by_kind': {'student_status': 777},
    'by_decision': [{'key': 'dismiss_academic', 'count': 700}, {'key': 'final_chance', 'count': 77}],
  };
  j['by_programme'] = [
    for (var i = 0; i < 12; i++)
      {'program': i == 11 ? null : {'id': i + 1, 'code': 'PRG-LONG-CODE-$i', 'name_ar': _long, 'name_en': _long}, ...countsJson(total: 100000 + i)},
  ];
  j['by_level'] = [
    for (var i = 0; i < 8; i++) {'level': i == 7 ? null : '$i', 'label_ar': 'المستوى $i', 'label_en': 'Level $i', ...countsJson(total: 99999)},
  ];
  return j;
}

void main() {
  final period = last30Days(DateTime(2026, 11, 21));
  final term = ReportPeriod(ReportPeriodKind.custom, DateTime(2026, 9, 20), DateTime(2026, 11, 21), termLabel: 'الفصل الدراسي الأول 2026/2027 — First term');

  testWidgets('loading, error, empty', (tester) async {
    await expectNoLayoutErrors(tester, () => StudentReportView(report: null, period: period, loading: true));
    await expectNoLayoutErrors(tester, () => StudentReportView(report: null, period: period, error: 'Could not load the report', onRetry: () {}));
    await expectNoLayoutErrors(tester, () => StudentReportView(report: const StudentReport(), period: period, onPeriod: (_) {}));
  });

  testWidgets('small data, refreshing with an error line', (tester) async {
    final r = StudentReport.fromJson(reportJson());
    await expectNoLayoutErrors(tester, () => StudentReportView(report: r, period: period, onPeriod: (_) {}));
    await expectNoLayoutErrors(tester, () => StudentReportView(report: r, period: term, loading: true, error: 'Could not refresh', onRetry: () {}, onChangeDates: () {}));
  });

  testWidgets('a period with no changes', (tester) async {
    final j = reportJson()
      ..['movements'] = {'total': 0}
      ..['pending'] = {'total': 0}
      ..['top_reasons'] = [];
    final r = StudentReport.fromJson(j);
    await expectNoLayoutErrors(tester, () => StudentReportView(report: r, period: period));
  });

  testWidgets('large data', (tester) async {
    final r = StudentReport.fromJson(_large());
    await expectNoLayoutErrors(tester, () => StudentReportView(report: r, period: term, onPeriod: (_) {}, onChangeDates: () {}));
  });
}
