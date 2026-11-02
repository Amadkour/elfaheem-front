// Bubble-sheet scanning (D-154, D-159; brief part 3, Example 5): the pure part — the engine's replies as models, the
// auto-capture decision, the live-hint pacing, the server codes in plain words and the calls. The screens are
// omr_scanner_screen.dart (camera), omr_upload_screen.dart (files + progress), omr_sheets_sheet.dart (print).
//
// Server (Exam Engine, the exam's managers; rules in exam_engine/services/omr_camera.py, omr_scan.py, omr_sheets.py):
//   POST /api/v1/exam/exams/{id}/omr/live-hint   multipart frame (a small JPEG, ≤ 400 KB, long side ≤ 1280), prev?
//        → {ok, code, en, ar, corners, corners_found, brightness, clipped, sharpness, motion, page_fraction, cv_ms, ms,
//           stat}; 503 omr_busy + Retry-After, 429 too_many_requests (300 / min / user), 413 frame_too_large
//   POST …/omr/capture   multipart photo, batch_id?, expected? → accepted {page_id, batch_id, captured, expected, en, ar,
//        duplicate?} | rejected {code, en, ar, issues} (nothing stored); 404 batch_not_found, 429 (60 / min), 503
//   POST …/scans          files[] (≤ 50 files, PNG / JPEG / WebP / PDF, ≤ 300 pages) → {batch_id, pages, duplicates, omr}
//   GET  …/omr/batches[/{batch_id}] → progress {total, done, graded, review, rejected, failed, pending, status, en, ar,
//        rejected_pages[{page_id, page_no, page_label, file_name, codes, en, ar, instruction_en, instruction_ar}]}
//   POST …/omr/pages/{page_id}/replace   multipart image (JPG / PNG / WebP) → the capture gate on the request:
//        accepted {page_id (new), replaces, batch_id, en, ar, progress} | refused {code, en, ar, page_en, page_ar,
//        issues}; 409 page_not_rejected / page_duplicate, 415, 413, 429, 503 omr_busy
//   GET / POST …/omr/sheets → what will be printed / application/pdf
//   live: job_updated {kind: omr_scan, id: batch_id, exam_id, status, done, total, page_id, page_status, en, ar}
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Offset;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';

import '../../../../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import '../../exam_engine_api.dart';
import '../exam_setup.dart' show identifierZoneMismatchText;

/// The live event kind of a scan batch's progress (`job_updated`).
const kOmrScanJobKind = 'omr_scan';

/// The server's limits (exam_engine/settings.py, routers/scans.py) — checked here first so a person is told at once.
abstract final class OmrLimits {
  static const maxFiles = 50;
  static const maxFileBytes = 25 * 1024 * 1024;
  static const maxUploadBytes = 2 * maxFileBytes;
  static const maxPages = 300;
  static const hintMaxBytes = 400 * 1024;
  static const hintMaxSide = 1280;
  static const maxCopies = 500;
  static const maxStudentSheets = 200;
  static const maxExpected = 5000;
}

String _pick(Object? ar, Object? en) {
  final a = '${ar ?? ''}', e = '${en ?? ''}';
  if (AppConfig.lang == 'ar') return a.isNotEmpty ? a : e;
  return e.isNotEmpty ? e : a;
}

double? _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

// ── live hint ───────────────────────────────────────────────────────────────────────────────────────────────────

/// One answer of `POST …/omr/live-hint`. [corners] are in the pixels of the frame that was sent ([frameW] × [frameH],
/// filled in by the caller that knows them).
class OmrLiveHint {
  const OmrLiveHint({
    required this.ok,
    required this.code,
    required this.en,
    required this.ar,
    this.corners = const [],
    this.cornersFound = 0,
    this.brightness,
    this.sharpness,
    this.motion,
    this.pageFraction,
    this.stat,
    this.frameW = 0,
    this.frameH = 0,
  });

  final bool ok;

  /// ready | no_sheet | corners | too_dark | too_bright | blurry | moving | move_closer.
  final String code;
  final String en;
  final String ar;
  final List<Offset> corners;
  final int cornersFound;
  final double? brightness;
  final double? sharpness;

  /// Null on the first frame (no `prev` sent): steadiness is not known yet.
  final double? motion;
  final double? pageFraction;

  /// The server's thumbnail of this frame, sent back as `prev` with the next one.
  final String? stat;
  final int frameW;
  final int frameH;

  static OmrLiveHint fromJson(Map<String, dynamic> j, {int frameW = 0, int frameH = 0}) => OmrLiveHint(
        ok: j['ok'] == true,
        code: '${j['code'] ?? ''}',
        en: '${j['en'] ?? ''}',
        ar: '${j['ar'] ?? ''}',
        corners: [
          for (final p in (j['corners'] as List?) ?? const [])
            if (p is List && p.length >= 2 && _d(p[0]) != null && _d(p[1]) != null) Offset(_d(p[0])!, _d(p[1])!),
        ],
        cornersFound: asInt(j['corners_found']),
        brightness: _d(j['brightness']),
        sharpness: _d(j['sharpness']),
        motion: _d(j['motion']),
        pageFraction: _d(j['page_fraction']),
        stat: j['stat']?.toString(),
        frameW: frameW,
        frameH: frameH,
      );

  /// The server's own sentence in the current language.
  String get text => _pick(ar, en);

  /// Ready AND steadiness measured (a first frame without `prev` cannot be steady yet) AND the four marks found.
  bool get steady => ok && code == 'ready' && motion != null && cornersFound >= 4;

  /// Which of the frame's quarters hold a detected corner mark: [top-left, top-right, bottom-right, bottom-left] in
  /// image space (not mirrored by the reading direction: the sheet is a physical object).
  List<bool> get cornerQuarters {
    final q = [false, false, false, false];
    if (frameW <= 0 || frameH <= 0) return q;
    for (final p in corners) {
      final right = p.dx >= frameW / 2, bottom = p.dy >= frameH / 2;
      q[bottom ? (right ? 2 : 3) : (right ? 1 : 0)] = true;
    }
    return q;
  }
}

/// The tone a hint is drawn in.
enum OmrHintTone { neutral, warn, good }

OmrHintTone omrHintTone(String code) => switch (code) {
      'ready' => OmrHintTone.good,
      'too_dark' || 'too_bright' || 'blurry' => OmrHintTone.warn,
      _ => OmrHintTone.neutral,
    };

/// Auto-capture (brief 3.1): capture when the hint said steady + sharp + lit + all four marks for [streak] answers in
/// a row spanning at least [minSpan]. After a capture it is DISARMED until the scene changes (the sheet is taken
/// away, the camera moves, a corner leaves the frame), so the same sheet is never sent twice by itself.
class AutoCaptureGate {
  AutoCaptureGate({this.streak = 3, this.minSpan = const Duration(milliseconds: 700)});

  final int streak;
  final Duration minSpan;

  /// Codes that mean the scene changed: a new sheet may come.
  static const rearmCodes = {'no_sheet', 'corners', 'moving', 'move_closer'};

  int _run = 0;
  DateTime? _since;
  bool _armed = true;

  bool get armed => _armed;

  /// 0 … 1, how far the current good run is (drawn on the guide).
  double get progress => _armed ? (_run / streak).clamp(0.0, 1.0).toDouble() : 0;

  /// One hint; true = capture now.
  bool feed(OmrLiveHint h, DateTime now) {
    if (!h.steady) {
      _run = 0;
      _since = null;
      if (!_armed && rearmCodes.contains(h.code)) _armed = true;
      return false;
    }
    if (!_armed) return false;
    _run++;
    _since ??= now;
    return _run >= streak && now.difference(_since!) >= minSpan;
  }

  /// A capture was sent (auto or by the shutter): wait for the next sheet.
  void captured() {
    _armed = false;
    _run = 0;
    _since = null;
  }

  /// Start over armed (after Retake, a camera switch, a resume).
  void reset() {
    _armed = true;
    _run = 0;
    _since = null;
  }
}

/// How long to wait before the next live-hint frame. A modest rate (≤ 2.5 frames / s, the server allows 5), and a
/// growing back-off on 503 `omr_busy` (its Retry-After first), 429 and network failures; reset by the next answer.
class HintPacer {
  HintPacer({this.interval = const Duration(milliseconds: 400), this.maxBackoff = const Duration(seconds: 8)});

  final Duration interval;
  final Duration maxBackoff;
  int _fails = 0;

  int get failures => _fails;

  /// The wait after an answer that took [took] (the next frame leaves [interval] after the last one left).
  Duration afterOk(Duration took) {
    _fails = 0;
    final left = interval - took;
    return left.isNegative ? Duration.zero : left;
  }

  /// 503 omr_busy: Retry-After (≥ 1 s), doubled for every busy answer in a row.
  Duration afterBusy(int? retryAfterSeconds) {
    _fails++;
    final base = Duration(seconds: math.max(1, retryAfterSeconds ?? 1));
    return _cap(base * math.pow(2, _fails - 1).toInt());
  }

  /// 429: the server's window, capped (the camera keeps working with the manual shutter meanwhile).
  Duration afterRateLimit(int? retryAfterSeconds) {
    _fails++;
    final s = Duration(seconds: math.max(1, retryAfterSeconds ?? 5));
    return s > const Duration(seconds: 30) ? const Duration(seconds: 30) : s;
  }

  /// No answer (network, a dead frame): 1 s, 2 s, 4 s … up to [maxBackoff].
  Duration afterError() {
    _fails++;
    return _cap(const Duration(seconds: 1) * math.pow(2, _fails - 1).toInt());
  }

  Duration _cap(Duration d) => d > maxBackoff ? maxBackoff : d;
}

/// Retry-After of a failed engine call: the body's `retry_after` (the engine puts it there next to the header).
int? retryAfterOf(EngineResult r) {
  final v = r.detail['retry_after'];
  return v is num ? v.toInt() : int.tryParse('${v ?? ''}');
}

// ── capture ─────────────────────────────────────────────────────────────────────────────────────────────────────

class OmrIssue {
  const OmrIssue(this.code, this.en, this.ar);
  final String code;
  final String en;
  final String ar;
  String get text => _pick(ar, en);
}

/// `POST …/omr/capture`: accepted ("Paper 12 of 40 captured") or rejected with the exact instruction.
class OmrCaptureResult {
  const OmrCaptureResult({
    required this.accepted,
    required this.en,
    required this.ar,
    this.code,
    this.pageId,
    this.batchId,
    this.captured = 0,
    this.expected,
    this.duplicate = false,
    this.issues = const [],
  });

  final bool accepted;
  final String? code;
  final String en;
  final String ar;
  final int? pageId;
  final int? batchId;
  final int captured;
  final int? expected;

  /// The very same photo was already stored: nothing new was added.
  final bool duplicate;
  final List<OmrIssue> issues;

  static OmrCaptureResult fromJson(Map<String, dynamic> j) => OmrCaptureResult(
        accepted: j['accepted'] == true,
        code: j['code']?.toString(),
        en: '${j['en'] ?? ''}',
        ar: '${j['ar'] ?? ''}',
        pageId: j['page_id'] == null ? null : asInt(j['page_id']),
        batchId: j['batch_id'] == null ? null : asInt(j['batch_id']),
        captured: asInt(j['captured']),
        expected: j['expected'] == null ? null : asInt(j['expected']),
        duplicate: j['duplicate'] == true,
        issues: [for (final i in asMapList(j['issues'])) OmrIssue('${i['code'] ?? ''}', '${i['en'] ?? ''}', '${i['ar'] ?? ''}')],
      );

  String get text => _pick(ar, en);

  /// The other problems of a rejected photo (the first one is [text]).
  List<String> get moreIssues => [
        for (final i in issues.skip(1))
          if (i.text.isNotEmpty && i.text != text) i.text,
      ];
}

// ── upload + progress ───────────────────────────────────────────────────────────────────────────────────────────

/// `POST …/scans` for a bubble exam.
class OmrUploadReply {
  const OmrUploadReply({required this.batchId, required this.pages, required this.duplicates, required this.omr});
  final int batchId;
  final List<int> pages;
  final int duplicates;
  final bool omr;

  static OmrUploadReply fromJson(Map<String, dynamic> j) => OmrUploadReply(
        batchId: asInt(j['batch_id']),
        pages: [for (final p in (j['pages'] as List?) ?? const []) asInt(p)],
        duplicates: asInt(j['duplicates']),
        omr: j['omr'] == true,
      );
}

/// A page the gate refused: never graded; the person re-uploads a better image.
class OmrRejectedPage {
  const OmrRejectedPage({
    required this.pageId,
    required this.pageNo,
    required this.label,
    required this.en,
    required this.ar,
    this.fileName,
    this.codes = const [],
    this.instructionEn = '',
    this.instructionAr = '',
  });

  final int pageId;
  final int pageNo;
  final String label;
  final String? fileName;
  final List<String> codes;

  /// "Page 7 is too blurry. Please upload a clearer image of it." (+ ar).
  final String en;
  final String ar;

  /// "Too blurry, hold steady." (+ ar).
  final String instructionEn;
  final String instructionAr;

  static OmrRejectedPage fromJson(Map<String, dynamic> j) => OmrRejectedPage(
        pageId: asInt(j['page_id']),
        pageNo: asInt(j['page_no'], 1),
        label: '${j['page_label'] ?? j['page_no'] ?? ''}',
        fileName: j['file_name']?.toString(),
        codes: [for (final c in (j['codes'] as List?) ?? const []) '$c'],
        en: '${j['en'] ?? ''}',
        ar: '${j['ar'] ?? ''}',
        instructionEn: '${j['instruction_en'] ?? ''}',
        instructionAr: '${j['instruction_ar'] ?? ''}',
      );

  String get text => _pick(ar, en);
  String get instruction => _pick(instructionAr, instructionEn);
}

/// `GET …/omr/batches/{id}` (the list rows have no rejected_pages).
class OmrBatchProgress {
  const OmrBatchProgress({
    required this.batchId,
    required this.kind,
    required this.total,
    required this.done,
    required this.en,
    required this.ar,
    this.graded = 0,
    this.review = 0,
    this.rejected = 0,
    this.failed = 0,
    this.pending = 0,
    this.status = 'processing',
    this.expected,
    this.createdAt,
    this.rejectedPages = const [],
  });

  final int batchId;

  /// omr (files) | camera.
  final String kind;
  final int total;

  /// Pages with an outcome (graded, review, rejected, failed, dismissed, purged).
  final int done;
  final int graded;
  final int review;
  final int rejected;
  final int failed;
  final int pending;

  /// processing | done.
  final String status;
  final int? expected;
  final String? createdAt;

  /// "12 of 40 papers processed" (+ ar).
  final String en;
  final String ar;
  final List<OmrRejectedPage> rejectedPages;

  static OmrBatchProgress fromJson(Map<String, dynamic> j) => OmrBatchProgress(
        batchId: asInt(j['batch_id']),
        kind: '${j['kind'] ?? 'omr'}',
        total: asInt(j['total']),
        done: asInt(j['done']),
        graded: asInt(j['graded']),
        review: asInt(j['review']),
        rejected: asInt(j['rejected']),
        failed: asInt(j['failed']),
        pending: asInt(j['pending']),
        status: '${j['status'] ?? 'processing'}',
        expected: j['expected'] == null ? null : asInt(j['expected']),
        createdAt: j['created_at']?.toString(),
        en: '${j['en'] ?? ''}',
        ar: '${j['ar'] ?? ''}',
        rejectedPages: [for (final p in asMapList(j['rejected_pages'])) OmrRejectedPage.fromJson(p)],
      );

  bool get finished => status == 'done';
  String get text => _pick(ar, en);
  double get fraction => total <= 0 ? (finished ? 1 : 0) : (done / total).clamp(0.0, 1.0).toDouble();

  /// The live event's numbers on top of the last fetch (the event carries done / total / status / text only).
  OmrBatchProgress withEvent(Map<String, dynamic> e) => OmrBatchProgress(
        batchId: batchId,
        kind: kind,
        total: e['total'] == null ? total : asInt(e['total']),
        done: e['done'] == null ? done : math.max(done, asInt(e['done'])),
        graded: graded,
        review: review,
        rejected: rejected,
        failed: failed,
        pending: pending,
        status: '${e['status'] ?? status}',
        expected: expected,
        createdAt: createdAt,
        en: '${e['en'] ?? en}',
        ar: '${e['ar'] ?? ar}',
        rejectedPages: rejectedPages,
      );
}

// ── printable sheets ────────────────────────────────────────────────────────────────────────────────────────────

/// `GET …/omr/sheets`.
class OmrSheetsInfo {
  const OmrSheetsInfo({
    required this.printable,
    required this.questions,
    required this.sheetQuestions,
    this.templateId,
    this.forms = const [],
    this.sheetForms = const [],
    this.formMarkers = const [],
    this.idKind = '',
  });

  final int? templateId;

  /// Only the built-in sheets are printed by the engine (a learned template is the school's own printed sheet).
  final bool printable;
  final int questions;
  final int sheetQuestions;
  final List<String> forms;
  final List<String> sheetForms;
  final List<String> formMarkers;

  /// shaded | handwritten | printed | qr | none.
  final String idKind;

  static OmrSheetsInfo fromJson(Map<String, dynamic> j) => OmrSheetsInfo(
        templateId: j['template_id'] == null ? null : asInt(j['template_id']),
        printable: j['printable'] == true,
        questions: asInt(j['questions']),
        sheetQuestions: asInt(j['sheet_questions']),
        forms: [for (final f in (j['forms'] as List?) ?? const []) '$f'],
        sheetForms: [for (final f in (j['sheet_forms'] as List?) ?? const []) '$f'],
        formMarkers: [for (final f in (j['form_markers'] as List?) ?? const []) '$f'],
        idKind: '${j['id_kind'] ?? ''}',
      );
}

/// The POST body of `…/omr/sheets`: blank sheets per form × copies, or one named sheet per student (forms cycle).
Map<String, dynamic> omrSheetsBody({List<String> forms = const [], int copies = 1, List<int> studentIds = const []}) => {
      if (forms.isNotEmpty) 'forms': forms,
      if (studentIds.isEmpty) 'copies': copies.clamp(1, OmrLimits.maxCopies),
      if (studentIds.isNotEmpty) 'student_ids': studentIds,
    };

/// Pages the request will print (the server refuses > 1000 blank or > 200 named ones).
int omrSheetsPageCount({required int forms, required int copies, required int students}) =>
    students > 0 ? students : math.max(1, forms) * copies.clamp(1, OmrLimits.maxCopies);

// ── files ───────────────────────────────────────────────────────────────────────────────────────────────────────

const omrUploadExtensions = ['jpg', 'jpeg', 'png', 'webp', 'pdf'];

/// The first problem with a pick of files, before anything is sent (null = fine).
String? omrPickProblem(List<(String, Uint8List)> files) {
  if (files.isEmpty) return null;
  if (files.length > OmrLimits.maxFiles) return omrCodeText('too_many_files');
  var total = 0;
  for (final (name, bytes) in files) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (!omrUploadExtensions.contains(ext)) return omrCodeText('unsupported_file');
    if (bytes.length > OmrLimits.maxFileBytes) return omrCodeText('file_too_large');
    total += bytes.length;
  }
  if (total > OmrLimits.maxUploadBytes) return omrCodeText('upload_too_large');
  return null;
}

/// A replacement of a rejected page is ONE photo (JPG / PNG / WebP; a PDF cannot stand for one page).
const omrReplaceExtensions = ['jpg', 'jpeg', 'png', 'webp'];

/// The problem with the picked replacement before anything is sent (null = fine).
String? omrReplaceProblem((String, Uint8List) file) {
  final (name, bytes) = file;
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (!omrReplaceExtensions.contains(ext)) {
    return t('اختر صورة واحدة (JPG أو PNG أو WebP) — لا يحلّ ملف PDF محل صفحة', 'Choose one photo (JPG, PNG or WebP) — a PDF cannot replace a page');
  }
  if (bytes.length > OmrLimits.maxFileBytes) return omrCodeText('file_too_large');
  return null;
}

/// `POST …/omr/pages/{page_id}/replace`: the gate's answer, on the request. Accepted → a new page in the same batch
/// (read like any other; the old one becomes `replaced`); refused → the exact instruction, nothing stored.
class OmrReplaceResult {
  const OmrReplaceResult({
    required this.accepted,
    required this.pageId,
    this.replaces,
    this.batchId,
    this.code,
    this.en = '',
    this.ar = '',
    this.pageEn = '',
    this.pageAr = '',
    this.issues = const [],
    this.progress,
  });

  final bool accepted;

  /// Accepted: the NEW page; refused: the rejected page itself.
  final int pageId;
  final int? replaces;
  final int? batchId;
  final String? code;

  /// Accepted: "Page 7 replaced. It is being read now."; refused: the instruction ("Too blurry, hold steady.").
  final String en, ar;

  /// Refused: "Page 7 is too blurry. Please upload a clearer image of it."
  final String pageEn, pageAr;
  final List<OmrIssue> issues;

  /// Accepted: the batch's progress after the swap.
  final OmrBatchProgress? progress;

  static OmrReplaceResult fromJson(Map<String, dynamic> j) {
    final p = asMap(j['progress']);
    return OmrReplaceResult(
      accepted: j['accepted'] == true,
      pageId: asInt(j['page_id']),
      replaces: j['replaces'] == null ? null : asInt(j['replaces']),
      batchId: j['batch_id'] == null ? null : asInt(j['batch_id']),
      code: j['code']?.toString(),
      en: '${j['en'] ?? ''}',
      ar: '${j['ar'] ?? ''}',
      pageEn: '${j['page_en'] ?? ''}',
      pageAr: '${j['page_ar'] ?? ''}',
      issues: [for (final i in asMapList(j['issues'])) OmrIssue('${i['code'] ?? ''}', '${i['en'] ?? ''}', '${i['ar'] ?? ''}')],
      progress: p.isEmpty ? null : OmrBatchProgress.fromJson(p),
    );
  }

  String get text => _pick(ar, en);

  /// Refused: the page sentence, then the instruction ("Page 2 is too blurry. … Too blurry, hold steady.").
  String get refusal {
    final page = _pick(pageAr, pageEn);
    final how = text;
    if (page.isEmpty) return how;
    if (how.isEmpty || page.contains(how)) return page;
    return '$page $how';
  }
}

/// The name a photo is sent under, from its first bytes (the server sniffs the content anyway).
String photoNameOf(Uint8List b) {
  if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'camera.png';
  if (b.length > 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45) return 'camera.webp';
  return 'camera.jpg';
}

// ── server codes ────────────────────────────────────────────────────────────────────────────────────────────────

/// The codes of these routes in plain words (the server's own text wins when it has one in the current language).
String omrCodeText(String? code, [Map<String, dynamic> detail = const {}]) => switch (code) {
      'exam_not_bubble' => t('هذا الاختبار ليس بورقة تظليل — اختر ورقة التظليل وقالبًا منشورًا في إعداد الاختبار',
          'This exam does not use a bubble sheet — choose the bubble sheet and a published template in the exam setup'),
      'template_not_found' => t('قالب ورقة التظليل غير موجود — اختر قالبًا في إعداد الاختبار', 'The exam\'s sheet template is missing — choose one in the exam setup'),
      'template_too_small' => t('القالب فيه ${detail['template_questions'] ?? '?'} سؤالًا والاختبار ${detail['questions'] ?? '?'}',
          'The sheet holds ${detail['template_questions'] ?? '?'} questions, the exam has ${detail['questions'] ?? '?'}'),
      'question_options_exceed_sheet' => t('بعض الأسئلة فيها خيارات أكثر من فقاعات الورقة', 'Some questions have more options than the sheet has bubbles'),
      'marker_not_on_template' => t('علامة النموذج المختارة غير موجودة على هذه الورقة', 'The chosen model marker is not on this sheet'),
      'forms_not_on_template' => t('بعض أكواد النماذج غير موجودة على الورقة', 'Some model codes are not on the sheet'),
      'no_bubble_questions' => t('لا توجد أسئلة اختيار في الأقسام الورقية للاختبار', 'The paper sections have no multiple-choice questions'),
      'template_not_printable' => t('قالب مخصص: اطبع ورقتك الأصلية — يطبع النظام الأوراق المدمجة فقط',
          'A learned template is your own printed sheet: the app prints built-in sheets only'),
      'form_unknown' => t('نموذج ليس في الاختبار أو على الورقة', 'A model that is not in the exam or on the sheet'),
      'identifier_zone_mismatch' => identifierZoneMismatchText(detail),
      'not_a_student' => t('طالب ليس من طلاب هذا الاختبار${detail['student_id'] == null ? '' : ' (#${detail['student_id']})'}',
          'Not a student of this exam${detail['student_id'] == null ? '' : ' (#${detail['student_id']})'}'),
      'too_many_sheets' => t('عدد كبير من الأوراق في مرة واحدة — حتى ${OmrLimits.maxStudentSheets} ورقة باسم الطالب',
          'Too many sheets at once — up to ${OmrLimits.maxStudentSheets} named sheets'),
      'too_many_files' => t('حتى ${OmrLimits.maxFiles} ملفًا في المرة', 'Up to ${OmrLimits.maxFiles} files at a time'),
      'too_many_pages' => t('حتى ${OmrLimits.maxPages} صفحة في الرفع الواحد', 'Up to ${OmrLimits.maxPages} pages per upload'),
      'unsupported_file' => t('نوع ملف غير مدعوم — صور JPG أو PNG أو WebP أو ملفات PDF', 'Unsupported file — JPG, PNG or WebP images, or PDFs'),
      'file_too_large' => t('ملف أكبر من 25 ميجابايت', 'A file is larger than 25 MB'),
      'upload_too_large' => t('حجم الرفع الكلي أكبر من 50 ميجابايت — ارفعها على دفعات', 'The upload is larger than 50 MB — send it in parts'),
      'image_too_large' => t('أبعاد الصورة أكبر من المسموح', 'The image is too large'),
      'bad_image' => t('تعذّر فتح الصورة', 'The image could not be opened'),
      'grading_busy' || 'omr_busy' => t('الخادم مشغول الآن — أعد المحاولة بعد لحظة', 'The server is busy — try again in a moment'),
      'too_many_requests' => t('طلبات كثيرة في وقت قصير — انتظر قليلًا', 'Too many requests — wait a moment'),
      'batch_not_found' => t('جلسة التصوير غير موجودة — ابدأ جلسة جديدة', 'This capture session was not found — start a new one'),
      'frame_too_large' => t('الإطار أكبر من المسموح', 'The frame is too large'),
      'expected_invalid' => t('عدد الأوراق المتوقع بين 1 و ${OmrLimits.maxExpected}', 'The expected number of papers is 1 to ${OmrLimits.maxExpected}'),
      'forbidden' => t('ليس لديك صلاحية إدارة هذا الاختبار', 'You cannot manage this exam'),
      'no_files' => t('أرفق صورة أو ملف PDF', 'Attach an image or a PDF'),
      'page_not_rejected' => t('يمكن استبدال الصفحات المرفوضة فقط', 'Only a rejected page can be replaced'),
      'page_duplicate' => t('هذه الصورة مرفوعة من قبل في هذا الاختبار — اختر صورة أخرى أوضح', 'This image was already uploaded for this exam — choose another, clearer one'),
      _ => t('تعذّر إكمال الطلب', 'The request could not be completed'),
    };

/// A failed call in plain words: the server's sentence in the current language when it sent one, else [omrCodeText].
String omrErrorText(EngineResult r) {
  if (r.status == 0) return r.message.isNotEmpty ? r.message : t('لا يوجد اتصال', 'No connection');
  final en = '${r.detail['message_en'] ?? ''}';
  if (AppConfig.lang == 'ar' && r.message.isNotEmpty && r.code != null) return r.message;
  if (AppConfig.lang != 'ar' && en.isNotEmpty) return en;
  return omrCodeText(r.code, r.detail);
}

/// The exam itself cannot be scanned (setup problem): no retry helps, the setup must change.
bool omrIsSetupProblem(String? code) => const {
      'exam_not_bubble',
      'template_not_found',
      'template_too_small',
      'question_options_exceed_sheet',
      'marker_not_on_template',
      'forms_not_on_template',
      'no_bubble_questions',
    }.contains(code);

// ── calls ───────────────────────────────────────────────────────────────────────────────────────────────────────

class OmrScanApi {
  OmrScanApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _b = '/api/v1/exam';

  Future<EngineResult> liveHint(int examId, Uint8List jpeg, {String? prev}) => engineCall(() => _api.postFiles('$_b/exams/$examId/omr/live-hint',
      files: [('frame.jpg', jpeg)], field: 'frame', fields: {'prev': ?prev}));

  Future<EngineResult> capture(int examId, Uint8List photo, {int? batchId, int? expected}) => engineCall(() => _api.postFiles(
      '$_b/exams/$examId/omr/capture',
      files: [(photoNameOf(photo), photo)],
      field: 'photo',
      fields: {'batch_id': ?batchId, 'expected': ?expected}));

  Future<EngineResult> upload(int examId, List<(String, Uint8List)> files) => engineCall(() => _api.postFiles('$_b/exams/$examId/scans', files: files));

  Future<EngineResult> batch(int examId, int batchId) => engineCall(() => _api.get('$_b/exams/$examId/omr/batches/$batchId'));

  Future<EngineResult> batches(int examId) => engineCall(() => _api.get('$_b/exams/$examId/omr/batches'));

  /// A better image for a REJECTED page (multipart `image`): the gate answers on the request ([OmrReplaceResult]).
  Future<EngineResult> replacePage(int examId, int pageId, (String, Uint8List) file) =>
      engineCall(() => _api.postFiles('$_b/exams/$examId/omr/pages/$pageId/replace', files: [file], field: 'image'));

  /// One page's state (`GET …/omr/pages/{id}` → `page.status`): how a replacement ended.
  Future<EngineResult> page(int examId, int pageId) => engineCall(() => _api.get('$_b/exams/$examId/omr/pages/$pageId'));

  Future<EngineResult> sheetsInfo(int examId) => engineCall(() => _api.get('$_b/exams/$examId/omr/sheets'));

  /// The PDF, or the failure (a JSON error body comes back as bytes here: parsed into an [EngineResult]).
  Future<(Uint8List?, EngineResult?)> sheetsPdf(int examId, Map<String, dynamic> body) async {
    try {
      final bytes = await _api.postForBytes('$_b/exams/$examId/omr/sheets', body: body);
      if (bytes.length > 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) return (bytes, null);
      return (null, EngineResult.fail(200, null, t('لم يصل ملف PDF', 'No PDF came back')));
    } on ApiException catch (e) {
      // a bytes request gets its JSON error body as bytes: decoded here so the code reaches the person
      Object? body = e.body;
      if (body is List<int>) {
        try {
          body = jsonDecode(utf8.decode(body));
        } catch (_) {}
      }
      final d = omrDetailOf(body);
      return (null, EngineResult.fail(e.statusCode, d['code']?.toString() ?? e.code, '${d['message'] ?? e.message}', d));
    } catch (e) {
      return (null, EngineResult.fail(0, null, ApiException.from(e).message));
    }
  }
}

/// Reads `{detail: {...}}` from a body that may be JSON text (an error answer to a bytes request).
Map<String, dynamic> omrDetailOf(Object? body) => asMap(asMap(body)['detail']);
