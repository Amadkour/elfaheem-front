// lib/features/org/students/student_requests_api.dart — student lifecycle phase 6 (contract §9, PLAN §3.6): lifecycle
// requests through Governance and transfer credit (المقاصة). The backend is features/org/students/requests.py,
// transfer_credits.py and api/requests_router.py; every call goes through `orgCall` (never throws).
//
//   StudentRequestsApi(orgId)
//     the student   myRequests()                     GET  /public/{o}/my-requests            → MyRequests.fromJson
//                   submit(draft.toJson())           POST /public/{o}/my-requests            → LifecycleRequest (201)
//                   withdraw(id)                     POST /public/{o}/my-requests/{id}/withdraw → LifecycleRequest
//                   attach(id, files)                POST /public/governance/items/{id}/comments (the request is a
//                                                    governance item: its documents ride on one comment)
//     staff         detail(id)                       GET  /students/requests/{id}            → LifecycleRequest (staff)
//                   accept(id, body) / reject(id, note) / toCouncil(id, councilDeptId:, note:)
//                   statusToCouncil(uid, body)       POST /students/{uid}/status/council     (StatusIn + council_dept_id)
//                   credits(uid)                     GET  /students/{uid}/transfer-credits   → TransferCredits.fromJson
//                   addCredit(uid, body) · patchCredit(id, body) · deleteCredit(id) · saveCreditSettings(…)
//                   courses(search:)                 GET  /orgs/{o}/courses?scope=tree       → [CourseChoice]
//
//   requestsCodeTexts() / requestsErrorText(e)      bilingual texts of the phase-6 codes (status codes fall back to
//                                                    statusCodeTexts, the rest to orgErrorText)
library;

import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_badges.dart' show AppTone;
import 'package:flutter_education_app/design/app_icons.dart' show DirIcons;

import '../../admin/admin_common.dart' show t, asMap, asMapList, asInt, asStr, asBool;
import '../governance/gov_api.dart' show GovApi;
import '../governance/gov_models.dart' show GovAttachment;
import '../org_providers.dart' show orgBase;
import '../org_v3.dart' show OrgCall, orgCall, orgErrorText, orgParseUtc;
import 'student_status_models.dart' show statusCodeTexts, ymd;

// ═════════════════════════════════════════════════════════════════════════════
//  Request kinds (server REQUESTS)
// ═════════════════════════════════════════════════════════════════════════════

const lifecycleRequestKeys = ['suspend', 'postpone', 'withdraw', 'transfer_out', 'reenrol', 'excuse', 'data_update'];

/// A request whose change ends or pauses the studies: the form asks the student to confirm it.
const lifecycleRequestsSerious = {'withdraw', 'transfer_out'};

String _pick(String ar, String en) => AppConfig.lang == 'en' && en.trim().isNotEmpty ? en : (ar.trim().isNotEmpty ? ar : en);

String requestKindLabel(String key) => switch (key) {
      'suspend' => t('وقف القيد', 'Suspend my enrolment'),
      'postpone' => t('تأجيل الدراسة', 'Postpone my studies'),
      'withdraw' => t('الانسحاب وسحب الملف', 'Withdraw from the faculty'),
      'transfer_out' => t('التحويل إلى جهة أخرى', 'Transfer to another faculty'),
      'reenrol' => t('إعادة القيد', 'Re-enrol'),
      'excuse' => t('عذر مقبول', 'An accepted excuse'),
      'data_update' => t('تحديث بياناتي', 'Update my details'),
      _ => t('طلب', 'A request'),
    };

/// One plain sentence: what the request does, for a student who has never read the bylaw.
String requestKindHint(String key) => switch (key) {
      'suspend' => t('توقف دراستك مؤقتاً حتى تاريخ تحدده، ثم تعود إلى مكانك.', 'Pause your studies until a date you choose, then come back where you left.'),
      'postpone' => t('تؤجل الدراسة أو الامتحانات لفصل أو أكثر بعذر.', 'Put your studies or exams off for a term or more, with a reason.'),
      'withdraw' => t('تنهي دراستك هنا وتسحب ملفك. لا يحدث شيء قبل الموافقة.', 'End your studies here and take your file. Nothing happens before it is approved.'),
      'transfer_out' => t('تنتقل إلى كلية أو جامعة أخرى.', 'Move to another faculty or university.'),
      'reenrol' => t('تعود إلى الدراسة بعد وقف أو انقطاع.', 'Come back to your studies after a pause or a break.'),
      'excuse' => t('تقدّم عذراً عن غياب أو امتحان فاتك.', 'Give a reason for an absence or a missed exam.'),
      'data_update' => t('تطلب تصحيح بيانات في ملفك، مثل العنوان أو الهاتف.', 'Ask to correct details in your file, such as an address or a phone number.'),
      _ => '',
    };

IconData requestKindIcon(String key) => switch (key) {
      'suspend' => Icons.pause_circle_outline_rounded,
      'postpone' => Icons.event_repeat_rounded,
      'withdraw' => DirIcons.exitToApp,
      'transfer_out' => Icons.swap_horiz_rounded,
      'reenrol' => Icons.replay_rounded,
      'excuse' => Icons.medical_information_outlined,
      'data_update' => Icons.edit_note_rounded,
      _ => Icons.description_outlined,
    };

/// Stages of item_out: review · council · approved · rejected · withdrawn · closed.
String requestStageLabel(String stage) => switch (stage) {
      'review' => t('قيد المراجعة', 'In review'),
      'council' => t('معروض على المجلس', 'Before the council'),
      'approved' => t('تمت الموافقة', 'Approved'),
      'rejected' => t('لم تتم الموافقة', 'Not approved'),
      'withdrawn' => t('سُحب الطلب', 'Withdrawn'),
      'closed' => t('أُغلق', 'Closed'),
      _ => t('قُدِّم', 'Submitted'),
    };

AppTone requestStageTone(String stage) => switch (stage) {
      'approved' => AppTone.success,
      'rejected' => AppTone.danger,
      'council' => AppTone.info,
      'review' => AppTone.warning,
      _ => AppTone.neutral,
    };

/// The reached stop of AppStatusPath.request (0 submitted · 1 in review · 2 decided).
int requestPathReached(String stage) => switch (stage) {
      'approved' || 'rejected' || 'closed' => 2,
      'review' || 'council' => 1,
      _ => 0,
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Models
// ═════════════════════════════════════════════════════════════════════════════

DateTime? _day(dynamic v) {
  final s = asStr(v).trim();
  if (s.length < 10) return null;
  return DateTime.tryParse(s.substring(0, 10));
}

String? _opt(dynamic v) {
  final s = v == null ? '' : '$v'.trim();
  return s.isEmpty ? null : s;
}

double? _num(dynamic v) {
  if (v == null || v == '') return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

/// "3" for 3.0, "1.5" for 1.5.
String creditHoursText(double? h) {
  if (h == null) return '—';
  var s = h.toStringAsFixed(2);
  while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// One editable detail of a data update: `{key, label_ar, label_en, kind}`.
class RequestField {
  const RequestField({required this.key, this.labelAr = '', this.labelEn = '', this.kind = 'text'});
  final String key, labelAr, labelEn, kind;

  String get label => _pick(labelAr, labelEn).isEmpty ? key : _pick(labelAr, labelEn);

  factory RequestField.fromJson(Map<String, dynamic> m) =>
      RequestField(key: asStr(m['key']), labelAr: asStr(m['label_ar']), labelEn: asStr(m['label_en']), kind: asStr(m['kind']).isEmpty ? 'text' : asStr(m['kind']));
}

/// One request the student may make, from `options` of GET my-requests.
class RequestOption {
  const RequestOption({
    required this.request,
    this.labelAr = '',
    this.labelEn = '',
    this.needs = const [],
    this.allowed = true,
    this.openItemId,
    this.fields = const [],
    this.reasonCodes = const [],
  });

  final String request, labelAr, labelEn;
  final List<String> needs;
  final bool allowed;

  /// The same request is already in review (409 `request_open` on a second one).
  final int? openItemId;
  final List<RequestField> fields;
  final List<String> reasonCodes;

  String get label => _pick(labelAr, labelEn).isEmpty ? requestKindLabel(request) : _pick(labelAr, labelEn);
  bool get isDataUpdate => request == 'data_update';
  bool get needsUntil => needs.contains('effective_to');
  bool get needsReason => needs.contains('reason');

  /// May be started now (allowed, and none of the same kind open).
  bool get canStart => allowed && openItemId == null;

  factory RequestOption.fromJson(Map<String, dynamic> m) => RequestOption(
        request: asStr(m['request']),
        labelAr: asStr(m['label_ar']),
        labelEn: asStr(m['label_en']),
        needs: [for (final n in (m['needs'] is List ? m['needs'] as List : const [])) '$n'],
        allowed: m['allowed'] == null ? true : asBool(m['allowed']),
        openItemId: m['open_item_id'] == null ? null : asInt(m['open_item_id']),
        fields: [for (final f in asMapList(m['fields'])) RequestField.fromJson(f)],
        reasonCodes: [for (final r in (m['reason_codes'] is List ? m['reason_codes'] as List : const [])) '$r'],
      );
}

class RequestCouncil {
  const RequestCouncil({required this.deptId, this.councilId, this.level = 0, this.nameAr = '', this.nameEn = ''});
  final int deptId;
  final int? councilId;
  final int level;
  final String nameAr, nameEn;

  String get name => _pick(nameAr, nameEn).isEmpty ? t('مجلس', 'A council') : _pick(nameAr, nameEn);

  factory RequestCouncil.fromJson(Map<String, dynamic> m) => RequestCouncil(
        deptId: asInt(m['dept_id']),
        councilId: m['council_id'] == null ? null : asInt(m['council_id']),
        level: asInt(m['level']),
        nameAr: asStr(m['name_ar']),
        nameEn: asStr(m['name_en']),
      );
}

class RequestCan {
  const RequestCan({this.accept = false, this.reject = false, this.council = false});
  final bool accept, reject, council;

  bool get any => accept || reject || council;

  factory RequestCan.fromJson(Map<String, dynamic> m) =>
      RequestCan(accept: asBool(m['accept']), reject: asBool(m['reject']), council: asBool(m['council']));
}

/// One lifecycle request (server item_out; the staff keys come from GET …/students/requests/{id}).
class LifecycleRequest {
  const LifecycleRequest({
    required this.id,
    this.ref = '',
    this.request = '',
    this.labelAr = '',
    this.labelEn = '',
    this.status = '',
    this.stage = 'review',
    this.origin,
    this.reason,
    this.reasonCode,
    this.effectiveFrom,
    this.effectiveTo,
    this.changes = const {},
    this.decisionNo,
    this.applied = false,
    this.note,
    this.createdAt,
    this.decidedAt,
    this.canWithdraw = false,
    this.studentId,
    this.decision,
    this.title = '',
    this.bodyKey,
    this.needsDecisionNo = false,
    this.councils = const [],
    this.can = const RequestCan(),
  });

  final int id;
  final String ref, request, labelAr, labelEn, status, stage;
  final String? origin, reason, reasonCode;
  final DateTime? effectiveFrom, effectiveTo;
  final Map<String, String> changes;
  final String? decisionNo;
  final bool applied;

  /// The reviewer's reason of a rejection (the student reads it).
  final String? note;
  final DateTime? createdAt, decidedAt;
  final bool canWithdraw;

  // staff
  final int? studentId;

  /// The status decision key behind it (null = a data update).
  final String? decision;
  final String title;
  final String? bodyKey;
  final bool needsDecisionNo;
  final List<RequestCouncil> councils;
  final RequestCan can;

  String get label => _pick(labelAr, labelEn).isEmpty ? requestKindLabel(request) : _pick(labelAr, labelEn);
  bool get isOpen => stage == 'review' || stage == 'council';
  bool get isDataUpdate => request == 'data_update' || (decision == null && changes.isNotEmpty);

  /// "Ahmed Ali" out of the server title "وقف القيد: Ahmed Ali".
  String get studentName {
    final i = title.indexOf(':');
    return i < 0 ? '' : title.substring(i + 1).trim();
  }

  factory LifecycleRequest.fromJson(Map<String, dynamic> m) {
    final params = asMap(m['params']);
    final ch = asMap(m['changes']);
    return LifecycleRequest(
      id: asInt(m['id']),
      ref: asStr(m['ref']),
      request: asStr(m['request']),
      labelAr: asStr(m['label_ar']),
      labelEn: asStr(m['label_en']),
      status: asStr(m['status']),
      stage: asStr(m['stage']).isEmpty ? 'review' : asStr(m['stage']),
      origin: _opt(m['origin']),
      reason: _opt(m['reason']),
      reasonCode: _opt(m['reason_code']),
      effectiveFrom: _day(m['effective_from']),
      effectiveTo: _day(m['effective_to']),
      changes: {for (final e in ch.entries) e.key: e.value == null ? '' : '${e.value}'},
      decisionNo: _opt(m['decision_no']),
      applied: asBool(m['applied']),
      note: _opt(m['note']),
      createdAt: orgParseUtc(m['created_at']),
      decidedAt: orgParseUtc(m['decided_at']),
      canWithdraw: asBool(m['can_withdraw']),
      studentId: m['student_id'] == null ? null : asInt(m['student_id']),
      decision: _opt(params['decision']),
      title: asStr(m['title']),
      bodyKey: _opt(m['body_key']),
      needsDecisionNo: asBool(m['needs_decision_no']),
      councils: [for (final c in asMapList(m['councils'])) RequestCouncil.fromJson(c)],
      can: RequestCan.fromJson(asMap(m['can'])),
    );
  }
}

class MyRequests {
  const MyRequests({this.options = const [], this.items = const []});
  final List<RequestOption> options;
  final List<LifecycleRequest> items;

  List<LifecycleRequest> get open => [for (final i in items) if (i.isOpen) i];
  List<LifecycleRequest> get closed => [for (final i in items) if (!i.isOpen) i];

  RequestOption? option(String request) {
    for (final o in options) {
      if (o.request == request) return o;
    }
    return null;
  }

  factory MyRequests.fromJson(Map<String, dynamic> m) => MyRequests(
        options: [for (final o in asMapList(m['options'])) RequestOption.fromJson(o)],
        items: [for (final i in asMapList(m['items'])) LifecycleRequest.fromJson(i)],
      );
}

/// What the student fills in before sending (MyRequestIn).
class RequestDraft {
  RequestDraft(this.request);
  final String request;
  String reason = '';
  String? reasonCode;
  DateTime? effectiveFrom, effectiveTo;
  final Map<String, String> changes = {};

  /// Picked files, uploaded already (ids), sent on one comment after the request is created.
  final List<GovAttachment> documents = [];

  /// The first problem as a code of [requestsCodeTexts] / status codes, null when it may go.
  String? check(RequestOption o) {
    if (o.isDataUpdate) {
      if (changes.values.every((v) => v.trim().isEmpty)) return 'changes_required';
      return null;
    }
    if (reason.trim().length < 3) return 'reason_required';
    if (o.needsUntil && effectiveTo == null) return 'dates_required';
    final f = effectiveFrom, to = effectiveTo;
    if (f != null && to != null && !to.isAfter(f)) return 'bad_dates';
    return null;
  }

  Map<String, dynamic> toJson() => {
        'request': request,
        if (reason.trim().isNotEmpty) 'reason': reason.trim(),
        'reason_code': ?reasonCode,
        if (effectiveFrom != null) 'effective_from': ymd(effectiveFrom!),
        if (effectiveTo != null) 'effective_to': ymd(effectiveTo!),
        if (request == 'data_update')
          'changes': {
            for (final e in changes.entries)
              if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
          },
      };
}

/// What the reviewer adds on Accept (AcceptIn).
class AcceptDraft {
  String decisionNo = '';
  DateTime? decisionDate;
  String note = '';
  bool override = false;

  String? check(LifecycleRequest r) {
    if (r.needsDecisionNo && (decisionNo.trim().isEmpty || decisionDate == null)) return 'decision_no_required';
    return null;
  }

  Map<String, dynamic> toJson() => {
        if (decisionNo.trim().isNotEmpty) 'decision_no': decisionNo.trim(),
        if (decisionDate != null) 'decision_date': ymd(decisionDate!),
        if (note.trim().isNotEmpty) 'note': note.trim(),
        if (override) 'override': true,
      };
}

// ── transfer credit ─────────────────────────────────────────────────────────

const creditDecisions = ['pending', 'credited', 'not_credited'];

String creditDecisionLabel(String d) => switch (d) {
      'credited' => t('تمت المقاصة', 'Credited'),
      'not_credited' => t('لم تُحتسب', 'Not credited'),
      _ => t('قيد الدراسة', 'Pending'),
    };

AppTone creditDecisionTone(String d) => switch (d) {
      'credited' => AppTone.success,
      'not_credited' => AppTone.danger,
      _ => AppTone.warning,
    };

class CourseChoice {
  const CourseChoice({required this.id, this.code, this.nameAr = '', this.nameEn = '', this.creditHours});
  final int id;
  final String? code;
  final String nameAr, nameEn;
  final double? creditHours;

  String get name => _pick(nameAr, nameEn).isEmpty ? '#$id' : _pick(nameAr, nameEn);
  String get label => code == null || code!.isEmpty ? name : '$code · $name';

  factory CourseChoice.fromJson(Map<String, dynamic> m) => CourseChoice(
        id: asInt(m['id']),
        code: _opt(m['code']),
        nameAr: asStr(m['name_ar']),
        nameEn: asStr(m['name_en']),
        creditHours: _num(m['credit_hours']),
      );
}

class TransferCredit {
  const TransferCredit({
    required this.id,
    this.sourceInstitution,
    this.sourceCourse = '',
    this.sourceCode,
    this.sourceGrade,
    this.sourceCredits,
    this.course,
    this.creditedHours,
    this.countedHours = 0,
    this.decision = 'pending',
    this.countsInGpa = false,
    this.belowMin = false,
    this.note,
    this.decidedBy,
    this.decidedAt,
  });

  final int id;
  final String? sourceInstitution;
  final String sourceCourse;
  final String? sourceCode, sourceGrade;
  final double? sourceCredits;

  /// Our equivalent course (null = not chosen yet; crediting needs one: 422 `course_required`).
  final CourseChoice? course;

  /// Hours it counts for here when set by hand (null = the course's own hours).
  final double? creditedHours;

  /// What it counts for now (0 unless credited).
  final double countedHours;
  final String decision;
  final bool countsInGpa;

  /// The source grade is under the organization's minimum letter (a warning; the body still decides).
  final bool belowMin;
  final String? note;
  final String? decidedBy;
  final DateTime? decidedAt;

  bool get pending => decision == 'pending';

  /// The hours it would count for if credited.
  double? get hoursHere => creditedHours ?? course?.creditHours;

  factory TransferCredit.fromJson(Map<String, dynamic> m) {
    final c = asMap(m['course']);
    final by = asMap(m['decided_by']);
    return TransferCredit(
      id: asInt(m['id']),
      sourceInstitution: _opt(m['source_institution']),
      sourceCourse: asStr(m['source_course']),
      sourceCode: _opt(m['source_code']),
      sourceGrade: _opt(m['source_grade']),
      sourceCredits: _num(m['source_credits']),
      course: c.isEmpty || c['id'] == null ? null : CourseChoice.fromJson(c),
      creditedHours: _num(m['credited_hours']),
      countedHours: _num(m['counted_hours']) ?? 0,
      decision: asStr(m['decision']).isEmpty ? 'pending' : asStr(m['decision']),
      countsInGpa: asBool(m['counts_in_gpa']),
      belowMin: asBool(m['below_min']),
      note: _opt(m['note']),
      decidedBy: _opt(by['name']),
      decidedAt: orgParseUtc(m['decided_at']),
    );
  }
}

class TransferCreditSettings {
  const TransferCreditSettings({this.countsInGpa = false, this.minLetter});
  final bool countsInGpa;
  final String? minLetter;

  factory TransferCreditSettings.fromJson(Map<String, dynamic> m) =>
      TransferCreditSettings(countsInGpa: asBool(m['counts_in_gpa']), minLetter: _opt(m['min_letter']));

  Map<String, dynamic> toJson() => {'counts_in_gpa': countsInGpa, 'min_letter': minLetter};
}

class TransferCredits {
  const TransferCredits({
    this.items = const [],
    this.settings = const TransferCreditSettings(),
    this.pending = 0,
    this.credited = 0,
    this.creditedHours = 0,
    this.gpaHours = 0,
    this.canEdit = false,
    this.canDecide = false,
  });

  final List<TransferCredit> items;
  final TransferCreditSettings settings;
  final int pending, credited;
  final double creditedHours, gpaHours;
  final bool canEdit, canDecide;

  factory TransferCredits.fromJson(Map<String, dynamic> m) {
    final s = asMap(m['summary']);
    final can = asMap(m['can']);
    return TransferCredits(
      items: [for (final i in asMapList(m['items'])) TransferCredit.fromJson(i)],
      settings: TransferCreditSettings.fromJson(asMap(m['settings'])),
      pending: asInt(s['pending']),
      credited: asInt(s['credited']),
      creditedHours: _num(s['credited_hours']) ?? 0,
      gpaHours: _num(s['gpa_hours']) ?? 0,
      canEdit: asBool(can['edit']),
      canDecide: asBool(can['decide']),
    );
  }
}

/// The add / edit form of one equivalence (CreditIn). Text fields hold what was typed.
class CreditDraft {
  CreditDraft();

  factory CreditDraft.of(TransferCredit c) => CreditDraft()
    ..sourceInstitution = c.sourceInstitution ?? ''
    ..sourceCourse = c.sourceCourse
    ..sourceCode = c.sourceCode ?? ''
    ..sourceGrade = c.sourceGrade ?? ''
    ..sourceCredits = c.sourceCredits == null ? '' : creditHoursText(c.sourceCredits)
    ..course = c.course
    ..creditedHours = c.creditedHours == null ? '' : creditHoursText(c.creditedHours)
    ..countsInGpa = c.countsInGpa
    ..note = c.note ?? '';

  String sourceInstitution = '';
  String sourceCourse = '';
  String sourceCode = '';
  String sourceGrade = '';
  String sourceCredits = '';
  CourseChoice? course;
  String creditedHours = '';
  bool? countsInGpa;
  String note = '';

  static bool _hoursOk(String s) {
    if (s.trim().isEmpty) return true;
    final v = double.tryParse(s.trim().replaceAll(',', '.'));
    return v != null && v >= 0 && v <= 60;
  }

  /// The first bad field's key, null when it may be saved.
  String? check() {
    if (sourceCourse.trim().isEmpty) return 'source_course';
    if (!_hoursOk(sourceCredits)) return 'source_credits';
    if (!_hoursOk(creditedHours)) return 'credited_hours';
    return null;
  }

  static double? _h(String s) => s.trim().isEmpty ? null : double.tryParse(s.trim().replaceAll(',', '.'));
  static String? _s(String s) => s.trim().isEmpty ? null : s.trim();

  /// Every source key is sent (a PATCH clears what was emptied).
  Map<String, dynamic> toJson() => {
        'source_institution': _s(sourceInstitution),
        'source_course': sourceCourse.trim(),
        'source_code': _s(sourceCode),
        'source_grade': _s(sourceGrade),
        'source_credits': _h(sourceCredits),
        'course_id': course?.id,
        'credited_hours': _h(creditedHours),
        'counts_in_gpa': ?countsInGpa,
        'note': _s(note),
      };
}

// ═════════════════════════════════════════════════════════════════════════════
//  API
// ═════════════════════════════════════════════════════════════════════════════

class StudentRequestsApi {
  StudentRequestsApi(this.orgId, [ApiClient? api]) : _api = api ?? ApiClient();
  final int orgId;
  final ApiClient _api;

  String get base => '$orgBase/orgs/$orgId/students';
  String get mine => '$orgBase/public/$orgId/my-requests';

  // ── the student ───────────────────────────────────────────────────────────

  Future<OrgCall> myRequests({bool quiet = true}) => orgCall(() => _api.get(mine), quiet: quiet);

  /// [body] is `RequestDraft.toJson()`.
  Future<OrgCall> submit(Map<String, dynamic> body, {bool quiet = true}) => orgCall(() => _api.post(mine, body: body), quiet: quiet);

  Future<OrgCall> withdraw(int id, {bool quiet = true}) => orgCall(() => _api.post('$mine/$id/withdraw', body: const {}), quiet: quiet);

  /// The supporting documents of request [id] on one governance comment (the request IS a governance item).
  Future<OrgCall> attach(int id, List<GovAttachment> files, {bool quiet = true}) => orgCall(
      () => GovApi.memberComment(id, t('المستندات المؤيدة للطلب', 'Supporting documents'), attachments: files, client: _api),
      quiet: quiet);

  // ── staff ─────────────────────────────────────────────────────────────────

  Future<OrgCall> detail(int id, {bool quiet = true}) => orgCall(() => _api.get('$base/requests/$id'), quiet: quiet);

  /// [body] is `AcceptDraft.toJson()`.
  Future<OrgCall> accept(int id, Map<String, dynamic> body, {bool quiet = true}) =>
      orgCall(() => _api.post('$base/requests/$id/accept', body: body), quiet: quiet);

  /// [note] (≥ 3 characters) reaches the student.
  Future<OrgCall> reject(int id, String note, {bool quiet = true}) =>
      orgCall(() => _api.post('$base/requests/$id/reject', body: {'note': note}), quiet: quiet);

  /// 409 `no_council` carries `councils` in `r.detail`: ask which one and send again with [councilDeptId].
  Future<OrgCall> toCouncil(int id, {int? councilDeptId, String? note, bool quiet = true}) => orgCall(
      () => _api.post('$base/requests/$id/council', body: {
            'council_dept_id': ?councilDeptId,
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          }),
      quiet: quiet);

  /// A status decision for student [uid] put before a council through Governance: [body] is StatusIn plus
  /// `council_dept_id?`, `note?` → 201 the request.
  Future<OrgCall> statusToCouncil(int uid, Map<String, dynamic> body, {bool quiet = true}) =>
      orgCall(() => _api.post('$base/$uid/status/council', body: body), quiet: quiet);

  Future<OrgCall> credits(int uid, {bool quiet = true}) => orgCall(() => _api.get('$base/$uid/transfer-credits'), quiet: quiet);

  /// [body] is `CreditDraft.toJson()`, plus `decision` when an approver adds a decided row.
  Future<OrgCall> addCredit(int uid, Map<String, dynamic> body, {bool quiet = true}) =>
      orgCall(() => _api.post('$base/$uid/transfer-credits', body: body), quiet: quiet);

  /// Only the keys sent change; `decision` needs academic:approve.
  Future<OrgCall> patchCredit(int id, Map<String, dynamic> body, {bool quiet = true}) =>
      orgCall(() => _api.patch('$base/transfer-credits/$id', body: body), quiet: quiet);

  Future<OrgCall> deleteCredit(int id, {bool quiet = true}) => orgCall(() => _api.delete('$base/transfer-credits/$id'), quiet: quiet);

  /// The WHOLE settings object (academic:update).
  Future<OrgCall> saveCreditSettings(TransferCreditSettings s, {bool quiet = true}) =>
      orgCall(() => _api.put('$base/transfer-credits/settings', body: s.toJson()), quiet: quiet);

  /// The organization's courses (its whole tree) to pick "our course" from.
  Future<OrgCall> courses({String? search, bool quiet = true}) => orgCall(
      () => _api.get('$orgBase/orgs/$orgId/courses', queryParams: {
            'scope': 'tree',
            'size': 50,
            if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
          }),
      quiet: quiet);
}

List<CourseChoice> courseChoicesOf(Map<String, dynamic> m) => [for (final c in asMapList(m['items'])) CourseChoice.fromJson(c)];

// ═════════════════════════════════════════════════════════════════════════════
//  Error texts
// ═════════════════════════════════════════════════════════════════════════════

Map<String, String> requestsCodeTexts() => {
      'request_closed': t('تم البت في هذا الطلب أو سحبه من قبل', 'This request was already decided or withdrawn'),
      'request_open': t('لديك طلب من النوع نفسه قيد المراجعة؛ انتظر قراره أو اسحبه أولاً', 'You already have the same request in review; wait for its answer or withdraw it first'),
      'request_not_found': t('الطلب غير موجود', 'This request does not exist'),
      'request_unknown': t('نوع الطلب غير معروف', 'Unknown request type'),
      'no_student_affairs': t('لا توجد بعد إدارة شؤون طلاب تستقبل الطلبات؛ تواصل مع مؤسستك', 'There is no Student Affairs office to receive requests yet; contact your organization'),
      'no_council': t('اختر المجلس الذي يعرض عليه الطلب', 'Choose the council that votes on the request'),
      'not_council_body': t('هذا القرار لا يُعرض على مجلس حسب مصفوفة القرارات', 'The decision matrix does not give this decision to a council'),
      'council_not_found': t('المجلس غير موجود أو موقوف', 'The council does not exist or is switched off'),
      'no_case': t('لا يوجد ملف التحاق لتحديث بياناته', 'There is no admission file to update'),
      'field_not_editable': t('لا يمكن طلب تعديل هذا البند؛ يعدله الموظف بمستند', 'This detail cannot be changed by a request; staff change it with a document'),
      'changes_required': t('اكتب القيمة الجديدة لبند واحد على الأقل', 'Write the new value of at least one detail'),
      'credit_decided': t('تم البت في هذه المقاصة؛ لا يعدلها إلا من يعتمدها', 'This credit was decided; only an approver can change it'),
      'course_required': t('اختر المقرر المعادل لدينا قبل اعتماد المقاصة', 'Choose our equivalent course before crediting'),
      'course_not_found': t('المقرر غير موجود في هذه المؤسسة', 'The course is not in this organization'),
      'bad_transfer_credit': t('قيمة غير صالحة؛ راجع الساعات (من 0 إلى 60) والتقدير', 'A value is not valid; check the hours (0 to 60) and the grade'),
      'transfer_credit_not_found': t('سجل المقاصة غير موجود', 'This transfer credit does not exist'),
    };

String requestsErrorText(ApiException e) {
  final c = e.code;
  if (c == 'rule_blocks') {
    // the server names the rule that stops it
    final d = ApiException.asMap(e.body)?['detail'];
    final en = d is Map ? asStr(d['message_en']).trim() : '';
    final ar = e.message.trim();
    final s = AppConfig.lang == 'en' && en.isNotEmpty ? en : ar;
    if (s.isNotEmpty) return s;
  }
  if (c == null) return orgErrorText(e);
  return requestsCodeTexts()[c] ?? statusCodeTexts()[c] ?? orgErrorText(e);
}

/// The councils a 409 `no_council` lists in its detail.
List<RequestCouncil> councilsOfError(OrgCall r) => [for (final c in asMapList(r.detail['councils'])) RequestCouncil.fromJson(c)];
