// S-C (redesign) plain-value pieces: the hand-in sheet, the offline steps, the score card, the course bar and ring
// tile, the inbox hero and the announcements lines, at 320x640 and 1400x900, ar / en, text x1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/analytics/student/student_analytics_screen.dart' show ScCourseBar;
import 'package:flutter_education_app/features/analytics/student/student_course_analytics_screen.dart' show ScRingTile;
import 'package:flutter_education_app/features/exams/exam_result_screen.dart' show ExamScoreCard;
import 'package:flutter_education_app/features/exams/exam_taking_screen.dart' show ExamSubmitSheet, ExamOptionTile;
import 'package:flutter_education_app/features/exams/offline/offline_exam_core.dart' show OfflineStage;
import 'package:flutter_education_app/features/exams/offline/offline_exam_screen.dart' show OfflineStepsView;
import 'package:flutter_education_app/features/messaging/chat/chat_page.dart' show ScAnnouncementsBanner, ScPrivateReplyNote;
import 'package:flutter_education_app/features/messaging/inbox/inbox_page.dart' show ScInboxHero;
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void main() {
  testWidgets('S-C pieces never overflow', (tester) async {
    await expectNoLayoutErrors(tester, () => const AppAreaScope(
          area: AppArea.exam,
          child: SingleChildScrollView(
            child: Column(children: [
              ExamSubmitSheet(answered: 18, left: 1, firstLeft: 19, remainingSeconds: 1920),
              ExamOptionTile(text: 'ثمانية وأربعون وحدة مربعة تقريباً بعد التقريب', mark: 'ب', selected: true),
              ExamScoreCard(percentage: 88, score: '44', maxScore: '50', passed: true),
              OfflineStepsView(stage: OfflineStage.waitingToSync),
            ]),
          ),
        ));
  });

  testWidgets('S-C analysis pieces never overflow', (tester) async {
    await expectNoLayoutErrors(tester, () => const AppAreaScope(
          area: AppArea.me,
          child: SingleChildScrollView(
            child: Column(children: [
              ScCourseBar(title: 'الكيمياء العضوية للصف الثاني الثانوي', value: 32, needsPush: true),
              Row(children: [
                Expanded(child: ScRingTile(label: 'تقدّمك', value: 64, tone: KitTone(Colors.orange, Colors.white, Colors.brown))),
              ]),
            ]),
          ),
        ));
  });

  testWidgets('S-C inbox hero never overflows', (tester) async {
    await expectNoLayoutErrors(tester, () => const AppAreaScope(
          area: AppArea.chat, child: SingleChildScrollView(child: ScInboxHero(waiting: 4, late: 1))));
  });

  testWidgets('S-C announcement lines never overflow', (tester) async {
    await expectNoLayoutErrors(tester, () => const AppAreaScope(
          area: AppArea.chat, child: Column(children: [ScAnnouncementsBanner(), ScPrivateReplyNote()])));
  });
}
