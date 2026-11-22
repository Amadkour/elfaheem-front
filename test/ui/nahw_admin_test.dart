// The super admin's nahw content editor (6.R #8, D-1349): the draft reads the server's exercise shapes and sends
// them back in the shape `check_exercise` accepts, says what is missing first, and every part of the page lays out
// on a phone and a desktop in both languages.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/nahw/admin/nahw_admin_api.dart';
import 'package:flutter_education_app/features/nahw/admin/nahw_admin_page.dart';
import 'package:flutter_education_app/features/nahw/admin/nahw_exercise_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

final _classify = {
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
  'answer': {
    'items': ['ism', 'fil', 'harf'],
  },
  'explanation': 'كتاب اسم يقبل (ال)، وذهبَ فعل، وفي حرف جر.',
  'sort': 0,
};

final _choose = {
  'id': 2,
  'kind': 'choose',
  'prompt': 'أيّ الكلمات الآتية فعل؟',
  'data': {
    'prompt_en': 'Which word is a verb?',
    'options': ['قلم', 'جلسَ', 'إلى', 'بيت'],
  },
  'answer': {'index': 1},
  'explanation': 'جلسَ فعل ماضٍ.',
  'sort': 1,
};

final _fill = {
  'id': 3,
  'kind': 'fill',
  'prompt': 'أكمل',
  'data': {
    'prompt_en': 'Complete',
    'text': 'الكلمة ثلاثة أقسام: اسم وفعل و___',
    'options': ['حرف', 'جملة', 'خبر'],
    'hint_ar': 'kept',
  },
  'answer': {'text': 'حرف'},
  'explanation': '',
  'sort': 2,
};

final _levels = NahwAdminLevel.listFrom({
  'levels': [
    {
      'id': 1,
      'key': 'beginner',
      'title_ar': 'المستوى المبتدئ في قواعد اللغة العربية للصفوف الأولى',
      'title_en': 'Beginner level of Arabic grammar for the first grades',
      'stage_id': null,
      'sort': 0,
      'active': true,
      'lessons': [
        {'id': 7, 'level_id': 1, 'title_ar': 'أقسام الكلمة', 'title_en': 'Parts of speech', 'exercise_count': 5, 'active': true},
        {'id': 8, 'level_id': 1, 'title_ar': 'الجملة الاسمية والجملة الفعلية وأركانهما', 'title_en': 'Sentences', 'exercise_count': 1, 'active': false},
      ],
    },
    {'id': 2, 'key': 'mid', 'title_ar': 'المتوسط', 'title_en': 'Intermediate', 'stage_id': 4, 'active': false, 'lessons': []},
  ],
});

final _lesson = NahwAdminLesson.from({
  'id': 7,
  'level_id': 1,
  'title_ar': 'أقسام الكلمة',
  'title_en': 'Parts of speech',
  'body_ar': 'الكلمة في العربية ثلاثة أقسام: اسم، وفعل، وحرف.\nالاسم: كلمة تدل على معنى في نفسها غير مقترن بزمن.',
  'active': true,
  'exercises': [
    _classify,
    _choose,
    _fill,
    {'id': 4, 'kind': 'order', 'prompt': 'رتّب', 'data': {}, 'answer': {}},
  ],
});

Future<String?> _noSave(Map<String, dynamic> _) async => null;

void main() {
  setUp(() => AppConfig.lang = 'ar');

  group('draft', () {
    test('each kind reads and writes the server shape', () {
      for (final raw in [_classify, _choose, _fill]) {
        final d = NahwExerciseDraft.from(raw);
        expect(d.problem(), isNull, reason: '${raw['kind']}');
        final out = d.toJson();
        expect(out['kind'], raw['kind']);
        expect(out['prompt'], raw['prompt']);
        expect(out['data'], raw['data'], reason: '${raw['kind']} data');
        expect(out['answer'], raw['answer'], reason: '${raw['kind']} answer');
        expect(d.toExercise().supported, isTrue);
      }
    });

    test('says what is missing first, and never offers order', () {
      final d = NahwExerciseDraft();
      expect(d.problem(), isNotNull);
      d.prompt = 'أيّها اسم؟';
      d.options = ['قلم', ''];
      expect(d.problem(), contains('خيارين'));
      d.options = ['قلم', 'كتبَ'];
      expect(d.problem(), contains('الإجابة الصحيحة'));
      d.answerIndex = 0;
      expect(d.problem(), isNull);
      expect(d.toJson()['answer'], {'index': 0});

      final c = NahwExerciseDraft.from(_classify)..items.first.category = null;
      expect(c.problem(), isNotNull);

      final f = NahwExerciseDraft.from(_fill)..text = 'لا فراغ هنا';
      expect(f.problem(), contains('___'));

      expect(kNahwEditableKinds, isNot(contains('order')));
      expect(NahwExerciseDraft.from({'kind': 'order', 'prompt': 'x'}).problem(), isNotNull);
    });

    test('a new category gets a key no other category uses', () {
      final d = NahwExerciseDraft.from(_classify);
      expect(d.nextCategoryKey(), isNot(anyOf('ism', 'fil', 'harf')));
      final n = NahwExerciseDraft();
      expect(n.nextCategoryKey(), 'c3');
    });
  });

  testWidgets('levels body: list, loading, error, empty — no layout errors', (tester) async {
    Widget host(Widget w) => ListView(padding: const EdgeInsets.all(16), children: [w]);
    await expectNoLayoutErrors(
        tester, () => host(NahwAdminLevelsBody(levels: _levels, onEditLevel: (_) {}, onAddLesson: (_) {}, onOpenLesson: (_) {})));
    await expectNoLayoutErrors(tester, () => host(const NahwAdminLevelsBody(levels: null)));
    await expectNoLayoutErrors(tester, () => host(const NahwAdminLevelsBody(levels: null, error: 'تعذر الاتصال بالخادم')));
    await expectNoLayoutErrors(tester, () => host(const NahwAdminLevelsBody(levels: [])));
  });

  testWidgets('lesson body: no layout errors', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => ListView(padding: const EdgeInsets.all(16), children: [
              NahwAdminLessonBody(lesson: _lesson, onEditLesson: () {}, onEditExercise: (_) {}, onDeleteExercise: (_) {}),
            ]));
  });

  testWidgets('forms and the exercise editor for each kind: no layout errors', (tester) async {
    await expectNoLayoutErrors(tester, () => NahwLevelForm(onSave: _noSave));
    await expectNoLayoutErrors(tester, () => NahwLevelForm(initial: _levels.first, onSave: _noSave));
    await expectNoLayoutErrors(tester, () => NahwLessonForm(levelId: 1, initial: _lesson, onSave: _noSave));
    for (final raw in [_classify, _choose, _fill]) {
      await expectNoLayoutErrors(tester, () => NahwExerciseEditor(draft: NahwExerciseDraft.from(raw), onSave: _noSave));
    }
    await expectNoLayoutErrors(tester, () => NahwExerciseEditor(draft: NahwExerciseDraft(), onSave: _noSave));
  });

  testWidgets('the editor previews with the student widget and saves the typed payload', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    Map<String, dynamic>? sent;
    await tester.pumpWidget(layoutHost(
      NahwExerciseEditor(
        draft: NahwExerciseDraft.from(_choose),
        onSave: (b) async {
          sent = b;
          return null;
        },
      ),
      scale: 1,
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('nahw.admin.preview')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('nahw.admin.option.0')), 'قلمٌ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('nahw.admin.save')));
    await tester.pump();
    expect(sent?['data']['options'], ['قلمٌ', 'جلسَ', 'إلى', 'بيت']);
    expect(sent?['answer'], {'index': 1});
    expect(sent?['data']['prompt_en'], 'Which word is a verb?');
  });
}
