// Fix the key from the item analysis (D-664): a choice or true / false question the analysis flagged (too hard, weak or
// negative discrimination, a suspect key) can get its correct answer changed from the results, then this question's
// answers are re-marked. The key is saved through the question bank's edit (`PUT /questions/{id}`, a new version) and the
// re-marking is the engine's own `POST /exams/{id}/regrade {question_id}`; the grade log already records what it moves.
// Limit (D-664): the engine re-marks only undecided answers, with the exam's PINNED question version, so no mark moves to
// the new key until the server gains a key-fix route; the texts never promise more than that.
// The screens are key_fix_sheet.dart (the sheet, the confirm and the progress) and the results' "Check these keys" card.
//
// Pure (unit-tested): kKeyFixFlags · keyFixable · keyFixCandidates · keyFixBody · keyFixAnswerOf · the texts.
library;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';

import '../../../../admin/admin_common.dart' show asMap, t;
import '../../exam_authoring.dart' show ExamView, authoringError;
import '../../exam_engine_api.dart' show EngineResult, engineCall;
import '../../exam_insights.dart' show ExamAnalytics, ItemStat, OptionStat, itemFlagText;

/// The flags that make a key worth checking.
const kKeyFixFlags = {'negative', 'key_suspect', 'too_hard', 'weak_discrimination'};

/// The question types whose key is one pick (or several) the teacher can change here.
bool keyFixable(String type) => type == 'mcq_single' || type == 'mcq_multi' || type == 'true_false';

/// One answer the teacher may mark correct, with what the class chose (null when the analysis has no per-option rows).
class KeyFixOption {
  const KeyFixOption(this.id, this.text, {this.share, this.upperShare});
  final String id, text;

  /// Share of the class (0..1) and of the top group that chose it.
  final double? share, upperShare;
}

/// A flagged question whose key can be fixed.
class KeyFixCandidate {
  const KeyFixCandidate({required this.questionId, required this.n, required this.type, required this.prompt, required this.options,
      required this.correct, required this.flags, required this.body, required this.answer});
  final int questionId;

  /// Its number on the paper (1-based, across sections).
  final int n;
  final String type, prompt;
  final List<KeyFixOption> options;

  /// The ids marked correct now ('true' / 'false' for a true / false question).
  final Set<String> correct;
  final List<String> flags;

  /// The pinned version's body and key, sent back whole with the new `correct`.
  final Map<String, dynamic> body, answer;

  bool get multi => type == 'mcq_multi';

  /// The strongest reason first: negative and suspect keys before the rest.
  String get reason => itemFlagText(flags.firstWhere((f) => f == 'negative' || f == 'key_suspect', orElse: () => flags.first));
}

String _optionId(Object? o) => o is Map ? '${o['id']}' : '$o';
String _optionText(Object? o) => o is Map ? '${o['text'] ?? o['id'] ?? ''}' : '$o';

/// The flagged objective questions of [view], in paper order; cancelled ones and questions with nothing flagged are left out.
List<KeyFixCandidate> keyFixCandidates(ExamView view, ExamAnalytics? analytics) {
  if (analytics == null) return const [];
  final items = {for (final it in analytics.items) it.questionId: it};
  final out = <KeyFixCandidate>[];
  var n = 0;
  for (final s in view.sections) {
    for (final p in s.questions) {
      n++;
      final it = items[p.questionId];
      if (it == null || it.voided || !keyFixable(p.type)) continue;
      final flags = [for (final f in it.flags) if (kKeyFixFlags.contains(f)) f];
      if (flags.isEmpty) continue;
      final body = asMap(p.raw['body']);
      final answer = asMap(p.raw['answer']);
      out.add(KeyFixCandidate(
        questionId: p.questionId, n: n, type: p.type, prompt: p.prompt, options: _options(p.type, body, it), correct: _correctOf(p.type, answer),
        flags: flags, body: body, answer: answer,
      ));
    }
  }
  return out;
}

List<KeyFixOption> _options(String type, Map<String, dynamic> body, ItemStat it) {
  OptionStat? stat(String id) {
    for (final o in it.optionStats) {
      if (o.key == id) return o;
    }
    return null;
  }

  KeyFixOption make(String id, String text) {
    final s = stat(id);
    return KeyFixOption(id, text, share: s?.share, upperShare: s?.upperShare);
  }

  if (type == 'true_false') return [make('true', t('صح', 'True')), make('false', t('خطأ', 'False'))];
  return [for (final o in (body['options'] as List?) ?? const []) make(_optionId(o), _optionText(o))];
}

Set<String> _correctOf(String type, Map<String, dynamic> answer) {
  final c = answer['correct'];
  if (type == 'true_false') return c is bool ? {'$c'} : const {};
  if (c is List) return {for (final x in c) '$x'};
  return c == null ? const {} : {'$c'};
}

/// The key's `correct` for [picked] in the engine's shape: one id, a list, or a bool.
Object keyFixAnswerOf(String type, Set<String> picked) => switch (type) {
      'true_false' => picked.contains('true'),
      'mcq_multi' => [...picked],
      _ => picked.first,
    };

/// The `PUT /questions/{id}` body: the same body and key with the new correct answer (points, tags and difficulty unsent,
/// so the bank keeps them).
Map<String, dynamic> keyFixBody(KeyFixCandidate c, Set<String> picked) => {
      'body': c.body,
      'answer': {...c.answer, 'correct': keyFixAnswerOf(c.type, picked)},
    };

/// A pick the sheet may save: not empty, one answer for a single choice / true-false, and not the key it already has.
bool keyFixReady(KeyFixCandidate c, Set<String> picked) =>
    picked.isNotEmpty && (c.multi || picked.length == 1) && !(picked.length == c.correct.length && picked.containsAll(c.correct));

String get keyFixConfirmText => t(
    'تُحفظ الإجابة الصحيحة كنسخة جديدة من السؤال في بنك الأسئلة، ثم تُصحَّح من جديد إجابات هذا السؤال التي ما زالت بانتظار قرار. الدرجات المعتمدة لا تتغير، فهذا الاختبار يحتفظ بنسخة السؤال التي نُشر بها. كل تغيير يُسجَّل في سجل الدرجات.',
    'The correct answer is saved as a new version of the question in the bank, then this question\'s answers still waiting for a decision are marked again. Final marks do not change: this exam keeps the question version it was published with. Every change is written to the grade log.');

/// After the regrade call: how many attempts went back to the grader.
String keyFixQueuedText(int attempts) => countText(attempts,
    ar1: 'يُعاد تصحيح محاولة واحدة', ar2: 'يُعاد تصحيح محاولتين', arFew: 'يُعاد تصحيح {n} محاولات', arMany: 'يُعاد تصحيح {n} محاولة',
    en1: 'Marking 1 attempt again', en: 'Marking {n} attempts again');

/// Nothing went back to the grader: every answer to this question is already final.
String get keyFixNothingText => t(
    'حُفظ المفتاح في بنك الأسئلة. لا توجد إجابة لهذا السؤال بانتظار قرار، فلم تتغير أي درجة. لإزالة أثر السؤال من الدرجات استخدم "إلغاء هذا السؤال" في تحليل الأسئلة.',
    'The key is saved in the question bank. No answer to this question was waiting for a decision, so no mark changed. To take the question out of the marks, use "Cancel this question" in the item analysis.');

String keyFixDoneText(int attempts) => countText(attempts,
    ar1: 'انتهى تصحيح محاولة واحدة من جديد', ar2: 'انتهى تصحيح محاولتين من جديد', arFew: 'انتهى تصحيح {n} محاولات من جديد',
    arMany: 'انتهى تصحيح {n} محاولة من جديد', en1: '1 attempt is marked again', en: '{n} attempts are marked again');

/// The server's refusal in words (its own text when the code is not one we know).
String keyFixErrorText(EngineResult r) => r.code == 'feature_disabled'
    ? t('إعادة التصحيح الآلي متوقفة على المنصة. حُفظ المفتاح فقط.', 'Automatic marking is switched off on the platform. Only the key was saved.')
    : authoringError(r);

class KeyFixApi {
  KeyFixApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _b = '/api/v1/exam';

  Future<EngineResult> saveKey(int questionId, Map<String, dynamic> body) => engineCall(() => _api.put('$_b/questions/$questionId', body: body));

  /// `{attempts}`: how many attempts went back to the grader.
  Future<EngineResult> regrade(int examId, int questionId) => engineCall(() => _api.post('$_b/exams/$examId/regrade', body: {'question_id': questionId}));

  /// The open review rows of one question (`queued` = still waiting for the grader).
  Future<EngineResult> openAnswers(int examId, int questionId) =>
      engineCall(() => _api.get('$_b/exams/$examId/review', queryParams: {'state': 'open', 'question_id': questionId, 'limit': 100}));
}

/// How many of [review]'s rows still wait for the grader.
int keyFixWaiting(Map<String, dynamic> review) {
  final items = (review['items'] as List?) ?? const [];
  return items.where((x) => x is Map && x['review_state'] == 'queued').length;
}
