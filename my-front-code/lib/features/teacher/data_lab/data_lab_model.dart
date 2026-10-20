// lib/features/shared/data_lab/data_lab_models.dart
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
  });

  final bool enabled, studentView, allowImport, allowExport, allowEmailExport;
  final bool allowCreateAccounts, allowStudentRequests, allowCertificates;
  final int maxImportRows, maxCustomColumns;
  final List<String> exportFormats;

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
  );
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
    this.position = 0,
    this.expr,
    this.display,
  });

  final int id;
  final String key, label, kind, dataType;
  final String? source;

  /// Excel-style formula written with column KEYS ({quiz_1}); see data_lab_formula.dart.
  final String? expr;

  /// How this column is drawn: 'value' | 'bar' | 'both' (null = follow the sheet's default).
  final String? display;

  bool get hasExpr => isCalculated && expr != null && expr!.trim().isNotEmpty;

  /// calculated columns: [{key, weight}]
  final List<Map<String, dynamic>> inputs;
  final String missing;
  final List<String> options;
  final double maxValue;
  final bool visibleToStudents, isHidden;
  final int position;

  bool get isNumber => dataType == 'number';
  bool get isCalculated => kind == 'calculated';
  bool get isBuiltin => kind == 'builtin';
  bool get isCustom => kind == 'custom';

  DlColumn copyWith({String? label, bool? visibleToStudents, bool? isHidden}) => DlColumn(
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
    position: position,
    expr: expr,
    display: display,
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
      position: (j['position'] as num?)?.toInt() ?? 0,
      expr: f['expr'] is String && (f['expr'] as String).trim().isNotEmpty ? f['expr'] as String : null,
      display: j['display'] as String?,
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
  const DlStat({this.avg, this.min, this.max, this.filled = 0});

  final double? avg, min, max;
  final int filled;

  factory DlStat.fromJson(Map<String, dynamic> j) => DlStat(
    avg: dlNum(j['avg']),
    min: dlNum(j['min']),
    max: dlNum(j['max']),
    filled: (j['filled'] as num?)?.toInt() ?? 0,
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
  List<String> get newColumns => (raw['new_columns'] as List?)?.map((e) => '$e').toList() ?? [];
  List<Map<String, dynamic>> get missingFields => dlList(raw['missing_fields']);
  List<Map<String, dynamic>> get errors => dlList(raw['errors']);
  List<Map<String, dynamic>> get credentials => dlList(raw['credentials']);
  List<Map<String, dynamic>> get unmatchedPreview => dlList(raw['unmatched_preview']);
  bool get needsName => missingFields.any((m) => m['field'] == 'name');
  bool get needsContact => missingFields.any((m) => m['field'] == 'contact');
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
  });

  final int requestId;
  final String courseTitle, title, inputType;
  final List<String> options;

  bool get isDropdown => inputType == 'dropdown';

  factory DlPendingRequest.fromJson(Map<String, dynamic> j) => DlPendingRequest(
    requestId: (j['request_id'] as num).toInt(),
    courseTitle: '${j['course_title'] ?? ''}',
    title: '${j['title'] ?? ''}',
    inputType: '${j['input_type'] ?? 'text'}',
    options: (j['options'] as List?)?.map((e) => '$e').toList() ?? [],
  );
}

class DlRequestInfo {
  DlRequestInfo({
    required this.id,
    required this.title,
    required this.inputType,
    required this.isActive,
    required this.answered,
    required this.total,
  });

  final int id, answered, total;
  final String title, inputType;
  final bool isActive;

  factory DlRequestInfo.fromJson(Map<String, dynamic> j) => DlRequestInfo(
    id: (j['id'] as num).toInt(),
    title: '${j['title']}',
    inputType: '${j['input_type']}',
    isActive: j['is_active'] == true,
    answered: (j['answered'] as num?)?.toInt() ?? 0,
    total: (j['total'] as num?)?.toInt() ?? 0,
  );
}
