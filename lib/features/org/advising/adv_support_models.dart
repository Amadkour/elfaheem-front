// lib/features/org/advising/adv_support_models.dart — pure models of Academic Advising Phase 7 (docs/advising/PHASE7.md):
// support requests and referrals (a governance work item behind each submitted one), the approval chain per scope,
// support plans and accommodations, the student 360's Support block and the student's own view. No Flutter widgets:
// unit-tested in test/org/adv_support_models_test.dart.
//
// Every parser is tolerant of missing keys (an older server leaves a block out): a missing flag is false, a missing
// block is null, a missing list is empty. Labels are bilingual through `t(ar, en)` like every org screen.
//
// Names: `AdvSupportPlan` (NOT `AdvPlan`, the Phase 3 distribution plan) and `AdvAccommodationGrant` (NOT
// `AdvAccommodation`, the Phase 4 category's recommended accommodation `{key, label_ar, label_en}`).
library;

import 'package:flutter_education_app/core/plural.dart';

import '../../admin/admin_common.dart' show asBool, asInt, asMap, asMapList, asStr, t;
import '../governance/gov_models.dart' show GovAttachment;
import '../org_v3.dart' show orgDay, orgParseUtc, orgUtc;
import 'adv_models.dart' show AdvAccommodation, AdvCategory, AdvRef, advPriorities;

String? _text(dynamic v) {
  final s = asStr(v).trim();
  return s.isEmpty || s == 'null' ? null : s;
}

int? _id(dynamic v) {
  final n = asInt(v);
  return v == null || n == 0 ? null : n;
}

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

/// A date-only value (`YYYY-MM-DD`) as a local calendar date.
DateTime? advParseDay(dynamic v) {
  final s = _text(v);
  if (s == null) return null;
  final d = DateTime.tryParse(s.length >= 10 ? s.substring(0, 10) : s);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// `{"ar","en"}` → the shown one, the other as a fallback, else [fallback].
String _pick(String ar, String en, [String fallback = '']) {
  final s = t(ar, en);
  if (s.isNotEmpty) return s;
  final other = ar.isNotEmpty ? ar : en;
  return other.isNotEmpty ? other : fallback;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Labels
// ═════════════════════════════════════════════════════════════════════════════

/// The kinds of a request: a support request (the approval chain) · a referral to a service department.
const advRequestKinds = ['support', 'referral'];

String advRequestKindLabel(String kind) => kind == 'referral' ? t('إحالة', 'Referral') : t('طلب دعم', 'Support request');

/// The support types of the server's catalogue, in its order.
const advSupportTypeKeys = [
  'academic_load',
  'course_withdrawal',
  'exam_excuse',
  'study_postponement',
  'program_transfer',
  'readmission',
  'accommodation',
  'financial_support',
  'other',
];

/// The app's own label of a support type (the server sends its labels; this is the fallback).
String advSupportTypeKeyLabel(String key) => switch (key) {
      'academic_load' => t('تخفيف العبء الدراسي', 'Lighter study load'),
      'course_withdrawal' => t('انسحاب من مقرر', 'Course withdrawal'),
      'exam_excuse' => t('عذر عن امتحان', 'Exam excuse'),
      'study_postponement' => t('تأجيل الدراسة', 'Study postponement'),
      'program_transfer' => t('تحويل برنامج', 'Program transfer'),
      'readmission' => t('إعادة قيد', 'Readmission'),
      'accommodation' => t('تسهيلات', 'Accommodations'),
      'financial_support' => t('دعم مالي', 'Financial support'),
      'other' => t('طلب آخر', 'Another request'),
      _ => key,
    };

/// Support stages, in their order along a request's life.
const advSupportStages = ['draft', 'submitted', 'needs_info', 'in_review', 'at_department_council', 'at_faculty_council', 'approved', 'rejected', 'closed'];

/// Referral stages.
const advReferralStages = ['draft', 'sent', 'in_progress', 'handled', 'declined', 'closed'];

/// The stages after which nothing waits on a decider.
const advDecidedStages = {'approved', 'rejected', 'handled', 'declined', 'closed'};

String advStageLabel(String? stage) => switch (stage) {
      'draft' => t('مسودة', 'Draft'),
      'submitted' => t('أُرسل', 'Submitted'),
      'needs_info' => t('بحاجة إلى معلومات', 'Needs more information'),
      'in_review' => t('قيد المراجعة', 'In review'),
      'at_department_council' => t('في مجلس القسم', 'At the department council'),
      'at_faculty_council' => t('في مجلس الكلية', 'At the faculty council'),
      'approved' => t('مقبول', 'Approved'),
      'rejected' => t('مرفوض', 'Rejected'),
      'closed' => t('مغلق', 'Closed'),
      'sent' => t('أُرسلت', 'Sent'),
      'in_progress' => t('قيد المتابعة', 'In progress'),
      'handled' => t('عولجت', 'Handled'),
      'declined' => t('اعتُذر عنها', 'Declined'),
      _ => t('غير معروف', 'Unknown'),
    };

/// One line under a stage: what is happening now and who acts next.
String advStageHint(String? stage, {bool postponed = false, bool student = false}) => switch (stage) {
      'draft' => t('لم يُرسل بعد — يراه كاتبه فقط', 'Not sent yet — only its author sees it'),
      'submitted' => t('بانتظار مراجعة مدير الإرشاد', 'Waiting for the advising director\'s review'),
      'needs_info' => student
          ? t('طُلبت معلومات إضافية من مرشدك', 'More information was asked of your advisor')
          : t('أعاده مدير الإرشاد لطلب معلومات إضافية', 'The advising director asked for more information'),
      'in_review' => t('تراجعه الجهة المختصة', 'The responsible office is reviewing it'),
      'at_department_council' || 'at_faculty_council' => postponed
          ? t('أُجّل إلى جلسة قادمة للمجلس', 'Postponed to a later council session')
          : t('على جدول أعمال المجلس للتصويت', 'On the council\'s agenda for a vote'),
      'approved' => t('صدر القرار بالموافقة', 'The decision is to approve'),
      'rejected' => t('صدر القرار بالرفض', 'The decision is to reject'),
      'closed' => t('أُغلقت الحالة', 'The case is closed'),
      'sent' => t('وصلت الجهة المحال إليها', 'Received by the department it was sent to'),
      'in_progress' => t('تتابعها الجهة المحال إليها', 'The receiving department is working on it'),
      'handled' => t('أنهت الجهة معالجتها', 'The receiving department dealt with it'),
      'declined' => t('اعتذرت الجهة عنها', 'The receiving department declined it'),
      _ => '',
    };

/// The tone of a stage (a colour role the widgets map): `muted` · `brand` · `warn` · `council` · `good` · `bad`.
String advStageTone(String? stage) => switch (stage) {
      'draft' || 'closed' => 'muted',
      'needs_info' => 'warn',
      'at_department_council' || 'at_faculty_council' => 'council',
      'approved' || 'handled' => 'good',
      'rejected' || 'declined' => 'bad',
      _ => 'brand',
    };

String advOutcomeLabel(String? outcome) => switch (outcome) {
      'approved' => t('قُبل', 'Approved'),
      'rejected' => t('رُفض', 'Rejected'),
      'withdrawn' => t('سُحب', 'Withdrawn'),
      'closed' => t('أُغلق دون قرار', 'Closed without a decision'),
      'handled' => t('عولجت', 'Handled'),
      'declined' => t('اعتُذر عنها', 'Declined'),
      _ => '',
    };

/// The approval chain's step kinds (the advising policy's `workflow_steps`).
const advChainKinds = ['director_review', 'student_department_council', 'faculty_council', 'entity'];

String advChainKindLabel(String kind) => switch (kind) {
      'director_review' => t('مراجعة مدير الإرشاد', 'Advising director review'),
      'student_department_council' => t('مجلس قسم الطالب', 'Student\'s department council'),
      'faculty_council' => t('مجلس الكلية', 'Faculty council'),
      'entity' => t('إدارة أو لجنة', 'An office or committee'),
      'referral' => t('الجهة المحال إليها', 'The receiving department'),
      _ => kind,
    };

String advChainKindHint(String kind) => switch (kind) {
      'director_review' => t('يقبل مدير الإرشاد أو يرفض أو يطلب معلومات', 'The advising director approves, rejects or asks for more information'),
      'student_department_council' => t('يصوّت مجلس القسم العلمي لبرنامج الطالب', 'The council of the student\'s program department votes'),
      'faculty_council' => t('يصوّت مجلس الكلية في جلسته', 'The faculty council votes in its session'),
      'entity' => t('تقرر إدارة أو لجنة تختارها (مثل شؤون الطلاب)', 'An office or committee you choose decides (e.g. Student Affairs)'),
      _ => '',
    };

/// Why a chain step is skipped (`skip_reason`, the preview's `reason`).
String advSkipReasonText(String? reason) => switch (reason) {
      'no_department_council' => t('لا مجلس قسم لبرنامج الطالب — تُتجاوز هذه الخطوة', 'The student\'s program department has no council — this step is skipped'),
      'no_faculty_council' => t('لا مجلس كلية في هذه المؤسسة — تُتجاوز هذه الخطوة', 'This organization has no faculty council — this step is skipped'),
      'target_missing' => t('الجهة لم تعد نشطة — تُتجاوز هذه الخطوة', 'That office is no longer active — this step is skipped'),
      null || '' => '',
      _ => t('تُتجاوز هذه الخطوة', 'This step is skipped'),
    };

/// The service-department presets offered first as referral targets.
const advReferralPresets = ['healthcare', 'student_activities', 'student_affairs'];

String advPresetLabel(String? preset) => switch (preset) {
      'healthcare' => t('الرعاية الصحية', 'Healthcare'),
      'student_activities' => t('رعاية الشباب', 'Student activities'),
      'student_affairs' => t('شؤون الطلاب', 'Student affairs'),
      _ => '',
    };

/// The request list's queues: everything I may see · at director review without an info request (manage) · waiting
/// on an advisor's information · past their step's time.
const advRequestQueues = ['', 'review', 'needs_info', 'overdue'];

String advRequestQueueLabel(String q) => switch (q) {
      'review' => t('للمراجعة', 'To review'),
      'needs_info' => t('بحاجة إلى معلومات', 'Needs information'),
      'overdue' => t('متأخرة', 'Overdue'),
      'mine' => t('طلباتي', 'Filed by me'),
      _ => t('الكل', 'All'),
    };

/// The request list's one filter: '' · `kind:<kind>` · `stage:<stage>`.
const advRequestFilters = [
  '',
  'kind:support',
  'kind:referral',
  'stage:draft',
  'stage:submitted',
  'stage:at_department_council',
  'stage:at_faculty_council',
  'stage:approved',
  'stage:rejected',
  'stage:closed',
];

String advRequestFilterLabel(String f) {
  if (f.startsWith('kind:')) return f == 'kind:referral' ? t('الإحالات', 'Referrals') : t('طلبات الدعم', 'Support requests');
  if (f.startsWith('stage:')) {
    final s = f.substring(6);
    return s == 'draft' ? t('المسودات', 'Drafts') : advStageLabel(s);
  }
  return t('كل الأنواع والمراحل', 'Every kind and stage');
}

// ═════════════════════════════════════════════════════════════════════════════
//  Shared blocks
// ═════════════════════════════════════════════════════════════════════════════

/// A department / entity a payload names (`target_dept`, a referral target, a chain entity).
class AdvSupportEntity {
  const AdvSupportEntity({required this.id, this.nameAr = '', this.nameEn = '', this.preset, this.suggested = false, this.kind});
  final int id;
  final String nameAr, nameEn;

  /// `healthcare` · `student_activities` · `student_affairs` · `academic_advising` · null.
  final String? preset;

  /// Offered first (a preset service department).
  final bool suggested;

  /// The governance entity kind (`service` · `office` · `council` · …), chain options only.
  final String? kind;

  factory AdvSupportEntity.fromJson(Map<String, dynamic> j) => AdvSupportEntity(
        id: asInt(j['id']),
        nameAr: asStr(j['name']).trim(),
        nameEn: asStr(j['name_en']).trim(),
        preset: _text(j['preset']),
        suggested: asBool(j['suggested']),
        kind: _text(j['kind']),
      );

  static AdvSupportEntity? maybe(dynamic v) => v is Map ? AdvSupportEntity.fromJson(asMap(v)) : null;

  String get name => _pick(nameAr, nameEn, advPresetLabel(preset).isEmpty ? '#$id' : advPresetLabel(preset));
}

/// The student a staff request is about.
class AdvRequestStudent {
  const AdvRequestStudent({required this.memberId, this.userId, this.name = '', this.code});
  final int memberId;
  final int? userId;
  final String name;
  final String? code;

  factory AdvRequestStudent.fromJson(Map<String, dynamic> j, {int memberId = 0}) => AdvRequestStudent(
        memberId: asInt(j['member_id'], memberId),
        userId: _id(j['user_id']),
        name: asStr(j['name']).trim(),
        code: _text(j['code']),
      );

  String get shown => name.isEmpty ? '#$memberId' : name;
}

/// An accommodation a request asks for / a category offers (`{"key","label_ar","label_en"}`).
List<AdvAccommodation> _accs(dynamic v) => [
      for (final x in (v is List ? v : const []))
        if (x is Map) AdvAccommodation.fromJson(asMap(x)) else if (_text(x) != null) AdvAccommodation(key: '$x'),
    ];

// ═════════════════════════════════════════════════════════════════════════════
//  Requests
// ═════════════════════════════════════════════════════════════════════════════

/// The info loop at the advising director's step.
class AdvRequestInfo {
  const AdvRequestInfo({this.requestedAt, this.note = '', this.by, this.answeredAt, this.answer});
  final DateTime? requestedAt;
  final String note;
  final AdvRef? by;
  final DateTime? answeredAt;
  final String? answer;

  bool get pending => answeredAt == null;

  static AdvRequestInfo? maybe(dynamic v) {
    if (v is! Map) return null;
    final j = asMap(v);
    return AdvRequestInfo(
      requestedAt: orgParseUtc(j['requested_at']),
      note: asStr(j['note']).trim(),
      by: AdvRef.maybe(j['by']),
      answeredAt: orgParseUtc(j['answered_at']),
      answer: _text(j['answer']),
    );
  }
}

/// Where a submitted request stands in its chain right now (`step`).
class AdvRequestCurrentStep {
  const AdvRequestCurrentStep({this.index = 0, this.count = 0, this.kind = '', this.labelAr = '', this.labelEn = '', this.dueAt, this.overdue = false});
  final int index, count;
  final String kind, labelAr, labelEn;
  final DateTime? dueAt;
  final bool overdue;

  static AdvRequestCurrentStep? maybe(dynamic v) {
    if (v is! Map) return null;
    final j = asMap(v);
    return AdvRequestCurrentStep(
      index: asInt(j['index']),
      count: asInt(j['count']),
      kind: asStr(j['kind']),
      labelAr: asStr(j['label_ar']).trim(),
      labelEn: asStr(j['label_en']).trim(),
      dueAt: orgParseUtc(j['due_at']),
      overdue: asBool(j['overdue']),
    );
  }

  String get label => _pick(labelAr, labelEn, advChainKindLabel(kind));
}

/// One step of a request's chain (staff detail `chain.steps`, the student's `steps`).
class AdvRequestStep {
  const AdvRequestStep({this.kind = '', this.deptId, this.labelAr = '', this.labelEn = '', this.status = 'waiting', this.at, this.by, this.note, this.skipReason});
  final String kind;
  final int? deptId;
  final String labelAr, labelEn;

  /// `waiting` · `current` · `approved` · `rejected` · `skipped`.
  final String status;
  final DateTime? at;

  /// Staff only: who decided it and their note.
  final AdvRef? by;
  final String? note;
  final String? skipReason;

  factory AdvRequestStep.fromJson(Map<String, dynamic> j) => AdvRequestStep(
        kind: asStr(j['kind']),
        deptId: _id(j['dept_id']),
        labelAr: asStr(j['label_ar']).trim(),
        labelEn: asStr(j['label_en']).trim(),
        status: _text(j['status']) ?? 'waiting',
        at: orgParseUtc(j['at']),
        by: AdvRef.maybe(j['by']),
        note: _text(j['note']),
        skipReason: _text(j['skip_reason']),
      );

  String get label => _pick(labelAr, labelEn, advChainKindLabel(kind));
}

/// The chain of a submitted request: this round's steps, the current index, the earlier rounds (rejected, then
/// resubmitted).
class AdvRequestChain {
  const AdvRequestChain({this.round = 1, this.current, this.steps = const [], this.rounds = const []});
  final int round;
  final int? current;
  final List<AdvRequestStep> steps;

  /// (round number, its steps), oldest first.
  final List<(int, List<AdvRequestStep>)> rounds;

  static AdvRequestChain? maybe(dynamic v) {
    if (v is! Map) return null;
    final j = asMap(v);
    final rounds = <(int, List<AdvRequestStep>)>[];
    final raw = j['rounds'];
    if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        final r = raw[i];
        if (r is Map) {
          final m = asMap(r);
          rounds.add((asInt(m['round'], i + 1), [for (final s in asMapList(m['steps'])) AdvRequestStep.fromJson(s)]));
        } else if (r is List) {
          rounds.add((i + 1, [for (final s in asMapList(r)) AdvRequestStep.fromJson(s)]));
        }
      }
    }
    final cur = j['current'];
    return AdvRequestChain(
      round: asInt(j['round'], 1),
      current: cur == null ? null : asInt(cur),
      steps: [for (final s in asMapList(j['steps'])) AdvRequestStep.fromJson(s)],
      rounds: rounds,
    );
  }
}

/// One stage the request went through (`history`, oldest first).
class AdvStagePoint {
  const AdvStagePoint({required this.stage, this.at, this.labelAr = '', this.labelEn = ''});
  final String stage;
  final DateTime? at;
  final String labelAr, labelEn;

  factory AdvStagePoint.fromJson(Map<String, dynamic> j) =>
      AdvStagePoint(stage: asStr(j['stage']), at: orgParseUtc(j['at']), labelAr: asStr(j['label_ar']).trim(), labelEn: asStr(j['label_en']).trim());

  String get label => _pick(labelAr, labelEn, advStageLabel(stage));
}

/// A council session the request is on (`agenda`), with the vote so far.
class AdvAgendaEntry {
  const AdvAgendaEntry({
    this.councilName = '',
    this.councilNameEn = '',
    this.level,
    this.scheduledAt,
    this.status = '',
    this.approve = 0,
    this.reject = 0,
    this.abstain = 0,
    this.eligible = 0,
  });
  final String councilName, councilNameEn;

  /// `department` · `faculty` · …
  final String? level;
  final DateTime? scheduledAt;

  /// The session's status (`scheduled` · `open` · `closed` · …).
  final String status;
  final int approve, reject, abstain, eligible;

  factory AdvAgendaEntry.fromJson(Map<String, dynamic> j) {
    final c = asMap(j['council']);
    return AdvAgendaEntry(
      councilName: asStr(c['name']).trim(),
      councilNameEn: asStr(c['name_en']).trim(),
      level: _text(c['level']),
      scheduledAt: orgParseUtc(j['scheduled_at']),
      status: asStr(j['status']),
      approve: asInt(j['approve_count']),
      reject: asInt(j['reject_count']),
      abstain: asInt(j['abstain_count']),
      eligible: asInt(j['eligible_count']),
    );
  }

  String get council => _pick(councilName, councilNameEn, t('المجلس', 'The council'));
  int get voted => approve + reject + abstain;
  bool get closed => status == 'closed' || status == 'done';
}

/// What the caller may do on a request (`can`).
class AdvRequestCan {
  const AdvRequestCan({
    this.edit = false,
    this.submit = false,
    this.delete = false,
    this.review = false,
    this.answerInfo = false,
    this.resubmit = false,
    this.cancel = false,
    this.close = false,
  });
  final bool edit, submit, delete, review, answerInfo, resubmit, cancel, close;

  factory AdvRequestCan.fromJson(Map<String, dynamic> j) => AdvRequestCan(
        edit: asBool(j['edit']),
        submit: asBool(j['submit']),
        delete: asBool(j['delete']),
        review: asBool(j['review']),
        answerInfo: asBool(j['answer_info']),
        resubmit: asBool(j['resubmit']),
        cancel: asBool(j['cancel']),
        close: asBool(j['close']),
      );

  bool get any => edit || submit || delete || review || answerInfo || resubmit || cancel || close;
}

/// The governance work item behind a submitted request.
class AdvWorkItemRef {
  const AdvWorkItemRef({required this.id, this.ref = '', this.status = '', this.version = 0});
  final int id;
  final String ref, status;
  final int version;

  static AdvWorkItemRef? maybe(dynamic v) {
    if (v is! Map) return null;
    final j = asMap(v);
    final id = asInt(j['id']);
    return id == 0 ? null : AdvWorkItemRef(id: id, ref: asStr(j['ref']), status: asStr(j['status']), version: asInt(j['version']));
  }
}

/// A support request or a referral, as staff see it (`Request`; the detail adds [chain], [history], [agenda]).
class AdvRequest {
  const AdvRequest({
    required this.id,
    this.kind = 'support',
    this.memberId = 0,
    this.student,
    this.supportType,
    this.targetDept,
    this.category,
    this.title = '',
    this.body = '',
    this.priority = 'normal',
    this.accommodations = const [],
    this.accommodationUntil,
    this.attachments = const [],
    this.templateId,
    this.flagId,
    this.stage = 'draft',
    this.stageAt,
    this.postponed = false,
    this.outcome,
    this.outcomeNote,
    this.outcomeAt,
    this.info,
    this.step,
    this.escalated = false,
    this.workItem,
    this.createdBy,
    this.createdAt,
    this.submittedAt,
    this.updatedAt,
    this.closedAt,
    this.closeNote,
    this.version = 0,
    this.can = const AdvRequestCan(),
    this.chain,
    this.history = const [],
    this.agenda = const [],
  });

  final int id;

  /// `support` · `referral`.
  final String kind;
  final int memberId;
  final AdvRequestStudent? student;
  final String? supportType;
  final AdvSupportEntity? targetDept;
  final AdvCategory? category;
  final String title, body, priority;
  final List<AdvAccommodation> accommodations;
  final DateTime? accommodationUntil;
  final List<GovAttachment> attachments;
  final int? templateId, flagId;
  final String stage;
  final DateTime? stageAt;
  final bool postponed;
  final String? outcome, outcomeNote;
  final DateTime? outcomeAt;
  final AdvRequestInfo? info;
  final AdvRequestCurrentStep? step;
  final bool escalated;
  final AdvWorkItemRef? workItem;
  final AdvRef? createdBy;
  final DateTime? createdAt, submittedAt, updatedAt, closedAt;
  final String? closeNote;
  final int version;
  final AdvRequestCan can;

  // detail only
  final AdvRequestChain? chain;
  final List<AdvStagePoint> history;
  final List<AdvAgendaEntry> agenda;

  factory AdvRequest.fromJson(Map<String, dynamic> j) {
    final member = asInt(j['member_id']);
    final st = j['student'];
    return AdvRequest(
      id: asInt(j['id']),
      kind: _text(j['kind']) ?? 'support',
      memberId: member != 0 ? member : asInt(asMap(st)['member_id']),
      student: st is Map ? AdvRequestStudent.fromJson(asMap(st), memberId: member) : null,
      supportType: _text(j['support_type']),
      targetDept: AdvSupportEntity.maybe(j['target_dept']),
      category: AdvCategory.maybe(j['category']),
      title: asStr(j['title']).trim(),
      body: asStr(j['body']),
      priority: _text(j['priority']) ?? 'normal',
      accommodations: _accs(j['accommodations']),
      accommodationUntil: advParseDay(j['accommodation_until']),
      attachments: [for (final m in asMapList(j['attachments'])) GovAttachment.fromJson(m)],
      templateId: _id(j['template_id']),
      flagId: _id(j['flag_id']),
      stage: _text(j['stage']) ?? 'draft',
      stageAt: orgParseUtc(j['stage_at']),
      postponed: asBool(j['postponed']),
      outcome: _text(j['outcome']),
      outcomeNote: _text(j['outcome_note']),
      outcomeAt: orgParseUtc(j['outcome_at']),
      info: AdvRequestInfo.maybe(j['info']),
      step: AdvRequestCurrentStep.maybe(j['step']),
      escalated: asBool(j['escalated']),
      workItem: AdvWorkItemRef.maybe(j['work_item']),
      createdBy: AdvRef.maybe(j['created_by']),
      createdAt: orgParseUtc(j['created_at']),
      submittedAt: orgParseUtc(j['submitted_at']),
      updatedAt: orgParseUtc(j['updated_at']),
      closedAt: orgParseUtc(j['closed_at']),
      closeNote: _text(j['close_note']),
      version: asInt(j['version']),
      can: AdvRequestCan.fromJson(asMap(j['can'])),
      chain: AdvRequestChain.maybe(j['chain']),
      history: [for (final m in asMapList(j['history'])) AdvStagePoint.fromJson(m)],
      agenda: [for (final m in asMapList(j['agenda'])) AdvAgendaEntry.fromJson(m)],
    );
  }

  bool get referral => kind == 'referral';
  bool get draft => stage == 'draft';
  bool get decided => outcome != null;
  bool get closed => stage == 'closed';
  bool get sensitive => category?.sensitive ?? false;

  /// An open info request at the director's step.
  bool get infoPending => info != null && info!.pending && stage == 'needs_info';

  /// "Exam excuse" · "Referral · Healthcare".
  String get typeLabel => referral
      ? [advRequestKindLabel(kind), if (targetDept != null) targetDept!.name].join(' · ')
      : (supportType == null ? advRequestKindLabel(kind) : advSupportTypeKeyLabel(supportType!));

  String get shownTitle => title.isEmpty ? typeLabel : title;
  String get studentName => student?.shown ?? '#$memberId';

  /// The steps of the track ([advRequestTrack]).
  List<AdvTrackPoint> get track => advRequestTrack(
        kind: kind,
        stage: stage,
        steps: chain?.steps ?? const [],
        currentStep: step,
        target: targetDept?.name,
        submittedAt: submittedAt,
        outcome: outcome,
        outcomeAt: outcomeAt,
        closedAt: closedAt,
        postponed: postponed,
      );
}

/// A request as the student sees it (`StudentRequest`): no drafts, no info note, no deciders, no votes.
class AdvStudentRequest {
  const AdvStudentRequest({
    required this.id,
    this.kind = 'support',
    this.supportType,
    this.targetName = '',
    this.targetNameEn = '',
    this.title = '',
    this.body = '',
    this.priority = 'normal',
    this.stage = 'submitted',
    this.stageAt,
    this.postponed = false,
    this.outcome,
    this.outcomeNote,
    this.outcomeAt,
    this.steps = const [],
    this.history = const [],
    this.accommodations = const [],
    this.createdAt,
    this.submittedAt,
    this.advisorName = '',
  });

  final int id;
  final String kind;
  final String? supportType;
  final String targetName, targetNameEn;
  final String title, body, priority, stage;
  final DateTime? stageAt;
  final bool postponed;
  final String? outcome, outcomeNote;
  final DateTime? outcomeAt;
  final List<AdvRequestStep> steps;
  final List<AdvStagePoint> history;
  final List<AdvAccommodation> accommodations;
  final DateTime? createdAt, submittedAt;
  final String advisorName;

  factory AdvStudentRequest.fromJson(Map<String, dynamic> j) {
    final target = asMap(j['target_dept']);
    return AdvStudentRequest(
      id: asInt(j['id']),
      kind: _text(j['kind']) ?? 'support',
      supportType: _text(j['support_type']),
      targetName: asStr(target['name']).trim(),
      targetNameEn: asStr(target['name_en']).trim(),
      title: asStr(j['title']).trim(),
      body: asStr(j['body']),
      priority: _text(j['priority']) ?? 'normal',
      stage: _text(j['stage']) ?? 'submitted',
      stageAt: orgParseUtc(j['stage_at']),
      postponed: asBool(j['postponed']),
      outcome: _text(j['outcome']),
      outcomeNote: _text(j['outcome_note']),
      outcomeAt: orgParseUtc(j['outcome_at']),
      steps: [for (final m in asMapList(j['steps'])) AdvRequestStep.fromJson(m)],
      history: [for (final m in asMapList(j['history'])) AdvStagePoint.fromJson(m)],
      accommodations: _accs(j['accommodations']),
      createdAt: orgParseUtc(j['created_at']),
      submittedAt: orgParseUtc(j['submitted_at']),
      advisorName: asStr(j['advisor_name']).trim(),
    );
  }

  bool get referral => kind == 'referral';
  bool get decided => outcome != null;
  String get target => _pick(targetName, targetNameEn);

  String get typeLabel => referral
      ? [advRequestKindLabel(kind), if (target.isNotEmpty) target].join(' · ')
      : (supportType == null ? advRequestKindLabel(kind) : advSupportTypeKeyLabel(supportType!));

  String get shownTitle => title.isEmpty ? typeLabel : title;

  List<AdvTrackPoint> get track => advRequestTrack(
        kind: kind,
        stage: stage,
        steps: steps,
        target: target.isEmpty ? null : target,
        submittedAt: submittedAt ?? createdAt,
        outcome: outcome,
        outcomeAt: outcomeAt,
        closedAt: stage == 'closed' ? stageAt : null,
        postponed: postponed,
        student: true,
      );
}

// ── The stage track ──────────────────────────────────────────────────────────

/// How a point of the track is drawn: done · the current one · the current one waiting on more information ·
/// not reached yet · skipped · refused here · never reached (the request ended before it).
enum AdvTrackState { done, current, attention, waiting, skipped, failed, stopped }

class AdvTrackPoint {
  const AdvTrackPoint({required this.label, required this.state, this.at, this.hint});
  final String label;
  final AdvTrackState state;
  final DateTime? at;

  /// A short line under the label (why it was skipped, "Postponed", "Waiting for information").
  final String? hint;

  @override
  String toString() => '$label:${state.name}';
}

/// The milestones of a request, in order: sent → each chain step (or the receiving department of a referral) →
/// the decision → closed (only once closed). Pure: the widget draws what this returns.
List<AdvTrackPoint> advRequestTrack({
  required String kind,
  required String stage,
  List<AdvRequestStep> steps = const [],
  AdvRequestCurrentStep? currentStep,
  String? target,
  DateTime? submittedAt,
  String? outcome,
  DateTime? outcomeAt,
  DateTime? closedAt,
  bool postponed = false,
  bool student = false,
}) {
  final referral = kind == 'referral';
  final draft = stage == 'draft';
  final ended = outcome != null;
  final points = <AdvTrackPoint>[
    draft
        ? AdvTrackPoint(label: t('مسودة', 'Draft'), state: AdvTrackState.current, hint: t('لم يُرسل بعد', 'Not sent yet'))
        : AdvTrackPoint(label: referral ? t('أُرسلت', 'Sent') : t('أُرسل', 'Submitted'), state: AdvTrackState.done, at: submittedAt),
  ];
  if (steps.isNotEmpty) {
    for (final s in steps) {
      final AdvTrackState state;
      String? hint;
      switch (s.status) {
        case 'approved':
          state = AdvTrackState.done;
        case 'rejected':
          state = AdvTrackState.failed;
        case 'skipped':
          state = AdvTrackState.skipped;
          hint = advSkipReasonText(s.skipReason).isEmpty ? t('تُجووزت', 'Skipped') : advSkipReasonText(s.skipReason);
        case 'current':
          if (ended || draft) {
            state = ended ? AdvTrackState.stopped : AdvTrackState.waiting;
          } else if (stage == 'needs_info') {
            state = AdvTrackState.attention;
            hint = student ? t('بانتظار معلومات من مرشدك', 'Waiting for information from your advisor') : t('بانتظار معلومات من المرشد', 'Waiting for information from the advisor');
          } else {
            state = AdvTrackState.current;
            if (postponed) hint = t('أُجّل إلى جلسة قادمة', 'Postponed to a later session');
          }
        default:
          state = ended ? AdvTrackState.stopped : AdvTrackState.waiting;
      }
      // a date only for a step that happened (a waiting step's `at` means nothing yet)
      final happened = state == AdvTrackState.done || state == AdvTrackState.failed || state == AdvTrackState.skipped;
      points.add(AdvTrackPoint(label: s.label, state: state, at: happened ? s.at : null, hint: hint));
    }
  } else if (!referral && currentStep != null && currentStep.count > 1 && !draft) {
    // a list row carries no chain: the steps before the current one are done, the later ones wait
    for (var i = 0; i < currentStep.count; i++) {
      final now = i == currentStep.index;
      points.add(AdvTrackPoint(
        label: now ? currentStep.label : t('الخطوة ${i + 1}', 'Step ${i + 1}'),
        state: i < currentStep.index
            ? AdvTrackState.done
            : (now ? (ended ? AdvTrackState.stopped : (stage == 'needs_info' ? AdvTrackState.attention : AdvTrackState.current)) : (ended ? AdvTrackState.stopped : AdvTrackState.waiting)),
      ));
    }
  } else if (referral || currentStep != null) {
    // a referral has no chain (one decision by the receiving department); an older answer may leave the chain out
    final label = referral ? (target == null || target.isEmpty ? t('الجهة المحال إليها', 'The receiving department') : target) : currentStep!.label;
    final state = switch (outcome) {
      'handled' || 'approved' => AdvTrackState.done,
      'declined' || 'rejected' => AdvTrackState.failed,
      null => draft ? AdvTrackState.waiting : (stage == 'needs_info' ? AdvTrackState.attention : AdvTrackState.current),
      _ => AdvTrackState.stopped,
    };
    points.add(AdvTrackPoint(label: label, state: state, hint: state == AdvTrackState.current && stage == 'in_progress' ? advStageLabel('in_progress') : null));
  }
  final decision = switch (outcome) {
    'approved' || 'handled' => AdvTrackPoint(label: advOutcomeLabel(outcome), state: AdvTrackState.done, at: outcomeAt),
    'rejected' || 'declined' => AdvTrackPoint(label: advOutcomeLabel(outcome), state: AdvTrackState.failed, at: outcomeAt),
    'withdrawn' || 'closed' => AdvTrackPoint(label: advOutcomeLabel(outcome), state: AdvTrackState.stopped, at: outcomeAt),
    _ => AdvTrackPoint(label: t('القرار', 'Decision'), state: AdvTrackState.waiting),
  };
  points.add(decision);
  if (stage == 'closed') points.add(AdvTrackPoint(label: t('أُغلقت الحالة', 'Case closed'), state: AdvTrackState.done, at: closedAt));
  return points;
}

// ── The composer's body ──────────────────────────────────────────────────────

/// The longest title and body the server keeps.
const advRequestTitleMax = 200;
const advRequestBodyMax = 10000;
const advRequestMaxAttachments = 10;

/// A request being written: the POST (with `submit`), a draft's whole-object PUT (with `version`), and the copy kept
/// on the device while typing ([toStore] / [fromStore], attachments by id only).
class AdvRequestDraft {
  const AdvRequestDraft({
    this.kind = 'support',
    this.supportType,
    this.targetDeptId,
    this.categoryId,
    this.title = '',
    this.body = '',
    this.priority = 'normal',
    this.accommodations = const [],
    this.accommodationUntil,
    this.attachments = const [],
    this.templateId,
    this.flagId,
    this.clientId,
  });

  final String kind;
  final String? supportType;
  final int? targetDeptId, categoryId;
  final String title, body, priority;
  final List<String> accommodations;
  final DateTime? accommodationUntil;
  final List<GovAttachment> attachments;
  final int? templateId, flagId;
  final String? clientId;

  bool get referral => kind == 'referral';

  /// A draft request opened again for editing.
  factory AdvRequestDraft.of(AdvRequest r) => AdvRequestDraft(
        kind: r.kind,
        supportType: r.supportType,
        targetDeptId: r.targetDept?.id,
        categoryId: r.category?.id,
        title: r.title,
        body: r.body,
        priority: r.priority,
        accommodations: [for (final a in r.accommodations) a.key],
        accommodationUntil: r.accommodationUntil,
        attachments: r.attachments,
        templateId: r.templateId,
        flagId: r.flagId,
      );

  AdvRequestDraft copyWith({
    String? kind,
    String? Function()? supportType,
    int? Function()? targetDeptId,
    int? Function()? categoryId,
    String? title,
    String? body,
    String? priority,
    List<String>? accommodations,
    DateTime? Function()? accommodationUntil,
    List<GovAttachment>? attachments,
    int? Function()? templateId,
    String? Function()? clientId,
  }) =>
      AdvRequestDraft(
        kind: kind ?? this.kind,
        supportType: supportType == null ? this.supportType : supportType(),
        targetDeptId: targetDeptId == null ? this.targetDeptId : targetDeptId(),
        categoryId: categoryId == null ? this.categoryId : categoryId(),
        title: title ?? this.title,
        body: body ?? this.body,
        priority: priority ?? this.priority,
        accommodations: accommodations ?? this.accommodations,
        accommodationUntil: accommodationUntil == null ? this.accommodationUntil : accommodationUntil(),
        attachments: attachments ?? this.attachments,
        templateId: templateId == null ? this.templateId : templateId(),
        flagId: flagId,
        clientId: clientId == null ? this.clientId : clientId(),
      );

  /// Picks a support type: its default category comes with it; accommodations stay only when the type needs them.
  AdvRequestDraft withType(AdvSupportType type, List<AdvCategory> categories) {
    final cat = type.categoryKey == null ? null : categories.where((c) => c.key == type.categoryKey).firstOrNull;
    return copyWith(
      supportType: () => type.key,
      categoryId: () => cat?.id ?? (type.categoryKey == null ? null : categoryId),
      accommodations: type.needsAccommodations ? accommodations : const [],
      accommodationUntil: type.needsAccommodations ? null : () => null,
    );
  }

  AdvRequestDraft toggleAccommodation(String key) =>
      copyWith(accommodations: accommodations.contains(key) ? [for (final a in accommodations) if (a != key) a] : [...accommodations, key]);

  /// Why it cannot be sent (null: it can). [type] = the chosen support type; [submit]: sending, not saving a draft.
  String? error({AdvSupportType? type, bool submit = true}) {
    final title = this.title.trim();
    if (title.isEmpty) return t('اكتب عنواناً للطلب', 'Give the request a title');
    if (title.length > advRequestTitleMax) return t('العنوان أطول من $advRequestTitleMax حرف', 'The title is longer than $advRequestTitleMax characters');
    if (body.length > advRequestBodyMax) return t('النص أطول من الحد المسموح', 'The text is longer than allowed');
    if (attachments.length > advRequestMaxAttachments) return t('الحد الأقصى 10 مرفقات', 'At most 10 attachments');
    if (referral) {
      if (targetDeptId == null) return t('اختر الجهة التي يُحال إليها الطالب', 'Choose the department to refer the student to');
    } else {
      if (supportType == null) return t('اختر نوع الطلب', 'Choose the type of request');
      if (submit && type != null && type.needsAccommodations && accommodations.isEmpty) {
        return t('اختر التسهيلات المطلوبة', 'Choose the accommodations requested');
      }
    }
    if (submit && body.trim().isEmpty) return t('اكتب تفاصيل الطلب', 'Write the details of the request');
    return null;
  }

  /// Something worth keeping on the device.
  bool get worthKeeping => title.trim().isNotEmpty || body.trim().isNotEmpty;

  /// POST `…/students/{mid}/requests` ([submit]) or the draft's PUT ([version]).
  Map<String, dynamic> toJson({bool submit = false, int? version}) => {
        'kind': kind,
        'support_type': referral ? null : supportType,
        'target_dept_id': referral ? targetDeptId : null,
        'category_id': categoryId,
        'title': title.trim(),
        'body': body.trim(),
        'priority': priority,
        'accommodations': referral ? <String>[] : accommodations,
        'accommodation_until': referral || accommodationUntil == null ? null : orgDay(accommodationUntil),
        'attachments': [for (final a in attachments) a.toJson()],
        'template_id': templateId,
        'flag_id': flagId,
        if (version == null) 'client_id': clientId,
        if (version == null) 'submit': submit,
        'version': ?version,
      };

  Map<String, dynamic> toStore() => {
        'kind': kind,
        'support_type': supportType,
        'target_dept_id': targetDeptId,
        'category_id': categoryId,
        'title': title,
        'body': body,
        'priority': priority,
        'accommodations': accommodations,
        'accommodation_until': accommodationUntil == null ? null : orgDay(accommodationUntil),
        'attachments': [
          for (final a in attachments) {'id': a.id, 'name': a.name, 'type': a.type, 'ext': a.ext, 'size': a.size, 'preview': a.preview},
        ],
        'template_id': templateId,
        'client_id': clientId,
      };

  factory AdvRequestDraft.fromStore(Map<String, dynamic> j) => AdvRequestDraft(
        kind: _text(j['kind']) ?? 'support',
        supportType: _text(j['support_type']),
        targetDeptId: _id(j['target_dept_id']),
        categoryId: _id(j['category_id']),
        title: asStr(j['title']),
        body: asStr(j['body']),
        priority: advPriorities.contains(j['priority']) ? asStr(j['priority']) : 'normal',
        accommodations: [for (final a in (j['accommodations'] is List ? j['accommodations'] as List : const [])) '$a'],
        accommodationUntil: advParseDay(j['accommodation_until']),
        attachments: [for (final m in asMapList(j['attachments'])) if (m['id'] != null) GovAttachment.fromJson(m)],
        templateId: _id(j['template_id']),
        clientId: _text(j['client_id']),
      );
}

// ── The composer's choices ───────────────────────────────────────────────────

class AdvSupportType {
  const AdvSupportType({required this.key, this.labelAr = '', this.labelEn = '', this.categoryKey, this.needsAccommodations = false});
  final String key, labelAr, labelEn;

  /// The category a request of this type is filed under by default (`accommodation` → `accessibility`, …).
  final String? categoryKey;

  /// The composer asks which accommodations (and until when).
  final bool needsAccommodations;

  factory AdvSupportType.fromJson(Map<String, dynamic> j) => AdvSupportType(
        key: asStr(j['key']),
        labelAr: asStr(j['label_ar']).trim(),
        labelEn: asStr(j['label_en']).trim(),
        categoryKey: _text(j['category_key']),
        needsAccommodations: asBool(j['needs_accommodations']),
      );

  String get label => _pick(labelAr, labelEn, advSupportTypeKeyLabel(key));
}

/// A request template (`adv_templates` of kind `support_request`).
class AdvRequestTemplate {
  const AdvRequestTemplate({required this.id, this.nameAr = '', this.nameEn = '', this.bodyAr = '', this.bodyEn = ''});
  final int id;
  final String nameAr, nameEn, bodyAr, bodyEn;

  factory AdvRequestTemplate.fromJson(Map<String, dynamic> j) => AdvRequestTemplate(
        id: asInt(j['id']),
        nameAr: asStr(j['name_ar']).trim(),
        nameEn: asStr(j['name_en']).trim(),
        bodyAr: asStr(j['body_ar']),
        bodyEn: asStr(j['body_en']),
      );

  String get name => _pick(nameAr, nameEn, '#$id');

  /// The body in the app's language (the other one when that is empty).
  String get body => _pick(bodyAr, bodyEn);
}

/// Fills a template's `{placeholders}`: the known ones from [values], every other one left empty for the advisor to
/// write (e.g. `{details}`).
String advFillTemplate(String body, Map<String, String> values) =>
    body.replaceAllMapped(RegExp(r'\{([a-z_]+)\}'), (m) => values[m.group(1)!] ?? '');

/// `GET …/request-options`.
class AdvRequestOptions {
  const AdvRequestOptions({this.supportTypes = const [], this.referralTargets = const [], this.categories = const [], this.templates = const [], this.priorities = advPriorities});
  final List<AdvSupportType> supportTypes;

  /// Suggested (preset) ones first.
  final List<AdvSupportEntity> referralTargets;
  final List<AdvCategory> categories;
  final List<AdvRequestTemplate> templates;
  final List<String> priorities;

  factory AdvRequestOptions.fromJson(Map<String, dynamic> j) {
    final types = [for (final m in asMapList(j['support_types'])) AdvSupportType.fromJson(m)].where((x) => x.key.isNotEmpty).toList();
    final targets = [for (final m in asMapList(j['referral_targets'])) AdvSupportEntity.fromJson(m)];
    // suggested first, then the presets in their order, then by name (a stable sort keeps the server's order)
    int rank(AdvSupportEntity e) => e.suggested ? 0 : (advReferralPresets.contains(e.preset) ? 1 : 2);
    targets.sort((a, b) => rank(a).compareTo(rank(b)));
    final pr = [for (final p in (j['priorities'] is List ? j['priorities'] as List : const [])) '$p'].where(advPriorities.contains).toList();
    return AdvRequestOptions(
      supportTypes: types.isNotEmpty ? types : [for (final k in advSupportTypeKeys) AdvSupportType(key: k, needsAccommodations: k == 'accommodation', categoryKey: _defaultCategoryKey(k))],
      referralTargets: targets,
      categories: [for (final m in asMapList(j['categories'])) AdvCategory.fromJson(m)],
      templates: [for (final m in asMapList(j['templates'])) AdvRequestTemplate.fromJson(m)],
      priorities: pr.isEmpty ? advPriorities : pr,
    );
  }

  AdvSupportType? type(String? key) => supportTypes.where((x) => x.key == key).firstOrNull;
  AdvCategory? category(int? id) => categories.where((c) => c.id == id).firstOrNull;
  AdvSupportEntity? target(int? id) => referralTargets.where((x) => x.id == id).firstOrNull;
}

String? _defaultCategoryKey(String type) => switch (type) {
      'accommodation' => 'accessibility',
      'financial_support' => 'financial',
      'other' => null,
      _ => 'academic',
    };

/// The request list's query.
class AdvRequestQuery {
  const AdvRequestQuery({this.memberId, this.queue = '', this.filter = '', this.mine = false, this.q = '', this.page = 1, this.size = 20});
  final int? memberId;

  /// '' · `review` · `needs_info` · `overdue`.
  final String queue;

  /// One of [advRequestFilters].
  final String filter;
  final bool mine;
  final String q;
  final int page, size;

  AdvRequestQuery copyWith({String? queue, String? filter, bool? mine, String? q, int? page}) =>
      AdvRequestQuery(memberId: memberId, queue: queue ?? this.queue, filter: filter ?? this.filter, mine: mine ?? this.mine, q: q ?? this.q, page: page ?? this.page, size: size);

  Map<String, dynamic> toQuery() => {
        'member_id': ?memberId,
        if (filter.startsWith('kind:')) 'kind': filter.substring(5),
        if (filter.startsWith('stage:')) 'stage': filter.substring(6),
        if (queue.isNotEmpty) 'queue': queue,
        if (mine) 'mine': 1,
        if (q.trim().isNotEmpty) 'q': q.trim(),
        'page': page,
        'size': size,
      };
}

// ═════════════════════════════════════════════════════════════════════════════
//  The approval chain (#12)
// ═════════════════════════════════════════════════════════════════════════════

/// The most steps a chain may have.
const advChainMaxSteps = 6;

class AdvChainStep {
  const AdvChainStep({required this.kind, this.deptId, this.labelAr = '', this.labelEn = ''});
  final String kind;

  /// The entity of an `entity` step.
  final int? deptId;
  final String labelAr, labelEn;

  factory AdvChainStep.fromJson(Map<String, dynamic> j) =>
      AdvChainStep(kind: asStr(j['kind']), deptId: _id(j['dept_id']), labelAr: asStr(j['label_ar']).trim(), labelEn: asStr(j['label_en']).trim());

  String get label => _pick(labelAr, labelEn, advChainKindLabel(kind));

  Map<String, dynamic> toJson() => {'kind': kind, 'dept_id': kind == 'entity' ? deptId : null};

  bool same(AdvChainStep o) => kind == o.kind && (kind != 'entity' || deptId == o.deptId);
}

/// One scope row that sets its own chain.
class AdvChainScope {
  const AdvChainScope({this.policyId, required this.scopeType, this.scopeRef, this.labelAr = '', this.labelEn = '', this.steps = const []});
  final int? policyId;
  final String scopeType;
  final String? scopeRef;
  final String labelAr, labelEn;
  final List<AdvChainStep> steps;

  factory AdvChainScope.fromJson(Map<String, dynamic> j) => AdvChainScope(
        policyId: _id(j['policy_id']),
        scopeType: asStr(j['scope_type']),
        scopeRef: _text(j['scope_ref']),
        labelAr: asStr(j['label']).trim(),
        labelEn: asStr(j['label_en']).trim(),
        steps: [for (final m in asMapList(j['steps'])) AdvChainStep.fromJson(m)],
      );

  String get label => _pick(labelAr, labelEn, scopeRef ?? '');
  String get key => '$scopeType:${scopeRef ?? ''}';
}

class AdvChainKindOption {
  const AdvChainKindOption({required this.key, this.labelAr = '', this.labelEn = '', this.needsDept = false});
  final String key, labelAr, labelEn;
  final bool needsDept;

  factory AdvChainKindOption.fromJson(Map<String, dynamic> j) =>
      AdvChainKindOption(key: asStr(j['key']), labelAr: asStr(j['label_ar']).trim(), labelEn: asStr(j['label_en']).trim(), needsDept: asBool(j['needs_dept']));

  String get label => _pick(labelAr, labelEn, advChainKindLabel(key));
}

/// `GET …/request-chain` (also the PUT's answer).
class AdvChainConfig {
  const AdvChainConfig({
    this.orgSteps = const [],
    this.orgInherited = true,
    this.defaults = const [],
    this.scopes = const [],
    this.kinds = const [],
    this.entities = const [],
    this.facultyCouncil = false,
    this.departmentCouncils = 0,
    this.advisingDept,
  });

  final List<AdvChainStep> orgSteps;

  /// The organization's chain comes from a parent organization / the defaults.
  final bool orgInherited;
  final List<AdvChainStep> defaults;
  final List<AdvChainScope> scopes;
  final List<AdvChainKindOption> kinds;
  final List<AdvSupportEntity> entities;

  /// This organization has a faculty council.
  final bool facultyCouncil;

  /// How many scientific departments have a council.
  final int departmentCouncils;
  final AdvSupportEntity? advisingDept;

  factory AdvChainConfig.fromJson(Map<String, dynamic> j) {
    final org = asMap(j['org']);
    final o = asMap(j['options']);
    final kinds = [for (final m in asMapList(o['kinds'])) AdvChainKindOption.fromJson(m)].where((k) => k.key.isNotEmpty).toList();
    return AdvChainConfig(
      orgSteps: [for (final m in asMapList(org['steps'])) AdvChainStep.fromJson(m)],
      orgInherited: asBool(org['inherited'], true),
      defaults: [for (final m in asMapList(j['defaults'])) AdvChainStep.fromJson(m)],
      scopes: [for (final m in asMapList(j['scopes'])) AdvChainScope.fromJson(m)],
      kinds: kinds.isNotEmpty ? kinds : [for (final k in advChainKinds) AdvChainKindOption(key: k, needsDept: k == 'entity')],
      entities: [for (final m in asMapList(o['entities'])) AdvSupportEntity.fromJson(m)],
      facultyCouncil: asBool(o['faculty_council']),
      departmentCouncils: asInt(o['department_councils']),
      advisingDept: AdvSupportEntity.maybe(o['advising_dept']),
    );
  }

  /// The steps of a scope ([scopeType] `org` = the organization's), null when that scope inherits.
  List<AdvChainStep>? stepsOf(String scopeType, String? scopeRef) {
    if (scopeType == 'org') return orgSteps;
    return scopes.where((s) => s.scopeType == scopeType && s.scopeRef == scopeRef).firstOrNull?.steps;
  }

  AdvSupportEntity? entity(int? id) => entities.where((e) => e.id == id).firstOrNull;
}

/// The first problem of a chain the server would refuse (`advising_chain_invalid` reasons), with its step index;
/// null when it can be saved. Mirrors the server's validation.
(int, String)? advChainProblem(List<AdvChainStep> steps, {required bool facultyCouncil, Set<int>? entityIds}) {
  if (steps.isEmpty) return (0, 'empty');
  if (steps.length > advChainMaxSteps) return (advChainMaxSteps, 'too_many');
  for (var i = 0; i < steps.length; i++) {
    final s = steps[i];
    if (!advChainKinds.contains(s.kind)) return (i, 'unknown_kind');
    if (s.kind == 'director_review' && i > 0) return (i, 'director_first');
    if (i > 0 && s.same(steps[i - 1])) return (i, 'duplicate');
    if (s.kind == 'entity' && (s.deptId == null || (entityIds != null && !entityIds.contains(s.deptId)))) return (i, 'entity_invalid');
    if (s.kind == 'faculty_council' && !facultyCouncil) return (i, 'no_faculty_council');
  }
  return null;
}

/// The sentence of a chain problem (local or the server's 422 `advising_chain_invalid` `{index, reason}`).
String advChainProblemText(String reason, {int? index}) {
  final at = index == null ? '' : t(' (الخطوة ${index + 1})', ' (step ${index + 1})');
  return switch (reason) {
        'empty' => t('أضف خطوة واحدة على الأقل', 'Add at least one step'),
        'too_many' => t('الحد الأقصى $advChainMaxSteps خطوات', 'At most $advChainMaxSteps steps'),
        'unknown_kind' => t('نوع خطوة غير معروف', 'An unknown kind of step'),
        'director_first' => t('مراجعة مدير الإرشاد تكون الخطوة الأولى فقط', 'The advising director review can only be the first step'),
        'duplicate' => t('خطوتان متتاليتان متطابقتان', 'Two identical steps in a row'),
        'entity_invalid' => t('اختر إدارة أو لجنة نشطة لهذه الخطوة', 'Choose an active office or committee for this step'),
        'no_faculty_council' => t('لا مجلس كلية في هذه المؤسسة — احذف خطوة مجلس الكلية', 'This organization has no faculty council — remove the faculty council step'),
        _ => t('سلسلة الاعتماد غير صالحة', 'The approval chain is not valid'),
      } +
      at;
}

/// One step of `GET …/request-chain/preview`: will it run for this student, and if not why.
class AdvChainPreviewStep {
  const AdvChainPreviewStep({required this.step, this.resolved = true, this.reason});
  final AdvChainStep step;
  final bool resolved;
  final String? reason;

  factory AdvChainPreviewStep.fromJson(Map<String, dynamic> j) =>
      AdvChainPreviewStep(step: AdvChainStep.fromJson(j), resolved: asBool(j['resolved'], true), reason: _text(j['reason']));
}

class AdvChainPreview {
  const AdvChainPreview({this.steps = const [], this.advisingDept});
  final List<AdvChainPreviewStep> steps;
  final AdvSupportEntity? advisingDept;

  factory AdvChainPreview.fromJson(Map<String, dynamic> j) => AdvChainPreview(
        steps: [for (final m in asMapList(j['steps'])) AdvChainPreviewStep.fromJson(m)],
        advisingDept: AdvSupportEntity.maybe(j['advising_dept']),
      );

  int get skipped => steps.where((s) => !s.resolved).length;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Support plans (#14)
// ═════════════════════════════════════════════════════════════════════════════

const advPlanStatuses = ['draft', 'active', 'completed', 'cancelled'];

String advPlanStatusLabel(String? s) => switch (s) {
      'draft' => t('مسودة', 'Draft'),
      'active' => t('نشطة', 'Active'),
      'completed' => t('مكتملة', 'Completed'),
      'cancelled' => t('ملغاة', 'Cancelled'),
      _ => t('غير معروفة', 'Unknown'),
    };

String advPlanStatusHint(String s) => switch (s) {
      'active' => t('يبدأ العمل بها، ويراها الطالب إن كانت ظاهرة له', 'Work on it starts; the student sees it when it is shown to them'),
      'completed' => t('انتهت؛ تُسجَّل نتيجة المقياس وتُكتب الخلاصة', 'It is over: the measure\'s result is recorded with an outcome note'),
      'cancelled' => t('تتوقف دون إكمال', 'It stops without being completed'),
      'draft' => t('تعود مسودة', 'Back to a draft'),
      _ => '',
    };

/// The moves a plan may make from [status] (the server's `request_flow.py`).
List<String> advPlanNext(String status) => switch (status) {
      'draft' => const ['active', 'cancelled'],
      'active' => const ['completed', 'cancelled'],
      'completed' || 'cancelled' => const ['active'],
      _ => const [],
    };

const advPlanMeasureKinds = ['term_gpa', 'cgpa', 'absence_max', 'custom'];

String advPlanMeasureLabel(String kind) => switch (kind) {
      'term_gpa' => t('معدل الفصل', 'Term GPA'),
      'cgpa' => t('المعدل التراكمي', 'CGPA'),
      'absence_max' => t('أعلى نسبة غياب', 'Highest absence'),
      'custom' => t('مقياس آخر', 'Another measure'),
      _ => kind,
    };

/// Absence is met at or below its target; a GPA at or above.
bool advMeasureLowerIsBetter(String kind) => kind == 'absence_max';

const advPlanItemOwners = ['student', 'advisor', 'other'];

String advPlanOwnerLabel(String? o) => switch (o) {
      'student' => t('الطالب', 'Student'),
      'advisor' => t('المرشد', 'Advisor'),
      'other' => t('جهة أخرى', 'Someone else'),
      _ => '',
    };

String advPlanItemStatusLabel(String? s) => switch (s) {
      'done' => t('تم', 'Done'),
      'dropped' => t('أُسقط', 'Dropped'),
      _ => t('مفتوح', 'Open'),
    };

class AdvPlanMeasure {
  const AdvPlanMeasure({required this.kind, this.target, this.text});
  final String kind;
  final double? target;
  final String? text;

  static AdvPlanMeasure? maybe(dynamic v) {
    if (v is! Map) return null;
    final j = asMap(v);
    final kind = asStr(j['kind']);
    if (kind.isEmpty) return null;
    return AdvPlanMeasure(kind: kind, target: _num(j['target']), text: _text(j['text']));
  }

  Map<String, dynamic> toJson() => {'kind': kind, 'target': kind == 'custom' ? null : target, 'text': kind == 'custom' ? text?.trim() : null};

  /// "Term GPA ≥ 2.50" · "Highest absence ≤ 15%" · the custom text.
  String get summary {
    if (kind == 'custom') return text ?? advPlanMeasureLabel(kind);
    final v = target;
    if (v == null) return advPlanMeasureLabel(kind);
    final shown = kind == 'absence_max' ? '${_trim(v)}%' : v.toStringAsFixed(2);
    return '${advPlanMeasureLabel(kind)} ${advMeasureLowerIsBetter(kind) ? '≤' : '≥'} $shown';
  }

  /// Why the measure cannot be saved (422 `advising_bad_measure`); null when fine.
  String? get error {
    if (!advPlanMeasureKinds.contains(kind)) return t('مقياس غير معروف', 'An unknown measure');
    if (kind == 'custom') return (text ?? '').trim().isEmpty ? t('صف المقياس', 'Describe the measure') : null;
    final v = target;
    if (v == null) return t('أدخل القيمة المستهدفة', 'Enter the target value');
    if (kind == 'absence_max' ? (v < 0 || v > 100) : (v < 0 || v > 5)) {
      return kind == 'absence_max' ? t('النسبة بين 0 و100', 'A percentage between 0 and 100') : t('المعدل بين 0 و5', 'A GPA between 0 and 5');
    }
    return null;
  }
}

String _trim(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

class AdvPlanResult {
  const AdvPlanResult({this.value, this.met, this.at});
  final double? value;
  final bool? met;
  final DateTime? at;

  static AdvPlanResult? maybe(dynamic v) {
    if (v is! Map) return null;
    final j = asMap(v);
    final met = j['met'];
    return AdvPlanResult(value: _num(j['value']), met: met is bool ? met : null, at: orgParseUtc(j['at']));
  }
}

class AdvSupportPlanItem {
  const AdvSupportPlanItem({
    this.id,
    this.goal = '',
    this.action = '',
    this.owner = 'student',
    this.ownerNote,
    this.dueAt,
    this.status = 'open',
    this.doneAt,
    this.note,
    this.order = 0,
    this.overdue = false,
    this.mine,
  });

  /// null: a new item (not saved yet).
  final int? id;
  final String goal, action, owner;
  final String? ownerNote;
  final DateTime? dueAt;
  final String status;
  final DateTime? doneAt;
  final String? note;
  final int order;
  final bool overdue;

  /// The student's view: an `owner=student` item of an active plan, theirs to tick (null from staff routes).
  final bool? mine;

  factory AdvSupportPlanItem.fromJson(Map<String, dynamic> j) => AdvSupportPlanItem(
        id: _id(j['id']),
        goal: asStr(j['goal']).trim(),
        action: asStr(j['action']).trim(),
        owner: _text(j['owner']) ?? 'student',
        ownerNote: _text(j['owner_note']),
        dueAt: orgParseUtc(j['due_at']),
        status: _text(j['status']) ?? 'open',
        doneAt: orgParseUtc(j['done_at']),
        note: _text(j['note']),
        order: asInt(j['order']),
        overdue: asBool(j['overdue']),
        mine: j['mine'] is bool ? j['mine'] as bool : null,
      );

  bool get done => status == 'done';
  bool get dropped => status == 'dropped';

  /// "Student" · "Someone else: Student Affairs office".
  String get ownerText => owner == 'other' && ownerNote != null ? '${advPlanOwnerLabel(owner)}: $ownerNote' : advPlanOwnerLabel(owner);

  AdvSupportPlanItem copyWith({String? goal, String? action, String? owner, String? Function()? ownerNote, DateTime? Function()? dueAt}) => AdvSupportPlanItem(
        id: id,
        goal: goal ?? this.goal,
        action: action ?? this.action,
        owner: owner ?? this.owner,
        ownerNote: ownerNote == null ? this.ownerNote : ownerNote(),
        dueAt: dueAt == null ? this.dueAt : dueAt(),
        status: status,
        doneAt: doneAt,
        note: note,
        order: order,
        overdue: overdue,
        mine: mine,
      );

  Map<String, dynamic> toJson() => {
        'id': ?id,
        'goal': goal.trim(),
        'action': action.trim(),
        'owner': owner,
        'owner_note': owner == 'other' && (ownerNote ?? '').trim().isNotEmpty ? ownerNote!.trim() : null,
        'due_at': orgUtc(dueAt),
        // the PUT replaces the items: a done item stays done
        'status': status,
      };
}

class AdvPlanCan {
  const AdvPlanCan({this.edit = false, this.status = false, this.delete = false});
  final bool edit, status, delete;

  factory AdvPlanCan.fromJson(Map<String, dynamic> j) => AdvPlanCan(edit: asBool(j['edit']), status: asBool(j['status']), delete: asBool(j['delete']));
}

/// A support plan (`Plan`).
class AdvSupportPlan {
  const AdvSupportPlan({
    required this.id,
    this.memberId = 0,
    this.title = '',
    this.status = 'draft',
    this.measure,
    this.result,
    this.followUpAt,
    this.studentVisible = false,
    this.flagId,
    this.requestId,
    this.outcomeNote,
    this.closedAt,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.version = 0,
    this.done = 0,
    this.total = 0,
    this.items = const [],
    this.can = const AdvPlanCan(),
    this.reviewDue = false,
    this.reviewDueAt,
    this.reviewedAt,
    this.measureNow,
  });

  final int id, memberId;
  final String title, status;
  final AdvPlanMeasure? measure;
  final AdvPlanResult? result;
  final DateTime? followUpAt;
  final bool studentVisible;
  final int? flagId, requestId;
  final String? outcomeNote;
  final DateTime? closedAt;
  final AdvRef? createdBy;
  final DateTime? createdAt, updatedAt;
  final int version;

  /// `progress`.
  final int done, total;
  final List<AdvSupportPlanItem> items;
  final AdvPlanCan can;

  /// The follow-up date arrived and nobody reviewed the plan yet (`POST …/plans/{id}/review`).
  final bool reviewDue;
  final DateTime? reviewDueAt, reviewedAt;

  /// The measure on the student's current stats row (`{value, met}`).
  final AdvPlanResult? measureNow;

  factory AdvSupportPlan.fromJson(Map<String, dynamic> j) {
    final items = [for (final m in asMapList(j['items'])) AdvSupportPlanItem.fromJson(m)]..sort((a, b) => a.order.compareTo(b.order));
    final p = j['progress'];
    final live = items.where((i) => !i.dropped).toList();
    return AdvSupportPlan(
      id: asInt(j['id']),
      memberId: asInt(j['member_id']),
      title: asStr(j['title']).trim(),
      status: _text(j['status']) ?? 'draft',
      measure: AdvPlanMeasure.maybe(j['measure']),
      result: AdvPlanResult.maybe(j['result']),
      followUpAt: orgParseUtc(j['follow_up_at']),
      studentVisible: asBool(j['student_visible']),
      flagId: _id(j['flag_id']),
      requestId: _id(j['request_id']),
      outcomeNote: _text(j['outcome_note']),
      closedAt: orgParseUtc(j['closed_at']),
      createdBy: AdvRef.maybe(j['created_by']),
      createdAt: orgParseUtc(j['created_at']),
      updatedAt: orgParseUtc(j['updated_at']),
      version: asInt(j['version']),
      done: p is Map ? asInt(asMap(p)['done']) : live.where((i) => i.done).length,
      total: p is Map ? asInt(asMap(p)['total']) : live.length,
      items: items,
      can: AdvPlanCan.fromJson(asMap(j['can'])),
      reviewDue: asBool(j['review_due']),
      reviewDueAt: orgParseUtc(j['review_due_at']),
      reviewedAt: orgParseUtc(j['reviewed_at']),
      measureNow: AdvPlanResult.maybe(j['measure_now']),
    );
  }

  bool get active => status == 'active';
  bool get finished => status == 'completed' || status == 'cancelled';

  /// 0 – 1.
  double get progress => total <= 0 ? 0 : (done / total).clamp(0, 1).toDouble();

  String get shownTitle => title.isEmpty ? t('خطة دعم', 'Support plan') : title;

  /// The same plan with one item's status changed (the optimistic tick before the server answers).
  AdvSupportPlan withItemStatus(int itemId, String status) {
    final items = [
      for (final i in this.items)
        i.id == itemId
            ? AdvSupportPlanItem(
                id: i.id, goal: i.goal, action: i.action, owner: i.owner, ownerNote: i.ownerNote, dueAt: i.dueAt, status: status, doneAt: status == 'done' ? DateTime.now().toUtc() : null, note: i.note, order: i.order, mine: i.mine)
            : i,
    ];
    final live = items.where((i) => !i.dropped).toList();
    return AdvSupportPlan(
      id: id, memberId: memberId, title: title, status: this.status, measure: measure, result: result, followUpAt: followUpAt, studentVisible: studentVisible,
      flagId: flagId, requestId: requestId, outcomeNote: outcomeNote, closedAt: closedAt, createdBy: createdBy, createdAt: createdAt, updatedAt: updatedAt,
      version: version, done: live.where((i) => i.done).length, total: live.length, items: items, can: can,
      reviewDue: reviewDue, reviewDueAt: reviewDueAt, reviewedAt: reviewedAt, measureNow: measureNow,
    );
  }
}

/// The plan editor's body: the POST (with [status] `draft` | `active`) and the whole-object PUT (with `version`).
class AdvPlanDraft {
  const AdvPlanDraft({
    this.title = '',
    this.status = 'draft',
    this.measure,
    this.followUpAt,
    this.studentVisible = true,
    this.flagId,
    this.requestId,
    this.items = const [],
  });

  final String title, status;
  final AdvPlanMeasure? measure;
  final DateTime? followUpAt;
  final bool studentVisible;
  final int? flagId, requestId;
  final List<AdvSupportPlanItem> items;

  /// The most items a plan holds.
  static const maxItems = 30;

  factory AdvPlanDraft.of(AdvSupportPlan p) => AdvPlanDraft(
        title: p.title,
        status: p.status,
        measure: p.measure,
        followUpAt: p.followUpAt,
        studentVisible: p.studentVisible,
        flagId: p.flagId,
        requestId: p.requestId,
        items: p.items,
      );

  AdvPlanDraft copyWith({String? title, String? status, AdvPlanMeasure? Function()? measure, DateTime? Function()? followUpAt, bool? studentVisible, List<AdvSupportPlanItem>? items}) =>
      AdvPlanDraft(
        title: title ?? this.title,
        status: status ?? this.status,
        measure: measure == null ? this.measure : measure(),
        followUpAt: followUpAt == null ? this.followUpAt : followUpAt(),
        studentVisible: studentVisible ?? this.studentVisible,
        flagId: flagId,
        requestId: requestId,
        items: items ?? this.items,
      );

  /// Why it cannot be saved (null: it can).
  String? get error {
    if (title.trim().isEmpty) return t('اكتب عنواناً للخطة', 'Give the plan a title');
    final m = measure;
    if (m != null && m.error != null) return m.error;
    if (items.isEmpty) return t('أضف بنداً واحداً على الأقل', 'Add at least one item');
    if (items.length > maxItems) return t('الحد الأقصى $maxItems بنداً', 'At most $maxItems items');
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (it.goal.trim().isEmpty) return t('اكتب هدف البند ${i + 1}', 'Write the goal of item ${i + 1}');
      if (it.goal.trim().length > 500) return t('هدف البند ${i + 1} طويل جداً', 'The goal of item ${i + 1} is too long');
      if (it.action.trim().length > 2000) return t('إجراء البند ${i + 1} طويل جداً', 'The action of item ${i + 1} is too long');
      if ((it.ownerNote ?? '').trim().length > 120) return t('وصف الجهة في البند ${i + 1} طويل جداً', 'The owner of item ${i + 1} is described at too much length');
    }
    return null;
  }

  Map<String, dynamic> toJson({int? version}) => {
        'title': title.trim(),
        if (version == null) 'status': status == 'active' ? 'active' : 'draft',
        'measure': measure?.toJson(),
        'follow_up_at': orgUtc(followUpAt),
        'student_visible': studentVisible,
        'flag_id': flagId,
        'request_id': requestId,
        'items': [for (final i in items) i.toJson()],
        'version': ?version,
      };
}

// ═════════════════════════════════════════════════════════════════════════════
//  Accommodations (#24)
// ═════════════════════════════════════════════════════════════════════════════

/// An accommodation granted to a student (`Accommodation`).
class AdvAccommodationGrant {
  const AdvAccommodationGrant({
    required this.id,
    this.memberId = 0,
    this.studentName = '',
    this.key = '',
    this.labelAr = '',
    this.labelEn = '',
    this.category,
    this.status = 'active',
    this.startsOn,
    this.endsOn,
    this.source = 'manual',
    this.requestId,
    this.note,
    this.grantedBy,
    this.grantedAt,
    this.endedAt,
    this.endReason,
  });

  final int id, memberId;
  final String studentName, key, labelAr, labelEn;
  final AdvCategory? category;

  /// `active` · `ended`.
  final String status;
  final DateTime? startsOn, endsOn;

  /// `request` (an approved accommodation request) · `manual`.
  final String source;
  final int? requestId;

  /// Staff only.
  final String? note;
  final AdvRef? grantedBy;
  final DateTime? grantedAt, endedAt;
  final String? endReason;

  factory AdvAccommodationGrant.fromJson(Map<String, dynamic> j) => AdvAccommodationGrant(
        id: asInt(j['id']),
        memberId: asInt(j['member_id']),
        studentName: asStr(j['student_name']).trim(),
        key: asStr(j['key']),
        labelAr: asStr(j['label_ar']).trim(),
        labelEn: asStr(j['label_en']).trim(),
        category: AdvCategory.maybe(j['category']),
        status: _text(j['status']) ?? 'active',
        startsOn: advParseDay(j['starts_on']),
        endsOn: advParseDay(j['ends_on']),
        source: _text(j['source']) ?? 'manual',
        requestId: _id(j['request_id']),
        note: _text(j['note']),
        grantedBy: AdvRef.maybe(j['granted_by']),
        grantedAt: orgParseUtc(j['granted_at']),
        endedAt: orgParseUtc(j['ended_at']),
        endReason: _text(j['end_reason']),
      );

  bool get active => status == 'active';
  String get label => _pick(labelAr, labelEn, category?.accommodationLabel(key) ?? key);
}

/// The grant sheet's body (`POST …/students/{mid}/accommodations`).
class AdvGrantDraft {
  const AdvGrantDraft({this.categoryId, this.keys = const [], this.startsOn, this.endsOn, this.note = ''});
  final int? categoryId;
  final List<String> keys;
  final DateTime? startsOn, endsOn;
  final String note;

  AdvGrantDraft copyWith({int? Function()? categoryId, List<String>? keys, DateTime? Function()? startsOn, DateTime? Function()? endsOn, String? note}) => AdvGrantDraft(
        categoryId: categoryId == null ? this.categoryId : categoryId(),
        keys: keys ?? this.keys,
        startsOn: startsOn == null ? this.startsOn : startsOn(),
        endsOn: endsOn == null ? this.endsOn : endsOn(),
        note: note ?? this.note,
      );

  AdvGrantDraft toggle(String key) => copyWith(keys: keys.contains(key) ? [for (final k in keys) if (k != key) k] : [...keys, key]);

  String? get error {
    if (categoryId == null) return t('اختر التصنيف', 'Choose the category');
    if (keys.isEmpty) return t('اختر تسهيلاً واحداً على الأقل', 'Choose at least one accommodation');
    final s = startsOn, e = endsOn;
    if (s != null && e != null && e.isBefore(s)) return t('تاريخ النهاية يجب أن يكون بعد تاريخ البداية', 'The end date must be after the start date');
    return null;
  }

  Map<String, dynamic> toJson() => {
        'category_id': categoryId,
        'keys': keys,
        'starts_on': startsOn == null ? null : orgDay(startsOn),
        'ends_on': endsOn == null ? null : orgDay(endsOn),
        'note': note.trim().isEmpty ? null : note.trim(),
      };
}

// ═════════════════════════════════════════════════════════════════════════════
//  The 360's Support block · the student's own view
// ═════════════════════════════════════════════════════════════════════════════

class AdvSupportCan {
  const AdvSupportCan({this.request = false, this.refer = false, this.plan = false, this.accommodate = false});
  final bool request, refer, plan, accommodate;

  factory AdvSupportCan.fromJson(Map<String, dynamic> j) =>
      AdvSupportCan(request: asBool(j['request']), refer: asBool(j['refer']), plan: asBool(j['plan']), accommodate: asBool(j['accommodate']));
}

/// `GET …/students/{member_id}/support`.
class AdvSupportSummary {
  const AdvSupportSummary({
    this.requestsOpen = 0,
    this.requestsNeedsInfo = 0,
    this.requestsTotal = 0,
    this.requests = const [],
    this.referralsOpen = 0,
    this.referralsTotal = 0,
    this.referrals = const [],
    this.activePlans = const [],
    this.completedPlans = 0,
    this.accommodations = const [],
    this.restricted = 0,
    this.can = const AdvSupportCan(),
  });

  final int requestsOpen, requestsNeedsInfo, requestsTotal;

  /// The latest five, newest first.
  final List<AdvRequest> requests;
  final int referralsOpen, referralsTotal;
  final List<AdvRequest> referrals;
  final List<AdvSupportPlan> activePlans;
  final int completedPlans;

  /// The active ones.
  final List<AdvAccommodationGrant> accommodations;

  /// Sensitive requests the caller may not read, only counted.
  final int restricted;
  final AdvSupportCan can;

  factory AdvSupportSummary.fromJson(Map<String, dynamic> j) {
    final r = asMap(j['requests']), f = asMap(j['referrals']), p = asMap(j['plans']);
    return AdvSupportSummary(
      requestsOpen: asInt(r['open']),
      requestsNeedsInfo: asInt(r['needs_info']),
      requestsTotal: asInt(r['total']),
      requests: [for (final m in asMapList(r['latest'])) AdvRequest.fromJson(m)],
      referralsOpen: asInt(f['open']),
      referralsTotal: asInt(f['total']),
      referrals: [for (final m in asMapList(f['latest'])) AdvRequest.fromJson(m)],
      activePlans: [for (final m in asMapList(p['active'])) AdvSupportPlan.fromJson(m)],
      completedPlans: asInt(p['completed']),
      accommodations: [for (final m in asMapList(j['accommodations'])) AdvAccommodationGrant.fromJson(m)],
      restricted: asInt(j['restricted']),
      can: AdvSupportCan.fromJson(asMap(j['can'])),
    );
  }

  bool get empty => requestsTotal == 0 && referralsTotal == 0 && activePlans.isEmpty && completedPlans == 0 && accommodations.isEmpty && restricted == 0;
}

/// The student's `GET …/public/{org}/advising/support`.
class AdvMemberSupport {
  const AdvMemberSupport({this.requests = const [], this.plans = const [], this.accommodations = const []});
  final List<AdvStudentRequest> requests;
  final List<AdvSupportPlan> plans;
  final List<AdvAccommodationGrant> accommodations;

  factory AdvMemberSupport.fromJson(Map<String, dynamic> j) => AdvMemberSupport(
        requests: [for (final m in asMapList(j['requests'])) AdvStudentRequest.fromJson(m)],
        plans: [for (final m in asMapList(j['plans'])) AdvSupportPlan.fromJson(m)],
        accommodations: [for (final m in asMapList(j['accommodations'])) AdvAccommodationGrant.fromJson(m)],
      );

  bool get empty => requests.isEmpty && plans.isEmpty && accommodations.isEmpty;
}

/// The `/status` counts of this phase (`me.requests_review` · `requests_needs_info` · `requests_overdue`).
class AdvRequestCounts {
  const AdvRequestCounts({this.review = 0, this.needsInfo = 0, this.overdue = 0});
  final int review, needsInfo, overdue;

  factory AdvRequestCounts.fromMe(Map<String, dynamic> me) =>
      AdvRequestCounts(review: asInt(me['requests_review']), needsInfo: asInt(me['requests_needs_info']), overdue: asInt(me['requests_overdue']));

  int get attention => review + needsInfo + overdue;

  /// "3 to review · 1 needs your information".
  String get text => [
        if (review > 0) countText(review, ar1: 'طلب للمراجعة', ar2: 'طلبان للمراجعة', arFew: '$review طلبات للمراجعة', arMany: '$review طلباً للمراجعة', en1: '1 to review', en: '$review to review'),
        if (needsInfo > 0)
          countText(needsInfo, ar1: 'طلب ينتظر معلوماتك', ar2: 'طلبان ينتظران معلوماتك', arFew: '$needsInfo طلبات تنتظر معلوماتك', arMany: '$needsInfo طلباً ينتظر معلوماتك',
              en1: '1 needs your information', en: '$needsInfo need your information'),
        if (overdue > 0) countText(overdue, ar1: 'طلب متأخر', ar2: 'طلبان متأخران', arFew: '$overdue طلبات متأخرة', arMany: '$overdue طلباً متأخراً', en1: '1 overdue', en: '$overdue overdue'),
      ].join(' · ');
}

// ═════════════════════════════════════════════════════════════════════════════
//  Timeline kinds of this phase
// ═════════════════════════════════════════════════════════════════════════════

const advSupportTimelineKinds = [
  'request_submitted',
  'request_stage',
  'request_decided',
  'request_closed',
  'referral_sent',
  'referral_outcome',
  'plan_created',
  'plan_status',
  'accommodation_granted',
  'accommodation_ended',
  'plan_review_due',
  'plan_reviewed',
];

/// The line of a Phase 7 timeline entry (null: not a kind of this phase).
String? advSupportTimelineText(String kind, Map<String, dynamic> d) {
  String? title() => _text(d['title']);
  String label() => _pick(asStr(d['label_ar']).trim(), asStr(d['label_en']).trim());
  switch (kind) {
    case 'request_submitted':
      final type = _text(d['support_type']);
      final head = _text(d['kind']) == 'referral' ? t('أُرسلت إحالة', 'Referral sent') : t('أُرسل طلب دعم', 'Support request submitted');
      return [head, if (type != null) advSupportTypeKeyLabel(type), ?title()].join(' · ');
    case 'request_stage':
      final l = label();
      final s = _text(d['stage']);
      return t('مرحلة الطلب: ${l.isEmpty ? advStageLabel(s) : l}', 'Request stage: ${l.isEmpty ? advStageLabel(s) : l}');
    case 'request_decided':
      return t('قرار الطلب: ${advOutcomeLabel(_text(d['outcome']))}', 'Request decided: ${advOutcomeLabel(_text(d['outcome']))}');
    case 'request_closed':
      final o = advOutcomeLabel(_text(d['outcome']));
      return o.isEmpty ? t('أُغلق طلب', 'Request closed') : t('أُغلق طلب · $o', 'Request closed · $o');
    case 'referral_sent':
      final tg = asMap(d['target']);
      final name = _pick(asStr(tg['name']).trim(), asStr(tg['name_en']).trim());
      return name.isEmpty ? t('أُرسلت إحالة', 'Referral sent') : t('إحالة إلى $name', 'Referred to $name');
    case 'referral_outcome':
      return t('نتيجة الإحالة: ${advOutcomeLabel(_text(d['outcome']))}', 'Referral outcome: ${advOutcomeLabel(_text(d['outcome']))}');
    case 'plan_created':
      final x = title();
      return x == null ? t('خطة دعم جديدة', 'New support plan') : t('خطة دعم جديدة · $x', 'New support plan · $x');
    case 'plan_status':
      final from = _text(d['from']), to = _text(d['to']);
      if (to == null) return t('تغيّرت حالة خطة دعم', 'A support plan changed status');
      return from == null
          ? t('خطة الدعم: ${advPlanStatusLabel(to)}', 'Support plan: ${advPlanStatusLabel(to)}')
          : t('خطة الدعم: ${advPlanStatusLabel(from)} ← ${advPlanStatusLabel(to)}', 'Support plan: ${advPlanStatusLabel(from)} → ${advPlanStatusLabel(to)}');
    case 'plan_review_due':
      final x = title();
      return x == null ? t('حان موعد مراجعة خطة الدعم', 'A support plan is due for review') : t('حان موعد مراجعة الخطة · $x', 'Plan due for review · $x');
    case 'plan_reviewed':
      final x = title();
      return x == null ? t('روجعت خطة الدعم', 'Support plan reviewed') : t('روجعت الخطة · $x', 'Plan reviewed · $x');
    case 'accommodation_granted':
      final l = label();
      return l.isEmpty ? t('مُنح تسهيل', 'Accommodation granted') : t('مُنح تسهيل · $l', 'Accommodation granted · $l');
    case 'accommodation_ended':
      final l = label();
      return l.isEmpty ? t('انتهى تسهيل', 'Accommodation ended') : t('انتهى تسهيل · $l', 'Accommodation ended · $l');
  }
  return null;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Push / deep links
// ═════════════════════════════════════════════════════════════════════════════

/// Where an advising notice of this phase leads (push data `kind` · `request_id` | `plan_id` | `accommodation_id`
/// · `member_id` · `audience`), from the push's own map or its nested `data`.
class AdvSupportLink {
  const AdvSupportLink({required this.kind, this.requestId, this.planId, this.accommodationId, this.memberId, this.student = false});

  /// `request` · `plan` · `accommodation`.
  final String kind;
  final int? requestId, planId, accommodationId, memberId;

  /// `audience` = `student`: the student's own pages.
  final bool student;

  static AdvSupportLink? parse(Map<String, dynamic> data, {String? module, String? kind}) {
    final inner = data['data'];
    final m = {if (inner is Map) ...asMap(inner), ...data};
    var k = _text(m['kind']) ?? kind;
    if (module == 'org_adv_request') k = 'request';
    if (module == 'org_adv_plan') k = 'plan';
    if (k == null || !const {'request', 'plan', 'accommodation'}.contains(k)) return null;
    final link = AdvSupportLink(
      kind: k,
      requestId: _id(m['request_id'] ?? (k == 'request' ? m['target_id'] ?? m['id'] : null)),
      planId: _id(m['plan_id'] ?? (k == 'plan' ? m['target_id'] ?? m['id'] : null)),
      accommodationId: _id(m['accommodation_id']),
      memberId: _id(m['member_id']),
      student: _text(m['audience']) == 'student',
    );
    if (k == 'request' && link.requestId == null) return null;
    return link;
  }
}
