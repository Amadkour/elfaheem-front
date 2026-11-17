// Teacher review of Exam Engine answers (Phase 6): the grader proposes, the teacher decides.
//
// Pure models and helpers (unit-tested: test/org/exam_review_test.dart) plus the manager API over the one ApiClient.
// Server contract: ../back/exam_engine/routers/grading.py and scans.py (FLUTTER_API_CHANGES · phase 6).
import 'dart:typed_data';

import 'package:flutter_education_app/core/api_client.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, asMapList, t;
import 'package:flutter_education_app/features/exams/exam_autograde.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';

double? _d(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

/// A span of the student's own text that the grader used as evidence.
class EvidenceSpan {
  const EvidenceSpan(this.start, this.end);
  final int start, end;
}

class ReviewCriterion {
  ReviewCriterion({required this.id, required this.criterion, required this.points, this.score, this.fraction, this.evidence,
      this.evidenceText, this.keywords = const [], this.flags = const [], this.justification = ''});
  final String id;
  final String criterion;
  final double points;
  final double? score;
  final double? fraction;
  final EvidenceSpan? evidence;
  final String? evidenceText;
  final List<String> keywords;
  final List<String> flags;
  final String justification;

  factory ReviewCriterion.fromJson(Map<String, dynamic> j) {
    final ev = j['evidence'] is Map ? asMap(j['evidence']) : null;
    return ReviewCriterion(
      id: '${j['id']}', criterion: '${j['criterion'] ?? ''}', points: _d(j['points']) ?? 0, score: _d(j['score']), fraction: _d(j['fraction']),
      evidence: ev == null ? null : EvidenceSpan(asInt(ev['start']), asInt(ev['end'])), evidenceText: ev?['text']?.toString(),
      keywords: [for (final k in (j['keywords_found'] as List? ?? const [])) '$k'], flags: [for (final f in (j['flags'] as List? ?? const [])) '$f'],
      justification: '${j['justification'] ?? ''}');
  }
}

/// One rubric line of the question (what the teacher marks against).
class RubricLine {
  const RubricLine(this.id, this.criterion, this.points);
  final String id, criterion;
  final double points;
}

class ReviewMark {
  const ReviewMark(this.role, this.score, this.reviewerId, this.acceptedProposal);
  final String role;
  final double score;
  final int reviewerId;
  final bool acceptedProposal;
}

class ReviewItem {
  ReviewItem({required this.answerId, required this.attemptId, required this.questionId, required this.type, required this.studentLabel,
      required this.prompt, required this.answerText, required this.source, this.scanPageId, this.ocrConfidence, required this.points,
      required this.scale, required this.reviewState, this.proposedScore, this.confidence, required this.abstain, this.finalScore,
      this.criteria = const [], this.rubric = const [], this.modelAnswer = '', this.flags = const [], this.marks = const [], this.graderVersion,
      this.studentId, this.auto, this.nb2, this.questionKind = ''});
  final int answerId, attemptId, questionId;

  /// null under anonymous marking ([studentLabel] is then the pseudonym `S-…`).
  final int? studentId;
  final String type, studentLabel, prompt, answerText, source;
  final int? scanPageId;
  final double? ocrConfidence;
  final double points, scale;
  final String reviewState;
  final double? proposedScore, confidence, finalScore;
  final bool abstain;
  final List<ReviewCriterion> criteria;
  final List<RubricLine> rubric;
  final String modelAnswer;
  final List<String> flags;
  final List<ReviewMark> marks;
  final String? graderVersion;

  /// The grading tiers' proposal (contract A3; null from an older engine) and an NB2 character-box reading (B).
  final AutoGrade? auto;
  final Nb2Chars? nb2;

  /// word | short | long from the question's key (empty when the key does not say).
  final String questionKind;

  bool get isOpen => const {'needs_review', 'queued', 'proposed', 'second_pending', 'moderation'}.contains(reviewState);
  bool get hasProposal => proposedScore != null;
  bool get fromScan => source == 'ocr' || source == 'ocr_corrected';

  /// Read from a scanned paper by the paper-exam reader (bubble marks or handwriting, D-154 / D-160): its review,
  /// with the crop of the answer, is the OMR review page.
  bool get fromPaperReader => source == 'handwriting' || source == 'omr';

  factory ReviewItem.fromJson(Map<String, dynamic> j) {
    final ans = asMap(j['answer']);
    final prop = j['proposal'] is Map ? asMap(j['proposal']) : <String, dynamic>{};
    final key = j['key'] is Map ? asMap(j['key']) : <String, dynamic>{};
    final rubric = [
      for (final (i, c) in asMapList(key['rubric']).indexed) RubricLine('${c['id'] ?? 'c${i + 1}'}', '${c['criterion'] ?? ''}', _d(c['points']) ?? 0)
    ];
    final sid = j['student_id'];
    return ReviewItem(
      answerId: asInt(j['answer_id']), attemptId: asInt(j['attempt_id']), questionId: asInt(j['question_id']), type: '${j['type'] ?? ''}',
      studentLabel: sid != null ? '#$sid' : '${j['student_code'] ?? '—'}', prompt: '${j['prompt'] ?? ''}',
      answerText: '${ans['text'] ?? ''}', source: '${ans['source'] ?? 'online'}', scanPageId: ans['scan_page_id'] == null ? null : asInt(ans['scan_page_id']),
      ocrConfidence: _d(ans['ocr_confidence']), points: _d(j['points']) ?? 0, scale: _d(prop['scale']) ?? 1.0,
      reviewState: '${j['review_state'] ?? ''}', proposedScore: _d(j['proposed_score']), confidence: _d(j['confidence']),
      abstain: prop['abstain'] == true, finalScore: _d(j['final_score']),
      criteria: [for (final c in asMapList(prop['criteria'])) ReviewCriterion.fromJson(c)], rubric: rubric,
      modelAnswer: '${key['model'] ?? ''}', flags: [for (final f in (prop['flags'] as List? ?? const [])) '$f'],
      marks: [for (final m in asMapList(j['marks'])) ReviewMark('${m['role']}', _d(m['score']) ?? 0, asInt(m['reviewer_id']), m['accepted_proposal'] == true)],
      graderVersion: j['grader_version']?.toString(), studentId: sid == null ? null : asInt(sid),
      auto: AutoGrade.fromJson(prop), nb2: Nb2Chars.fromJson(ans['nb2']), questionKind: '${asMap(key['derived'])['kind'] ?? key['kind'] ?? ''}');
  }
}

class ReviewQueue {
  ReviewQueue({required this.items, required this.total, required this.counts, required this.threshold, required this.policy});
  final List<ReviewItem> items;
  final int total;
  final Map<String, int> counts;
  final double threshold;
  final Map<String, dynamic> policy;

  bool get doubleMarking => policy['double_marking'] == true;

  /// Proposals a bulk approval at [minConfidence] would take (open, proposed, not abstained).
  int approvable(double minConfidence) =>
      items.where((i) => i.reviewState == 'proposed' && !i.abstain && (i.confidence ?? 0) >= minConfidence).length;

  factory ReviewQueue.fromJson(Map<String, dynamic> j) => ReviewQueue(
        items: [for (final i in asMapList(j['items'])) ReviewItem.fromJson(i)],
        total: asInt(j['total']),
        counts: {for (final e in asMap(j['counts']).entries) e.key: asInt(e.value)},
        threshold: _d(j['accept_threshold']) ?? 0.95,
        policy: asMap(j['policy']),
      );
}

/// high ≥ the accept threshold · medium ≥ 0.6 · low otherwise (and always low when the grader abstained).
String confidenceBand(double? c, {double threshold = 0.95, bool abstain = false}) {
  if (c == null) return 'none';
  if (abstain) return 'low';
  if (c >= threshold) return 'high';
  return c >= 0.6 ? 'medium' : 'low';
}

/// The student's text cut into (text, highlighted) runs for the evidence spans (overlaps merged, out-of-range ignored).
List<(String, bool)> highlightRuns(String text, Iterable<EvidenceSpan> spans) {
  final ranges = [
    for (final s in spans)
      if (s.start >= 0 && s.end > s.start && s.start < text.length) (s.start, s.end.clamp(0, text.length))
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(int, int)>[];
  for (final r in ranges) {
    if (merged.isNotEmpty && r.$1 <= merged.last.$2) {
      merged[merged.length - 1] = (merged.last.$1, r.$2 > merged.last.$2 ? r.$2 : merged.last.$2);
    } else {
      merged.add(r);
    }
  }
  final out = <(String, bool)>[];
  var pos = 0;
  for (final (a, b) in merged) {
    if (a > pos) out.add((text.substring(pos, a), false));
    out.add((text.substring(a, b), true));
    pos = b;
  }
  if (pos < text.length) out.add((text.substring(pos), false));
  return out;
}

/// The score a set of criterion marks gives (rubric points scaled to the placement's points), half points.
double criteriaTotal(Map<String, double> marks, double scale) {
  final raw = marks.values.fold<double>(0, (a, b) => a + b);
  return ((raw * scale) * 1000).round() / 1000;
}

/// A typed score is valid between 0 and the question's points.
String? scoreError(String text, double points) {
  final v = double.tryParse(text.trim().replaceAll('٫', '.').replaceAll(',', '.'));
  if (v == null) return t('أدخل رقماً', 'Enter a number');
  if (v < 0 || v > points + 1e-9) return t('بين 0 و $points', 'Between 0 and $points');
  return null;
}

String reviewStateText(String s) => switch (s) {
      'queued' => t('بانتظار المصحح الآلي', 'Waiting for the grader'),
      'proposed' => t('اقتراح ينتظر قرارك', 'Proposal awaiting your decision'),
      'needs_review' => t('يحتاج تصحيحاً', 'Needs marking'),
      'second_pending' => t('بانتظار المصحح الثاني', 'Waiting for the second marker'),
      'moderation' => t('خلاف بين المصححين — يقرر المشرف', 'Markers disagree — moderator decides'),
      'auto_accepted' => t('قُبل آلياً', 'Accepted automatically'),
      'reviewed' => t('تم التصحيح', 'Marked'),
      _ => s,
    };

String flagText(String f) => switch (f) {
      'negation' => t('نفي يخالف الإجابة النموذجية', 'Negation against the model answer'),
      'antonym' => t('عكس المعنى المطلوب', 'Opposite of the expected idea'),
      'contradiction' => t('تناقض مع المعيار', 'Contradicts the criterion'),
      'trap' => t('قريب من خطأ شائع', 'Close to a known wrong answer'),
      // the answer gives one concept's properties to another (exam_engine/grading/features.py ROLE_SWAP_FLAG)
      'role_swap' => t('تبديل الأدوار بين المفاهيم', 'Roles swapped between concepts'),
      // only when GRADER_LLM_CHECK is on (off today): a second check disagrees, the answer goes to the teacher
      'llm_disagrees' => t('فحص ثانٍ يخالف هذا التصحيح', 'A second check disagrees with this mark'),
      'empty' => t('إجابة فارغة', 'Empty answer'),
      'ocr_low_confidence' => t('قراءة الخط غير مؤكدة — راجع النص', 'Handwriting reading uncertain — check the text'),
      // D-1135: the tiered grader's own guards (exam_engine/grading/tiers.py), shown as raw keys before
      'symbols' => t('رموز أو معادلات — تحقق منها', 'Symbols or equations — check them'),
      'memory_wrong' => t('تشبه إجابة صُحّحت خطأً من قبل', 'Like an answer marked wrong before'),
      'other_language' => t('مكتوبة بلغة غير لغة الإجابة النموذجية', 'Written in another language than the model answer'),
      // an unknown future flag: a readable fallback, never the raw key
      _ => t('علامة للمراجعة', 'Flagged for review'),
    };

/// OCR words of a page region with the ones to highlight for the teacher.
class OcrWord {
  const OcrWord(this.text, this.confidence, this.low);
  final String text;
  final double confidence;
  final bool low;
}

class OcrRegion {
  OcrRegion({required this.questionId, required this.text, required this.confidence, required this.box, required this.words});
  final int? questionId;
  final String text;
  final double confidence;
  final List<double> box;          // normalised x, y, w, h
  final List<OcrWord> words;

  factory OcrRegion.fromJson(Map<String, dynamic> j) => OcrRegion(
        questionId: j['question_id'] == null ? null : asInt(j['question_id']),
        text: '${j['text'] ?? ''}', confidence: _d(j['confidence']) ?? 0,
        box: [for (final v in (j['box'] as List? ?? const [0, 0, 1, 1])) _d(v) ?? 0],
        words: [
          for (final ln in asMapList(j['lines']))
            for (final w in asMapList(ln['words'])) OcrWord('${w['text']}', _d(w['confidence']) ?? 0, w['low'] == true)
        ],
      );
}

class ScanPageInfo {
  ScanPageInfo({required this.id, required this.status, this.studentId, this.attemptId, this.fileName, required this.regions,
      required this.corrected, required this.warnings});
  final int id;
  final String status;
  final int? studentId, attemptId;
  final String? fileName;
  final List<OcrRegion> regions;
  final Map<String, String> corrected;
  final List<String> warnings;

  bool get unmatched => status == 'unmatched';

  /// The warnings that ask for this page to be photographed again.
  List<String> get retakeWarnings => [for (final w in warnings) if (kRetakeWarnings.contains(w)) w];

  factory ScanPageInfo.fromJson(Map<String, dynamic> j) {
    final ocr = j['ocr'] is Map ? asMap(j['ocr']) : <String, dynamic>{};
    final regions = asMapList(ocr['regions']).isNotEmpty ? asMapList(ocr['regions']) : asMapList(j['regions']);
    return ScanPageInfo(
      id: asInt(j['id']), status: '${j['status'] ?? ''}', studentId: j['student_id'] == null ? null : asInt(j['student_id']),
      attemptId: j['attempt_id'] == null ? null : asInt(j['attempt_id']), fileName: j['file_name']?.toString(),
      regions: [for (final r in regions) OcrRegion.fromJson(r)],
      corrected: {for (final e in asMap(j['corrected']).entries) e.key: '${e.value}'},
      warnings: [for (final w in (j['quality_warnings'] is List ? j['quality_warnings'] as List : const [])) if (w != null && '$w'.isNotEmpty) '$w'],
    );
  }
}

String scanStatusText(String s) => switch (s) {
      'uploaded' => t('بانتظار القراءة', 'Waiting to be read'),
      'matched' => t('مُسندة — بانتظار القراءة', 'Matched — waiting to be read'),
      'unmatched' => t('غير مُسندة — حدد الطالب', 'Unmatched — choose the student'),
      'processed' => t('قُرئت', 'Read'),
      'failed' => t('تعذرت القراءة', 'Could not be read'),
      _ => s,
    };

/// Page warnings that need a new photo (NB1 from a phone, D-690..D-693): they head the "Retake these pages" list.
const kRetakeWarnings = {'sheet_marks_missing', 'cut_left', 'cut_right', 'cut_top', 'cut_bottom'};

String qualityWarningText(String w) => switch (w) {
      'blurred' => t('الصورة مهتزة', 'The photo is blurred'),
      'too_dark' => t('الصورة مظلمة', 'The photo is too dark'),
      'too_bright' => t('الصورة شديدة الإضاءة', 'The photo is too bright'),
      'low_contrast' => t('التباين ضعيف', 'Low contrast'),
      'too_small' => t('الصورة صغيرة', 'The image is too small'),
      'sheet_marks_missing' => t('أعد التصوير: لم تظهر مربعات الأركان وإطار الورقة', 'Retake: the corner squares and the sheet frame were not found'),
      'cut_left' => t('أعد التصوير: الجانب الأيسر من الورقة خارج الصورة', 'Retake: the left side of the sheet is outside the photo'),
      'cut_right' => t('أعد التصوير: الجانب الأيمن من الورقة خارج الصورة', 'Retake: the right side of the sheet is outside the photo'),
      'cut_top' => t('أعد التصوير: أعلى الورقة خارج الصورة', 'Retake: the top of the sheet is outside the photo'),
      'cut_bottom' => t('أعد التصوير: أسفل الورقة خارج الصورة', 'Retake: the bottom of the sheet is outside the photo'),
      _ => w,
    };

/// The manager side of /api/v1/exam for grading and scans.
class ExamReviewApi {
  ExamReviewApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const base = ExamEngineApi.base;

  Future<EngineResult> manageable({int? courseId, int? orgId}) => engineCall(() => _api.get('$base/exams', queryParams: {
        'course_id': ?courseId,
        'org_id': ?orgId,
      }));

  Future<EngineResult> grading(int examId) => engineCall(() => _api.get('$base/exams/$examId/grading'));

  Future<EngineResult> setPolicy(int examId, Map<String, dynamic> body) => engineCall(() => _api.put('$base/exams/$examId/grading', body: body));

  Future<EngineResult> review(int examId, {String state = 'open', int? questionId, int limit = 100, int offset = 0}) =>
      engineCall(() => _api.get('$base/exams/$examId/review', queryParams: {
            'state': state, 'limit': limit, 'offset': offset,
            'question_id': ?questionId,
          }));

  Future<EngineResult> mark(int answerId, {double? score, Map<String, double>? criteria, String? comment, bool accept = false}) =>
      engineCall(() => _api.post('$base/answers/$answerId/mark', body: {
            'score': ?score,
            if (criteria != null && criteria.isNotEmpty) 'criteria': criteria,
            if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
            'accept': accept,
          }));

  /// `dryRun`: how many proposals in the WHOLE exam the approval would take (the screen shows only a page).
  Future<EngineResult> bulkApprove(int examId, {double? minConfidence, bool dryRun = false}) =>
      engineCall(() => _api.post('$base/exams/$examId/review/bulk-approve', body: {'min_confidence': ?minConfidence, 'dry_run': dryRun}));

  Future<EngineResult> scans(int examId, {String? status}) =>
      engineCall(() => _api.get('$base/exams/$examId/scans', queryParams: {'status': ?status}));

  Future<EngineResult> scan(int pageId) => engineCall(() => _api.get('$base/scans/$pageId'));

  Future<Uint8List?> scanImage(int pageId) async {
    try {
      return await _api.getBytes('$base/scans/$pageId/image');
    } on ApiException {
      return null;
    }
  }

  Future<EngineResult> assign(int pageId, {required int studentId, int? questionId}) =>
      engineCall(() => _api.post('$base/scans/$pageId/assign', body: {'student_id': studentId, 'question_id': ?questionId}));

  Future<EngineResult> correct(int pageId, {required int questionId, required String text}) =>
      engineCall(() => _api.put('$base/scans/$pageId/transcription', body: {'question_id': questionId, 'text': text}));

  /// [batchId]: the next part of an upload sent in parts (paper/scan/scan_files.dart) — its pages join that batch.
  Future<EngineResult> uploadScans(int examId, List<(String, Uint8List)> files, {int? studentId, int? questionId, int? batchId}) =>
      engineCall(() => _api.postFiles('$base/exams/$examId/scans', files: files, fields: {
            'student_id': ?studentId,
            'question_id': ?questionId,
            'batch_id': ?batchId,
          }));

  Future<EngineResult> importMarks(int examId, String fileName, Uint8List bytes) =>
      engineCall(() => _api.postFiles('$base/exams/$examId/marks/import', files: [(fileName, bytes)], field: 'file'));

  /// CSV / XLSX `student_id, file_name[, question_id]` for the scans of [batchId].
  Future<EngineResult> scanMapping(int examId, String fileName, Uint8List bytes, {required int batchId}) =>
      engineCall(() => _api.postFiles('$base/exams/$examId/scans/mapping', files: [(fileName, bytes)], field: 'file', fields: {'batch_id': batchId}));

  /// The exam's attempts (the only list of students a paper exam has; `student_id` is null under anonymous grading).
  Future<EngineResult> attempts(int examId) => engineCall(() => _api.get('$base/exams/$examId/attempts'));

  Future<Uint8List?> sheetsPdf(int examId, {List<int> studentIds = const [], int blank = 0}) async {
    try {
      return await _api.postForBytes('$base/exams/$examId/sheets', body: {'student_ids': studentIds, 'blank': blank});
    } on ApiException {
      return null;
    }
  }
}
