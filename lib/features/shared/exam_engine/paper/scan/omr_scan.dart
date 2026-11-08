// Bubble-sheet scanning (D-154, D-159; brief part 3, Example 5): the pure part — the engine's replies as models, the
// auto-capture decision, the live-hint pacing, the server codes in plain words and the calls. The screens are
// omr_scanner_screen.dart (camera), omr_upload_screen.dart (files + progress), omr_sheets_sheet.dart (print).
//
// Server (Exam Engine, the exam's managers; rules in exam_engine/services/omr_camera.py, omr_scan.py, omr_sheets.py):
//   POST /api/v1/exam/exams/{id}/omr/live-hint   multipart frame (a small JPEG, ≤ 400 KB, long side ≤ 1280), prev?
//        → {ok, code, en, ar, corners, corners_found, brightness, clipped, sharpness, motion, page_fraction, cv_ms, ms,
//           stat, blocking?}; 503 omr_busy + Retry-After, 429 too_many_requests (300 / min / user), 413 frame_too_large.
//           `blocking: false` (smart photos) = a gentle hint ("Add a little more light") that never stops a capture.
//   POST …/omr/capture   multipart photo, batch_id?, expected? → accepted {page_id, batch_id, captured, expected, en, ar,
//        duplicate?, result?} | rejected {code, en, ar, issues, result?} (nothing stored); 404 batch_not_found, 429, 503
//   every OMR page (capture, batch pages / rejected_pages, page, replace) may carry `result` (smart photos):
//        {tier: accept|flags|retake|reject, review_count, message {ar,en}, tips [{ar,en}], preview_url, applied [str]}
//   POST …/scans          files[] (≤ 50 files, PNG / JPEG / WebP / PDF, ≤ 300 pages) → {batch_id, pages, duplicates, omr}
//   GET  …/omr/batches[/{batch_id}] → progress {total, done, graded, review, rejected, failed, pending, status, en, ar,
//        rejected_pages[{page_id, page_no, page_label, page_file_page?, file_name, codes, en, ar, instruction_en,
//        instruction_ar, result?}], pages?[{page_id, page_no, page_label, page_file_page?, file_name, status, result?}]}
//        page_label = the page's name in its batch (the server's sentences use it); page_no = the page inside its own
//        file (every photo is page 1 of itself); page_file_page = the page inside a multi-page PDF (final polish).
//   GET  …/omr/batches?limit=&before=      newest first; has_more + next_before (final polish; an older server ignores
//        both and returns up to 100)
//   POST …/omr/pages/{page_id}/replace   multipart image (JPG / PNG / WebP) → the capture gate on the request:
//        accepted {page_id (new), replaces, batch_id, en, ar, progress} | refused {code, en, ar, page_en, page_ar,
//        issues}; 409 page_not_rejected / page_duplicate / page_reviewed, 415, 413, 429, 503 omr_busy. Smart photos: a
//        page read in part (`result.tier: retake`) may be replaced too (the camera's Retake, the batch's preview)
//   GET / POST …/omr/sheets → what will be printed (+ `modes` on a server with print modes) / application/pdf
//        (body: forms?, copies, student_ids?, + mode / order / index only when the describe listed `modes`)
//   live: job_updated {kind: omr_scan, id: batch_id, exam_id, status, done, total, page_id, page_status, en, ar}
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Offset;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_time.dart';

import '../../../../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import '../../exam_engine_api.dart';
import '../exam_setup.dart' show identifierZoneMismatchText;
import '../omr_counts.dart';

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

/// The engine's naive UTC (`2026-11-02T05:29:37.03`) as a UTC instant; null when absent / unreadable.
DateTime? omrUtcOf(Object? v) {
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty || s == 'null') return null;
  final zoned = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(zoned ? s : '${s}Z')?.toUtc();
}

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
    this.blocking,
  });

  final bool ok;

  /// false = a gentle hint ("Add a little more light", "Hold steady"): the frame is readable enough, the hint only
  /// helps; null = an older server (only `ready` may capture).
  final bool? blocking;

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
        blocking: j['blocking'] is bool ? j['blocking'] as bool : null,
      );

  /// The server's own sentence in the current language.
  String get text => _pick(ar, en);

  /// A gentle hint: drawn softly, never a blocker.
  bool get gentle => blocking == false && code != 'ready';

  /// The server says this frame may be captured: `ready`, or a non-blocking hint about a frame it can read — never
  /// one that says the scene is still changing (no sheet, a corner out, moving, too far).
  bool get capturable => (ok && code == 'ready') || (blocking == false && !AutoCaptureGate.rearmCodes.contains(code));

  /// Capturable AND steadiness measured (a first frame without `prev` cannot be steady yet) AND the four marks found.
  bool get steady => capturable && motion != null && cornersFound >= 4;

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

/// The tone a hint is drawn in ([gentle]: a soft tip that never stops the capture).
enum OmrHintTone { neutral, warn, good, gentle }

OmrHintTone omrHintTone(String code, {bool? blocking}) => switch (code) {
      'ready' => OmrHintTone.good,
      _ when blocking == false => OmrHintTone.gentle,
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

// ── a page's result (smart photos) ──────────────────────────────────────────────────────────────────────────────

/// accept = graded, nothing to review · flags = graded, N questions to review · retake = read what it could, the rest
/// to review, and a better photo is suggested (never required) · reject = not graded.
enum OmrTier { accept, flags, retake, reject }

OmrTier? omrTierOf(Object? v) => switch ('${v ?? ''}') {
      'accept' => OmrTier.accept,
      'flags' => OmrTier.flags,
      'retake' => OmrTier.retake,
      'reject' => OmrTier.reject,
      _ => null,
    };

/// The steps the server ran on the photo, in plain words ("direct" = used as it was: nothing to say).
String? omrStepText(String step) => switch (step) {
      'resize' => t('تصغير', 'resized'),
      'shadow' => t('إزالة الظلال', 'shadows evened out'),
      'clahe' => t('تحسين التباين', 'contrast improved'),
      'sauvola' => t('توضيح الحبر', 'ink sharpened'),
      'perspective' => t('تقويم الورقة', 'page straightened'),
      'rotate' || 'rotation' => t('تدوير', 'rotated'),
      'deskew' => t('تقويم الميل', 'deskewed'),
      _ => null,
    };

/// Who the paper belongs to, as far as the reading knows: the student is known ([none] needed), a student is named or
/// proposed but a person confirms ([confirm]), or nobody is named and a person chooses ([choose]).
enum OmrStudentNeed { none, confirm, choose }

/// `result.student`: "identified" | "confirm" | "unidentified"; absent (an older server, a rejected page) = nothing to
/// say; any other value is treated like "unidentified".
OmrStudentNeed omrStudentNeedOf(Object? v) => switch (v) {
      null || 'identified' || '' => OmrStudentNeed.none,
      'confirm' => OmrStudentNeed.confirm,
      _ => OmrStudentNeed.choose,
    };

/// `result` of one OMR page: what the reading gave, in a sentence, with tips and the improved image.
///
/// Contract (round 3): `review_count` counts the QUESTIONS to review only, `student` says whether a person must
/// confirm / choose the student, `message` is one sentence with " — ". An older server counted the open identity
/// items in `review_count` (its `questions_to_review`, when sent, is the questions alone): when the count cannot be
/// trusted the title follows the server's own sentence instead of printing a second, different number.
class OmrPageResult {
  const OmrPageResult({
    required this.tier,
    this.reviewCount = 0,
    this.messageAr = '',
    this.messageEn = '',
    this.tips = const [],
    this.previewUrl,
    this.applied = const [],
    this.student = OmrStudentNeed.none,
    this.questionsOnly = true,
  });

  final OmrTier tier;

  /// The questions to review (`questions_to_review` when the server sends it, else `review_count`).
  final int reviewCount;
  final String messageAr, messageEn;

  /// Whether a person still has to confirm / choose the student (never on a rejected page).
  final OmrStudentNeed student;

  /// [reviewCount] counts questions only: the server said so (`questions_to_review`, `student: confirm`) or no
  /// identity item can be in it (the student is known). False = an older server may have added identity items.
  final bool questionsOnly;

  /// (ar, en) pairs.
  final List<(String, String)> tips;

  /// The access-logged page image with the improvement applied and the detected marks drawn (a signed path).
  final String? previewUrl;
  final List<String> applied;

  /// Null when [j] has no known tier (an older server, a malformed block): the screens keep their old look then.
  static OmrPageResult? fromJson(Object? j) {
    if (j is! Map) return null;
    final m = asMap(j);
    final tier = omrTierOf(m['tier']);
    if (tier == null) return null;
    final msg = asMap(m['message']);
    final url = '${m['preview_url'] ?? ''}'.trim();
    final need = tier == OmrTier.reject ? OmrStudentNeed.none : omrStudentNeedOf(m['student']);
    final q = m['questions_to_review'];
    return OmrPageResult(
      tier: tier,
      reviewCount: math.max(0, asInt(q ?? m['review_count'])),
      student: need,
      questionsOnly: q != null || need != OmrStudentNeed.choose,
      messageAr: '${msg['ar'] ?? (m['message'] is String ? m['message'] : '')}',
      messageEn: '${msg['en'] ?? (m['message'] is String ? m['message'] : '')}',
      tips: [
        for (final tip in (m['tips'] as List?) ?? const [])
          if (tip is Map && '${tip['ar'] ?? ''}${tip['en'] ?? ''}'.isNotEmpty) ('${tip['ar'] ?? ''}', '${tip['en'] ?? ''}')
          else if (tip is String && tip.isNotEmpty) (tip, tip),
      ],
      previewUrl: url.isEmpty ? null : url,
      applied: [for (final a in (m['applied'] as List?) ?? const []) '$a'],
    );
  }

  /// The `result` of a page map, or of its `page` object.
  static OmrPageResult? of(Map<String, dynamic> j) => fromJson(j['result']) ?? fromJson(asMap(j['page'])['result']);

  bool get graded => tier != OmrTier.reject;

  /// A better photo is suggested (retake, non-blocking) or needed (reject).
  bool get wantsRetake => tier == OmrTier.retake || tier == OmrTier.reject;

  /// The server's sentence in the current language (as sent; [detail] is what is drawn of it).
  String get message => _pick(messageAr, messageEn);

  /// The tips in the current language, each once: none that only repeats the title, the [detail] line or another tip.
  List<String> get tipTexts {
    final seen = <String>{omrTextKey(title), if (detail != null) omrTextKey(detail!), omrTextKey(message)};
    return [
      for (final (ar, en) in tips)
        if (_pick(ar, en).trim().isNotEmpty && seen.add(omrTextKey(_pick(ar, en)))) _pick(ar, en).trim(),
    ];
  }

  /// "Read successfully" · "Read with 3 questions to review" · "Read with 2 questions to review — confirm the student"
  /// · "Read in part — 5 questions to review" · "Couldn't read this paper". When an older server may have counted the
  /// student's check in the number, its own sentence is the title (never two different numbers on one card).
  String get title {
    final own = omrSentenceHead(message);
    final tail = omrSentenceTail(message);
    if (tier == OmrTier.retake) {
      // "Read in part — 1 question to review" + the server's own student / form part ("· confirm the student")
      final base = omrResultTitle(tier, questionsOnly ? reviewCount : 0);
      // one dash per title ("Read in part — 1 question to review · confirm the student"; the Arabic, a comma)
      if (tail != null) return '$base${base.contains(' — ') ? ' · ' : ' — '}$tail';
      return omrResultTitle(tier, questionsOnly ? reviewCount : 0, student: student);
    }
    // a read paper with a person's part (student, answer form, another exam's sheet), or a count an older server may
    // have inflated with the student's check: the server's one sentence, which its count and wording agree with
    if (tier != OmrTier.reject && own.isNotEmpty && (student != OmrStudentNeed.none || tail != null || !questionsOnly)) return own;
    if (!questionsOnly && tier != OmrTier.reject) return omrResultTitle(tier, 0, student: student);
    return omrResultTitle(tier, reviewCount, student: student);
  }

  /// The line under the title: what only the server's sentence says (a retake's or a rejection's reason). Null for a
  /// read paper (its sentence is the title again) and when it would repeat the title.
  String? get detail {
    final m = message.trim();
    if (m.isEmpty || tier == OmrTier.accept || tier == OmrTier.flags) return null;
    String d = m;
    if (tier == OmrTier.retake) {
      d = _after(m, const [', but ', '، لكن ', '، ولكن ']) ?? _after(m, const [' — ', ' - ']) ?? m;
      // "…outside the photo — confirm the student.": the person's part is in the title already
      final dash = d.indexOf(' — ');
      if (dash > 0) d = '${d.substring(0, dash)}.';
    } else if (tier == OmrTier.reject) {
      d = _after(m, const [': ']) ?? m;
    }
    d = _capital(d.trim());
    if (d.isEmpty || omrTextKey(omrResultTitle(tier, reviewCount, student: student)).contains(omrTextKey(d))) return null;
    if (omrTextKey(title).contains(omrTextKey(d))) return null;
    return d;
  }

  static String? _after(String s, List<String> seps) {
    for (final sep in seps) {
      final i = s.indexOf(sep);
      if (i > 0 && i + sep.length < s.length) return s.substring(i + sep.length);
    }
    return null;
  }

  static String _capital(String s) => s.isEmpty || AppConfig.lang == 'ar' ? s : s[0].toUpperCase() + s.substring(1);

  /// "Improved: shadows evened out · contrast improved" — empty when the photo was used as it was.
  String get appliedText {
    final steps = [for (final a in applied) ?omrStepText(a)];
    if (steps.isEmpty) return '';
    return t('حُسّنت الصورة: ${steps.join('، ')}', 'Improved: ${steps.join(' · ')}');
  }
}

String omrResultTitle(OmrTier tier, int review, {OmrStudentNeed student = OmrStudentNeed.none}) {
  final who = switch (student) {
    OmrStudentNeed.none => null,
    OmrStudentNeed.confirm => t('أكّد الطالب', 'confirm the student'),
    OmrStudentNeed.choose => t('اختر الطالب', 'choose the student'),
  };
  // the server's phrasing (mlkit/omr/messages.smart_message), so a batch never says one state two ways: "تمت القراءة،
  // وسؤالان للمراجعة" (the count in the nominative, countText's 1 / 2 / 3–10 / 11+ forms) / "Read with 2 questions to
  // review"; "Read — confirm the student" when only the student needs a person
  if (who != null && review == 0 && tier != OmrTier.retake && tier != OmrTier.reject) return t('تمت القراءة — $who', 'Read — $who');
  final base = switch (tier) {
    OmrTier.accept => t('تمت القراءة بنجاح', 'Read successfully'),
    OmrTier.flags => review > 0
        ? t('تمت القراءة، و${omrQuestionsText(review)} للمراجعة', 'Read with ${omrQuestionsText(review)} to review')
        : t('تمت القراءة، وبعض الأسئلة للمراجعة', 'Read with some questions to review'),
    OmrTier.retake => review > 0
        ? t('تمت القراءة جزئيًا، و${omrQuestionsText(review)} للمراجعة', 'Read in part — ${omrQuestionsText(review)} to review')
        : t('تمت القراءة جزئيًا', 'Read in part'),
    OmrTier.reject => t('تعذّرت قراءة الورقة', "Couldn't read this paper"),
  };
  if (who == null || tier == OmrTier.reject) return base;
  // one dash per title: the student's part after " · " when the title already has one
  return base.contains(' — ') ? '$base · $who' : '$base — $who';
}

/// A sentence compared by its letters and digits only (case, spaces, punctuation and Arabic marks ignored): two tips
/// that say the same thing are shown once.
String omrTextKey(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

/// The person's part of the server's sentence ("confirm the student", "confirm the answer form", "check this sheet"):
/// what follows its last " — " (" - " on an older server); null when it has none.
String? omrSentenceTail(String message) {
  final s = message.trim().replaceAll(' - ', ' — ');
  final i = s.lastIndexOf(' — ');
  if (i <= 0) return null;
  var tail = s.substring(i + 3).trim();
  final b = tail.lastIndexOf(' (');
  if (b > 0 && tail.endsWith(')')) tail = tail.substring(0, b);
  if (tail.endsWith('.')) tail = tail.substring(0, tail.length - 1);
  return tail.isEmpty ? null : tail;
}

/// The server's sentence as a title: " - " as a dash, the bracketed explanation left to the tips ("Read with 2
/// questions to review - confirm the student (its QR code …)" → "Read with 2 questions to review — confirm the
/// student"), and a retake's ", but …" reason left to the line under it.
String omrSentenceHead(String message) {
  var s = message.trim().replaceAll(' - ', ' — ');
  for (final sep in const [', but ', '، لكن ', '، ولكن ']) {
    final i = s.indexOf(sep);
    if (i > 0) s = s.substring(0, i);
  }
  final b = s.lastIndexOf(' (');
  if (b > 0 && s.endsWith(')')) s = s.substring(0, b);
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s.trim();
}

/// The non-blocking suggestion of a `retake` page.
String omrRetakeSuggestion() =>
    t('صورة أوضح تعطي قراءة كاملة — أعد التصوير إن أمكن، أو تابع', 'A clearer photo gives a full reading — retake it if you can, or carry on');

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
    this.result,
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

  /// What the reading gave (smart photos); null on an older server.
  final OmrPageResult? result;

  /// The scanner stops for this answer (nothing stored, or nothing graded): Retake is the way on.
  bool get blocks => !accepted || result?.tier == OmrTier.reject;

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
        result: OmrPageResult.of(j),
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
    this.pageFilePage,
    this.codes = const [],
    this.instructionEn = '',
    this.instructionAr = '',
    this.result,
  });

  final int pageId;
  final int pageNo;
  final String label;
  final String? fileName;

  /// The page inside a multi-page PDF uploaded with other files (null for a photo, and on an older server).
  final int? pageFilePage;
  final List<String> codes;

  /// "Page 7 is too blurry. Please upload a clearer image of it." (+ ar).
  final String en;
  final String ar;

  /// "Too blurry, hold steady." (+ ar).
  final String instructionEn;
  final String instructionAr;

  /// The reading's result (smart photos: the reason + tips + the improved image); null on an older server.
  final OmrPageResult? result;

  static OmrRejectedPage fromJson(Map<String, dynamic> j) => OmrRejectedPage(
        pageId: asInt(j['page_id']),
        pageNo: asInt(j['page_no'], 1),
        label: '${j['page_label'] ?? j['page_no'] ?? ''}',
        fileName: j['file_name']?.toString(),
        pageFilePage: j['page_file_page'] == null ? null : asInt(j['page_file_page']),
        codes: [for (final c in (j['codes'] as List?) ?? const []) '$c'],
        en: '${j['en'] ?? ''}',
        ar: '${j['ar'] ?? ''}',
        instructionEn: '${j['instruction_en'] ?? ''}',
        instructionAr: '${j['instruction_ar'] ?? ''}',
        result: OmrPageResult.of(j),
      );

  String get text => _pick(ar, en);
  String get instruction => _pick(instructionAr, instructionEn);
}

/// One page of a batch with its reading's result (`pages` of `GET …/omr/batches/{id}`, smart photos).
class OmrBatchPage {
  const OmrBatchPage({required this.pageId, required this.pageNo, required this.label, this.fileName, this.pageFilePage, this.status = '', this.result});

  final int pageId;

  /// The page inside its own file (every photo is page 1 of itself).
  final int pageNo;

  /// The page's name in its batch ("3": the server's sentences say "Page 3"); empty when the server sent none.
  final String label;
  final String? fileName;

  /// The page inside a multi-page PDF uploaded with other files (null for a photo, and on an older server).
  final int? pageFilePage;

  /// uploaded · processing · processed · review · rejected · failed · …
  final String status;
  final OmrPageResult? result;

  static OmrBatchPage fromJson(Map<String, dynamic> j) => OmrBatchPage(
        pageId: asInt(j['page_id'] ?? j['id']),
        pageNo: asInt(j['page_no'], 1),
        label: '${j['page_label'] ?? ''}',
        fileName: j['file_name']?.toString(),
        pageFilePage: j['page_file_page'] == null ? null : asInt(j['page_file_page']),
        status: '${j['status'] ?? ''}',
        result: OmrPageResult.of(j),
      );
}

/// `GET …/omr/batches?limit=&before=`: one page of the exam's batches, newest first.
class OmrBatchList {
  const OmrBatchList({required this.items, this.hasMore = false, this.nextBefore});
  final List<OmrBatchProgress> items;

  /// Older batches exist past this page; [nextBefore] is where the next page starts (the last batch id here when an
  /// older server forgot it). False on an older server (it returns up to 100 at once).
  final bool hasMore;
  final int? nextBefore;

  static OmrBatchList fromJson(Map<String, dynamic> j) {
    final items = [for (final b in asMapList(j['items'])) OmrBatchProgress.fromJson(b)];
    final more = j['has_more'] == true && items.isNotEmpty;
    final next = j['next_before'] == null ? null : asInt(j['next_before']);
    return OmrBatchList(items: items, hasMore: more, nextBefore: more ? (next ?? items.last.batchId) : null);
  }
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
    this.pages = const [],
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

  /// Every page with its result (smart photos); empty on an older server.
  final List<OmrBatchPage> pages;

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
        pages: [for (final p in asMapList(j['pages'])) OmrBatchPage.fromJson(p)],
      );

  bool get finished => status == 'done';
  String get text => _pick(ar, en);

  /// When the batch was started (the engine's naive UTC read as UTC); null when absent.
  DateTime? get createdUtc => omrUtcOf(createdAt);

  /// "Camera · Today, 10:42 AM" / "Upload · 2 Nov 2026 · 9:05 AM" (the platform / organization time zone, AppTime).
  String get whenText {
    final kindText = kind == 'camera' ? t('تصوير', 'Camera') : t('رفع', 'Upload');
    final at = createdUtc;
    if (at == null) return kindText;
    final day = AppTime.toZone(at), now = AppTime.toZone(DateTime.now().toUtc());
    final today = day.year == now.year && day.month == now.month && day.day == now.day;
    return '$kindText · ${today ? t('اليوم، ${AppTime.time(at)}', 'Today, ${AppTime.time(at)}') : AppTime.dateTime(at)}';
  }

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
        pages: pages,
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
    this.modes,
    this.prefilledReasonAr = '',
    this.prefilledReasonEn = '',
    this.blankReason = '',
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

  /// The print modes this exam offers (prefilled · named · blank, in that order); null = an older server that knows
  /// no modes (blank sheets or named sheets, and the body carries no mode / order / index).
  final List<OmrPrintMode>? modes;

  /// Why Pre-filled is not offered, when the server says so.
  final String prefilledReasonAr, prefilledReasonEn;

  /// `mode_detail.blank.reason` (D-161: `identifier_zone_mismatch` — the students' numbers do not fit the ID zone,
  /// so only sheets that identify each student by name / QR print); empty when blank is offered or not said.
  final String blankReason;

  /// Why [m] is not offered, in one line (the server's reason code in words); null when it is offered, or on an
  /// older server without modes. An unavailable mode is shown disabled with this line, never hidden silently.
  String? missingText(OmrPrintMode m) {
    final list = modes;
    if (list == null || list.contains(m)) return null;
    return switch (m) {
      OmrPrintMode.prefilled => prefilledMissing,
      OmrPrintMode.blank => blankReason == 'identifier_zone_mismatch' || blankReason == 'too_long'
          ? t('الأوراق الفارغة غير متاحة: أرقام الطلاب لا تتسع في خانات الورقة، فتُطبع الأوراق باسم كل طالب ويعرّفه رمز QR',
              "Blank sheets are not available: the students' numbers do not fit the sheet's boxes, so each sheet is printed for a named student and its QR code identifies them")
          : t('الأوراق الفارغة غير متاحة لهذا الاختبار', 'Blank sheets are not available for this exam'),
      OmrPrintMode.named => t('الأوراق بالاسم غير متاحة لهذا الاختبار', 'Named sheets are not available for this exam'),
    };
  }

  bool get hasModes => modes != null;

  /// One line on why Pre-filled is missing (the server's words, else the likely reason from the sheet's ID kind);
  /// null when it is offered or the server has no modes.
  String? get prefilledMissing {
    final m = modes;
    if (m == null || m.contains(OmrPrintMode.prefilled)) return null;
    final own = _pick(prefilledReasonAr, prefilledReasonEn);
    if (own.isNotEmpty) return own;
    if (idKind != 'shaded') {
      return t('التظليل المسبق غير متاح: لا توجد على الورقة خانات تظليل لرقم الطالب', 'Pre-filled is not available: the sheet has no student-number bubbles');
    }
    return t('التظليل المسبق غير متاح: أرقام الطلاب ليست أرقامًا فقط أو أطول من خانات الورقة',
        "Pre-filled is not available: the student numbers are not all digits or do not fit the sheet's boxes");
  }

  static OmrSheetsInfo fromJson(Map<String, dynamic> j) => OmrSheetsInfo(
        templateId: j['template_id'] == null ? null : asInt(j['template_id']),
        printable: j['printable'] == true,
        questions: asInt(j['questions']),
        sheetQuestions: asInt(j['sheet_questions']),
        forms: [for (final f in (j['forms'] as List?) ?? const []) '$f'],
        sheetForms: [for (final f in (j['sheet_forms'] as List?) ?? const []) '$f'],
        formMarkers: [for (final f in (j['form_markers'] as List?) ?? const []) '$f'],
        idKind: '${j['id_kind'] ?? ''}',
        modes: omrPrintModesOf(j['modes']),
        prefilledReasonAr: _reasonOf(j, 'ar'),
        prefilledReasonEn: _reasonOf(j, 'en'),
        blankReason: '${asMap(asMap(j['mode_detail'])['blank'])['reason'] ?? ''}',
      );

  static const _prefilledReasons = <String, (String, String)>{
    'zone_not_shaded': ('التظليل المسبق غير متاح: لا توجد على الورقة خانات تظليل لرقم الطالب',
        'Pre-filled is not available: the sheet has no student-number bubbles'),
    'no_identifier': ('التظليل المسبق غير متاح: الاختبار لا يعرّف الطلاب برقم', 'Pre-filled is not available: this exam does not identify students by a number'),
    'identifier_unknown': ('التظليل المسبق غير متاح الآن: تعذّر التحقق من أرقام الطلاب، حاول لاحقًا',
        "Pre-filled is not available right now: the students' numbers could not be checked, try again later"),
    'identifier_zone_mismatch': ('التظليل المسبق غير متاح: أرقام الطلاب لا تتسع في خانات الورقة',
        "Pre-filled is not available: the student numbers do not fit the sheet's boxes"),
    'too_long': ('التظليل المسبق غير متاح: أرقام الطلاب أطول من خانات الورقة', "Pre-filled is not available: the student numbers are longer than the sheet's boxes"),
    'not_digits': ('التظليل المسبق غير متاح: بعض أرقام الطلاب ليست أرقامًا فقط', 'Pre-filled is not available: some student numbers are not all digits'),
  };

  /// The server's `mode_detail.prefilled.reason` code (omr_sheets.modes_of), else `prefilled_reason {ar, en}`, or the
  /// reason of a `{mode: prefilled, available: false, reason}` entry of `modes`. An unknown code falls back to the
  /// reason worked out from the ID kind (`prefilledMissing`).
  static String _reasonOf(Map<String, dynamic> j, String lang) {
    final code = '${asMap(asMap(j['mode_detail'])['prefilled'])['reason'] ?? ''}';
    final known = _prefilledReasons[code];
    if (known != null) return lang == 'ar' ? known.$1 : known.$2;
    final direct = asMap(j['prefilled_reason']);
    if (direct.isNotEmpty) return '${direct[lang] ?? ''}';
    for (final m in asMapList(j['modes'])) {
      if ('${m['mode'] ?? m['id'] ?? ''}' == 'prefilled') {
        final r = m['reason'];
        if (r is Map) return '${r[lang] ?? ''}';
        return '${m['reason_$lang'] ?? ''}';
      }
    }
    return '';
  }
}

/// prefilled = name + masked ID printed, the ID bubbles shaded · named = name + masked ID printed, bubbles empty ·
/// blank = no name, no ID.
enum OmrPrintMode { prefilled, named, blank }

/// The modes `describe` lists: strings, or `{mode, available?}` maps (an unavailable one is left out); unknown
/// names are skipped. Null when the server sent no `modes` (an older server).
List<OmrPrintMode>? omrPrintModesOf(Object? v) {
  if (v is! List) return null;
  final got = <OmrPrintMode>{};
  for (final e in v) {
    final name = e is Map ? '${e['mode'] ?? e['id'] ?? ''}' : '$e';
    if (e is Map && e['available'] == false) continue;
    for (final m in OmrPrintMode.values) {
      if (m.name == name) got.add(m);
    }
  }
  return [for (final m in OmrPrintMode.values) if (got.contains(m)) m];
}

/// The print order of the student sheets (the server sorts).
enum OmrPrintOrder { name, identifier }

/// The POST body of `…/omr/sheets`: blank sheets per form × copies, or one sheet per student (forms cycle). The
/// student ids go in the order they were chosen: the server sorts ([order]). [mode] / [order] / [index] are sent
/// only to a server that listed modes (an older one refuses unknown fields): null [mode] = the old body.
Map<String, dynamic> omrSheetsBody({
  List<String> forms = const [],
  int copies = 1,
  List<int> studentIds = const [],
  OmrPrintMode? mode,
  OmrPrintOrder order = OmrPrintOrder.name,
  bool index = true,
}) {
  final students = mode != OmrPrintMode.blank && studentIds.isNotEmpty;
  return {
    if (forms.isNotEmpty) 'forms': forms,
    if (!students) 'copies': copies.clamp(1, OmrLimits.maxCopies),
    if (students) 'student_ids': studentIds,
    if (mode != null) 'mode': mode.name,
    if (mode != null && students) 'order': order.name,
    if (mode != null && students) 'index': index,
  };
}

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
    this.result,
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

  /// The new image's result (smart photos); null on an older server.
  final OmrPageResult? result;

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
      result: OmrPageResult.of(j),
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
      'feature_disabled' => t('التصحيح التلقائي متوقف حالياً من إدارة المنصة', 'Automatic correction is switched off by the platform right now'),   // D-301
      'exam_not_bubble' => t('هذا الاختبار ليس بورقة تظليل — اختر ورقة التظليل وقالبًا منشورًا في إعداد الاختبار',
          'This exam does not use a bubble sheet — choose the bubble sheet and a published template in the exam setup'),
      'template_not_found' => t('قالب ورقة التظليل غير موجود — اختر قالبًا في إعداد الاختبار', 'The exam\'s sheet template is missing — choose one in the exam setup'),
      'template_too_small' => t('القالب فيه ${_questionsAr(detail['template_questions'])} والاختبار فيه ${_questionsAr(detail['questions'])}',
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
      'bad_pdf' => t('ملف PDF غير صالح أو محمي بكلمة مرور', 'The PDF is damaged or protected by a password'),
      'page_too_large' => t('صفحة في ملف PDF أكبر من المسموح', 'A page of the PDF is larger than allowed'),
      'grading_busy' || 'omr_busy' => t('الخادم مشغول الآن — أعد المحاولة بعد لحظة', 'The server is busy — try again in a moment'),
      'too_many_requests' => t('طلبات كثيرة في وقت قصير — انتظر قليلًا', 'Too many requests — wait a moment'),
      'batch_not_found' => t('جلسة التصوير غير موجودة — ابدأ جلسة جديدة', 'This capture session was not found — start a new one'),
      'frame_too_large' => t('الإطار أكبر من المسموح', 'The frame is too large'),
      'expected_invalid' => t('عدد الأوراق المتوقع بين 1 و ${OmrLimits.maxExpected}', 'The expected number of papers is 1 to ${OmrLimits.maxExpected}'),
      'forbidden' => t('ليس لديك صلاحية إدارة هذا الاختبار', 'You cannot manage this exam'),
      'no_files' => t('أرفق صورة أو ملف PDF', 'Attach an image or a PDF'),
      'page_not_rejected' => t('يمكن استبدال الصفحات المرفوضة فقط', 'Only a rejected page can be replaced'),
      'page_reviewed' => t('راجعت هذه الورقة من قبل — لن تُستبدل', 'You already reviewed this paper — it is not replaced'),
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

  /// [batchId]: the next part of an upload sent in parts (scan_files.dart) — its pages join that batch.
  Future<EngineResult> upload(int examId, List<(String, Uint8List)> files, {int? batchId}) =>
      engineCall(() => _api.postFiles('$_b/exams/$examId/scans', files: files, fields: {'batch_id': ?batchId}));

  /// The exam's scan issues (or one batch's): unreadable pages, duplicates, identifier / form review items.
  Future<EngineResult> issues(int examId, {int? batchId}) =>
      engineCall(() => _api.get('$_b/exams/$examId/omr/issues', queryParams: batchId == null ? null : {'batch_id': batchId}));

  Future<EngineResult> batch(int examId, int batchId) => engineCall(() => _api.get('$_b/exams/$examId/omr/batches/$batchId'));

  /// The exam's batches, newest first: [limit] at a time, [before] = a batch id (only older ones). An older server
  /// ignores both and returns up to 100 (no `has_more`: [OmrBatchList.hasMore] false).
  Future<EngineResult> batches(int examId, {int? limit, int? before}) => engineCall(() => _api.get('$_b/exams/$examId/omr/batches',
      queryParams: (limit == null && before == null) ? null : {'limit': ?limit, 'before': ?before}));

  /// A better image for a REJECTED page (multipart `image`): the gate answers on the request ([OmrReplaceResult]).
  Future<EngineResult> replacePage(int examId, int pageId, (String, Uint8List) file) =>
      engineCall(() => _api.postFiles('$_b/exams/$examId/omr/pages/$pageId/replace', files: [file], field: 'image'));

  /// One page's state (`GET …/omr/pages/{id}` → `page.status`): how a replacement ended.
  Future<EngineResult> page(int examId, int pageId) => engineCall(() => _api.get('$_b/exams/$examId/omr/pages/$pageId'));

  Future<EngineResult> sheetsInfo(int examId) => engineCall(() => _api.get('$_b/exams/$examId/omr/sheets'));

  /// A signed page / crop / preview image (a result's `preview_url`); null when it cannot be read.
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

/// "50 سؤالًا" for a server value that should be a number.
String _questionsAr(Object? v) => v is int ? omrQuestionsText(v) : '${v ?? '?'} سؤالًا';
