// The join flow (D-1323): every step at 320×640 and 1400×900, Arabic and English, text ×1.3, for each role.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/core/edu/edu_countries.dart';
import 'package:flutter_education_app/features/auth/register_levels_step.dart' show TeachingLevel;
import 'package:flutter_education_app/features/onboarding/join/join_draft.dart';
import 'package:flutter_education_app/features/onboarding/join/join_steps.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

final _catalog = EduCountryCatalog.fromJson({
  'country': 'EG',
  'stages': [
    for (var s = 1; s <= 4; s++)
      {
        'id': s,
        'key': 'stage$s',
        'name_ar': 'المرحلة الدراسية الطويلة جدًا رقم $s',
        'name_en': 'A rather long study stage name number $s',
        'contact_only': s == 4,
        'has_grades': s != 4,
        'grades': [
          if (s != 4)
            for (var g = 1; g <= 6; g++)
              {
                'id': s * 10 + g,
                'key': 'g$g',
                'name_ar': 'الصف $g',
                'name_en': 'Grade $g',
                'tracks': g == 6
                    ? [
                        {'key': 'sci', 'name_ar': 'علمي', 'name_en': 'Science'},
                        {'key': 'lit', 'name_ar': 'أدبي', 'name_en': 'Literature'},
                      ]
                    : const [],
              },
        ],
      },
  ],
});

const _countries = [
  EduCountry(code: 'EG', nameAr: 'مصر', nameEn: 'Egypt'),
  EduCountry(code: 'SA', nameAr: 'المملكة العربية السعودية', nameEn: 'Saudi Arabia'),
  EduCountry(code: 'AE', nameAr: 'الإمارات العربية المتحدة', nameEn: 'United Arab Emirates'),
];

const _area1 = EduArea(id: 5, key: 'cai', nameAr: 'محافظة القاهرة الكبرى', nameEn: 'Greater Cairo Governorate', hasChildren: true);
const _area2 = EduArea(id: 51, key: 'nc', nameAr: 'مدينة نصر الجديدة', nameEn: 'Nasr City New District', level: 2);

JoinDraft _draft(String role, {bool filled = false}) => JoinDraft(
      role: role,
      country: 'EG',
      stageId: filled ? 3 : null,
      gradeId: filled ? 36 : null,
      trackKey: filled ? 'sci' : null,
      teachingLevels: filled && role == 'teacher' ? [const TeachingLevel(1), const TeachingLevel(2, 23), const TeachingLevel(3, 36)] : null,
      delivery: filled ? 'in_person' : null,
      area1: filled ? _area1 : null,
      area2: filled ? _area2 : null,
      address: filled ? '12 شارع عباس العقاد، الدور الثالث، بجوار المكتبة الكبيرة' : '',
      name: filled ? 'عبد الرحمن محمد عبد الله الطويل' : '',
      phone: filled ? '+20 100 123 4567' : '',
      childCode: filled ? 'ABCD-1234' : '',
    );

Widget _view(JoinStep step, String role, {bool filled = true}) {
  final d = _draft(role, filled: filled);
  return JoinFlowView(
    step: step,
    draft: d,
    countries: _countries,
    catalog: _catalog,
    onEdit: (f) => f(),
    onBack: () {},
    onNext: () {},
    onSkip: () {},
    onGoTo: (_) {},
    onSecondary: () {},
    onLinkChild: role == 'parent' ? () {} : null,
    loadAreas: (parent) async => parent == null ? [_area1] : [_area2],
    address: TextEditingController(text: d.address),
    name: TextEditingController(text: d.name),
    phone: TextEditingController(text: d.phone),
    childCode: TextEditingController(text: d.childCode),
  );
}

void main() {
  for (final role in kJoinRoles) {
    for (final step in JoinStep.values) {
      testWidgets('join $role · ${step.name}: no layout errors', (tester) async {
        await expectNoLayoutErrors(tester, () => _view(step, role), scaffold: false);
      });
    }
  }

  testWidgets('join · empty answers and a loading catalog: no layout errors', (tester) async {
    await expectNoLayoutErrors(tester, () => _view(JoinStep.levels, 'student', filled: false), scaffold: false);
    await expectNoLayoutErrors(
      tester,
      () => JoinFlowView(
        step: JoinStep.levels,
        draft: _draft('student'),
        catalogLoading: true,
        onEdit: (f) => f(),
        onBack: () {},
        onNext: () {},
        loadAreas: (_) async => const [],
        address: TextEditingController(),
        name: TextEditingController(),
        phone: TextEditingController(),
        childCode: TextEditingController(),
      ),
      scaffold: false,
    );
  });

  testWidgets('join · the area sheet opens without layout errors', (tester) async {
    await expectNoLayoutErrors(tester, () => _view(JoinStep.area, 'student', filled: false), scaffold: false,
        act: (t) async {
      final tile = find.byIcon(Icons.location_on_outlined).first;
      await t.ensureVisible(tile);
      await t.pump();
      await t.tap(tile);
    });
  });

  test('an online learner skips the area step; filters follow CONTRACT §4', () {
    final d = _draft('student', filled: true);
    expect(joinStepsFor(d), contains(JoinStep.area));
    expect(d.filters, {'country': 'EG', 'stage_id': 3, 'grade_id': 36, 'delivery': 'in_person', 'area_id': 51});
    d.delivery = 'online';
    expect(joinStepsFor(d), isNot(contains(JoinStep.area)));
    final back = JoinDraft.fromJson(d.toJson());
    expect(back.area?.id, 51);
    expect(back.studyProfile.gradeId, 36);
  });
}
