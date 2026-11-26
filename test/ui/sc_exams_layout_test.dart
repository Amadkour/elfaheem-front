// S-C exams (redesign): the exam list, its cards and the Review page at 320x640 and 1400x900, ar / en, text x1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/analytics/student/flags/student_flags_provider.dart';
import 'package:flutter_education_app/features/analytics/student/flags/student_flags_screen.dart';
import 'package:flutter_education_app/features/exams/legacy/student/sc_exam_widgets.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_list_screen.dart';
import 'package:flutter_education_app/features/exams/legacy/student/student_exam_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/redesign/sc_fakes.dart';
import 'layout_harness.dart';

void main() {
  testWidgets('the exam card holds its facts, deadline and button', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(children: [
          ScExamCard(
            title: 'اختبار قصير: قوانين نيوتن نيوتن نيوتن نيوتن',
            subtitle: Text('الفيزياء، أ. فهد المطيري'),
            subject: 'الفيزياء',
            facts: ['٢٠ دقيقة', '١٠ أسئلة', 'المحاولة ٢ من ٣'],
            foot: 'باقي ١٢ دقيقة',
            footTone: ScFootTone.live,
            actionLabel: 'كمّل',
            action: ScExamAction.hot,
            hot: true,
          ),
          ScReviewSummary(saved: 14, wrong: 9),
        ]),
      ),
    );
  });

  testWidgets('the exam list: hero, tabs and cards', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ChangeNotifierProvider(
        create: (_) => StudentExamProvider(api: ScFakeExamApi()),
        child: StudentExamListScreen(flagsApi: ScFakeFlagsApi(), showOffline: false),
      ),
      frames: 6,
    );
  });

  testWidgets('the review page and its empty state', (tester) async {
    for (final empty in [false, true]) {
      await expectNoLayoutErrors(
        tester,
        () => StudentFlagsScreen(
          courseNames: scCourseNames,
          provider: StudentFlagsProvider(api: ScFakeFlagsApi(empty: empty))..load(),
        ),
        frames: 6,
      );
    }
  });
}
