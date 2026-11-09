// Templates for the teacher's OWN paper sheets (D-241, contract docs/grading/CONTRACT.md §3 + §4): covers, mark
// sheets and MCQ answer tables. The pure part: the library rows, the MarkSheetSpec (fields with boxes normalised 0..1
// on the blank reference), the detect proposals, the plain-words validation, the test reading and the engine calls.
// No widget here; templates/ draws it.
library;

import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:http_parser/http_parser.dart' show MediaType;

import '../../../admin/admin_common.dart' show asMap, asMapList, t;
import '../exam_authoring.dart' show parseEngineUtc;
import '../exam_engine_api.dart' show EngineResult, engineCall;
import 'templates/mark_strip.dart';

/// The kill switch of the whole part (feature catalog `exam.mark_templates`).
const kMarkTemplatesFeatureKey = 'exam.mark_templates';

double _d(dynamic v, [double d = 0]) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}'.replaceAll(',', '.')) ?? d);
double? _dn(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'.replaceAll(',', '.')));
int? _in(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
String? _s(dynamic v) => v == null || '$v'.trim().isEmpty ? null : '$v';

/// A number as the teacher reads it: 5, 0.5, 12.25 (no trailing zeros).
String numText(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

// ── kinds and field types ────────────────────────────────────────────────────

enum MarkKind {
  cover('cover'),
  markSheet('mark_sheet'),
  answerTable('answer_table');

  const MarkKind(this.wire);
  final String wire;

  static MarkKind? parse(dynamic v) {
    for (final k in values) {
      if (k.wire == '$v') return k;
    }
    return null;
  }

  String get label => switch (this) {
        MarkKind.cover => t('غلاف الورقة', 'Cover page'),
        MarkKind.markSheet => t('ورقة الدرجات', 'Mark sheet'),
        MarkKind.answerTable => t('جدول إجابات الاختيار', 'MCQ answer table'),
      };

  String get hint => switch (this) {
        MarkKind.cover => t('الرقم التعريفي للطالب والدرجة الكلية (ودرجات الأسئلة إن وُجدت).', 'The student identifier and the total (and the question marks, if any).'),
        MarkKind.markSheet => t('الرقم التعريفي للطالب ودرجة كل سؤال (والمجموع).', 'The student identifier and one mark per question (and the total).'),
        MarkKind.answerTable => t('الرقم التعريفي للطالب وجدول اختيار الإجابات لكل سؤال.', 'The student identifier and the table where each question gets its answer.'),
      };
}

enum FieldType {
  identifier('identifier'),
  questionMark('question_mark'),
  total('total'),
  answerRow('answer_row'),
  unset('');

  const FieldType(this.wire);
  final String wire;

  static FieldType parse(dynamic v) {
    final s = '${v ?? ''}';
    for (final k in values) {
      if (k.wire.isNotEmpty && k.wire == s) return k;
    }
    return switch (s) {
      'mark' || 'marks' => FieldType.questionMark,
      'id' || 'qr' || 'digits' || 'digit_row' => FieldType.identifier,
      'table' || 'answers' => FieldType.answerRow,
      _ => FieldType.unset,
    };
  }

  String get label => switch (this) {
        FieldType.identifier => t('هوية الطالب', 'Student identifier'),
        FieldType.questionMark => t('درجة سؤال', 'Question mark'),
        FieldType.total => t('المجموع', 'Total'),
        FieldType.answerRow => t('صف إجابة', 'Answer row'),
        FieldType.unset => t('لم يُحدَّد النوع', 'Type not set'),
      };
}

const kIdentifierSources = ['qr', 'national_id', 'academic_id', 'name'];

String identifierSourceLabel(String s) => switch (s) {
      'qr' => t('رمز QR', 'QR code'),
      'national_id' => t('الرقم القومي', 'National ID'),
      'academic_id' => t('الرقم الأكاديمي', 'Academic number'),
      'name' => t('الاسم', 'Name'),
      _ => s,
    };

// ── the spec ─────────────────────────────────────────────────────────────────

Rect boxFromJson(dynamic v) {
  if (v is List && v.length >= 4) return Rect.fromLTWH(_d(v[0]), _d(v[1]), _d(v[2]), _d(v[3]));
  return Rect.zero;
}

List<double> boxToJson(Rect r) => [_r4(r.left), _r4(r.top), _r4(r.width), _r4(r.height)];
double _r4(double v) => (v * 10000).roundToDouble() / 10000;

class MarkOption {
  const MarkOption(this.label, this.box);
  final String label;
  final Rect box;
}

class MarkField {
  const MarkField({
    required this.id,
    required this.type,
    required this.box,
    this.source = 'qr',
    this.digits,
    this.questionNo,
    this.max,
    this.step,
    this.mode = 'mark',
    this.options = const [],
    this.guess,
    this.conf,
    this.extra = const {},
    this.strip,
    this.optional = false,
  });

  final String id;
  final FieldType type;
  final Rect box;
  final String source;
  final int? digits;
  final int? questionNo;
  final double? max;
  final double? step;
  final String mode;
  final List<MarkOption> options;

  /// The detector's guess and its confidence (proposals only; never sent back).
  final String? guess;
  final double? conf;

  /// Keys the app does not edit (an identifier's `cells`, …): kept as they came.
  final Map<String, dynamic> extra;

  /// An identifier written on a printed rule at any angle (D-357); the [box] then encloses it.
  final MarkStrip? strip;

  /// A mark that may be left empty: an empty cell counts as 0 and raises no `mark_blank`.
  final bool optional;

  bool get readsNumber => source == 'national_id' || source == 'academic_id';

  MarkField copyWith({
    String? id,
    FieldType? type,
    Rect? box,
    String? source,
    int? digits,
    int? questionNo,
    double? max,
    double? step,
    String? mode,
    List<MarkOption>? options,
    MarkStrip? strip,
    bool? optional,
    bool clearStrip = false,
    bool clearDigits = false,
    bool clearQuestionNo = false,
    bool clearMax = false,
    bool clearStep = false,
  }) =>
      MarkField(
        id: id ?? this.id,
        type: type ?? this.type,
        box: box ?? this.box,
        source: source ?? this.source,
        digits: clearDigits ? null : (digits ?? this.digits),
        questionNo: clearQuestionNo ? null : (questionNo ?? this.questionNo),
        max: clearMax ? null : (max ?? this.max),
        step: clearStep ? null : (step ?? this.step),
        mode: mode ?? this.mode,
        options: options ?? this.options,
        guess: guess,
        conf: conf,
        extra: extra,
        strip: clearStrip ? null : (strip ?? this.strip),
        optional: optional ?? this.optional,
      );

  /// A field of [type] with the defaults the editor starts from.
  MarkField asType(FieldType to, {int? nextQuestionNo}) {
    switch (to) {
      case FieldType.identifier:
        return copyWith(type: to, source: kIdentifierSources.contains(source) ? source : 'qr', clearQuestionNo: true, clearMax: true, clearStep: true);
      case FieldType.questionMark:
        return copyWith(type: to, questionNo: questionNo ?? nextQuestionNo ?? 1, max: max ?? 1, step: step ?? 0.5, clearDigits: true, clearStrip: true);
      case FieldType.total:
        return copyWith(type: to, max: max ?? 10, clearQuestionNo: true, clearStep: true, clearDigits: true, clearStrip: true);
      case FieldType.answerRow:
        final labels = options.isNotEmpty ? [for (final o in options) o.label] : const ['A', 'B', 'C', 'D'];
        return copyWith(type: to, questionNo: questionNo ?? nextQuestionNo ?? 1, options: splitOptions(box, labels, old: options), clearMax: true, clearStep: true, clearDigits: true, clearStrip: true);
      case FieldType.unset:
        return copyWith(type: to, clearStrip: true);
    }
  }

  factory MarkField.fromJson(Map<String, dynamic> j, {required String fallbackId}) {
    final type = FieldType.parse(j['type'] ?? j['guess']);
    final box = boxFromJson(j['box']);
    final opts = <MarkOption>[
      for (final o in asMapList(j['options'])) MarkOption('${o['label'] ?? ''}', boxFromJson(o['box'])),
    ];
    const known = {'id', 'type', 'source', 'box', 'digits', 'question_no', 'max', 'step', 'mode', 'options', 'guess', 'conf', 'strip', 'optional'};
    return MarkField(
      id: _s(j['id']) ?? fallbackId,
      type: type,
      box: box,
      source: _s(j['source']) ?? 'qr',
      digits: _in(j['digits']),
      questionNo: _in(j['question_no']),
      max: _dn(j['max']),
      step: _dn(j['step']),
      mode: _s(j['mode']) == 'letter' ? 'letter' : 'mark',
      options: opts,
      guess: _s(j['guess']),
      conf: _dn(j['conf']),
      extra: {for (final e in j.entries) if (!known.contains(e.key)) e.key: e.value},
      strip: MarkStrip.fromJson(j['strip']),
      optional: j['optional'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'id': id, 'type': type.wire, ...extra, 'box': boxToJson(box)};
    switch (type) {
      case FieldType.identifier:
        m['source'] = source;
        if (digits != null) m['digits'] = digits;
        if (strip != null) m['strip'] = strip!.toJson();
      case FieldType.questionMark:
        m['question_no'] = questionNo;
        m['max'] = max;
        m['step'] = step ?? 0.5;
      case FieldType.total:
        m['max'] = max;
      case FieldType.answerRow:
        m['question_no'] = questionNo;
        m['mode'] = mode;
        m['options'] = [for (final o in options) {'label': o.label, 'box': boxToJson(o.box)}];
      case FieldType.unset:
        break;
    }
    if (optional && type != FieldType.identifier && type != FieldType.unset) m['optional'] = true;
    return m;
  }
}

/// The option boxes of an answer row: the row's box cut into [labels].length equal cells, left to right (a label
/// that existed keeps its own box while the count is unchanged).
List<MarkOption> splitOptions(Rect row, List<String> labels, {List<MarkOption> old = const []}) {
  if (labels.isEmpty) return const [];
  if (old.length == labels.length) return [for (var i = 0; i < labels.length; i++) MarkOption(labels[i], old[i].box)];
  final w = row.width / labels.length;
  return [for (var i = 0; i < labels.length; i++) MarkOption(labels[i], Rect.fromLTWH(row.left + i * w, row.top, w, row.height))];
}

class MarkSheetSpec {
  const MarkSheetSpec({required this.kind, required this.page, required this.fields, this.sumTotal, this.sumParts});

  final MarkKind kind;

  /// The `page` block as the server sent it (aspect, ref_w, ref_h, anchors): kept and sent back as it came.
  final Map<String, dynamic> page;
  final List<MarkField> fields;

  /// `sum_rule.total` (a `total` field's id) and `sum_rule.parts`; null parts = every question mark.
  final String? sumTotal;
  final List<String>? sumParts;

  /// The page's width / height (the reference image's), 1/1.414 when the server gave nothing.
  double get aspect {
    final a = _dn(page['aspect']);
    final w = _dn(page['ref_w']);
    final h = _dn(page['ref_h']);
    if (w != null && h != null && w > 0 && h > 0) return w / h;
    return a != null && a > 0 ? (a > 1 ? 1 / a : a) : 1 / 1.414;
  }

  MarkField? field(String? id) {
    for (final f in fields) {
      if (f.id == id) return f;
    }
    return null;
  }

  Iterable<MarkField> get questionMarks => fields.where((f) => f.type == FieldType.questionMark);

  /// The ids the sum is made of: the chosen parts that still exist, else every question mark.
  List<String> get effectiveParts {
    final ids = {for (final f in questionMarks) f.id};
    final p = sumParts;
    return p == null ? [for (final f in questionMarks) f.id] : [for (final x in p) if (ids.contains(x)) x];
  }

  MarkSheetSpec copyWith({MarkKind? kind, List<MarkField>? fields, String? sumTotal, List<String>? sumParts, bool clearSumTotal = false, bool clearSumParts = false}) =>
      MarkSheetSpec(
        kind: kind ?? this.kind,
        page: page,
        fields: fields ?? this.fields,
        sumTotal: clearSumTotal ? null : (sumTotal ?? this.sumTotal),
        sumParts: clearSumParts ? null : (sumParts ?? this.sumParts),
      );

  /// A saved spec.
  factory MarkSheetSpec.fromJson(Map<String, dynamic> j, {MarkKind? kind}) {
    final fields = <MarkField>[
      for (final (i, f) in asMapList(j['fields']).indexed) MarkField.fromJson(f, fallbackId: 'f${i + 1}'),
    ];
    final rule = asMap(j['sum_rule']);
    final parts = rule['parts'];
    return MarkSheetSpec(
      kind: kind ?? MarkKind.parse(j['kind']) ?? MarkKind.markSheet,
      page: asMap(j['page']),
      fields: fields,
      sumTotal: _s(rule['total']),
      sumParts: parts is List ? [for (final x in parts) '$x'] : null,
    );
  }

  /// The detector's proposals (`guess` + `conf`) as editable fields; ids are made unique here.
  factory MarkSheetSpec.fromDetect(Map<String, dynamic> detect, MarkKind kind) {
    final used = <String>{};
    final fields = <MarkField>[];
    for (final (i, p) in asMapList(detect['proposals']).indexed) {
      var f = MarkField.fromJson(p, fallbackId: 'f${i + 1}');
      var id = f.id;
      var n = 2;
      while (used.contains(id)) {
        id = '${f.id}_${n++}';
      }
      used.add(id);
      if (id != f.id) f = f.copyWith(id: id);
      fields.add(f);
    }
    // printed numbers the detector did not read: number them in order, after the ones it did
    for (final type in [FieldType.questionMark, FieldType.answerRow]) {
      final taken = {for (final f in fields) if (f.type == type && f.questionNo != null) f.questionNo!};
      var n = 0;
      for (var i = 0; i < fields.length; i++) {
        if (fields[i].type != type || fields[i].questionNo != null) continue;
        while (taken.contains(++n)) {}
        fields[i] = fields[i].copyWith(questionNo: n);
      }
    }
    var spec = MarkSheetSpec(kind: kind, page: asMap(detect['page']), fields: fields);
    final totals = spec.fields.where((f) => f.type == FieldType.total);
    if (totals.isNotEmpty) spec = spec.copyWith(sumTotal: totals.first.id);
    return spec;
  }

  Map<String, dynamic> toJson() {
    final total = field(sumTotal);
    final parts = effectiveParts;
    return {
      'kind': kind.wire,
      'page': page,
      'fields': [for (final f in fields) f.toJson()],
      if (total != null && total.type == FieldType.total && parts.isNotEmpty) 'sum_rule': {'total': total.id, 'parts': parts, 'mode': 'sum'},
    };
  }
}

// ── validation (the server's rules, in plain words) ─────────────────────────

class SpecIssue {
  const SpecIssue(this.code, {this.error = true, this.fieldIds = const [], this.params = const {}});
  final String code;
  final bool error;
  final List<String> fieldIds;
  final Map<String, Object?> params;

  String get text {
    final n = params['n'];
    return switch (code) {
      'missing_identifier' => t('لا يوجد حقل لهوية الطالب. حدّد مربع الرقم أو رمز QR.', 'There is no student identifier field. Mark the ID box or the QR code.'),
      'unset_type' => t('مربع بلا نوع. اختر نوعه أو احذفه.', 'A box has no type. Choose its type or delete it.'),
      'duplicate_question' => t('رقم السؤال $n مكرر.', 'Question number $n is used twice.'),
      'question_no_missing' => t('حقل بلا رقم سؤال.', 'A field has no question number.'),
      'max_not_positive' => t('الدرجة العظمى يجب أن تكون أكبر من صفر.', 'The maximum mark must be more than zero.'),
      'step_not_positive' => t('الخطوة يجب أن تكون أكبر من صفر.', 'The step must be more than zero.'),
      'outside_page' => t('مربع يخرج عن حدود الورقة.', 'A box goes outside the page.'),
      'box_too_small' => t('مربع صغير جدًا.', 'A box is too small.'),
      'overlap' => t('مربعان متداخلان. افصل بينهما.', 'Two boxes overlap. Move them apart.'),
      'no_options' => t('صف الإجابة بلا خيارات.', 'An answer row has no options.'),
      'duplicate_option' => t('خيار مكرر في صف الإجابة.', 'An answer row repeats an option label.'),
      'no_marks' => t('أضف مربع درجة واحدًا على الأقل لكل سؤال.', 'Add at least one question mark box.'),
      'no_answer_rows' => t('أضف صف إجابة واحدًا على الأقل.', 'Add at least one answer row.'),
      'no_total' => t('الغلاف يحتاج مربع مجموع.', 'A cover needs a total box.'),
      'two_totals' => t('يوجد أكثر من مربع مجموع.', 'There is more than one total box.'),
      'sum_mismatch' => t('مجموع درجات الأجزاء ${params['sum']} لا يساوي درجة المجموع ${params['total']}.', 'The parts add up to ${params['sum']} but the total is ${params['total']}.'),
      'sum_no_parts' => t('قاعدة المجموع بلا أجزاء.', 'The sum rule has no parts.'),
      'strip_point' => t('طرف الخط خارج الورقة.', 'An end of the line is outside the page.'),
      'strip_short' => t('خط الرقم قصير جدًا. اسحب طرفيه على الخط المطبوع.', 'The line is too short. Drag its two ends along the printed line.'),
      'strip_height' => t('ارتفاع منطقة الكتابة غير مناسب.', 'The height of the writing area is not valid.'),
      'strip_search' => t('هامش البحث غير مناسب.', 'The search margin is not valid.'),
      'strip_source' => t('الخط المائل يقرأ رقمًا فقط.', 'A slanted line reads a number only.'),
      _ => code,
    };
  }
}

/// Smallest side of a box (fraction of the page): below it nothing can be read.
const kMinBoxSide = 0.006;

bool _overlaps(Rect a, Rect b) {
  final iw = (a.right < b.right ? a.right : b.right) - (a.left > b.left ? a.left : b.left);
  final ih = (a.bottom < b.bottom ? a.bottom : b.bottom) - (a.top > b.top ? a.top : b.top);
  return iw > 0.002 && ih > 0.002;
}

/// Errors (the server would refuse) and warnings (it would accept) of [spec]; pure, runs on every edit.
List<SpecIssue> validateSpec(MarkSheetSpec spec) {
  final out = <SpecIssue>[];
  final fs = spec.fields;
  if (!fs.any((f) => f.type == FieldType.identifier)) out.add(const SpecIssue('missing_identifier'));
  for (final f in fs.where((f) => f.type == FieldType.unset)) {
    out.add(SpecIssue('unset_type', fieldIds: [f.id]));
  }
  // kind rules
  switch (spec.kind) {
    case MarkKind.markSheet:
      if (!fs.any((f) => f.type == FieldType.questionMark)) out.add(const SpecIssue('no_marks'));
    case MarkKind.answerTable:
      if (!fs.any((f) => f.type == FieldType.answerRow)) out.add(const SpecIssue('no_answer_rows'));
    case MarkKind.cover:
      if (!fs.any((f) => f.type == FieldType.total)) out.add(const SpecIssue('no_total'));
  }
  if (fs.where((f) => f.type == FieldType.total).length > 1) {
    out.add(SpecIssue('two_totals', fieldIds: [for (final f in fs) if (f.type == FieldType.total) f.id]));
  }
  // numbers, per type
  for (final type in [FieldType.questionMark, FieldType.answerRow]) {
    final seen = <int, String>{};
    for (final f in fs.where((f) => f.type == type)) {
      final n = f.questionNo;
      if (n == null || n <= 0) {
        out.add(SpecIssue('question_no_missing', fieldIds: [f.id]));
      } else if (seen.containsKey(n)) {
        out.add(SpecIssue('duplicate_question', fieldIds: [seen[n]!, f.id], params: {'n': n}));
      } else {
        seen[n] = f.id;
      }
    }
  }
  for (final f in fs) {
    if ((f.type == FieldType.questionMark || f.type == FieldType.total) && (f.max == null || f.max! <= 0)) {
      out.add(SpecIssue('max_not_positive', fieldIds: [f.id]));
    }
    if (f.type == FieldType.questionMark && f.step != null && f.step! <= 0) out.add(SpecIssue('step_not_positive', fieldIds: [f.id]));
    if (f.type == FieldType.identifier && f.strip != null) {
      for (final code in f.strip!.errorCodes) {
        out.add(SpecIssue(code, fieldIds: [f.id]));
      }
      if (!f.readsNumber) out.add(SpecIssue('strip_source', fieldIds: [f.id]));
    }
    if (f.type == FieldType.answerRow) {
      if (f.options.isEmpty) out.add(SpecIssue('no_options', fieldIds: [f.id]));
      if (f.options.map((o) => o.label).toSet().length != f.options.length) out.add(SpecIssue('duplicate_option', fieldIds: [f.id]));
    }
    final b = f.box;
    if (b.left < -0.0001 || b.top < -0.0001 || b.right > 1.0001 || b.bottom > 1.0001) out.add(SpecIssue('outside_page', fieldIds: [f.id]));
    if (b.width < kMinBoxSide || b.height < kMinBoxSide) out.add(SpecIssue('box_too_small', fieldIds: [f.id]));
  }
  for (var i = 0; i < fs.length; i++) {
    for (var j = i + 1; j < fs.length; j++) {
      if (fs[i].strip != null || fs[j].strip != null) continue; // a slanted strip's box is not its real extent
      if (_overlaps(fs[i].box, fs[j].box)) out.add(SpecIssue('overlap', fieldIds: [fs[i].id, fs[j].id]));
    }
  }
  // the sum rule
  final total = spec.field(spec.sumTotal);
  if (total != null && total.type == FieldType.total) {
    final parts = spec.effectiveParts;
    if (parts.isEmpty) {
      out.add(SpecIssue('sum_no_parts', error: false, fieldIds: [total.id]));
    } else {
      final sum = partsMaxSum(spec);
      final tm = total.max ?? 0;
      if ((sum - tm).abs() > 0.0001) {
        out.add(SpecIssue('sum_mismatch', error: false, fieldIds: [total.id], params: {'sum': numText(sum), 'total': numText(tm)}));
      }
    }
  }
  return out;
}

/// The sum of the chosen parts' maximum marks.
double partsMaxSum(MarkSheetSpec spec) {
  var s = 0.0;
  for (final id in spec.effectiveParts) {
    s += spec.field(id)?.max ?? 0;
  }
  return s;
}

bool hasErrors(List<SpecIssue> issues) => issues.any((i) => i.error);

// ── library rows ─────────────────────────────────────────────────────────────

class MarkTemplate {
  const MarkTemplate({
    required this.id,
    required this.familyId,
    required this.version,
    required this.name,
    required this.kind,
    this.orgId,
    this.status = 'published',
    this.fieldsCount = 0,
    this.totalMax,
    this.ownerId,
    this.ownerName = '',
    this.updatedAt,
    this.hasImage = true,
  });

  final int id;
  final String familyId;          // the uuid shared by every version of one template
  final int version;
  final String name;
  final MarkKind? kind;
  final int? orgId;
  final String status;
  final int fieldsCount;
  final double? totalMax;
  final int? ownerId;
  final String ownerName;
  final DateTime? updatedAt;
  final bool hasImage;

  bool get retired => status == 'retired';

  factory MarkTemplate.fromJson(Map<String, dynamic> j) => MarkTemplate(
        id: _in(j['id']) ?? 0,
        familyId: '${j['family_id'] ?? j['id'] ?? ''}',
        version: _in(j['version']) ?? 1,
        name: '${j['name'] ?? ''}',
        kind: MarkKind.parse(j['kind']),
        orgId: _in(j['org_id']),
        status: _s(j['status']) ?? 'published',
        fieldsCount: _in(j['fields_count']) ?? 0,
        totalMax: _dn(j['total_max']),
        ownerId: _in(j['owner_id']),
        ownerName: '${j['owner_name'] ?? ''}',
        updatedAt: parseEngineUtc(j['updated_at']),
        hasImage: j['has_image'] != false,
      );
}

/// A ready-made template shipped with the server (D-357): `GET /mark-templates/builtins`.
class MarkBuiltin {
  const MarkBuiltin({required this.key, required this.nameAr, required this.nameEn, this.kind, this.noteAr = '', this.noteEn = '', this.fieldsCount = 0, this.totalMax});

  final String key, nameAr, nameEn, noteAr, noteEn;
  final MarkKind? kind;
  final int fieldsCount;
  final double? totalMax;

  String get name => t(nameAr, nameEn);
  String get note => t(noteAr, noteEn);

  factory MarkBuiltin.fromJson(Map<String, dynamic> j) => MarkBuiltin(
        key: '${j['key'] ?? ''}',
        kind: MarkKind.parse(j['kind']),
        nameAr: '${j['name_ar'] ?? ''}',
        nameEn: '${j['name_en'] ?? ''}',
        noteAr: '${j['note_ar'] ?? ''}',
        noteEn: '${j['note_en'] ?? ''}',
        fieldsCount: _in(j['fields_count']) ?? 0,
        totalMax: _dn(j['total_max']),
      );

  /// The name a copy of this template gets for a paper out of [total]: the same copy is found again however many exams use it.
  String copyName(double total) => '$name · ${numText(total)}';

  /// Is [template] a copy of this built-in? The server keeps no link to the built-in, so a copy is known by its name.
  bool isCopy(String template) {
    final n = template.trim();
    return (nameAr.isNotEmpty && n.startsWith(nameAr)) || (nameEn.isNotEmpty && n.startsWith(nameEn));
  }

  /// The teacher's own copy out of [total], if they already made one: reused rather than duplicated.
  MarkTemplate? copyFor(Iterable<MarkTemplate> templates, double total) {
    for (final x in templates) {
      if (!x.retired && isCopy(x.name) && x.totalMax != null && (x.totalMax! - total).abs() < 0.0001) return x;
    }
    return null;
  }
}

/// A full mark as typed (Arabic digits and decimal commas included); null unless the server would accept it (0 < x <= 1000).
double? parseFullMark(String text) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  var s = text.trim().replaceAll('٫', '.').replaceAll(',', '.');
  for (var i = 0; i < arabic.length; i++) {
    s = s.replaceAll(arabic[i], '$i');
  }
  final v = double.tryParse(s);
  return v == null || !(v > 0) || v > 1000 ? null : v;
}

/// `detect` → the blank image's key and size, the page block and the proposals.
class MarkDetect {
  const MarkDetect({required this.blankKey, required this.width, required this.height, required this.raw});
  final String blankKey;
  final int width;
  final int height;
  final Map<String, dynamic> raw;

  factory MarkDetect.fromJson(Map<String, dynamic> j) {
    final im = asMap(j['image']);
    return MarkDetect(blankKey: '${j['blank_key'] ?? ''}', width: _in(im['w']) ?? 0, height: _in(im['h']) ?? 0, raw: j);
  }
}

// ── the test reading ─────────────────────────────────────────────────────────

class FieldReading {
  const FieldReading({required this.id, required this.type, this.value, this.conf = 0, this.status = 'ok', this.candidates = const [], this.box});
  final String id;
  final FieldType type;
  final String? value;
  final double conf;

  /// ok · low · blank · unreadable · above_max
  final String status;
  final List<(String, double)> candidates;
  final Rect? box;

  bool get ok => status == 'ok';

  factory FieldReading.fromJson(Map<String, dynamic> j) => FieldReading(
        id: '${j['id'] ?? ''}',
        type: FieldType.parse(j['type']),
        value: j['value'] == null ? null : '${j['value']}',
        conf: _d(j['conf']),
        status: _s(j['status']) ?? 'ok',
        candidates: [
          for (final c in (j['candidates'] is List ? j['candidates'] as List : const []))
            if (c is List && c.length >= 2) ('${c[0]}', _d(c[1])),
        ],
        box: j['box'] is List ? boxFromJson(j['box']) : null,
      );
}

class MarkTestReading {
  const MarkTestReading({
    required this.ok,
    this.method = '',
    this.qualityCode,
    this.fields = const [],
    this.partsRead,
    this.computed,
    this.written,
    this.consistent,
    this.identifierValue,
    this.identifierMethod,
    this.identifierConf,
    this.previewUrl,
    this.previewB64,
  });

  final bool ok;
  final String method;
  final String? qualityCode;
  final List<FieldReading> fields;
  final int? partsRead;
  final double? computed;
  final double? written;
  final bool? consistent;
  final String? identifierValue;
  final String? identifierMethod;
  final double? identifierConf;
  final String? previewUrl;

  /// The straightened page as base64 (the server's `preview_b64`); `preview_url` is null then.
  final String? previewB64;

  factory MarkTestReading.fromJson(Map<String, dynamic> j) {
    final reading = asMap(j['reading']);
    final sum = asMap(reading['sum']);
    final id = asMap(reading['identifier']);
    final q = j['quality'];
    return MarkTestReading(
      ok: j['ok'] != false,
      method: '${j['method'] ?? ''}',
      qualityCode: q is Map ? _s(q['code']) : null,
      fields: [for (final f in asMapList(reading['fields'])) FieldReading.fromJson(f)],
      partsRead: _in(sum['parts_read']),
      computed: _dn(sum['computed']),
      written: _dn(sum['written']),
      consistent: sum['consistent'] is bool ? sum['consistent'] as bool : null,
      identifierValue: id['value'] == null ? null : '${id['value']}',
      identifierMethod: _s(id['method']),
      identifierConf: _dn(id['conf']),
      previewUrl: _s(j['preview_url']),
      previewB64: _s(j['preview_b64']),
    );
  }
}

/// Plain words for a quality code (`blurry`, `too_dark`, …) the server answers when a photo is unusable.
String qualityCodeText(String? code) => switch (code) {
      'blurry' => t('الصورة غير واضحة. ثبّت الهاتف وأعد التصوير.', 'The photo is blurry. Hold the phone steady and retake it.'),
      'too_dark' => t('الصورة مظلمة. صوّر في إضاءة أفضل.', 'The photo is too dark. Use better light.'),
      'too_bright' => t('الصورة شديدة السطوع.', 'The photo is too bright.'),
      'glare' => t('يوجد انعكاس ضوء على الورقة. غيّر زاوية التصوير.', 'There is glare on the sheet. Change the angle.'),
      'page_not_found' => t('لم نجد حدود الورقة. أظهر الورقة كاملة على خلفية مختلفة.', 'The page edges were not found. Show the whole sheet on a plain background.'),
      'not_this_sheet' => t('هذه الورقة لا تطابق القالب.', 'This is not the sheet of this template.'),
      _ => code ?? '',
    };

/// The text of a failed call: the server's bilingual message when it sent one, else the quality code, else its text.
String markErrorText(EngineResult r) {
  final en = r.detail['message_en'];
  if (AppConfig.lang != 'ar' && en != null && '$en'.trim().isNotEmpty) return '$en';
  final byCode = qualityCodeText(r.code);
  if (byCode.isNotEmpty && byCode != r.code) return byCode;
  return switch (r.code) {
    'server_busy' => t('الخادم مشغول، حاول بعد قليل.', 'The server is busy. Try again in a moment.'),
    'spec_invalid' => t('القالب غير صالح. راجع الأخطاء في القائمة.', 'The template is not valid. See the errors in the list.'),
    _ => r.message.isEmpty ? t('تعذّر إكمال الطلب.', 'The request failed.') : r.message,
  };
}

/// The server's `spec_invalid` errors / warnings as plain lines (a string, or a map with message / message_en).
List<String> specInvalidLines(EngineResult r, {bool warnings = false}) {
  final v = r.detail[warnings ? 'warnings' : 'errors'];
  if (v is! List) return const [];
  return [
    for (final x in v)
      if (x is Map)
        (AppConfig.lang != 'ar' ? _s(x['message_en']) : null) ?? _s(x['message']) ?? _s(x['code']) ?? ''
      else
        '$x',
  ].where((s) => s.isNotEmpty).toList();
}

String _mime(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

// ── calls ────────────────────────────────────────────────────────────────────

class MarkTemplatesApi {
  MarkTemplatesApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _b = '/api/v1/exam/mark-templates';

  Future<EngineResult> list({int? orgId, String? kind}) => engineCall(() => _api.get(_b, queryParams: {
        'org_id': ?orgId,
        'kind': ?kind,
      }));

  /// [wholePhoto]: the whole photo is the blank instead of the printed table only, so the editor can reach a corner outside it.
  Future<EngineResult> detect((String, Uint8List) image, {int? orgId, bool wholePhoto = false}) {
    final form = FormData();
    if (orgId != null) form.fields.add(MapEntry('org_id', '$orgId'));
    if (wholePhoto) form.fields.add(const MapEntry('whole_photo', 'true'));
    form.files.add(MapEntry('image', MultipartFile.fromBytes(image.$2, filename: image.$1, contentType: MediaType.parse(_mime(image.$1)))));
    return engineCall(() => _api.post('$_b/detect', body: form));
  }

  Future<EngineResult> create({int? orgId, required String name, required MarkKind kind, required String blankKey, required MarkSheetSpec spec}) =>
      engineCall(() => _api.post(_b, body: {
            'org_id': ?orgId,
            'name': name.trim(),
            'kind': kind.wire,
            'blank_key': blankKey,
            'spec': spec.toJson(),
          }));

  /// A NEW version in the family (old versions stay for the sessions that used them).
  Future<EngineResult> update(int id, {String? name, required MarkSheetSpec spec}) =>
      engineCall(() => _api.put('$_b/$id', body: {if (name != null) 'name': name.trim(), 'spec': spec.toJson()}));

  Future<EngineResult> retire(int id) => engineCall(() => _api.delete('$_b/$id'));

  /// The saved template (its `spec` and `name`) when the server has a detail route; the list row otherwise.
  Future<EngineResult> detail(int id) => engineCall(() => _api.get('$_b/$id'));

  Future<List<MarkBuiltin>> builtins() async {
    final r = await engineCall(() => _api.get('$_b/builtins'));
    if (!r.ok) return const [];
    return [for (final m in asMapList(r.map['items'])) MarkBuiltin.fromJson(m)].where((b) => b.key.isNotEmpty).toList();
  }

  Future<Uint8List?> builtinImage(String key) async {
    try {
      final b = await _api.getBytes('$_b/builtins/$key/image');
      return b.isEmpty ? null : b;
    } catch (_) {
      return null;
    }
  }

  /// A copy of the built-in that the teacher owns. [totalMax] is this paper's full mark (the booklet prints none).
  Future<EngineResult> createBuiltin(String key, {int? orgId, String? name, double? totalMax}) => engineCall(() => _api.post('$_b/builtin', body: {
        'key': key,
        'org_id': ?orgId,
        'name': ?name,
        'total_max': ?totalMax,
      }));

  /// The signed blank image; null when it is not there.
  Future<Uint8List?> image(int id) async {
    try {
      final b = await _api.getBytes('$_b/$id/image');
      return b.isEmpty ? null : b;
    } catch (_) {
      return null;
    }
  }

  /// Any signed image url the server answered with (`preview_url`).
  Future<Uint8List?> imageAt(String url) async {
    try {
      final b = await _api.getBytes(url);
      return b.isEmpty ? null : b;
    } catch (_) {
      return null;
    }
  }

  Future<EngineResult> test(int id, (String, Uint8List) image) {
    final form = FormData();
    form.files.add(MapEntry('image', MultipartFile.fromBytes(image.$2, filename: image.$1, contentType: MediaType.parse(_mime(image.$1)))));
    return engineCall(() => _api.post('$_b/$id/test', body: form));
  }
}
