// Open-ended answers (D-686): the key's kinds, the teacher's overrides, the derived-key preview (contract A1 / A2), the
// debounced call, the three editors' parts under the layout harness.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_authoring.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_engine_api.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_open_key.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_open_key_widgets.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_quick.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_quick_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

/// The contract A2 answer, as the engine sends it.
const _preview = <String, dynamic>{
  'kind': 'short',
  'kind_source': 'inferred',
  'derived': {
    'v': 1,
    'kind': 'short',
    'kind_source': 'inferred',
    'alternatives': ['light travels much faster than sound', 'light travel much fast than sound'],
    'keywords': [
      {'term': 'light', 'weight': 1.0, 'synonyms': []},
      {'term': 'faster', 'weight': 0.8, 'synonyms': []},
    ],
    'points': [
      {'text': 'Light travels much faster than sound', 'weight': 1.0},
    ],
    'points_source': 'model',
    'keywords_source': 'model',
    'model_hash': '9f2c1a',
  },
  'effective': {
    'keywords': [
      {'term': 'light', 'weight': 1, 'synonyms': []},
      'faster',
    ],
    'points': [
      {'text': 'Light travels much faster than sound', 'weight': 1},
    ],
  },
};

class _FakeDerive extends DeriveKeyApi {
  _FakeDerive([this.answer]);
  final EngineResult? answer;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<EngineResult> preview(Map<String, dynamic> body) async {
    bodies.add(body);
    return answer ?? EngineResult.ok(Map<String, dynamic>.from(_preview));
  }
}

void main() {
  group('kinds', () {
    test('inferred like the server: up to 3 words one word, up to 30 short, else long; 2+ criteria long', () {
      expect(inferOpenKind('Cairo'), OpenKind.word);
      expect(inferOpenKind('the water cycle'), OpenKind.word);
      expect(inferOpenKind('Light travels much faster than sound.'), OpenKind.short);
      expect(inferOpenKind(List.filled(31, 'word').join(' ')), OpenKind.long);
      expect(inferOpenKind('x', rubricCriteria: 2), OpenKind.long);
      expect(inferOpenKind(''), OpenKind.short);
    });

    test('shown: the teacher wins, a number is a number, an essay is long by default', () {
      expect(openKindShown('numeric', teacher: OpenKind.word), OpenKind.numeric);
      expect(openKindShown('essay'), OpenKind.long);
      expect(openKindShown('essay', teacher: OpenKind.short), OpenKind.short);
      expect(openKindShown('short_answer', model: 'Paris'), OpenKind.word);
      expect(openTypeFor(OpenKind.long), 'essay');
      expect(openTypeFor(OpenKind.word), 'short_answer');
      expect(openKindKey(OpenKind.numeric), isNull);
      expect(openKindOf('LONG'), OpenKind.long);
      expect(openKindOf('numeric'), isNull);
    });
  });

  group('the overrides', () {
    test('points: one per line with a ×2 weight, back to text', () {
      final p = parseKeyPoints('Both start together\n\nLight is faster ×2\n ×3');
      expect(p, const [KeyPoint('Both start together'), KeyPoint('Light is faster', 2)]);
      expect(keyPointsText(p), 'Both start together\nLight is faster ×2');
    });

    test('an old key has none and writes none: it saves exactly as before', () {
      final old = {'model': 'Paris', 'alternatives': ['paris city']};
      final x = OpenKeyExtras.fromAnswer(old);
      expect(x.kind, isNull);
      expect(x.hasOverrides, isFalse);
      final a = Map<String, dynamic>.from(old);
      x.writeTo(a);
      expect(a, old);
    });

    test('a full key round-trips, and a reset removes the override', () {
      final a = <String, dynamic>{'model': 'm'};
      OpenKeyExtras(kind: OpenKind.long, keywords: [RubricKeyword('light', ['glow'], 2)], points: const [KeyPoint('a'), KeyPoint('b', 2)], matchBy: MatchBy.exact)
          .writeTo(a);
      expect(a['kind'], 'long');
      expect(a['keywords'], [
        {'term': 'light', 'synonyms': ['glow'], 'weight': 2.0},
      ]);
      expect(a['points'], [
        {'text': 'a'},
        {'text': 'b', 'weight': 2.0},
      ]);
      expect(a['match_by'], 'exact');
      final back = OpenKeyExtras.fromAnswer(a);
      expect(back.kind, OpenKind.long);
      expect(back.points, const [KeyPoint('a'), KeyPoint('b', 2)]);
      expect(back.matchBy, MatchBy.exact);
      (back
            ..keywords = null
            ..points = null
            ..matchBy = MatchBy.meaning)
          .writeTo(a);
      expect(a.keys.toSet(), {'model', 'kind'});
    });

    test('a classic-editor question with the new fields opens and saves them unchanged', () {
      final q = QuestionDraft.fromJson({
        'id': 4,
        'type': 'short_answer',
        'points': 2,
        'body': {'prompt': 'Why?'},
        'answer': {
          'model': 'Light is faster.',
          'kind': 'short',
          'keywords': ['light'],
          'derived': {'v': 1},
        },
      });
      expect(q.model, 'Light is faster.');
      expect(OpenKeyExtras.fromAnswer(q.extraAnswer).kind, OpenKind.short);
      final a = q.answer();
      expect(a['kind'], 'short');
      expect(a['keywords'], ['light']);
    });
  });

  group('the preview', () {
    test('parses contract A2: the effective key, string keywords included', () {
      final p = DeriveKeyPreview.fromJson(Map<String, dynamic>.from(_preview));
      expect(p.kind, OpenKind.short);
      expect(p.kindSource, 'inferred');
      expect([for (final k in p.keywords) k.term], ['light', 'faster']);
      expect(p.points.single.text, 'Light travels much faster than sound');
      expect(p.otherWordings, ['light travel much fast than sound']);
      expect(p.keywordsAreTeachers, isFalse);
      expect(p.derived.keywords[1].weight, 0.8);
    });

    test('the body carries the key and only the two open types', () {
      final b = deriveKeyBody(orgId: 1, courseId: 7, type: 'essay', prompt: ' Why? ', answer: {'model': ' m ', 'kind': 'long', 'rubric': []});
      expect(b['type'], 'essay');
      expect(b['body'], {'prompt': 'Why?'});
      expect((b['answer'] as Map)['model'], 'm');
      expect((b['answer'] as Map).containsKey('rubric'), isFalse);
      expect(deriveKeyReady(b), isTrue);
      expect(deriveKeyReady(deriveKeyBody(type: 'short_answer', prompt: '', answer: {'model': '  '})), isFalse);
    });

    test('switched off or not routed: hidden, never an error', () {
      expect(deriveKeyHidden(EngineResult.fail(403, 'feature_disabled', 'off')), isTrue);
      expect(deriveKeyHidden(EngineResult.fail(404, null, 'Not Found')), isTrue);
      expect(deriveKeyHidden(EngineResult.fail(422, 'bad_answer_key', 'x')), isFalse);
    });

    testWidgets('asked once after a pause, the same key never twice, an empty model clears it', (tester) async {
      final api = _FakeDerive();
      var changes = 0;
      final d = DeriveKeyDebouncer(call: api.preview, onChange: () => changes++);
      Map<String, dynamic> body(String m) => deriveKeyBody(type: 'short_answer', prompt: 'q', answer: {'model': m});
      d.update(body('Li'));
      await tester.pump(const Duration(milliseconds: 300));
      d.update(body('Light is faster'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.bodies, isEmpty);
      await tester.pump(const Duration(milliseconds: 500));
      expect(api.bodies.length, 1);
      expect(d.phase, DerivePhase.ready);
      expect(d.preview?.kind, OpenKind.short);
      d.update(body('Light is faster'));
      await tester.pump(const Duration(seconds: 1));
      expect(api.bodies.length, 1);
      d.update(body(''));
      expect(d.phase, DerivePhase.idle);
      expect(d.preview, isNull);
      expect(changes, greaterThan(0));
      d.dispose();
    });

    testWidgets('a kill switch answer hides the strip for good', (tester) async {
      final api = _FakeDerive(EngineResult.fail(403, 'feature_disabled', 'off'));
      final d = DeriveKeyDebouncer(call: api.preview, onChange: () {}, pause: Duration.zero);
      d.update(deriveKeyBody(type: 'short_answer', prompt: 'q', answer: {'model': 'x'}));
      await tester.pump(const Duration(milliseconds: 10));
      expect(d.phase, DerivePhase.hidden);
      d.update(deriveKeyBody(type: 'short_answer', prompt: 'q', answer: {'model': 'y'}));
      await tester.pump(const Duration(milliseconds: 10));
      expect(api.bodies.length, 1);
      d.dispose();
    });
  });

  group('the quick builder', () {
    test('a short answer moves to a number and back, keeping prompt and marks', () {
      final q = QuickQuestion.ofType('short_answer')
        ..prompt = 'How much?'
        ..points = 3
        ..keyText = 'twelve';
      q.setOpenKind(OpenKind.numeric);
      expect(q.type, 'numeric');
      q.engine!.numValue = '12';
      expect(q.validate(), isEmpty);
      final n = q.toDraft();
      expect(n.answer()['value'], 12);
      expect(n.points, 3);
      q.setOpenKind(OpenKind.long);
      expect(q.type, 'essay');
      expect(q.engine, isNull);
      final d = q.toDraft();
      expect(d.answer()['model'], 'twelve');
      expect(d.answer()['kind'], 'long');
    });

    test('only the model answer is required; the overrides travel with it', () {
      final q = QuickQuestion.ofType('short_answer')..prompt = 'Why?';
      expect(q.validate(), ['essay_key_required']);
      q.keyText = 'Light is faster than sound.';
      expect(q.validate(), isEmpty);
      expect(q.toDraft().answer().containsKey('kind'), isFalse);
      q.extras = OpenKeyExtras(matchBy: MatchBy.exact, keywords: [RubricKeyword('light')]);
      final a = q.toDraft().answer();
      expect(a['match_by'], 'exact');
      expect(a['keywords'], [
        {'term': 'light'},
      ]);
    });
  });

  group('layout', () {
    final preview = DeriveKeyPreview.fromJson(Map<String, dynamic>.from(_preview));
    final long = DeriveKeyPreview.fromJson({
      'kind': 'long',
      'derived': {
        'points': [
          {'text': 'Both start at the same moment and travel the same way', 'weight': 1},
          {'text': 'Light is faster than sound by a very large margin', 'weight': 2},
        ],
        'points_source': 'teacher',
      },
    });

    testWidgets('kind chips', (t) async => expectNoLayoutErrors(t, () => SingleChildScrollView(child: OpenKindChips(value: OpenKind.short, auto: true, onPick: (_) {}))));

    testWidgets('derived strip, short and long', (t) async => expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
              child: Column(children: [
                DerivedKeyStrip(phase: DerivePhase.ready, kind: OpenKind.short, preview: preview, onAdvanced: () {}),
                DerivedKeyStrip(phase: DerivePhase.ready, kind: OpenKind.long, preview: long, onAdvanced: () {}, overridden: true),
                const DerivedKeyStrip(phase: DerivePhase.loading, kind: OpenKind.word),
                const DerivedKeyStrip(phase: DerivePhase.failed, kind: OpenKind.word, error: 'Could not show what was derived right now'),
              ]),
            )));

    testWidgets('advanced sheet body', (t) async => expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
            child: OpenKeyAdvancedBody(kind: OpenKind.long, extras: OpenKeyExtras(matchBy: MatchBy.exact, points: const [KeyPoint('a', 2)]), preview: long, onDone: (_) {}))));

    testWidgets('numeric advanced body', (t) async => expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
            child: NumericAdvancedBody(
                draft: QuestionDraft(type: 'numeric')
                  ..numTolerance = '0.5'
                  ..units = [NumericUnit('m', '1'), NumericUnit('cm', '0.01')],
                onDone: () {}))));

    testWidgets('quick cards: number, word, long with the strip', (t) async => expectNoLayoutErrors(
        t,
        () => SingleChildScrollView(
              child: Column(children: [
                QuickQuestionCard(
                    index: 0,
                    question: QuickQuestion.ofType('short_answer')..setOpenKind(OpenKind.numeric),
                    onChanged: () {},
                    onRemove: () {},
                    deriveApi: _FakeDerive()),
                QuickQuestionCard(
                    index: 1,
                    question: QuickQuestion.ofType('short_answer')
                      ..prompt = 'Capital of Egypt?'
                      ..keyText = 'Cairo',
                    onChanged: () {},
                    onRemove: () {},
                    deriveApi: _FakeDerive()),
                QuickQuestionCard(
                    index: 11,
                    question: QuickQuestion.ofType('essay')
                      ..prompt = 'Explain the delay.'
                      ..keyText = 'Light travels much faster than sound, so we see the flash first.',
                    errors: const ['essay_key_required'],
                    onChanged: () {},
                    onRemove: () {},
                    deriveApi: _FakeDerive()),
              ]),
            ),
        frames: 10));
  });
}
