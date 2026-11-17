// The super admin's exam policy in the app (D-1130) and the result fixes (D-1131): parsing, clamping, the client check,
// a new exam born from the defaults in every creation flow, the codes and counts in words.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/exam_authoring.dart';
import 'package:flutter_education_app/features/exams/exam_policy.dart';
import 'package:flutter_education_app/features/exams/exam_quick.dart';
import 'package:flutter_education_app/features/exams/exam_result_screen.dart' show fmtScore;
import 'package:flutter_education_app/features/exams/exam_taking.dart' show examCodeText;
import 'package:flutter_education_app/features/exams/exam_words.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    ExamPolicy.reset();
  });
  tearDown(ExamPolicy.reset);

  test('an empty or older server reads exactly the old defaults, no limits', () {
    final p = ExamPolicy.fromJson(const {});
    expect(p.durationMinutes, 30);
    expect(p.maxAttempts, 1);
    expect(p.highStakes, isFalse);
    expect(p.resultsPolicy, 'after_submit');
    expect(p.check(durationMinutes: 999, maxAttempts: 0, resultsView: 'answers_key', questions: 999), isEmpty);
  });

  test('parse, clamp, check', () {
    final p = ExamPolicy.fromJson(const {
      'defaults': {'duration_minutes': 45, 'max_attempts': 2, 'results_policy': 'nonsense', 'high_stakes': true, 'passing_percent': 60},
      'limits': {'max_duration_minutes': 90, 'max_attempts': 3, 'allow_unlimited_attempts': false, 'max_questions': 20, 'allow_answer_key': false},
    });
    expect(p.durationMinutes, 45);
    expect(p.resultsPolicy, 'after_submit'); // an unknown value falls back
    expect(p.clampDuration(120), 90);
    expect(p.clampAttempts(0), 3);
    expect(p.clampAttempts(9), 3);
    expect(p.check(durationMinutes: 91, maxAttempts: 0, resultsView: 'answers_key', questions: 21),
        ['policy_duration', 'policy_unlimited_attempts', 'policy_answer_key', 'policy_questions']);
    expect(p.check(durationMinutes: 90, maxAttempts: 4), ['policy_attempts']);
    expect(p.defaultsJson()['duration_minutes'], 45);
    expect(p.limitsJson()['allow_answer_key'], isFalse);
  });

  test('every creation flow starts from the policy', () {
    ExamPolicy.current = const ExamPolicy(
        durationMinutes: 40,
        maxAttempts: 2,
        shuffle: false,
        resultsPolicy: 'when_published',
        resultsView: 'answers',
        passingPercent: 65,
        highStakes: true,
        maxDurationMinutes: 100);
    final q = QuickExam(kind: QuickKind.quiz);
    expect(q.durationMinutes, 40);
    expect(q.maxAttempts, 2);
    expect(q.shuffle, isFalse);
    expect(q.resultsPolicy, 'when_published');
    expect(q.highStakes, isTrue);
    expect(q.passingPercent, 65);
    expect(q.toExamDraft().settings['results_view'], 'answers');
    // a final keeps its own length, inside the limit
    expect(QuickExam(kind: QuickKind.finalExam).durationMinutes, 100);
    final d = ExamDraft.fromPolicy(ExamPolicy.current);
    expect(d.durationMinutes, 40);
    expect(d.maxAttempts, 2);
    expect(d.resultsPolicy, 'when_published');
    expect(d.highStakes, isTrue);
    expect(d.passingPercent, 65.0);
  });

  test('the answer key right after submitting needs an end time: it waits as "answers" without one', () {
    ExamPolicy.current = const ExamPolicy(resultsView: 'answers_key');
    final q = QuickExam(kind: QuickKind.quiz);
    expect(q.effectiveResultsView, 'answers');
    q.endsAt = DateTime.utc(2030);
    expect(q.effectiveResultsView, 'answers_key');
    expect(ExamDraft.fromPolicy(ExamPolicy.current).resultsView, 'answers');
  });

  test('the quick exam refuses what the platform refuses', () {
    ExamPolicy.current = const ExamPolicy(maxDurationMinutes: 60, allowUnlimitedAttempts: false);
    final q = QuickExam(kind: QuickKind.quiz)
      ..mode = QuickMode.online
      ..durationMinutes = 61
      ..maxAttempts = 0;
    final (codes, _) = q.validate();
    expect(codes, containsAll(['policy_duration', 'policy_unlimited_attempts']));
    expect(quickCodeText('policy_duration'), contains('60'));
  });

  test('codes and counts in words', () {
    expect(examCodeText('policy_attempts'), contains('attempts'));
    expect(examPolicyCodeText('policy_questions', limit: 40), contains('40'));
    expect(examPolicyCodeText('other'), isNull);
    expect(questionsText(1), '1 question');
    expect(questionsText(5), '5 questions');
    AppConfig.lang = 'ar';
    expect(questionsText(2), 'سؤالان');
    expect(questionsText(5), '5 أسئلة');
    expect(questionsText(12), '12 سؤالاً');
    expect(fmtScore(2.0), '2');
    expect(fmtScore(2.5), '2.5');
  });
}
