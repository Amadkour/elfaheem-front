// Scanned bubble sheets — review queue and results (brief Part 4: 4.3 – 4.6, S.1; D-156, D-158): the pure part.
// Models parsed from the engine's replies, the API, the server codes in plain words and the export of the results.
// The screens are omr_review_page.dart (the queue, one-click fixes, the full paper view) and omr_results_page.dart
// (grades, per-question statistics, the score distribution, export, publish); their plain-value widgets are in
// omr_review_parts.dart / omr_results_parts.dart.
//
// Server (Exam Engine, the exam's managers + platform admins; students and parents get 403):
//   GET  /api/v1/exam/exams/{id}/review-items?status=open|resolved&kind=     {items, total, open_by_kind}
//   GET  /api/v1/exam/exams/{id}/review-items/{item}                         + system_reading, question, page
//   POST /api/v1/exam/exams/{id}/review-items/{item}/resolve {action, …}     {item, page_status, open_items_on_page,
//                                                                              attempt | null, next_item_id}
//   GET  /api/v1/exam/exams/{id}/omr/pages/{page}                             the page: signed image URL + overlay
//   GET  /api/v1/exam/exams/{id}/omr/changes                                  the append-only manual changes
//   GET  /api/v1/exam/exams/{id}/omr/students?q=&limit=20                      the exam's audience, for "assign"
//   GET  /api/v1/exam/exams/{id}/omr/results · POST …/omr/results/publish {graded_only?}
//   GET  /api/v1/exam/omr/images/{crop|page}/{id}?exp=&sig=                   the image (token + signature, audited)
// Handwritten answers (D-160): kinds `completion` and `short_answer` — accept the suggested score, set the score
// (0 … points, step 0.5) or fix the recognised text (the server matches it again; a short answer's suggestion is then
// `pending` until a worker recomputed it). Nothing handwritten is final here without a teacher's action.
// Live: `job_updated {kind: omr_review, exam_id, item_id, status, open_count}` after every decision.
// Rules: exam_engine/services/omr_review.py, omr_written.py, omr_results.py, omr_scan.page_view (the code wins).
// Every reply above is recorded from the real engine in test/fixtures/payloads/omr_review/. Round 3 (additive, older
// servers fall back): items carry `page_no`, `file_name`, `batch_id` and the batch's `created_at` (top level, or under
// `page` / `batch`); an identifier item's `reading` may name the student (`student_name`, `masked_id` = the last 4) and,
// for student_already_scanned, the graded page (`other_page_label` / `other_page_no`, `other_file_name`);
// `reading.value` is null when no digit was read (an older server sent "??"). Final polish: items carry `page_label`
// (the page's name in its batch, the one the server's sentence uses: "Page 3 is too blurry…") and `page_file_page`
// (the page inside a multi-page PDF); `page_no` is the page inside its own file (every photo is page 1 of itself), so
// a page is named by its label and `page_no` is only an older server's fallback.
library;

import 'dart:typed_data';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_table_export.dart';

import '../../../../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import '../../exam_engine_api.dart';
import '../omr_counts.dart' show omrFilePlace;

/// The live event the engine sends the uploader after every scanned page: `job_updated {kind: omr_scan, exam_id, …}`.
const kOmrScanEventKind = 'omr_scan';

/// The live event after every review decision: `job_updated {kind: omr_review, exam_id, item_id, status, open_count}`.
const kOmrReviewEventKind = 'omr_review';

// ── small parsers ───────────────────────────────────────────────────────────────────────────────────────────────

/// The engine stores naive UTC (`2026-11-02T05:29:37.033859`): read it as UTC; null when absent / unreadable.
DateTime? omrUtc(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  if (s.isEmpty) return null;
  final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(hasZone ? s : '${s}Z')?.toUtc();
}

double? _dbl(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
int? _intOrNull(Object? v) => v == null ? null : (v is int ? v : int.tryParse('$v'));
List<String> _strs(Object? v) => v is List ? [for (final x in v) '$x'] : const [];

/// [s] as one left-to-right run inside Arabic text ("5 / 11 · 45%" keeps its order); unchanged in English.
String omrLtr(String s) => AppConfig.lang == 'ar' ? '${String.fromCharCode(0x2066)}$s${String.fromCharCode(0x2069)}' : s;

/// "5" for 5.0, "4.5" for 4.5.
String omrNum(num? v) {
  if (v == null) return '—';
  final d = v.toDouble();
  return d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(d * 10 == (d * 10).roundToDouble() ? 1 : 2);
}

// ── review items ────────────────────────────────────────────────────────────────────────────────────────────────

/// The kinds of the queue, in the order the filter shows them.
const kOmrKinds = ['identifier', 'form', 'bubble', 'completion', 'short_answer', 'quality'];

/// The handwritten kinds (D-160): never final without a teacher's accept / set score.
const kOmrWrittenKinds = {'completion', 'short_answer'};

String omrKindLabel(String kind) => switch (kind) {
      'identifier' => t('رقم الطالب', 'Student ID'),
      'form' => t('النموذج', 'Form'),
      'bubble' => t('الإجابات', 'Answers'),
      'completion' => t('أكمل الفراغ', 'Completion'),
      'short_answer' => t('إجابة قصيرة', 'Short answer'),
      'handwriting' => t('الكتابة اليدوية', 'Handwriting'),
      'quality' => t('جودة الصورة', 'Image quality'),
      _ => kind,
    };

/// One digit of a handwritten identifier as the digits model read it (Example 7).
class OmrDigit {
  const OmrDigit(this.index, this.digit, this.confidence, {this.low = false});
  final int index;
  final String digit;
  final double? confidence;

  /// Below the model's threshold: the reason the item is here.
  final bool low;
}

/// A student the item may belong to (a duplicate value's candidates, a search hit).
class OmrStudent {
  const OmrStudent(this.id, this.name, {this.email, this.identifier, this.distance});
  final int id;
  final String name;
  final String? email;

  /// The exam identifier, masked by the server except its last 4 characters ("••••••0121").
  final String? identifier;

  /// How many characters differ from the reading (a closest candidate), when the server says so.
  final int? distance;

  String get label => name.trim().isEmpty ? t('الطالب #$id', 'Student #$id') : name;

  /// A candidate / search row, whatever the server calls the id (`user_id` | `student_id` | `id`); null without one.
  static OmrStudent? fromJson(Map<String, dynamic> m) {
    final id = _intOrNull(m['user_id'] ?? m['student_id'] ?? m['id']);
    if (id == null) return null;
    final ident = m['identifier'] ?? m['value'];
    return OmrStudent(id, '${m['name'] ?? ''}',
        email: m['gmail']?.toString() ?? m['email']?.toString(),
        identifier: ident == null || '$ident'.isEmpty ? null : '$ident',
        distance: _intOrNull(m['distance']));
  }
}

/// `GET …/omr/students`: the exam's audience matching a search (a part of the name, or 3+ characters of the ID).
class OmrAudience {
  const OmrAudience({this.items = const [], this.total = 0, this.source, this.labelEn, this.labelAr, this.reason});
  final List<OmrStudent> items;
  final int total;

  /// Why the list is empty when the server says so (`no_course`: the exam is linked to no course).
  final String? reason;

  /// The exam identifier's source (`academic_id`, `national_id`, …; `name` when the exam has none).
  final String? source;
  final String? labelEn, labelAr;

  factory OmrAudience.fromJson(Map<String, dynamic> m) {
    final l = asMap(m['label']);
    return OmrAudience(
      items: [for (final x in asMapList(m['items'])) ?OmrStudent.fromJson(x)],
      total: asInt(m['total']),
      source: m['source']?.toString(),
      labelEn: l['en']?.toString(),
      labelAr: l['ar']?.toString(),
      reason: m['reason']?.toString(),
    );
  }

  /// "Academic ID" in the app's language (null when the exam identifies students by name).
  String? get label {
    final s = AppConfig.lang == 'ar' ? (labelAr ?? labelEn) : (labelEn ?? labelAr);
    return s == null || s.isEmpty ? null : s;
  }
}

/// One blank of a handwritten completion as the engine read and matched it (D-160).
class OmrBlank {
  const OmrBlank({
    required this.index,
    required this.status,
    this.given = '',
    this.matched,
    this.distance,
    this.suggestedCredit,
    this.isFinal = false,
    this.reason,
    this.prefill = false,
    this.confidence,
    this.engine,
    this.checkText,
    this.checkAgree,
  });

  final int index;

  /// exact | near | none | empty.
  final String status;

  /// What the reader read (or the teacher typed).
  final String given;

  /// The accepted answer it matched (exact / near).
  final String? matched;
  final int? distance;

  /// Share of the blank's points suggested (0 … 1).
  final double? suggestedCredit;
  final bool isFinal;
  final String? reason;

  /// true = the suggestion is shown pre-filled: one tap confirms it.
  final bool prefill;
  final double? confidence;
  final String? engine;

  /// The second reader's text and whether it agreed.
  final String? checkText;
  final bool? checkAgree;

  factory OmrBlank.fromJson(int i, Map<String, dynamic> m) {
    final r = asMap(m['reading']);
    final check = asMap(r['check']);
    return OmrBlank(
      index: i,
      status: '${m['status'] ?? ''}',
      given: '${m['given'] ?? r['text'] ?? ''}',
      matched: m['matched']?.toString(),
      distance: _intOrNull(m['distance']),
      suggestedCredit: _dbl(m['suggested_credit']),
      isFinal: m['final'] == true,
      reason: m['reason']?.toString(),
      prefill: m['prefill'] == true,
      confidence: _dbl(r['confidence']),
      engine: r['engine']?.toString(),
      checkText: check.isEmpty ? null : check['text']?.toString(),
      checkAgree: check['agree'] is bool ? check['agree'] as bool : null,
    );
  }
}

/// A short answer's keyword (D-160): found (the words that matched, exact or near) or missing.
class OmrKeyword {
  const OmrKeyword(this.term, {this.found = const [], this.how, this.weight});
  final String term;
  final List<String> found;

  /// exact | near | null (missing).
  final String? how;
  final double? weight;

  bool get hit => found.isNotEmpty || how != null;
}

/// `question {n, question_id, type, points, letters}` of a bubble item's detail.
class OmrQuestionRef {
  const OmrQuestionRef(
      {required this.n, required this.questionId, required this.type, required this.points, required this.letters, this.step, this.blanks, this.lang, this.key = const {}});
  final int n;
  final int questionId;
  final String type;
  final double points;
  final List<String> letters;

  /// Handwritten questions: the score step (0.5), the number of blanks, the answer language, the key (accepted
  /// answers, or the model answer + keywords).
  final double? step;
  final int? blanks;
  final String? lang;
  final Map<String, dynamic> key;

  static OmrQuestionRef? fromJson(Object? v) {
    final m = asMap(v);
    if (m.isEmpty) return null;
    return OmrQuestionRef(
        n: asInt(m['n']),
        questionId: asInt(m['question_id']),
        type: '${m['type'] ?? ''}',
        points: _dbl(m['points']) ?? 0,
        letters: _strs(m['letters']),
        step: _dbl(m['step']),
        blanks: _intOrNull(m['blanks']),
        lang: m['lang']?.toString(),
        key: asMap(m['key']));
  }

  /// A short answer's model answer (the key), when the server sends it.
  String? get modelAnswer {
    final v = key['model'];
    return v == null || '$v'.trim().isEmpty ? null : '$v';
  }

  /// The accepted answers of each blank of a completion.
  List<List<String>> get acceptedBlanks => [
        for (final b in (key['blanks'] is List ? key['blanks'] as List : const []))
          b is List ? [for (final x in b) '$x'] : ['$b'],
      ];
}

/// A review item (list row or detail). [reading] is what the system read, [en] / [ar] why the item is here.
class OmrReviewItem {
  const OmrReviewItem({
    required this.id,
    required this.kind,
    required this.code,
    required this.status,
    this.scanPageId,
    this.attemptId,
    this.questionId,
    this.reading = const {},
    this.resolution = const {},
    this.resolvedBy,
    this.resolvedAt,
    this.createdAt,
    this.actions = const [],
    this.hasCrop = false,
    this.cropUrl,
    this.en = '',
    this.ar = '',
    this.systemReading = const {},
    this.question,
    this.pageLabel,
    this.pageStatus,
    this.studentName,
    this.studentCode,
    this.pageNo,
    this.pageFilePage,
    this.fileName,
    this.batchId,
    this.batchAt,
  });

  final int id;
  final String kind;
  final String code;
  final String status;
  final int? scanPageId;
  final int? attemptId;
  final int? questionId;
  final Map<String, dynamic> reading;
  final Map<String, dynamic> resolution;
  final int? resolvedBy;
  final DateTime? resolvedAt;
  final DateTime? createdAt;
  final List<String> actions;
  final bool hasCrop;
  final String? cropUrl;
  final String en;
  final String ar;

  /// Detail only: the original reading's part (`answer` / `identifier` / `form` / `quality`).
  final Map<String, dynamic> systemReading;
  final OmrQuestionRef? question;
  final String? pageLabel;
  final String? pageStatus;

  /// Whose paper it is (`student {id, name}`): the name, or the pseudonym (`{code}`) under anonymous grading; both
  /// null while the page is not matched to a student, and on an identifier item.
  final String? studentName;
  final String? studentCode;

  /// Which paper it is, to tell items apart: the page inside its own file ([pageLabel] is its name in the batch), the
  /// page inside a multi-page PDF uploaded with other files, the file it came from, the batch and when the batch was
  /// made (null on an older server; [when] falls back to the item's own time).
  final int? pageNo;
  final int? pageFilePage;
  final String? fileName;
  final int? batchId;
  final DateTime? batchAt;

  /// The student in words for the queue and the card; null when the server names nobody.
  String? get studentText {
    final n = studentName?.trim() ?? '';
    if (n.isNotEmpty) return n;
    final code = studentCode?.trim() ?? '';
    return code.isEmpty ? null : code;
  }

  factory OmrReviewItem.fromJson(Map<String, dynamic> m) {
    final page = asMap(m['page']);
    final student = asMap(m['student']);
    final sid = _intOrNull(student['id']);
    final sname = '${student['name'] ?? ''}'.trim();
    final batch = asMap(m['batch']);
    final file = '${m['file_name'] ?? page['file_name'] ?? ''}'.trim();
    return OmrReviewItem(
      id: asInt(m['id']),
      kind: '${m['kind'] ?? ''}',
      code: '${m['code'] ?? ''}',
      status: '${m['status'] ?? 'open'}',
      scanPageId: _intOrNull(m['scan_page_id']),
      attemptId: _intOrNull(m['attempt_id']),
      questionId: _intOrNull(m['question_id']),
      reading: asMap(m['reading']),
      resolution: asMap(m['resolution']),
      resolvedBy: _intOrNull(m['resolved_by']),
      resolvedAt: omrUtc(m['resolved_at']),
      createdAt: omrUtc(m['created_at']),
      actions: _strs(m['actions']),
      hasCrop: m['has_crop'] == true,
      cropUrl: m['crop_url']?.toString(),
      en: '${m['en'] ?? ''}',
      ar: '${m['ar'] ?? ''}',
      systemReading: asMap(m['system_reading']),
      question: OmrQuestionRef.fromJson(m['question']),
      pageLabel: (m['page_label'] ?? page['page_label'])?.toString(),
      pageStatus: page['status']?.toString(),
      // a roster without the name still says which student: "Student #12"
      studentName: sname.isNotEmpty ? sname : (sid == null ? null : t('الطالب #$sid', 'Student #$sid')),
      studentCode: student['code']?.toString(),
      pageNo: _intOrNull(m['page_no'] ?? page['page_no']),
      pageFilePage: _intOrNull(m['page_file_page'] ?? page['page_file_page']),
      fileName: file.isEmpty ? null : file,
      batchId: _intOrNull(m['batch_id'] ?? page['batch_id'] ?? batch['id']),
      batchAt: omrUtc(m['batch_created_at'] ?? batch['created_at'] ?? page['batch_created_at']),
    );
  }

  bool get open => status == 'open';

  /// The page's name in its batch, as the server's sentence says it ("3" of "Page 3 is too blurry…"): the label, else
  /// (an older server) the page number; null when the server says neither.
  String? get pageName {
    final l = pageLabel?.trim() ?? '';
    if (l.isNotEmpty) return l;
    return pageNo?.toString();
  }

  /// "Page 3"; null when the server names no page.
  String? get pageText {
    final n = pageName;
    return n == null ? null : t('الصفحة $n', 'Page $n');
  }

  /// The file it came from: "wa01.jpg", or "PDF page 4 of scan.pdf" for a page of a multi-page PDF (never "page 1"
  /// of a photo); null when the server names neither (anonymous grading hides the file).
  String? get fileText => omrFilePlace(fileName, pageFilePage);

  /// When the paper came in: the batch's time, else the item's (an older server).
  DateTime? get when => batchAt ?? createdAt;

  /// "Page 3 · wa01.jpg" — which paper (without the time).
  String get placeText => [?pageText, ?fileText].join(' · ');

  /// "Today, 10:42 AM": when the paper came in; null when the server says nothing.
  String? get whenText => when == null ? null : omrWhenText(when!);

  /// "Page 3 · wa01.jpg · Today, 10:42 AM" — enough to tell two items of the same kind apart.
  String get whereText => [?pageText, ?fileText, ?whenText].join(' · ');

  /// This detail with a decision reply's item on top (its reading, code, state), keeping what only the detail has
  /// (the question, the system reading, the signed crop) until the fresh detail arrives.
  OmrReviewItem withReading(OmrReviewItem r) => OmrReviewItem(
        id: id,
        kind: kind,
        code: r.code.isEmpty ? code : r.code,
        status: r.status,
        scanPageId: scanPageId,
        attemptId: r.attemptId ?? attemptId,
        questionId: questionId,
        reading: r.reading.isEmpty ? reading : r.reading,
        resolution: r.resolution,
        resolvedBy: r.resolvedBy,
        resolvedAt: r.resolvedAt,
        createdAt: createdAt,
        actions: r.actions.isEmpty ? actions : r.actions,
        hasCrop: hasCrop,
        cropUrl: cropUrl,
        en: r.en.isEmpty ? en : r.en,
        ar: r.ar.isEmpty ? ar : r.ar,
        systemReading: systemReading,
        question: question,
        pageLabel: r.pageLabel ?? pageLabel,
        pageStatus: pageStatus,
        // the decision reply's item does not name the student: keep the list's / detail's
        studentName: r.studentName ?? studentName,
        studentCode: r.studentCode ?? studentCode,
        pageNo: r.pageNo ?? pageNo,
        pageFilePage: r.pageFilePage ?? pageFilePage,
        fileName: r.fileName ?? fileName,
        batchId: r.batchId ?? batchId,
        batchAt: r.batchAt ?? batchAt,
      );

  /// Why the item is here, in the app's language (the server's own sentence; two codes get a sharper one).
  String get reason {
    if (code == 'qr_mismatch') return omrCodeText(code);
    if (code == 'identifier_conflict' && uploadedFor != null) {
      return t('رُفعت هذه الورقة لطالب، لكنها تحمل رقم طالب آخر', 'This page was uploaded for one student, but the sheet names another');
    }
    final s = AppConfig.lang == 'ar' ? ar : en;
    return s.isNotEmpty ? s : omrCodeText(code);
  }

  /// A second line that says what to do about it (which exam / version, the key to fix).
  String? get detail => switch (code) {
        'qr_mismatch' => '${reading['reason'] ?? ''}' == 'other_version'
            ? t('طُبعت لإصدار آخر من ورقة هذا الاختبار، فقُرئت فقاعاتها بتخطيط مختلف. ارفعها في الاختبار الصحيح أو اطبع الأوراق من جديد.',
                "It was printed for another version of this exam's sheet, so its bubbles were read with a different layout. Upload it into the right exam, or print the sheets again.")
            : t('رمز QR فيها موقَّع لاختبار آخر. ارفعها في ذلك الاختبار؛ هنا لا يمكن إلا تنحيتها.',
                'Its QR code is signed for another exam. Upload it into that exam; here it can only be set aside.'),
        'qr_forged' => t('توقيع رمز QR غير صالح، فقد تكون الورقة منسوخة أو معدّلة. افحص الورقة قبل أن تختار نموذجها.',
            "The QR code's signature is not valid: the sheet may be copied or altered. Check the paper before you choose its form."),
        'key_missing' => t('أضف إجابة هذا السؤال إلى مفتاح النموذج (إعداد الاختبار الورقي ← النماذج)؛ تُصحَّح الأوراق فور الحفظ.',
            "Add this question's answer to the form's key (Paper exam setup → Models); the sheets are graded again as soon as you save."),
        _ => null,
      };

  bool can(String action) => actions.contains(action);

  // bubble
  int? get n => question?.n ?? _intOrNull(reading['n']);
  String get questionType => question?.type ?? '${reading['type'] ?? ''}';
  bool get multi => questionType == 'mcq_multi';
  Map<String, double> get fills {
    final f = asMap(reading['fills']);
    return {for (final e in f.entries) e.key: _dbl(e.value) ?? 0};
  }

  List<String> get selected => _strs(reading['selected']);

  /// The letters to choose from: the detail's (the question's own options), else the shaded sheet's.
  List<String> get letters {
    final q = question?.letters ?? const [];
    if (q.isNotEmpty) return q;
    final f = fills.keys.toList()..sort();
    return f;
  }

  // identifier
  /// The ID as read; empty when no digit was read (null, or an older server's "??" / "????").
  String get readValue {
    final v = '${reading['value'] ?? ''}'.trim();
    return omrNothingRead(v) ? '' : v;
  }

  /// No digit of the ID could be read: the student is chosen, not confirmed.
  bool get nothingRead => kind == 'identifier' && readValue.isEmpty;

  /// The read value has unread digits ("12?4"): never offered as "The ID is right".
  bool get partlyRead => readValue.contains('?');

  /// The student the sheet names or the system proposes (its QR code, the shaded ID, the server's `student_name` /
  /// `masked_id`); a person still decides. Null when nobody is named.
  OmrStudent? get proposed {
    // the codes where naming a student is a proposal (a conflict lists its own choices; already-scanned, not in the
    // exam and an online attempt name the student the problem is about, not the sheet's owner to pick)
    if (const {'identifier_conflict', 'student_already_scanned', 'student_not_in_exam', 'attempt_in_progress'}.contains(code)) return null;
    for (final p in const ['qr_', 'read_', '']) {
      final s = namedStudent(p);
      if (s != null) return s;
    }
    return null;
  }

  /// The student [prefix]`student_id` names, with the server's `…_name` / `…_masked_id` (prefix '' = `student_id`,
  /// `student_name`, `masked_id`; 'uploaded_for' = `uploaded_for`, `uploaded_for_name`, `uploaded_for_masked_id`);
  /// null when the reading holds no such id.
  OmrStudent? namedStudent(String prefix) {
    final upload = prefix == 'uploaded_for';
    final id = _intOrNull(reading[upload ? 'uploaded_for' : '${prefix}student_id']);
    if (id == null) return null;
    final name = '${reading[upload ? 'uploaded_for_name' : '${prefix}student_name'] ?? ''}'.trim();
    final masked = '${reading[upload ? 'uploaded_for_masked_id' : '${prefix}masked_id'] ?? ''}'.trim();
    final known = candidates.where((c) => c.id == id).firstOrNull;
    return OmrStudent(id, name.isNotEmpty ? name : (known?.name ?? ''),
        identifier: masked.isNotEmpty ? omrMasked(masked) : known?.identifier, email: known?.email);
  }

  /// student_not_in_exam / attempt_in_progress: the student the sheet names, in words ("Sara Nabil ••••0121").
  String? get namedText {
    if (!const {'student_not_in_exam', 'attempt_in_progress'}.contains(code)) return null;
    final s = namedStudent('') ?? namedStudent('qr_') ?? namedStudent('read_');
    if (s == null || (s.name.trim().isEmpty && (s.identifier ?? '').isEmpty)) return null;
    return [if (s.name.trim().isNotEmpty) s.name.trim(), if ((s.identifier ?? '').isNotEmpty) omrLtr(s.identifier!)].join(' ');
  }

  /// Why [proposed] is offered.
  String get proposedWhy {
    final p = proposed;
    if (p != null && p.id == _intOrNull(reading['qr_student_id'])) return t('رمز QR في الورقة يحمل اسمه', "The sheet's QR code names this student");
    if (p != null && p.id == _intOrNull(reading['read_student_id'])) return t('رقمه على الورقة', "The sheet shows this student's ID");
    return t('اقتراح النظام', "The system's proposal");
  }

  /// student_already_scanned: whose sheet is already graded — `student_name` + `masked_id`, else the one candidate.
  String? get gradedStudentText {
    final name = '${reading['student_name'] ?? ''}'.trim();
    final masked = '${reading['masked_id'] ?? ''}'.trim();
    final c = candidates.length == 1 ? candidates.first : null;
    final n = name.isNotEmpty ? name : (c?.name.trim() ?? '');
    final m = masked.isNotEmpty ? omrMasked(masked) : (c?.identifier ?? '');
    if (n.isEmpty && m.isEmpty) return null;
    return [if (n.isNotEmpty) n, if (m.isNotEmpty) omrLtr(m)].join(' ');
  }

  /// The graded student's name alone (the Replace button names it).
  String? get gradedStudentName {
    final name = '${reading['student_name'] ?? ''}'.trim();
    if (name.isNotEmpty) return name;
    final c = candidates.length == 1 ? candidates.first.name.trim() : '';
    return c.isEmpty ? null : c;
  }

  /// student_already_scanned: the graded page ("Page 4 · wa03.jpg": its name in its batch, else an older server's
  /// page number); null when the server does not say.
  String? get gradedPageText {
    final label = '${reading['other_page_label'] ?? ''}'.trim();
    final no = label.isNotEmpty ? label : _intOrNull(reading['other_page_no'])?.toString();
    final file = '${reading['other_file_name'] ?? ''}'.trim();
    final parts = [if (no != null) t('الصفحة $no', 'Page $no'), if (file.isNotEmpty) file];
    return parts.isEmpty ? null : parts.join(' · ');
  }
  String get idKind => '${reading['kind'] ?? ''}';
  List<OmrDigit> get digits {
    final low = {for (final x in (reading['low'] is List ? reading['low'] as List : const [])) asInt(x)};
    final rows = asMapList(reading['digits']);
    if (rows.isNotEmpty) {
      return [for (final d in rows) OmrDigit(asInt(d['index']), '${d['digit'] ?? ''}', _dbl(d['confidence']), low: low.contains(asInt(d['index'])))];
    }
    final v = readValue;
    return [for (var i = 0; i < v.length; i++) OmrDigit(i, v[i], null, low: low.contains(i))];
  }

  /// The students the reading may name (a duplicate value, the closest identifiers); empty when the server sends none.
  List<OmrStudent> get candidates => [for (final c in asMapList(reading['candidates'])) ?OmrStudent.fromJson(c)];

  /// identifier_conflict: the student the page was uploaded for, and whom the sheet names (shaded ID / signed QR).
  int? get uploadedFor => _intOrNull(reading['uploaded_for']);
  int? get sheetStudentId => _intOrNull(reading['read_student_id']) ?? _intOrNull(reading['qr_student_id']);

  // handwriting (D-160)
  bool get written => kOmrWrittenKinds.contains(kind);

  /// What the reader read, or the teacher's corrected text ("\n" between blanks).
  String get writtenText => '${reading['text'] ?? asMap(reading['reading'])['text'] ?? ''}';

  /// One text per blank (completion), else the one text.
  List<String> get texts {
    final x = _strs(reading['texts']);
    if (x.isNotEmpty) return x;
    final b = blanks;
    if (b.isNotEmpty) return [for (final v in b) v.given];
    return [writtenText];
  }

  List<OmrBlank> get blanks => [for (final (i, b) in asMapList(reading['blanks']).indexed) OmrBlank.fromJson(i, b)];

  /// How many texts a fix takes: the question's blanks, else the reading's.
  int get blankCount {
    if (kind != 'completion') return 1;
    final q = question?.blanks;
    if (q != null && q > 0) return q;
    final b = asMapList(reading['blanks']).length;
    return b > 0 ? b : 1;
  }

  /// The suggested score (null = no suggestion: the teacher sets the score).
  double? get suggestedScore => _dbl(reading['suggested_score']);

  /// The question's points on this paper.
  double get maxPoints => _dbl(reading['max']) ?? _dbl(reading['points']) ?? question?.points ?? 0;
  double get scoreStep => question?.step ?? 0.5;

  /// A short answer's suggestion is being recomputed after a fix: "accept" is refused until it lands.
  bool get pending => reading['pending'] == true;
  bool get corrected => reading['corrected'] == true;
  String? get lang => reading['lang']?.toString() ?? question?.lang;

  /// full | partial | zero | empty | null.
  String? get band => reading['band']?.toString();

  /// 0 … 1, rescaled by the engine.
  double? get similarity => _dbl(reading['similarity']);
  List<OmrKeyword> get keywords => [
        for (final k in asMapList(reading['keywords']))
          OmrKeyword('${k['term'] ?? ''}',
              found: k['found'] is List ? _strs(k['found']) : (k['found'] == null || '${k['found']}'.isEmpty ? const [] : ['${k['found']}']),
              how: k['how']?.toString(),
              weight: _dbl(k['weight'])),
      ];

  /// The keywords not found (the server's own list when sent, else the ones without a hit).
  List<String> get missingKeywords {
    final m = _strs(reading['missing_keywords']);
    return m.isNotEmpty ? m : [for (final k in keywords) if (!k.hit) k.term];
  }

  List<String> get reasons => _strs(reading['reasons']);

  /// The reader's confidence of a short answer; null for typed text.
  double? get readConfidence => _dbl(asMap(reading['reading'])['confidence']);

  /// The optional second reading (Arabic, low confidence; it never changes a score).
  String? get secondPassText {
    final v = asMap(reading['second_pass'])['text']?.toString();
    return v == null || v.trim().isEmpty ? null : v;
  }

  /// One tap accepts the suggestion: the server has one and is not recomputing it.
  bool get canAcceptSuggestion => written && can('accept') && !pending && suggestedScore != null;

  // form
  /// The exam's forms as the reading lists them (`forms: ["A", "B"]`).
  List<String> get forms => _strs(reading['forms']);

  /// marker → the form it read (`{qr: B, printed: A}`).
  Map<String, String> get markersRead {
    final r = asMap(reading['read']).isNotEmpty ? asMap(reading['read']) : asMap(reading['markers']);
    return {for (final e in r.entries) if (e.value != null) e.key: '${e.value}'};
  }

  /// What the person decided, in words ("A", "Blank", "Student #106", "Form B", "Set aside").
  String get resolutionText {
    final r = resolution;
    final a = '${r['action'] ?? ''}';
    return switch (a) {
      'choose' => _strs(r['options']).join(', '),
      'blank' => t('بلا إجابة', 'No answer'),
      'accept' when written => t('قُبلت الدرجة المقترحة ${omrNum(_dbl(r['score']))}', 'Accepted the suggested ${omrNum(_dbl(r['score']))}'),
      'set_score' => t('الدرجة ${omrNum(_dbl(r['score']))}', 'Score ${omrNum(_dbl(r['score']))}'),
      'fix_text' when r['score'] != null => t('صُحّح النص · الدرجة ${omrNum(_dbl(r['score']))}', 'Text fixed · score ${omrNum(_dbl(r['score']))}'),
      'fix_text' => t('صُحّح النص', 'Text fixed'),
      'superseded' => t('طابقت إجابة مقبولة', 'Matched an accepted answer'),
      'replaced' => t('استُبدلت الصفحة بصورة أوضح', 'The page was replaced with a clearer image'),
      'assign' || 'accept' || 'fix' => r['value'] != null ? t('الرقم ${r['value']}', 'ID ${r['value']}') : t('الطالب #${r['student_id']}', 'Student #${r['student_id']}'),
      'replace' => t('استُبدلت الورقة المصححة', 'Replaced the graded sheet'),
      'confirm' => t('النموذج ${r['form']}', 'Form ${r['form']}'),
      'dismiss' => t('نُحّيت الورقة', 'Set aside'),
      _ => a,
    };
  }
}

/// `GET …/review-items`.
class OmrReviewList {
  const OmrReviewList({this.items = const [], this.total = 0, this.openByKind = const {}});
  final List<OmrReviewItem> items;
  final int total;
  final Map<String, int> openByKind;

  factory OmrReviewList.fromJson(Map<String, dynamic> m) => OmrReviewList(
        items: [for (final x in asMapList(m['items'])) OmrReviewItem.fromJson(x)],
        total: asInt(m['total']),
        openByKind: {for (final e in asMap(m['open_by_kind']).entries) e.key: asInt(e.value)},
      );

  int get openTotal => openByKind.values.fold(0, (a, b) => a + b);

  /// The kinds to offer as filters: the known ones that have open items, then any new kind the server sends.
  List<String> get kinds => [
        for (final k in kOmrKinds) if ((openByKind[k] ?? 0) > 0) k,
        for (final k in openByKind.keys) if (!kOmrKinds.contains(k) && (openByKind[k] ?? 0) > 0) k,
      ];
}

/// The attempt after a decision: `{id, state, score, max_score, percentage, passed}`.
class OmrAttemptScore {
  const OmrAttemptScore({required this.id, required this.state, this.score, this.maxScore, this.percentage, this.passed});
  final int id;
  final String state;
  final double? score;
  final double? maxScore;
  final double? percentage;
  final bool? passed;

  bool get graded => state == 'graded' && score != null;

  static OmrAttemptScore? fromJson(Object? v) {
    final m = asMap(v);
    if (m.isEmpty) return null;
    return OmrAttemptScore(
        id: asInt(m['id']),
        state: '${m['state'] ?? ''}',
        score: _dbl(m['score']),
        maxScore: _dbl(m['max_score']),
        percentage: _dbl(m['percentage']),
        passed: m['passed'] is bool ? m['passed'] as bool : null);
  }
}

/// `POST …/resolve`: the item, the page's state, the regraded attempt and the next open item.
class OmrResolveReply {
  const OmrResolveReply({required this.item, this.pageStatus, this.openOnPage = 0, this.attempt, this.nextItemId});
  final OmrReviewItem item;
  final String? pageStatus;
  final int openOnPage;
  final OmrAttemptScore? attempt;
  final int? nextItemId;

  factory OmrResolveReply.fromJson(Map<String, dynamic> m) => OmrResolveReply(
        item: OmrReviewItem.fromJson(asMap(m['item'])),
        pageStatus: m['page_status']?.toString(),
        openOnPage: asInt(m['open_items_on_page']),
        attempt: OmrAttemptScore.fromJson(m['attempt']),
        nextItemId: _intOrNull(m['next_item_id']),
      );

  /// The decided item is still open: a fixed text that matched near again, or a short answer being recomputed.
  bool get stillOpen => item.open;

  /// The one line shown after the fix: the new score, or what still waits on this paper.
  String get summary {
    if (item.open && item.written) {
      return item.pending
          ? t('حُفظ النص · تُحسب الدرجة المقترحة من جديد', 'Text saved · the suggestion is being worked out again')
          : t('حُفظ النص وطوبق من جديد · أكّد الاقتراح الجديد أو حدّد الدرجة', 'Text saved and matched again · confirm the new suggestion or set the score');
    }
    final a = attempt;
    if (a != null && a.graded) {
      final pct = a.percentage == null ? '' : ' · ${omrNum(a.percentage)}%';
      final v = omrLtr('${omrNum(a.score)} / ${omrNum(a.maxScore)}$pct');
      return t('الدرجة الجديدة $v', 'New score $v');
    }
    if (openOnPage > 0) {
      return t('حُفظ · بقي $openOnPage على هذه الورقة قبل حساب الدرجة', 'Saved · $openOnPage more on this paper before it is scored');
    }
    if (pageStatus == 'dismissed') return t('حُفظ · نُحّيت الورقة', 'Saved · the paper was set aside');
    return t('حُفظ', 'Saved');
  }
}

/// The body of a decision (only the keys the action takes).
Map<String, dynamic> omrResolveBody(String action,
        {int? studentId, String? value, String? form, List<String>? options, double? score, String? text, List<String>? texts, String? reason}) =>
    {
      'action': action,
      'student_id': ?studentId,
      'value': ?value,
      'form': ?form,
      'options': ?options,
      'score': ?score,
      'text': ?text,
      'texts': ?texts,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    };

/// `fix_text` of a handwritten item: one text, or one per blank when the question has several.
Map<String, dynamic> omrFixTextBody(List<String> texts, {required int blanks}) => blanks > 1
    ? omrResolveBody('fix_text', texts: [for (final x in texts) x.trim()])
    : omrResolveBody('fix_text', text: (texts.isEmpty ? '' : texts.first).trim());

/// The scores a teacher may set: 0 … [max] in steps of [step] (the full points always included).
List<double> omrScoreSteps(double max, {double step = 0.5}) {
  if (max <= 0 || step <= 0) return const [0];
  final out = <double>[];
  for (var i = 0; i * step < max - 1e-9; i++) {
    out.add(double.parse((i * step).toStringAsFixed(4)));
  }
  out.add(max);
  return out;
}

/// The nearest allowed score to [v] (0 … [max]).
double omrSnapScore(double v, double max, {double step = 0.5}) {
  final steps = omrScoreSteps(max, step: step);
  var best = steps.first;
  for (final s in steps) {
    if ((s - v).abs() < (best - v).abs()) best = s;
  }
  return best;
}

// ── the full page ───────────────────────────────────────────────────────────────────────────────────────────────

/// One detected bubble of the page (source pixels): an answer bubble (`n`, `state`) or an ID / form bubble.
class OmrMark {
  const OmrMark({required this.label, required this.cx, required this.cy, required this.r, this.n, this.idColumn, this.form, this.mark, this.state});
  final String label;
  final double cx, cy, r;
  final int? n;
  final int? idColumn;
  final String? form;
  final String? mark;
  final String? state;

  /// Clear answers vs the ones that wait for a person (multiple / uncertain / blank).
  bool get flagged => state != null && state != 'clear';
  bool get isAnswer => n != null;

  factory OmrMark.fromJson(Map<String, dynamic> m) => OmrMark(
        label: '${m['label'] ?? ''}',
        cx: _dbl(m['cx']) ?? 0,
        cy: _dbl(m['cy']) ?? 0,
        r: _dbl(m['r']) ?? 0,
        n: _intOrNull(m['n']),
        idColumn: _intOrNull(m['id_column']),
        form: m['form']?.toString(),
        mark: m['mark']?.toString(),
        state: m['state']?.toString(),
      );
}

/// One question as read on the page.
class OmrAnswerMark {
  const OmrAnswerMark({required this.questionId, required this.n, required this.state, this.selected = const [], this.box, this.finalScore, this.reviewState});
  final int questionId;
  final int n;
  final String state;
  final List<String> selected;

  /// `[x, y, w, h]` (source px) — present for the flagged rows.
  final List<double>? box;
  final double? finalScore;
  final String? reviewState;

  bool get flagged => state != 'clear';

  factory OmrAnswerMark.fromJson(Map<String, dynamic> m) {
    final b = m['box'] is List ? [for (final x in m['box'] as List) _dbl(x) ?? 0] : null;
    return OmrAnswerMark(
      questionId: asInt(m['question_id']),
      n: asInt(m['n']),
      state: '${m['state'] ?? ''}',
      selected: _strs(m['selected']),
      box: b != null && b.length == 4 ? b : null,
      finalScore: _dbl(m['final_score']),
      reviewState: m['review_state']?.toString(),
    );
  }
}

/// `GET …/omr/pages/{id}`.
class OmrPageView {
  const OmrPageView({
    required this.id,
    this.label,
    this.status = '',
    this.studentId,
    this.attemptId,
    this.fileName,
    this.imageUrl,
    this.width,
    this.height,
    this.marks = const [],
    this.answers = const [],
    this.identifierBox,
    this.identifierValue,
    this.formValue,
    this.items = const [],
    this.problem = '',
  });

  final int id;
  final String? label;
  final String status;
  final int? studentId;
  final int? attemptId;
  final String? fileName;
  final String? imageUrl;
  final double? width, height;
  final List<OmrMark> marks;
  final List<OmrAnswerMark> answers;
  final List<double>? identifierBox;
  final String? identifierValue;
  final String? formValue;

  /// The page's review items: (id, kind, code, status).
  final List<({int id, String kind, String code, int? questionId, String status})> items;

  /// The page's quality sentence (a rejected page), in the app's language.
  final String problem;

  factory OmrPageView.fromJson(Map<String, dynamic> m) {
    final p = asMap(m['page']);
    final size = m['size'] is List ? [for (final x in m['size'] as List) _dbl(x) ?? 0] : const <double>[];
    final ident = asMap(m['identifier']);
    final ib = ident['box'] is List ? [for (final x in ident['box'] as List) _dbl(x) ?? 0] : null;
    return OmrPageView(
      id: asInt(p['id']),
      label: p['page_label']?.toString(),
      status: '${p['status'] ?? ''}',
      studentId: _intOrNull(p['student_id']),
      attemptId: _intOrNull(p['attempt_id']),
      fileName: p['file_name']?.toString(),
      imageUrl: m['image_url']?.toString(),
      width: size.length == 2 ? size[0] : null,
      height: size.length == 2 ? size[1] : null,
      marks: [for (final o in asMapList(m['overlay'])) OmrMark.fromJson(o)],
      answers: [for (final a in asMapList(m['answers'])) OmrAnswerMark.fromJson(a)],
      identifierBox: ib != null && ib.length == 4 ? ib : null,
      identifierValue: ident['value']?.toString(),
      formValue: asMap(m['form'])['value']?.toString(),
      items: [
        for (final i in asMapList(m['items']))
          (id: asInt(i['id']), kind: '${i['kind'] ?? ''}', code: '${i['code'] ?? ''}', questionId: _intOrNull(i['question_id']), status: '${i['status'] ?? ''}'),
      ],
      problem: '${(AppConfig.lang == 'ar' ? p['ar'] : p['en']) ?? ''}',
    );
  }
}

// ── the manual-change trail (D-158) ─────────────────────────────────────────────────────────────────────────────

class OmrChange {
  const OmrChange({required this.id, required this.entity, this.entityId, required this.field, this.old, this.next, this.actorId, this.reason, this.at});
  final int id;
  final String entity;
  final int? entityId;
  final String field;
  final Object? old;
  final Object? next;
  final int? actorId;
  final String? reason;
  final DateTime? at;

  factory OmrChange.fromJson(Map<String, dynamic> m) => OmrChange(
        id: asInt(m['id']),
        entity: '${m['entity'] ?? ''}',
        entityId: _intOrNull(m['entity_id']),
        field: '${m['field'] ?? ''}',
        old: m['old'],
        next: m['new'],
        actorId: _intOrNull(m['actor_id']),
        reason: m['reason']?.toString(),
        at: omrUtc(m['at']),
      );

  /// "Question 5: unclear → A", "Student ID: 9999999999 → student #106", "Form: QR B · printed A → B".
  String get summary {
    final o = asMap(old), n = asMap(next);
    switch (entity) {
      case 'answer' when field == 'score':
        final was = o['suggested'] == null ? t('بلا اقتراح', 'no suggestion') : t('مقترح ${omrNum(_dbl(o['suggested']))}', 'suggested ${omrNum(_dbl(o['suggested']))}');
        return t('إجابة مكتوبة: $was ← ${omrNum(_dbl(n['score']))}', 'Written answer: $was → ${omrNum(_dbl(n['score']))}');
      case 'answer' when field == 'text':
        final now = n['text'] is List ? _strs(n['text']).join(' · ') : '${n['text'] ?? ''}';
        return t('إجابة مكتوبة: صُحّح النص ← «$now»', 'Written answer: text corrected → "$now"');
      case 'scan_page':
        return t('استُبدلت صفحة مرفوضة بصورة أوضح', 'A rejected page was replaced with a clearer image');
      case 'answer':
        final was = '${o['state'] ?? ''}';
        final now = n['blank'] == true ? t('بلا إجابة', 'no answer') : _strs(n['options']).join(', ');
        return t('السؤال ${o['n'] ?? ''}: ${omrStateText(was)} ← $now', 'Question ${o['n'] ?? ''}: ${omrStateText(was)} → $now');
      case 'identifier':
        final was = omrNothingRead('${o['value'] ?? ''}') ? '—' : '${o['value']}';
        final now = n['action'] == 'dismiss' ? t('نُحّيت', 'set aside') : (n['student_id'] != null ? t('الطالب #${n['student_id']}', 'student #${n['student_id']}') : '${n['action'] ?? ''}');
        return t('رقم الطالب: $was ← $now', 'Student ID: $was → $now');
      case 'form':
        final m = asMap(o['markers']);
        final was = m.isEmpty ? '—' : m.entries.map((e) => '${omrMarkerText(e.key)} ${e.value ?? '—'}').join(' · ');
        final now = n['action'] == 'dismiss' ? t('نُحّيت', 'set aside') : '${n['form'] ?? ''}';
        return t('النموذج: $was ← $now', 'Form: $was → $now');
      default:
        return t('${omrCodeText('${o['code'] ?? ''}')}: نُحّيت', '${omrCodeText('${o['code'] ?? ''}')}: set aside');
    }
  }
}

/// Nothing of an ID was read: empty, or an older server's question marks ("??", "????", "? ?").
bool omrNothingRead(String v) => RegExp(r'^[\s?\-_]*$').hasMatch(v);

/// "••••0121" for a server's last-4 `masked_id` ("0121" or already "••••0121").
String omrMasked(String v) => RegExp(r'^\d{1,4}$').hasMatch(v) ? '••••$v' : v;

/// "Today, 10:42 AM" / "2 Nov 2026 · 10:42 AM" in the platform / organization time zone.
String omrWhenText(DateTime utc) => _sameDay(utc) ? t('اليوم، ${AppTime.time(utc)}', 'Today, ${AppTime.time(utc)}') : AppTime.dateTime(utc);

/// "Changed by you · 10:42" (the server's audited actor and time, D-158).
String omrChangedBy(int? actorId, DateTime? at, {int? meId}) {
  final who = actorId != null && actorId == meId ? t('بواسطتك', 'by you') : (actorId == null ? '' : t('بواسطة #$actorId', 'by #$actorId'));
  final when = at == null ? '' : ' · ${_sameDay(at) ? AppTime.time(at) : AppTime.dateTime(at)}';
  return t('عُدّل $who$when', 'Changed $who$when');
}

bool _sameDay(DateTime utc) {
  final a = AppTime.toZone(utc), b = AppTime.toZone(DateTime.now().toUtc());
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

// ── results ─────────────────────────────────────────────────────────────────────────────────────────────────────

class OmrStudentResult {
  const OmrStudentResult({
    required this.attemptId,
    this.studentId,
    this.studentCode,
    this.name,
    required this.state,
    this.score,
    this.maxScore,
    this.percentage,
    this.passed,
    this.forms = const [],
    this.openReview = 0,
    this.graded = false,
    this.correct = 0,
    this.answered = 0,
  });

  final int attemptId;
  final int? studentId;
  final String? studentCode;
  final String? name;
  final String state;
  final double? score, maxScore, percentage;
  final bool? passed;
  final List<String> forms;
  final int openReview;
  final bool graded;
  final int correct, answered;

  /// The name, else the anonymous code, else the id.
  String get who {
    if ((name ?? '').trim().isNotEmpty) return name!.trim();
    if ((studentCode ?? '').isNotEmpty) return studentCode!;
    return studentId == null ? '—' : t('طالب #$studentId', 'Student #$studentId');
  }

  String get formText => forms.isEmpty ? '—' : forms.join(', ');

  factory OmrStudentResult.fromJson(Map<String, dynamic> m) {
    final f = m['form'];
    return OmrStudentResult(
      attemptId: asInt(m['attempt_id']),
      studentId: _intOrNull(m['student_id']),
      studentCode: m['student_code']?.toString(),
      name: m['name']?.toString(),
      state: '${m['state'] ?? ''}',
      score: _dbl(m['score']),
      maxScore: _dbl(m['max_score']),
      percentage: _dbl(m['percentage']),
      passed: m['passed'] is bool ? m['passed'] as bool : null,
      forms: f is List ? _strs(f) : (f == null ? const [] : ['$f']),
      openReview: asInt(m['open_review']),
      graded: m['graded'] == true,
      correct: asInt(m['correct']),
      answered: asInt(m['answered']),
    );
  }
}

class OmrQuestionStat {
  const OmrQuestionStat({
    required this.n,
    required this.questionId,
    required this.type,
    required this.points,
    this.scored = 0,
    this.correct = 0,
    this.difficulty,
    this.mostChosenWrong,
    this.mostChosenWrongCount = 0,
    this.distribution = const {},
  });

  final int n;
  final int questionId;
  final String type;
  final double points;
  final int scored, correct;

  /// Share of the scored answers that are right (0–1); null before anything is scored.
  final double? difficulty;
  final String? mostChosenWrong;
  final int mostChosenWrongCount;

  /// letter | blank | multiple | pending → count.
  final Map<String, int> distribution;

  /// The option letters in the order of the sheet (the buckets that are not blank / multiple / pending).
  List<String> get letters => [for (final k in distribution.keys) if (!const {'blank', 'multiple', 'pending'}.contains(k)) k];

  factory OmrQuestionStat.fromJson(Map<String, dynamic> m) => OmrQuestionStat(
        n: asInt(m['n']),
        questionId: asInt(m['question_id']),
        type: '${m['type'] ?? ''}',
        points: _dbl(m['points']) ?? 0,
        scored: asInt(m['scored']),
        correct: asInt(m['correct']),
        difficulty: _dbl(m['difficulty']),
        mostChosenWrong: m['most_chosen_wrong']?.toString(),
        mostChosenWrongCount: asInt(m['most_chosen_wrong_count']),
        distribution: {for (final e in asMap(m['distribution']).entries) e.key: asInt(e.value)},
      );
}

class OmrResults {
  const OmrResults({
    required this.examId,
    this.title = '',
    this.students = const [],
    this.questions = const [],
    this.bins = const [],
    this.studentsTotal = 0,
    this.graded = 0,
    this.openReviewItems = 0,
    this.mean,
    this.max,
    this.min,
    this.passed = 0,
    this.publishedAt,
    this.anonymous = false,
  });

  final int examId;
  final String title;
  final List<OmrStudentResult> students;
  final List<OmrQuestionStat> questions;

  /// Percent bins `(from, to, count)`.
  final List<({int from, int to, int count})> bins;
  final int studentsTotal, graded, openReviewItems, passed;
  final double? mean, max, min;
  final DateTime? publishedAt;
  final bool anonymous;

  factory OmrResults.fromJson(Map<String, dynamic> m) {
    final s = asMap(m['summary']);
    return OmrResults(
      examId: asInt(m['exam_id']),
      title: '${m['title'] ?? ''}',
      students: [for (final x in asMapList(m['students'])) OmrStudentResult.fromJson(x)],
      questions: [for (final x in asMapList(m['questions'])) OmrQuestionStat.fromJson(x)],
      bins: [for (final b in asMapList(m['distribution'])) (from: asInt(b['from']), to: asInt(b['to']), count: asInt(b['count']))],
      studentsTotal: asInt(s['students']),
      graded: asInt(s['graded']),
      openReviewItems: asInt(s['open_review_items']),
      mean: _dbl(s['mean_percentage']),
      max: _dbl(s['max_percentage']),
      min: _dbl(s['min_percentage']),
      passed: asInt(s['passed']),
      publishedAt: omrUtc(m['published_at']),
      anonymous: m['anonymous'] == true,
    );
  }

  int get inReview => students.where((s) => !s.graded).length;
  int get failed => students.where((s) => s.graded && s.passed == false).length;
}

/// `POST …/omr/results/publish`.
class OmrPublishReply {
  const OmrPublishReply({this.publishedAt, this.gradedOnly = false, this.visibleAttempts = 0, this.openReviewItems = 0});
  final DateTime? publishedAt;
  final bool gradedOnly;
  final int visibleAttempts;
  final int openReviewItems;

  factory OmrPublishReply.fromJson(Map<String, dynamic> m) => OmrPublishReply(
        publishedAt: omrUtc(m['published_at']),
        gradedOnly: m['graded_only'] == true,
        visibleAttempts: asInt(m['visible_attempts']),
        openReviewItems: asInt(m['open_review_items']),
      );
}

// ── codes in plain words ────────────────────────────────────────────────────────────────────────────────────────

String omrStateText(String state) => switch (state) {
      'clear' => t('واضحة', 'clear'),
      'blank' => t('فارغة', 'blank'),
      'multiple' => t('أكثر من إجابة', 'multiple'),
      'uncertain' => t('غير واضحة', 'unclear'),
      _ => state,
    };

String omrMarkerText(String marker) => switch (marker) {
      'qr' => 'QR',
      'printed' => t('الحرف المطبوع', 'printed'),
      'bubble' => t('التظليل', 'shaded'),
      _ => marker,
    };

/// The server's review codes (omr_common.REVIEW_TEXT) — used only when an item carries no sentence of its own.
String omrCodeText(String code) => switch (code) {
      'identifier_no_match' => t('لا يوجد طالب بهذا الرقم', 'No student has this ID'),
      'identifier_duplicate' => t('أكثر من طالب لديهم هذا الرقم', 'More than one student has this ID'),
      'identifier_unclear' => t('تعذّرت قراءة رقم الطالب بثقة', 'The student ID could not be read with confidence'),
      'identifier_blank' => t('رقم الطالب فارغ', 'The student ID is empty'),
      'identifier_missing' => t('هذه الورقة لا تحمل رقم طالب', 'This sheet carries no student ID'),
      'identifier_not_set' => t('لم يُحدَّد معرّف الطالب للاختبار: اختر الطالب', 'The exam has no student identifier: choose the student'),
      'identifier_conflict' => t('رمز QR ورقم الطالب المظلّل يشيران إلى طالبين مختلفين', 'The QR code and the shaded ID name different students'),
      'student_not_in_exam' => t('هذا الطالب ليس من طلاب الاختبار', "This student is not in the exam's audience"),
      'student_already_scanned' => t('لهذا الطالب ورقة مصححة بالفعل', 'This student already has a graded sheet'),
      'attempt_in_progress' => t('للطالب محاولة جارية على الإنترنت', 'The student has an online attempt in progress'),
      'form_unconfirmed' => t('تعذّر تأكيد النموذج', 'Model could not be confirmed'),
      'form_unknown' => t('الورقة تحمل نموذجًا غير موجود في هذا الاختبار', 'The sheet names a form this exam does not have'),
      'qr_forged' => t('رمز QR في الورقة ليس رمزًا صالحًا لهذا الاختبار', "The sheet's QR code is not a valid code of this exam"),
      'qr_mismatch' => t('هذه الورقة تخص اختبارًا آخر أو إصدارًا آخر', 'This sheet belongs to another exam or version'),
      'key_missing' => t('مفتاح هذا النموذج لا يحوي إجابة هذا السؤال', "This form's answer key has no answer for this question"),
      'near_match' => t('قريبة من إجابة مقبولة: أكّد الدرجة المقترحة', 'Close to an accepted answer: confirm the suggested credit'),
      'low_confidence' => t('تعذّرت قراءة الخط بثقة', 'The handwriting could not be read with confidence'),
      'checker_disagrees' => t('القارئان لم يقرآ النص نفسه', 'The two readers did not read the same text'),
      'blank_box' => t('مربع الإجابة يبدو فارغًا', 'The answer box looks empty'),
      'outcome_not_final' => t('لم تطابق أي إجابة مقبولة: أكّد الدرجة', 'No accepted answer matched: confirm the score'),
      'handwriting_always_reviewed' => t('الخط العربي المكتوب باليد يراجعه المعلم دائمًا', 'Arabic handwriting is always checked by the teacher'),
      'no_completion_rule' => t('الإجابات المكتوبة بخط اليد يراجعها المعلم', 'Handwriting is checked by the teacher'),
      'several_blanks_in_one_box' => t('كُتبت عدة فراغات في مربع واحد', 'Several blanks were written in one box'),
      'blank_count_mismatch' => t('عدد الأسطر لا يطابق عدد الفراغات', 'The number of lines does not match the number of blanks'),
      'short_answer' => t('إجابة قصيرة: أكّد الدرجة أو عدّلها', 'Short answer: confirm or set the score'),
      'uncertain' => t('التظليل غير واضح', 'The mark is unclear'),
      'blank' => t('لم تُظلَّل أي إجابة', 'No answer was shaded'),
      'multiple' => t('ظُلِّلت أكثر من إجابة', 'More than one answer was shaded'),
      'option_not_in_question' => t('الخيار المظلّل غير موجود في هذا السؤال', 'The shaded option does not exist in this question'),
      _ => code,
    };

/// The text of a failed call: the server's sentence in the app's language, else a mapped code, else a generic line.
String omrErrorText(EngineResult r) {
  final en = r.detail['message_en'];
  if (AppConfig.lang == 'en' && en != null && '$en'.isNotEmpty) return '$en';
  if (AppConfig.lang == 'ar' && r.message.isNotEmpty && r.code != null) return r.message;
  final mapped = switch (r.code) {
    'review_item_resolved' => t('تمت مراجعة هذا العنصر بالفعل', 'This item was already resolved.'),
    'page_gone' => t('الصفحة الممسوحة لم تعد متاحة', 'The scanned page is no longer available.'),
    'not_a_student' => t('طالب ليس من طلاب هذا الاختبار', 'This student is not in the exam.'),
    'review_items_open' => t('ما زالت هناك عناصر تنتظر المراجعة', 'Some items still need review.'),
    'score_required' => t('أدخل الدرجة', 'Enter the score.'),
    'score_invalid' => t('الدرجة من 0 إلى الدرجة الكاملة بخطوة 0.5', 'The score is 0 to the full points in steps of 0.5.'),
    'texts_required' => t('اكتب النص الصحيح لكل فراغ', 'Type the corrected text of every blank.'),
    'no_suggestion' => t('لا توجد درجة مقترحة — أدخل الدرجة', 'There is no suggested score: enter the score.'),
    'suggestion_pending' => t('الاقتراح يُحسب الآن — أعد المحاولة بعد لحظة', 'The suggestion is being recomputed. Try again in a moment.'),
    'question_not_in_exam' => t('السؤال لم يعد في الاختبار', 'The question is no longer in the exam.'),
    'action_invalid' => t('هذا الإجراء غير متاح لهذا العنصر', 'That action is not available for this item.'),
    'forbidden' || 'org_forbidden' => t('ليست لديك صلاحية على هذا الاختبار', 'You do not have access to this exam.'),
    _ => '',
  };
  if (mapped.isNotEmpty) return mapped;
  if (r.code != null && omrCodeText(r.code!) != r.code) return omrCodeText(r.code!);
  if (r.status == 0) return t('لا يوجد اتصال — أعد المحاولة', 'No connection — try again');
  return t('تعذّر الحفظ — أعد المحاولة', 'Could not save — try again');
}

// ── API ─────────────────────────────────────────────────────────────────────────────────────────────────────────

class OmrReviewApi {
  OmrReviewApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _b = '/api/v1/exam';

  Future<EngineResult> items(int examId, {String status = 'open', String? kind}) =>
      engineCall(() => _api.get('$_b/exams/$examId/review-items', queryParams: {'status': status, 'kind': ?kind, 'limit': 500}));
  Future<EngineResult> item(int examId, int itemId) => engineCall(() => _api.get('$_b/exams/$examId/review-items/$itemId'));
  Future<EngineResult> resolve(int examId, int itemId, Map<String, dynamic> body) =>
      engineCall(() => _api.post('$_b/exams/$examId/review-items/$itemId/resolve', body: body));
  Future<EngineResult> page(int examId, int pageId) => engineCall(() => _api.get('$_b/exams/$examId/omr/pages/$pageId'));
  Future<EngineResult> changes(int examId) => engineCall(() => _api.get('$_b/exams/$examId/omr/changes'));
  Future<EngineResult> results(int examId) => engineCall(() => _api.get('$_b/exams/$examId/omr/results'));
  Future<EngineResult> publish(int examId, {bool gradedOnly = false}) =>
      engineCall(() => _api.post('$_b/exams/$examId/omr/results/publish', body: {'graded_only': gradedOnly}));

  /// The exam's audience matching [q] (a part of the name, or 3+ characters of the identifier; empty = A-Z):
  /// `{items: [{student_id, name, identifier (masked), has_identifier}], total, source, label}` — the exam's managers.
  Future<EngineResult> audience(int examId, String q, {int limit = 20}) =>
      engineCall(() => _api.get('$_b/exams/$examId/omr/students', queryParams: {'q': q, 'limit': limit}));

  /// A signed crop / page image (`/api/v1/exam/omr/images/{crop|page}/{id}?exp=&sig=`); null when it cannot be read.
  Future<Uint8List?> image(String? signedUrl) async {
    final u = Uri.tryParse(signedUrl ?? '');
    final seg = u?.pathSegments ?? const [];
    final i = seg.indexOf('images');
    if (u == null || i < 0 || seg.length < i + 3) return null;
    final what = seg[i + 1], id = seg[i + 2];
    try {
      return await _api.getBytes('$_b/omr/images/$what/$id', queryParams: u.queryParameters);
    } catch (_) {
      return null;
    }
  }
}

// ── export (Export Studio) ──────────────────────────────────────────────────────────────────────────────────────

/// The grades table for the Export Studio; call inside `bilingualExport(() => …)` so the other language's headers
/// come along.
AppTableExport omrResultsExport(OmrResults r) => AppTableExport(
      id: 'exam.omr.results',
      title: r.title.isEmpty ? t('نتائج الاختبار الورقي', 'Paper exam results') : r.title,
      subtitle: t('نتائج أوراق التظليل', 'Bubble-sheet results'),
      meta: [
        t('الطلاب: ${r.studentsTotal} · مصحّح: ${r.graded}', 'Students: ${r.studentsTotal} · graded: ${r.graded}'),
        if (r.mean != null) t('المتوسط: ${omrNum(r.mean)}%', 'Mean: ${omrNum(r.mean)}%'),
      ],
      columns: [
        AppExportColumn('student', r.anonymous ? t('الرمز', 'Code') : t('الطالب', 'Student'), locked: true),
        AppExportColumn('form', t('النموذج', 'Form')),
        AppExportColumn('score', t('الدرجة', 'Score'), type: AppColType.number, decimals: 2),
        AppExportColumn('max', t('من', 'Out of'), type: AppColType.number, decimals: 2),
        AppExportColumn('percentage', t('النسبة', 'Percent'), type: AppColType.percent, total: AppTotal.average),
        AppExportColumn('correct', t('صحيحة', 'Correct'), type: AppColType.integer),
        AppExportColumn('answered', t('مُجابة', 'Answered'), type: AppColType.integer),
        AppExportColumn('status', t('الحالة', 'Status'), type: AppColType.status, statusLabels: {
          'passed': t('ناجح', 'Passed'),
          'failed': t('لم ينجح', 'Not passed'),
          'review': t('قيد المراجعة', 'In review'),
          'graded': t('مصحّح', 'Graded'),
        }, statusTones: const {
          'passed': AppStatusTone.good,
          'failed': AppStatusTone.bad,
          'review': AppStatusTone.warn,
          'graded': AppStatusTone.neutral,
        }),
      ],
      rows: [
        for (final s in r.students)
          {
            'student': s.who,
            'form': s.formText,
            'score': s.score,
            'max': s.maxScore,
            'percentage': s.percentage,
            'correct': s.correct,
            'answered': s.answered,
            'status': !s.graded ? 'review' : (s.passed == true ? 'passed' : (s.passed == false ? 'failed' : 'graded')),
          },
      ],
    );
