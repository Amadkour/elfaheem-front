// lib/features/data_lab/data_lab_models.dart
// Plain Dart models of the Data Lab API (no Flutter import on purpose).
library;

double? dlNum(dynamic v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

/// 83 → "83", 83.5 → "83.5"; null → "–"
String dlFmt(dynamic v, {String empty = '–'}) {
  if (v == null) return empty;
  if (v is num) {
    final d = v.toDouble();
    return d == d.roundToDouble() ? '${d.toInt()}' : d.toStringAsFixed(1);
  }
  final s = '$v'.trim();
  return s.isEmpty ? empty : s;
}

Map<String, dynamic> dlMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> dlList(dynamic v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

// ── config ───────────────────────────────────────────────────────────────────

class DlConfig {
  const DlConfig({
    this.enabled = true,
    this.studentView = true,
    this.allowImport = true,
    this.allowExport = true,
    this.allowEmailExport = true,
    this.allowCreateAccounts = true,
    this.allowStudentRequests = true,
    this.allowCertificates = true,
    this.maxImportRows = 2000,
    this.maxCustomColumns = 30,
    this.exportFormats = const ['xlsx', 'csv', 'pdf'],
    this.passPercent = 50,
  });

  final bool enabled, studentView, allowImport, allowExport, allowEmailExport;
  final bool allowCreateAccounts, allowStudentRequests, allowCertificates;
  final int maxImportRows, maxCustomColumns;
  final List<String> exportFormats;

  /// Default pass mark (% of a column's full mark) set by the admin — used by the stats and the certificates.
  final double passPercent;

  factory DlConfig.fromJson(Map<String, dynamic> j) => DlConfig(
    enabled: j['enabled'] != false,
    studentView: j['student_view'] != false,
    allowImport: j['allow_import'] != false,
    allowExport: j['allow_export'] != false,
    allowEmailExport: j['allow_email_export'] != false,
    allowCreateAccounts: j['allow_create_accounts'] != false,
    allowStudentRequests: j['allow_student_requests'] != false,
    allowCertificates: j['allow_certificates'] != false,
    maxImportRows: (j['max_import_rows'] as num?)?.toInt() ?? 2000,
    maxCustomColumns: (j['max_custom_columns'] as num?)?.toInt() ?? 30,
    exportFormats: (j['export_formats'] as List?)?.map((e) => '$e').toList() ?? const ['xlsx', 'csv', 'pdf'],
    passPercent: dlNum(j['pass_percent']) ?? 50,
  );
}

// ── column style: colour, font, alignment, highlight rules ─────────────────

/// Colours are stored as a theme name (primary, success, warning, danger, purple, accent, accent2) — so they follow
/// the app theme and dark mode — or as '#RRGGBB'.
const dlStyleColors = ['primary', 'success', 'warning', 'danger', 'purple', 'accent', 'accent2', '#3B82F6', '#14B8A6', '#F97316', '#EC4899', '#64748B'];

/// Fonts the teacher can pick (bundled with the app). null = the sheet's default.
const dlStyleFonts = <String?>[null, 'tajawal', 'bahji'];

/// One highlight rule. The first rule that matches a cell colours it.
///   cmp     : this cell  <op>  a   (op: > >= < <= = <> between contains)   — numbers, or text for = <> contains
///   empty   : the cell is empty          filled : the cell has a value
///   formula : any formula (column names in [ ], [@] = this cell) that is true (≠ 0 / not empty)
class DlRule {
  const DlRule({required this.type, this.op = '>=', this.a, this.b, this.expr, this.bg = 'danger', this.fg, this.bold = false});

  final String type, op;
  final String? a, b, expr, bg, fg;
  final bool bold;

  DlRule copyWith({String? type, String? op, String? a, String? b, String? expr, String? bg, String? fg, bool? bold, bool clearFg = false}) => DlRule(
    type: type ?? this.type,
    op: op ?? this.op,
    a: a ?? this.a,
    b: b ?? this.b,
    expr: expr ?? this.expr,
    bg: bg ?? this.bg,
    fg: clearFg ? null : (fg ?? this.fg),
    bold: bold ?? this.bold,
  );

  factory DlRule.fromJson(Map<String, dynamic> j) => DlRule(
    type: '${j['type'] ?? 'cmp'}',
    op: '${j['op'] ?? '>='}',
    a: j['a']?.toString(),
    b: j['b']?.toString(),
    expr: j['expr'] as String?,
    bg: j['bg'] as String?,
    fg: j['fg'] as String?,
    bold: j['bold'] == true,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'op': op,
    'a': ?a,
    'b': ?b,
    'expr': ?expr,
    'bg': ?bg,
    'fg': ?fg,
    if (bold) 'bold': true,
  };
}

class DlColumnStyle {
  const DlColumnStyle({
    this.color,
    this.font,
    this.size = 1.0,
    this.bold = false,
    this.align,
    this.scale = false,
    this.rules = const [],
    this.cells = const {},
  });

  /// Tint of the whole column (title + cells).
  final String? color;
  final String? font;

  /// Text size factor: 0.9 small · 1 normal · 1.15 large.
  final double size;
  final bool bold;

  /// start | center | end (null = the sheet's default).
  final String? align;

  /// Colour scale on numbers: low = red → middle = amber → high = green (of the column's full mark).
  final bool scale;
  final List<DlRule> rules;

  /// Cells highlighted by hand: row id → colour.
  final Map<int, String> cells;

  bool get isEmpty => color == null && font == null && size == 1.0 && !bold && align == null && !scale && rules.isEmpty && cells.isEmpty;

  DlColumnStyle copyWith({
    String? color,
    String? font,
    double? size,
    bool? bold,
    String? align,
    bool? scale,
    List<DlRule>? rules,
    Map<int, String>? cells,
    bool clearColor = false,
    bool clearFont = false,
    bool clearAlign = false,
  }) =>
      DlColumnStyle(
        color: clearColor ? null : (color ?? this.color),
        font: clearFont ? null : (font ?? this.font),
        size: size ?? this.size,
        bold: bold ?? this.bold,
        align: clearAlign ? null : (align ?? this.align),
        scale: scale ?? this.scale,
        rules: rules ?? this.rules,
        cells: cells ?? this.cells,
      );

  factory DlColumnStyle.fromJson(Map<String, dynamic> j) {
    if (j.isEmpty) return const DlColumnStyle();
    final cells = <int, String>{};
    dlMap(j['cells']).forEach((k, v) {
      final id = int.tryParse(k);
      if (id != null && v is String) cells[id] = v;
    });
    return DlColumnStyle(
      color: j['color'] as String?,
      font: j['font'] as String?,
      size: dlNum(j['size']) ?? 1.0,
      bold: j['bold'] == true,
      align: j['align'] as String?,
      scale: j['scale'] == true,
      rules: dlList(j['rules']).map(DlRule.fromJson).toList(),
      cells: cells,
    );
  }

  Map<String, dynamic> toJson() => {
    'color': ?color,
    'font': ?font,
    if (size != 1.0) 'size': size,
    if (bold) 'bold': true,
    'align': ?align,
    if (scale) 'scale': true,
    if (rules.isNotEmpty) 'rules': [for (final r in rules) r.toJson()],
    if (cells.isNotEmpty) 'cells': {for (final e in cells.entries) '${e.key}': e.value},
  };
}

// ── sheet ────────────────────────────────────────────────────────────────────

class DlColumn {
  DlColumn({
    required this.id,
    required this.key,
    required this.label,
    required this.kind,
    required this.dataType,
    this.source,
    this.inputs = const [],
    this.missing = 'zero',
    this.options = const [],
    this.maxValue = 100,
    this.visibleToStudents = false,
    this.isHidden = false,
    this.isLocked = false,
    this.position = 0,
    this.expr,
    this.display,
    this.style = const DlColumnStyle(),
  });

  final int id;
  final String key, label, kind, dataType;
  final String? source;

  /// Excel-style formula written with column KEYS ({quiz_1}); see data_lab_formula.dart.
  final String? expr;

  /// How this column is drawn: 'value' | 'bar' | 'both' (null = follow the sheet's default).
  final String? display;

  /// Colour, font, alignment, highlight rules and manually highlighted cells (shared by everyone on the sheet).
  final DlColumnStyle style;

  bool get hasExpr => isCalculated && expr != null && expr!.trim().isNotEmpty;

  /// calculated columns: [{key, weight}]
  final List<Map<String, dynamic>> inputs;
  final String missing;
  final List<String> options;
  final double maxValue;
  final bool visibleToStudents, isHidden;

  /// Approved results: the server refuses edits and imports until the teacher unlocks the column.
  final bool isLocked;
  final int position;

  bool get isNumber => dataType == 'number';
  bool get isCalculated => kind == 'calculated';
  bool get isBuiltin => kind == 'builtin';
  bool get isCustom => kind == 'custom';

  DlColumn copyWith({String? label, bool? visibleToStudents, bool? isHidden, bool? isLocked, String? display, DlColumnStyle? style}) => DlColumn(
    id: id,
    key: key,
    label: label ?? this.label,
    kind: kind,
    dataType: dataType,
    source: source,
    inputs: inputs,
    missing: missing,
    options: options,
    maxValue: maxValue,
    visibleToStudents: visibleToStudents ?? this.visibleToStudents,
    isHidden: isHidden ?? this.isHidden,
    isLocked: isLocked ?? this.isLocked,
    position: position,
    expr: expr,
    display: display ?? this.display,
    style: style ?? this.style,
  );

  /// 0–100 style columns get a coloured bar.
  bool get isPercent => isNumber && maxValue == 100 && source != 'read_flags' && source != 'review_flags';

  factory DlColumn.fromJson(Map<String, dynamic> j) {
    final f = dlMap(j['formula']);
    return DlColumn(
      id: (j['id'] as num?)?.toInt() ?? 0,
      key: '${j['key']}',
      label: '${j['label']}',
      kind: '${j['kind']}',
      dataType: '${j['data_type'] ?? 'number'}',
      source: j['source'] as String?,
      inputs: dlList(f['inputs']),
      missing: '${f['missing'] ?? 'zero'}',
      options: (j['options'] as List?)?.map((e) => '$e').toList() ?? const [],
      maxValue: dlNum(f['max']) ?? dlNum(j['max_value']) ?? 100,
      visibleToStudents: j['visible_to_students'] == true,
      isHidden: j['is_hidden'] == true,
      isLocked: j['is_locked'] == true,
      position: (j['position'] as num?)?.toInt() ?? 0,
      expr: f['expr'] is String && (f['expr'] as String).trim().isNotEmpty ? f['expr'] as String : null,
      display: j['display'] as String?,
      style: DlColumnStyle.fromJson(dlMap(j['style'])),
    );
  }
}

class DlRow {
  DlRow({
    required this.rowId,
    this.studentId,
    required this.name,
    this.email,
    this.phone,
    this.identifier,
    this.isTemporary = false,
    this.isStaged = false,
    required this.values,
    Set<String>? overridden,
  }) : overridden = overridden ?? <String>{};

  final int rowId;
  final int? studentId;
  final String name;
  final String? email, phone, identifier;
  final bool isTemporary, isStaged;
  Map<String, dynamic> values;

  /// Keys whose value the teacher typed over the automatic one.
  Set<String> overridden;

  factory DlRow.fromJson(Map<String, dynamic> j) => DlRow(
    rowId: (j['row_id'] as num).toInt(),
    studentId: (j['student_id'] as num?)?.toInt(),
    name: '${j['name'] ?? ''}',
    email: j['email'] as String?,
    phone: j['phone'] as String?,
    identifier: j['identifier'] as String?,
    isTemporary: j['is_temporary'] == true,
    isStaged: j['is_staged'] == true,
    values: dlMap(j['values']),
    overridden: (j['overridden'] as List?)?.map((e) => '$e').toSet(),
  );
}

class DlStat {
  const DlStat({
    this.avg,
    this.min,
    this.max,
    this.filled = 0,
    this.median,
    this.std,
    this.passCount = 0,
    this.passRate,
    this.buckets = const [],
  });

  final double? avg, min, max, median, std, passRate;
  final int filled, passCount;

  /// How many students fall in 0–20 %, 20–40 %, 40–60 %, 60–80 %, 80–100 % of the full mark.
  final List<int> buckets;

  factory DlStat.fromJson(Map<String, dynamic> j) => DlStat(
    avg: dlNum(j['avg']),
    min: dlNum(j['min']),
    max: dlNum(j['max']),
    filled: (j['filled'] as num?)?.toInt() ?? 0,
    median: dlNum(j['median']),
    std: dlNum(j['std']),
    passCount: (j['pass_count'] as num?)?.toInt() ?? 0,
    passRate: dlNum(j['pass_rate']),
    buckets: (j['buckets'] as List?)?.map((e) => (e as num?)?.toInt() ?? 0).toList() ?? const [],
  );
}

class DlGrid {
  DlGrid({
    required this.courseId,
    required this.title,
    required this.columns,
    required this.rows,
    required this.total,
    required this.studentsTotal,
    required this.summary,
    required this.config,
  });

  final int courseId;
  final String title;
  final List<DlColumn> columns;
  final List<DlRow> rows;
  final int total, studentsTotal;
  final Map<String, DlStat> summary;
  final DlConfig config;

  factory DlGrid.fromJson(Map<String, dynamic> j) {
    final course = dlMap(j['course']);
    return DlGrid(
      courseId: (course['id'] as num?)?.toInt() ?? 0,
      title: '${course['title'] ?? ''}',
      columns: dlList(j['columns']).map(DlColumn.fromJson).toList(),
      rows: dlList(j['rows']).map(DlRow.fromJson).toList(),
      total: (j['total'] as num?)?.toInt() ?? 0,
      studentsTotal: (j['students_total'] as num?)?.toInt() ?? 0,
      summary: dlMap(j['summary']).map((k, v) => MapEntry(k, DlStat.fromJson(dlMap(v)))),
      config: DlConfig.fromJson(dlMap(j['config'])),
    );
  }
}

// ── import ───────────────────────────────────────────────────────────────────

class DlImportHeader {
  DlImportHeader({required this.header, required this.target, required this.sample});

  final String header;
  String target;
  final List<String> sample;
}

class DlImportPreview {
  DlImportPreview({
    required this.importId,
    required this.filename,
    required this.rows,
    required this.headers,
    required this.shared,
    required this.suggestedMerge,
    required this.existingColumns,
    required this.allowCreateAccounts,
    required this.allowStudentRequests,
    required this.allowCertificates,
  });

  final String importId, filename;
  final int rows;
  final List<DlImportHeader> headers;
  final List<String> shared;
  final String? suggestedMerge;
  final List<DlColumn> existingColumns;
  final bool allowCreateAccounts, allowStudentRequests, allowCertificates;

  factory DlImportPreview.fromJson(Map<String, dynamic> j) => DlImportPreview(
    importId: '${j['import_id']}',
    filename: '${j['filename'] ?? ''}',
    rows: (j['rows'] as num?)?.toInt() ?? 0,
    headers: dlList(j['columns'])
        .map((h) => DlImportHeader(
      header: '${h['header']}',
      target: '${h['target']}',
      sample: (h['sample'] as List?)?.map((e) => '$e').toList() ?? [],
    ))
        .toList(),
    shared: (j['shared'] as List?)?.map((e) => '$e').toList() ?? [],
    suggestedMerge: j['suggested_merge'] as String?,
    existingColumns: dlList(j['existing_columns']).map(DlColumn.fromJson).toList(),
    allowCreateAccounts: j['allow_create_accounts'] != false,
    allowStudentRequests: j['allow_student_requests'] != false,
    allowCertificates: j['allow_certificates'] != false,
  );
}

class DlImportPlan {
  DlImportPlan(this.raw);

  final Map<String, dynamic> raw;

  int _i(String k) => (raw[k] as num?)?.toInt() ?? 0;

  int get total => _i('total_rows');
  int get matched => _i('matched');
  int get unmatched => _i('unmatched');
  int get emptyKey => _i('empty_key');
  int get ambiguous => _i('ambiguous');
  int get willCreateTemp => _i('will_create_temp');
  int get willCreateAccounts => _i('will_create_accounts');
  int get willStage => _i('will_stage');
  int get rowsMissingContact => _i('rows_missing_contact');
  int get cellsWritten => _i('cells_written');
  int get rejectedCells => _i('rejected_cells');

  /// [{label, type, max}] — a new number column gets the highest mark of the file as full mark when it is above 100.
  List<Map<String, dynamic>> get newColumnsDetail => dlList(raw['new_columns_detail']);
  List<String> get newColumns => (raw['new_columns'] as List?)?.map((e) => '$e').toList() ?? [];
  List<Map<String, dynamic>> get missingFields => dlList(raw['missing_fields']);
  List<Map<String, dynamic>> get errors => dlList(raw['errors']);
  List<Map<String, dynamic>> get credentials => dlList(raw['credentials']);
  List<Map<String, dynamic>> get unmatchedPreview => dlList(raw['unmatched_preview']);
  bool get needsName => missingFields.any((m) => m['field'] == 'name');
  bool get needsContact => missingFields.any((m) => m['field'] == 'contact');

  // "Add them to the course" (create_accounts)
  int get willEnrollExisting => _i('will_enroll_existing');
  int get willInviteEmail => _i('will_invite_email');
  int get willPhoneOnly => _i('will_phone_only');
  int get willSheetOnly => _i('will_sheet_only');
  int get skipped => _i('skipped');

  /// Lines with neither e-mail nor phone: [{row, name, identifier, email, phone, values}].
  List<Map<String, dynamic>> get needsContactLines => dlList(raw['needs_contact']);

  /// After the import: {enrolled_existing, invited, phone_only, sheet_only, left_out}.
  Map<String, dynamic> get result => dlMap(raw['result']);
  int resultOf(String k) => (result[k] as num?)?.toInt() ?? 0;
}

// ── profile ──────────────────────────────────────────────────────────────────

class DlExam {
  DlExam({required this.name, this.best, this.attempts = 0, this.passed});

  final String name;
  final double? best;
  final int attempts;
  final bool? passed;

  factory DlExam.fromJson(Map<String, dynamic> j) => DlExam(
    name: '${j['name'] ?? ''}',
    best: dlNum(j['best_percentage']),
    attempts: (j['attempts'] as num?)?.toInt() ?? 0,
    passed: j['passed'] as bool?,
  );
}

class DlProfileColumn {
  DlProfileColumn({
    required this.key,
    required this.label,
    required this.dataType,
    required this.kind,
    required this.maxValue,
    this.value,
    this.classAvg,
    this.visibleToStudents = false,
  });

  final String key, label, dataType, kind;
  final double maxValue;
  final dynamic value;
  final double? classAvg;
  final bool visibleToStudents;

  bool get isNumber => dataType == 'number';

  factory DlProfileColumn.fromJson(Map<String, dynamic> j) => DlProfileColumn(
    key: '${j['key']}',
    label: '${j['label']}',
    dataType: '${j['data_type'] ?? 'number'}',
    kind: '${j['kind']}',
    maxValue: dlNum(j['max_value']) ?? 100,
    value: j['value'],
    classAvg: dlNum(j['class_avg']),
    visibleToStudents: j['visible_to_students'] == true,
  );
}

class DlCourseBlock {
  DlCourseBlock({
    required this.courseId,
    required this.title,
    this.progress,
    this.attendance,
    this.attended = 0,
    this.held = 0,
    this.examAvg,
    required this.exams,
    this.reviewFlags = 0,
    this.readFlags = 0,
    required this.columns,
  });

  final int courseId;
  final String title;
  final double? progress, attendance, examAvg;
  final int attended, held, reviewFlags, readFlags;
  final List<DlExam> exams;
  final List<DlProfileColumn> columns;

  /// Data Lab columns that are not already shown as a dedicated ring / list.
  List<DlProfileColumn> get extraColumns => columns
      .where((c) => !const {'progress', 'attendance', 'exam_avg', 'read_flags', 'review_flags'}.contains(c.key) &&
      !c.key.startsWith('exam_'))
      .toList();

  factory DlCourseBlock.fromJson(Map<String, dynamic> j) {
    final course = dlMap(j['course']);
    final att = dlMap(j['attendance']);
    final ex = dlMap(j['exams']);
    final fl = dlMap(j['flags']);
    return DlCourseBlock(
      courseId: (course['id'] as num?)?.toInt() ?? 0,
      title: '${course['title'] ?? ''}',
      progress: dlNum(j['progress']),
      attendance: dlNum(att['rate']),
      attended: (att['attended'] as num?)?.toInt() ?? 0,
      held: (att['held'] as num?)?.toInt() ?? 0,
      examAvg: dlNum(ex['avg']),
      exams: dlList(ex['items']).map(DlExam.fromJson).toList(),
      reviewFlags: (fl['review'] as num?)?.toInt() ?? 0,
      readFlags: (fl['read'] as num?)?.toInt() ?? 0,
      columns: dlList(j['columns']).map(DlProfileColumn.fromJson).toList(),
    );
  }
}

class DlProfile {
  DlProfile({
    required this.studentId,
    required this.name,
    this.email,
    this.phone,
    this.imageUrl,
    this.progress,
    this.attendance,
    this.examAvg,
    this.reviewFlags = 0,
    this.readFlags = 0,
    required this.courses,
  });

  final int studentId;
  final String name;
  final String? email, phone, imageUrl;
  final double? progress, attendance, examAvg;
  final int reviewFlags, readFlags;
  final List<DlCourseBlock> courses;

  factory DlProfile.fromJson(Map<String, dynamic> j) {
    final s = dlMap(j['student']);
    final o = dlMap(j['overall']);
    return DlProfile(
      studentId: (s['id'] as num?)?.toInt() ?? 0,
      name: '${s['name'] ?? ''}',
      email: s['email'] as String?,
      phone: s['phone'] as String?,
      imageUrl: s['image_url'] as String?,
      progress: dlNum(o['progress']),
      attendance: dlNum(o['attendance']),
      examAvg: dlNum(o['exam_avg']),
      reviewFlags: (o['review_flags'] as num?)?.toInt() ?? 0,
      readFlags: (o['read_flags'] as num?)?.toInt() ?? 0,
      courses: dlList(j['courses']).map(DlCourseBlock.fromJson).toList(),
    );
  }
}

// ── requests ─────────────────────────────────────────────────────────────────

class DlPendingRequest {
  DlPendingRequest({
    required this.requestId,
    required this.courseTitle,
    required this.title,
    required this.inputType,
    required this.options,
    this.courseId = 0,
    this.formKey = '',
    this.formTitle = '',
    this.position = 0,
    this.maxValue,
  });

  final int requestId, courseId, position;
  final String courseTitle, title, inputType, formKey, formTitle;
  final List<String> options;
  final double? maxValue;

  bool get isDropdown => inputType == 'dropdown';
  bool get isNumber => inputType == 'number';

  factory DlPendingRequest.fromJson(Map<String, dynamic> j) => DlPendingRequest(
    requestId: (j['request_id'] as num).toInt(),
    courseId: (j['course_id'] as num?)?.toInt() ?? 0,
    courseTitle: '${j['course_title'] ?? ''}',
    title: '${j['title'] ?? ''}',
    inputType: '${j['input_type'] ?? 'text'}',
    options: (j['options'] as List?)?.map((e) => '$e').toList() ?? [],
    formKey: '${j['form_key'] ?? 'q${j['request_id']}'}',
    formTitle: '${j['form_title'] ?? ''}',
    position: (j['position'] as num?)?.toInt() ?? 0,
    maxValue: dlNum(j['max_value']),
  );
}

/// The questions of one form, as the student sees them on ONE screen.
class DlPendingForm {
  DlPendingForm(this.questions);

  final List<DlPendingRequest> questions;

  String get key => questions.first.formKey;
  String get courseTitle => questions.first.courseTitle;
  String get title => questions.first.formTitle;

  /// Pending questions grouped by form (order kept).
  static List<DlPendingForm> group(List<DlPendingRequest> items) {
    final map = <String, List<DlPendingRequest>>{};
    for (final q in items) {
      map.putIfAbsent('${q.courseId}|${q.formKey}', () => []).add(q);
    }
    return [
      for (final l in map.values) DlPendingForm(l..sort((a, b) => a.position.compareTo(b.position))),
    ];
  }
}

class DlRequestInfo {
  DlRequestInfo({
    required this.id,
    required this.title,
    required this.inputType,
    required this.isActive,
    required this.answered,
    required this.total,
    this.isMergeKey = false,
    this.createdAt,
    this.formKey = '',
    this.formTitle = '',
    this.position = 0,
    this.columnKey,
    this.columnLabel,
    this.options = const [],
  });

  final int id, answered, total, position;
  final String title, inputType, formKey, formTitle;
  final bool isActive, isMergeKey;
  final DateTime? createdAt;
  final String? columnKey, columnLabel;
  final List<String> options;

  int get waiting {
    final w = total - answered;
    return w < 0 ? 0 : w;
  }

  DlRequestInfo copyWith({bool? isActive}) => DlRequestInfo(
    id: id,
    title: title,
    inputType: inputType,
    isActive: isActive ?? this.isActive,
    answered: answered,
    total: total,
    isMergeKey: isMergeKey,
    createdAt: createdAt,
    formKey: formKey,
    formTitle: formTitle,
    position: position,
    columnKey: columnKey,
    columnLabel: columnLabel,
    options: options,
  );

  factory DlRequestInfo.fromJson(Map<String, dynamic> j) => DlRequestInfo(
    id: (j['id'] as num).toInt(),
    title: '${j['title']}',
    inputType: '${j['input_type']}',
    isActive: j['is_active'] == true,
    answered: (j['answered'] as num?)?.toInt() ?? 0,
    total: (j['total'] as num?)?.toInt() ?? 0,
    isMergeKey: j['is_merge_key'] == true,
    createdAt: DateTime.tryParse('${j['created_at'] ?? ''}')?.toLocal(),
    formKey: '${j['form_key'] ?? 'q${j['id']}'}',
    formTitle: '${j['form_title'] ?? ''}',
    position: (j['position'] as num?)?.toInt() ?? 0,
    columnKey: j['column_key'] as String?,
    columnLabel: j['column_label'] as String?,
    options: (j['options'] as List?)?.map((e) => '$e').toList() ?? const [],
  );
}

/// The questions of one form, for the teacher.
class DlRequestForm {
  DlRequestForm(this.questions);

  final List<DlRequestInfo> questions;

  String get key => questions.first.formKey;
  String get title => questions.first.formTitle.isNotEmpty ? questions.first.formTitle : questions.first.title;
  DateTime? get createdAt => questions.first.createdAt;
  int get activeCount => questions.where((q) => q.isActive).length;
  bool get isMergeKey => questions.any((q) => q.isMergeKey);

  /// Students still missing at least one active answer (the biggest gap of an active question).
  int get waiting => questions.where((q) => q.isActive).fold(0, (m, q) => q.waiting > m ? q.waiting : m);
  int get total => questions.isEmpty ? 0 : questions.first.total;

  static List<DlRequestForm> group(List<DlRequestInfo> items) {
    final map = <String, List<DlRequestInfo>>{};
    for (final q in items) {
      map.putIfAbsent(q.formKey, () => []).add(q);
    }
    final out = [for (final l in map.values) DlRequestForm(l..sort((a, b) => a.position.compareTo(b.position)))];
    out.sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
    return out;
  }
}

// ── change history ───────────────────────────────────────────────────────────

class DlAuditEntry {
  DlAuditEntry({
    required this.id,
    required this.action,
    this.rowId,
    this.rowLabel,
    this.columnKey,
    this.columnLabel,
    this.oldValue,
    this.newValue,
    this.note,
    this.user = '',
    this.at,
  });

  final int id;

  /// cell | import | column_create | column_update | column_delete | lock | unlock | row_delete | request |
  /// certificates | publish
  final String action;
  final int? rowId;
  final String? rowLabel, columnKey, columnLabel, oldValue, newValue, note;
  final String user;
  final DateTime? at;

  factory DlAuditEntry.fromJson(Map<String, dynamic> j) => DlAuditEntry(
    id: (j['id'] as num?)?.toInt() ?? 0,
    action: '${j['action'] ?? ''}',
    rowId: (j['row_id'] as num?)?.toInt(),
    rowLabel: j['row_label'] as String?,
    columnKey: j['column_key'] as String?,
    columnLabel: j['column_label'] as String?,
    oldValue: j['old'] as String?,
    newValue: j['new'] as String?,
    note: j['note'] as String?,
    user: '${j['user'] ?? ''}',
    at: DateTime.tryParse('${j['at'] ?? ''}')?.toLocal(),
  );
}
