// Paper exam setup (D-150, D-151, D-155, D-156): the pure part of the teacher's wizard — models, the step logic, the
// request bodies and the server codes in plain words. The screen is exam_setup_wizard.dart.
//
// Server (Exam Engine, managers only): GET / PUT /api/v1/exam/exams/{id}/setup (a PUT changes ONLY the keys it
// sends), GET …/identifiers (the audience check, never a value), POST …/identifiers/request {due_at?},
// POST …/identifiers/remind, GET / PUT …/forms (a PUT replaces the list), GET /api/v1/exam/omr/templates; the core's
// GET /api/v1/identity-fields lists the platform's custom fields. Rules: exam_engine/services/omr_setup.py.
//
// The ID-zone check (`identifierZoneFit`, the server's `zone_fit` — keep them the same): a shaded grid / handwritten
// boxes hold N digits; `block` when no value the identifier allows can go there (a name or an e-mail, or its shortest
// allowed length > N — the server then refuses BLANK sheets, 409 identifier_zone_mismatch; a named sheet per student
// still prints), `warn` when some values do not fit or missing students may type one that will not.
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';

import '../../../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import '../exam_engine_api.dart';

/// Kill switches (the server's feature catalog): the identifier step + the student's dialog; the bubble-sheet parts.
const kExamIdentifiersFeatureKey = 'exam.identifiers';
const kExamOmrFeatureKey = 'exam.omr';

/// The live event the core sends the teacher who asked: `{exam_ref, missing, duplicate?}` (stream only).
const kExamIdentifiersEvent = 'exam_identifiers';

/// `exam:<id>` → the engine exam id (null for anything else).
int? examIdFromRef(Object? ref) {
  final m = RegExp(r'^exam:(\d+)$').firstMatch('${ref ?? ''}');
  return m == null ? null : int.tryParse(m.group(1)!);
}

String examRefOf(int examId) => 'exam:$examId';

// ── the exam's setup ────────────────────────────────────────────────────────────────────────────────────────────

/// {blank: zero | review, multiple: wrong | review}; an uncertain mark is ALWAYS reviewed (not a setting).
class OmrPolicy {
  const OmrPolicy({this.blank = 'review', this.multiple = 'review'});
  final String blank;
  final String multiple;

  static OmrPolicy fromJson(Object? v) {
    final m = asMap(v);
    return OmrPolicy(blank: '${m['blank'] ?? 'review'}', multiple: '${m['multiple'] ?? 'review'}');
  }

  /// Never `uncertain`: the server refuses it (422 policy_uncertain_fixed).
  Map<String, dynamic> toJson() => {'blank': blank, 'multiple': multiple};

  OmrPolicy copyWith({String? blank, String? multiple}) => OmrPolicy(blank: blank ?? this.blank, multiple: multiple ?? this.multiple);

  @override
  bool operator ==(Object other) => other is OmrPolicy && other.blank == blank && other.multiple == multiple;

  @override
  int get hashCode => Object.hash(blank, multiple);
}

/// `{source, key}`: name · email · phone · academic_id · national_id · custom (key = a registry field) · datalab
/// (key = a Data Lab column of the course, or `__identifier`).
class IdentifierChoice {
  const IdentifierChoice(this.source, [this.key]);
  final String source;
  final String? key;

  static IdentifierChoice? fromJson(Object? v) {
    if (v is! Map) return null;
    final s = '${v['source'] ?? ''}';
    if (s.isEmpty) return null;
    final k = v['key'];
    return IdentifierChoice(s, k == null || '$k'.isEmpty ? null : '$k');
  }

  Map<String, dynamic> toJson() => {'source': source, 'key': key};

  String get id => key == null ? source : '$source:$key';

  @override
  bool operator ==(Object other) => other is IdentifierChoice && other.source == source && other.key == key;

  @override
  int get hashCode => Object.hash(source, key);
}

class SetupTemplateRef {
  const SetupTemplateRef({required this.id, required this.version, required this.name, required this.status, this.idZone});
  final int id;
  final int version;
  final String name;
  final String status;

  /// The sheet's student-ID zone (null from an older server).
  final IdZone? idZone;
}

/// `GET /exams/{id}/setup`.
class ExamSetup {
  const ExamSetup({
    required this.examId,
    this.delivery = 'online',
    this.onlineAvailable = false,
    this.paperFormat,
    this.identifier,
    this.templateId,
    this.templateVersion,
    this.template,
    this.policy = const OmrPolicy(),
    this.markers = const [],
    this.forms = 0,
    this.paperSections = 0,
    this.warnings = const [],
    this.identifierFit,
  });

  final int examId;

  /// online | paper (an existing exam reads online).
  final String delivery;
  final bool onlineAvailable;

  /// paper | bubble | both | null.
  final String? paperFormat;
  final IdentifierChoice? identifier;
  final int? templateId;
  final int? templateVersion;
  final SetupTemplateRef? template;
  final OmrPolicy policy;

  /// ⊂ {qr, printed, bubble}, at most two.
  final List<String> markers;
  final int forms;
  final int paperSections;
  final List<String> warnings;

  /// Does the identifier fit the pinned bubble sheet's ID zone (the server's answer; null: nothing to check).
  final IdZoneFit? identifierFit;

  static ExamSetup fromJson(Map<String, dynamic> j) {
    final tpl = j['template'];
    return ExamSetup(
      examId: asInt(j['exam_id']),
      delivery: '${j['delivery'] ?? 'online'}',
      onlineAvailable: j['online_available'] == true,
      paperFormat: j['paper_format'] == null ? null : '${j['paper_format']}',
      identifier: IdentifierChoice.fromJson(j['identifier']),
      templateId: j['omr_template_id'] == null ? null : asInt(j['omr_template_id']),
      templateVersion: j['omr_template_version'] == null ? null : asInt(j['omr_template_version']),
      template: tpl is Map
          ? SetupTemplateRef(
              id: asInt(tpl['id']),
              version: asInt(tpl['version'], 1),
              name: '${tpl['name'] ?? ''}',
              status: '${tpl['status'] ?? ''}',
              idZone: tpl['id_zone'] is Map ? IdZone.fromJson(asMap(tpl['id_zone'])) : null)
          : null,
      policy: OmrPolicy.fromJson(j['omr_policy']),
      markers: [for (final m in (j['form_markers'] as List?) ?? const []) '$m'],
      forms: asInt(j['forms']),
      paperSections: asInt(j['paper_sections']),
      warnings: [for (final w in (j['warnings'] as List?) ?? const []) '$w'],
      identifierFit: j['identifier_fit'] is Map ? IdZoneFit.fromJson(asMap(j['identifier_fit'])) : null,
    );
  }

  bool get isBubble => paperFormat == 'bubble' || paperFormat == 'both';
}

// ── identifiers ─────────────────────────────────────────────────────────────────────────────────────────────────

/// A field of the core's registry (`GET /api/v1/identity-fields`).
class IdentityFieldDef {
  const IdentityFieldDef({required this.key, required this.labelAr, required this.labelEn, this.kind = 'text', this.pattern, this.minLen = 1, this.maxLen = 255});
  final String key;
  final String labelAr;
  final String labelEn;

  /// digits | text | email | phone.
  final String kind;
  final String? pattern;
  final int minLen;
  final int maxLen;

  static IdentityFieldDef fromJson(Map<String, dynamic> j) => IdentityFieldDef(
        key: '${j['key'] ?? ''}',
        labelAr: '${j['label_ar'] ?? j['key'] ?? ''}',
        labelEn: '${j['label_en'] ?? j['key'] ?? ''}',
        kind: '${j['kind'] ?? 'text'}',
        pattern: j['pattern'] == null || '${j['pattern']}'.isEmpty ? null : '${j['pattern']}',
        minLen: asInt(j['min_len'], 1),
        maxLen: asInt(j['max_len'], 255),
      );

  String get label => t(labelAr, labelEn);
}

/// One way the wizard offers to identify the students.
class IdentifierOption {
  const IdentifierOption({required this.choice, required this.labelAr, required this.labelEn, required this.kind, required this.collectable, required this.group});
  final IdentifierChoice choice;
  final String labelAr;
  final String labelEn;
  final String kind;

  /// Can be asked of the students (name and Data Lab columns cannot: 409 identifier_not_collectable).
  final bool collectable;

  /// account | field (the platform's custom fields) | datalab (the course's sheet).
  final String group;

  String get label => t(labelAr, labelEn);
}

/// The registry keys that are their own sources (`academic_id`, `national_id`), not `custom`.
const _ownSources = {'national_id', 'academic_id'};

/// name, email, phone, academic id, national id (when the registry has it switched on), every other registry field as
/// `custom`, then the course's Data Lab: the sheet's identifier and each typed (custom) column.
List<IdentifierOption> identifierOptions(List<IdentityFieldDef> fields, {List<(String key, String label)> dataLabColumns = const [], bool dataLab = false}) {
  IdentityFieldDef? reg(String k) {
    for (final f in fields) {
      if (f.key == k) return f;
    }
    return null;
  }

  final academic = reg('academic_id');
  final national = reg('national_id');
  return [
    const IdentifierOption(choice: IdentifierChoice('name'), labelAr: 'الاسم', labelEn: 'Name', kind: 'text', collectable: false, group: 'account'),
    const IdentifierOption(choice: IdentifierChoice('email'), labelAr: 'البريد الإلكتروني', labelEn: 'Email', kind: 'email', collectable: true, group: 'account'),
    const IdentifierOption(choice: IdentifierChoice('phone'), labelAr: 'رقم الهاتف', labelEn: 'Phone number', kind: 'phone', collectable: true, group: 'account'),
    IdentifierOption(
        choice: const IdentifierChoice('academic_id'),
        labelAr: academic?.labelAr ?? 'الرقم الأكاديمي',
        labelEn: academic?.labelEn ?? 'Academic ID',
        kind: academic?.kind ?? 'text',
        collectable: true,
        group: 'account'),
    if (national != null)
      IdentifierOption(
          choice: const IdentifierChoice('national_id'), labelAr: national.labelAr, labelEn: national.labelEn, kind: national.kind, collectable: true, group: 'account'),
    for (final f in fields)
      if (!_ownSources.contains(f.key))
        IdentifierOption(choice: IdentifierChoice('custom', f.key), labelAr: f.labelAr, labelEn: f.labelEn, kind: f.kind, collectable: true, group: 'field'),
    if (dataLab) ...[
      const IdentifierOption(
          choice: IdentifierChoice('datalab', '__identifier'), labelAr: 'رقم الطالب في الجدول', labelEn: 'Sheet identifier', kind: 'text', collectable: false, group: 'datalab'),
      for (final (key, label) in dataLabColumns)
        IdentifierOption(choice: IdentifierChoice('datalab', key), labelAr: label, labelEn: label, kind: 'text', collectable: false, group: 'datalab'),
    ],
  ];
}

class StudentRef {
  const StudentRef(this.userId, this.name);
  final int userId;
  final String name;

  static StudentRef fromJson(Map<String, dynamic> j) => StudentRef(asInt(j['user_id']), '${j['name'] ?? ''}');
}

/// `GET /exams/{id}/identifiers` — who holds the value and who does not (names only, never a value).
class IdentifierReport {
  const IdentifierReport({
    required this.source,
    this.key,
    this.labelAr = '',
    this.labelEn = '',
    this.kind,
    this.collectable = false,
    this.total = 0,
    this.ready = 0,
    this.missing = const [],
    this.duplicates = const [],
    this.pending,
    this.done,
    this.minLen,
    this.maxLen,
    this.valueLengths = const {},
    this.nonDigit = 0,
  });

  final String source;
  final String? key;
  final String labelAr;
  final String labelEn;
  final String? kind;
  final bool collectable;
  final int total;
  final int ready;
  final List<StudentRef> missing;

  /// Groups of two or more students who hold the same value.
  final List<List<StudentRef>> duplicates;

  /// The requests already sent (null: not collectable).
  final int? pending;
  final int? done;

  /// The field's allowed lengths (null from an older server or when the field has none).
  final int? minLen;
  final int? maxLen;

  /// {length: students} of the values that are plain digits, and how many values are not — counts, never a value.
  final Map<int, int> valueLengths;
  final int nonDigit;

  static IdentifierReport fromJson(Map<String, dynamic> j) {
    final req = j['requests'];
    return IdentifierReport(
      source: '${j['source'] ?? ''}',
      key: j['key'] == null ? null : '${j['key']}',
      labelAr: '${j['label_ar'] ?? ''}',
      labelEn: '${j['label_en'] ?? ''}',
      kind: j['kind'] == null ? null : '${j['kind']}',
      collectable: j['collectable'] == true,
      total: asInt(j['total']),
      ready: asInt(j['ready']),
      missing: [for (final m in asMapList(j['missing'])) StudentRef.fromJson(m)],
      duplicates: [
        for (final g in (j['duplicates'] as List?) ?? const [])
          if (g is List) [for (final m in asMapList(g)) StudentRef.fromJson(m)],
      ],
      pending: req is Map ? asInt(req['pending']) : null,
      done: req is Map ? asInt(req['done']) : null,
      minLen: j['min_len'] is num ? (j['min_len'] as num).toInt() : null,
      maxLen: j['max_len'] is num ? (j['max_len'] as num).toInt() : null,
      valueLengths: {
        for (final e in asMap(j['value_lengths']).entries)
          if (int.tryParse(e.key) != null) int.parse(e.key): asInt(e.value),
      },
      nonDigit: asInt(j['non_digit']),
    );
  }

  String get label => t(labelAr.isEmpty ? labelEn : labelAr, labelEn.isEmpty ? labelAr : labelEn);
  int get missingCount => missing.length;

  /// Students who share a value with someone else.
  int get duplicateStudents => duplicates.fold(0, (s, g) => s + g.length);

  /// "34 ready, 6 missing".
  String get summary => t('${arNum(ready)} جاهز، ${arNum(missingCount)} ناقص', '$ready ready, $missingCount missing');
}

/// Western digits in the Arabic UI too (the app's numbers are Western everywhere); one place to change it.
String arNum(int n) => '$n';

// ── templates ───────────────────────────────────────────────────────────────────────────────────────────────────

/// A row of `GET /omr/templates`: one VERSION of a bubble-sheet layout.
class OmrTemplateItem {
  const OmrTemplateItem(
      {required this.id, required this.version, required this.name, this.description, this.status = 'published', this.questions = 0, this.options, this.idZone});
  final int id;
  final int version;
  final String name;
  final String? description;
  final String status;
  final int questions;

  /// Choices per question. TODO(omr): the template list does not send it yet (only `questions`); shown when present.
  final int? options;

  /// The student-ID zone (`id_kind` + `id_digits` of the library row; null when the server does not send it).
  final IdZone? idZone;

  static OmrTemplateItem fromJson(Map<String, dynamic> j) => OmrTemplateItem(
        id: asInt(j['id']),
        version: asInt(j['version'], 1),
        name: '${j['name'] ?? ''}',
        description: j['description'] == null || '${j['description']}'.trim().isEmpty ? null : '${j['description']}',
        status: '${j['status'] ?? ''}',
        questions: asInt(j['questions']),
        options: j['options'] is num ? (j['options'] as num).toInt() : null,
        idZone: j['id_kind'] == null ? null : IdZone('${j['id_kind']}', j['id_digits'] is num ? (j['id_digits'] as num).toInt() : 0),
      );

  bool get published => status == 'published';

  /// "50 questions, 4 options (A–D)".
  String get shape {
    final o = options;
    if (o == null || o < 2 || o > 26) return t('${arNum(questions)} سؤالًا', '$questions questions');
    final last = String.fromCharCode(64 + o);
    return t('${arNum(questions)} سؤالًا، $o اختيارات (A–$last)', '$questions questions, $o options (A–$last)');
  }
}

/// The templates an exam can use: published only (a teacher's own drafts are listed by the server too).
List<OmrTemplateItem> choosableTemplates(List<OmrTemplateItem> all) => [for (final x in all) if (x.published) x];

// ── does the identifier fit the sheet's ID zone? ───────────────────────────────────────────────────────────────

/// A sheet's student-ID zone: shaded columns / handwritten boxes hold [digits] digits; printed / qr / none are not
/// checked (no fixed width, or no zone at all).
class IdZone {
  const IdZone(this.kind, this.digits);
  final String kind;
  final int digits;

  static IdZone fromJson(Map<String, dynamic> j) => IdZone('${j['kind'] ?? 'none'}', asInt(j['digits']));

  bool get checked => (kind == 'shaded' || kind == 'handwritten') && digits > 0;

  @override
  bool operator ==(Object other) => other is IdZone && other.kind == kind && other.digits == digits;

  @override
  int get hashCode => Object.hash(kind, digits);
}

/// The answer of the check: block | warn | ok, why (too_long | not_digits | values | missing_may_not_fit), and the
/// numbers behind it.
class IdZoneFit {
  const IdZoneFit({
    required this.status,
    this.reason,
    required this.zoneKind,
    required this.zoneDigits,
    this.kind = 'text',
    this.minLen,
    this.maxLen,
    this.tooLong = 0,
    this.nonDigit = 0,
    this.missing = 0,
    this.longest,
  });

  final String status;
  final String? reason;
  final String zoneKind;
  final int zoneDigits;
  final String kind;
  final int? minLen;
  final int? maxLen;

  /// Students whose value is longer than the zone / is not only digits / have no value yet.
  final int tooLong;
  final int nonDigit;
  final int missing;

  /// The longest digits value held (null: none).
  final int? longest;

  static IdZoneFit fromJson(Map<String, dynamic> j) {
    int? n(Object? v) => v is num ? v.toInt() : null;
    return IdZoneFit(
      status: '${j['status'] ?? 'ok'}',
      reason: j['reason'] == null ? null : '${j['reason']}',
      zoneKind: '${j['zone_kind'] ?? ''}',
      zoneDigits: asInt(j['zone_digits']),
      kind: '${j['kind'] ?? 'text'}',
      minLen: n(j['min_len']),
      maxLen: n(j['max_len']),
      tooLong: asInt(j['too_long']),
      nonDigit: asInt(j['non_digit']),
      missing: asInt(j['missing']),
      longest: n(j['longest']),
    );
  }

  bool get blocks => status == 'block';
  bool get warns => status == 'warn';
}

/// The server's `zone_fit` (exam_engine/services/omr_setup.py), for a template the teacher is looking at before it is
/// saved. Null when the zone is not a digit zone.
IdZoneFit? identifierZoneFit({
  required String source,
  required String kind,
  int? minLen,
  int? maxLen,
  Map<int, int> lengths = const {},
  int nonDigit = 0,
  int missing = 0,
  required IdZone zone,
}) {
  if (!zone.checked) return null;
  final cap = zone.digits;
  final lo = minLen != null && minLen > 0 ? minLen : null;
  final hi = maxLen != null && maxLen > 0 ? maxLen : null;
  final tooLong = lengths.entries.where((e) => e.key > cap).fold<int>(0, (s, e) => s + e.value);
  final longest = lengths.isEmpty ? null : lengths.keys.reduce((a, b) => a > b ? a : b);
  IdZoneFit fit(String status, String? reason) => IdZoneFit(
      status: status,
      reason: reason,
      zoneKind: zone.kind,
      zoneDigits: cap,
      kind: kind,
      minLen: lo,
      maxLen: hi,
      tooLong: tooLong,
      nonDigit: nonDigit,
      missing: missing,
      longest: longest);
  if (source == 'name' || kind == 'email') return fit('block', 'not_digits');
  if (lo != null && lo > cap) return fit('block', 'too_long');
  if (tooLong > 0 || nonDigit > 0) return fit('warn', 'values');
  if (missing > 0 && ((hi != null && hi > cap) || kind != 'digits')) return fit('warn', 'missing_may_not_fit');
  return fit('ok', null);
}

/// The check for [zone] from the audience report (null when either is missing or the zone is not checked).
IdZoneFit? reportZoneFit(IdentifierReport? r, IdZone? zone) => r == null || zone == null
    ? null
    : identifierZoneFit(
        source: r.source,
        kind: r.kind ?? 'text',
        minLen: r.minLen,
        maxLen: r.maxLen,
        lengths: r.valueLengths,
        nonDigit: r.nonDigit,
        missing: r.missingCount,
        zone: zone);

/// "10 shaded digits" / "10 handwritten boxes" / "printed ID" … for a sheet type's line.
String idZoneLabel(IdZone z) => switch (z.kind) {
      'shaded' => t('رقم الطالب: ${z.digits} أرقام بالتظليل', 'Student ID: ${z.digits} shaded digits'),
      'handwritten' => t('رقم الطالب: ${z.digits} خانات بخط اليد', 'Student ID: ${z.digits} handwritten boxes'),
      'printed' => t('رقم طالب مطبوع', 'Printed student ID'),
      'qr' => t('رقم الطالب برمز QR', 'Student ID as a QR code'),
      _ => t('بلا منطقة لرقم الطالب', 'No student-ID zone'),
    };

/// The card's words: a title, what is wrong, and the ways out (in order: another sheet type, another identifier,
/// named sheets). [label] is the identifier's name in the current language.
({String title, String body, List<String> fixes}) idZoneFitTexts(IdZoneFit f, String label) {
  final n = f.zoneDigits;
  final shaded = f.zoneKind == 'shaded';
  final zoneAr = shaded ? 'منطقة التظليل ($n أعمدة)' : 'خانات رقم الطالب ($n خانات)';
  final zoneEn = shaded ? 'ID grid ($n columns)' : 'ID boxes ($n boxes)';
  final need = f.reason == 'too_long' ? f.minLen : (f.longest != null && f.longest! > n ? f.longest : f.maxLen);
  final named = t('اطبع ورقة باسم كل طالب — رمز QR عليها يحدد الطالب، فلا يحتاج إلى التظليل',
      'Print a named sheet per student — its QR code identifies the student, nothing to shade');
  final other = t('عرّف الطلاب بقيمة أقصر (ارجع إلى خطوة «تحديد الطالب»)', 'Identify students by a shorter value (back to the Students step)');
  final wider = need != null && need > n
      ? t('اختر نوع ورقة بمنطقة $need أرقام على الأقل', 'Choose a sheet type with at least $need ID digits')
      : t('اختر نوع ورقة آخر', 'Choose another sheet type');
  if (f.blocks) {
    final size = f.minLen == null ? '' : (f.minLen == f.maxLen || f.maxLen == null ? '${f.minLen}' : '${f.minLen}–${f.maxLen}');
    final body = f.reason == 'not_digits'
        ? t('$label ليس رقمًا، و$zoneAr تقبل الأرقام فقط. لن تُطبع أوراق فارغة لهذا الاختبار.',
            '$label is not a number, and the $zoneEn takes digits only. Blank sheets will not print for this exam.')
        : t('$label من $size رقمًا، و$zoneAr في هذه الورقة أقصر منه، فلن يستطيع أي طالب كتابته. لن تُطبع أوراق فارغة لهذا الاختبار.',
            '$label has $size digits but this sheet\'s $zoneEn is shorter, so no student can fill it in. Blank sheets will not print for this exam.');
    return (
      title: t('$label لا يتسع في هذه الورقة', '$label does not fit this sheet'),
      body: body,
      fixes: [if (f.reason == 'too_long') wider, other, named],
    );
  }
  final lines = <String>[
    if (f.tooLong + f.nonDigit > 0)
      t('${f.tooLong + f.nonDigit} من الطلاب قيمتهم أطول من $n أرقام أو فيها حروف — لن تُطابَق أوراقهم وستذهب للمراجعة.',
          '${f.tooLong + f.nonDigit} ${f.tooLong + f.nonDigit == 1 ? 'student has a value' : 'students have values'} longer than $n digits or with letters — their sheets will not match and go to review.'),
    if (f.reason == 'missing_may_not_fit' || (f.missing > 0 && f.tooLong + f.nonDigit == 0))
      t('${f.missing} لم يُدخلوا قيمتهم بعد، وقد تكون أطول من $n أرقام أو فيها حروف.',
          '${f.missing} ${f.missing == 1 ? 'student has' : 'students have'} not entered it yet, and it may be longer than $n digits or hold letters.'),
  ];
  return (
    title: t('قد لا يتسع $label في هذه الورقة', '$label may not fit this sheet'),
    body: lines.join(' '),
    fixes: [wider, other, named],
  );
}

// ── forms (models A / B / C …) ──────────────────────────────────────────────────────────────────────────────────

class ExamFormDraft {
  ExamFormDraft({required this.code, this.label, Map<String, dynamic>? key}) : key = key ?? {};
  final String code;
  String? label;

  /// {question_id: answer}: an option id (single choice), a list of ids (multiple choice), a bool (true / false).
  final Map<String, dynamic> key;

  static ExamFormDraft fromJson(Map<String, dynamic> j) =>
      ExamFormDraft(code: '${j['code'] ?? ''}'.toUpperCase(), label: j['label'] == null ? null : '${j['label']}', key: Map<String, dynamic>.from(asMap(j['key'])));

  Map<String, dynamic> toJson() => {'code': code, if (label != null && label!.trim().isNotEmpty) 'label': label!.trim(), 'key': key};

  ExamFormDraft copy() => ExamFormDraft(code: code, label: label, key: {
        for (final e in key.entries) e.key: e.value is List ? List.of(e.value as List) : e.value,
      });
}

const kMaxForms = 10;

/// The next free code: A, B, C … Z, then null (the server allows 10).
String? nextFormCode(List<ExamFormDraft> forms) {
  if (forms.length >= kMaxForms) return null;
  final used = {for (final f in forms) f.code};
  for (var c = 65; c <= 90; c++) {
    final s = String.fromCharCode(c);
    if (!used.contains(s)) return s;
  }
  return null;
}

/// True when the two lists hold the same forms with the same keys (nothing to send).
bool sameForms(List<ExamFormDraft> a, List<ExamFormDraft> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i], y = b[i];
    if (x.code != y.code || (x.label ?? '') != (y.label ?? '') || !_sameKey(x.key, y.key)) return false;
  }
  return true;
}

bool _sameKey(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (!b.containsKey(e.key)) return false;
    final x = e.value, y = b[e.key];
    if (x is List && y is List) {
      if (x.length != y.length || !x.every((v) => y.map((w) => '$w').contains('$v'))) return false;
    } else if ('$x' != '$y') {
      return false;
    }
  }
  return true;
}

/// A question the bubble sheet can carry (single / multiple choice, true / false) with its own key.
class ObjectiveQuestion {
  const ObjectiveQuestion({required this.id, required this.type, required this.prompt, this.options = const [], this.correct});
  final int id;

  /// mcq_single | mcq_multi | true_false.
  final String type;
  final String prompt;

  /// (option id, text) in the authored order.
  final List<(String, String)> options;

  /// The question's own key (option id · list of ids · bool).
  final Object? correct;

  static const types = {'mcq_single', 'mcq_multi', 'true_false'};

  /// A placed question of `GET /exams/{id}` (managers see `answer`); null when not objective.
  static ObjectiveQuestion? fromPlaced(Map<String, dynamic> q) {
    final type = '${q['type'] ?? ''}';
    if (!types.contains(type)) return null;
    final body = asMap(q['body']);
    final ans = asMap(q['answer']);
    return ObjectiveQuestion(
      id: asInt(q['id']),
      type: type,
      prompt: '${body['prompt'] ?? ''}',
      options: [
        for (final o in (body['options'] as List?) ?? const []) o is Map ? ('${o['id']}', '${o['text'] ?? ''}') : ('$o', '$o'),
      ],
      correct: ans['correct'],
    );
  }

  /// A, B, C … by position.
  static String letter(int i) => i < 26 ? String.fromCharCode(65 + i) : '${i + 1}';

  /// The choices drawn as buttons: (value, label).
  List<(Object, String)> get choices => type == 'true_false'
      ? [(true, t('صح', 'True')), (false, t('خطأ', 'False'))]
      : [for (var i = 0; i < options.length; i++) (options[i].$1, letter(i))];

  /// True when [form]'s key answers this question.
  bool answeredIn(ExamFormDraft form) {
    final v = form.key['$id'];
    if (v == null) return false;
    if (v is List) return v.isNotEmpty;
    return '$v'.isNotEmpty;
  }

  bool isChosen(ExamFormDraft form, Object value) {
    final v = form.key['$id'];
    if (v is List) return v.map((e) => '$e').contains('$value');
    return v != null && '$v' == '$value';
  }

  /// Tapping a choice: single choice / true-false replace it, multiple choice toggles it.
  void choose(ExamFormDraft form, Object value) {
    if (type == 'mcq_multi') {
      final cur = [for (final e in (form.key['$id'] as List?) ?? const []) '$e'];
      cur.contains('$value') ? cur.remove('$value') : cur.add('$value');
      form.key['$id'] = cur;
    } else {
      form.key['$id'] = value;
    }
  }
}

/// A new form starts from the questions' own keys (the teacher changes what the shuffle moved).
ExamFormDraft newForm(String code, List<ObjectiveQuestion> questions) => ExamFormDraft(code: code, key: {
      for (final q in questions)
        if (q.correct != null) '${q.id}': q.correct is List ? List.of(q.correct as List) : q.correct,
    });

// ── the steps ───────────────────────────────────────────────────────────────────────────────────────────────────

enum SetupStep { identify, delivery, format, template, forms }

/// The wizard's steps for the choices made so far. Online stops after the type; "Exam paper only" skips the template
/// step; the kill switches drop the identifier step (`exam.identifiers`) and every bubble-sheet part (`exam.omr`).
List<SetupStep> setupSteps({required bool identifiersOn, required bool omrOn, String? delivery, String? format}) {
  final d = delivery ?? 'paper';
  final f = format ?? (omrOn ? 'bubble' : 'paper');
  return [
    if (identifiersOn) SetupStep.identify,
    SetupStep.delivery,
    if (d == 'paper') ...[
      SetupStep.format,
      if (omrOn && (f == 'bubble' || f == 'both')) SetupStep.template,
      SetupStep.forms,
    ],
  ];
}

String setupStepLabel(SetupStep s) => switch (s) {
      SetupStep.identify => t('تحديد الطالب', 'Students'),
      SetupStep.delivery => t('النوع', 'Type'),
      SetupStep.format => t('الورقة', 'Paper'),
      SetupStep.template => t('ورقة التظليل', 'Bubble sheet'),
      SetupStep.forms => t('النماذج', 'Models'),
    };

// ── request bodies (only the keys that change, D-151: the server merges) ──────────────────────────────────────

Map<String, dynamic> identifierBody(ExamSetup before, IdentifierChoice choice) => before.identifier == choice ? const {} : {'identifier': choice.toJson()};

Map<String, dynamic> onlineBody(ExamSetup before) => before.delivery == 'online' ? const {} : {'delivery': 'online'};

/// The paper format (+ the template for a bubble sheet). Leaving the bubble sheet also drops a `bubble` form marker
/// (else 422 marker_needs_bubble_sheet).
Map<String, dynamic> formatBody(ExamSetup before, String format, {OmrTemplateItem? template}) {
  final out = <String, dynamic>{};
  if (before.delivery != 'paper') out['delivery'] = 'paper';
  if (before.paperFormat != format) out['paper_format'] = format;
  if (format == 'bubble' || format == 'both') {
    if (template != null && (before.templateId != template.id || before.templateVersion != template.version || out.isNotEmpty)) {
      out['omr_template_id'] = template.id;
      out['omr_template_version'] = template.version;
    }
  } else if (before.markers.contains('bubble')) {
    out['form_markers'] = [for (final m in before.markers) if (m != 'bubble') m];
  }
  return out;
}

/// The last step: policies (bubble sheets only) and the form markers (only with more than one form).
Map<String, dynamic> finishBody(ExamSetup before, {OmrPolicy? policy, List<String>? markers}) => {
      if (policy != null && policy != before.policy) 'omr_policy': policy.toJson(),
      if (markers != null && !_sameList(markers, before.markers)) 'form_markers': markers,
    };

bool _sameList(List<String> a, List<String> b) => a.length == b.length && a.toSet().containsAll(b);

// ── server codes in plain words, each with the fix ────────────────────────────────────────────────────────────

String setupCodeText(String? code, [Map<String, dynamic> detail = const {}]) => switch (code) {
      'setup_unknown_keys' => t('هذا الإصدار من التطبيق أرسل حقلًا لا يعرفه الخادم — حدّث التطبيق', 'This app version sent a setting the server does not know — update the app'),
      'delivery_invalid' => t('اختر نوع الاختبار: إلكتروني أو ورقي', 'Choose the exam type: online or paper'),
      'paper_settings_need_paper' => t('إعدادات الورق للاختبار الورقي فقط — اختر «ورقي» أولًا', 'Paper settings are for paper exams only — choose Paper first'),
      'paper_format_required' => t('اختر شكل الورقة: ورقة الأسئلة أو ورقة التظليل أو كلاهما', 'Choose the paper: the exam paper, the bubble sheet or both'),
      'template_required' => t('اختر نوع ورقة التظليل من القائمة', 'Choose a bubble-sheet type from the list'),
      'template_needs_bubble' => t('نوع ورقة التظليل يخص ورقة التظليل فقط — اختر «ورقة التظليل» أو «كلاهما»', 'A bubble-sheet type needs a bubble sheet — choose Bubble sheet or Both'),
      'template_not_found' => t('لم يعد نوع الورقة هذا موجودًا — اختر نوعًا آخر', 'This sheet type no longer exists — choose another one'),
      'template_not_published' => t('نوع الورقة هذا لم يُعتمد بعد — اختر نوعًا منشورًا', 'This sheet type is not approved yet — choose a published one'),
      'template_version_mismatch' => t('تغيّر إصدار نوع الورقة — أعد فتح القائمة واختره من جديد', 'This sheet type has a newer version — reopen the list and choose it again'),
      'policy_invalid' => t('اختيار غير مسموح في قواعد التظليل — أعد الاختيار', 'That choice is not allowed for marking rules — choose again'),
      'policy_uncertain_fixed' => t('التظليل غير الواضح يذهب للمراجعة دائمًا', 'Unclear marks always go to review'),
      'markers_invalid' => t('اختر طرق التمييز من القائمة دون تكرار', 'Pick the ways to tell models apart from the list, each once'),
      'markers_too_many' => t('طريقتان على الأكثر لتمييز النماذج — ألغِ واحدة', 'At most two ways to tell models apart — remove one'),
      'marker_needs_bubble_sheet' => t('«الفقاعة المظللة» تحتاج ورقة تظليل — اختر طريقة أخرى أو ورقة التظليل', 'A marked bubble needs a bubble sheet — pick another way or use a bubble sheet'),
      'markers_need_forms' => t('طرق التمييز تلزم فقط مع أكثر من نموذج — أضف نموذجًا', 'Ways to tell models apart are needed only with more than one model — add a model'),
      'identifier_source' || 'identifier_invalid_shape' => t('اختر طريقة التعرف على الطالب من القائمة', 'Choose how to identify students from the list'),
      'identifier_key_required' => t('اختر الحقل أو العمود المطلوب', 'Choose the field or the column'),
      'identity_field_unknown' || 'identity_field_inactive' => t('هذا الحقل أوقفه مشرف المنصة — اختر طريقة أخرى', 'The platform admin switched this field off — choose another way'),
      'datalab_column_unknown' => t('هذا العمود لم يعد في جدول المقرر — اختر عمودًا آخر', 'This column is no longer in the course sheet — choose another column'),
      'datalab_column_unsupported' => t('يُقرأ المعرّف من عمود تكتبه أنت فقط، لا من عمود محسوب', 'Only a column you type in can identify students, not a calculated one'),
      'identifiers_need_course' => t('اربط الاختبار بمقرر أولًا لنعرف طلابه (من محرر الاختبار)', 'Link the exam to a course first so we know its students (in the exam editor)'),
      'identifier_not_set' => t('اختر طريقة التعرف على الطالب أولًا', 'Choose how to identify students first'),
      'identifier_zone_mismatch' => identifierZoneMismatchText(detail),
      'identifier_not_collectable' => t('هذه القيمة لا تُطلب من الطلاب — أكملها في جدول بيانات المقرر', 'Students cannot be asked for this one — fill it in the course\'s Data Lab sheet'),
      'identities_unavailable' => t('تعذّر الوصول إلى بيانات الطلاب الآن — أعد المحاولة بعد قليل', 'Student details are unreachable right now — try again in a moment'),
      'due_at_invalid' => t('تاريخ التسليم غير صالح — اختر تاريخًا آخر', 'That due date is not valid — pick another date'),
      'reminder_too_soon' => _retryText(asInt(detail['retry_after'])),
      'forms_invalid' => t('عشرة نماذج على الأكثر', 'Ten models at most'),
      'form_code_invalid' => t('رمز النموذج حروف إنجليزية كبيرة وأرقام (حتى 8)', 'A model code is capital letters and digits (up to 8)'),
      'form_code_duplicate' => t('رمز النموذج ${detail['form_code'] ?? ''} مكرر — غيّر أحدهما', 'Model ${detail['form_code'] ?? ''} appears twice — rename one'),
      'form_key_invalid' => t('مفتاح النموذج غير صالح — أعد اختيار الإجابات', 'That answer key is not valid — choose the answers again'),
      'form_key_unknown_question' => t('مفتاح النموذج ${detail['form_code'] ?? ''} يذكر أسئلة حُذفت من الاختبار — أعد فتح الخطوة', 'Model ${detail['form_code'] ?? ''} lists questions no longer in the exam — reopen this step'),
      'form_key_too_large' => t('مفتاح النموذج أكبر من المسموح', 'That answer key is too large'),
      'form_in_use' => t('نماذج لها أوراق مقروءة لا تُحذف: ${(detail['codes'] as List?)?.join('، ') ?? ''}', 'Models with read sheets cannot be removed: ${(detail['codes'] as List?)?.join(', ') ?? ''}'),
      'exam_closed' => t('الاختبار مغلق — لا يمكن تغيير إعداداته', 'The exam is closed — its setup cannot change'),
      'forbidden' => t('ليس لديك صلاحية إدارة هذا الاختبار', 'You cannot manage this exam'),
      'teachers_only' => t('مكتبة أوراق التظليل للمعلمين والإدارة', 'The bubble-sheet library is for teachers and staff'),
      _ => '',
    };

/// 409 identifier_zone_mismatch (printing blank sheets): what is wrong and the three ways out.
String identifierZoneMismatchText(Map<String, dynamic> detail) {
  final n = detail['zone_digits'] ?? '?';
  final lo = detail['min_len'];
  final named = t('أو اطبع ورقة باسم كل طالب (رمز QR عليها يحدد الطالب)', 'or print a named sheet per student (its QR identifies the student)');
  if (detail['reason'] == 'not_digits') {
    return t('معرّف الطالب ليس رقمًا ولا يُكتب في منطقة رقم الطالب ($n أرقام) — عرّف الطلاب برقم، $named',
        'The student identifier is not a number and cannot go on the $n-digit ID zone — identify students by a number, $named');
  }
  return t('معرّف الطالب ($lo رقمًا) أطول من منطقة رقم الطالب في الورقة ($n أرقام) — اختر نوع ورقة بمنطقة $lo أرقام على الأقل، أو معرّفًا أقصر، $named',
      'The student identifier ($lo digits) is longer than the sheet\'s ID zone ($n digits) — choose a sheet type with at least $lo ID digits, or a shorter identifier, $named');
}

String _retryText(int seconds) {
  final m = (seconds / 60).ceil().clamp(1, 60);
  return t('أُرسل تذكير منذ قليل — يمكنك التذكير مرة أخرى بعد $m دقيقة', 'A reminder went out recently — you can remind again in $m min');
}

/// The text to show for a failed call: the mapped code, else the server's own message, else a generic line.
String setupErrorText(EngineResult r) {
  final mapped = setupCodeText(r.code, r.detail);
  if (mapped.isNotEmpty) return mapped;
  final en = r.detail['message_en'];
  if (en != null && AppConfig.lang == 'en') return '$en';
  if (r.message.isNotEmpty && r.message != 'Not Found') return r.message;
  return t('تعذّر الحفظ — أعد المحاولة', 'Could not save — try again');
}

// ── API ─────────────────────────────────────────────────────────────────────────────────────────────────────────

class ExamSetupApi {
  ExamSetupApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _b = '/api/v1/exam';

  Future<EngineResult> exam(int id) => engineCall(() => _api.get('$_b/exams/$id'));
  Future<EngineResult> setup(int id) => engineCall(() => _api.get('$_b/exams/$id/setup'));

  /// Only the keys in [body] change.
  Future<EngineResult> putSetup(int id, Map<String, dynamic> body) => engineCall(() => _api.put('$_b/exams/$id/setup', body: body));
  Future<EngineResult> identifiers(int id) => engineCall(() => _api.get('$_b/exams/$id/identifiers'));

  /// [dueUtc]: null = the server's default (a paper exam: when it starts).
  Future<EngineResult> requestIdentifiers(int id, {DateTime? dueUtc}) =>
      engineCall(() => _api.post('$_b/exams/$id/identifiers/request', body: {if (dueUtc != null) 'due_at': dueUtc.toUtc().toIso8601String()}));
  Future<EngineResult> remind(int id) => engineCall(() => _api.post('$_b/exams/$id/identifiers/remind'));
  Future<EngineResult> forms(int id) => engineCall(() => _api.get('$_b/exams/$id/forms'));

  /// Replaces the exam's forms.
  Future<EngineResult> putForms(int id, List<ExamFormDraft> forms) =>
      engineCall(() => _api.put('$_b/exams/$id/forms', body: {'forms': [for (final f in forms) f.toJson()]}));
  Future<EngineResult> templates() => engineCall(() => _api.get('$_b/omr/templates'));
  Future<EngineResult> identityFields() => engineCall(() => _api.get('/api/v1/identity-fields'));

  /// The course's Data Lab columns a student can be identified by (typed columns only); empty when the Data Lab is
  /// off or unreachable — the option is then simply not offered.
  Future<List<(String, String)>> dataLabColumns(int courseId) async {
    final r = await engineCall(() => _api.get('/api/v1/data-lab/courses/$courseId/grid', queryParams: {'limit': 1, 'lang': t('ar', 'en')}));
    if (!r.ok) return const [];
    return [
      for (final c in asMapList(r.map['columns']))
        if ('${c['kind']}' == 'custom') ('${c['key']}', '${c['label'] ?? c['key']}'),
    ];
  }
}
