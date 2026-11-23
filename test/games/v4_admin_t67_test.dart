// Games v4 T67: the levels page, the wizard's five steps, the preview panel, the bank picker and the auto-split sheet
// lay out at 320 and 1400 px, ar + en, text 1.3 (expectNoLayoutErrors); the draft builds the server's body.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/games/admin/v4/hub_api.dart';
import 'package:flutter_education_app/features/games/admin/v4/level_wizard.dart';
import 'package:flutter_education_app/features/games/admin/v4/levels_api.dart';
import 'package:flutter_education_app/features/games/admin/v4/levels_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

GameTemplateRow _tpl(String key, {bool sacred = true}) => GameTemplateRow(
      key: key,
      nameAr: 'قالب طويل الاسم جداً حتى يلتف على سطرين',
      nameEn: 'A template with a very long name that wraps onto two lines',
      sacredAllowed: sacred,
      codeDefaults: const {'timer_s': 0, 'lives': 3, 'speed': 3, 'penalty': 'soft', 'theme': 'auto', 'music': true},
    );

const _quran = GameSubjectRow(id: 1, key: 'quran', nameAr: 'القرآن الكريم', nameEn: 'The Holy Quran', sacred: true);
const _math = GameSubjectRow(id: 2, key: 'math', nameAr: 'رياضيات', nameEn: 'Math');

LevelRow _level(int id, {String status = 'draft'}) => LevelRow({
      'id': id,
      'engine': 'car_race',
      'title_ar': 'مستوى طويل الاسم جداً لاختبار الالتفاف في الشاشات الضيقة',
      'title_en': 'A level with a very long name to test wrapping on narrow screens',
      'status': status,
      'level_no': id,
      'age_min': 6,
      'age_max': 99,
      'sacred': id.isEven,
      'stats': {'starts': 120, 'avg_score_pct': 71},
    });

void main() {
  testWidgets('levels list: loading, error, empty, data', (tester) async {
    final tp = [_tpl('car_race'), _tpl('balloon_pop', sacred: false)];
    await expectNoLayoutErrors(tester, () => SizedBox(height: 600, child: GamesLevelsBody(levels: null, templates: tp, subjects: const [_quran, _math])));
    await expectNoLayoutErrors(tester, () => const SizedBox(height: 600, child: GamesLevelsBody(levels: null, error: 'x')));
    await expectNoLayoutErrors(tester, () => const SizedBox(height: 600, child: GamesLevelsBody(levels: [])));
    await expectNoLayoutErrors(
      tester,
      () => SizedBox(
        height: 600,
        child: GamesLevelsBody(
            levels: [_level(1), _level(2, status: 'published'), _level(3)],
            templates: tp,
            subjects: const [_quran, _math],
            onToggle: (_, _) {},
            onEdit: (_) {},
            onDelete: (_) {},
            onReorder: (_, _) {}),
      ),
    );
  });

  testWidgets('wizard: every step, fixed and pool, sacred and not', (tester) async {
    final tp = [_tpl('car_race'), _tpl('balloon_pop', sacred: false), _tpl('growing_tree')];
    for (var step = 0; step < 4; step++) {
      for (final mode in ['pool', 'fixed']) {
        for (final subject in [1, 2]) {
          await expectNoLayoutErrors(tester, () {
            final d = LevelDraft(template: 'balloon_pop', subjectId: subject, mode: mode, itemIds: [1, 2], titleAr: 'س', titleEn: 'q');
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: LevelStepBody(step: step, draft: d, templates: tp, subjects: const [_quran, _math], onChanged: () {}, onTemplate: (_) {}, onPickItems: () {}),
            );
          });
        }
      }
    }
    await expectNoLayoutErrors(tester, () => const SingleChildScrollView(child: LevelStepper(step: 2)));
  });

  testWidgets('preview panel: idle, unapproved badge, done, error', (tester) async {
    await expectNoLayoutErrors(tester, () => const SingleChildScrollView(child: PreviewPanel(engine: 'car_race')));
    await expectNoLayoutErrors(
        tester,
        () => const SingleChildScrollView(
            child: PreviewPanel(engine: 'car_race', unapproved: 3, done: (score: 5, max: 8), error: 'هذه رسالة خطأ طويلة جداً لاختبار الالتفاف في الشاشات الضيقة')));
  });

  testWidgets('auto-split sheet lays out', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: AutoSplitSheet(templates: [_tpl('car_race')], subjects: const [_quran, _math])));
  });

  test('the draft builds the server body', () {
    final d = LevelDraft(template: 'car_race', subjectId: 2, titleAr: 'أ', titleEn: 'A', topic: ' t ', count: 6, itemIds: [4, 5]);
    final b = d.toBody();
    expect(b['engine'], 'car_race');
    expect(b['config'], isEmpty);
    expect(b['status'], 'draft');
    expect(b['key'], startsWith('lv_car_race_'));
    expect((b['item_source'] as Map)['mode'], 'pool');
    expect((b['item_source'] as Map)['topic'], 't');
    expect((b['item_source'] as Map)['difficulty'], [1, 5]);
    expect((b['unlock'] as Map)['mode'], 'prev');
    d.mode = 'fixed';
    expect(d.itemSource(), {'mode': 'fixed', 'item_ids': [4, 5]});
    d.id = 9;
    expect(d.toBody().containsKey('key'), isFalse);
    d.dispose();
  });

  test('step problems are named', () {
    final d = LevelDraft();
    expect(d.stepProblem(0), isNotNull);
    d.template = 'car_race';
    d.titleArC.text = 'أ';
    d.titleEnC.text = 'A';
    expect(d.stepProblem(0), isNull);
    expect(d.stepProblem(1), isNotNull);
    d.subjectId = 1;
    expect(d.stepProblem(1, sacredClash: true), isNotNull);
    expect(d.stepProblem(1), isNull);
    d.mode = 'fixed';
    expect(d.stepProblem(1), isNotNull);
    d.ageMin = 50;
    d.ageMax = 20;
    expect(d.stepProblem(2), isNotNull);
    d.dispose();
  });
}
