// lib/features/org/onboarding/onboarding_models.dart — plain parse classes of member onboarding (contract §2, §6).
//
//   OnbType / OnbField / OnbDocReq / OnbChainStep / OnbSettings / OnbIntake     the type config (TypeOut / TypeIn)
//   OnbCase                    CaseRow + CaseOut in one class (the row has no detail keys, so those stay empty)
//   OnbDocRecord / OnbEvent    DocOut / EventOut
//   OnbSummary / OnbPreset / OnbRejectReason
//
// Times are naive UTC on the server: read with orgParseUtc, show with AppTime. Every parser is lenient (a missing
// key gives a default) so an older or newer server never breaks the page.
library;

import '../../admin/admin_common.dart' show t, asMap, asMapList, asInt, asStr;
import '../org_v3.dart' show orgParseUtc;

// ═════════════════════════════════════════════════════════════════════════════
//  Vocabulary
// ═════════════════════════════════════════════════════════════════════════════

const onbStatuses = ['draft', 'submitted', 'under_review', 'needs_correction', 'approved', 'active', 'rejected', 'withdrawn'];

/// The kill switch of the whole feature (`feature_catalog.py`).
const onboardingFeatureKey = 'org.onboarding';

/// The order of the wizard's groups (contract §2 `group`).
const onbGroups = ['identity', 'personal', 'academic', 'appointment', 'guardian', 'other'];

const onbFieldKinds = [
  'national_id', 'text', 'textarea', 'number', 'date', 'select', 'multiselect', 'checkbox', 'email', 'phone',
  'nationality', 'program', 'department', 'level',
];

const onbRequiredLevels = ['mandatory', 'optional', 'conditional'];

const onbModules = ['students', 'teachers', 'staff'];

/// The system fields (contract §2): they map to case columns, not to `data`.
const onbSystemKeys = {
  'full_name', 'name_en', 'nid_kind', 'national_id', 'passport_no', 'nationality', 'birth_date', 'gender', 'email', 'phone',
  'dept_id', 'program_id',
};

String onbStatusLabel(String s) => switch (s) {
      'draft' => t('مسودة', 'Draft'),
      'submitted' => t('بانتظار المراجعة', 'Waiting for review'),
      'under_review' => t('قيد المراجعة', 'Under review'),
      'needs_correction' => t('يحتاج تصحيحاً', 'Needs correction'),
      'approved' => t('مقبول', 'Approved'),
      'active' => t('مُفعَّل', 'Active'),
      'rejected' => t('مرفوض', 'Rejected'),
      'withdrawn' => t('مسحوب', 'Withdrawn'),
      _ => s,
    };

String onbDocStatusLabel(String s) => switch (s) {
      'uploaded' => t('بانتظار التحقق', 'Waiting to be checked'),
      'verified' => t('تم التحقق', 'Verified'),
      'rejected' => t('مرفوض', 'Rejected'),
      'deferred' => t('مؤجل', 'Deferred'),
      'waived' => t('معفى', 'Waived'),
      'missing' => t('ناقص', 'Missing'),
      _ => s,
    };

String onbRequiredLabel(String r) => switch (r) {
      'mandatory' => t('إلزامي', 'Mandatory'),
      'conditional' => t('مشروط', 'Conditional'),
      _ => t('اختياري', 'Optional'),
    };

String onbGroupLabel(String g) => switch (g) {
      'identity' => t('الهوية', 'Identity'),
      'personal' => t('البيانات الشخصية', 'Personal details'),
      'academic' => t('البيانات الأكاديمية', 'Academic details'),
      'appointment' => t('بيانات التعيين', 'Appointment details'),
      'guardian' => t('ولي الأمر', 'Guardian'),
      _ => t('بيانات أخرى', 'Other details'),
    };

String onbModuleLabel(String m) => switch (m) {
      'students' => t('طلاب', 'Students'),
      'teachers' => t('هيئة التدريس', 'Faculty'),
      _ => t('إداريون', 'Staff'),
    };

String _bi(String ar, String en) => t(ar.isNotEmpty ? ar : en, en.isNotEmpty ? en : ar);

Map<String, dynamic>? _when(Object? v) {
  final m = asMap(v);
  return m.isEmpty ? null : Map<String, dynamic>.from(m);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Type config
// ═════════════════════════════════════════════════════════════════════════════

class OnbOption {
  const OnbOption(this.value, this.labelAr, this.labelEn);
  final String value, labelAr, labelEn;
  String get label => _bi(labelAr, labelEn);

  factory OnbOption.fromJson(Map<String, dynamic> j) => OnbOption(asStr(j['value']), asStr(j['label_ar']), asStr(j['label_en']));
  Map<String, dynamic> toJson() => {'value': value, 'label_ar': labelAr, 'label_en': labelEn};
}

class OnbField {
  const OnbField({
    required this.key,
    this.kind = 'text',
    this.labelAr = '',
    this.labelEn = '',
    this.required = 'optional',
    this.when,
    this.options = const [],
    this.helpAr = '',
    this.helpEn = '',
    this.group = 'other',
    this.system = false,
  });

  final String key, kind, labelAr, labelEn, required, helpAr, helpEn, group;
  final Map<String, dynamic>? when;
  final List<OnbOption> options;
  final bool system;

  String get label => _bi(labelAr, labelEn);
  String get help => _bi(helpAr, helpEn);

  factory OnbField.fromJson(Map<String, dynamic> j) => OnbField(
        key: asStr(j['key']),
        kind: asStr(j['kind']).isEmpty ? 'text' : asStr(j['kind']),
        labelAr: asStr(j['label_ar']),
        labelEn: asStr(j['label_en']),
        required: asStr(j['required']).isEmpty ? 'optional' : asStr(j['required']),
        when: _when(j['when']),
        options: asMapList(j['options']).map(OnbOption.fromJson).toList(),
        helpAr: asStr(j['help_ar']),
        helpEn: asStr(j['help_en']),
        group: asStr(j['group']).isEmpty ? 'other' : asStr(j['group']),
        system: j['system'] == true,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'kind': kind,
        'label_ar': labelAr,
        'label_en': labelEn,
        'required': required,
        if (when != null) 'when': when,
        if (options.isNotEmpty) 'options': [for (final o in options) o.toJson()],
        if (helpAr.isNotEmpty) 'help_ar': helpAr,
        if (helpEn.isNotEmpty) 'help_en': helpEn,
        'group': group,
        'system': system,
      };

  OnbField copyWith({String? labelAr, String? labelEn, String? required, Map<String, dynamic>? when, bool clearWhen = false}) => OnbField(
        key: key,
        kind: kind,
        labelAr: labelAr ?? this.labelAr,
        labelEn: labelEn ?? this.labelEn,
        required: required ?? this.required,
        when: clearWhen ? null : (when ?? this.when),
        options: options,
        helpAr: helpAr,
        helpEn: helpEn,
        group: group,
        system: system,
      );
}

class OnbDocReq {
  const OnbDocReq({
    required this.key,
    this.labelAr = '',
    this.labelEn = '',
    this.required = 'optional',
    this.when,
    this.accept = const ['jpg', 'png', 'pdf'],
    this.maxMb = 5,
    this.photoMinPx,
    this.photoAspect,
    this.originalNeeded = false,
    this.allowLater = false,
    this.defaultDueDays = 30,
  });

  final String key, labelAr, labelEn, required;
  final Map<String, dynamic>? when;
  final List<String> accept;
  final int maxMb;
  final int? photoMinPx;
  final String? photoAspect;
  final bool originalNeeded, allowLater;
  final int defaultDueDays;

  String get label => _bi(labelAr, labelEn);
  bool get isPhoto => photoMinPx != null || photoAspect != null;

  factory OnbDocReq.fromJson(Map<String, dynamic> j) {
    final p = asMap(j['photo']);
    final acc = j['accept'];
    return OnbDocReq(
      key: asStr(j['key']),
      labelAr: asStr(j['label_ar']),
      labelEn: asStr(j['label_en']),
      required: asStr(j['required']).isEmpty ? 'optional' : asStr(j['required']),
      when: _when(j['when']),
      accept: acc is List ? [for (final a in acc) '$a'.toLowerCase()] : const ['jpg', 'png', 'pdf'],
      maxMb: asInt(j['max_mb'], 5),
      photoMinPx: p.isEmpty ? null : asInt(p['min_px']),
      photoAspect: p.isEmpty || asStr(p['aspect']).isEmpty ? null : asStr(p['aspect']),
      originalNeeded: j['original_needed'] == true,
      allowLater: j['allow_later'] == true,
      defaultDueDays: asInt(j['default_due_days'], 30),
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'label_ar': labelAr,
        'label_en': labelEn,
        'required': required,
        if (when != null) 'when': when,
        'accept': accept,
        'max_mb': maxMb,
        'photo': isPhoto ? {'min_px': photoMinPx, 'aspect': photoAspect} : null,
        'original_needed': originalNeeded,
        'allow_later': allowLater,
        'default_due_days': defaultDueDays,
      };

  OnbDocReq copyWith({String? labelAr, String? labelEn, String? required, List<String>? accept, int? maxMb, bool? allowLater, bool? originalNeeded}) =>
      OnbDocReq(
        key: key,
        labelAr: labelAr ?? this.labelAr,
        labelEn: labelEn ?? this.labelEn,
        required: required ?? this.required,
        when: when,
        accept: accept ?? this.accept,
        maxMb: maxMb ?? this.maxMb,
        photoMinPx: photoMinPx,
        photoAspect: photoAspect,
        originalNeeded: originalNeeded ?? this.originalNeeded,
        allowLater: allowLater ?? this.allowLater,
        defaultDueDays: defaultDueDays,
      );
}

/// One approval step: either a module permission (`{module, action}`) or a department role (`{org_role, scope}`).
class OnbChainStep {
  const OnbChainStep({required this.key, this.labelAr = '', this.labelEn = '', this.need = const {}});
  final String key, labelAr, labelEn;
  final Map<String, dynamic> need;

  String get label => _bi(labelAr, labelEn);

  /// A short sentence on who decides this step.
  String get needText {
    final role = asStr(need['org_role']);
    if (role.isNotEmpty) return role == 'dept_head' ? t('رئيس القسم', 'The department head') : role;
    final m = asStr(need['module']);
    return t('من يملك صلاحية القبول على ${onbModuleLabel(m)}', 'Whoever may approve ${onbModuleLabel(m).toLowerCase()}');
  }

  factory OnbChainStep.fromJson(Map<String, dynamic> j) =>
      OnbChainStep(key: asStr(j['key']), labelAr: asStr(j['label_ar']), labelEn: asStr(j['label_en']), need: Map<String, dynamic>.from(asMap(j['need'])));

  Map<String, dynamic> toJson() => {'key': key, 'label_ar': labelAr, 'label_en': labelEn, 'need': need};
}

class OnbSettings {
  const OnbSettings({this.autoActivate = true, this.studentCodePattern, this.inviteDays = 14, this.purgeRejectedDays = 180, this.guardianUnder = 18});
  final bool autoActivate;
  final String? studentCodePattern;
  final int inviteDays, purgeRejectedDays, guardianUnder;

  factory OnbSettings.fromJson(Map<String, dynamic> j) => OnbSettings(
        autoActivate: j['auto_activate'] != false,
        studentCodePattern: asStr(j['student_code_pattern']).isEmpty ? null : asStr(j['student_code_pattern']),
        inviteDays: asInt(j['invite_days'], 14),
        purgeRejectedDays: asInt(j['purge_rejected_days'], 180),
        guardianUnder: asInt(j['guardian_under'], 18),
      );

  Map<String, dynamic> toJson() => {
        'auto_activate': autoActivate,
        'student_code_pattern': studentCodePattern,
        'invite_days': inviteDays,
        'purge_rejected_days': purgeRejectedDays,
        'guardian_under': guardianUnder,
      };

  OnbSettings copyWith({bool? autoActivate}) => OnbSettings(
      autoActivate: autoActivate ?? this.autoActivate,
      studentCodePattern: studentCodePattern,
      inviteDays: inviteDays,
      purgeRejectedDays: purgeRejectedDays,
      guardianUnder: guardianUnder);
}

class OnbIntake {
  const OnbIntake({this.enabled = false, this.validUntil, this.capacity, this.used = 0});
  final bool enabled;
  final DateTime? validUntil;
  final int? capacity;
  final int used;

  factory OnbIntake.fromJson(Map<String, dynamic> j) => OnbIntake(
        enabled: j['enabled'] == true,
        validUntil: orgParseUtc(j['valid_until']),
        capacity: j['capacity'] == null ? null : asInt(j['capacity']),
        used: asInt(j['used']),
      );
}

class OnbType {
  const OnbType({
    required this.key,
    this.labelAr = '',
    this.labelEn = '',
    this.baseRole = 'student',
    this.module = 'students',
    this.fields = const [],
    this.documents = const [],
    this.chain = const [],
    this.settings = const OnbSettings(),
    this.presetKey,
    this.active = true,
    this.sort = 0,
    this.intake = const OnbIntake(),
  });

  final String key, labelAr, labelEn, baseRole, module;
  final List<OnbField> fields;
  final List<OnbDocReq> documents;
  final List<OnbChainStep> chain;
  final OnbSettings settings;
  final String? presetKey;
  final bool active;
  final int sort;
  final OnbIntake intake;

  String get label => _bi(labelAr, labelEn);

  OnbField? field(String k) {
    for (final f in fields) {
      if (f.key == k) return f;
    }
    return null;
  }

  OnbDocReq? doc(String k) {
    for (final d in documents) {
      if (d.key == k) return d;
    }
    return null;
  }

  factory OnbType.fromJson(Map<String, dynamic> j) => OnbType(
        key: asStr(j['key']),
        labelAr: asStr(j['label_ar']),
        labelEn: asStr(j['label_en']),
        baseRole: asStr(j['base_role']).isEmpty ? 'student' : asStr(j['base_role']),
        module: asStr(j['module']).isEmpty ? 'students' : asStr(j['module']),
        fields: asMapList(j['fields']).map(OnbField.fromJson).toList(),
        documents: asMapList(j['documents']).map(OnbDocReq.fromJson).toList(),
        chain: asMapList(j['chain']).map(OnbChainStep.fromJson).toList(),
        settings: OnbSettings.fromJson(asMap(j['settings'])),
        presetKey: asStr(j['preset_key']).isEmpty ? null : asStr(j['preset_key']),
        active: j['active'] != false,
        sort: asInt(j['sort']),
        intake: OnbIntake.fromJson(asMap(j['intake'])),
      );

  /// The whole object for `PUT …/types/{key}` (the server replaces it as a whole).
  Map<String, dynamic> toJson() => {
        'key': key,
        'label_ar': labelAr,
        'label_en': labelEn,
        'base_role': baseRole,
        'module': module,
        'fields': [for (final f in fields) f.toJson()],
        'documents': [for (final d in documents) d.toJson()],
        'chain': [for (final c in chain) c.toJson()],
        'settings': settings.toJson(),
        'preset_key': presetKey,
        'active': active,
        'sort': sort,
      };

  OnbType copyWith({List<OnbField>? fields, List<OnbDocReq>? documents, List<OnbChainStep>? chain, OnbSettings? settings, bool? active, String? labelAr, String? labelEn}) =>
      OnbType(
        key: key,
        labelAr: labelAr ?? this.labelAr,
        labelEn: labelEn ?? this.labelEn,
        baseRole: baseRole,
        module: module,
        fields: fields ?? this.fields,
        documents: documents ?? this.documents,
        chain: chain ?? this.chain,
        settings: settings ?? this.settings,
        presetKey: presetKey,
        active: active ?? this.active,
        sort: sort,
        intake: intake,
      );
}

class OnbPreset {
  const OnbPreset({required this.key, this.labelAr = '', this.labelEn = '', this.types = const []});
  final String key, labelAr, labelEn;
  final List<String> types;
  String get label => _bi(labelAr, labelEn);

  factory OnbPreset.fromJson(Map<String, dynamic> j) =>
      OnbPreset(key: asStr(j['key']), labelAr: asStr(j['label_ar']), labelEn: asStr(j['label_en']), types: [for (final x in (j['types'] is List ? j['types'] as List : const [])) '$x']);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Cases
// ═════════════════════════════════════════════════════════════════════════════

class OnbDocRecord {
  const OnbDocRecord({
    required this.id,
    required this.reqKey,
    this.status = 'uploaded',
    this.fileName = '',
    this.mime = '',
    this.size = 0,
    this.version = 1,
    this.uploadedAt,
    this.verifiedAt,
    this.note = '',
    this.dueAt,
    this.filePath = '',
  });

  final int id, size, version;
  final String reqKey, status, fileName, mime, note, filePath;
  final DateTime? uploadedAt, verifiedAt, dueAt;

  bool get isImage => mime.startsWith('image/');
  bool get isPdf => mime == 'application/pdf' || fileName.toLowerCase().endsWith('.pdf');

  factory OnbDocRecord.fromJson(Map<String, dynamic> j) => OnbDocRecord(
        id: asInt(j['id']),
        reqKey: asStr(j['req_key']),
        status: asStr(j['status']).isEmpty ? 'uploaded' : asStr(j['status']),
        fileName: asStr(j['file_name']),
        mime: asStr(j['mime']),
        size: asInt(j['size']),
        version: asInt(j['version'], 1),
        uploadedAt: orgParseUtc(j['uploaded_at']),
        verifiedAt: orgParseUtc(j['verified_at']),
        note: asStr(j['note']),
        dueAt: orgParseUtc(j['due_at']),
        filePath: asStr(j['file_path']),
      );
}

class OnbEvent {
  const OnbEvent({required this.id, this.kind = '', this.fromStatus = '', this.toStatus = '', this.reason = '', this.actorName = '', this.createdAt, this.details = const {}});
  final int id;
  final String kind, fromStatus, toStatus, reason, actorName;
  final DateTime? createdAt;
  final Map<String, dynamic> details;

  factory OnbEvent.fromJson(Map<String, dynamic> j) => OnbEvent(
        id: asInt(j['id']),
        kind: asStr(j['kind']),
        fromStatus: asStr(j['from_status']),
        toStatus: asStr(j['to_status']),
        reason: asStr(j['reason']),
        actorName: asStr(j['actor_name']),
        createdAt: orgParseUtc(j['created_at']),
        details: Map<String, dynamic>.from(asMap(j['details'])),
      );

  /// A bilingual line for the timeline.
  String get text {
    final to = toStatus.isEmpty ? '' : onbStatusLabel(toStatus);
    return switch (kind) {
      'created' => t('أُنشئ الطلب', 'Case created'),
      'submitted' => t('قُدِّم الطلب', 'Submitted'),
      'claimed' => t('بدأت المراجعة', 'Review started'),
      'correction_requested' => t('طُلب تصحيح', 'Correction requested'),
      'resubmitted' => t('أُعيد التقديم بعد التصحيح', 'Resubmitted after correction'),
      'approved' => t('تم القبول', 'Approved'),
      'step_approved' => t('اعتُمدت مرحلة', 'A step was approved'),
      'rejected' => t('رُفض الطلب', 'Rejected'),
      'activated' => t('فُعِّلت العضوية', 'Membership activated'),
      'withdrawn' => t('سُحب الطلب', 'Withdrawn'),
      'document_uploaded' => t('رُفع مستند', 'A document was uploaded'),
      'document_verified' => t('تم التحقق من مستند', 'A document was verified'),
      'document_rejected' => t('رُفض مستند', 'A document was rejected'),
      _ => to.isNotEmpty ? to : kind,
    };
  }
}

class OnbCorrection {
  const OnbCorrection(this.key, this.note);
  final String key, note;
}

/// The actions the viewer may take on a case (`can` of CaseOut).
class OnbCan {
  const OnbCan({
    this.edit = false,
    this.submit = false,
    this.claim = false,
    this.approve = false,
    this.reject = false,
    this.requestCorrection = false,
    this.activate = false,
    this.withdraw = false,
    this.viewDocuments = false,
    this.unmask = false,
  });
  final bool edit, submit, claim, approve, reject, requestCorrection, activate, withdraw, viewDocuments, unmask;

  factory OnbCan.fromJson(Map<String, dynamic> j) => OnbCan(
        edit: j['edit'] == true,
        submit: j['submit'] == true,
        claim: j['claim'] == true,
        approve: j['approve'] == true,
        reject: j['reject'] == true,
        requestCorrection: j['request_correction'] == true,
        activate: j['activate'] == true,
        withdraw: j['withdraw'] == true,
        viewDocuments: j['view_documents'] == true,
        unmask: j['unmask'] == true,
      );
}

class OnbCase {
  const OnbCase({
    required this.id,
    this.typeKey = '',
    this.typeLabelAr = '',
    this.typeLabelEn = '',
    this.status = 'draft',
    this.step = 0,
    this.stepLabelAr = '',
    this.stepLabelEn = '',
    this.source = 'manual',
    this.fullName = '',
    this.nidMasked = '',
    this.email = '',
    this.phone = '',
    this.conditional = false,
    this.dueAt,
    this.overdue = false,
    this.missingCount = 0,
    this.submittedAt,
    this.updatedAt,
    this.nameEn = '',
    this.nidKind = 'national_id',
    this.nationality = 'EG',
    this.birthDate,
    this.gender = '',
    this.deptId,
    this.programId,
    this.data = const {},
    this.decisionReason = '',
    this.correctionFields = const [],
    this.correctionDocs = const [],
    this.requiredFields = const [],
    this.requiredDocs = const [],
    this.missingFields = const [],
    this.missingDocs = const [],
    this.documents = const [],
    this.events = const [],
    this.memberId,
    this.lockedFields = const [],
    this.can = const OnbCan(),
    this.type,
    this.generatedPassword,
    this.warnings = const [],
    this.detailed = false,
    this.orgId,
    this.orgName = '',
    this.orgLogo = '',
  });

  final int id, step, missingCount;
  final String typeKey, typeLabelAr, typeLabelEn, status, stepLabelAr, stepLabelEn, source, fullName, nidMasked, email, phone;
  final String nameEn, nidKind, nationality, gender, decisionReason;
  final bool conditional, overdue, detailed;

  /// The organization of an applicant's own case (`GET /me/onboarding`).
  final int? orgId;
  final String orgName, orgLogo;
  final DateTime? dueAt, submittedAt, updatedAt;
  final String? birthDate;
  final int? deptId, programId, memberId;
  final Map<String, dynamic> data;
  final List<OnbCorrection> correctionFields, correctionDocs;
  final List<String> requiredFields, requiredDocs, missingFields, missingDocs, lockedFields;
  final List<OnbDocRecord> documents;
  final List<OnbEvent> events;
  final OnbCan can;
  final OnbType? type;

  /// Shown once, in a copyable dialog: the password of a new account the activation created.
  final String? generatedPassword;
  final List<Map<String, dynamic>> warnings;

  String get typeLabel => _bi(typeLabelAr, typeLabelEn);
  String get stepLabel => _bi(stepLabelAr, stepLabelEn);

  bool get isOpen => const {'draft', 'submitted', 'under_review', 'needs_correction'}.contains(status);

  /// The current (latest) document of a requirement, or null.
  OnbDocRecord? docFor(String reqKey) {
    OnbDocRecord? r;
    for (final d in documents) {
      if (d.reqKey == reqKey && (r == null || d.version >= r.version)) r = d;
    }
    return r;
  }

  /// The form values by key: `data` plus the system columns (the national ID is only ever the masked text).
  Map<String, dynamic> get values => {
        ...data,
        'full_name': fullName,
        if (nameEn.isNotEmpty) 'name_en': nameEn,
        'nid_kind': nidKind,
        if (nidMasked.isNotEmpty) (nidKind == 'passport' ? 'passport_no' : 'national_id'): nidMasked,
        'nationality': nationality,
        if (birthDate != null) 'birth_date': birthDate,
        if (gender.isNotEmpty) 'gender': gender,
        if (email.isNotEmpty) 'email': email,
        if (phone.isNotEmpty) 'phone': phone,
        if (deptId != null) 'dept_id': deptId,
        if (programId != null) 'program_id': programId,
      };

  factory OnbCase.fromJson(Map<String, dynamic> j) {
    List<OnbCorrection> corr(Object? v) => [for (final x in asMapList(v)) OnbCorrection(asStr(x['key']), asStr(x['note']))];
    List<String> keys(Object? v) => v is List ? [for (final x in v) '$x'] : const [];
    final corrections = asMap(j['corrections']);
    final required = asMap(j['required']), missing = asMap(j['missing']);
    final typeJson = asMap(j['type']);
    final orgJson = asMap(j['org']);
    final birth = asStr(j['birth_date']);
    return OnbCase(
      id: asInt(j['id']),
      typeKey: asStr(j['type_key']),
      typeLabelAr: asStr(j['type_label_ar']),
      typeLabelEn: asStr(j['type_label_en']),
      status: asStr(j['status']).isEmpty ? 'draft' : asStr(j['status']),
      step: asInt(j['step']),
      stepLabelAr: asStr(j['step_label_ar']),
      stepLabelEn: asStr(j['step_label_en']),
      source: asStr(j['source']).isEmpty ? 'manual' : asStr(j['source']),
      fullName: asStr(j['full_name']),
      nidMasked: asStr(j['nid_masked']),
      email: asStr(j['email']),
      phone: asStr(j['phone']),
      conditional: j['conditional'] == true,
      dueAt: orgParseUtc(j['due_at']),
      overdue: j['overdue'] == true,
      missingCount: asInt(j['missing_count']),
      submittedAt: orgParseUtc(j['submitted_at']),
      updatedAt: orgParseUtc(j['updated_at']),
      nameEn: asStr(j['name_en']),
      nidKind: asStr(j['nid_kind']).isEmpty ? 'national_id' : asStr(j['nid_kind']),
      nationality: asStr(j['nationality']).isEmpty ? 'EG' : asStr(j['nationality']),
      birthDate: birth.isEmpty ? null : birth.substring(0, birth.length < 10 ? birth.length : 10),
      gender: asStr(j['gender']),
      deptId: j['dept_id'] == null ? null : asInt(j['dept_id']),
      programId: j['program_id'] == null ? null : asInt(j['program_id']),
      data: Map<String, dynamic>.from(asMap(j['data'])),
      decisionReason: asStr(j['decision_reason']),
      correctionFields: corr(corrections['fields']),
      correctionDocs: corr(corrections['documents']),
      requiredFields: keys(required['fields']),
      requiredDocs: keys(required['documents']),
      missingFields: keys(missing['fields']),
      missingDocs: keys(missing['documents']),
      documents: asMapList(j['documents']).map(OnbDocRecord.fromJson).toList(),
      events: asMapList(j['events']).map(OnbEvent.fromJson).toList(),
      memberId: j['member_id'] == null ? null : asInt(j['member_id']),
      lockedFields: keys(j['locked_fields']),
      can: OnbCan.fromJson(asMap(j['can'])),
      type: typeJson.isEmpty ? null : OnbType.fromJson(typeJson),
      generatedPassword: asStr(j['generated_password']).isEmpty ? null : asStr(j['generated_password']),
      warnings: asMapList(j['warnings']),
      detailed: j.containsKey('can') || j.containsKey('documents'),
      orgId: orgJson.isNotEmpty ? asInt(orgJson['id']) : (j['org_id'] == null ? null : asInt(j['org_id'])),
      orgName: asStr(orgJson['name'] ?? j['org_name']),
      orgLogo: asStr(orgJson['logo'] ?? j['org_logo']),
    );
  }
}

class OnbSummary {
  const OnbSummary({this.counts = const {}, this.overdue = 0, this.byType = const {}});
  final Map<String, int> counts;
  final int overdue;
  final Map<String, Map<String, int>> byType;

  int count(String status) => counts[status] ?? 0;

  /// The pill counts of the stage tabs.
  int get toReview => count('submitted') + count('under_review');
  int get needsCorrection => count('needs_correction');
  int get drafts => count('draft');
  int get done => count('approved') + count('active') + count('rejected') + count('withdrawn');

  /// Not in the contract's `counts`; shown only when the server sends a `conditional` key.
  int? get conditional => counts.containsKey('conditional') ? counts['conditional'] : null;

  factory OnbSummary.fromJson(Map<String, dynamic> j) {
    Map<String, int> ints(Object? v) => {for (final e in asMap(v).entries) e.key: asInt(e.value)};
    return OnbSummary(
      counts: ints(j['counts']),
      overdue: asInt(j['overdue']),
      byType: {for (final e in asMap(j['by_type']).entries) e.key: ints(e.value)},
    );
  }
}

class OnbRejectReason {
  const OnbRejectReason(this.key, this.labelAr, this.labelEn);
  final String key, labelAr, labelEn;
  String get label => _bi(labelAr, labelEn);

  factory OnbRejectReason.fromJson(Map<String, dynamic> j) =>
      OnbRejectReason(asStr(j['key']), asStr(j['label_ar'] ?? j['ar']), asStr(j['label_en'] ?? j['en']));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Phase B / C: import batches, intake link, invite result
// ═════════════════════════════════════════════════════════════════════════════

/// One message of an import row: the field it names, the code and the bilingual text.
class OnbRowMessage {
  const OnbRowMessage({this.field = '', this.code = '', this.ar = '', this.en = ''});
  final String field, code, ar, en;
  String get text => _bi(ar, en);

  factory OnbRowMessage.fromJson(Map<String, dynamic> j) => OnbRowMessage(field: asStr(j['field']), code: asStr(j['code']), ar: asStr(j['ar']), en: asStr(j['en']));
}

class OnbImportRow {
  const OnbImportRow({required this.rowNo, this.state = 'ok', this.data = const {}, this.messages = const []});
  final int rowNo;
  final String state; // ok | warning | error
  final Map<String, dynamic> data;
  final List<OnbRowMessage> messages;

  /// The person of the row, for the card title: the full name, else the first value.
  String get title {
    final n = asStr(data['full_name']);
    if (n.isNotEmpty) return n;
    for (final v in data.values) {
      if ('$v'.isNotEmpty && v != null) return '$v';
    }
    return '#$rowNo';
  }

  factory OnbImportRow.fromJson(Map<String, dynamic> j) => OnbImportRow(
        rowNo: asInt(j['row_no']),
        state: asStr(j['state']).isEmpty ? 'ok' : asStr(j['state']),
        data: Map<String, dynamic>.from(asMap(j['data'])),
        messages: asMapList(j['messages']).map(OnbRowMessage.fromJson).toList(),
      );
}

/// BatchOut: the staged import the person reviews before confirming (24 h).
class OnbBatch {
  const OnbBatch({required this.id, this.typeKey = '', this.mode = 'draft', this.ok = 0, this.warning = 0, this.error = 0, this.rows = const [], this.expiresAt});
  final int id, ok, warning, error;
  final String typeKey, mode;
  final List<OnbImportRow> rows;
  final DateTime? expiresAt;

  int get total => ok + warning + error;

  /// What a confirm would save (rows with a warning only when included).
  int willCreate({required bool includeWarnings}) => ok + (includeWarnings ? warning : 0);

  List<OnbImportRow> rowsIn(String state) => state.isEmpty ? rows : [for (final r in rows) if (r.state == state) r];

  factory OnbBatch.fromJson(Map<String, dynamic> j) {
    final c = asMap(j['counts']);
    final rows = asMapList(j['rows']).map(OnbImportRow.fromJson).toList();
    int n(String k, String state) => c.containsKey(k) ? asInt(c[k]) : rows.where((r) => r.state == state).length;
    return OnbBatch(
      id: asInt(j['id']),
      typeKey: asStr(j['type_key']),
      mode: asStr(j['mode']).isEmpty ? 'draft' : asStr(j['mode']),
      ok: n('ok', 'ok'),
      warning: n('warning', 'warning'),
      error: n('error', 'error'),
      rows: rows,
      expiresAt: orgParseUtc(j['expires_at']),
    );
  }
}

/// `{created, skipped, invited, case_ids}` of a confirmed import (skipped may be a number or a list).
class OnbImportResult {
  const OnbImportResult({this.created = 0, this.skipped = 0, this.invited = 0, this.caseIds = const []});
  final int created, skipped, invited;
  final List<int> caseIds;

  factory OnbImportResult.fromJson(Map<String, dynamic> j) {
    int n(Object? v) => v is List ? v.length : asInt(v);
    return OnbImportResult(created: n(j['created']), skipped: n(j['skipped']), invited: n(j['invited']), caseIds: [for (final x in (j['case_ids'] is List ? j['case_ids'] as List : const [])) asInt(x)]);
  }
}

/// `{invited, skipped:[{id, reason}]}` of "Invite to complete".
class OnbInviteResult {
  const OnbInviteResult({this.invited = 0, this.skipped = const []});
  final int invited;
  final List<({int id, String reason})> skipped;

  factory OnbInviteResult.fromJson(Map<String, dynamic> j) => OnbInviteResult(
        invited: j['invited'] is List ? (j['invited'] as List).length : asInt(j['invited']),
        skipped: [for (final x in asMapList(j['skipped'])) (id: asInt(x['id']), reason: asStr(x['reason']))],
      );
}

/// The reason text of a skipped invitation.
String onbSkipReason(String code) => switch (code) {
      'no_contact' => t('لا بريد ولا هاتف', 'No e-mail or phone'),
      'not_draft' => t('ليس مسودة', 'Not a draft'),
      'already_invited' => t('مدعو بالفعل', 'Already invited'),
      'duplicate_member' => t('عضو بالفعل', 'Already a member'),
      _ => code.isEmpty ? t('تم تخطيه', 'Skipped') : code,
    };

/// The answer of saving an intake link: the code shows once.
class OnbIntakeLink {
  const OnbIntakeLink({this.code = '', this.link = ''});
  final String code, link;
  bool get hasCode => code.isNotEmpty;

  factory OnbIntakeLink.fromJson(Map<String, dynamic> j) => OnbIntakeLink(code: asStr(j['code']), link: asStr(j['link']));
}

/// `GET /public/onboarding/intake/{code}`.
class OnbIntakePreview {
  const OnbIntakePreview({this.orgId, this.orgName = '', this.orgLogo = '', this.typeKey = '', this.typeLabelAr = '', this.typeLabelEn = '', this.open = true});
  final int? orgId;
  final String orgName, orgLogo, typeKey, typeLabelAr, typeLabelEn;
  final bool open;
  String get typeLabel => _bi(typeLabelAr, typeLabelEn);

  factory OnbIntakePreview.fromJson(Map<String, dynamic> j) {
    final o = asMap(j['org']), ty = asMap(j['type']);
    return OnbIntakePreview(
      orgId: o['id'] == null ? null : asInt(o['id']),
      orgName: asStr(o['name']),
      orgLogo: asStr(o['logo']),
      typeKey: asStr(ty['key']),
      typeLabelAr: asStr(ty['label_ar']),
      typeLabelEn: asStr(ty['label_en']),
      open: j['open'] != false,
    );
  }
}
