// The Students list and the missing-data sheet never overflow (contract §14 phase 1): StudentsPageView with 0, 1 and
// 30 rows and long names, its loading and error states, and MissingDataView in each of its states.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/students/students_missing_sheet.dart';
import 'package:flutter_education_app/features/org/students/students_models.dart';
import 'package:flutter_education_app/features/org/students/students_page.dart';
import 'package:flutter_education_app/features/org/students/students_parts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _longAr = 'عبد الرحمن محمد عبد العزيز إبراهيم السيد الشربيني أبو العلا';
const _longEn = 'Abdelrahman Mohamed Abdelaziz Ibrahim Elsayed Elsherbiny Abouelela';

const _chips = [
  {'dimension': 'standing', 'value': 'regular'},
  {'dimension': 'intake', 'value': 'missing'},
  {'dimension': 'enrolment', 'value': 'disc_suspended'},
  {'dimension': 'member', 'value': 'pending'},
  {'dimension': 'enrolment', 'value': 'graduated'},
  {'dimension': 'standing', 'value': 'final_chance'},
];

StudentRow _row(int i, {bool long = false}) => StudentRow.fromJson({
      'user': {'id': 800 + i, 'name': long ? _longAr : 'طالب $i', 'name_en': long ? _longEn : 'Student $i', 'image_url': null},
      'member_id': 5000 + i,
      'member_status': 'active',
      'student_code': i.isEven ? '2026${1000 + i}' : null,
      'program': i % 3 == 0 ? null : {'id': 7, 'code': 'CS', 'name_ar': 'علوم الحاسب والذكاء الاصطناعي وتطبيقاته', 'name_en': 'Computer Science and Artificial Intelligence'},
      'level': i % 4 == 0 ? null : '${1 + i % 4}',
      'enrol_status': 'enrolled',
      'acad_standing': 'carrying',
      'flags': i % 2 == 0 ? ['transferred_in', 'struggling', 'special_case'] : <String>[],
      'missing_count': i % 3 == 0 ? null : (i % 5) * 4,
      'chip': _chips[i % _chips.length],
    });

StudentsPageData _data(int n, {bool long = false}) => StudentsPageData(
      total: n == 30 ? 1840 : n,
      page: 1,
      size: 30,
      pages: n == 30 ? 62 : 1,
      summary: const StudentsSummary(enrolled: 1712, missing: 96, awaiting: 41, attention: 58, suspended: 12),
      can: const StudentsCan(add: true, import: true),
      items: [for (var i = 0; i < n; i++) _row(i, long: long || i == 0)],
    );

Widget _view(StudentsPageData? d, {bool loading = false, String? error, StudentsQuery query = const StudentsQuery()}) => StudentsPageView(
      data: d,
      loading: loading,
      error: error,
      query: query,
      onRetry: () {},
      onSearch: (_) {},
      onChip: (_) {},
      onEnrol: (_) {},
      onSort: (_) {},
      onPage: (_) {},
      onClearFilters: () {},
      onAwaiting: () {},
      onOpen: (_) {},
      onMissing: (_) {},
      onAdd: () {},
      onImport: () {},
    );

MissingItem _item(String key, {String? status, bool long = false}) => MissingItem(
      key: key,
      labelAr: long ? 'شهادة إتمام الخدمة العسكرية أو الإعفاء منها أو تأجيلها (نموذج 2 جند)' : 'نموذج 2 جند',
      labelEn: long ? 'Certificate of completed, exempted or postponed military service (Military form 2)' : 'Military form 2',
      whyAr: 'مطلوب للطلاب المصريين الذكور الذين تزيد أعمارهم عن 18 سنة',
      whyEn: 'Required for male Egyptian students over 18 years old',
      dueAt: DateTime.utc(2026, 12, 15),
      status: status,
      kind: 'phone',
    );

void main() {
  test('the standing shows beside another chip only when it is not regular', () {
    expect(studentExtraStanding(const StudentChip('intake', 'missing'), 'warning'), 'warning');
    expect(studentExtraStanding(const StudentChip('intake', 'missing'), 'regular'), isNull);
    expect(studentExtraStanding(const StudentChip('standing', 'warning'), 'warning'), isNull);
    expect(studentExtraStanding(const StudentChip('enrolment', 'suspended'), null), isNull);
  });

  setUp(() => AppConfig.lang = 'ar');

  testWidgets('StudentsPageView: 0 rows', (t) => expectNoLayoutErrors(t, () => _view(_data(0))));
  testWidgets('StudentsPageView: 0 rows, filtered', (t) => expectNoLayoutErrors(t, () => _view(_data(0), query: const StudentsQuery(q: 'zzz', chip: 'missing'))));
  testWidgets('StudentsPageView: 1 row, long name', (t) => expectNoLayoutErrors(t, () => _view(_data(1, long: true))));
  testWidgets('StudentsPageView: 30 rows', (t) => expectNoLayoutErrors(t, () => _view(_data(30))));
  testWidgets('StudentsPageView: 30 long rows, a chip and a status filter on',
      (t) => expectNoLayoutErrors(t, () => _view(_data(30, long: true), query: const StudentsQuery(chip: 'attention', enrol: 'transferred_out'))));
  testWidgets('StudentsPageView: first load', (t) => expectNoLayoutErrors(t, () => _view(null, loading: true)));
  testWidgets('StudentsPageView: reloading over data', (t) => expectNoLayoutErrors(t, () => _view(_data(30), loading: true)));
  testWidgets('StudentsPageView: error', (t) => expectNoLayoutErrors(t, () => _view(null, error: 'قسم الطلاب غير مفعّل لهذه المؤسسة')));
  testWidgets('StudentsPageView: read only (no add, no import, no awaiting)',
      (t) => expectNoLayoutErrors(t, () => StudentsPageView(data: _data(30), onSearch: (_) {}, onEnrol: (_) {})));

  testWidgets('the row card and its parts', (t) => expectNoLayoutErrors(
        t,
        () => ListView(padding: const EdgeInsets.all(16), children: [
          for (var i = 0; i < 6; i++) StudentRowCard(row: _row(i, long: true), onTap: () {}, onMissing: () {}),
          const MissingBadge(count: 123),
          const StudentFlagChips([...flagKeys, ...derivedFlagKeys]),
        ]),
      ));

  testWidgets('MissingDataView: every group, long labels', (t) => expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
          child: MissingDataView(
            data: StudentMissing(
              caseId: 3310,
              dueAt: DateTime.utc(2026, 12, 15),
              photos: [_item('photo', long: true)],
              documents: [_item('military_2', status: 'deferred', long: true), _item('birth', status: 'rejected'), _item('school')],
              fields: [_item('guardian_phone', long: true)],
            ),
            onOpenFile: () {},
          ),
        ),
      ));
  testWidgets('MissingDataView: nothing missing, no case, loading, error', (t) => expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
          child: Column(children: [
            MissingDataView(data: const StudentMissing(caseId: 1), onOpenFile: () {}),
            const MissingDataView(data: StudentMissing()),
            const MissingDataView(loading: true),
            MissingDataView(error: 'الطالب غير موجود في هذه المؤسسة', onRetry: () {}),
          ]),
        ),
      ));
}
