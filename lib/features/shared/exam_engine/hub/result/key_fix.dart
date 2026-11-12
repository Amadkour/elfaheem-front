// Fix the key from the item analysis (D-664, D-666): a choice or true / false question the analysis flagged (too hard, weak
// or negative discrimination, a suspect key) can get its correct answer changed from the results. One call does it all,
// `POST /exams/{id}/questions/{qid}/key {correct, reason?}` (back D-653): the fix is stored on THIS exam (the question bank
// keeps its key), every answer to the question is marked again at once (final ones too), the totals move, a mark the
// teacher gave by hand is kept, and the grade log records the key change and every moved mark. When the results are
// published, students see the new marks straight away. Synchronous: no job to follow.
// The screens are key_fix_sheet.dart (the sheet and the confirm) and the results' "Check these keys" card.
//
// Pure (unit-tested): kKeyFixFlags · keyFixable · keyFixCandidates · keyFixRequest · keyFixAnswerOf · KeyFixOutcome · the texts.
library;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';

import '../../../../admin/admin_common.dart' show asInt, asMap, t;
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

/// The key-fix body: the picked answers as a list (`[true]` / `[false]` for a true / false question).
Map<String, dynamic> keyFixRequest(KeyFixCandidate c, Set<String> picked, {String? reason}) {
  final a = keyFixAnswerOf(c.type, picked);
  return {
    'correct': a is List ? a : [a],
    if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
  };
}

/// A pick the sheet may save: not empty, one answer for a single choice / true-false, and not the key it already has.
bool keyFixReady(KeyFixCandidate c, Set<String> picked) =>
    picked.isNotEmpty && (c.multi || picked.length == 1) && !(picked.length == c.correct.length && picked.containsAll(c.correct));

String get keyFixConfirmText => t(
    'تتغير الإجابة الصحيحة في هذا الاختبار وحده، ويبقى السؤال في بنك الأسئلة كما هو. تُصحَّح الآن كل إجابات هذا السؤال من جديد، ومنها الدرجات المعتمدة، فتتغير المجاميع. الدرجة التي وضعتها بنفسك لإجابة ما تبقى كما هي. إن كانت النتائج منشورة يرى الطلاب الدرجات الجديدة فورًا. كل تغيير يُسجَّل في سجل الدرجات.',
    'The correct answer changes for this exam only; the question bank keeps its own. Every answer to this question is marked again now, final marks included, so totals change. A mark you gave by hand stays as it is. If the results are published, students see the new marks at once. Every change is written to the grade log.');

/// What the key fix did (the route's reply).
class KeyFixOutcome {
  const KeyFixOutcome({this.answersChanged = 0, this.attemptsChanged = 0, this.manualKept = 0, this.waiting = 0, this.resultsPublished = false});

  factory KeyFixOutcome.fromJson(Map<String, dynamic> j) => KeyFixOutcome(
        answersChanged: asInt(j['answers_changed']),
        attemptsChanged: asInt(j['attempts_changed']),
        manualKept: asInt(j['manual_kept']),
        waiting: asInt(j['waiting']),
        resultsPublished: j['results_published'] == true,
      );

  final int answersChanged, attemptsChanged, manualKept, waiting;
  final bool resultsPublished;
}

/// The notice after a fix: how many results moved, then what was kept or is still open, then who sees it.
String keyFixOutcomeText(KeyFixOutcome o) {
  final parts = <String>[
    o.attemptsChanged == 0
        ? t('حُفظ المفتاح. لم تتغير أي درجة: لا توجد إجابة تتأثر به.', 'The key is saved. No mark changed: no answer is affected by it.')
        : countText(o.attemptsChanged,
            ar1: 'حُفظ المفتاح وتغيرت نتيجة طالب واحد', ar2: 'حُفظ المفتاح وتغيرت نتيجتا طالبين', arFew: 'حُفظ المفتاح وتغيرت نتائج {n} طلاب',
            arMany: 'حُفظ المفتاح وتغيرت نتائج {n} طالبًا', en1: 'The key is saved and 1 result changed', en: 'The key is saved and {n} results changed'),
    if (o.manualKept > 0)
      countText(o.manualKept,
          ar1: 'بقيت درجة واحدة وضعتها بنفسك', ar2: 'بقيت درجتان وضعتهما بنفسك', arFew: 'بقيت {n} درجات وضعتها بنفسك', arMany: 'بقيت {n} درجة وضعتها بنفسك',
          en1: '1 mark you gave by hand is kept', en: '{n} marks you gave by hand are kept'),
    if (o.waiting > 0)
      countText(o.waiting,
          ar1: 'وإجابة واحدة بانتظار قرارك تُصحَّح بالمفتاح الجديد', ar2: 'وإجابتان بانتظار قرارك تُصحَّحان بالمفتاح الجديد',
          arFew: 'و{n} إجابات بانتظار قرارك تُصحَّح بالمفتاح الجديد', arMany: 'و{n} إجابة بانتظار قرارك تُصحَّح بالمفتاح الجديد',
          en1: '1 answer waiting for your decision uses the new key', en: '{n} answers waiting for your decision use the new key'),
    if (o.resultsPublished && o.attemptsChanged > 0) t('النتائج منشورة: يرى الطلاب الدرجات الجديدة الآن.', 'The results are published: students see the new marks now.'),
  ];
  return [for (final p in parts) p.endsWith('.') ? p : '$p.'].join(' ');
}

/// The server's refusal in words (its own text when the code is not one we know).
String keyFixErrorText(EngineResult r) => switch (r.code) {
      'key_unchanged' => t('هذه هي الإجابة الصحيحة الحالية.', 'That is already the correct answer.'),
      'question_voided' => t('السؤال ملغى. استعده أولًا لتغيير مفتاحه.', 'The question is cancelled. Restore it first to change its key.'),
      'form_keys_own' => t('مفاتيح نماذج هذا الاختبار أدخلتها بنفسك: صحّح المفتاح في إعداد ورقة التظليل.',
          'This exam has answer keys you typed per paper version: fix the key in the bubble sheet setup.'),
      _ => authoringError(r),
    };

class KeyFixApi {
  KeyFixApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _b = '/api/v1/exam';

  /// Saves the fixed key on this exam and marks every answer again (one synchronous call, D-666).
  Future<EngineResult> fixKey(int examId, int questionId, Map<String, dynamic> body) =>
      engineCall(() => _api.post('$_b/exams/$examId/questions/$questionId/key', body: body));
}
