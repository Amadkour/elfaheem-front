// The creator's verdict on generated questions (Track F, exam_generate.dart): each question keeps its index in the
// draft, a rejection is reported at once with its reason, saving the exam reports the rest in one batch — accepted
// when unchanged, edited (with the final text) when changed — and an older server switches the review off.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/exam_authoring.dart' show QOption;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';
import 'package:flutter_education_app/features/exams/exam_generate.dart';
import 'package:flutter_education_app/features/shared/rag/rag_learning.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLearning implements LearningApi {
  _FakeLearning(this.answer);
  EngineResult answer;
  final calls = <(int, int, Map<String, dynamic>)>[];

  @override
  Future<EngineResult> examItemFeedback(int draftId, int n, Map<String, dynamic> body) async {
    calls.add((draftId, n, body));
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _draft = <Map<String, dynamic>>[
  {'type': 'mcq', 'prompt': 'What is 2 + 2?', 'options': [{'id': 'a', 'text': '3'}, {'id': 'b', 'text': '4'}], 'correct': 'b', 'points': 2},
  {'type': 'mcq', 'prompt': 'Only one choice', 'options': [{'id': 'a', 'text': 'x'}]}, // unusable: skipped, index 1 kept free
  {'type': 'essay', 'prompt': 'Explain photosynthesis.', 'key_points': ['light', 'chlorophyll']},
  {'type': 'essay', 'prompt': '  '}, // no prompt: skipped
  {'type': 'mcq', 'prompt': 'Capital of Egypt?', 'options': [{'id': 'a', 'text': 'Cairo'}, {'id': 'b', 'text': 'Giza'}], 'correct': 'a'},
];

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('genItemsOf keeps each question\'s index in the draft; quickQuestionsOf is the same questions', () {
    final items = genItemsOf(_draft);
    expect(items.map((e) => e.$1), [0, 2, 4]);
    expect(items.map((e) => e.$2.prompt), ['What is 2 + 2?', 'Explain photosynthesis.', 'Capital of Egypt?']);
    expect(quickQuestionsOf(_draft).map((q) => q.prompt), ['What is 2 + 2?', 'Explain photosynthesis.', 'Capital of Egypt?']);
    expect(const ExamGenResult(5, []).questions, isEmpty);
  });

  test('genFinalOf: the text, the non-empty choices and the answer (the right choice or the essay key)', () {
    final items = genItemsOf(_draft);
    expect(genFinalOf(items[0].$2), {
      'question': 'What is 2 + 2?',
      'options': [{'id': 'a', 'text': '3'}, {'id': 'b', 'text': '4'}],
      'answer': 'b',
    });
    expect(genFinalOf(items[1].$2), {'question': 'Explain photosynthesis.', 'options': <Map<String, dynamic>>[], 'answer': 'light\nchlorophyll'});
  });

  test('genChanged ignores spaces, sees the text, the choices and the answer', () {
    final q = genItemsOf(_draft).first.$2;
    final before = genFinalOf(q);
    q.prompt = '  What is   2 + 2? ';
    expect(genChanged(before, genFinalOf(q)), isFalse);
    q.correct = 'a';
    expect(genChanged(before, genFinalOf(q)), isTrue);
    q.correct = 'b';
    q.options.first.text = 'three';
    expect(genChanged(before, genFinalOf(q)), isTrue);
    q.options.first.text = '3';
    q.options.add(QOption('c', '5'));
    expect(genChanged(before, genFinalOf(q)), isTrue);
  });

  test('a rejection is reported once with its reason; saving reports the rest as accepted or edited, once', () {
    final r = ExamGenResult(42, genItemsOf(_draft));
    final review = ExamGenReview()..track(r);
    final [q0, q2, q4] = r.questions;
    final typed = genItemsOf([_draft.first]).single.$2; // a question the creator typed
    expect((review.isGenerated(q0), review.isGenerated(typed), review.isEmpty), (true, false, false));

    review.mark(q0, GenMark.accepted);
    expect(review.of(q0)!.mark, GenMark.accepted);

    final rej = review.reject(q2, 'too_easy');
    expect((rej!.$1, rej.$2), (42, 2));
    expect(rej.$3, {'action': 'reject', 'reason': 'too_easy'});
    expect(review.reject(q2, 'too_easy'), isNull); // once
    expect(review.reject(typed, null), isNull);
    expect(review.of(q2)!.mark, GenMark.rejected);

    q4.prompt = 'What is the capital of Egypt?';
    final batch = review.onSave([typed, q0, q4]);
    expect(batch.map((c) => (c.$1, c.$2, c.$3['action'])), [(42, 0, 'accept'), (42, 4, 'edit')]);
    expect(batch[1].$3['final'], {
      'question': 'What is the capital of Egypt?',
      'options': [{'id': 'a', 'text': 'Cairo'}, {'id': 'b', 'text': 'Giza'}],
      'answer': 'a',
    });
    expect(review.of(q4)!.mark, GenMark.edited);
    expect(review.onSave([q0, q4]), isEmpty); // a second save sends nothing again
  });

  test('sendGenFeedback sends every call; an older server switches the review off and nothing more goes', () async {
    final api = _FakeLearning(EngineResult.ok(const {}));
    final review = ExamGenReview();
    await sendGenFeedback(api, review, [(1, 0, {'action': 'accept'}), (1, 2, {'action': 'accept'})]);
    expect(api.calls.map((c) => c.$2), [0, 2]);
    expect(review.supported, isTrue);
    api.answer = EngineResult.fail(404, null, 'Not Found');
    await sendGenFeedback(api, review, [(1, 4, {'action': 'accept'})]);
    expect(review.supported, isFalse);
    await sendGenFeedback(api, review, [(1, 5, {'action': 'accept'})]);
    expect(api.calls.length, 3);
    // a refusal that is not an older server keeps it on
    final r2 = ExamGenReview();
    api.answer = EngineResult.fail(403, 'not_draft_owner', 'x');
    await sendGenFeedback(api, r2, [(1, 0, {'action': 'accept'})]);
    expect(r2.supported, isTrue);
  });
}
