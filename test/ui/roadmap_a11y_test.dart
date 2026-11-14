// Accessibility guidelines (`meetsGuideline`, through `expectA11y` of a11y_guidelines_test.dart) on the course
// roadmap and recommendation widgets (D-120): tap targets, a label on every tappable node, WCAG text contrast —
// Arabic and English, light and dark, phone and wide window. The data is roadmap_layout_test.dart's.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_recs_page.dart';
import 'package:flutter_education_app/features/courses/roadmap/journey_page.dart';
import 'package:flutter_education_app/features/courses/roadmap/recommendations.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_editor.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_tab.dart';
import 'package:flutter_education_app/features/student/home/home_journey.dart';
import 'package:flutter_test/flutter_test.dart';

import 'a11y_guidelines_test.dart' show expectA11y;
import 'roadmap_layout_test.dart' as rm;

Widget _scroll(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() => AppConfig.disableList = []);

  testWidgets('Path tab: student and teacher', (t) async {
    await expectA11y(
      t,
      'roadmap student',
      () => _scroll(RoadmapTabContent(
          roadmap: rm.rmStudentRoadmap(), staff: false, onOpenCourse: (_) {}, onEnrollAll: () {}, teacherPicks: rm.rmPicks(), onOpenPick: (_) {})),
    );
    await expectA11y(t, 'roadmap teacher', () => _scroll(RoadmapTabContent(roadmap: rm.rmTeacherRoadmap(), staff: true, onEdit: () {}, onOpenCourse: (_) {})));
  });

  testWidgets('Path editor', (t) async {
    await expectA11y(
      t,
      'roadmap editor',
      () => RoadmapEditorForm(
        draft: RoadmapDraft(
          next: [rm.rmCourse(11), rm.rmCourse(12, published: false), rm.rmCourse(13)],
          prereqs: [rm.rmCourse(1)],
          level: 'beginner',
          tags: ['الذكاء الاصطناعي', 'Python'],
        ),
        onAddNext: () {},
        onAddPrereq: () {},
        onChanged: () {},
      ),
    );
  });

  testWidgets('Home journey card and the journey page', (t) async {
    await expectA11y(t, 'journey card', () => _scroll(HomeJourneyCard(journey: rm.rmJourney(), onTap: () {})));
    await expectA11y(t, 'journey page', () => _scroll(JourneyContent(journey: rm.rmJourney(), onOpenCourse: (_) {})));
  });

  testWidgets('Recommended for you and the interests sheet', (t) async {
    await expectA11y(
      t,
      'recommendations',
      () => _scroll(RecommendationsSectionView(page: rm.rmRecs(), onOpen: (_) {}, onDismiss: (_) {}, onInterests: () {}, onSeeAll: () {})),
    );
    final fields = [
      for (var i = 0; i < 3; i++) ...[
        RmField(id: 100 + i, nameAr: 'المجال الرئيسي $i', nameEn: 'Top field $i'),
        for (var k = 0; k < 3; k++) RmField(id: 200 + i * 10 + k, nameAr: 'فرع $k', nameEn: 'Sub-field $k', parentId: 100 + i),
      ],
      const RmField(id: 300, nameAr: 'اللغات', nameEn: 'Languages'),
    ];
    await expectA11y(
      t,
      'interests',
      () => _scroll(InterestsForm(fields: fields, picked: {100, 211}, show: true, hidden: 2, onShowHidden: () {}, onToggle: (_) {}, onShow: (_) {})),
    );
  });

  testWidgets('Super admin: Recommendations', (t) async {
    final stats = RecStats.fromJson({
      'days': 30,
      'students': 1240,
      'total': {'shown': 18420, 'opened': 2210, 'dismissed': 190, 'enrolled': 412},
      'by_reason': [
        for (final r in ['because_completed', 'similar_students'])
          {'reason': r, 'shown': 4000, 'opened': 520, 'dismissed': 40, 'enrolled': 96, 'open_rate': 0.13, 'enroll_rate': 0.024},
      ],
      'weights': {'similar_students': 0.35, 'content': 0.3, 'same_teacher': 0.25, 'popularity': 0.1},
      'defaults': {'similar_students': 0.35, 'content': 0.3, 'same_teacher': 0.25, 'popularity': 0.1},
    });
    await expectA11y(
      t,
      'recs admin',
      () => _scroll(RecsAdminView(stats: stats, days: 30, weights: stats.weights, onDays: (_) {}, onWeight: (_, _) {}, onReset: () {}, onSave: () {})),
    );
  });
}
