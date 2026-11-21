import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/nahw/nahw_exercise_view.dart';
import 'package:flutter_education_app/features/nahw/nahw_lesson_page.dart';
import 'package:flutter_education_app/features/nahw/nahw_models.dart';
import 'package:flutter_education_app/features/nahw/nahw_tab.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

// The shapes of back/data/learn_seed/nahw.json, as GET /api/v1/nahw/lessons/{id} sends them.
final _lessonJson = {
  'id': 7,
  'level_id': 1,
  'title_ar': 'أقسام الكلمة في اللغة العربية الفصحى',
  'title_en': 'Parts of speech',
  'body_ar': 'الكلمة في العربية ثلاثة أقسام: اسم، وفعل، وحرف.\nالاسم: كلمة تدل على معنى في نفسها غير مقترن بزمن، مثل: محمد، كتاب، شجرة.',
  'progress': {'lesson_id': 7, 'best_score': 6, 'max_score': 8, 'attempts': 2, 'completed': true},
  'exercises': [
    {
      'id': 1,
      'kind': 'classify',
      'prompt': 'صنّف الكلمات الآتية إلى اسم وفعل وحرف.',
      'data': {
        'prompt_en': 'Sort the words into noun, verb and particle.',
        'categories': [
          {'key': 'ism', 'label_ar': 'اسم', 'label_en': 'Noun'},
          {'key': 'fil', 'label_ar': 'فعل', 'label_en': 'Verb'},
          {'key': 'harf', 'label_ar': 'حرف', 'label_en': 'Particle'},
        ],
        'items': [
          {'text': 'كتاب'},
          {'text': 'ذهبَ'},
          {'text': 'في'},
        ],
      },
      'answer': {'items': ['ism', 'fil', 'harf']},
      'explanation': 'كتاب اسم يقبل (ال)، وذهبَ فعل، وفي حرف جر.',
    },
    {
      'id': 2,
      'kind': 'choose',
      'prompt': 'أيّ الكلمات الآتية فعل؟',
      'data': {'prompt_en': 'Which word is a verb?', 'options': ['قلم', 'جلسَ', 'إلى', 'بيت']},
      'answer': {'index': 1},
      'explanation': 'جلسَ فعل ماضٍ.',
    },
    {
      'id': 3,
      'kind': 'fill',
      'prompt': 'أكمل',
      'data': {'prompt_en': 'Complete', 'text': 'الكلمة ثلاثة أقسام: اسم وفعل و___', 'options': ['حرف', 'جملة', 'خبر']},
      'answer': {'text': 'حرف'},
      'explanation': '',
    },
    {'id': 4, 'kind': 'order', 'prompt': 'رتّب', 'data': {}, 'answer': {}},
  ],
};

final _levelsJson = {
  'levels': [
    {
      'id': 1,
      'key': 'beginner',
      'title_ar': 'المستوى المبتدئ',
      'title_en': 'Beginner',
      'total': 3,
      'completed': 1,
      'lessons': [
        {'id': 7, 'level_id': 1, 'title_ar': 'أقسام الكلمة في اللغة العربية الفصحى وعلاماتها', 'title_en': 'Parts of speech and their signs', 'exercise_count': 5, 'progress': {'lesson_id': 7, 'best_score': 6, 'max_score': 8, 'attempts': 2, 'completed': true}},
        {'id': 8, 'level_id': 1, 'title_ar': 'الجملة الاسمية', 'title_en': 'The nominal sentence', 'exercise_count': 5, 'progress': {'lesson_id': 8, 'best_score': 2, 'max_score': 8, 'attempts': 1, 'completed': false}},
        {'id': 9, 'level_id': 1, 'title_ar': 'الجملة الفعلية', 'title_en': 'The verbal sentence', 'exercise_count': 5, 'progress': null},
      ],
    },
    {'id': 2, 'key': 'advanced', 'title_ar': 'المستوى المتقدم', 'title_en': 'Advanced', 'total': 0, 'completed': 0, 'lessons': []},
  ],
};

void main() {
  final lesson = NahwLesson.from(_lessonJson);

  test('models and on-device grading', () {
    expect(lesson.exercises.map((e) => e.kind), ['classify', 'choose', 'fill'], reason: 'an unknown kind is skipped');
    expect(lesson.maxScore, 5);
    final classify = lesson.exercises[0];
    var r = const NahwResponse();
    expect(r.complete(classify), isFalse);
    r = r.withItem(0, 'ism', 3).withItem(1, 'harf', 3).withItem(2, 'harf', 3);
    expect(r.complete(classify), isTrue);
    final g = nahwGrade(classify, r);
    expect(g.score, 2);
    expect(g.max, 3);
    expect(g.itemsRight, [true, false, true]);
    expect(nahwGrade(lesson.exercises[1], const NahwResponse(choice: 1)).correct, isTrue);
    expect(nahwGrade(lesson.exercises[1], const NahwResponse(choice: 0)).correct, isFalse);
    expect(nahwGrade(lesson.exercises[2], const NahwResponse(choice: 0)).correct, isTrue);
    expect(const NahwResponse(choice: 0).toJson(lesson.exercises[2]), {'text': 'حرف'});
    final levels = NahwLevel.listFrom(_levelsJson);
    expect(levels.length, 2);
    expect(levels[0].fraction, closeTo(1 / 3, 0.001));
    expect(levels[0].lessons[0].progress?.percent, 75);
    expect(levels[0].lessons[2].progress, isNull);
  });

  for (var i = 0; i < 3; i++) {
    for (final checked in [false, true]) {
      testWidgets('exercise ${lesson.exercises[i].kind}, checked $checked: no layout errors', (tester) async {
        final e = lesson.exercises[i];
        final r = switch (e.kind) {
          'classify' => const NahwResponse().withItem(0, 'ism', 3).withItem(1, 'harf', 3).withItem(2, 'harf', 3),
          _ => const NahwResponse(choice: 0),
        };
        await expectNoLayoutErrors(
          tester,
          () => NahwRoundView(exercise: e, index: i, total: 3, score: 2, response: r, checked: checked, onChanged: (_) {}),
        );
      });
    }
  }

  testWidgets('exercise view alone and the reading view: no layout errors', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: NahwExerciseView(exercise: lesson.exercises[0], response: const NahwResponse(), onChanged: (_) {}),
      ),
    );
    await expectNoLayoutErrors(tester, () => NahwReadingView(lesson: lesson, onStart: () {}));
    await expectNoLayoutErrors(tester, () => NahwReadingView(lesson: NahwLesson.from({'id': 1, 'title_ar': 'درس'})));
  });

  testWidgets('levels view (student, parent, loading, error, empty): no layout errors', (tester) async {
    final levels = NahwLevel.listFrom(_levelsJson);
    await expectNoLayoutErrors(tester, () => NahwLevelsView(levels: levels, onOpen: (_) {}, mine: true, onMine: (_) {}));
    await expectNoLayoutErrors(tester, () => NahwLevelsView(levels: levels));
    await expectNoLayoutErrors(tester, () => const NahwLevelsView(levels: null));
    await expectNoLayoutErrors(tester, () => const NahwLevelsView(levels: null, error: 'تعذر الاتصال بالخادم'));
    await expectNoLayoutErrors(tester, () => const NahwLevelsView(levels: []));
  });
}
