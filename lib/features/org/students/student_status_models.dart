// lib/features/org/students/student_status_models.dart — plain parse classes and pure rules of phase 2 (student
// lifecycle contract §6): statuses, decisions, undo, the student's own status. No widgets, no network.
//
//   vocabulary      decision keys (§6.1) and what each writes, reason codes, dismissal reasons, deciding bodies, all
//                   with bilingual labels (decisionText, reasonText, dismissReasonText, bodyText); a unit test checks
//                   every value has one
//   StatusEvent     one row of `org_student_status_events` + actor, title, can_undo, undone
//   StatusOption    one change the caller may make (`options` of GET …/status): mode decide | propose, needs, blocked
//   StudentStatus   GET …/status
//   StatusDraft     the sheet's form → `StatusIn` (toJson), its first problem (problem / problemText) and the plain
//                   preview sentence (statusPreview)
//   StatusResult    what the sheet / the undo confirm return to the caller
//   MyStatus        GET /public/{org}/my-status (the student himself; staff-only flags removed again here)
//   LifecycleSettings / DecisionRule   GET / PUT …/students/settings (§6.4)
//   statusCodeTexts the bilingual texts of the §6.3 codes
//
// Dates of a decision are calendar dates (`YYYY-MM-DD`, shown with AppTime.wall); `created_at` is naive UTC (read with
// orgParseUtc, shown with AppTime). Every parser is lenient: a missing key gives a default.
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';

import '../../admin/admin_common.dart' show t, asMap, asMapList, asInt, asStr, asBool;
import '../org_v3.dart' show orgParseUtc;
import 'students_models.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Vocabulary (§1, §6.1)
// ═════════════════════════════════════════════════════════════════════════════

/// The kill switch of statuses (§12); off → the server answers 409 `status_disabled`.
const kStudentsStatusKey = 'org.students.status';

/// What a decision writes: the dimension, the value (enrolment / standing; null when the caller picks it) and, for a
/// flag, its key.
typedef DecisionTarget = ({String dimension, String? to, String? flag});

/// Every decision key of §6.1, in the order the sheet lists them.
const Map<String, DecisionTarget> decisionTargets = {
  'suspend': (dimension: 'enrolment', to: 'suspended', flag: null),
  'suspend_extend': (dimension: 'enrolment', to: 'suspended', flag: null),
  'postpone': (dimension: 'enrolment', to: 'postponed', flag: null),
  'resume': (dimension: 'enrolment', to: 'enrolled', flag: null),
  'disc_suspend': (dimension: 'enrolment', to: 'disc_suspended', flag: null),
  'outside': (dimension: 'enrolment', to: 'outside', flag: null),
  'dismiss_academic': (dimension: 'enrolment', to: 'dismissed', flag: null),
  'dismiss_disciplinary': (dimension: 'enrolment', to: 'dismissed', flag: null),
  'withdraw': (dimension: 'enrolment', to: 'withdrawn', flag: null),
  'cancel': (dimension: 'enrolment', to: 'cancelled', flag: null),
  'transfer_out': (dimension: 'enrolment', to: 'transferred_out', flag: null),
  'reenrol': (dimension: 'enrolment', to: 'enrolled', flag: null),
  'graduate_undo': (dimension: 'enrolment', to: 'enrolled', flag: null),
  'deceased': (dimension: 'enrolment', to: 'deceased', flag: null),
  'standing_override': (dimension: 'standing', to: null, flag: null),
  'final_chance': (dimension: 'standing', to: 'final_chance', flag: null),
  'flag.struggling': (dimension: 'flag', to: null, flag: 'struggling'),
  'flag.special_case': (dimension: 'flag', to: null, flag: 'special_case'),
  'flag.conscripted': (dimension: 'flag', to: null, flag: 'conscripted'),
  'flag.excuse_open': (dimension: 'flag', to: null, flag: 'excuse_open'),
  'flag.disciplinary_record': (dimension: 'flag', to: null, flag: 'disciplinary_record'),
};

const decisionKeys = [
  'suspend', 'suspend_extend', 'postpone', 'resume', 'disc_suspend', 'outside', 'dismiss_academic', 'dismiss_disciplinary',
  'withdraw', 'cancel', 'transfer_out', 'reenrol', 'graduate_undo', 'deceased', 'standing_override', 'final_chance',
  'flag.struggling', 'flag.special_case', 'flag.conscripted', 'flag.excuse_open', 'flag.disciplinary_record',
];

/// The keys whose matrix entry may be `auto`.
const decisionAutoOk = {'dismiss_academic', 'final_chance'};

/// Changes that take a student out of the institution (the confirm is red), used when the server does not say.
const decisionDangerous = {'dismiss_academic', 'dismiss_disciplinary', 'cancel', 'withdraw', 'transfer_out', 'deceased', 'disc_suspend'};

const Map<String, BiText> decisionText = {
  'suspend': ('إيقاف القيد', 'Suspend enrolment'),
  'suspend_extend': ('تمديد إيقاف القيد', 'Extend the suspension'),
  'postpone': ('تأجيل الدراسة', 'Postpone studies'),
  'resume': ('استئناف القيد', 'Resume enrolment'),
  'disc_suspend': ('إيقاف تأديبي', 'Disciplinary suspension'),
  'outside': ('الدراسة من الخارج', 'Sit exams from outside'),
  'dismiss_academic': ('فصل لأسباب أكاديمية', 'Dismiss (academic)'),
  'dismiss_disciplinary': ('فصل تأديبي', 'Dismiss (disciplinary)'),
  'withdraw': ('انسحاب وسحب الملف', 'Withdraw (file collected)'),
  'cancel': ('إلغاء القيد', 'Cancel enrolment'),
  'transfer_out': ('تحويل إلى جهة أخرى', 'Transfer out'),
  'reenrol': ('إعادة القيد', 'Re-enrol'),
  'graduate_undo': ('إلغاء التخرج', 'Undo graduation'),
  'deceased': ('تسجيل وفاة', 'Record a death'),
  'standing_override': ('تصحيح الوضع الأكاديمي', 'Correct the academic standing'),
  'final_chance': ('منح فرصة أخيرة', 'Grant a final chance'),
  'flag.struggling': ('متعثر', 'Struggling'),
  'flag.special_case': ('حالة خاصة', 'Special case'),
  'flag.conscripted': ('مجنّد', 'Conscripted'),
  'flag.excuse_open': ('عذر مقبول', 'Accepted excuse'),
  'flag.disciplinary_record': ('سجل تأديبي', 'Disciplinary record'),
};

const reasonCodes = [
  'military', 'illness', 'abroad_work', 'abroad_spouse', 'child_care', 'parent_care', 'detention', 'own_request', 'fees',
  'transfer_same_univ', 'transfer_other_univ', 'penalty', 'complaint', 'appeal', 'leniency', 'data_error', 'other',
];

const Map<String, BiText> reasonText = {
  'military': ('الخدمة العسكرية', 'Military service'),
  'illness': ('مرض', 'Illness'),
  'abroad_work': ('عمل بالخارج', 'Work abroad'),
  'abroad_spouse': ('مرافقة الزوج أو الزوجة بالخارج', 'Joining a spouse abroad'),
  'child_care': ('رعاية طفل', 'Caring for a child'),
  'parent_care': ('رعاية أحد الوالدين', 'Caring for a parent'),
  'detention': ('احتجاز', 'Detention'),
  'own_request': ('بناءً على طلب الطالب', 'At the student\'s request'),
  'fees': ('عدم سداد المصروفات', 'Unpaid fees'),
  'transfer_same_univ': ('تحويل داخل الجامعة', 'Transfer within the university'),
  'transfer_other_univ': ('تحويل إلى جامعة أخرى', 'Transfer to another university'),
  'penalty': ('جزاء', 'A penalty'),
  'complaint': ('بناءً على شكوى', 'Following a complaint'),
  'appeal': ('تظلم', 'An appeal'),
  'leniency': ('رأفة', 'Leniency'),
  'data_error': ('تصحيح خطأ في البيانات', 'Correcting a data error'),
  'other': ('سبب آخر', 'Another reason'),
};

const dismissReasons = ['chances_exhausted', 'gpa', 'max_duration', 'not_registered', 'disciplinary'];

const Map<String, BiText> dismissReasonText = {
  'chances_exhausted': ('استنفد مرات الرسوب', 'Used up the failure chances'),
  'gpa': ('انخفاض المعدل التراكمي', 'GPA too low'),
  'max_duration': ('تجاوز المدة القصوى للدراسة', 'Passed the longest study time'),
  'not_registered': ('لم يسجّل مقررات', 'Did not register courses'),
  'disciplinary': ('قرار تأديبي', 'A disciplinary decision'),
};

const decisionBodies = [
  'student_affairs', 'education_committee', 'faculty_council', 'university_council', 'dean', 'university_president',
  'disciplinary_board', 'department_council',
];

const Map<String, BiText> bodyText = {
  'student_affairs': ('شؤون الطلاب', 'Student affairs'),
  'education_committee': ('لجنة شؤون التعليم والطلاب', 'Education and students committee'),
  'faculty_council': ('مجلس الكلية', 'Faculty council'),
  'university_council': ('مجلس الجامعة', 'University council'),
  'dean': ('عميد الكلية', 'Dean'),
  'university_president': ('رئيس الجامعة', 'University president'),
  'disciplinary_board': ('مجلس التأديب', 'Disciplinary board'),
  'department_council': ('مجلس القسم', 'Department council'),
};

/// The reasons offered first for a decision (the rest stay under "Another reason"); null = every reason code.
const Map<String, List<String>> decisionReasons = {
  'suspend': ['illness', 'military', 'abroad_work', 'abroad_spouse', 'child_care', 'parent_care', 'detention', 'own_request', 'other'],
  'suspend_extend': ['illness', 'military', 'abroad_work', 'abroad_spouse', 'child_care', 'parent_care', 'detention', 'other'],
  'postpone': ['military', 'illness', 'abroad_work', 'abroad_spouse', 'child_care', 'parent_care', 'own_request', 'other'],
  'withdraw': ['own_request', 'transfer_other_univ', 'fees', 'other'],
  'cancel': ['own_request', 'fees', 'penalty', 'data_error', 'other'],
  'transfer_out': ['transfer_same_univ', 'transfer_other_univ', 'other'],
  'standing_override': ['appeal', 'leniency', 'data_error', 'other'],
};

String _label(Map<String, BiText> m, String v) {
  final x = m[v];
  return x == null ? v : biText(x);
}

String decisionLabel(String key) => _label(decisionText, key);
String reasonLabel(String code) => _label(reasonText, code);
String dismissReasonLabel(String code) => _label(dismissReasonText, code);
String bodyLabel(String body) => _label(bodyText, body);

/// The body inside an English sentence ("goes to the faculty council"); the Arabic label as it is.
String bodyPhrase(String body) {
  final x = bodyText[body];
  if (x == null) return body;
  if (AppConfig.lang != 'en') return x.$1;
  final en = x.$2.toLowerCase();
  return body == 'student_affairs' ? en : 'the $en';
}

/// The reason codes the sheet offers for [decision]: dismissal reasons for an academic dismissal, the short list of
/// [decisionReasons], otherwise every code.
List<String> reasonChoices(String decision) {
  if (decision == 'dismiss_academic') return const ['chances_exhausted', 'gpa', 'max_duration', 'not_registered'];
  if (decision == 'dismiss_disciplinary') return const ['disciplinary'];
  return decisionReasons[decision] ?? reasonCodes;
}

/// The label of a reason code of either list.
String anyReasonLabel(String code) => dismissReasonText.containsKey(code) ? dismissReasonLabel(code) : reasonLabel(code);

/// `YYYY-MM-DD` of a calendar date.
String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A `YYYY-MM-DD` (or an ISO date-time: its date part) → the calendar date; null when empty or unreadable.
DateTime? parseYmd(dynamic v) {
  final s = asStr(v).trim();
  if (s.length < 10) return null;
  final p = s.substring(0, 10).split('-');
  if (p.length != 3) return null;
  final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

String? _opt(dynamic v) {
  final s = asStr(v).trim();
  return s.isEmpty ? null : s;
}

int? _optInt(dynamic v) {
  final n = asInt(v);
  return n > 0 ? n : null;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Server shapes (§6.2)
// ═════════════════════════════════════════════════════════════════════════════

class StatusActor {
  const StatusActor({required this.id, this.name = ''});
  final int id;
  final String name;

  static StatusActor? fromJson(dynamic j) {
    if (j is! Map) return null;
    final m = asMap(j);
    return StatusActor(id: asInt(m['id']), name: asStr(m['name']));
  }
}

/// One row of `org_student_status_events` (§2.1) as the server sends it.
class StatusEvent {
  const StatusEvent({
    required this.id,
    this.userId = 0,
    this.dimension = 'enrolment',
    this.key,
    this.fromValue,
    this.toValue = '',
    this.reasonCode,
    this.reason,
    this.decisionNo,
    this.decisionDate,
    this.body,
    this.effectiveFrom,
    this.effectiveTo,
    this.via = 'manual',
    this.sourceType,
    this.sourceId,
    this.revertsId,
    this.revertedById,
    this.actor,
    this.createdAt,
    this.titleAr = '',
    this.titleEn = '',
    this.canUndo = false,
    this.undone = false,
  });

  final int id, userId;
  final String dimension;
  final String? key, fromValue;
  final String toValue;
  final String? reasonCode, reason, decisionNo, body;
  final DateTime? decisionDate, effectiveFrom, effectiveTo;
  final String via;
  final String? sourceType;
  final int? sourceId, revertsId, revertedById;
  final StatusActor? actor;
  final DateTime? createdAt;
  final String titleAr, titleEn;
  final bool canUndo, undone;

  factory StatusEvent.fromJson(dynamic j) {
    final m = asMap(j);
    final reverted = _optInt(m['reverted_by_id']);
    return StatusEvent(
      id: asInt(m['id']),
      userId: asInt(m['user_id']),
      dimension: asStr(m['dimension'], 'enrolment'),
      key: _opt(m['key']),
      fromValue: _opt(m['from_value']),
      toValue: asStr(m['to_value']),
      reasonCode: _opt(m['reason_code']),
      reason: _opt(m['reason']),
      decisionNo: _opt(m['decision_no']),
      decisionDate: parseYmd(m['decision_date']),
      body: _opt(m['body']),
      effectiveFrom: parseYmd(m['effective_from']),
      effectiveTo: parseYmd(m['effective_to']),
      via: asStr(m['via'], 'manual'),
      sourceType: _opt(m['source_type']),
      sourceId: _optInt(m['source_id']),
      revertsId: _optInt(m['reverts_id']),
      revertedById: reverted,
      actor: StatusActor.fromJson(m['actor']),
      createdAt: orgParseUtc(m['created_at']),
      titleAr: asStr(m['title_ar']),
      titleEn: asStr(m['title_en']),
      canUndo: asBool(m['can_undo']),
      undone: asBool(m['undone'], reverted != null),
    );
  }

  /// The server's sentence, or one built here from the values.
  String get title {
    final s = t(titleAr, titleEn).trim();
    if (s.isNotEmpty) return s;
    final other = t(titleEn, titleAr).trim();
    if (other.isNotEmpty) return other;
    return eventValueLabel(dimension, toValue, key: key);
  }
}

/// The label of a value of [dimension]: an enrolment status, a standing, or a flag ("on" / "off" with its name).
String eventValueLabel(String dimension, String value, {String? key}) => switch (dimension) {
      'standing' => standingLabel(value),
      'flag' => value == 'off' ? t('أُزيلت علامة: ${flagLabel(key ?? '')}', 'Mark removed: ${flagLabel(key ?? '')}') : t('علامة: ${flagLabel(key ?? '')}', 'Mark: ${flagLabel(key ?? '')}'),
      _ => enrolLabel(value),
    };

/// A rule that stops a change (`blocked` of an option, or the detail of 409 `rule_blocks`).
class RuleBlock {
  const RuleBlock({this.rule = '', this.textAr = '', this.textEn = ''});
  final String rule, textAr, textEn;

  static RuleBlock? fromJson(dynamic j) {
    if (j is! Map) return null;
    final m = asMap(j);
    return RuleBlock(
      rule: asStr(m['rule']),
      textAr: asStr(m['text_ar'] ?? m['message']),
      textEn: asStr(m['text_en'] ?? m['message_en']),
    );
  }

  String get text {
    final s = t(textAr, textEn).trim();
    if (s.isNotEmpty) return s;
    final o = t(textEn, textAr).trim();
    return o.isNotEmpty ? o : t('قاعدة من قواعد المؤسسة تمنع هذا التغيير', 'One of the institution\'s rules stops this change');
  }
}

/// One change the caller may make, from `options` of GET …/status.
class StatusOption {
  const StatusOption({
    required this.decision,
    this.labelAr = '',
    this.labelEn = '',
    this.mode = 'decide',
    this.needs = const [],
    this.body,
    this.danger = false,
    this.blocked,
    this.canOverride = false,
  });

  final String decision, labelAr, labelEn;

  /// `decide` (applied at once) or `propose` (sent for approval).
  final String mode;
  final List<String> needs;
  final String? body;
  final bool danger;
  final RuleBlock? blocked;

  /// The caller may pass a blocking rule with a reason (holders of `approve`). Read from `can_override`; an older
  /// server that does not send it → a caller who decides may try (the server refuses when not).
  final bool canOverride;

  factory StatusOption.fromJson(dynamic j) {
    final m = asMap(j);
    final decision = asStr(m['decision']);
    final mode = asStr(m['mode'], 'decide') == 'propose' ? 'propose' : 'decide';
    return StatusOption(
      decision: decision,
      labelAr: asStr(m['label_ar']),
      labelEn: asStr(m['label_en']),
      mode: mode,
      needs: [for (final n in (m['needs'] is List ? m['needs'] as List : const [])) '$n'],
      body: _opt(m['body']),
      danger: asBool(m['danger'], decisionDangerous.contains(decision)),
      blocked: RuleBlock.fromJson(m['blocked']),
      canOverride: asBool(m['can_override'], mode == 'decide'),
    );
  }

  bool get proposes => mode == 'propose';
  bool needsField(String f) => needs.contains(f);

  /// The decision number (and its date) is asked for.
  bool get needsDecisionNo => needsField('decision_no');
  bool get needsReasonText => needsField('reason');
  bool get needsEffectiveTo => needsField('effective_to') || needsField('dates');

  DecisionTarget get target => decisionTargets[decision] ?? (dimension: 'enrolment', to: null, flag: null);

  String get label {
    final s = t(labelAr, labelEn).trim();
    return s.isNotEmpty ? s : decisionLabel(decision);
  }
}

class StatusFlag {
  const StatusFlag({required this.key, this.since, this.until, this.reason, this.eventId});
  final String key;
  final DateTime? since, until;
  final String? reason;
  final int? eventId;

  factory StatusFlag.fromJson(dynamic j) {
    final m = asMap(j);
    return StatusFlag(
      key: asStr(m['key']),
      since: parseYmd(m['since']),
      until: parseYmd(m['until']),
      reason: _opt(m['reason']),
      eventId: _optInt(m['event_id']),
    );
  }
}

/// GET …/students/{uid}/status.
class StudentStatus {
  const StudentStatus({
    this.enrolStatus = 'enrolled',
    this.enrolSince,
    this.enrolUntil,
    this.acadStanding,
    this.standingHoldUntil,
    this.flags = const [],
    this.lastEnrolment,
    this.lastStanding,
    this.options = const [],
  });

  final String enrolStatus;
  final DateTime? enrolSince, enrolUntil;
  final String? acadStanding;
  final int? standingHoldUntil;
  final List<StatusFlag> flags;
  final StatusEvent? lastEnrolment, lastStanding;
  final List<StatusOption> options;

  factory StudentStatus.fromJson(dynamic j) {
    final m = asMap(j);
    final last = asMap(m['last']);
    return StudentStatus(
      enrolStatus: asStr(m['enrol_status'], 'enrolled'),
      enrolSince: parseYmd(m['enrol_since']),
      enrolUntil: parseYmd(m['enrol_until']),
      acadStanding: _opt(m['acad_standing']),
      standingHoldUntil: _optInt(m['standing_hold_until']),
      flags: [for (final f in asMapList(m['flags'])) StatusFlag.fromJson(f)],
      lastEnrolment: last['enrolment'] is Map ? StatusEvent.fromJson(last['enrolment']) : null,
      lastStanding: last['standing'] is Map ? StatusEvent.fromJson(last['standing']) : null,
      options: [for (final o in asMapList(m['options'])) StatusOption.fromJson(o)].where((o) => o.decision.isNotEmpty).toList(),
    );
  }

  bool hasFlag(String key) => flags.any((f) => f.key == key);
  List<String> get flagKeys => [for (final f in flags) f.key];

  StatusOption? option(String decision) => options.where((o) => o.decision == decision).firstOrNull;

  /// The options of one dimension (`enrolment`, `standing`, `flag`) in the order of [decisionKeys] (unknown keys last).
  List<StatusOption> optionsOf(String dimension) {
    final list = options.where((o) => o.target.dimension == dimension).toList();
    int rank(StatusOption o) {
      final i = decisionKeys.indexOf(o.decision);
      return i < 0 ? decisionKeys.length : i;
    }

    list.sort((a, b) => rank(a).compareTo(rank(b)));
    return list;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The form (StatusIn)
// ═════════════════════════════════════════════════════════════════════════════

/// Where a change came from (a complaint, a case, …): `source` of StatusIn.
class StatusSource {
  const StatusSource(this.type, this.id);
  final String type;
  final int id;
  Map<String, dynamic> toJson() => {'type': type, 'id': id};
}

/// The sheet's form. Mutable: the sheet edits it inside setState.
class StatusDraft {
  StatusDraft({
    required this.decision,
    this.to,
    this.flagOn,
    this.reasonCode,
    this.reason = '',
    this.decisionNo = '',
    this.decisionDate,
    this.effectiveFrom,
    this.effectiveTo,
    this.dropCurrent = false,
    this.accessUntil,
    this.source,
    this.override = false,
  });

  /// A fresh form for [option]: the value it writes, the flag switched to the other side of [current], today as the
  /// effective date, the only reason when there is one.
  factory StatusDraft.forOption(StatusOption option, {StudentStatus? current, DateTime? today, String reason = '', StatusSource? source}) {
    final tgt = option.target;
    final now = today ?? DateTime.now();
    final reasons = reasonChoices(option.decision);
    return StatusDraft(
      decision: option.decision,
      to: tgt.to,
      flagOn: tgt.flag == null ? null : !(current?.hasFlag(tgt.flag!) ?? false),
      reasonCode: reasons.length == 1 ? reasons.first : null,
      reason: reason,
      effectiveFrom: DateTime(now.year, now.month, now.day),
      source: source,
    );
  }

  String decision;
  String? to;
  bool? flagOn;
  String? reasonCode;
  String reason;
  String decisionNo;
  DateTime? decisionDate, effectiveFrom, effectiveTo;
  bool dropCurrent;
  DateTime? accessUntil;
  StatusSource? source;
  bool override;

  DecisionTarget get target => decisionTargets[decision] ?? (dimension: 'enrolment', to: null, flag: null);

  /// The enrolment value this change leads to (null for standing / flags).
  String? get enrolTo => target.dimension == 'enrolment' ? (to ?? target.to) : null;

  /// The change takes the student out of active enrolment (the side-effect questions apply).
  bool get leavesEnrolment {
    final e = enrolTo;
    return e != null && e != 'enrolled';
  }

  /// The change ends the student's time here (an access end date applies).
  bool get isFinal => enrolFinal.contains(enrolTo);

  /// The first missing or wrong value for [option], as a §6.3 code (`reason_required`, `decision_no_required`,
  /// `dates_required`, `bad_dates`, `to_required`, `flag_required`), or null when the form can go.
  String? problem(StatusOption option) {
    final tgt = target;
    if (tgt.dimension == 'standing' && (to ?? '').isEmpty) return 'to_required';
    if (tgt.dimension == 'flag' && flagOn == null) return 'flag_required';
    final needsCode = option.needsField('reason_code') || decision.startsWith('dismiss_');
    if (needsCode && (reasonCode ?? '').isEmpty) return 'reason_required';
    if ((option.needsReasonText || override) && reason.trim().isEmpty) return 'reason_required';
    if (option.needsDecisionNo && (decisionNo.trim().isEmpty || decisionDate == null)) return 'decision_no_required';
    if (option.needsField('decision_date') && decisionDate == null) return 'decision_no_required';
    if (option.needsField('effective_from') && effectiveFrom == null) return 'dates_required';
    if (option.needsEffectiveTo && effectiveTo == null) return 'dates_required';
    final from = effectiveFrom, until = effectiveTo;
    if (from != null && until != null && !until.isAfter(from)) return 'bad_dates';
    final access = accessUntil;
    if (from != null && access != null && access.isBefore(from)) return 'bad_dates';
    return null;
  }

  /// [problem] as one plain sentence.
  String? problemText(StatusOption option) {
    final p = problem(option);
    return p == null ? null : (statusCodeTexts()[p] ?? p);
  }

  /// StatusIn (§6.2).
  Map<String, dynamic> toJson() {
    final tgt = target;
    final note = reason.trim(), no = decisionNo.trim();
    return {
      'decision': decision,
      'to': tgt.dimension == 'flag' ? null : (to ?? tgt.to),
      'flag_on': tgt.dimension == 'flag' ? flagOn : null,
      'reason_code': reasonCode,
      'reason': note.isEmpty ? null : note,
      'decision_no': no.isEmpty ? null : no,
      'decision_date': decisionDate == null ? null : ymd(decisionDate!),
      'effective_from': effectiveFrom == null ? null : ymd(effectiveFrom!),
      'effective_to': effectiveTo == null ? null : ymd(effectiveTo!),
      'effects': {
        'drop_current': leavesEnrolment && dropCurrent,
        'access_until': isFinal && accessUntil != null ? ymd(accessUntil!) : null,
      },
      'source': source?.toJson(),
      'override': override,
      'attachment_ids': const <int>[],
    };
  }
}

/// The plain preview under the form: what happens, and when ("From 21 Nov 2026 the student cannot register new
/// courses. Current courses stay."). [proposes]: nothing happens until [body] approves.
String statusPreview(StatusDraft d, {bool proposes = false, String? body}) {
  final parts = <String>[];
  if (proposes) {
    final who = body == null ? t('صاحب الصلاحية', 'whoever decides') : bodyPhrase(body);
    parts.add(t('لن يتغير شيء حتى يوافق: $who.', 'Nothing changes until $who approves.'));
  }
  final from = d.effectiveFrom;
  final when = from == null ? t('من الآن', 'From now') : t('من ${AppTime.wall(from)}', 'From ${AppTime.wall(from)}');
  final tgt = d.target;
  switch (tgt.dimension) {
    case 'standing':
      final to = d.to;
      if (to != null && to.isNotEmpty) {
        parts.add(t('يصبح الوضع الأكاديمي «${standingLabel(to)}» حتى اعتماد النتائج القادمة.',
            'The standing becomes “${standingLabel(to)}” until the next approved results.'));
      }
    case 'flag':
      final name = flagLabel(tgt.flag ?? '');
      if (d.flagOn == true) {
        parts.add(t('تُضاف علامة «$name».', 'The mark “$name” is added.'));
        parts.add(staffOnlyFlags.contains(tgt.flag)
            ? t('لا يراها الطالب.', 'The student does not see it.')
            : t('يراها الطالب في ملفه.', 'The student sees it on their file.'));
      } else if (d.flagOn == false) {
        parts.add(t('تُزال علامة «$name».', 'The mark “$name” is removed.'));
      }
    default:
      final to = d.enrolTo;
      if (to == 'enrolled') {
        parts.add(t('$when يستطيع الطالب تسجيل المقررات من جديد.', '$when the student can register courses again.'));
      } else if (to != null) {
        parts.add(t('$when تصبح الحالة «${enrolLabel(to)}» ولا يستطيع الطالب تسجيل مقررات جديدة.',
            '$when the status is “${enrolLabel(to)}” and the student cannot register new courses.'));
        parts.add(d.dropCurrent
            ? t('يُسحب من مقررات هذا الفصل.', 'This term\'s courses are withdrawn.')
            : t('مقررات هذا الفصل تبقى كما هي.', 'This term\'s courses stay.'));
        final until = d.effectiveTo;
        if (enrolPaused.contains(to) && until != null) {
          parts.add(t('يعود القيد في ${AppTime.wall(until)}.', 'Enrolment resumes on ${AppTime.wall(until)}.'));
        }
        if (d.isFinal) {
          final access = d.accessUntil;
          parts.add(access == null
              ? t('ينتهي دخوله إلى المؤسسة بعد المدة المحددة في الإعدادات.', 'Their access to the organization ends after the period set in the settings.')
              : t('ينتهي دخوله إلى المؤسسة في ${AppTime.wall(access)}.', 'Their access to the organization ends on ${AppTime.wall(access)}.'));
        }
      }
  }
  return parts.join(' ');
}

/// What the status sheet and the undo confirm hand back.
class StatusResult {
  const StatusResult({this.event, this.status, this.decisionId});
  final StatusEvent? event;
  final StudentStatus? status;

  /// Set when the change was sent for approval (POST …/status/propose).
  final int? decisionId;

  bool get proposed => decisionId != null;

  /// `{event, status}` of POST …/status and of the undo route.
  factory StatusResult.fromJson(dynamic j) {
    final m = asMap(j);
    return StatusResult(
      event: m['event'] is Map ? StatusEvent.fromJson(m['event']) : null,
      status: m['status'] is Map ? StudentStatus.fromJson(m['status']) : null,
    );
  }

  /// `{decision_id}` of POST …/status/propose.
  factory StatusResult.proposedFrom(dynamic j) => StatusResult(decisionId: asInt(asMap(j)['decision_id'], -1));
}

// ═════════════════════════════════════════════════════════════════════════════
//  The student's own status (§6.5)
// ═════════════════════════════════════════════════════════════════════════════

class MyStatusLast {
  const MyStatusLast({this.titleAr = '', this.titleEn = '', this.reason, this.decisionNo, this.at});
  final String titleAr, titleEn;
  final String? reason, decisionNo;
  final DateTime? at;

  static MyStatusLast? fromJson(dynamic j) {
    if (j is! Map) return null;
    final m = asMap(j);
    final last = MyStatusLast(
      titleAr: asStr(m['title_ar']),
      titleEn: asStr(m['title_en']),
      reason: _opt(m['reason']),
      decisionNo: _opt(m['decision_no']),
      at: orgParseUtc(m['at']),
    );
    return last.title.isEmpty ? null : last;
  }

  String get title {
    final s = t(titleAr, titleEn).trim();
    return s.isNotEmpty ? s : t(titleEn, titleAr).trim();
  }
}

/// GET /api/v1/org/public/{org_id}/my-status. [enrolStatus] is null when the institution hides it (`student_sees`).
class MyStatus {
  const MyStatus({this.enrolStatus, this.enrolUntil, this.acadStanding, this.flags = const [], this.last});
  final String? enrolStatus;
  final DateTime? enrolUntil;
  final String? acadStanding;
  final List<String> flags;
  final MyStatusLast? last;

  factory MyStatus.fromJson(dynamic j) {
    final m = asMap(j);
    return MyStatus(
      enrolStatus: _opt(m['enrol_status']),
      enrolUntil: parseYmd(m['enrol_until']),
      acadStanding: _opt(m['acad_standing']),
      // the server removes them already; a student never sees a staff-only flag, whatever an older server sends
      flags: [
        for (final f in (m['flags'] is List ? m['flags'] as List : const []))
          if (!staffOnlyFlags.contains(f is Map ? '${f['key']}' : '$f')) f is Map ? '${f['key']}' : '$f',
      ],
      last: MyStatusLast.fromJson(m['last']),
    );
  }

  /// Nothing to show at all.
  bool get isEmpty => enrolStatus == null && acadStanding == null && flags.isEmpty && last == null;

  /// Everything is as it should be (the card stays one calm line).
  bool get allWell =>
      (enrolStatus == null || enrolStatus == 'enrolled') && (acadStanding == null || acadStanding == 'regular') && flags.isEmpty;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Settings (§6.4)
// ═════════════════════════════════════════════════════════════════════════════

/// One row of `decision_matrix`.
class DecisionRule {
  const DecisionRule({this.decide = 'approve', this.body, this.decisionNo = false});
  final String decide; // update | approve | auto
  final String? body;
  final bool decisionNo;

  factory DecisionRule.fromJson(dynamic j) {
    final m = asMap(j);
    return DecisionRule(decide: asStr(m['decide'], 'approve'), body: _opt(m['body']), decisionNo: asBool(m['decision_no']));
  }

  Map<String, dynamic> toJson() => {'decide': decide, 'body': body, 'decision_no': decisionNo};

  DecisionRule copyWith({String? decide, String? Function()? body, bool? decisionNo}) =>
      DecisionRule(decide: decide ?? this.decide, body: body == null ? this.body : body(), decisionNo: decisionNo ?? this.decisionNo);
}

/// `settings.lifecycle`. The whole object is kept ([raw]) so a PUT sends every key back, also the ones this app
/// version does not know.
class LifecycleSettings {
  const LifecycleSettings(this.raw);
  final Map<String, dynamic> raw;

  factory LifecycleSettings.fromJson(dynamic j) => LifecycleSettings(Map<String, dynamic>.from(asMap(j)));

  Map<String, DecisionRule> get matrix => {for (final e in asMap(raw['decision_matrix']).entries) e.key: DecisionRule.fromJson(e.value)};

  DecisionRule rule(String decision) => matrix[decision] ?? const DecisionRule();

  /// A copy with [decision]'s row replaced.
  LifecycleSettings withRule(String decision, DecisionRule r) {
    final m = Map<String, dynamic>.from(asMap(raw['decision_matrix']));
    m[decision] = r.toJson();
    return LifecycleSettings({...raw, 'decision_matrix': m});
  }

  /// A copy with the top-level [section] (`side_effects`, `student_sees`, …) merged with [values].
  LifecycleSettings withSection(String section, Map<String, dynamic> values) =>
      LifecycleSettings({...raw, section: {...asMap(raw[section]), ...values}});

  Map<String, dynamic> toJson() => raw;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Error texts (§6.3) — also the form's own problems
// ═════════════════════════════════════════════════════════════════════════════

Map<String, String> statusCodeTexts() => {
      'bad_transition': t('لا يمكن الانتقال من الحالة الحالية إلى هذه الحالة', 'The student cannot move from the current status to this one'),
      'rule_blocks': t('قاعدة من قواعد المؤسسة تمنع هذا التغيير', 'One of the institution\'s rules stops this change'),
      'needs_body': t('هذا التغيير يحتاج موافقة جهة أعلى: أرسله للاعتماد', 'This change needs a higher body\'s approval: send it for approval'),
      'reason_required': t('اكتب السبب', 'Give the reason'),
      'decision_no_required': t('اكتب رقم القرار وتاريخه', 'Enter the decision number and its date'),
      'dates_required': t('حدّد التاريخ المطلوب', 'Pick the date asked for'),
      'bad_dates': t('تاريخ النهاية يجب أن يكون بعد تاريخ البداية', 'The end date must come after the start date'),
      'not_latest': t('يوجد تغيير أحدث على هذه الحالة: تراجع عنه أولاً', 'There is a newer change to this status: undo that one first'),
      'already_reverted': t('تم التراجع عن هذا التغيير من قبل', 'This change was already undone'),
      'status_disabled': t('تغيير حالات الطلاب غير مفعّل لهذه المؤسسة', 'Changing student statuses is not switched on for this organization'),
      'to_required': t('اختر الوضع الأكاديمي الجديد', 'Pick the new standing'),
      'flag_required': t('اختر إضافة العلامة أو إزالتها', 'Choose to add or remove the mark'),
    };
