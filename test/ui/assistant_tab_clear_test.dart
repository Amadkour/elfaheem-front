// Round 3 of the paper-exam e2e (I3_e8_results_ar_phone): at 390 px the floating assistant's docked tab sat on the
// first result card's score and percent. The tab keeps its 44 dp touch target, but only its face at the screen edge
// is drawn ([appAssistantTabFace]: the 16 dp page gutter + at most 10 dp of a card's padding), so no text or icon of
// a dense list's cards is ever under it — whatever the scroll position, at the END side in both directions.
//
// The lists checked are the dense ones of the exam pages at 390 px: the paper-exam results (grade cards, question
// statistics), the student's course exam cards and the teacher hub's engine rows.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/features/shared/exam_engine/engine_exams_section.dart' show EngineExamCard;
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_results_parts.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review.dart';
import 'package:flutter_education_app/features/shared/rag/app_assistant.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

Map<String, dynamic> _p(String name) => Map<String, dynamic>.from(
    (jsonDecode(File('test/fixtures/payloads/omr_review/$name.json').readAsStringSync()) as Map)['payload'] as Map);

void main() {
  setUp(() {
    AppConfig.lang = 'ar';
    SharedPreferences.setMockInitialValues({});
  });

  /// The width the docked tab DRAWS from the screen edge it is docked to.
  Future<double> faceWidth(WidgetTester tester, {required bool left}) async {
    await tester.pumpWidget(layoutHost(Align(alignment: left ? Alignment.centerLeft : Alignment.centerRight,
        child: AppAssistantEdgeTab(onLeftSide: left, onTap: () {})), scale: 1));
    final tab = tester.getRect(find.byType(AppAssistantEdgeTab));
    final face = tester.getRect(find.descendant(of: find.byType(AppAssistantEdgeTab), matching: find.byType(Material)).first);
    expect(tab.width, greaterThanOrEqualTo(44), reason: 'the touch target stays 44 dp');
    return left ? face.right - tab.left : tab.right - face.left;
  }

  /// Every text and icon of the cards, as its distance from the END edge of a 390 px phone (the side the tab docks to).
  Future<double> closestToEnd(WidgetTester tester, Widget list) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(layoutHost(list, scale: 1));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final rtl = AppConfig.lang == 'ar';
    var best = double.infinity;
    for (final f in [find.byType(RichText), find.byType(Icon)]) {
      for (final e in f.evaluate()) {
        final box = e.renderObject as RenderBox?;
        if (box == null || !box.hasSize || box.size.isEmpty) continue;
        final r = box.localToGlobal(Offset.zero) & box.size;
        best = [best, rtl ? r.left : 390 - r.right].reduce((a, b) => a < b ? a : b);
      }
    }
    return best;
  }

  testWidgets('the tab\'s face never covers a dense card\'s text or icons at 390 px', (tester) async {
    final r = OmrResults.fromJson(_p('scan_results'));
    final b = OmrResults.fromJson(_p('bubble_results'));
    Widget lists() => ListView(padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xl), children: [
          OmrGradesView(results: b, wide: false),
          OmrGradesView(results: r, wide: false),
          OmrQuestionStatsView(questions: r.questions, wide: false),
          for (final e in [
            {'id': 1, 'title': 'CS101 Quiz 1 (online)', 'status': 'published', 'duration_minutes': 30, 'attempts_used': 1,
             'attempts_allowed': 2, 'can_start': true, 'results': [{'visible': true, 'percentage': 66.67, 'passed': true}]},
          ])
            EngineExamCard(exam: e, onOpen: () {}),
        ]);
    for (final lang in ['ar', 'en']) {
      AppConfig.lang = lang;
      final face = await faceWidth(tester, left: lang == 'ar');
      final content = await closestToEnd(tester, lists());
      expect(face, lessThanOrEqualTo(content),
          reason: '$lang: the docked tab draws $face dp from the edge, a card\'s text / icon starts $content dp from it');
    }
  });
}
