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
import 'exam_paper_bands.dart' show ExamPaperCopy, PaperPrintedId;

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

/// A version's icon says "shuffled" only when it differs from version A (the first one, the exam's own order).
bool versionShuffled(ExamVersion v, ExamVersion? a) {
  if (v.optionOrders.isNotEmpty) return true;
  final o = v.questionOrder, base = a?.questionOrder;
  if (o == null) return false;
  if (base == null || base.length != o.length) return true;
  for (var i = 0; i < o.length; i++) {
    if (o[i] != base[i]) return true;
  }
  return false;
}

/// The words for a warning code of `POST /exams/{id}/versions` (an unknown code is not shown raw).
String versionWarningText(String code) => switch (code) {
      'nothing_shuffled' => t('لم يتغيّر شيء بين النماذج: فعّل خلط الأسئلة أو الاختيارات وأنشئ مرة أخرى.', 'Nothing differs between the versions: turn on shuffling the questions or the choices and generate again.'),
      'identifier_not_set' => t('لم تحدّد كيف يُعرَّف الطالب على الورقة بعد: افتح «إعداد الاختبار الورقي» واختر طريقة.', 'How a student is identified on the paper isn\'t set yet: open the paper setup and choose a way.'),
      'form_markers_required' => t('لكل نموذج علامة تميّزه على الورقة (رمز QR أو رقم مطبوع أو فقاعة): اختر طريقة في إعداد الاختبار الورقي.', 'Each version needs a mark that tells it apart on the paper (a QR code, a printed number or a bubble): choose one in the paper setup.'),
      'form_markers_unused' => t('هناك علامات للنماذج لكن يوجد نموذج واحد فقط، فلن تُستخدم.', 'Version marks are set but there is only one version, so they won\'t be used.'),
      'identifier_zone_mismatch' => t('خانة رقم الطالب في ورقة التظليل لا تتسع لمعرّف الطلاب: اختر نوع ورقة آخر أو طريقة تعريف أخرى.', 'The student-ID area of the bubble sheet cannot hold the identifier of the students: pick another sheet type or another way to identify them.'),
      'identifier_zone_may_not_fit' => t('قد لا تتسع خانة رقم الطالب في ورقة التظليل لبعض المعرّفات: راجع الإعداد.', 'The student-ID area of the bubble sheet may not fit some identifiers: check the setup.'),
      _ => code.contains(' ') ? code : t('تنبيه من الخادم عند إنشاء النماذج. راجع النماذج قبل الطباعة.', 'The server raised a warning while making the versions. Check them before printing.'),
    };

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

/// The key summary printed with [d]: numbered by the paper's own numbering (matched on question id, the server's `n`
/// counts paper sections only) and, for choice questions, drawn with the paper's own letters and its remapped correct index.
/// Other types keep the server's display text. Questions the server's key lacks are left out.
List<PaperKeyLine> keyLinesForPaper(ExamPaperDoc d, List<AnswerKeyItem> items) {
  final byId = {for (final i in items) i.questionId: i};
  final out = <PaperKeyLine>[];
  for (final s in d.sections) {
    for (final q in s.questions) {
      final item = byId[q.id];
      if (item == null) continue;
      if (q.isChoice && q.correct.isNotEmpty) {
        final letters = ([...q.correct]..sort()).map((i) => choiceLetter(i, rtl: d.rtl));
        out.add(PaperKeyLine(q.number, letters.join(d.rtl ? '، ' : ', ')));
      } else {
        out.add(PaperKeyLine(q.number, item.display));
      }
    }
  }
  return out;
}

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
      pairs: q.pairs, items: q.items, order: q.order, blanks: q.blanks, tfCorrect: q.tfCorrect, answerText: q.answerText, mediaId: q.mediaId,
      mediaAlt: q.mediaAlt, image: q.image, imageFailed: q.imageFailed);
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
  const PrintPlanItem({required this.copyNo, this.form, this.studentId, this.studentName = '', this.identifierMasked = '', this.pages = const [], this.identifiers = const []});
  final int copyNo;
  final String? form;
  final int? studentId;
  final String studentName, identifierMasked;

  /// The QR payload of each page, page 1 first.
  final List<String> pages;

  /// `student.identifiers`: what is printed on this copy (masked by the server where the rules say so).
  final List<PaperPrintedId> identifiers;
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
            identifiers: x['student'] is Map
                ? [for (final i in asMapList(asMap(x['student'])['identifiers'])) PaperPrintedId(labelAr: '${i['label_ar'] ?? ''}', labelEn: '${i['label_en'] ?? ''}', value: '${i['value'] ?? ''}')]
                : const [],
          ),
      ]);
}

/// One paper per plan item: the item's version applied, its student's name and one QR per page. A copy whose version
/// has fewer pages than the plan's keeps only its own pages' QRs ([pagesOf] by version code, null = the plan's).
/// A named copy prints its student's identifiers; a blank copy shows [blankIds] (labels only) to write in by hand.
List<ExamPaperDoc> copiesFor(ExamPaperDoc base, PrintPlan plan, ExamVersions versions, {Map<String?, int> pagesOf = const {}, List<PaperPrintedId> blankIds = const []}) {
  final out = <ExamPaperDoc>[];
  for (final item in plan.items) {
    final v = versions.byCode(item.form);
    var doc = v == null ? base : applyVersion(base, v);
    final own = pagesOf[item.form];
    final qr = own == null || own >= item.pages.length ? item.pages : item.pages.sublist(0, own);
    doc = doc.copyWith(studentName: item.studentName, qrPages: qr);
    final ids = item.studentId != null ? item.identifiers : blankIds;
    out.add(ids.isEmpty ? doc : ExamPaperCopy.of(doc, ids));
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
