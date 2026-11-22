// The study rules never overflow (contract §14 phase 5, F1): StudyRulesView for credit hours, years and both, read
// only and as a programme's own rules; the scale editor with a ready scale, a custom one and a broken one; the
// bylaw presets; the programme picker; the Students page's Settings chooser. Plus the pure helpers: a preset fills
// only what it sets, a ready scale brings its pass mark, a programme stores only what differs.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/students/student_rules_pages.dart';
import 'package:flutter_education_app/features/org/students/student_scale_editor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Map<String, dynamic> _g(String l, num min, num pts, String ar, String en) => {'letter': l, 'min': min, 'points': pts, 'name_ar': ar, 'name_en': en};

/// The server's DEFAULT_RULES (registrar/policy.py), the lifecycle blocks only.
Map<String, dynamic> usualRules() => {
      'grade_scale': [
        _g('A', 90, 4.0, 'ممتاز', 'Excellent'),
        _g('B', 75, 3.0, 'جيد جدا', 'Very good'),
        _g('C', 60, 2.0, 'جيد', 'Good'),
        _g('D', 50, 1.0, 'مقبول', 'Pass'),
        _g('F', 0, 0.0, 'راسب', 'Fail'),
      ],
      'pass_letter': 'D',
      'scale_preset': 'gpa4_default',
      'pass': {'course_min_pct': 50, 'final_min_pct': null},
      'graduation': {'min_cgpa': 2.0},
      'standing': {
        'probation_below': 2.0, 'probation_after_credits': 12, 'honours_term_gpa': 3.5, 'honours_min_credits': 12,
        'dismiss_after_probations': 0, 'warning_basis': 'cgpa', 'skip_first_term': false, 'reset_on_recover': true,
        'warning_load_max': 12,
      },
      'retake': {'allowed_below': 'C', 'max_attempts': 3, 'count': 'latest', 'improvement_max': 5, 'improvement_count': 'best', 'failed_cap_letter': null},
      'traditional': {
        'max_carry': 2, 'max_carry_specialised': null, 'years_inside': 2, 'outside_chances': {'first': 0, 'middle': 1, 'final': 3},
        'five_year_rule': true, 'repeat_cap_letter': null, 'second_round': false, 'promotion_basis': 'carry_limit', 'promotion_min': null,
      },
      'dismissal': {'consecutive_warnings': 0, 'early_gpa': null, 'cgpa_after': null, 'max_years': null, 'unregistered_terms': null},
      'final_chance': {'terms': 2, 'summer': true, 'min_credits_pct': 75},
      'study': {'summer': true, 'preparatory_year': false, 'makeup_term': false},
      'calendar': {'registration_days': 21},
    };

/// Every rule switched on with long values (the widest rows).
Map<String, dynamic> busyRules() {
  var r = usualRules();
  r = rulesSet(r, 'dismissal', {
    'consecutive_warnings': 6, 'early_gpa': {'below': 1.0, 'terms': 3}, 'cgpa_after': {'below': 1.5, 'term': 4}, 'max_years': 10,
    'unregistered_terms': {'consecutive': 2, 'total': 3},
  });
  r = rulesSet(r, 'traditional', {'max_carry_specialised': 1, 'promotion_basis': 'min_gpa', 'promotion_min': 2.25, 'repeat_cap_letter': 'D'});
  r = rulesSet(r, 'pass', {'course_min_pct': null, 'final_min_pct': 40});
  r = rulesSet(r, 'retake', {'improvement_max': null, 'failed_cap_letter': 'B'});
  return {...r, 'scale_preset': 'custom'};
}

const _scales = [
  ScalePreset(key: 'gpa4_default', labelAr: 'نقاط من 4 (الافتراضي)', labelEn: '4-point (default)', passLetter: 'D'),
  ScalePreset(
    key: 'gpa5',
    labelAr: 'نقاط من 5 (آداب بني سويف)',
    labelEn: '5-point (Beni-Suef Arts)',
    pointsMax: 5,
    passLetter: 'D-',
    gradeScale: [
      {'letter': 'A', 'min': 85, 'points': 5.0},
      {'letter': 'D-', 'min': 50, 'points': 1.0},
      {'letter': 'F', 'min': 0, 'points': 0.0},
    ],
  ),
  ScalePreset(key: 'traditional_names', labelAr: 'التقديرات (ممتاز … ضعيف جدا)', labelEn: 'Grade names (Excellent … Very weak)'),
];

final _presets = [
  RulePreset.fromJson({
    'key': 'law49_traditional_2015',
    'label_ar': 'نظام الفرق الدراسية (قانون 49 لسنة 1972، المادة 80 بعد 2015)',
    'label_en': 'Traditional years (Law 49/1972, art. 80 as replaced in 2015)',
    'system': 'traditional',
    'review_with_bylaw': false,
    'note_ar': 'سنتان في الفرقة، ثم الامتحان من الخارج: لا فرص للفرقة الأولى، فرصة للفرق المتوسطة، وثلاث للفرقتين قبل النهائية والنهائية.',
    'note_en': 'Two years inside a year, then exams from outside: none for the first year, one for the middle years, three for the final years.',
    'sources': ['S3', 'S5', 'S6', 'S7', 'S9', 'S12'],
    'rules': {
      ...usualRules(),
      'scale_preset': 'traditional_names',
      'grade_scale': [_g('A', 85, 4.0, 'ممتاز', 'Excellent'), _g('D', 50, 1.0, 'مقبول', 'Pass'), _g('F', 0, 0, 'ضعيف', 'Weak')],
      'pass_letter': 'D',
      'pass': {'course_min_pct': 50, 'final_min_pct': null},
    },
    'overrides': {
      'scale_preset': 'traditional_names',
      'traditional': {'repeat_cap_letter': 'D'},
      'study': {'summer': false},
    },
  }),
  RulePreset.fromJson({
    'key': 'private_credit',
    'label_ar': 'جامعة خاصة — ساعات معتمدة (راجعها مع لائحتك)',
    'label_en': 'Private university — credit hours (review with your bylaw)',
    'system': 'credit_hour',
    'review_with_bylaw': true,
    'note_en': 'An editable starting point: review it with your bylaw before you rely on it.',
    'sources': ['S23', 'S99'],
  }),
];

void main() {
  testWidgets('StudyRulesView · credit hours, the usual values, editable', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
              child: StudyRulesView(
                rules: usualRules(),
                yearsCount: 4,
                scales: _scales,
                inherited: true,
                onChanged: (_) {},
                onPresets: () {},
                onEditScale: () {},
                onStudySystem: () {},
                onProgrammes: () {},
              ),
            ));
  });

  testWidgets('StudyRulesView · both systems, every rule on, read only', (tester) async {
    await expectNoLayoutErrors(
        tester, () => SingleChildScrollView(child: StudyRulesView(rules: busyRules(), system: 'mixed', scales: _scales, onEditScale: () {})));
  });

  testWidgets('StudyRulesView · years, a programme with its own values', (tester) async {
    final own = rulesSet(usualRules(), 'traditional', {'max_carry': 3});
    await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
              child: StudyRulesView(rules: own, system: 'traditional', programme: true, institution: usualRules(), onChanged: (_) {}),
            ));
  });

  testWidgets('StudyRulesView · an empty rule set (an old server) still draws', (tester) async {
    await expectNoLayoutErrors(tester, () => const SingleChildScrollView(child: StudyRulesView(rules: {}, system: 'mixed')));
  });

  testWidgets('StudyRulesView · a switch edits its block and keeps the rest', (tester) async {
    final prev = AppConfig.lang;
    addTearDown(() => AppConfig.lang = prev);
    AppConfig.lang = 'en';
    Map<String, dynamic>? got;
    await tester.pumpWidget(layoutHost(SingleChildScrollView(child: StudyRulesView(rules: usualRules(), onChanged: (r) => got = r))));
    await tester.pump(const Duration(milliseconds: 100));
    final tile = find.byKey(const ValueKey('rules-switch-dismissal.max_years'));
    await tester.ensureVisible(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();
    expect(got?['dismissal']['max_years'], 8);
    expect(got?['final_chance'], usualRules()['final_chance']);
  });

  testWidgets('ScaleEditorView · a ready scale, editable', (tester) async {
    await expectNoLayoutErrors(
        tester, () => SingleChildScrollView(child: ScaleEditorView(value: ScaleEdit.ofRules(usualRules()), scales: _scales, onChanged: (_, _) {})));
  });

  testWidgets('ScaleEditorView · a custom, broken scale, read only', (tester) async {
    final broken = ScaleEdit(rows: [_g('A+', 95, 4.0, 'ممتاز مرتفع جداً جداً', 'Outstanding with distinction'), _g('', 99.5, 3.75, '', ''), _g('F', 10, 0, '', '')], passLetter: 'X', presetKey: 'custom');
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: ScaleEditorView(value: broken, scales: _scales)));
  });

  testWidgets('RulePresetsView · notes, sources, review with your bylaw', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: RulePresetsView(presets: _presets, system: 'credit_hour', onPick: (_) {})));
  });

  testWidgets('ProgrammeListView and the Settings chooser', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
              child: Column(children: [
                ProgrammeListView(items: const [
                  ProgrammeRef(id: 1, nameAr: 'هندسة الحاسبات والتحكم الآلي ونظم المعلومات', nameEn: 'Computer and Control Engineering and Information Systems', code: 'CCE'),
                  ProgrammeRef(id: 2, code: 'LAW'),
                ], onPick: (_) {}),
                const ProgrammeListView(items: [], onPick: _noop),
                StudentSettingsChooserView(onPick: (_) {}),
              ]),
            ));
  });

  test('a preset fills only what it sets, with its scale and pass mark', () {
    final before = rulesSet(usualRules(), 'traditional', {'max_carry': 3});
    final out = rulesWithPreset(before, _presets.first);
    expect(out['scale_preset'], 'traditional_names');
    expect((out['grade_scale'] as List).length, 3);
    expect(out['traditional']['repeat_cap_letter'], 'D');
    expect(out['traditional']['max_carry'], 3);
    expect(out['study']['summer'], false);
    expect(out['study']['preparatory_year'], false);
    expect(out['calendar'], usualRules()['calendar']);
    expect(out['pass']['course_min_pct'], 50);
  });

  test('a ready scale brings its pass mark; a custom one keeps it', () {
    final five = rulesWithScale(usualRules(), ScaleEdit.ofPreset(_scales[1]));
    expect(five['pass_letter'], 'D-');
    expect(five['pass']['course_min_pct'], 50.0);
    final custom = rulesWithScale(rulesSet(usualRules(), 'pass', {'course_min_pct': 60}), ScaleEdit.ofRules(usualRules()).withPass('C'));
    expect(custom['scale_preset'], 'custom');
    expect(custom['pass']['course_min_pct'], 60);
  });

  test('scaleProblem: order, the last grade at 0, the pass letter', () {
    final ok = ScaleEdit.ofRules(usualRules());
    expect(scaleProblem(ok), isNull);
    expect(scaleProblem(ok.withRow(1, {'min': 95})), isNotNull);
    expect(scaleProblem(ok.withRow(4, {'min': 5})), isNotNull);
    expect(scaleProblem(ok.withPass('Z')), isNotNull);
    expect(scaleProblem(ok.withoutRow(3).withRowAdded()), isNotNull); // the new row has no letter yet
  });

  test('removing the pass grade moves the pass mark to the grade above it, never to the top', () {
    final ok = ScaleEdit.ofRules(usualRules());
    expect(ok.withoutRow(3).passLetter, 'C', reason: 'D was the lowest pass: C is now');
    expect(ok.withoutRow(4).passLetter, 'D', reason: 'removing another grade keeps it');
    final topPass = ok.withPass('A').withoutRow(0);
    expect(topPass.passLetter, '');
    expect(scaleProblem(topPass), isNotNull, reason: 'no passing grade left: the editor asks for one');
  });

  test('a programme stores only what differs from the institution', () {
    final inst = usualRules();
    final prog = rulesSet(rulesSet(inst, 'traditional', {'max_carry': 3}), 'study', {'summer': false});
    final own = programmeOverrides(inst, prog);
    expect(own.keys.toSet(), {'traditional', 'study'});
    expect(own['traditional'], {'max_carry': 3});
    expect(overrideCount(own), 2);
    expect(programmeOverrides(inst, rulesSet(inst, 'retake', {'improvement_max': 1})), isEmpty);
  });
}

void _noop(ProgrammeRef _) {}
