// Games v4 T64: the admin hub, the templates list + defaults sheet and the subjects list + sheet on a phone and a wide
// window, ar / en, text 1.3: no layout error anywhere.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/games/admin/v4/hub_api.dart';
import 'package:flutter_education_app/features/games/admin/v4/hub_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/subjects_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/templates_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

GameTemplateRow _tpl(String key, {bool sacred = true, bool on = true}) => GameTemplateRow(
      key: key,
      nameAr: 'قالب طويل الاسم جداً حتى يلتف على سطرين في الهاتف',
      nameEn: 'A template with a very long name that wraps onto two lines',
      enabled: on,
      sacredAllowed: sacred,
      codeDefaults: const {'timer_s': 0, 'lives': 3, 'speed': 3, 'penalty': 'soft', 'theme': 'auto', 'music': true},
      levels: 12,
    );

const _subject = GameSubjectRow(
  id: 1,
  key: 'quran',
  nameAr: 'القرآن الكريم وعلومه الطويلة جداً',
  nameEn: 'The Holy Quran and its very long sciences',
  sacred: true,
  requiresReview: true,
  items: 120,
  levels: 8,
);

void main() {
  testWidgets('hub: loading, error, data with the review banner and links', (tester) async {
    final links = [
      GamesHubLink(
          id: 'templates',
          titleAr: 'قوالب الألعاب',
          titleEn: 'Game templates',
          subAr: 'شغّل أو أوقف',
          subEn: 'Switch on or off',
          icon: Icons.apps_rounded,
          badge: 14,
          open: (_) {}),
    ];
    const data = GamesHub(playsToday: 1234, playersToday: 56, completionPct: 71.4, avgScorePct: 83, pendingReview: 14, itemsTotal: 2400, levelsPublished: 40);
    await expectNoLayoutErrors(tester, () => GamesHubBody(hub: null, links: links));
    await expectNoLayoutErrors(tester, () => GamesHubBody(hub: data, links: links));
    await expectNoLayoutErrors(tester, () => GamesHubBody(hub: null, error: 'x', links: links));
  });

  testWidgets('templates: list, empty, defaults sheet', (tester) async {
    await expectNoLayoutErrors(tester, () => GamesTemplatesBody(templates: [_tpl('a'), _tpl('b', sacred: false), _tpl('c', on: false)]));
    await expectNoLayoutErrors(tester, () => const GamesTemplatesBody(templates: []));
    for (final key in ['car_race', 'growing_tree']) {
      await expectNoLayoutErrors(
        tester,
        () => TemplateDefaultsSheet(template: _tpl(key, sacred: false), subjects: const [_subject]),
      );
    }
  });

  testWidgets('subjects: list, empty, add and edit sheets', (tester) async {
    await expectNoLayoutErrors(tester, () => const GamesSubjectsBody(subjects: [_subject]));
    await expectNoLayoutErrors(tester, () => const GamesSubjectsBody(subjects: []));
    const course = [(id: 1, name: 'مادة دورة طويلة الاسم جداً'), (id: 2, name: 'Math')];
    await expectNoLayoutErrors(tester, () => const SubjectSheet(courseSubjects: course));
    await expectNoLayoutErrors(tester, () => const SubjectSheet(subject: _subject, courseSubjects: course));
  });
}
