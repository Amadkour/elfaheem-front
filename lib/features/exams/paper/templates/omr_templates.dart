// Bubble-sheet types (OMR templates, D-155) — the pure part: the library rows, the learning job's step-through reply,
// the shading description sent with the scans, the sheet geometry (millimetres ↔ preview pixels), server codes as
// text, and the engine calls. No widget here; omr_template_library.dart and omr_template_learn.dart draw it.
//
// Coordinates (back mlkit/omr/spec.py): every box is in MILLIMETRES of a canonical page (origin top-left, x right,
// y down) anchored on the four corner marks, so the photo's framing never matters. The step-through previews are
// that canonical page warped at `ppm` px / mm (exam_engine/services/omr_templates.py, PREVIEW_PPM = 4; A4 = 840 ×
// 1188). OpenCV's warp (WARP_INVERSE_MAP) samples a canonical point (x, y) mm at the pixel INDEX (x·ppm, y·ppm), and
// pixel index i is the centre of the square [i, i + 1) when Flutter paints the image at its natural size, so a point
// lands at x·ppm + 0.5 in the painted preview (`SheetGeometry`). Radii and lengths have no offset. The server's own
// `px` field (mm × ppm, rounded to 0.1) is the index without that half pixel.
library;

import 'dart:convert' show jsonEncode;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:flutter/widgets.dart' show Matrix4;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:http_parser/http_parser.dart' show MediaType;

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, asMapList, t;
import 'package:flutter_education_app/features/exams/exam_authoring.dart' show parseEngineUtc;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult, engineCall;
import 'package:flutter_education_app/features/exams/paper/omr_counts.dart';

/// The kill switch of every bubble-sheet part (feature catalog `exam.omr`).
const kOmrFeatureKey = 'exam.omr';

/// The server's limits for a bubble radius (services/omr_templates.py `_bubbles`).
const kBubbleMinR = 0.5;
const kBubbleMaxR = 10.0;

double _d(dynamic v, [double d = 0]) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? d);
double _round3(double v) => (v * 1000).roundToDouble() / 1000;
String? _s(dynamic v) => v == null || '$v'.trim().isEmpty ? null : '$v';
List<String> _strs(dynamic v) => [for (final x in (v is List ? v : const [])) '$x'];

// ── geometry ───────────────────────────────────────────────────────────────────────────────────────────────────

/// One printed circle (millimetres).
class OmrBubble {
  const OmrBubble({required this.label, required this.cx, required this.cy, required this.r});
  final String label;
  final double cx;
  final double cy;
  final double r;

  static OmrBubble fromJson(Map<String, dynamic> j) => OmrBubble(label: '${j['label'] ?? ''}', cx: _d(j['cx']), cy: _d(j['cy']), r: _d(j['r']));

  /// What PUT …/boxes takes: label + centre + radius in mm, rounded like the server stores them.
  Map<String, dynamic> toJson() => {'label': label, 'cx': _round3(cx), 'cy': _round3(cy), 'r': _round3(r)};

  OmrBubble copyWith({double? cx, double? cy, double? r}) => OmrBubble(label: label, cx: cx ?? this.cx, cy: cy ?? this.cy, r: r ?? this.r);

  bool sameAs(OmrBubble o) => label == o.label && (cx - o.cx).abs() < 5e-4 && (cy - o.cy).abs() < 5e-4 && (r - o.r).abs() < 5e-4;

  @override
  String toString() => '$label(${cx.toStringAsFixed(3)}, ${cy.toStringAsFixed(3)}, r ${r.toStringAsFixed(3)})';
}

/// A rectangle in millimetres (a handwritten digit box, a code zone).
class OmrBoxMm {
  const OmrBoxMm(this.x, this.y, this.w, this.h);
  final double x, y, w, h;

  static OmrBoxMm? fromJson(dynamic v) {
    if (v is List && v.length >= 4) return OmrBoxMm(_d(v[0]), _d(v[1]), _d(v[2]), _d(v[3]));
    if (v is! Map) return null;
    final j = asMap(v);
    if (j['x'] == null) return null;
    return OmrBoxMm(_d(j['x']), _d(j['y']), _d(j['w']), _d(j['h']));
  }

  Rect get rect => Rect.fromLTWH(x, y, w, h);
}

/// True when every bubble of [a] equals the one with the same index in [b].
bool sameBubbles(List<OmrBubble> a, List<OmrBubble> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!a[i].sameAs(b[i])) return false;
  }
  return true;
}

/// The canonical page as painted: the preview is [width] × [height] px at [ppm] px per mm.
class SheetGeometry {
  const SheetGeometry({required this.ppm, required this.width, required this.height});

  /// The pixel-centre convention (see the file header): a canonical point x mm is painted at x · ppm + 0.5.
  static const pixelCentre = 0.5;

  final double ppm;
  final double width;
  final double height;

  Size get size => Size(width, height);

  /// The page in mm.
  double get pageWmm => width / ppm;
  double get pageHmm => height / ppm;

  /// A point (mm) → the painted preview (px).
  Offset toPreview(double xMm, double yMm) => Offset(xMm * ppm + pixelCentre, yMm * ppm + pixelCentre);

  /// A painted preview point (px) → mm. The exact inverse of [toPreview].
  Offset toMm(Offset p) => Offset((p.dx - pixelCentre) / ppm, (p.dy - pixelCentre) / ppm);

  double lenToPreview(double mm) => mm * ppm;
  double lenToMm(double px) => px / ppm;

  Offset centreOf(OmrBubble b) => toPreview(b.cx, b.cy);

  /// A bubble's circle as a square in preview px.
  Rect bubbleRect(OmrBubble b) => Rect.fromCircle(center: centreOf(b), radius: lenToPreview(b.r));

  /// A mm rectangle → preview px.
  Rect rectToPreview(Rect mm) => Rect.fromPoints(toPreview(mm.left, mm.top), toPreview(mm.right, mm.bottom));

  /// The bubbles' union (preview px), grown by [padMm].
  Rect? unionRect(Iterable<OmrBubble> bubbles, {double padMm = 1.5}) {
    Rect? u;
    for (final b in bubbles) {
      final r = bubbleRect(b);
      u = u == null ? r : u.expandToInclude(r);
    }
    return u?.inflate(lenToPreview(padMm));
  }

  /// The scale that shows the whole page inside [viewport].
  double fitScale(Size viewport) {
    if (viewport.width <= 0 || viewport.height <= 0) return 1;
    return math.min(viewport.width / width, viewport.height / height);
  }

  /// The InteractiveViewer transform that centres [rect] (preview px) in [viewport], so it fills about [fill] of the
  /// narrower side; never smaller than the fit scale, never above [maxScale].
  Matrix4 focusOn(Rect rect, Size viewport, {double fill = 0.62, double maxScale = 5}) {
    final fit = fitScale(viewport);
    final want = math.min(viewport.width * fill / math.max(rect.width, 1), viewport.height * fill / math.max(rect.height, 1));
    final s = want.clamp(fit, math.max(fit, maxScale)).toDouble();
    final dx = viewport.width / 2 - rect.center.dx * s;
    final dy = viewport.height / 2 - rect.center.dy * s;
    return Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(s, s, s, 1);
  }

  /// The whole page, centred.
  Matrix4 fit(Size viewport) {
    final s = fitScale(viewport);
    return Matrix4.identity()
      ..translateByDouble((viewport.width - width * s) / 2, (viewport.height - height * s) / 2, 0, 1)
      ..scaleByDouble(s, s, s, 1);
  }

  /// [b] moved so its centre sits [deltaPx] (preview px) away from [start]'s, kept on the page.
  OmrBubble moved(OmrBubble start, Offset deltaPx) {
    final cx = (start.cx + deltaPx.dx / ppm).clamp(0.0, pageWmm).toDouble();
    final cy = (start.cy + deltaPx.dy / ppm).clamp(0.0, pageHmm).toDouble();
    return start.copyWith(cx: cx, cy: cy);
  }

  /// Every bubble of [start] moved by the same [deltaPx].
  List<OmrBubble> movedAll(List<OmrBubble> start, Offset deltaPx) => [for (final b in start) moved(b, deltaPx)];

  /// [b] with its radius set so the circle passes through [pointerPx] (preview px), within the server's limits.
  OmrBubble resizedTo(OmrBubble b, Offset pointerPx) {
    final r = lenToMm((pointerPx - centreOf(b)).distance).clamp(kBubbleMinR, kBubbleMaxR).toDouble();
    return b.copyWith(r: r);
  }
}

/// A bubble nudged by [dxMm] / [dyMm] (arrow keys), kept on the page.
OmrBubble nudged(OmrBubble b, double dxMm, double dyMm, SheetGeometry g) =>
    b.copyWith(cx: (b.cx + dxMm).clamp(0.0, g.pageWmm).toDouble(), cy: (b.cy + dyMm).clamp(0.0, g.pageHmm).toDouble());

// ── library rows ───────────────────────────────────────────────────────────────────────────────────────────────

/// One template version as `GET /omr/templates` lists it (services/omr_templates.py `library_dict`).
class OmrTemplateRow {
  const OmrTemplateRow({
    required this.id,
    required this.familyId,
    required this.version,
    required this.name,
    this.nameAr,
    this.nameEn,
    this.description,
    required this.status,
    this.ownerId = 0,
    this.ownerRole = '',
    this.questions = 0,
    this.options,
    this.optionLabels = const [],
    this.idKind,
    this.idDigits,
    this.formsOnSheet = const [],
    this.builtin,
    this.printable = false,
    this.learningState,
    this.previewUrl,
    this.validationOk,
    this.reviewNote,
    this.approvedAt,
    this.createdAt,
  });

  final int id;
  final String familyId;
  final int version;
  final String name;
  final String? nameAr;
  final String? nameEn;
  final String? description;

  /// draft · pending_approval · published · rejected · retired
  final String status;
  final int ownerId;
  final String ownerRole;
  final int questions;
  final int? options;
  final List<String> optionLabels;

  /// shaded · handwritten · printed · qr · none
  final String? idKind;
  final int? idDigits;
  final List<String> formsOnSheet;
  final String? builtin;
  final bool printable;

  /// queued · running · done · failed · recalibrating
  final String? learningState;
  final String? previewUrl;
  final bool? validationOk;
  final String? reviewNote;
  final DateTime? approvedAt;
  final DateTime? createdAt;

  static OmrTemplateRow fromJson(Map<String, dynamic> j) => OmrTemplateRow(
        id: asInt(j['id']),
        familyId: '${j['family_id'] ?? j['id']}',
        version: asInt(j['version'], 1),
        name: '${j['name'] ?? ''}',
        nameAr: _s(j['name_ar']),
        nameEn: _s(j['name_en']),
        description: _s(j['description']),
        status: '${j['status'] ?? 'draft'}',
        ownerId: asInt(j['owner_id']),
        ownerRole: '${j['owner_role'] ?? ''}',
        questions: asInt(j['questions']),
        options: j['options'] is num ? (j['options'] as num).toInt() : null,
        optionLabels: _strs(j['option_labels']),
        idKind: _s(j['id_kind']),
        idDigits: j['id_digits'] is num ? (j['id_digits'] as num).toInt() : null,
        formsOnSheet: _strs(j['forms_on_sheet']),
        builtin: _s(j['builtin']),
        printable: j['printable'] == true,
        learningState: _s(j['learning_state']),
        previewUrl: _s(j['preview_url']),
        validationOk: j['validation_ok'] is bool ? j['validation_ok'] as bool : null,
        reviewNote: _s(j['review_note']),
        approvedAt: parseEngineUtc(j['approved_at']),
        createdAt: parseEngineUtc(j['created_at']),
      );

  /// The built-in sheets carry both names; a learned one has the name its author typed.
  String get displayName => (AppConfig.lang == 'ar' ? nameAr : nameEn) ?? name;

  bool get isBuiltin => builtin != null;
  bool get published => status == 'published';
  bool get pending => status == 'pending_approval';

  /// Editable in place (draft / rejected; the server refuses the rest with template_not_editable).
  bool get editable => status == 'draft' || status == 'rejected';

  /// A new version can be made of it (published / retired).
  bool get versionable => status == 'published' || status == 'retired';

  bool get learning => learningState == 'queued' || learningState == 'running';

  /// "50 questions × 4 options (A–D)".
  String get shape {
    final o = options;
    final labels = optionLabels.isNotEmpty ? '${optionLabels.first}–${optionLabels.last}' : null;
    if (questions == 0 && o == null) return t('لم يكتمل التعلّم بعد', 'Not learned yet');
    final q = omrQuestionsText(questions);
    if (o == null) return q;
    return t('$q × ${omrOptionsText(o)}${labels == null ? '' : ' ($labels)'}', '$q × $o options${labels == null ? '' : ' ($labels)'}');
  }

  /// "Shaded ID · 10 digits".
  String get idLine {
    final k = omrIdKindLabel(idKind);
    final d = idDigits;
    if (idKind == null || idKind == 'none' || d == null || d == 0) return k;
    return t('$k · ${omrDigitsText(d)}', '$k · $d digits');
  }
}

/// A template family (every version of one layout), newest version first.
class OmrTemplateFamily {
  OmrTemplateFamily(this.familyId, List<OmrTemplateRow> versions) : versions = [...versions]..sort((a, b) => b.version.compareTo(a.version));
  final String familyId;
  final List<OmrTemplateRow> versions;

  OmrTemplateRow get latest => versions.first;

  /// What the family "is" today: its published version, else the newest one.
  OmrTemplateRow get current => versions.firstWhere((v) => v.published, orElse: () => latest);

  bool get hasPending => versions.any((v) => v.pending);
  bool get isBuiltin => versions.any((v) => v.isBuiltin);

  /// The newest version number (a new version gets this + 1).
  int get topVersion => versions.map((v) => v.version).reduce(math.max);
}

/// Groups the rows by family: families with a pending version first, then built-ins, then by name.
List<OmrTemplateFamily> groupFamilies(List<OmrTemplateRow> rows) {
  final by = <String, List<OmrTemplateRow>>{};
  for (final r in rows) {
    by.putIfAbsent(r.familyId, () => []).add(r);
  }
  final out = [for (final e in by.entries) OmrTemplateFamily(e.key, e.value)];
  int rank(OmrTemplateFamily f) => f.hasPending ? 0 : (f.isBuiltin ? 1 : 2);
  out.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : a.current.displayName.toLowerCase().compareTo(b.current.displayName.toLowerCase());
  });
  return out;
}

/// The library filter (at most one).
enum LibraryFilter { all, pending, published, drafts, rejected, retired }

bool libraryFilterMatches(LibraryFilter f, OmrTemplateFamily fam) => switch (f) {
      LibraryFilter.all => true,
      LibraryFilter.pending => fam.versions.any((v) => v.pending),
      LibraryFilter.published => fam.versions.any((v) => v.published),
      LibraryFilter.drafts => fam.versions.any((v) => v.status == 'draft'),
      LibraryFilter.rejected => fam.versions.any((v) => v.status == 'rejected'),
      LibraryFilter.retired => fam.versions.any((v) => v.status == 'retired'),
    };

String libraryFilterLabel(LibraryFilter f) => switch (f) {
      LibraryFilter.all => t('الكل', 'All'),
      LibraryFilter.pending => t('بانتظار الاعتماد', 'Pending approval'),
      LibraryFilter.published => t('منشور', 'Published'),
      LibraryFilter.drafts => t('مسودات', 'Drafts'),
      LibraryFilter.rejected => t('مرفوض', 'Rejected'),
      LibraryFilter.retired => t('متوقف', 'Retired'),
    };

String omrStatusLabel(String status) => switch (status) {
      'draft' => t('مسودة', 'Draft'),
      'pending_approval' => t('بانتظار الاعتماد', 'Pending approval'),
      'published' => t('منشور', 'Published'),
      'rejected' => t('مرفوض', 'Rejected'),
      'retired' => t('متوقف', 'Retired'),
      _ => status,
    };

String omrIdKindLabel(String? kind) => switch (kind) {
      'shaded' => t('رقم طالب بالتظليل', 'Shaded student ID'),
      'handwritten' => t('رقم طالب بخط اليد', 'Handwritten student ID'),
      'printed' => t('رمز مطبوع', 'Printed code'),
      'qr' => t('رمز QR', 'QR code'),
      'none' || null => t('بلا رقم طالب', 'No student ID'),
      _ => kind,
    };

// ── the step-through (GET /omr/templates/{tid}/steps) ──────────────────────────────────────────────────────────

/// A warning or a validation error: the server's sentence in both languages + the codes it names.
class OmrIssue {
  const OmrIssue({required this.code, this.en, this.ar, this.numbers = const [], this.where = const {}});
  final String code;
  final String? en;
  final String? ar;

  /// questions_unconfirmed: the question numbers.
  final List<int> numbers;
  final Map<String, dynamic> where;

  static OmrIssue fromJson(Map<String, dynamic> j) => OmrIssue(
        code: '${j['code'] ?? ''}',
        en: _s(j['en']),
        ar: _s(j['ar']),
        numbers: [for (final x in (j['numbers'] is List ? j['numbers'] as List : const [])) asInt(x)],
        where: asMap(j['where']),
      );

  String get text => (AppConfig.lang == 'ar' ? ar : en) ?? en ?? ar ?? code;

  /// The question this names, when it names one.
  int? get question => where['n'] is num ? (where['n'] as num).toInt() : null;

  /// What to do about it (null when the sentence already says it).
  String? get fix => omrIssueFix(code);
}

/// The fix for a learning warning / validation code (mlkit/omr/learn.py `warn(...)`, `validate_spec`, and the engine's
/// learning_not_done / not_calibrated / questions_unconfirmed).
String? omrIssueFix(String code) => switch (code) {
      'marks_missing' || 'marks' => t('ارفع صورة تظهر فيها علامات الأركان الأربع كاملة، مستقيمة ومن غير قص.',
          'Upload a straight scan where all four corner marks are fully visible (nothing cut off).'),
      'preview_unavailable' => t('صوّر الورقة الفارغة من الأعلى في إضاءة جيدة ثم ارفعها مرة أخرى.',
          'Photograph the blank sheet from straight above in good light, then upload it again.'),
      'unassigned' => t('غالبًا دوائر زخرفية أو تعليمات؛ لا يلزم شيء إن كانت كل الأسئلة صحيحة.',
          'Usually decorative circles or instructions: nothing to do if every question is right.'),
      'questions_short' || 'question_count' || 'no_questions' => t(
          'تأكد من عدد الأسئلة في الوصف، ومن أن الصورة تُظهر كل الأعمدة.', 'Check the number of questions in the description and that the scan shows every column.'),
      'questions_extra' => t('إن كان في الورقة أسئلة أكثر فعدّل عدد الأسئلة في الوصف.', 'If the sheet really has more questions, change the number in the description.'),
      'per_column' => t('راجع «أسئلة في كل عمود» في الوصف.', 'Check "questions per column" in the description.'),
      'interpolated' => t('راجع موضع هذه الفقاعات في خطوات المراجعة واسحبها إن لزم.', 'Check those bubbles in the step-through and drag them if needed.'),
      'sample_unreadable' => t('ارفع صورة أوضح للنموذج المظلّل، أو تابع بلا نموذج وراجع كل سؤال بعينك.',
          'Upload a clearer filled sample, or go on without it and check each question by eye.'),
      'sample_question' => t('افتح هذا السؤال في المراجعة وصحّح مربعاته.', 'Open this question in the step-through and fix its boxes.'),
      'sample_id' || 'id_columns' || 'id_digits' => t('راجع منطقة رقم الطالب وعدد أعمدتها في الوصف.', 'Check the student ID zone and its number of columns in the description.'),
      'id_boxes' || 'id_zone' => t('تأكد أن مربعات رقم الطالب ظاهرة كاملة في الصورة.', 'Make sure the student ID boxes are fully visible in the scan.'),
      'overlap' || 'spacing' || 'row_spacing' || 'outside' || 'on_mark' => t('اسحب الفقاعات المتداخلة إلى أماكنها في خطوات المراجعة.',
          'Drag the overlapping bubbles back into place in the step-through.'),
      'bubble_count' || 'labels' || 'numbering' => t('راجع عدد الاختيارات وترتيبها في الوصف.', 'Check the number and order of options in the description.'),
      'form_markers' || 'form_bubbles' || 'form_zone' => t('إن لم تكن في الورقة نماذج A/B فاترك حروف النماذج فارغة في الوصف.',
          'If the sheet has no A / B models, leave the model letters empty in the description.'),
      'learning_not_done' => t('انتظر حتى ينتهي التعلّم.', 'Wait for learning to finish.'),
      'not_calibrated' => t('نعيد قياس المربعات المعدّلة — لحظات.', 'The corrected boxes are being measured — a few seconds.'),
      'questions_unconfirmed' => t('افتح الأسئلة غير المؤكدة وأكّد كل واحد منها.', 'Open the unconfirmed questions and confirm each one.'),
      _ => null,
    };

class TemplateValidation {
  const TemplateValidation({this.ok = false, this.errors = const [], this.warnings = const []});
  final bool ok;
  final List<OmrIssue> errors;
  final List<OmrIssue> warnings;

  static TemplateValidation fromJson(dynamic v) {
    final j = asMap(v);
    return TemplateValidation(
      ok: j['ok'] == true,
      errors: [for (final e in asMapList(j['errors'])) OmrIssue.fromJson(e)],
      warnings: [for (final e in asMapList(j['warnings'])) OmrIssue.fromJson(e)],
    );
  }
}

class StepQuestion {
  const StepQuestion({required this.n, this.block = 0, required this.bubbles, this.filled = const [], this.state, this.en, this.ar, this.confirmed = false, this.problems = const []});
  final int n;
  final int block;
  final List<OmrBubble> bubbles;

  /// What the filled sample showed (labels).
  final List<String> filled;

  /// clear · blank · multiple · uncertain (on the filled sample), null without a sample.
  final String? state;
  final String? en;
  final String? ar;
  final bool confirmed;
  final List<OmrIssue> problems;

  static StepQuestion fromJson(Map<String, dynamic> j) => StepQuestion(
        n: asInt(j['n']),
        block: asInt(j['block']),
        bubbles: [for (final b in asMapList(j['bubbles'])) OmrBubble.fromJson(b)],
        filled: _strs(j['filled']),
        state: _s(j['state']),
        en: _s(j['en']),
        ar: _s(j['ar']),
        confirmed: j['confirmed'] == true,
        problems: [for (final p in asMapList(j['problems'])) OmrIssue.fromJson(p)],
      );

  /// The server's per-question sentence ("detected 4 bubbles, filled: B"), or one built from the boxes.
  String get detected {
    final s = AppConfig.lang == 'ar' ? ar : en;
    if (s != null) return s;
    final f = filled.isEmpty ? t('لا شيء', 'none') : filled.join(', ');
    return t('تم اكتشاف ${bubbles.length} فقاعات، المظلّل: $f', 'detected ${bubbles.length} bubbles, filled: $f');
  }

  /// "Question 17: detected 4 bubbles, filled: B. Correct?" (Example 3).
  String get prompt => t('السؤال $n: $detected. هل هذا صحيح؟', 'Question $n: $detected. Correct?');

  /// A note when the sample did not show one clear mark.
  String? get stateNote => switch (state) {
        'blank' => t('لم يُقرأ تظليل لهذا السؤال في النموذج المظلّل — تأكد من مربعاته.', 'Nothing was read for this question on the filled sample — check its boxes.'),
        'multiple' => t('قُرئ أكثر من تظليل لهذا السؤال في النموذج — تأكد من مربعاته.', 'More than one mark was read for this question on the sample — check its boxes.'),
        'uncertain' => t('التظليل غير واضح في النموذج — تأكد من مربعاته.', 'The mark on the sample is unclear — check its boxes.'),
        _ => null,
      };
}

class StepIdentifier {
  const StepIdentifier({this.kind = 'none', this.columns = const [], this.boxes = const [], this.read, this.status, this.en, this.ar});

  /// shaded · handwritten · printed · qr · none
  final String kind;

  /// shaded: one column of 10 bubbles ("0".."9") per digit (mm; the reply has no px for these).
  final List<List<OmrBubble>> columns;

  /// handwritten: one box per digit (mm).
  final List<OmrBoxMm> boxes;
  final String? read;
  final String? status;
  final String? en;
  final String? ar;

  static StepIdentifier fromJson(dynamic v) {
    final j = asMap(v);
    return StepIdentifier(
      kind: '${j['kind'] ?? 'none'}',
      columns: [
        for (final col in (j['columns'] is List ? j['columns'] as List : const []))
          if (col is List) [for (final b in asMapList(col)) OmrBubble.fromJson(b)],
      ],
      boxes: [for (final b in (j['boxes'] is List ? j['boxes'] as List : const [])) ?OmrBoxMm.fromJson(b)],
      read: _s(j['read']),
      status: _s(j['status']),
      en: _s(j['en']),
      ar: _s(j['ar']),
    );
  }

  bool get present => kind != 'none' && (columns.isNotEmpty || boxes.isNotEmpty || kind == 'printed' || kind == 'qr');

  /// "Detected 10 columns × 10 digits. Student ID read from the filled sheet: 2024001234. Correct?"
  String get prompt {
    final s = AppConfig.lang == 'ar' ? ar : en;
    if (s != null) return t('$s. هل هذا صحيح؟', '$s. Correct?');
    return switch (kind) {
      'shaded' => t('تم اكتشاف ${columns.length} أعمدة لرقم الطالب. هل هذا صحيح؟', 'Detected ${columns.length} student ID columns. Correct?'),
      'handwritten' => t('تم اكتشاف ${boxes.length} مربعات لرقم الطالب. هل هذا صحيح؟', 'Detected ${boxes.length} student ID boxes. Correct?'),
      'printed' => t('يُقرأ رقم الطالب من رمز مطبوع على الورقة.', 'The student ID is read from a printed code on the sheet.'),
      'qr' => t('يُقرأ رقم الطالب من رمز QR على الورقة.', 'The student ID is read from a QR code on the sheet.'),
      _ => t('لا يوجد رقم طالب على هذه الورقة.', 'This sheet has no student ID.'),
    };
  }

  /// The zone (mm) to highlight: the union of the columns or the boxes.
  Rect? get zoneMm {
    Rect? u;
    for (final col in columns) {
      for (final b in col) {
        final r = Rect.fromCircle(center: Offset(b.cx, b.cy), radius: b.r);
        u = u == null ? r : u.expandToInclude(r);
      }
    }
    for (final b in boxes) {
      u = u == null ? b.rect : u.expandToInclude(b.rect);
    }
    return u?.inflate(1.5);
  }
}

class StepForm {
  const StepForm({this.forms = const [], this.markers = const [], this.bubbles = const [], this.readValue, this.readStatus});
  final List<String> forms;
  final List<String> markers;

  /// The model row (one bubble per form), mm.
  final List<OmrBubble> bubbles;
  final String? readValue;
  final String? readStatus;

  static StepForm fromJson(dynamic v) {
    final j = asMap(v);
    final zone = asMap(j['zone']);
    final read = asMap(j['read']);
    return StepForm(
      forms: _strs(j['forms']).isNotEmpty ? _strs(j['forms']) : _strs(zone['forms']),
      markers: _strs(j['markers']).isNotEmpty ? _strs(j['markers']) : _strs(zone['markers']),
      bubbles: [for (final b in asMapList(zone['bubbles'])) OmrBubble.fromJson(b)],
      readValue: _s(read['value']),
      readStatus: _s(read['status']),
    );
  }

  bool get hasRow => bubbles.isNotEmpty;

  /// "Model row: 4 bubbles (A, B, C, D). Read from the filled sheet: A. Correct?"
  String get prompt {
    final labels = bubbles.map((b) => b.label).join(t('، ', ', '));
    final read = readValue == null ? '' : t(' النموذج المقروء من الورقة المظلّلة: $readValue.', ' Read from the filled sheet: $readValue.');
    return t('صف النموذج: ${bubbles.length} فقاعات ($labels).$read هل هذا صحيح؟', 'Model row: ${bubbles.length} bubbles ($labels).$read Correct?');
  }
}

class StepPreview {
  const StepPreview({this.ppm = 4, this.w, this.h, this.blankUrl, this.filledUrl});
  final double ppm;
  final int? w;
  final int? h;
  final String? blankUrl;
  final String? filledUrl;

  static StepPreview fromJson(dynamic v) {
    final j = asMap(v);
    return StepPreview(
      ppm: _d(j['ppm'], 4),
      w: j['w'] is num ? (j['w'] as num).toInt() : null,
      h: j['h'] is num ? (j['h'] as num).toInt() : null,
      blankUrl: _s(j['blank_url']),
      filledUrl: _s(j['filled_url']),
    );
  }

  bool get available => blankUrl != null && w != null && h != null && w! > 0 && h! > 0;

  SheetGeometry? get geometry => available ? SheetGeometry(ppm: ppm, width: w!.toDouble(), height: h!.toDouble()) : null;
}

class TemplateSteps {
  const TemplateSteps({
    required this.templateId,
    this.status = 'draft',
    this.learningState,
    this.error,
    this.preview = const StepPreview(),
    this.summaryEn,
    this.summaryAr,
    this.identifier = const StepIdentifier(),
    this.form = const StepForm(),
    this.warnings = const [],
    this.questions = const [],
    this.validation = const TemplateValidation(),
    this.unconfirmed = const [],
  });

  final int templateId;
  final String status;
  final String? learningState;
  final String? error;
  final StepPreview preview;
  final String? summaryEn;
  final String? summaryAr;
  final StepIdentifier identifier;
  final StepForm form;
  final List<OmrIssue> warnings;
  final List<StepQuestion> questions;
  final TemplateValidation validation;
  final List<int> unconfirmed;

  static TemplateSteps fromJson(Map<String, dynamic> j) {
    final summary = asMap(j['summary']);
    return TemplateSteps(
      templateId: asInt(j['template_id']),
      status: '${j['status'] ?? 'draft'}',
      learningState: _s(j['learning_state']),
      error: _s(j['error']),
      preview: StepPreview.fromJson(j['preview']),
      summaryEn: _s(summary['en']),
      summaryAr: _s(summary['ar']),
      identifier: StepIdentifier.fromJson(j['identifier']),
      form: StepForm.fromJson(j['form']),
      warnings: [for (final w in asMapList(j['warnings'])) OmrIssue.fromJson(w)],
      questions: [for (final q in asMapList(j['questions'])) StepQuestion.fromJson(q)]..sort((a, b) => a.n.compareTo(b.n)),
      validation: TemplateValidation.fromJson(j['validation']),
      unconfirmed: [for (final x in (j['unconfirmed'] is List ? j['unconfirmed'] as List : const [])) asInt(x)],
    );
  }

  /// The learning job has not answered yet.
  bool get learning => learningState == 'queued' || learningState == 'running';
  bool get recalibrating => learningState == 'recalibrating';
  bool get failed => learningState == 'failed';

  /// A job is on it (the screen watches `job_updated {kind: omr_template}`).
  bool get busy => learning || recalibrating;

  /// "Detected 4 corner marks, 2 answer columns".
  String? get summary => (AppConfig.lang == 'ar' ? summaryAr : summaryEn) ?? summaryEn;

  bool get editable => status == 'draft' || status == 'rejected';

  StepQuestion? question(int n) {
    for (final q in questions) {
      if (q.n == n) return q;
    }
    return null;
  }

  int get confirmedCount => questions.where((q) => q.confirmed).length;

  /// The questions a person can confirm in one go: unconfirmed, read as one clear mark, no problem named.
  List<int> get clearUnconfirmed => [for (final q in questions) if (!q.confirmed && q.state == 'clear' && q.problems.isEmpty) q.n];
}

/// One stop of the step-through: a question, the identifier zone, or the model row.
sealed class StepItem {
  const StepItem();
}

class QuestionItem extends StepItem {
  const QuestionItem(this.n);
  final int n;
}

class IdentifierItem extends StepItem {
  const IdentifierItem();
}

class FormRowItem extends StepItem {
  const FormRowItem();
}

/// Every question in order, then the identifier zone (when the sheet has one), then the model row (when printed).
List<StepItem> stepItems(TemplateSteps s) => [
      for (final q in s.questions) QuestionItem(q.n),
      if (s.identifier.present) const IdentifierItem(),
      if (s.form.hasRow) const FormRowItem(),
    ];

// ── the shading description (hints) ────────────────────────────────────────────────────────────────────────────

/// What the person says about the sheet (services/omr_templates.py `clean_hints`; unknown keys are refused there).
class LearnHints {
  const LearnHints({
    this.questions,
    this.options,
    this.perColumn,
    this.layout = 'columns',
    this.oneChoice = true,
    this.idKind = 'shaded',
    this.idColumns,
    this.forms = '',
  });

  final int? questions;
  final int? options;
  final int? perColumn;

  /// columns (numbered down each column) · rows (numbered across)
  final String layout;
  final bool oneChoice;

  /// shaded · handwritten · printed · qr · none
  final String idKind;
  final int? idColumns;

  /// The model letters printed on the sheet ("ABCD"), empty when none.
  final String forms;

  static const idKinds = ['shaded', 'handwritten', 'printed', 'qr', 'none'];

  bool get needsColumns => idKind == 'shaded' || idKind == 'handwritten';

  LearnHints copyWith({int? questions, int? options, int? perColumn, String? layout, bool? oneChoice, String? idKind, int? idColumns, String? forms, bool clearPerColumn = false, bool clearIdColumns = false}) =>
      LearnHints(
        questions: questions ?? this.questions,
        options: options ?? this.options,
        perColumn: clearPerColumn ? null : (perColumn ?? this.perColumn),
        layout: layout ?? this.layout,
        oneChoice: oneChoice ?? this.oneChoice,
        idKind: idKind ?? this.idKind,
        idColumns: clearIdColumns ? null : (idColumns ?? this.idColumns),
        forms: forms ?? this.forms,
      );

  /// The `hints` JSON of POST …/learn (only the keys that have a value).
  Map<String, dynamic> toJson() => {
        'questions': ?questions,
        'options': ?options,
        'per_column': ?perColumn,
        'layout': layout,
        'one_choice_per_question': oneChoice,
        'id_kind': idKind,
        if (needsColumns && idColumns != null) 'id_columns': idColumns,
        if (forms.trim().isNotEmpty) 'forms': forms.trim().toUpperCase(),
      };

  /// The first thing the server would refuse, said the way a person fixes it; null when it can be sent.
  String? problem() {
    final q = questions, o = options;
    if (q == null) return t('اكتب عدد الأسئلة', 'Enter the number of questions');
    if (q < 1 || q > 300) return t('عدد الأسئلة بين 1 و 300', 'The number of questions is between 1 and 300');
    if (o == null) return t('اكتب عدد الاختيارات لكل سؤال', 'Enter the options per question');
    if (o < 2 || o > 8) return t('الاختيارات لكل سؤال بين 2 و 8', 'Options per question are between 2 and 8');
    final pc = perColumn;
    if (pc != null && (pc < 1 || pc > 300)) return t('الأسئلة في كل عمود بين 1 و 300', 'Questions per column are between 1 and 300');
    if (idKind == 'shaded' && (idColumns == null || idColumns == 0)) {
      return t('اكتب عدد أعمدة رقم الطالب (عدد خاناته)', 'Enter the number of student ID columns (its digits)');
    }
    final ic = idColumns;
    if (needsColumns && ic != null && (ic < 0 || ic > 20)) return t('أعمدة رقم الطالب بين 1 و 20', 'Student ID columns are between 1 and 20');
    final f = forms.trim().toUpperCase();
    if (f.isNotEmpty && (!RegExp(r'^[A-H]{1,8}$').hasMatch(f) || f.split('').toSet().length != f.length)) {
      return t('حروف النماذج من A إلى H بلا تكرار (مثل ABCD)', 'Model letters are A to H, each once (like ABCD)');
    }
    return null;
  }
}

/// The picked file name says what the engine accepts (PNG / JPEG / WebP / PDF).
bool learnFileAccepted(String name) => RegExp(r'\.(png|jpe?g|webp|pdf)$', caseSensitive: false).hasMatch(name);

String _mime(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

// ── server codes as text ───────────────────────────────────────────────────────────────────────────────────────

/// A template route's refusal as one sentence for a person (the server's own English / Arabic when it has one).
String omrTemplateErrorText(EngineResult r) {
  final d = r.detail;
  final mapped = switch (r.code) {
    'hints_required' => d['key'] == 'id_columns'
        ? t('اكتب عدد أعمدة رقم الطالب للرقم المظلّل', 'Enter the number of student ID columns for a shaded ID')
        : t('أكمل وصف الورقة (${d['key'] ?? ''})', 'Complete the sheet description (${d['key'] ?? ''})'),
    'hints_out_of_range' => t('قيمة خارج الحدود في وصف الورقة (${d['key'] ?? ''}: ${d['min'] ?? ''}–${d['max'] ?? ''})',
        'A value is out of range in the sheet description (${d['key'] ?? ''}: ${d['min'] ?? ''}–${d['max'] ?? ''})'),
    'hints_invalid' || 'hints_unknown_keys' => t('وصف الورقة غير صالح — راجع الأرقام', 'The sheet description is not valid — check the numbers'),
    'name_required' => t('اكتب اسمًا لنوع الورقة', 'Give the sheet type a name'),
    'unsupported_file' => t('ارفع صورة PNG أو JPEG أو WebP أو ملف PDF', 'Upload a PNG, JPEG or WebP image or a PDF'),
    'file_too_large' => t('الملف أكبر من 20 ميجابايت', 'The file is larger than 20 MB'),
    'template_not_editable' => t('النسخة المنشورة لا تُعدَّل — أنشئ إصدارًا جديدًا منها', 'A published version is not edited: create a new version of it'),
    'template_learning' => t('ما زال التعلّم جاريًا — لحظات', 'Learning is still running — a few seconds'),
    'template_not_yours' => t('يعدّل هذا النوع صاحبه أو مشرف المنصة فقط', 'Only its owner or a platform super admin can change this sheet type'),
    'bubbles_invalid' => t('حجم الفقاعة بين 0.5 و 10 مم', 'A bubble radius is between 0.5 and 10 mm'),
    'bubble_labels' => t('يجب أن تبقى حروف الفقاعات كما هي', 'The bubble letters must stay the same'),
    'question_not_found' => t('هذا السؤال ليس في الورقة', 'That question is not on the sheet'),
    'column_not_found' => t('عمود رقم الطالب غير موجود', 'That student ID column is not on the sheet'),
    'template_invalid' => t('لم يجتز الفحص بعد — صحّح المشكلات وأكّد كل الأسئلة', 'It did not pass the checks yet — fix the problems and confirm every question'),
    'template_state' => t('لا يمكن ذلك في حالته الحالية (${omrStatusLabel('${d['template_status'] ?? ''}')})',
        'Not possible in its current state (${omrStatusLabel('${d['template_status'] ?? ''}')})'),
    'reason_required' => t('اكتب سبب الرفض', 'Write the reason for rejecting it'),
    'teachers_only' => t('مكتبة أوراق التظليل للمعلمين والإدارة', 'The bubble sheet library is for teachers and staff'),
    'super_admin_required' => t('لمشرف المنصة فقط', 'Platform super admins only'),
    'template_not_found' => t('نوع الورقة غير موجود', 'This sheet type was not found'),
    'image_not_found' => t('الصورة غير متاحة بعد', 'The image is not available yet'),
    _ => null,
  };
  if (mapped != null) return mapped;
  final en = d['message_en'];
  if (en != null && AppConfig.lang == 'en') return '$en';
  if (r.message.isNotEmpty && r.message != 'Not Found') return r.message;
  return t('تعذّر الاتصال — أعد المحاولة', 'Could not reach the server — try again');
}

// ── API ────────────────────────────────────────────────────────────────────────────────────────────────────────

/// The template routes of the Exam Engine (routers/omr.py + routers/omr_flow.py).
class OmrTemplatesApi {
  OmrTemplatesApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _b = '/api/v1/exam';

  /// Published + the caller's own (the super admin: all) and `require_approval`.
  Future<EngineResult> list({String? status}) => engineCall(() => _api.get('$_b/omr/templates', queryParams: {'status': ?status}));
  Future<EngineResult> detail(int id) => engineCall(() => _api.get('$_b/omr/templates/$id'));
  Future<EngineResult> steps(int id) => engineCall(() => _api.get('$_b/omr/templates/$id/steps'));

  /// 202 → the draft (`learning_state: queued`); a worker job learns it.
  Future<EngineResult> learn({
    required String name,
    required LearnHints hints,
    required (String, Uint8List) blank,
    (String, Uint8List)? filled,
    String? description,
  }) {
    final form = FormData();
    form.fields
      ..add(MapEntry('name', name.trim()))
      ..add(MapEntry('hints', jsonEncode(hints.toJson())));
    if (description != null && description.trim().isNotEmpty) form.fields.add(MapEntry('description', description.trim()));
    form.files.add(MapEntry('blank', MultipartFile.fromBytes(blank.$2, filename: blank.$1, contentType: MediaType.parse(_mime(blank.$1)))));
    if (filled != null) {
      form.files.add(MapEntry('filled', MultipartFile.fromBytes(filled.$2, filename: filled.$1, contentType: MediaType.parse(_mime(filled.$1)))));
    }
    return engineCall(() => _api.post('$_b/omr/templates/learn', body: form));
  }

  /// A question's moved / resized bubbles (mm) → the new steps (`learning_state: recalibrating`).
  Future<EngineResult> putAnswerBoxes(int id, int n, List<OmrBubble> bubbles) =>
      engineCall(() => _api.put('$_b/omr/templates/$id/boxes', body: {'kind': 'answers', 'n': n, 'bubbles': [for (final b in bubbles) b.toJson()]}));
  Future<EngineResult> putIdentifierColumn(int id, int column, List<OmrBubble> bubbles) =>
      engineCall(() => _api.put('$_b/omr/templates/$id/boxes', body: {'kind': 'identifier', 'column': column, 'bubbles': [for (final b in bubbles) b.toJson()]}));
  Future<EngineResult> putFormRow(int id, List<OmrBubble> bubbles) =>
      engineCall(() => _api.put('$_b/omr/templates/$id/boxes', body: {'kind': 'form', 'bubbles': [for (final b in bubbles) b.toJson()]}));

  /// [numbers] null = "all".
  Future<EngineResult> confirm(int id, List<int>? numbers, {bool confirmed = true}) =>
      engineCall(() => _api.post('$_b/omr/templates/$id/confirm', body: {'numbers': numbers ?? 'all', if (!confirmed) 'confirmed': false}));
  Future<EngineResult> validate(int id) => engineCall(() => _api.post('$_b/omr/templates/$id/validate'));

  /// Super admin → published; a teacher → pending_approval (while approval is required) or published.
  Future<EngineResult> submit(int id) => engineCall(() => _api.post('$_b/omr/templates/$id/submit'));
  Future<EngineResult> approve(int id) => engineCall(() => _api.post('$_b/omr/templates/$id/publish'));
  Future<EngineResult> reject(int id, String reason) => engineCall(() => _api.post('$_b/omr/templates/$id/reject', body: {'reason': reason.trim()}));

  /// A published / retired version → version n + 1 as a draft (201).
  Future<EngineResult> newVersion(int id) => engineCall(() => _api.post('$_b/omr/templates/$id/versions'));
  Future<EngineResult> settings() => engineCall(() => _api.get('$_b/admin/omr/settings'));
  /// Sends only what is given; the server keeps the other setting (`smart_photos`: D-163, OFF = the old reader).
  Future<EngineResult> putSettings({bool? requireApproval, bool? smartPhotos}) => engineCall(() => _api.put('$_b/admin/omr/settings', body: {
        if (requireApproval != null) 'require_approval': requireApproval,
        if (smartPhotos != null) 'smart_photos': smartPhotos,
      }));

  /// preview · blank_preview · filled_preview (PNG); null when it is not there (yet).
  Future<Uint8List?> image(int id, String kind) async {
    try {
      final b = await _api.getBytes('$_b/omr/templates/$id/image', queryParams: {'kind': kind});
      return b.isEmpty ? null : b;
    } catch (_) {
      return null;
    }
  }
}
