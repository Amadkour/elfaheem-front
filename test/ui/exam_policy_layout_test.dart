// The super admin's exam settings (D-1130): the whole body — stat cards, defaults, limits, the three method groups and
// the related pages — with no overflow at 320 and 1400 wide, Arabic and English, text at 130 %.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/admin/admin_exam_policy_page.dart';
import 'package:flutter_education_app/features/exams/exam_policy.dart';
import 'package:flutter_education_app/features/org/org_exam_policy_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _methods = [
  ExamMethod(key: 'exam.auto_create', group: 'create', title: 'AI question generation', about: 'Writes the questions from the course documents.', on: true),
  ExamMethod(key: 'exam.google_forms_import', group: 'create', title: 'Import from Google Forms', about: 'Brings a form in.', on: false),
  ExamMethod(key: 'exam.omr', group: 'create', title: 'Paper exams with bubble sheets', about: '', on: true, partial: true),
  ExamMethod(
      key: 'exam.auto_grade',
      group: 'grade',
      title: 'Automatic grading of written answers, a long name that wraps',
      about: 'Off leaves every one for the teacher.',
      on: true),
  ExamMethod(key: 'exam.results.import', group: 'results', title: 'Import marks from Excel', about: 'Each student total from a file.', on: true),
];

void main() {
  testWidgets('exam settings body: no overflow anywhere', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: ExamPolicyBody(
          policy: const ExamPolicy(maxDurationMinutes: 180, attemptsCap: 3, maxAttempts: 2, highStakes: true, resultsPolicy: 'when_published'),
          methods: _methods,
          busy: const {'exam.omr'},
          links: [(Icons.grid_on_rounded, 'Bubble sheet types', 'The sheet library and approving the sheets teachers send', () {})],
          onChanged: (_) {},
          onToggle: (_, _) {},
        ),
      ),
    );
  });

  test('a tighter limit pulls the defaults inside it', () {
    final p = fitPolicyDefaults(const ExamPolicy(maxAttempts: 0, resultsView: 'answers_key', durationMinutes: 90)
        .copyWith(allowUnlimitedAttempts: false, allowAnswerKey: false, attemptsCap: 3, maxDurationMinutes: 60));
    expect(p.maxAttempts, 3);
    expect(p.resultsView, 'answers');
    expect(p.durationMinutes, 60);
  });

  testWidgets('organization exam policy body: no overflow anywhere', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: OrgExamPolicyBody(
          platform: const ExamPolicy(maxDurationMinutes: 180, attemptsCap: 3, allowAnswerKey: false),
          limits: const OrgExamLimits(maxDuration: 90, noUnlimited: true),
          methods: [
            OrgExamMethod(method: _methods[0], platformOn: true, on: true),
            OrgExamMethod(method: _methods[1], platformOn: false, on: true),
            OrgExamMethod(method: _methods[3], platformOn: true, on: false, inheritedOff: true),
            OrgExamMethod(method: _methods[4], platformOn: true, on: false),
          ],
          onLimits: (_) {},
          onMethod: (_, _) {},
        ),
      ),
    );
  });

  test('organization limits: follow the platform = null, the body sends every key', () {
    final l = OrgExamLimits.fromJson(const {'max_attempts': 2, 'allow_answer_key': false});
    expect(l.maxDuration, isNull);
    expect(l.toJson(), {'max_duration_minutes': null, 'max_attempts': 2, 'max_questions': null, 'allow_unlimited_attempts': null, 'allow_answer_key': false});
    expect(l.copy(maxAttempts: () => null).maxAttempts, isNull);
    const m = OrgExamMethod(method: ExamMethod(key: 'exam.omr', group: 'create', title: 'x', about: '', on: true), platformOn: false, on: true);
    expect(m.editable, isFalse);
  });
}
