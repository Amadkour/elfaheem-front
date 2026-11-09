// Grade revision (Exam Hub, contract B3): the pure part. Plain models of the server's answers, the setup of a revision,
// the verdict on a sample read, and the queue that keeps every result of a running session in order. No widget and no
// network, so test/org/exam_hub_f6_test.dart runs it alone.
library;

import 'dart:convert' show base64Decode;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter_education_app/config/app_config.dart';

import '../../../../admin/admin_common.dart' show asInt, asMap, t;
import '../../exam_engine_api.dart' show EngineResult;
import '../../exam_features.dart' show examFeatureCodeText;
import '../../marks/mark_sessions_api.dart';
import '../../marks/templates/mark_strip.dart';
import '../../exam_authoring.dart' show parseEngineUtc;
import '../../marks/review/grade_review_start.dart' show GradeColumn;

double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

Uint8List? _b64(Object? v) {
  final s = '${v ?? ''}';
  if (s.isEmpty) return null;
  try {
    return base64Decode(s.contains(',') ? s.substring(s.indexOf(',') + 1) : s);
  } catch (_) {
    return null;
  }
}

/// A refusal in the app language: the words the server sent for this language, else the other one.
String revisionErrorText(EngineResult r, {String? fallback}) {
  final feature = examFeatureCodeText(r.code, r.detail['feature']?.toString());
  if (feature != null) return feature;
  final en = '${r.detail['message_en'] ?? ''}', ar = '${r.detail['message'] ?? ''}';
  final s = AppConfig.lang == 'en' ? (en.isNotEmpty ? en : ar) : (ar.isNotEmpty ? ar : en);
  if (s.isNotEmpty) return s;
  if (r.message.isNotEmpty) return r.message;
  return fallback ?? t('تعذّر تنفيذ الطلب', 'That did not work');
}

// ── what the sheet looks like ─────────────────────────────────────────────────────────────────────────────────────

class RevisionSheetColumn {
  const RevisionSheetColumn({required this.name, this.samples = const [], this.guess});
  final String name;
  final List<String> samples;

  /// identifier | degree | name | null
  final String? guess;

  factory RevisionSheetColumn.fromJson(Map<String, dynamic> j) => RevisionSheetColumn(
        name: '${j['name'] ?? ''}',
        samples: [for (final s in (j['samples'] as List?) ?? const []) '$s'],
        guess: j['guess']?.toString(),
      );
}

class RevisionSheetPreview {
  const RevisionSheetPreview({required this.sheetKey, required this.rows, required this.columns, this.fileName = ''});
  final String sheetKey, fileName;
  final int rows;
  final List<RevisionSheetColumn> columns;

  /// The column the server guessed for [kind], or null.
  String? guessFor(String kind) {
    for (final c in columns) {
      if (c.guess == kind) return c.name;
    }
    return null;
  }

  factory RevisionSheetPreview.fromJson(Map<String, dynamic> j, {String fileName = ''}) => RevisionSheetPreview(
        sheetKey: '${j['sheet_key'] ?? ''}',
        rows: asInt(j['rows']),
        fileName: fileName,
        columns: [for (final c in (j['columns'] as List?) ?? const []) if (c is Map) RevisionSheetColumn.fromJson(asMap(c))],
      );
}

// ── how the paper is written ──────────────────────────────────────────────────────────────────────────────────────

enum DigitScript { auto, western, arabic }

enum WriteKind { handwritten, printed }

class RevisionStyle {
  const RevisionStyle({this.script = DigitScript.auto, this.kind = WriteKind.handwritten});
  final DigitScript script;
  final WriteKind kind;

  RevisionStyle copyWith({DigitScript? script, WriteKind? kind}) => RevisionStyle(script: script ?? this.script, kind: kind ?? this.kind);

  Map<String, dynamic> toJson() => {'script': script.name, 'kind': kind.name};

  @override
  bool operator ==(Object other) => other is RevisionStyle && other.script == script && other.kind == kind;

  @override
  int get hashCode => Object.hash(script, kind);
}

class RevisionStyles {
  const RevisionStyles({this.degree = const RevisionStyle(), this.identifier = const RevisionStyle()});
  final RevisionStyle degree, identifier;

  RevisionStyles copyWith({RevisionStyle? degree, RevisionStyle? identifier}) => RevisionStyles(degree: degree ?? this.degree, identifier: identifier ?? this.identifier);

  Map<String, dynamic> toJson() => {'degree': degree.toJson(), 'identifier': identifier.toJson()};

  /// True when the degrees are set to printed: the screen says plainly what that risks.
  bool get anyPrinted => degree.kind == WriteKind.printed || identifier.kind == WriteKind.printed;

  @override
  bool operator ==(Object other) => other is RevisionStyles && other.degree == degree && other.identifier == identifier;

  @override
  int get hashCode => Object.hash(degree, identifier);
}

String digitScriptLabel(DigitScript s) => switch (s) {
      DigitScript.auto => t('تلقائي', 'Automatic'),
      DigitScript.western => t('أرقام غربية', 'Western digits'),
      DigitScript.arabic => t('أرقام عربية', 'Arabic digits'),
    };

String writeKindLabel(WriteKind k) => switch (k) {
      WriteKind.handwritten => t('بخط اليد', 'Handwritten'),
      WriteKind.printed => t('مطبوعة', 'Printed'),
    };

String revisionStyleLabel(RevisionStyle s) => '${digitScriptLabel(s.script)} · ${writeKindLabel(s.kind)}';

// ── one sample read ───────────────────────────────────────────────────────────────────────────────────────────────

class RevisionSampleField {
  const RevisionSampleField({required this.fieldId, this.type = 'question_mark', this.questionNo, this.value, this.conf = 0, this.status = 'ok', this.max, this.box, this.crop, this.optional = false});

  final String fieldId, type, status;
  final String? questionNo, value;
  final double conf;
  final double? max;

  /// Fractions of the page: left, top, width, height.
  final Rect? box;
  final Uint8List? crop;

  /// The template lets this box stay empty.
  final bool optional;

  /// An empty box the template allows: it counts as 0, it is not a problem and says nothing about accuracy.
  bool get emptyAllowed => optional && status == 'blank' && value == null;

  bool get ok => status == 'ok' || emptyAllowed;
  bool get isTotal => type == 'total';

  String get label => isTotal ? t('المجموع', 'Total') : '${t('سؤال', 'Q')} ${questionNo ?? fieldId}';

  factory RevisionSampleField.fromJson(Map<String, dynamic> j, {bool optional = false}) {
    final b = j['box'];
    return RevisionSampleField(
      fieldId: '${j['field_id'] ?? ''}',
      type: '${j['type'] ?? 'question_mark'}',
      questionNo: j['question_no']?.toString(),
      value: j['value'] == null || '${j['value']}'.isEmpty ? null : '${j['value']}',
      conf: _num(j['conf']) ?? 0,
      status: '${j['status'] ?? 'ok'}',
      max: _num(j['max']),
      box: b is List && b.length >= 4 ? Rect.fromLTWH(_num(b[0]) ?? 0, _num(b[1]) ?? 0, _num(b[2]) ?? 0, _num(b[3]) ?? 0) : null,
      crop: _b64(j['crop_b64']),
      optional: optional,
    );
  }
}

/// [willAsk]: everything was read except whose paper it is, and the teacher will simply be asked. A normal state, not a failure.
enum SampleVerdict { good, willAsk, partial, bad }

/// A student the reader thinks a written number may belong to.
class RevisionCandidate {
  const RevisionCandidate({required this.id, required this.name, this.score = 0, this.alreadyMatched = false, this.fromName = false});
  final int id;
  final String name;
  final double score;

  /// Another paper of this session already went to this student.
  final bool alreadyMatched;

  /// Suggested from a handwritten name, which never links by itself.
  final bool fromName;

  factory RevisionCandidate.fromJson(Map<String, dynamic> j) => RevisionCandidate(id: asInt(j['id']), name: '${j['name'] ?? ''}', score: _num(j['score']) ?? 0, alreadyMatched: j['already_matched'] == true);
}

List<RevisionCandidate> _candidates(Object? v) => [
      for (final c in (v as List?) ?? const [])
        if (c is Map && '${c['name'] ?? ''}'.trim().isNotEmpty) RevisionCandidate.fromJson(asMap(c)),
    ];

/// The choices in the order they are offered: the closest first, anyone who already has a paper last, three at most.
List<RevisionCandidate> orderRevisionCandidates(Iterable<RevisionCandidate> all) {
  final out = [...all]..sort((a, b) {
      if (a.alreadyMatched != b.alreadyMatched) return a.alreadyMatched ? 1 : -1;
      return b.score.compareTo(a.score);
    });
  return out.take(3).toList();
}

/// Why the teacher is being asked, in one calm sentence (`identifier.roster.reason`).
String revisionUnsureText(String? reason, {required bool candidates}) => switch (reason) {
      _ when !candidates => t('لم نجد هذا الرقم عند طلاب هذه القائمة. ابحث عن الطالب وسنقارن الدرجة.', "This number isn't in this list of students. Find the student and we compare the degree."),
      'already_matched' => t('أقرب طالب له ورقة أخرى، فتركنا القرار لك.', 'The closest student already has a paper, so the choice is yours.'),
      _ => t('لم نتأكد من الرقم المكتوب. اختر الطالب وسنقارن الدرجة.', "We weren't sure of the written number. Choose the student and we compare the degree."),
    };

class RevisionSample {
  const RevisionSample({
    required this.ok,
    this.code = '',
    this.message = '',
    this.preview,
    this.identifierMasked = '',
    this.identifierMethod,
    this.identifierConf,
    this.studentId,
    this.studentName,
    this.fields = const [],
    this.written,
    this.computed,
    this.consistent,
    this.styles = const RevisionStyles(),
    this.candidates = const [],
    this.rosterReason,
    this.stripImage,
    this.ruleFound,
  });

  /// The closest students when the number did not link by itself, in the order they are offered.
  final List<RevisionCandidate> candidates;
  final String? rosterReason;

  /// The straightened strip (`identifier.strip_b64`); null for a national id, a phone, an e-mail.
  final Uint8List? stripImage;

  /// Whether the printed line was found on this photo (null: not a strip).
  final bool? ruleFound;

  final bool ok;
  final String code, message, identifierMasked;
  final Uint8List? preview;
  final String? identifierMethod, studentName;
  final double? identifierConf, written, computed;
  final int? studentId;
  final List<RevisionSampleField> fields;
  final bool? consistent;

  /// The choice this photo was read with (the screen compares two reads side by side).
  final RevisionStyles styles;

  bool get matched => studentId != null;
  List<RevisionSampleField> get problems => [for (final f in fields) if (!f.ok) f];

  /// The mean confidence of what was read, 0 … 1 (0 when nothing was). A box allowed to stay empty says nothing either way.
  double get accuracy {
    final read = [for (final f in fields) if (!f.emptyAllowed) f];
    if (read.isEmpty) return 0;
    return read.fold<double>(0, (a, f) => a + f.conf) / read.length;
  }

  /// Nobody in this course has the number the template compares with: the sign to match on another column.
  bool get rosterEmpty => rosterReason == 'no_candidates';

  /// The total this paper comes to: the computed sum, else the written one.
  double? get sum => computed ?? written;

  /// [nameOnly]: the template identifies by a handwritten name, which never links by itself, so a value read is enough.
  /// [strip]: a number written on a printed line, where an unsure read is expected: the teacher is asked, nothing is wrong.
  SampleVerdict verdict({bool nameOnly = false, bool strip = false}) {
    if (!ok) return SampleVerdict.bad;
    if (problems.isNotEmpty) return SampleVerdict.partial;
    if (nameOnly ? identifierMasked.isNotEmpty : matched) return SampleVerdict.good;
    return strip || candidates.isNotEmpty ? SampleVerdict.willAsk : SampleVerdict.partial;
  }

  factory RevisionSample.fromJson(Map<String, dynamic> j, {String lang = 'ar', RevisionStyles styles = const RevisionStyles(), Set<String> optional = const {}}) {
    final id = asMap(j['identifier']);
    final strip = id['strip'] is Map ? asMap(id['strip']) : null;
    final st = asMap(id['student']);
    final sum = asMap(j['sum']);
    final en = '${j['message_en'] ?? ''}', ar = '${j['message'] ?? ''}';
    return RevisionSample(
      ok: j['ok'] != false,
      code: '${j['code'] ?? asMap(j['quality'])['code'] ?? ''}',
      message: lang == 'en' ? (en.isNotEmpty ? en : ar) : (ar.isNotEmpty ? ar : en),
      preview: _b64(j['preview_b64']),
      identifierMasked: '${id['value_masked'] ?? ''}',
      identifierMethod: id['method']?.toString(),
      identifierConf: _num(id['conf']),
      studentId: st['id'] == null ? null : asInt(st['id']),
      studentName: st['name']?.toString(),
      fields: [for (final f in (j['fields'] as List?) ?? const []) if (f is Map) RevisionSampleField.fromJson(asMap(f), optional: optional.contains('${f['field_id']}'))],
      written: _num(sum['written']),
      computed: _num(sum['computed']),
      consistent: sum['consistent'] is bool ? sum['consistent'] as bool : null,
      styles: styles,
      candidates: orderRevisionCandidates(_candidates(id['candidates'])),
      rosterReason: asMap(id['roster'])['reason']?.toString(),
      stripImage: _b64(id['strip_b64']),
      ruleFound: strip == null ? null : strip['rule_found'] == true,
    );
  }
}

/// One line of the side-by-side comparison of two reads of the same photo.
class SampleCompareRow {
  const SampleCompareRow({required this.label, this.before, this.after, this.confBefore, this.confAfter});
  final String label;
  final String? before, after;
  final double? confBefore, confAfter;

  bool get changed => before != after;
}

List<SampleCompareRow> compareSamples(RevisionSample before, RevisionSample after) {
  final prev = {for (final f in before.fields) f.fieldId: f};
  return [
    for (final f in after.fields)
      SampleCompareRow(label: f.label, before: prev[f.fieldId]?.value, after: f.value, confBefore: prev[f.fieldId]?.conf, confAfter: f.conf),
  ];
}

// ── the setup of a revision ───────────────────────────────────────────────────────────────────────────────────────

enum RevisionSource { gradebook, excel }

/// How a paper is linked to a student when it is not the template's own identifier.
class RevisionMatch {
  const RevisionMatch(this.source, [this.key]);
  final String source;
  final String? key;

  Map<String, dynamic> toJson() => {'source': source, 'key': ?key};

  @override
  bool operator ==(Object other) => other is RevisionMatch && other.source == source && other.key == key;

  @override
  int get hashCode => Object.hash(source, key);
}

/// The Data Lab's own student-number column: where an imported "seat number" column lands.
const kRevisionDataLabIdentifier = RevisionMatch('datalab', '__identifier');

/// Does this column name a seat number, in either language?
bool looksLikeSeatNumber(String label) {
  final s = label.toLowerCase();
  return s.contains('جلوس') || s.contains('seat') || s.contains('sitting');
}

/// What a number written on a slanted cover line should be matched on: a column named as a seat number, else the Data Lab's own
/// student number when it holds any. Null: the teacher's data does not say, and the screen asks them instead.
RevisionMatch? revisionSeatMatch({required int identifiers, required Iterable<({String key, String label})> columns}) {
  for (final c in columns) {
    if (looksLikeSeatNumber(c.label)) return RevisionMatch('datalab', c.key);
  }
  return identifiers > 0 ? kRevisionDataLabIdentifier : null;
}

/// The sheet column that names a seat number (never the degree column).
String? revisionSeatColumn(RevisionSheetPreview? sheet, {String? degreeColumn}) {
  for (final c in sheet?.columns ?? const <RevisionSheetColumn>[]) {
    if (c.name != degreeColumn && looksLikeSeatNumber(c.name)) return c.name;
  }
  return null;
}

class RevisionTemplateChoice {
  const RevisionTemplateChoice({required this.id, required this.name, required this.totalMax, required this.identifierSource, this.aspect = 1 / 1.414, this.identifierBox, this.strip, this.optionalFields = const {}});
  final int id;
  final String name;
  final double totalMax;

  /// The template's own identifier: qr | name | national_id | academic_id | … ('' when it has none).
  final String identifierSource;
  final double aspect;
  final Rect? identifierBox;

  /// The identifier is written on a printed line at an angle.
  final MarkStrip? strip;

  /// The marks the template lets stay empty.
  final Set<String> optionalFields;

  /// A handwritten name: never links by itself.
  bool get nameOnly => identifierSource == 'name';

  /// A template that reads a number can be matched against another list; a QR code or a name cannot (`match_not_digits`).
  bool get canOverrideMatch => identifierSource.isNotEmpty && identifierSource != 'qr' && identifierSource != 'name';
}

/// Everything the wizard collects; the steps read and fill it, and it says what is still missing.
class RevisionSetup {
  RevisionSource? source;
  int? courseId;
  GradeColumn? column;
  RevisionSheetPreview? sheet;
  String? matchColumn, degreeColumn;

  /// The sheet's own scale ("out of"); null = the paper's total.
  double? sheetMax;
  RevisionTemplateChoice? template;
  RevisionMatch? match;
  double step = 0.5;
  RevisionStyles styles = const RevisionStyles();

  /// The teacher chose what to match on themselves: the screen stops steering.
  bool matchTouched = false;

  bool get usesStrip => template?.strip != null;

  /// The scale of the place the degrees are compared with, while there is no template yet (a sheet's may be unset).
  double? get columnScale => source == RevisionSource.excel ? sheetMax : column?.max;

  bool get sourceReady => switch (source) {
        RevisionSource.gradebook => courseId != null && column != null,
        RevisionSource.excel => sheet != null && (matchColumn ?? '').isNotEmpty && (degreeColumn ?? '').isNotEmpty,
        null => false,
      };

  bool get templateReady => template != null;

  /// The scale the degrees are compared on.
  double? get targetMax => source == RevisionSource.excel ? (sheetMax ?? template?.totalMax) : column?.max;

  bool get converts {
    final a = template?.totalMax, b = targetMax;
    return a != null && b != null && a > 0 && b > 0 && (a - b).abs() > 0.0001;
  }

  /// A sheet source picks its own match column; a template that reads a QR code or a name has nothing to override.
  bool get matchIsFixed => source == RevisionSource.excel || !(template?.canOverrideMatch ?? false);

  /// Applies the guesses of a fresh sheet preview: the server's pick is preselected, a person only corrects it.
  void adoptSheet(RevisionSheetPreview p) {
    sheet = p;
    matchColumn = p.guessFor('identifier');
    degreeColumn = p.guessFor('degree');
    if (matchColumn == degreeColumn) degreeColumn = null;
    sheetMax = null;
  }

  /// The body of `POST /mark-sessions`.
  Map<String, dynamic> createBody({int? examId}) {
    final excel = source == RevisionSource.excel;
    return {
      'mode': 'review',
      'template_id': template!.id,
      'source': excel ? 'excel' : 'gradebook',
      'course_id': ?courseId,
      'exam_id': ?examId,
      if (!excel) 'column_key': column!.key,
      if (excel) 'sheet_key': sheet!.sheetKey,
      if (excel) 'sheet_match_column': matchColumn,
      if (excel) 'sheet_degree_column': degreeColumn,
      if (excel && sheetMax != null) 'sheet_max': sheetMax,
      if (!excel && match != null) 'match': match!.toJson(),
      if (converts) 'rounding_step': step,
      'styles': styles.toJson(),
    };
  }
}

// ── a session as the run needs it ─────────────────────────────────────────────────────────────────────────────────

class RevisionCounts {
  const RevisionCounts({this.match = 0, this.mismatch = 0, this.unreadable = 0, this.pending = 0, this.applied = 0, this.kept = 0, this.dismissed = 0, this.pages = 0, this.rejected = 0, this.failed = 0});
  final int match, mismatch, unreadable, pending, applied, kept, dismissed, pages, rejected, failed;

  /// Papers that still wait for a person.
  int get open => mismatch + unreadable;

  factory RevisionCounts.fromJson(Object? v) {
    final j = asMap(v);
    return RevisionCounts(
      match: asInt(j['match']),
      mismatch: asInt(j['mismatch']),
      unreadable: asInt(j['unreadable']),
      pending: asInt(j['pending']),
      applied: asInt(j['applied']),
      kept: asInt(j['kept']),
      dismissed: asInt(j['dismissed']),
      pages: asInt(j['pages']),
      rejected: asInt(j['rejected']),
      failed: asInt(j['failed']),
    );
  }
}

/// `GET /mark-sessions/{sid}` with what [MarkSession] does not carry: the source, the sheet, all the counts.
class RevisionSession {
  const RevisionSession({required this.session, this.excel = false, this.counts = const RevisionCounts(), this.degreeColumn, this.matchColumn, this.hubServer = false});
  final MarkSession session;
  final bool excel;
  final RevisionCounts counts;
  final String? degreeColumn, matchColumn;

  /// The server knows the revision routes (`source` is in its answer); an older one sends rows by open status only.
  final bool hubServer;

  int get id => session.id;

  /// The column's name as a person says it (`sheet:<name>` is only how an excel session stores it).
  String get columnLabel => degreeColumn ?? revisionColumnLabel(session.columnKey);

  factory RevisionSession.fromJson(Map<String, dynamic> j) {
    final s = j['session'] is Map ? asMap(j['session']) : j;
    final sheet = asMap(s['sheet']);
    return RevisionSession(
      session: MarkSession.fromJson(j),
      excel: '${s['source'] ?? ''}' == 'excel',
      counts: RevisionCounts.fromJson(j['counts'] ?? s['counts']),
      degreeColumn: sheet['degree_column']?.toString(),
      matchColumn: sheet['match_column']?.toString(),
      hubServer: s.containsKey('source'),
    );
  }
}

String revisionColumnLabel(String key) => key.startsWith('sheet:') ? key.substring(6) : key;

/// A row of the session with what [MarkRow] does not carry: its list and the name a handwritten paper suggests.
class RevisionRow {
  const RevisionRow({required this.row, required this.list, this.candidateId, this.candidateName, this.candidates = const [], this.rosterReason, this.identifierCropUrl});
  final MarkRow row;
  final MarkList list;
  final int? candidateId;
  final String? candidateName;

  /// The closest students, already in the order they are offered.
  final List<RevisionCandidate> candidates;
  final String? rosterReason;

  /// The signed picture of the straightened number; null for a national id, a phone, an e-mail.
  final String? identifierCropUrl;

  int get id => row.id;
  int? get pageId => row.pageId;
  bool get decided => row.decided;

  /// Whose paper it is, is the one thing left for the person to say.
  bool get needsStudent => !row.hasStudent && !row.decided;

  /// What to offer: the reader's candidates, or the one a handwritten name suggests.
  List<RevisionCandidate> get choices => candidates.isNotEmpty || candidateId == null || (candidateName ?? '').isEmpty ? candidates : [RevisionCandidate(id: candidateId!, name: candidateName!, fromName: true)];

  factory RevisionRow.fromJson(Map<String, dynamic> j) {
    final ident = asMap(j['identifier']);
    final cand = asMap(ident['candidate']);
    final crop = '${ident['crop_url'] ?? ''}';
    return RevisionRow(
      row: MarkRow.fromJson(j),
      list: switch ('${j['list'] ?? ''}') { 'match' => MarkList.match, 'mismatch' => MarkList.mismatch, _ => MarkList.unreadable },
      candidateId: cand['id'] == null ? null : asInt(cand['id']),
      candidateName: cand['name']?.toString(),
      candidates: orderRevisionCandidates(_candidates(ident['candidates'])),
      rosterReason: asMap(ident['roster'])['reason']?.toString(),
      identifierCropUrl: crop.isEmpty ? null : crop,
    );
  }
}

/// `GET …/pages/{id}/row`.
class RevisionPageRead {
  const RevisionPageRead({required this.ready, this.rejected = false, this.row, this.code = '', this.message = ''});
  final bool ready, rejected;
  final RevisionRow? row;
  final String code, message;

  factory RevisionPageRead.fromJson(Map<String, dynamic> j, {String lang = 'ar'}) {
    final en = '${j['message_en'] ?? ''}', ar = '${j['message'] ?? ''}';
    return RevisionPageRead(
      ready: j['ready'] == true,
      rejected: j['rejected'] == true,
      row: j['row'] is Map ? RevisionRow.fromJson(asMap(j['row'])) : null,
      code: '${j['code'] ?? ''}',
      message: lang == 'en' ? (en.isNotEmpty ? en : ar) : (ar.isNotEmpty ? ar : en),
    );
  }
}

// ── history ───────────────────────────────────────────────────────────────────────────────────────────────────────

class RevisionHistoryItem {
  const RevisionHistoryItem({required this.id, required this.action, this.rowId, this.studentName, this.old, this.next, this.reason, this.byName, this.at});
  final int id;
  final int? rowId;
  final String action;
  final String? studentName, reason, byName;
  final Object? old, next;
  final DateTime? at;

  factory RevisionHistoryItem.fromJson(Map<String, dynamic> j) {
    final st = asMap(j['student']);
    final r = '${j['reason'] ?? ''}'.trim();
    return RevisionHistoryItem(
      id: asInt(j['id']),
      rowId: j['row_id'] == null ? null : asInt(j['row_id']),
      action: '${j['action'] ?? ''}',
      studentName: st['name']?.toString(),
      old: j['old'],
      next: j['new'],
      reason: r.isEmpty ? null : r,
      byName: j['by_name']?.toString(),
      at: parseEngineUtc(j['at']),
    );
  }
}

class RevisionHistoryPage {
  const RevisionHistoryPage(this.items, this.nextBefore);
  final List<RevisionHistoryItem> items;
  final int? nextBefore;

  factory RevisionHistoryPage.fromJson(Map<String, dynamic> j) => RevisionHistoryPage(
        [for (final i in (j['items'] as List?) ?? const []) if (i is Map) RevisionHistoryItem.fromJson(asMap(i))],
        j['next_before'] == null ? null : asInt(j['next_before']),
      );
}

String revisionActionLabel(String action) => switch (action) {
      'apply' => t('حُدّثت الدرجة', 'Grade updated'),
      'keep' => t('تم التجاهل وبقيت الدرجة', 'Ignored, grade kept'),
      'dismiss' => t('استُبعدت الورقة', 'Paper set aside'),
      'retake' => t('طُلبت إعادة التصوير', 'Scan to be retaken'),
      'assign_student' => t('رُبطت بطالب', 'Linked to a student'),
      'fix_marks' => t('صُحّحت قراءة درجة', 'A mark was corrected'),
      _ => action,
    };

String _value(Object? v) {
  if (v == null || '$v'.isEmpty) return '—';
  final n = v is num ? v.toDouble() : double.tryParse('$v');
  return n == null ? '$v' : markNumberText(n);
}

/// "12 → 15" for a grade or a corrected mark; empty when the action changes no number (keep, retake, assign).
String revisionChangeText(RevisionHistoryItem i) {
  if (i.action == 'apply') return '${_value(i.old)} → ${_value(i.next)}';
  if (i.action == 'fix_marks' && i.old is Map && i.next is Map) {
    final o = asMap(i.old), n = asMap(i.next);
    return [for (final k in n.keys) '${_value(o[k])} → ${_value(n[k])}'].join(' · ');
  }
  return '';
}

// ── results that arrive while the next paper is being shot ────────────────────────────────────────────────────────

/// One paper that needs the person: a difference, something unreadable, or a page the reader refused afterwards.
class RevisionAttention {
  RevisionAttention({required this.pageId, this.photo, this.row, this.code = '', this.message = ''});
  final int pageId;
  Uint8List? photo;
  RevisionRow? row;
  final String code, message;

  /// Set after a 409 `value_changed`: the value the record holds now, shown before asking again.
  double? changedTo;

  bool get rejected => row == null;
}

enum RevisionReadKind { stillReading, matched, needsYou, nothing }

/// The order of a running session. The camera never waits for a result, so results land while the next paper is being
/// framed. The rule: a match is only ever a quiet line; anything that needs the person waits in a first-in-first-out
/// queue and is shown ONE at a time, only while the camera is between papers. [showing] is what holds the camera.
class RevisionFlow {
  /// Photos kept for the frozen scan behind a result; older ones are dropped (the crops still come from the server).
  static const maxPhotos = 12;

  final _waiting = <int, Uint8List?>{};
  final queue = <RevisionAttention>[];

  /// Papers the person chose to decide later: still open on the server, offered again on the summary.
  final later = <RevisionAttention>[];

  /// A result is on screen.
  bool showing = false;

  /// Pages sent and not read yet, oldest first.
  List<int> get waiting => _waiting.keys.toList();

  RevisionAttention? get current => queue.isEmpty ? null : queue.first;

  void shot(int pageId, Uint8List? photo) {
    _waiting[pageId] = photo;
    _trim();
  }

  /// The answer of `…/pages/{id}/row` for a page this session sent.
  RevisionReadKind take(int pageId, RevisionPageRead read) {
    if (!_waiting.containsKey(pageId) || !read.ready) return RevisionReadKind.stillReading;
    final photo = _waiting.remove(pageId);
    if (read.rejected) {
      queue.add(RevisionAttention(pageId: pageId, photo: photo, code: read.code, message: read.message));
      return RevisionReadKind.needsYou;
    }
    final r = read.row;
    if (r == null || r.decided) return RevisionReadKind.nothing;
    if (r.list == MarkList.match) return RevisionReadKind.matched;
    queue.add(RevisionAttention(pageId: pageId, photo: photo, row: r));
    return RevisionReadKind.needsYou;
  }

  /// May the next result be drawn now? Never while a shot is under way or the person is steadying a paper.
  bool canPresent({required bool cameraBusy}) => !showing && queue.isNotEmpty && !cameraBusy;

  void removeCurrent() {
    if (queue.isNotEmpty) queue.removeAt(0);
    showing = false;
  }

  void deferCurrent() {
    if (queue.isNotEmpty) later.add(queue.removeAt(0));
    showing = false;
  }

  /// The server answered a new row for the paper on screen (mark fixed, student assigned, value changed): true when it
  /// no longer needs anyone (it became a clean match or was decided), false when the same paper stays on screen.
  bool update(RevisionRow row) {
    final a = current;
    if (a == null) return false;
    if (row.decided || row.list == MarkList.match) {
      removeCurrent();
      return true;
    }
    a.row = row;
    return false;
  }

  void _trim() {
    final all = [...queue, ...later];
    var kept = _waiting.values.where((p) => p != null).length + all.where((a) => a.photo != null).length;
    for (final a in all) {
      if (kept <= maxPhotos) break;
      if (a.photo != null) {
        a.photo = null;
        kept--;
      }
    }
    for (final k in _waiting.keys.toList()) {
      if (kept <= maxPhotos) break;
      if (_waiting[k] != null) {
        _waiting[k] = null;
        kept--;
      }
    }
  }
}

/// The session's papers in capture order, updated as results come in, for the arrows.
List<RevisionRow> upsertRow(List<RevisionRow> rows, RevisionRow row) {
  final out = [...rows];
  final i = out.indexWhere((r) => r.id == row.id);
  if (i >= 0) {
    out[i] = row;
  } else {
    out.add(row);
    out.sort((a, b) => a.id.compareTo(b.id));
  }
  return out;
}

/// The summary's headline numbers (the Finish screen and the tests).
({int matched, int updated, int ignored, int unreadable, int differ}) revisionSummary(RevisionCounts c) =>
    (matched: c.match, updated: c.applied, ignored: c.kept, unreadable: c.unreadable, differ: c.mismatch);
