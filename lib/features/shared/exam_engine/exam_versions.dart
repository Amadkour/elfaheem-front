// Paper versions (A / B / C …) of an exam and the per-student print plan: the models and calls of the server's
// "B2" contract (docs/exam_creation/PLAN.md) plus the pure parts the paper writers use.
//
//   GET/POST /exams/{id}/versions · PUT …/versions/copies · GET …/answer-key?form= · POST …/print-plan
//
// Pure (unit-tested): ExamVersion.fromJson · applyVersion (question_order / option_orders onto a paper) ·
// versionBody · printPlanBody · PrintPlan.fromJson · copiesFor (one paper per plan item, QR payload per page) ·
// keyLinesOf.
library;

import 'package:flutter_education_app/core/api_client.dart';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import 'exam_authoring.dart' show authoringError;
import 'paper/exam_setup.dart' show versionsBubbleText;
import 'exam_engine_api.dart' show EngineResult, engineCall;
import 'exam_paper.dart';

/// The most versions the server makes (MAX_FORMS).
const kMaxVersions = 10;

class ExamVersion {
  const ExamVersion({required this.code, this.label, this.copies, this.questionOrder, this.optionOrders = const {}, this.key = const {}, this.seed, this.stale = false});
  final String code;
  final String? label;
  final int? copies;

  /// Question ids in printed order; null = the exam's own order.
  final List<int>? questionOrder;

  /// {question id: [original option index, … in printed order]}.
  final Map<int, List<int>> optionOrders;
  final Map<String, dynamic> key;
  final int? seed;

  /// Questions were placed or removed after this version was made: regenerate before printing.
  final bool stale;

  bool get shuffled => questionOrder != null || optionOrders.isNotEmpty;

  static ExamVersion fromJson(Map<String, dynamic> j) {
    final qo = j['question_order'];
    final oo = asMap(j['option_orders']);
    return ExamVersion(
      code: '${j['code'] ?? ''}'.toUpperCase(),
      label: j['label'] == null ? null : '${j['label']}',
      copies: j['copies'] == null ? null : asInt(j['copies']),
      questionOrder: qo is List ? [for (final x in qo) asInt(x)] : null,
      optionOrders: {
        for (final e in oo.entries)
          if (int.tryParse(e.key) != null && e.value is List) int.parse(e.key): [for (final x in e.value as List) asInt(x)],
      },
      key: Map<String, dynamic>.from(asMap(j['key'])),
      seed: j['seed'] == null ? null : asInt(j['seed']),
      stale: j['stale'] == true,
    );
  }
}

class ExamVersions {
  const ExamVersions({this.items = const [], this.shuffleQuestions = false, this.shuffleOptions = false, bool stale = false}) : _stale = stale;
  final List<ExamVersion> items;
  final bool _stale;

  /// The questions changed after the versions were made.
  bool get stale => _stale || items.any((v) => v.stale);
  final bool shuffleQuestions, shuffleOptions;

  static ExamVersions fromJson(Map<String, dynamic> j) => ExamVersions(
        items: [for (final v in asMapList(j['items'])) ExamVersion.fromJson(v)],
        shuffleQuestions: j['shuffle_questions'] == true,
        shuffleOptions: j['shuffle_options'] == true,
        stale: j['stale'] == true,
      );

  ExamVersion? byCode(String? code) {
    for (final v in items) {
      if (v.code == code) return v;
    }
    return null;
  }
}

/// The text of a failed versions / answer-key / print-plan call (`versions_stale` and the bubble rule in words).
String versionsErrorText(EngineResult r) => switch (r.code) {
      'versions_stale' => versionsStaleText,
      'question_shuffle_needs_paper_answers' => versionsBubbleText,
      _ => authoringError(r),
    };

String get versionsStaleText => t('تغيّرت الأسئلة بعد إنشاء النماذج — أعد إنشاءها', 'The questions changed after the versions were made — regenerate them');

/// `POST /exams/{id}/versions` body. [copies]: one number for every version (A…).
Map<String, dynamic> versionBody({required int count, required bool shuffleQuestions, required bool shuffleOptions, int? copies}) {
  final n = count < 1 ? 1 : (count > kMaxVersions ? kMaxVersions : count);
  return {
    'count': n,
    'shuffle_questions': shuffleQuestions,
    'shuffle_options': shuffleOptions,
    if (copies != null && copies > 0) 'copies': {for (var i = 0; i < n; i++) String.fromCharCode(65 + i): copies},
  };
}

/// One line of `GET …/answer-key`.
class AnswerKeyItem {
  const AnswerKeyItem(this.n, this.questionId, this.type, this.points, this.display);
  final int n, questionId;
  final String type, display;
  final double points;
}

List<AnswerKeyItem> answerKeyItems(Map<String, dynamic> j) => [
      for (final x in asMapList(j['items']))
        AnswerKeyItem(asInt(x['n']), asInt(x['question_id']), '${x['type'] ?? ''}', (x['points'] as num?)?.toDouble() ?? 0, '${x['display'] ?? ''}'),
    ];

List<PaperKeyLine> keyLinesOf(List<AnswerKeyItem> items) => [for (final i in items) PaperKeyLine(i.n, i.display)];

/// The paper in [v]'s order: questions reordered inside each section (sections stay in order) and numbered again,
/// choices in the version's option order (the key follows). A version without orders returns the paper as it is.
ExamPaperDoc applyVersion(ExamPaperDoc d, ExamVersion v) {
  final order = v.questionOrder;
  final pos = <int, int>{if (order != null) for (var i = 0; i < order.length; i++) order[i]: i};
  var n = 0;
  final sections = <PaperSection>[];
  for (final s in d.sections) {
    final qs = List<PaperQuestion>.of(s.questions);
    if (order != null) {
      // stable: questions the order does not know keep their place after the known ones
      final indexed = [for (var i = 0; i < qs.length; i++) (i, qs[i])];
      indexed.sort((a, b) {
        final pa = pos[a.$2.id] ?? (1 << 30) + a.$1, pb = pos[b.$2.id] ?? (1 << 30) + b.$1;
        return pa.compareTo(pb);
      });
      qs
        ..clear()
        ..addAll(indexed.map((e) => e.$2));
    }
    sections.add(PaperSection(title: s.title, instructions: s.instructions, questions: [for (final q in qs) _reorder(q, ++n, v.optionOrders[q.id])]));
  }
  return d.copyWith(sections: sections, version: v.code);
}

PaperQuestion _reorder(PaperQuestion q, int number, List<int>? optionOrder) {
  var options = q.options;
  var correct = q.correct;
  if (q.isChoice && optionOrder != null && optionOrder.length == q.options.length && optionOrder.every((i) => i >= 0 && i < q.options.length)) {
    options = [for (final i in optionOrder) q.options[i]];
    correct = {for (var j = 0; j < optionOrder.length; j++) if (q.correct.contains(optionOrder[j])) j};
  }
  return PaperQuestion(
      id: q.id, number: number, type: q.type, prompt: q.prompt, points: q.points, options: options, correct: correct, left: q.left, right: q.right,
      pairs: q.pairs, items: q.items, order: q.order, blanks: q.blanks, tfCorrect: q.tfCorrect, answerText: q.answerText);
}

// ── print plan ──

/// `POST /exams/{id}/print-plan` body. Named: [studentIds] (null = the whole roster). Blank: [copies].
Map<String, dynamic> printPlanBody({required bool named, List<int>? studentIds, int? copies, required int pages, String? form}) => {
      'mode': named ? 'named' : 'blank',
      if (named && studentIds != null) 'student_ids': studentIds,
      if (!named) 'copies': copies ?? 1,
      'pages': pages < 1 ? 1 : (pages > 40 ? 40 : pages),
      'form': ?form,
    };

class PrintPlanItem {
  const PrintPlanItem({required this.copyNo, this.form, this.studentId, this.studentName = '', this.identifierMasked = '', this.pages = const []});
  final int copyNo;
  final String? form;
  final int? studentId;
  final String studentName, identifierMasked;

  /// The QR payload of each page, page 1 first.
  final List<String> pages;
}

class PrintPlan {
  const PrintPlan(this.items);
  final List<PrintPlanItem> items;

  int get qrCount => items.fold(0, (s, i) => s + i.pages.length);

  static PrintPlan fromJson(Map<String, dynamic> j) => PrintPlan([
        for (final x in asMapList(j['items']))
          PrintPlanItem(
            copyNo: asInt(x['copy_no']),
            form: x['form'] == null ? null : '${x['form']}',
            studentId: x['student'] is Map ? asInt(asMap(x['student'])['id']) : null,
            studentName: x['student'] is Map ? '${asMap(x['student'])['name'] ?? ''}' : '',
            identifierMasked: x['student'] is Map ? '${asMap(x['student'])['identifier_masked'] ?? ''}' : '',
            pages: [for (final p in (x['pages'] as List?) ?? const []) '$p'],
          ),
      ]);
}

/// One paper per plan item: the item's version applied, its student's name and one QR per page. A copy whose version
/// has fewer pages than the plan's keeps only its own pages' QRs ([pagesOf] by version code, null = the plan's).
List<ExamPaperDoc> copiesFor(ExamPaperDoc base, PrintPlan plan, ExamVersions versions, {Map<String?, int> pagesOf = const {}}) {
  final out = <ExamPaperDoc>[];
  for (final item in plan.items) {
    final v = versions.byCode(item.form);
    var doc = v == null ? base : applyVersion(base, v);
    final own = pagesOf[item.form];
    final qr = own == null || own >= item.pages.length ? item.pages : item.pages.sublist(0, own);
    doc = doc.copyWith(studentName: item.studentName, qrPages: qr);
    out.add(doc);
  }
  return out;
}

class ExamVersionsApi {
  ExamVersionsApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _b = '/api/v1/exam';

  Future<EngineResult> versions(int examId) => engineCall(() => _api.get('$_b/exams/$examId/versions'));
  Future<EngineResult> generate(int examId, Map<String, dynamic> body) => engineCall(() => _api.post('$_b/exams/$examId/versions', body: body));
  Future<EngineResult> setCopies(int examId, Map<String, int> copies) => engineCall(() => _api.put('$_b/exams/$examId/versions/copies', body: copies));
  Future<EngineResult> answerKey(int examId, {String? form}) =>
      engineCall(() => _api.get('$_b/exams/$examId/answer-key', queryParams: {'form': ?form}));
  Future<EngineResult> printPlan(int examId, Map<String, dynamic> body) => engineCall(() => _api.post('$_b/exams/$examId/print-plan', body: body));
}
