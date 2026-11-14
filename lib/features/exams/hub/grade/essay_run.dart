// Grade Papers, essay path (D-662), the pure part: grade photographed written answers against a model answer or a
// rubric without an exam made in the app first. The engine's "essay run" (back D-651, `exam_engine/services/
// essay_runs.py`) is a hidden paper exam, so reading, the suggestion, the review decisions, the results and the export
// are the existing paper-exam machinery; this file holds what the screens draw: the question drafts (fast add, paste
// many at once), the run as the server sends it, the order answers are checked in (uncertain first), server codes in
// words and the calls. Never decide a mark here: the suggestion and what is final are the engine's.
library;

import 'dart:typed_data';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/live_events.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, t;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult, engineCall;
import 'package:flutter_education_app/features/exams/exam_autograde.dart' show AutoGrade;
import 'package:flutter_education_app/features/exams/paper/review/omr_review.dart' show OmrReviewApi, kOmrReviewEventKind;

/// The Super Admin's switch of the whole path (the engine answers 403 `feature_disabled` too).
const kEssayRunFeature = 'exam.essay_run';

/// `job_updated {kind: essay_run, exam_id, page_id, status, waiting}` after each page is read.
const kEssayRunEventKind = 'essay_run';

const kEssayMaxQuestions = 50;
const kEssayMaxCriteria = 12;

/// Pages of one student's paper in one upload, and pages of one answer (the engine stitches them into one image).
const kEssayMaxPages = 12;
const kEssayMaxPagesPerAnswer = 4;

// ── the question drafts ─────────────────────────────────────────────────────────────────────────────────────────

class EssayCriterionDraft {
  EssayCriterionDraft({this.criterion = '', this.points, this.model = ''});
  String criterion;
  double? points;
  String model;

  Map<String, dynamic> toJson() => {'criterion': criterion.trim(), 'points': points, if (model.trim().isNotEmpty) 'model': model.trim()};
}

class EssayQuestionDraft {
  EssayQuestionDraft({this.prompt = '', this.points, this.modelAnswer = '', List<EssayCriterionDraft>? criteria}) : criteria = criteria ?? [];
  String prompt;
  double? points;
  String modelAnswer;
  final List<EssayCriterionDraft> criteria;

  bool get usesRubric => criteria.isNotEmpty;

  /// The criteria's marks added up (null without a rubric or while one is missing).
  double? get rubricTotal {
    if (criteria.isEmpty || criteria.any((c) => c.points == null)) return null;
    return criteria.fold<double>(0, (s, c) => s + c.points!);
  }

  /// The question's mark: the rubric's total when it has one, else [points].
  double? get mark => usesRubric ? rubricTotal : points;

  Map<String, dynamic> toJson() => {
        if (prompt.trim().isNotEmpty) 'prompt': prompt.trim(),
        if (mark != null) 'points': mark,
        if (modelAnswer.trim().isNotEmpty) 'model_answer': modelAnswer.trim(),
        if (usesRubric) 'rubric': [for (final c in criteria) c.toJson()],
      };
}

/// What stops the drafts from being sent, in words naming the question; null when they can go.
String? essayDraftProblem(String title, List<EssayQuestionDraft> qs) {
  if (title.trim().isEmpty) return t('اكتب اسمًا لهذا التصحيح', 'Give this correction a name');
  if (qs.isEmpty) return t('أضف سؤالًا واحدًا على الأقل', 'Add at least one question');
  if (qs.length > kEssayMaxQuestions) return t('حتى $kEssayMaxQuestions سؤالًا', 'Up to $kEssayMaxQuestions questions');
  for (var i = 0; i < qs.length; i++) {
    final q = qs[i], n = i + 1;
    if (q.usesRubric) {
      if (q.criteria.length > kEssayMaxCriteria) return t('السؤال $n: حتى $kEssayMaxCriteria معيارًا', 'Question $n: up to $kEssayMaxCriteria criteria');
      for (final c in q.criteria) {
        if (c.criterion.trim().isEmpty || c.points == null || c.points! <= 0) {
          return t('السؤال $n: كل معيار يحتاج وصفًا ودرجة', 'Question $n: every criterion needs a description and a mark');
        }
      }
    } else {
      if (q.modelAnswer.trim().isEmpty) return t('السؤال $n يحتاج إجابة نموذجية أو معايير', 'Question $n needs a model answer or criteria');
      if (q.points == null || q.points! <= 0) return t('السؤال $n يحتاج درجة', 'Question $n needs a mark');
    }
    if ((q.mark ?? 0) > 1000) return t('درجة السؤال $n كبيرة جدًا', 'The mark of question $n is too large');
  }
  return null;
}

String _latinDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩', fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = ar.indexOf(ch), j = fa.indexOf(ch);
    b.write(i >= 0 ? '$i' : (j >= 0 ? '$j' : (ch == '٫' ? '.' : ch)));
  }
  return b.toString();
}

final _numbered = RegExp(r'^\s*(?:q|question|س|سؤال|السؤال)?\s*\d+\s*[\).:\-–]\s*(.*)$', caseSensitive: false);
final _mark = RegExp(r'[\(\[]\s*(\d+(?:\.\d+)?)\s*(?:marks?|points?|pts?|درجات|درجة|د)?\s*[\)\]]\s*$|(?:[\-–—|:]|\s)\s*(\d+(?:\.\d+)?)\s*(?:marks?|points?|pts?|درجات|درجة)\s*$',
    caseSensitive: false);
final _answer = RegExp(r'^\s*(?:answer|model answer|model|a|الإجابة النموذجية|الإجابة|الاجابة|ج)\s*[:：]\s*(.*)$', caseSensitive: false);
final _bullet = RegExp(r'^\s*[\-\*•▪◦]\s+(.*)$');

/// (text without its mark, the mark) for "Explain photosynthesis (5)" / "… - 5 marks" / "… [٣ درجات]".
(String, double?) essaySplitMark(String line) {
  final s = _latinDigits(line).trim();
  final m = _mark.firstMatch(s);
  if (m == null) return (s, null);
  final v = double.tryParse(m.group(1) ?? m.group(2) ?? '');
  return (s.substring(0, m.start).trim(), v);
}

/// Questions pasted at once: numbered lines ("1) …", "Q2: …", "س٣- …") or, without numbers, blocks separated by an
/// empty line. In a question: a mark at the end of its first line, "Answer: …" lines = the model answer, "- … (2)"
/// bullets = rubric criteria, any other line continues the prompt (or the model answer once one started).
List<EssayQuestionDraft> parseEssayPaste(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final numbered = lines.any((l) => _numbered.hasMatch(_latinDigits(l)));
  final blocks = <List<String>>[];
  for (final raw in lines) {
    final l = _latinDigits(raw);
    if (numbered) {
      final m = _numbered.firstMatch(l);
      if (m != null && !_answer.hasMatch(l)) {
        blocks.add([m.group(1) ?? '']);
      } else if (blocks.isNotEmpty && l.trim().isNotEmpty) {
        blocks.last.add(l);
      }
    } else if (l.trim().isEmpty) {
      if (blocks.isNotEmpty && blocks.last.isNotEmpty) blocks.add([]);
    } else {
      if (blocks.isEmpty) blocks.add([]);
      blocks.last.add(l);
    }
  }
  final out = <EssayQuestionDraft>[];
  for (final b in blocks.where((b) => b.any((l) => l.trim().isNotEmpty))) {
    final (first, mark) = essaySplitMark(b.first);
    final q = EssayQuestionDraft(prompt: first, points: mark);
    var inAnswer = false;
    for (final l in b.skip(1)) {
      final a = _answer.firstMatch(l), c = _bullet.firstMatch(l);
      if (a != null) {
        q.modelAnswer = [q.modelAnswer, (a.group(1) ?? '').trim()].where((x) => x.isNotEmpty).join('\n');
        inAnswer = true;
      } else if (c != null) {
        final (crit, pts) = essaySplitMark(c.group(1) ?? '');
        q.criteria.add(EssayCriterionDraft(criterion: crit, points: pts));
      } else if (inAnswer) {
        q.modelAnswer = '${q.modelAnswer}\n${l.trim()}'.trim();
      } else {
        q.prompt = '${q.prompt}\n${l.trim()}'.trim();
      }
    }
    if (q.usesRubric && q.rubricTotal != null) q.points = q.rubricTotal;
    out.add(q);
  }
  return out.take(kEssayMaxQuestions).toList();
}

// ── the run as the server sends it ──────────────────────────────────────────────────────────────────────────────

double? _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
List<Map<String, dynamic>> _maps(Object? v) => v is List ? [for (final x in v) if (x is Map) asMap(x)] : const [];
List<String> _strings(Object? v) => v is List ? [for (final x in v) '$x'] : const [];

class EssayCriterion {
  const EssayCriterion({required this.criterion, required this.points, this.model});
  final String criterion;
  final double points;
  final String? model;

  factory EssayCriterion.fromJson(Map<String, dynamic> m) =>
      EssayCriterion(criterion: '${m['criterion'] ?? ''}', points: _d(m['points']) ?? 0, model: m['model'] as String?);
}

class EssayQuestion {
  const EssayQuestion({required this.n, required this.questionId, required this.prompt, required this.points, this.modelAnswer, this.rubric = const []});
  final int n, questionId;
  final String prompt;
  final double points;
  final String? modelAnswer;
  final List<EssayCriterion> rubric;

  factory EssayQuestion.fromJson(Map<String, dynamic> m) => EssayQuestion(
        n: asInt(m['n'], 0),
        questionId: asInt(m['question_id'], 0),
        prompt: '${m['prompt'] ?? ''}',
        points: _d(m['points']) ?? 0,
        modelAnswer: m['model_answer'] as String?,
        rubric: [for (final c in _maps(m['rubric'])) EssayCriterion.fromJson(c)],
      );
}

/// One rubric criterion's banded suggestion (grading/paper.py `rubric_parts`).
class EssayRubricPart {
  const EssayRubricPart({required this.criterion, required this.points, required this.suggested, required this.band, this.similarity});
  final String criterion, band;
  final double points, suggested;
  final double? similarity;

  factory EssayRubricPart.fromJson(Map<String, dynamic> m) => EssayRubricPart(
      criterion: '${m['criterion'] ?? ''}', points: _d(m['points']) ?? 0, suggested: _d(m['suggested_score']) ?? 0, band: '${m['band'] ?? ''}', similarity: _d(m['similarity']));
}

/// The engine's review item for one answer: its suggestion and the evidence behind it.
class EssaySuggestion {
  const EssaySuggestion({
    required this.itemId,
    required this.status,
    this.suggested,
    this.band,
    this.similarity,
    this.reasons = const [],
    this.found = const [],
    this.missing = const [],
    this.rubric = const [],
    this.readText = '',
    this.confidence,
    this.cropUrl,
    this.pending = false,
    this.decidedScore,
    this.decision,
    this.auto,
  });
  final int itemId;
  final String status;
  final double? suggested, similarity, confidence;
  final String? band, cropUrl, decision;
  final List<String> reasons, found, missing;
  final List<EssayRubricPart> rubric;
  final String readText;
  final bool pending;
  final double? decidedScore;

  /// The grading tiers' suggestion (contract A4, D-688); null from an older engine.
  final AutoGrade? auto;

  bool get open => status == 'open';

  factory EssaySuggestion.fromJson(Map<String, dynamic> m) {
    final r = asMap(m['reading']);
    final kws = _maps(r['keywords']);
    final res = asMap(m['resolution']);
    return EssaySuggestion(
      itemId: asInt(m['id'], 0),
      status: '${m['status'] ?? ''}',
      suggested: _d(r['suggested_score']),
      band: r['band'] as String?,
      similarity: _d(r['similarity']),
      reasons: _strings(r['reasons']),
      found: [for (final k in kws) if (k['found'] != null && k['found'] != false) '${k['term'] ?? ''}'],
      missing: r['missing_keywords'] is List ? _strings(r['missing_keywords']) : [for (final k in kws) if (k['found'] == null || k['found'] == false) '${k['term'] ?? ''}'],
      rubric: [for (final p in _maps(r['rubric'])) EssayRubricPart.fromJson(p)],
      readText: '${r['text'] ?? asMap(r['reading'])['text'] ?? ''}',
      confidence: _d(asMap(r['reading'])['confidence']),
      cropUrl: m['crop_url'] as String?,
      pending: r['pending'] == true,
      decidedScore: _d(res['score']),
      decision: res['action'] as String?,
      auto: AutoGrade.fromJson(r['auto']),
    );
  }
}

enum EssayAnswerState { waiting, review, done, missing }

EssayAnswerState _state(Object? v) => switch ('$v') {
      'waiting' => EssayAnswerState.waiting,
      'review' => EssayAnswerState.review,
      'done' => EssayAnswerState.done,
      _ => EssayAnswerState.missing,
    };

class EssayAnswer {
  const EssayAnswer({required this.n, required this.questionId, required this.state, this.pageId, this.finalScore, this.text, this.quality = const [], this.suggestion});
  final int n, questionId;
  final EssayAnswerState state;
  final int? pageId;
  final double? finalScore;
  final String? text;

  /// The page's image quality codes (blurred, too_dark, too_bright, low_contrast, too_small).
  final List<String> quality;
  final EssaySuggestion? suggestion;

  /// The reading itself is in doubt: the teacher checks these first.
  bool get uncertain {
    final s = suggestion;
    if (s == null) return state == EssayAnswerState.review;
    return quality.isNotEmpty || s.suggested == null || s.pending || s.reasons.any((r) => r == 'reading_uncertain' || r == 'empty' || r == 'similarity_uncalibrated');
  }

  factory EssayAnswer.fromJson(Map<String, dynamic> m) => EssayAnswer(
        n: asInt(m['n'], 0),
        questionId: asInt(m['question_id'], 0),
        state: _state(m['state']),
        pageId: m['page_id'] == null ? null : asInt(m['page_id'], 0),
        finalScore: _d(m['final_score']),
        text: m['text'] as String?,
        quality: _strings(m['quality_warnings']),
        suggestion: m['item'] is Map ? EssaySuggestion.fromJson(asMap(m['item'])) : null,
      );
}

class EssayStudent {
  const EssayStudent({required this.id, required this.name, this.attemptId, this.score, this.maxScore, this.open = 0, this.waiting = 0, this.answers = const []});
  final int id;
  final String name;
  final int? attemptId;
  final double? score, maxScore;
  final int open, waiting;
  final List<EssayAnswer> answers;

  bool get finished => open == 0 && waiting == 0;

  factory EssayStudent.fromJson(Map<String, dynamic> m) {
    final id = asInt(m['student_id'], 0);
    final name = '${m['name'] ?? ''}'.trim();
    return EssayStudent(
      id: id,
      name: name.isEmpty ? t('طالب #$id', 'Student #$id') : name,
      attemptId: m['attempt_id'] == null ? null : asInt(m['attempt_id'], 0),
      score: _d(m['score']),
      maxScore: _d(m['max_score']),
      open: asInt(m['open'], 0),
      waiting: asInt(m['waiting'], 0),
      answers: [for (final a in _maps(m['answers'])) EssayAnswer.fromJson(a)],
    );
  }
}

class EssayRun {
  const EssayRun({
    required this.id,
    required this.title,
    this.courseId,
    this.orgId,
    this.questions = const [],
    this.maxScore = 0,
    this.students = const [],
    this.pages = 0,
    this.waiting = 0,
    this.open = 0,
    this.done = 0,
    this.published = false,
  });
  final int id;
  final String title;
  final int? courseId, orgId;
  final List<EssayQuestion> questions;
  final double maxScore;
  final List<EssayStudent> students;
  final int pages, waiting, open, done;
  final bool published;

  EssayQuestion? question(int n) => questions.where((q) => q.n == n).firstOrNull;

  factory EssayRun.fromJson(Map<String, dynamic> m) {
    final c = asMap(m['counts']);
    return EssayRun(
      id: asInt(m['id'], 0),
      title: '${m['title'] ?? ''}',
      courseId: m['course_id'] == null ? null : asInt(m['course_id'], 0),
      orgId: m['org_id'] == null ? null : asInt(m['org_id'], 0),
      questions: [for (final q in _maps(m['questions'])) EssayQuestion.fromJson(q)],
      maxScore: _d(m['max_score']) ?? 0,
      students: [for (final s in _maps(m['students'])) EssayStudent.fromJson(s)],
      pages: asInt(c['pages'], 0),
      waiting: asInt(c['waiting'], 0),
      open: asInt(c['open'], 0),
      done: asInt(c['done'], 0),
      published: m['published_at'] != null,
    );
  }
}

/// The order a student's answers are checked in: to review (doubtful readings first, then partial credit), being
/// read, done, not sent.
List<EssayAnswer> essayAnswerOrder(List<EssayAnswer> answers) {
  int rank(EssayAnswer a) => switch (a.state) {
        EssayAnswerState.review => a.uncertain ? 0 : (a.suggestion?.band == 'partial' ? 1 : 2),
        EssayAnswerState.waiting => 3,
        EssayAnswerState.done => 4,
        EssayAnswerState.missing => 5,
      };
  final out = [...answers];
  out.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : a.n.compareTo(b.n);
  });
  return out;
}

/// Page i answers question i; the last question takes any extra page (the engine's default too).
List<int> essayDefaultNumbers(int pages, int questions) => [for (var i = 1; i <= pages; i++) i < questions ? i : questions];

/// The `numbers` form field: "1,2,2".
String essayNumbersWire(List<int> numbers) => numbers.join(',');

/// What a page → question assignment breaks, in words; null when it can be sent.
String? essayNumbersProblem(List<int> numbers, int questions) {
  if (numbers.isEmpty) return t('أضف صفحة واحدة على الأقل', 'Add at least one page');
  if (numbers.length > kEssayMaxPages) return t('حتى $kEssayMaxPages صفحة في المرة', 'Up to $kEssayMaxPages pages at a time');
  for (var n = 1; n <= questions; n++) {
    if (numbers.where((x) => x == n).length > kEssayMaxPagesPerAnswer) {
      return t('حتى $kEssayMaxPagesPerAnswer صفحات لإجابة السؤال $n', 'Up to $kEssayMaxPagesPerAnswer pages for the answer to question $n');
    }
  }
  return null;
}

/// A live event about [examId]: a page read, or a review decision (a second teacher's too).
bool essayRunEvent(LiveEvent e, int examId) =>
    (e.kind == kEssayRunEventKind || e.kind == kOmrReviewEventKind) && asInt(e.data['exam_id'], -1) == examId;

// ── words ───────────────────────────────────────────────────────────────────────────────────────────────────────

String essayNum(num? v) {
  if (v == null) return '—';
  final d = v.toDouble();
  return d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(d * 10 == (d * 10).roundToDouble() ? 1 : 2);
}

String essayQualityText(String code) => switch (code) {
      'blurred' => t('الصورة غير واضحة — ثبّت الهاتف وأعد التصوير', 'The photo is blurry: hold the phone steady and retake it'),
      'too_dark' => t('الصورة مظلمة — صوّر في إضاءة أفضل', 'The photo is too dark: take it in better light'),
      'too_bright' => t('الصورة شديدة الإضاءة — تجنّب الفلاش والضوء المباشر', 'The photo is too bright: avoid the flash and direct light'),
      'low_contrast' => t('الكتابة باهتة في الصورة', 'The writing looks faint in the photo'),
      'too_small' => t('الصورة صغيرة — صوّر الورقة أقرب', 'The photo is too small: take the page closer'),
      _ => t('جودة الصورة قد تؤثر على القراءة', 'The photo quality may affect the reading'),
    };

String essayReasonText(String code) => switch (code) {
      'reading_uncertain' => t('القراءة غير مؤكدة — قارن النص بالصورة', 'The reading is not certain: compare the text with the photo'),
      'empty' => t('لم نجد كتابة في هذه الإجابة', 'No writing was found in this answer'),
      'no_model_answer' => t('لا توجد إجابة نموذجية للمقارنة', 'There is no model answer to compare with'),
      'similarity_uncalibrated' => t('لا يمكن اقتراح درجة بهذا النموذج — حدّدها أنت', 'No mark can be suggested with this model: set it yourself'),
      'suggestion_pending' => t('جارٍ حساب الاقتراح…', 'Working out the suggestion…'),
      'rubric' => t('الدرجة المقترحة مجموع المعايير', 'The suggestion adds up the criteria'),
      _ => code,
    };

String essayBandText(String? band) => switch (band) {
      'full' => t('قريبة جدًا من النموذج', 'Very close to the model'),
      'partial' => t('قريبة جزئيًا', 'Partly matches'),
      'zero' => t('بعيدة عن النموذج', 'Far from the model'),
      'empty' => t('فارغة', 'Empty'),
      _ => t('بلا اقتراح', 'No suggestion'),
    };

String essayStateText(EssayAnswerState s) => switch (s) {
      EssayAnswerState.waiting => t('تُقرأ الآن', 'Being read'),
      EssayAnswerState.review => t('للمراجعة', 'To check'),
      EssayAnswerState.done => t('تم', 'Done'),
      EssayAnswerState.missing => t('لم تُرسل', 'Not sent'),
    };

/// "2 to check · 1 being read" / "Done · 7 / 9".
String essayStudentLine(EssayStudent s) {
  final parts = <String>[
    if (s.open > 0) t('${s.open} للمراجعة', '${s.open} to check'),
    if (s.waiting > 0) t('${s.waiting} تُقرأ', '${s.waiting} being read'),
  ];
  if (parts.isEmpty) return t('تم · ${essayNum(s.score)} / ${essayNum(s.maxScore)}', 'Done · ${essayNum(s.score)} / ${essayNum(s.maxScore)}');
  return parts.join(' · ');
}

/// A server code in words (essay_runs.py and the routes it reuses).
String essayCodeText(EngineResult r) => switch (r.code) {
      'feature_disabled' => t('هذه الميزة متوقفة حاليًا', 'This feature is switched off right now'),
      'title_required' => t('اكتب اسمًا لهذا التصحيح', 'Give this correction a name'),
      'answer_key_required' => t('السؤال ${r.detail['n'] ?? ''} يحتاج إجابة نموذجية أو معايير', 'Question ${r.detail['n'] ?? ''} needs a model answer or criteria'),
      'rubric_points_mismatch' => t('مجموع المعايير في السؤال ${r.detail['n'] ?? ''} لا يساوي درجته', 'The criteria of question ${r.detail['n'] ?? ''} do not add up to its mark'),
      'rubric_invalid' || 'points_invalid' || 'questions_invalid' => t('راجع السؤال ${r.detail['n'] ?? ''}', 'Check question ${r.detail['n'] ?? ''}'),
      'not_a_student' => t('هذا الطالب ليس من طلاب المقرر', 'This student is not in this course'),
      'pages_questions_mismatch' => t('حدد سؤالًا لكل صفحة', 'Name the question of every page'),
      'too_many_pages' || 'too_many_files' => t('حتى $kEssayMaxPages صفحة في المرة', 'Up to $kEssayMaxPages pages at a time'),
      'too_many_pages_per_answer' => t('حتى $kEssayMaxPagesPerAnswer صفحات لكل إجابة', 'Up to $kEssayMaxPagesPerAnswer pages for one answer'),
      'unsupported_file' => t('نوع ملف غير مدعوم (صورة أو PDF)', 'Unsupported file type (a photo or a PDF)'),
      'bad_pdf' => t('ملف PDF غير صالح أو محمي بكلمة مرور', 'The PDF is damaged or password-protected'),
      'image_too_large' || 'file_too_large' || 'upload_too_large' => t('الملف كبير جدًا', 'The file is too large'),
      'grading_busy' => t('قائمة التصحيح ممتلئة الآن — أعد المحاولة بعد قليل', 'The marking queue is full: try again in a moment'),
      'score_invalid' => t('درجة غير صالحة', 'That mark is not valid'),
      'run_not_found' => t('هذا التصحيح غير موجود', 'This correction was not found'),
      'forbidden' => t('ليس لديك صلاحية إدارة هذا المقرر', 'You cannot manage this course'),
      _ => r.message.isNotEmpty ? r.message : t('تعذّر الاتصال — حاول مرة أخرى', 'Could not connect: try again'),
    };

// ── the calls ───────────────────────────────────────────────────────────────────────────────────────────────────

class EssayRunApi {
  EssayRunApi([ApiClient? api, OmrReviewApi? review])
      : _api = api ?? ApiClient(),
        _review = review ?? OmrReviewApi(api);
  final ApiClient _api;
  final OmrReviewApi _review;
  static const _b = '/api/v1/exam';

  Future<EngineResult> create({required int courseId, required String title, required List<EssayQuestionDraft> questions}) =>
      engineCall(() => _api.post('$_b/essay/runs', body: {'course_id': courseId, 'title': title.trim(), 'questions': [for (final q in questions) q.toJson()]}));

  Future<EngineResult> get(int id) => engineCall(() => _api.get('$_b/essay/runs/$id'));

  /// One student's paper; [numbers] = the question of each page (null: page i → question i).
  Future<EngineResult> sendPaper(int id, {required int studentId, required List<(String, Uint8List)> files, List<int>? numbers}) =>
      engineCall(() => _api.postFiles('$_b/essay/runs/$id/papers', files: files, fields: {
            'student_id': studentId,
            if (numbers != null) 'numbers': essayNumbersWire(numbers),
          }));

  Future<EngineResult> accept(int examId, int itemId) => _review.resolve(examId, itemId, {'action': 'accept'});
  Future<EngineResult> setScore(int examId, int itemId, double score) => _review.resolve(examId, itemId, {'action': 'set_score', 'score': score});
  Future<Uint8List?> crop(String? url) => _review.image(url);
  OmrReviewApi get review => _review;
}
