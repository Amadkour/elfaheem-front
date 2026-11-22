import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/admin/edu/edu_admin_api.dart';
import 'package:flutter_education_app/features/admin/edu/edu_levels_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

class _NoActions implements EduActions {
  @override
  dynamic noSuchMethod(Invocation i) {}
}

EduRow _r(int id, String ar, String en, {List<EduRow> children = const [], List<int> subjects = const [], int? parent, bool active = true}) =>
    EduRow(id: id, key: 'k$id', nameAr: ar, nameEn: en, children: children, subjectIds: subjects, parentId: parent, active: active);

final _tree = EduTree(
  country: const EduCountryRow(code: 'EG', nameAr: 'مصر', nameEn: 'Egypt', labels: {'1': ('محافظة', 'Governorate'), '2': ('مركز', 'District')}),
  stages: [
    _r(1, 'المرحلة الثانوية العامة الطويلة جداً', 'A very long general secondary stage name', children: [
      _r(11, 'الصف الأول الثانوي', 'First secondary', subjects: [100, 101]),
      _r(12, 'الصف الثاني', 'Second year', active: false),
    ]),
    _r(2, 'الجامعة', 'University'),
  ],
  subjects: [_r(100, 'الرياضيات', 'Mathematics'), _r(101, 'اللغة العربية', 'Arabic')],
  areas: [_r(200, 'القاهرة', 'Cairo'), _r(201, 'مدينة نصر', 'Nasr City', parent: 200)],
);

void main() {
  const countries = [EduCountryRow(code: 'EG', nameAr: 'مصر', nameEn: 'Egypt'), EduCountryRow(code: 'SA', nameAr: 'السعودية', nameEn: 'Saudi Arabia', active: false)];

  for (final tab in ['المراحل والصفوف', 'المواد', 'المناطق']) {
    testWidgets('education levels body, tab $tab: no layout errors', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(child: EduLevelsBody(countries: countries, country: 'EG', tree: _tree, actions: _NoActions())),
        act: (tester) async {
          final en = {'المراحل والصفوف': 'Stages & grades', 'المواد': 'Subjects', 'المناطق': 'Areas'}[tab]!;
          final f = find.byWidgetPredicate((w) => w is Text && (w.data == tab || w.data == en));
          if (f.evaluate().isNotEmpty) await tester.tap(f.first);
        },
      );
    });
  }

  testWidgets('loading state and the subject picker: no layout errors', (tester) async {
    await expectNoLayoutErrors(tester, () => EduLevelsBody(countries: countries, country: 'EG', tree: null, actions: _NoActions()));
    await expectNoLayoutErrors(tester, () => EduSubjectPicker(title: 'الصف', subjects: _tree.subjects, selected: const {100}, ar: true));
  });
}
