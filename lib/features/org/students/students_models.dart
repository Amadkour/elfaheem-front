// lib/features/org/students/students_models.dart — plain parse classes and pure rules of the Students section
// (student lifecycle contract §1, §3, §4). No widgets, no network.
//
//   vocabulary     the enums of §1 and their bilingual labels (enrolText, standingText, flagText, intakeText,
//                  memberStatusText, accessSectionText): every enum value has a label (test/org/students_models_test.dart)
//   intakeLabel    §3.1, the onboarding case → one word
//   studentChip    §3.2, THE one chip of a student; chipTone its tone
//   StudentRow     §3.3 (also the `student` block of GET …/file)
//   StudentsPageData / StudentsSummary / StudentsCan / StudentsQuery     GET /students (§4.1)
//   StudentMissing / MissingItem                                          GET …/missing (§4.4)
//   StudentAccessLog / AccessLogEntry                                     GET …/access-log (§4.5)
//
// Times are naive UTC on the server: read with orgParseUtc, show with AppTime. Every parser is lenient (a missing
// key gives a default) so an older or newer server never breaks the page.
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_badges.dart' show AppTone;

import '../../admin/admin_common.dart' show t, asMap, asMapList, asInt, asStr, asBool;
import '../org_v3.dart' show orgParseUtc;

// ═════════════════════════════════════════════════════════════════════════════
//  Vocabulary (§1)
// ═════════════════════════════════════════════════════════════════════════════

/// The kill switch of the whole section (`feature_catalog.py`, §12).
const kStudentsFeatureKey = 'org.students';

/// The kill switch of the missing-data badge (the app hides the badge).
const kStudentsMissingKey = 'org.students.missing';

const enrolStatuses = [
  'enrolled', 'suspended', 'postponed', 'disc_suspended', 'outside', 'withdrawn', 'cancelled', 'dismissed',
  'transferred_out', 'graduated', 'deceased',
];

/// Paused: comes back by date.
const enrolPaused = {'suspended', 'postponed', 'disc_suspended'};

/// Final: the student left.
const enrolFinal = {'withdrawn', 'cancelled', 'dismissed', 'transferred_out', 'graduated', 'deceased'};

const standings = ['regular', 'carrying', 'repeating', 'warning', 'final_chance'];

/// Stored flags, plus the derived `docs_owed` (never stored) at the end.
const flagKeys = [
  'struggling', 'special_case', 'transferred_in', 'conscripted', 'excuse_open', 'disciplinary_record', 'affiliated',
];
const derivedFlagKeys = ['docs_owed'];

/// Hidden from the student (Q8).
const staffOnlyFlags = {'struggling', 'special_case', 'disciplinary_record'};

const intakeLabels = ['nominated', 'provisional', 'missing', 'awaiting', 'accepted', 'rejected', 'withdrawn'];

/// `org_members.status` values the chip can show (§3.2 step 2) plus `active`.
const memberStatuses = ['active', 'pending', 'suspended', 'expired', 'rejected'];

/// The `chip=` filter of the list (§4.1).
const studentsChipFilters = ['enrolled', 'missing', 'attention', 'suspended'];

/// The `sort=` values of the list.
const studentsSorts = ['name', 'code', 'recent'];

/// The `section` values of the access log.
const accessSections = ['file', 'academic', 'documents', 'nid', 'advising', 'requests', 'access_log', 'export'];

/// A label in both languages.
typedef BiText = (String ar, String en);

/// The label in the current language.
String biText(BiText x) => t(x.$1, x.$2);

const Map<String, BiText> enrolText = {
  'enrolled': ('مقيد', 'Enrolled'),
  'suspended': ('موقوف قيده', 'Enrolment suspended'),
  'postponed': ('مؤجل', 'Postponed'),
  'disc_suspended': ('موقوف تأديبياً', 'Suspended (disciplinary)'),
  'outside': ('منقطع', 'Outside'),
  'withdrawn': ('منسحب', 'Withdrawn'),
  'cancelled': ('ملغى قيده', 'Enrolment cancelled'),
  'dismissed': ('مفصول', 'Dismissed'),
  'transferred_out': ('محوّل لجهة أخرى', 'Transferred out'),
  'graduated': ('خريج', 'Graduated'),
  'deceased': ('متوفى', 'Deceased'),
};

const Map<String, BiText> standingText = {
  'regular': ('منتظم', 'Regular'),
  'carrying': ('باقٍ بمواد', 'Carrying courses'),
  'repeating': ('باقٍ للإعادة', 'Repeating'),
  'warning': ('إنذار أكاديمي', 'Academic warning'),
  'final_chance': ('فرصة أخيرة', 'Final chance'),
};

const Map<String, BiText> flagText = {
  'struggling': ('متعثر', 'Struggling'),
  'special_case': ('حالة خاصة', 'Special case'),
  'transferred_in': ('محوّل إلينا', 'Transferred in'),
  'conscripted': ('مجنّد', 'Conscripted'),
  'excuse_open': ('عذر مفتوح', 'Open excuse'),
  'disciplinary_record': ('سجل تأديبي', 'Disciplinary record'),
  'affiliated': ('منتسب', 'Affiliated'),
  'docs_owed': ('مستندات ناقصة', 'Documents owed'),
};

const Map<String, BiText> intakeText = {
  'nominated': ('مرشح', 'Nominated'),
  'provisional': ('قيد مبدئي', 'Provisional'),
  'missing': ('بيانات ناقصة', 'Missing data'),
  'awaiting': ('في انتظار القبول', 'Awaiting acceptance'),
  'accepted': ('مقبول', 'Accepted'),
  'rejected': ('مرفوض', 'Rejected'),
  'withdrawn': ('سحب طلبه', 'Withdrew'),
};

const Map<String, BiText> memberStatusText = {
  'active': ('نشط', 'Active'),
  'pending': ('في انتظار التفعيل', 'Pending'),
  'suspended': ('حساب موقوف', 'Account suspended'),
  'expired': ('انتهت العضوية', 'Membership expired'),
  'rejected': ('مرفوض', 'Rejected'),
};

const Map<String, BiText> accessSectionText = {
  'file': ('الملف', 'File'),
  'academic': ('السجل الأكاديمي', 'Academic record'),
  'documents': ('المستندات', 'Documents'),
  'nid': ('الرقم القومي', 'National ID'),
  'advising': ('الإرشاد الأكاديمي', 'Academic advising'),
  'requests': ('الطلبات', 'Requests'),
  'access_log': ('سجل الاطلاع', 'Access log'),
  'export': ('تصدير', 'Export'),
};

/// The label of [value] in its map; an unknown value shows as it came.
String _label(Map<String, BiText> m, String value) {
  final x = m[value];
  return x == null ? value : biText(x);
}

String enrolLabel(String v) => _label(enrolText, v);
String standingLabel(String v) => _label(standingText, v);
String flagLabel(String v) => _label(flagText, v);
String intakeLabelText(String v) => _label(intakeText, v);
String memberStatusLabel(String v) => _label(memberStatusText, v);
String accessSectionLabel(String v) => _label(accessSectionText, v);

// ═════════════════════════════════════════════════════════════════════════════
//  Pure rules (§3.1, §3.2)
// ═════════════════════════════════════════════════════════════════════════════

/// §3.1: the onboarding case's status → one word of [intakeLabels]. No case ([caseStatus] null) → `accepted`.
/// [source] is the case's source (`excel`, `intake`, …) and [everSubmitted] whether it was ever submitted.
String intakeLabel(String? caseStatus, {String? source, bool everSubmitted = false, int missingCount = 0}) {
  final s = caseStatus ?? '';
  switch (s) {
    case '':
      return 'accepted';
    case 'draft':
      return (source == 'excel' || source == 'intake') && !everSubmitted ? 'nominated' : 'provisional';
    case 'submitted':
      return 'provisional';
    case 'needs_correction':
      return 'missing';
    case 'under_review' || 'approved':
      return 'awaiting';
    case 'active':
      return missingCount > 0 ? 'missing' : 'accepted';
    case 'rejected' || 'withdrawn':
      return s;
    default:
      return 'awaiting';
  }
}

/// THE one chip of a student: which dimension speaks and its value.
class StudentChip {
  const StudentChip(this.dimension, this.value);

  /// `enrolment`, `member`, `intake` or `standing`.
  final String dimension;
  final String value;

  factory StudentChip.fromJson(dynamic j) {
    final m = asMap(j);
    return StudentChip(asStr(m['dimension'], 'standing'), asStr(m['value'], 'regular'));
  }

  Map<String, dynamic> toJson() => {'dimension': dimension, 'value': value};

  /// The label in the current language.
  String get label => switch (dimension) {
        'enrolment' => enrolLabel(value),
        'member' => memberStatusLabel(value),
        'intake' => intakeLabelText(value),
        _ => standingLabel(value),
      };

  AppTone get tone => chipTone(this);

  @override
  bool operator ==(Object other) => other is StudentChip && other.dimension == dimension && other.value == value;

  @override
  int get hashCode => Object.hash(dimension, value);

  @override
  String toString() => 'StudentChip($dimension, $value)';
}

/// §3.2: the precedence enrolment → member → intake → standing.
StudentChip studentChip({String enrolStatus = 'enrolled', String memberStatus = 'active', String intake = 'accepted', String? acadStanding}) {
  if (enrolStatus != 'enrolled') return StudentChip('enrolment', enrolStatus);
  if (memberStatus != 'active') return StudentChip('member', memberStatus);
  if (intake != 'accepted') return StudentChip('intake', intake);
  final s = acadStanding;
  return StudentChip('standing', s == null || s.isEmpty ? 'regular' : s);
}

/// The tone of a chip (§3.2): calm green when all is well, amber for "needs something", red for trouble, neutral for
/// a student who left, gold for a graduate.
AppTone chipTone(StudentChip chip) {
  final v = chip.value;
  if (chip.dimension == 'member') {
    return switch (v) {
      'active' => AppTone.success,
      'pending' => AppTone.warning,
      'suspended' => AppTone.danger,
      _ => AppTone.neutral,
    };
  }
  if (v == 'graduated') return AppTone.gold;
  if (enrolFinal.contains(v)) return AppTone.neutral;
  return switch (v) {
    'regular' || 'accepted' || 'enrolled' => AppTone.success,
    'carrying' || 'missing' || 'awaiting' || 'provisional' || 'nominated' || 'postponed' => AppTone.warning,
    'repeating' || 'warning' || 'final_chance' || 'suspended' || 'disc_suspended' || 'outside' => AppTone.danger,
    _ => AppTone.neutral,
  };
}

/// The tone of a flag chip: the worrying ones amber, the rest neutral.
AppTone flagTone(String flag) => switch (flag) {
      'struggling' || 'disciplinary_record' || 'docs_owed' || 'excuse_open' => AppTone.warning,
      _ => AppTone.neutral,
    };

// ═════════════════════════════════════════════════════════════════════════════
//  StudentRow (§3.3)
// ═════════════════════════════════════════════════════════════════════════════

String _pickName(String ar, String en) => AppConfig.lang == 'en' && en.trim().isNotEmpty ? en : (ar.trim().isNotEmpty ? ar : en);

class StudentUser {
  const StudentUser({required this.id, this.name = '', this.nameEn = '', this.imageUrl, this.username});
  final int id;
  final String name, nameEn;
  final String? imageUrl, username;

  factory StudentUser.fromJson(dynamic j) {
    final m = asMap(j);
    final img = asStr(m['image_url']).trim(), un = asStr(m['username']).trim();
    return StudentUser(
      id: asInt(m['id']),
      name: asStr(m['name']),
      nameEn: asStr(m['name_en']),
      imageUrl: img.isEmpty ? null : img,
      username: un.isEmpty ? null : un,
    );
  }

  /// The name in the current language (the other one when it is empty).
  String get displayName => _pickName(name, nameEn);
}

class StudentProgram {
  const StudentProgram({required this.id, this.code = '', this.nameAr = '', this.nameEn = ''});
  final int id;
  final String code, nameAr, nameEn;

  static StudentProgram? fromJson(dynamic j) {
    if (j is! Map) return null;
    final m = asMap(j);
    return StudentProgram(id: asInt(m['id']), code: asStr(m['code']), nameAr: asStr(m['name_ar']), nameEn: asStr(m['name_en']));
  }

  String get label {
    final n = _pickName(nameAr, nameEn);
    return n.isEmpty ? code : n;
  }
}

/// The onboarding case behind a student (`intake` of the row).
class StudentIntake {
  const StudentIntake({this.caseId, this.status = '', this.label = 'accepted', this.conditional = false, this.dueAt});
  final int? caseId;
  final String status, label;
  final bool conditional;
  final DateTime? dueAt;

  static StudentIntake? fromJson(dynamic j) {
    if (j is! Map) return null;
    final m = asMap(j);
    final id = asInt(m['case_id']);
    return StudentIntake(
      caseId: id > 0 ? id : null,
      status: asStr(m['status']),
      label: asStr(m['label'], 'accepted'),
      conditional: asBool(m['conditional']),
      dueAt: orgParseUtc(m['due_at']),
    );
  }
}

class StudentRow {
  const StudentRow({
    required this.user,
    this.memberId = 0,
    this.memberStatus = 'active',
    this.studentCode,
    this.program,
    this.level,
    this.cohort,
    this.typeKey,
    this.nidLast4,
    this.enrolStatus = 'enrolled',
    this.enrolUntil,
    this.acadStanding,
    this.flags = const [],
    this.intake,
    this.missingCount,
    required this.chip,
  });

  final StudentUser user;
  final int memberId;
  final String memberStatus;
  final String? studentCode, level, cohort, typeKey, nidLast4;
  final StudentProgram? program;
  final String enrolStatus;
  final DateTime? enrolUntil;
  final String? acadStanding;

  /// Active stored flags only.
  final List<String> flags;
  final StudentIntake? intake;

  /// null = the student has no onboarding case.
  final int? missingCount;
  final StudentChip chip;

  int get id => user.id;
  String get name => user.displayName;

  /// Something is still owed (the badge shows).
  bool get hasMissing => (missingCount ?? 0) > 0;

  static String? _opt(dynamic v) {
    final s = asStr(v).trim();
    return s.isEmpty ? null : s;
  }

  factory StudentRow.fromJson(Map<String, dynamic> m) {
    final intake = StudentIntake.fromJson(m['intake']);
    final enrol = asStr(m['enrol_status'], 'enrolled');
    final member = asStr(m['member_status'], 'active');
    final standing = _opt(m['acad_standing']);
    final missing = m['missing_count'] == null ? null : asInt(m['missing_count']);
    // the server sends the chip; an older server that does not is answered by the same rule here
    final chip = m['chip'] is Map
        ? StudentChip.fromJson(m['chip'])
        : studentChip(enrolStatus: enrol, memberStatus: member, intake: intake?.label ?? 'accepted', acadStanding: standing);
    return StudentRow(
      user: StudentUser.fromJson(m['user']),
      memberId: asInt(m['member_id']),
      memberStatus: member,
      studentCode: _opt(m['student_code']),
      program: StudentProgram.fromJson(m['program']),
      level: _opt(m['level']),
      cohort: _opt(m['cohort']),
      typeKey: _opt(m['type_key']),
      nidLast4: _opt(m['nid_last4']),
      enrolStatus: enrol,
      enrolUntil: orgParseUtc(m['enrol_until']),
      acadStanding: standing,
      flags: [for (final f in (m['flags'] is List ? m['flags'] as List : const [])) '$f'],
      intake: intake,
      missingCount: missing,
      chip: chip,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The list (§4.1)
// ═════════════════════════════════════════════════════════════════════════════

/// Whole-organization counts (not the filtered list).
class StudentsSummary {
  const StudentsSummary({this.enrolled = 0, this.missing = 0, this.awaiting = 0, this.attention = 0, this.suspended = 0});
  final int enrolled, missing, awaiting, attention, suspended;

  factory StudentsSummary.fromJson(dynamic j) {
    final m = asMap(j);
    return StudentsSummary(
      enrolled: asInt(m['enrolled']),
      missing: asInt(m['missing']),
      awaiting: asInt(m['awaiting']),
      attention: asInt(m['attention']),
      suspended: asInt(m['suspended']),
    );
  }

  /// The count behind a `chip=` filter (or `awaiting`).
  int of(String key) => switch (key) {
        'enrolled' => enrolled,
        'missing' => missing,
        'awaiting' => awaiting,
        'attention' => attention,
        'suspended' => suspended,
        _ => 0,
      };
}

/// What the caller may do on the list page.
class StudentsCan {
  const StudentsCan({this.add = false, this.import = false, this.export = false, this.settings = false});
  final bool add, import, export, settings;

  factory StudentsCan.fromJson(dynamic j) {
    final m = asMap(j);
    return StudentsCan(add: asBool(m['add']), import: asBool(m['import']), export: asBool(m['export']), settings: asBool(m['settings']));
  }
}

class StudentsPageData {
  const StudentsPageData({
    this.total = 0,
    this.page = 1,
    this.size = 30,
    this.pages = 0,
    this.summary = const StudentsSummary(),
    this.can = const StudentsCan(),
    this.items = const [],
  });

  final int total, page, size, pages;
  final StudentsSummary summary;
  final StudentsCan can;
  final List<StudentRow> items;

  factory StudentsPageData.fromJson(dynamic j) {
    final m = asMap(j);
    final items = [for (final r in asMapList(m['items'])) StudentRow.fromJson(r)];
    final size = asInt(m['size'], 30);
    final total = asInt(m['total'], items.length);
    return StudentsPageData(
      total: total,
      page: asInt(m['page'], 1),
      size: size,
      pages: asInt(m['pages'], size > 0 ? (total + size - 1) ~/ size : 1),
      summary: StudentsSummary.fromJson(m['summary']),
      can: StudentsCan.fromJson(m['can']),
      items: items,
    );
  }
}

/// The list's query: what the page sends as `GET /students?…`.
class StudentsQuery {
  const StudentsQuery({
    this.q = '',
    this.chip,
    this.enrol,
    this.standing,
    this.flag,
    this.programId,
    this.level,
    this.typeKey,
    this.memberStatus,
    this.sort = 'name',
    this.page = 1,
    this.size = 30,
  });

  final String q;

  /// One of [studentsChipFilters]; null = everyone.
  final String? chip;
  final String? enrol, standing, flag, level, typeKey, memberStatus;
  final int? programId;
  final String sort;
  final int page, size;

  /// Anything narrows the list (the empty state then says "no matches").
  bool get filtered =>
      q.trim().isNotEmpty || chip != null || enrol != null || standing != null || flag != null || programId != null ||
      level != null || typeKey != null || memberStatus != null;

  Map<String, dynamic> toQuery() => {
        if (q.trim().isNotEmpty) 'q': q.trim(),
        if (chip != null) 'chip': chip,
        if (enrol != null) 'enrol': enrol,
        if (standing != null) 'standing': standing,
        if (flag != null) 'flag': flag,
        if (programId != null) 'program_id': programId,
        if (level != null) 'level': level,
        if (typeKey != null) 'type_key': typeKey,
        if (memberStatus != null) 'member_status': memberStatus,
        if (sort != 'name') 'sort': sort,
        'page': page < 1 ? 1 : page,
        'size': size.clamp(1, 100),
      };

  static const _keep = Object();

  /// A copy; pass `null` explicitly to clear a nullable filter (the default keeps it). Any change but [page]
  /// goes back to page 1.
  StudentsQuery copyWith({
    String? q,
    Object? chip = _keep,
    Object? enrol = _keep,
    Object? standing = _keep,
    Object? flag = _keep,
    Object? programId = _keep,
    Object? level = _keep,
    Object? typeKey = _keep,
    Object? memberStatus = _keep,
    String? sort,
    int? page,
    int? size,
  }) =>
      StudentsQuery(
        q: q ?? this.q,
        chip: identical(chip, _keep) ? this.chip : chip as String?,
        enrol: identical(enrol, _keep) ? this.enrol : enrol as String?,
        standing: identical(standing, _keep) ? this.standing : standing as String?,
        flag: identical(flag, _keep) ? this.flag : flag as String?,
        programId: identical(programId, _keep) ? this.programId : programId as int?,
        level: identical(level, _keep) ? this.level : level as String?,
        typeKey: identical(typeKey, _keep) ? this.typeKey : typeKey as String?,
        memberStatus: identical(memberStatus, _keep) ? this.memberStatus : memberStatus as String?,
        sort: sort ?? this.sort,
        page: page ?? 1,
        size: size ?? this.size,
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Missing data (§4.4)
// ═════════════════════════════════════════════════════════════════════════════

/// One missing photo, document or field, with WHY it is required.
class MissingItem {
  const MissingItem({
    required this.key,
    this.labelAr = '',
    this.labelEn = '',
    this.whyAr = '',
    this.whyEn = '',
    this.dueAt,
    this.status,
    this.kind,
  });

  final String key, labelAr, labelEn, whyAr, whyEn;
  final DateTime? dueAt;

  /// A document's state (`deferred`, `rejected`, …); null = never uploaded.
  final String? status;

  /// A field's input kind (`phone`, `date`, …).
  final String? kind;

  factory MissingItem.fromJson(Map<String, dynamic> m) {
    final st = asStr(m['status']).trim(), k = asStr(m['kind']).trim();
    return MissingItem(
      key: asStr(m['key']),
      labelAr: asStr(m['label_ar']),
      labelEn: asStr(m['label_en']),
      whyAr: asStr(m['why_ar']),
      whyEn: asStr(m['why_en']),
      dueAt: orgParseUtc(m['due_at']),
      status: st.isEmpty ? null : st,
      kind: k.isEmpty ? null : k,
    );
  }

  String get label {
    final l = _pickName(labelAr, labelEn);
    return l.isEmpty ? key : l;
  }

  String get why => _pickName(whyAr, whyEn);
}

class StudentMissing {
  const StudentMissing({
    this.caseId,
    this.canUpload = false,
    this.canEdit = false,
    this.canWaive = false,
    this.dueAt,
    this.photos = const [],
    this.documents = const [],
    this.fields = const [],
  });

  /// null = the student has no onboarding case (nothing can be missing).
  final int? caseId;
  final bool canUpload, canEdit, canWaive;
  final DateTime? dueAt;
  final List<MissingItem> photos, documents, fields;

  int get total => photos.length + documents.length + fields.length;
  bool get isEmpty => total == 0;

  factory StudentMissing.fromJson(dynamic j) {
    final m = asMap(j);
    final id = asInt(m['case_id']);
    List<MissingItem> list(String k) => [for (final r in asMapList(m[k])) MissingItem.fromJson(r)];
    return StudentMissing(
      caseId: id > 0 ? id : null,
      canUpload: asBool(m['can_upload']),
      canEdit: asBool(m['can_edit']),
      canWaive: asBool(m['can_waive']),
      dueAt: orgParseUtc(m['due_at']),
      photos: list('photos'),
      documents: list('documents'),
      fields: list('fields'),
    );
  }
}

/// The text of a missing document's state.
String missingStatusText(String? status) => switch (status) {
      null => t('لم يُرفع بعد', 'Not uploaded yet'),
      'deferred' => t('مؤجل', 'Deferred'),
      'rejected' => t('مرفوض، يلزم رفعه من جديد', 'Rejected, upload again'),
      'pending' || 'uploaded' => t('في انتظار المراجعة', 'Waiting for review'),
      'expired' => t('انتهت صلاحيته', 'Expired'),
      _ => status,
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Access log (§4.5)
// ═════════════════════════════════════════════════════════════════════════════

class AccessLogEntry {
  const AccessLogEntry({this.at, this.actorId, this.actorName = '', this.actorRole = '', this.section = 'file', this.ip = ''});
  final DateTime? at;
  final int? actorId;
  final String actorName, actorRole, section, ip;

  factory AccessLogEntry.fromJson(Map<String, dynamic> m) {
    final a = asMap(m['actor']);
    final id = asInt(a['id']);
    return AccessLogEntry(
      at: orgParseUtc(m['at']),
      actorId: id > 0 ? id : null,
      actorName: asStr(a['name']),
      actorRole: asStr(m['actor_role']),
      section: asStr(m['section'], 'file'),
      ip: asStr(m['ip']),
    );
  }

  String get sectionLabel => accessSectionLabel(section);
}

class StudentAccessLog {
  const StudentAccessLog({this.total = 0, this.page = 1, this.size = 30, this.pages = 0, this.items = const []});
  final int total, page, size, pages;
  final List<AccessLogEntry> items;

  factory StudentAccessLog.fromJson(dynamic j) {
    final m = asMap(j);
    final items = [for (final r in asMapList(m['items'])) AccessLogEntry.fromJson(r)];
    return StudentAccessLog(
      total: asInt(m['total'], items.length),
      page: asInt(m['page'], 1),
      size: asInt(m['size'], 30),
      pages: asInt(m['pages'], 1),
      items: items,
    );
  }
}
