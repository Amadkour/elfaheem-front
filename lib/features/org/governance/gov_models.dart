// lib/features/org/governance/gov_models.dart — pure models of the governance module (requests · complaints ·
// forms · routing · delegation · councils · Export Hub templates). No Flutter widgets: unit-tested in
// test/org/gov_models_test.dart. Contract: docs/backend/governance-spec.md (D-057); backend
// ../back/services/organization/governance/.
//
// Every model is built from the server JSON with `fromJson` and keeps the raw map in `raw` for fields a screen
// needs occasionally. Labels are bilingual through `t(ar, en)` (admin_common.dart), like every org screen.
library;

import 'dart:math' as math;

import '../../admin/admin_common.dart' show asBool, asDouble, asInt, asMap, asMapList, t;
import '../org_v3.dart' show orgParseUtc, orgUtc;

// ═════════════════════════════════════════════════════════════════════════════
//  Vocabularies + labels
// ═════════════════════════════════════════════════════════════════════════════

const entityKinds = ['service', 'scientific', 'council', 'office', 'custom'];
const itemTypes = ['complaint', 'request', 'form', 'memo', 'agenda', 'custom'];
const itemStatuses = ['draft', 'open', 'in_review', 'pending_approval', 'in_council', 'approved', 'rejected', 'postponed', 'closed', 'withdrawn'];
const openStatuses = ['open', 'in_review', 'pending_approval', 'in_council', 'postponed'];
const decidableStatuses = ['open', 'in_review', 'pending_approval'];
const priorities = ['low', 'medium', 'high', 'urgent'];
const routeActions = ['info', 'review', 'approval', 'vote'];
const routeAnswers = ['noted', 'reviewed', 'approved', 'rejected', 'voted', 'abstained', 'executed'];

/// Forwarding an APPROVED item (D-890): where it goes, what the person must do, and the answers each action takes
/// (mirrors `FORWARD_ANSWERS` on the server).
const forwardKinds = ['council', 'external', 'user'];
const forwardActions = ['info', 'review', 'approval', 'vote', 'execute'];
const forwardAnswers = {
  'info': ['noted'],
  'review': ['reviewed'],
  'approval': ['approved', 'rejected'],
  'vote': ['approved', 'rejected', 'abstained'],
  'execute': ['executed'],
};

/// Where an outside request received by a department goes on its own (D-891).
const externalRoutings = ['department_council', 'faculty_council'];
const delegationModes = ['global', 'scoped'];
const councilLevels = ['department', 'faculty'];
const tieRules = ['reject', 'chair', 'postpone'];
const noVoteRules = ['ignore', 'abstain'];
const holidayRules = ['next_day', 'next_week'];
const sessionKinds = ['regular', 'extraordinary'];
const sessionStatuses = ['draft', 'published', 'voting', 'closed', 'cancelled'];
const agendaStatuses = ['pending', 'voting', 'approved', 'rejected', 'tied', 'no_quorum', 'postponed', 'withdrawn'];
const voteValues = ['approve', 'reject', 'abstain'];
const voteOutcomes = ['approved', 'rejected', 'tied', 'no_quorum', 'postponed'];

String entityKindLabel(String k) =>
    {
      'service': t('إدارة خدمية', 'Service department'),
      'scientific': t('قسم علمي', 'Scientific department'),
      'council': t('مجلس', 'Council'),
      'office': t('مكتب', 'Office'),
      'custom': t('وحدة', 'Unit'),
    }[k] ??
    k;

String itemTypeLabel(String v) =>
    {
      'complaint': t('شكوى', 'Complaint'),
      'request': t('طلب', 'Request'),
      'form': t('نموذج', 'Form'),
      'memo': t('مذكرة', 'Memo'),
      'agenda': t('بند مجلس', 'Agenda item'),
      'custom': t('معاملة', 'Item'),
    }[v] ??
    v;

String itemStatusLabel(String v) =>
    {
      'draft': t('مسودة', 'Draft'),
      'open': t('مفتوح', 'Open'),
      'in_review': t('قيد المراجعة', 'In review'),
      'pending_approval': t('بانتظار الاعتماد', 'Pending approval'),
      'in_council': t('أمام المجلس', 'In council'),
      'approved': t('معتمد', 'Approved'),
      'rejected': t('مرفوض', 'Rejected'),
      'postponed': t('مؤجّل', 'Postponed'),
      'closed': t('مغلق', 'Closed'),
      'withdrawn': t('مسحوب', 'Withdrawn'),
    }[v] ??
    v;

String priorityLabelOf(String v) =>
    {'low': t('منخفضة', 'Low'), 'medium': t('متوسطة', 'Medium'), 'high': t('عالية', 'High'), 'urgent': t('عاجلة', 'Urgent')}[v] ?? v;

String routeActionLabel(String v) =>
    {
      'info': t('للعلم', 'For information'),
      'review': t('للمراجعة', 'For review'),
      'approval': t('للاعتماد', 'For approval'),
      'vote': t('للتصويت', 'For voting'),
      'execute': t('للتنفيذ', 'For execution'),
    }[v] ??
    v;

String forwardActionLabel(String v) =>
    {
      'info': t('للعلم فقط', 'For information only'),
      'review': t('مراجعة وتعليق', 'Review and comment'),
      'approval': t('اعتماد', 'Approve'),
      'vote': t('تصويت', 'Vote'),
      'execute': t('تنفيذ', 'Execute'),
    }[v] ??
    v;

String forwardKindLabel(String v) =>
    {
      'council': t('إلى مجلس أعلى', 'To a higher council'),
      'external': t('إلى جهة خارجية', 'To an outside party'),
      'user': t('إلى شخص', 'To a person'),
    }[v] ??
    v;

String externalRoutingLabel(String v) => v == 'faculty_council'
    ? t('مباشرة إلى مجلس الكلية', 'Straight to the faculty council')
    : t('إلى مجلس القسم (أو مجلس الكلية إن لم يكن للقسم مجلس)', "To the department council (the faculty council when it has none)");

String routeAnswerLabel(String v) =>
    {
      'noted': t('تم الاطلاع', 'Noted'),
      'reviewed': t('تمت المراجعة', 'Reviewed'),
      'approved': t('اعتمد', 'Approved'),
      'rejected': t('رفض', 'Rejected'),
      'voted': t('صُوِّت عليه', 'Voted'),
      'abstained': t('امتنع', 'Abstained'),
      'executed': t('نُفّذ', 'Executed'),
    }[v] ??
    v;

String routeStatusLabel(String v) =>
    {
      'pending': t('بانتظار الرد', 'Pending'),
      'answered': t('تم الرد', 'Answered'),
      'closed': t('مغلق', 'Closed'),
      'superseded': t('استُبدل', 'Superseded'),
    }[v] ??
    v;

String eventKindLabel(String v) =>
    {
      'created': t('أُنشئ', 'Created'),
      'updated': t('عُدّل', 'Updated'),
      'routed': t('أُحيل', 'Routed'),
      'forwarded': t('أُحيل بعد الاعتماد', 'Forwarded after approval'),
      'escalated': t('صُعّد', 'Escalated'),
      'assigned': t('أُسند', 'Assigned'),
      'decided': t('صدر القرار', 'Decided'),
      'locked_out': t('أُغلق أمام الآخرين', 'Locked for others'),
      'status': t('تغيّرت الحالة', 'Status changed'),
      'comment': t('تعليق', 'Comment'),
      'attachment': t('مرفق', 'Attachment'),
      'agenda': t('أُدرج في جدول أعمال', 'Put on an agenda'),
      'vote_opened': t('فُتح التصويت', 'Voting opened'),
      'vote_closed': t('أُغلق التصويت', 'Voting closed'),
      'voted': t('صوّت', 'Voted'),
      'exported': t('صُدّر', 'Exported'),
      'delegation': t('تفويض', 'Delegation'),
      'reminder': t('تذكير', 'Reminder'),
      'withdrawn': t('سُحب', 'Withdrawn'),
      'reopened': t('أُعيد فتحه', 'Reopened'),
      'conflict': t('أعلن تعارض مصالح', 'Declared a conflict of interest'),
    }[v] ??
    v;

String delegationModeLabel(String v) => v == 'global' ? t('تفويض كامل', 'Global delegation') : t('تفويض محدد', 'Scoped delegation');

String councilLevelLabel(String v) => v == 'faculty' ? t('مجلس الكلية', 'Faculty Council') : t('مجلس القسم', 'Department Council');

String tieRuleLabel(String v) =>
    {
      'reject': t('التعادل = رفض', 'Tie = rejected'),
      'chair': t('صوت الرئيس يرجّح', 'Chair decides a tie'),
      'postpone': t('التعادل = تأجيل', 'Tie = postponed'),
    }[v] ??
    v;

String noVoteRuleLabel(String v) =>
    v == 'abstain' ? t('من لم يصوّت يُعدّ ممتنعاً', 'Non-voters count as abstaining') : t('من لم يصوّت لا يُحتسب', 'Non-voters are ignored');

String holidayRuleLabel(String v) => v == 'next_week' ? t('تُنقل للأسبوع التالي', 'Moved to the next week') : t('تُنقل لليوم التالي', 'Moved to the next day');

String sessionKindLabel(String v) => v == 'extraordinary' ? t('جلسة طارئة', 'Extraordinary session') : t('جلسة دورية', 'Regular session');

String sessionStatusLabel(String v) =>
    {
      'draft': t('مسودة', 'Draft'),
      'published': t('نُشر جدول الأعمال', 'Agenda published'),
      'voting': t('التصويت مفتوح', 'Voting open'),
      'closed': t('مغلقة', 'Closed'),
      'cancelled': t('ملغاة', 'Cancelled'),
    }[v] ??
    v;

String agendaStatusLabel(String v) =>
    {
      'pending': t('بانتظار التصويت', 'Pending'),
      'voting': t('قيد التصويت', 'Voting'),
      'approved': t('موافقة', 'Approved'),
      'rejected': t('رفض', 'Rejected'),
      'tied': t('تعادل', 'Tied'),
      'no_quorum': t('لم يكتمل النصاب', 'No quorum'),
      'postponed': t('مؤجّل', 'Postponed'),
      'withdrawn': t('مسحوب', 'Withdrawn'),
    }[v] ??
    v;

String voteLabel(String v) => {'approve': t('موافق', 'Approve'), 'reject': t('غير موافق', 'Reject'), 'abstain': t('ممتنع', 'Abstain')}[v] ?? v;

String voteOutcomeLabel(String v) => agendaStatusLabel(v);

/// Server error codes of the module → bilingual text (merged into `orgErrorText`).
Map<String, String> govCodeTexts() => {
      'entity_not_found': t('الجهة غير موجودة', 'Entity not found'),
      'entity_kind_invalid': t('نوع الجهة لا يناسب هذا الإجراء', 'This entity kind does not fit the action'),
      'category_not_found': t('التصنيف غير موجود', 'Category not found'),
      'item_not_found': t('المعاملة غير موجودة', 'Item not found'),
      'item_forbidden': t('ليست لديك صلاحية على هذه المعاملة', 'You may not act on this item'),
      'already_decided': t('صدر قرار في هذه المعاملة بالفعل', 'This item has already been decided'),
      'stale_version': t('تغيّرت المعاملة — أعد التحميل', 'The item changed — reload'),
      'item_closed': t('المعاملة مغلقة', 'The item is closed'),
      'route_target_required': t('اختر جهة أو شخصاً', 'Choose an entity or a person'),
      'route_not_allowed': t('هذا المسار غير مسموح به في إعدادات المؤسسة', 'This route is not allowed by the organization rules'),
      'route_self': t('لا يمكن الإحالة إلى نفس الجهة', 'Cannot route to the same entity'),
      'not_a_decider': t('القرار لرئيس الجهة أو من فوّضه', 'Only the entity head or a delegate may decide'),
      'delegation_invalid': t('بيانات التفويض غير صالحة', 'Invalid delegation'),
      'delegation_not_found': t('التفويض غير موجود', 'Delegation not found'),
      'council_not_found': t('المجلس غير موجود', 'Council not found'),
      'council_exists': t('مجلس الكلية موجود بالفعل', 'The faculty council already exists'),
      'session_not_found': t('الجلسة غير موجودة', 'Session not found'),
      'session_state': t('حالة الجلسة لا تسمح بهذا الإجراء', 'The session state does not allow this'),
      'not_a_voter': t('التصويت لأعضاء المجلس فقط', 'Only council members may vote'),
      'own_item': t('مقدّم البند لا يصوّت عليه', 'The person who submitted an item does not vote on it'),
      'council_requests_only': t('تُعرض الطلبات على المجلس، لا الشكاوى', 'Requests go to the council, complaints do not'),
      'no_council': t('ليس لهذا القسم مجلس', 'This department has no council'),
      'voting_closed': t('أُغلق التصويت', 'Voting is closed'),
      'no_faculty_council': t('لا يوجد مجلس كلية بعد', 'There is no faculty council yet'),
      'form_not_found': t('النموذج غير موجود', 'Form not found'),
      'assignment_exists': t('النموذج مُسند لهذا الشخص بالفعل', 'The form is already assigned to this person'),
      'filter_name_taken': t('يوجد فلتر محفوظ بهذا الاسم', 'A saved filter has this name already'),
      'template_not_found': t('القالب غير موجود', 'Template not found'),
      'export_forbidden': t('تصدير نتائج التصويت يحتاج صلاحية', 'Exporting vote results needs a permission'),
      'dept_no_items': t('هذه الجهة لا تستقبل معاملات عبر التطبيق', 'This entity does not accept items through the app'),
      // D-140 / D-141: for someone else · attachments · export by ids · approval chain
      'on_behalf_forbidden': t('التقديم نيابةً عن غيرك يحتاج صلاحية في هذه الجهة', 'Filing for someone else needs a right in this entity'),
      'beneficiary_invalid': t('بيانات صاحب الطلب غير صحيحة', 'The details of the person it is for are not valid'),
      'beneficiary_not_member': t('هذا الشخص ليس عضواً فعّالاً في المؤسسة', 'This person is not an active member of the organization'),
      'beneficiary_anonymous': t('لا يُخفى اسم مقدّم طلب نيابةً عن غيره', 'A request filed for someone else cannot be anonymous'),
      'file_type': t('نوع الملف غير مسموح (PDF، صور، مستندات Office، نص)', 'File type not allowed (PDF, images, Office documents, text)'),
      'file_too_big': t('الملف أكبر من الحد المسموح', 'The file is larger than allowed'),
      'attachment_invalid': t('المرفق غير موجود أو ليس لك', 'The attachment does not exist or is not yours'),
      'too_many_attachments': t('الحد الأقصى 10 مرفقات', 'At most 10 attachments'),
      'attachment_not_found': t('المرفق غير موجود', 'Attachment not found'),
      'storage_unavailable': t('تعذّر تجهيز رابط الملف — حاول مجدداً', 'Could not prepare the file link — try again'),
      'ids_invalid': t('اختيار المعاملات غير صالح', 'The selection is not valid'),
      'reason_required': t('اكتب سبب الرفض — يصل إلى مقدّم الطلب', 'Write the reason for rejecting — the requester will see it'),
      'chain_invalid': t('خطوات سلسلة الاعتماد غير صالحة', 'The approval chain steps are not valid'),
      // D-890 – D-893: forwarding after approval · external requests · council votes
      'not_approved': t('لا يُحال بعد القرار إلا طلب معتمد', 'Only an approved request can be forwarded'),
      'forward_target_invalid': t('اختر وجهة الإحالة', 'Choose where to forward it'),
      'forward_actions_invalid': t('اختر الإجراء المطلوب («للعلم فقط» لا يُجمع مع غيره)', 'Choose the required action ("for information only" stands alone)'),
      'forward_not_higher': t('الإحالة بعد الاعتماد تكون إلى مجلس أعلى', 'An approved request goes up to a higher council'),
      'external_name_required': t('اكتب اسم الجهة الخارجية', 'Write the name of the outside party'),
      'external_conflict': t('الطلب الخارجي يُحال تلقائياً إلى المجلس', 'An outside request is routed to its council automatically'),
      'route_action_required': t('حدد الإجراء الذي ترد عليه', 'Choose which action you are answering'),
      'route_answer_invalid': t('الرد لا يناسب الإجراء المطلوب', 'The answer does not fit the required action'),
      'route_answered': t('سبق الرد على هذا الإجراء', 'This action was already answered'),
      'comment_required': t('المراجعة تحتاج تعليقاً', 'A review needs a comment'),
      'due_in_past': t('الموعد النهائي يجب أن يكون في المستقبل', 'The deadline must be in the future'),
      'council_no_members': t('لا أعضاء في المجلس — أضفهم قبل فتح التصويت', 'The council has no members — add them before opening the vote'),
      // Institutions S2 (D-965 – D-970): roster · weights · meeting · written items · reminders · conflicts
      'weight_cap': t('لا يجوز أن يتجاوز وزن عضو واحد 40٪ من مجموع أوزان المجلس — خفّض وزنه أو ارفع أوزان غيره',
          "No member may hold more than 40% of the council's total weight — lower that weight or raise the others"),
      'weight_invalid': t('وزن العضو من 1 إلى 3', "A member's weight is 1 to 3"),
      'secretary_not_member': t('أمين المجلس يجب أن يكون من أعضائه — أضفه إلى الأعضاء أولاً أو اختر شخصاً آخر', 'The secretary must be a member of this council: add them to the members first, or choose another person'),
      'not_staff_member': t('عضو المجلس يكون من هيئة المؤسسة أو إدارييها', 'A council member must be staff of the organization'),
      'council_settings_invalid': t('أحد إعدادات المجلس غير صالح — راجع الحقول', 'One of the council settings is not valid — check the fields'),
      'remind_too_soon': t('أُرسل تذكير منذ أقل من ساعة — حاول لاحقاً', 'A reminder went out less than an hour ago — try again later'),
      'conflict_declared': t('أعلنت تعارض مصالح على هذا البند فلا تصوّت عليه', 'You declared a conflict of interest on this item, so you do not vote on it'),
      'title_required': t('عنوان البند مطلوب', 'The item needs a title'),
      'template_key_invalid': t('قالب القرار غير صالح', 'The decision template is not valid'),
      // Institutions S3 (D-971)
      'auto_rule_invalid': t('إحدى قواعد الإحالة التلقائية غير مكتملة أو غير صالحة — راجع القاعدة المظللة',
          'One automatic routing rule is incomplete or not valid — check the highlighted rule'),
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Small shared pieces
// ═════════════════════════════════════════════════════════════════════════════

class GovUser {
  const GovUser({required this.id, required this.name, this.email, this.avatar});
  final int id;
  final String name;
  final String? email, avatar;

  static GovUser? from(dynamic j) {
    if (j is! Map || j['id'] == null) return null;
    return GovUser(id: asInt(j['id']), name: '${j['name'] ?? ''}', email: j['email'] as String?, avatar: j['avatar'] as String?);
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email, 'avatar': avatar};
}

class GovDept {
  const GovDept({required this.id, this.nameAr = '', this.nameEn = '', this.kind = 'service', this.icon, this.color, this.logoUrl});
  final int id;
  final String nameAr, nameEn, kind;
  final String? icon, color, logoUrl;

  String get name {
    final ar = nameAr.isNotEmpty ? nameAr : nameEn, en = nameEn.isNotEmpty ? nameEn : nameAr;
    return t(ar, en);
  }

  static GovDept? from(dynamic j) {
    if (j is! Map || j['id'] == null) return null;
    return GovDept(
        id: asInt(j['id']),
        nameAr: '${j['name_ar'] ?? ''}',
        nameEn: '${j['name_en'] ?? ''}',
        kind: '${j['kind'] ?? 'service'}',
        icon: j['icon'] as String?,
        color: j['color'] as String?,
        logoUrl: j['logo_url'] as String?);
  }

  Map<String, dynamic> toJson() => {'id': id, 'name_ar': nameAr, 'name_en': nameEn, 'kind': kind, 'icon': icon, 'color': color, 'logo_url': logoUrl};
}

/// An attachment entry. Uploaded files (D-140) carry an [id] and no URL: the link is asked for when opening
/// (`GET …/attachments/{id}`, 10 minutes, after the item's view check). Older entries are `{name, url}`.
class GovAttachment {
  const GovAttachment({required this.name, this.url = '', this.id, this.type, this.ext, this.size, this.preview = false});
  final String name, url;
  final int? id;
  final String? type, ext;
  final int? size;

  /// An image or a PDF: opens in the in-app preview.
  final bool preview;

  bool get isFile => id != null;
  bool get isImage => const {'png', 'jpg', 'jpeg', 'webp', 'gif'}.contains((ext ?? name.split('.').last).toLowerCase());
  bool get isPdf => (ext ?? name.split('.').last).toLowerCase() == 'pdf';

  factory GovAttachment.fromJson(Map<String, dynamic> j) => GovAttachment(
        name: '${j['name'] ?? ''}',
        url: '${j['url'] ?? ''}',
        id: j['id'] == null ? null : asInt(j['id']),
        type: j['type'] as String?,
        ext: j['ext'] as String?,
        size: j['size'] == null ? null : asInt(j['size']),
        preview: asBool(j['preview']),
      );

  /// What a submit / comment / resubmit sends: an uploaded file by id, an older entry as it was.
  Map<String, dynamic> toJson() => id != null ? {'id': id} : {'name': name, 'url': url, if (type != null) 'type': type, if (size != null) 'size': size};
}

/// `can` blocks the server sends with every object.
class GovCan {
  const GovCan(this._m);
  final Map<String, dynamic> _m;
  bool operator [](String key) => _m[key] == true;
  bool get isEmpty => _m.isEmpty;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Entities · categories
// ═════════════════════════════════════════════════════════════════════════════

class Category {
  const Category({required this.id, required this.deptId, required this.key, this.nameAr = '', this.nameEn = '', this.kind = 'request', this.description, this.formId, this.isActive = true, this.order = 0, this.slaHours});
  final int id, deptId;

  /// D-972: this request type's own SLA (null = the priority's hours).
  final int? slaHours;
  final String key, nameAr, nameEn, kind;
  final String? description;
  final int? formId;
  final bool isActive;
  final int order;

  String get name => t(nameAr.isNotEmpty ? nameAr : nameEn, nameEn.isNotEmpty ? nameEn : nameAr);

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: asInt(j['id']),
        deptId: asInt(j['dept_id']),
        key: '${j['key'] ?? ''}',
        nameAr: '${j['name_ar'] ?? ''}',
        nameEn: '${j['name_en'] ?? ''}',
        kind: '${j['kind'] ?? 'request'}',
        description: j['description'] as String?,
        formId: j['form_id'] == null ? null : asInt(j['form_id']),
        isActive: asBool(j['is_active'], true),
        order: asInt(j['order']),
        slaHours: j['sla_hours'] == null ? null : asInt(j['sla_hours']),
      );
}

class EntityCounts {
  const EntityCounts({this.open = 0, this.pendingDecision = 0, this.overdue = 0});
  final int open, pendingDecision, overdue;
  factory EntityCounts.fromJson(dynamic j) {
    final m = asMap(j);
    return EntityCounts(open: asInt(m['open']), pendingDecision: asInt(m['pending_decision']), overdue: asInt(m['overdue']));
  }
}

class Entity {
  Entity({
    required this.dept,
    this.code = '',
    this.description,
    this.parentId,
    this.programId,
    this.councilId,
    this.councilLevel,
    this.councilRowId,
    this.sessionDay,
    this.features = const [],
    this.acceptsComplaints = true,
    this.isActive = true,
    this.order = 0,
    this.head,
    this.members = 0,
    this.counts = const EntityCounts(),
    this.can = const GovCan({}),
    this.categories = const [],
    this.canSubmitToCouncil = false,
    this.canSubmitForOthers = false,
    this.chain = const [],
    this.raw = const {},
  });

  final GovDept dept;
  final String code;
  final String? description;
  final int? parentId, programId, councilId, councilRowId, sessionDay;
  final String? councilLevel;
  final List<String> features;
  final bool acceptsComplaints, isActive;
  final int order;
  final GovUser? head;
  final int members;
  final EntityCounts counts;
  final GovCan can;
  final List<Category> categories;

  /// Member side: I sit on this scientific department's team, so my request may go straight to its council.
  final bool canSubmitToCouncil;

  /// Member side (D-140): I hold the "create for others" right here, so the form offers "For: a member / someone
  /// outside the system".
  final bool canSubmitForOthers;

  /// The entity's approval chain (D-141), shown on the form before sending; empty = one decision by the entity.
  final List<ChainStep> chain;
  final Map<String, dynamic> raw;

  int get id => dept.id;
  String get name => dept.name;
  String get kind => dept.kind;
  bool get isCouncil => kind == 'council';
  bool get isScientific => kind == 'scientific';

  factory Entity.fromJson(Map<String, dynamic> j) {
    final council = j['council'] is Map ? asMap(j['council']) : null;
    return Entity(
      dept: GovDept.from(j)!,
      code: '${j['code'] ?? ''}',
      description: j['description'] as String?,
      parentId: j['parent_id'] == null ? null : asInt(j['parent_id']),
      programId: j['program_id'] == null ? null : asInt(j['program_id']),
      councilId: j['council_id'] == null ? null : asInt(j['council_id']),
      councilRowId: council == null ? null : asInt(council['id']),
      councilLevel: council?['level'] as String?,
      sessionDay: council?['session_day'] == null ? null : asInt(council!['session_day']),
      features: [for (final f in (j['features'] as List? ?? const [])) '$f'],
      acceptsComplaints: asBool(j['accepts_complaints'], true),
      isActive: asBool(j['is_active'], true),
      order: asInt(j['order']),
      head: GovUser.from(j['head']),
      members: asInt(j['members']),
      canSubmitToCouncil: asBool(j['can_submit_to_council']),
      canSubmitForOthers: asBool(j['can_submit_for_others']),
      chain: [for (final s in asMapList(j['chain'])) ChainStep.fromJson(s)],
      counts: EntityCounts.fromJson(j['counts']),
      can: GovCan(asMap(j['can'])),
      categories: [for (final c in asMapList(j['categories'])) Category.fromJson(c)],
      raw: j,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Items · routes · events
// ═════════════════════════════════════════════════════════════════════════════

class Decision {
  const Decision({required this.outcome, this.by, this.at, this.note, this.via = 'head', this.sessionId});
  final String outcome; // approved | rejected | postponed
  final GovUser? by;
  final DateTime? at;
  final String? note, via;
  final int? sessionId;

  static Decision? from(dynamic j) {
    if (j is! Map || j['outcome'] == null) return null;
    return Decision(
        outcome: '${j['outcome']}',
        by: GovUser.from(j['by']),
        at: orgParseUtc(j['at']),
        note: j['note'] as String?,
        via: '${j['via'] ?? 'head'}',
        sessionId: j['session_id'] == null ? null : asInt(j['session_id']));
  }
}

/// One answer of the person an approved item was forwarded to (D-890).
class ForwardResponse {
  const ForwardResponse({required this.action, required this.answer, this.note, this.by, this.at});
  final String action, answer;
  final String? note;
  final GovUser? by;
  final DateTime? at;

  factory ForwardResponse.fromJson(Map<String, dynamic> j) => ForwardResponse(
        action: '${j['action'] ?? ''}',
        answer: '${j['answer'] ?? ''}',
        note: j['note'] as String?,
        by: GovUser.from(j['by']),
        at: orgParseUtc(j['at']),
      );
}

/// The forward block of a route (D-890): a higher council, an outside party or a person with required actions,
/// the decision it carried and the answers so far.
class RouteForward {
  const RouteForward({required this.kind, this.actions = const [], this.openActions = const [], this.external = const {}, this.decision = const {}, this.responses = const []});
  final String kind; // council | external | user
  final List<String> actions, openActions;
  final Map<String, dynamic> external, decision;
  final List<ForwardResponse> responses;

  String get externalName => [external['name'], external['organization']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');

  /// The answers the person may still give for [action] (empty when it is answered or was not asked).
  List<String> answersFor(String action) => openActions.contains(action) ? (forwardAnswers[action] ?? const []) : const [];

  static RouteForward? from(dynamic j) {
    if (j is! Map || j['kind'] == null) return null;
    final m = asMap(j);
    return RouteForward(
      kind: '${m['kind']}',
      actions: [for (final a in (m['actions'] as List? ?? const [])) '$a'],
      openActions: [for (final a in (m['open_actions'] as List? ?? const [])) '$a'],
      external: asMap(m['external']),
      decision: asMap(m['decision']),
      responses: [for (final r in asMapList(m['responses'])) ForwardResponse.fromJson(r)],
    );
  }
}

/// The outside party of an external request (D-891); [contact] only reaches the people handling it.
class ExternalSource {
  const ExternalSource({required this.name, this.organization, this.reference, this.contact, this.receivedAt});
  final String name;
  final String? organization, reference, contact;
  final DateTime? receivedAt;

  String get label => [name, organization].where((x) => x != null && x.isNotEmpty).join(' · ');

  static ExternalSource? from(dynamic j) {
    if (j is! Map || j['name'] == null) return null;
    return ExternalSource(
      name: '${j['name']}',
      organization: j['organization'] as String?,
      reference: j['reference'] as String?,
      contact: j['contact'] as String?,
      receivedAt: orgParseUtc(j['received_at']),
    );
  }
}

class WorkRoute {
  const WorkRoute({
    required this.id,
    this.parentRouteId,
    this.fromDept,
    this.fromUser,
    this.toDept,
    this.toUser,
    this.action = 'review',
    this.note,
    this.dueAt,
    this.status = 'pending',
    this.answer,
    this.answeredBy,
    this.answeredAt,
    this.answerNote,
    this.sessionId,
    this.createdAt,
    this.createdBy,
    this.forward,
  });
  final int id;
  final int? parentRouteId, sessionId;

  /// Set on a forward of an approved item (D-890).
  final RouteForward? forward;
  final GovDept? fromDept, toDept;
  final GovUser? fromUser, toUser, answeredBy, createdBy;
  final String action, status;
  final String? note, answer, answerNote;
  final DateTime? dueAt, answeredAt, createdAt;

  bool get pending => status == 'pending';
  String get targetName => toUser?.name ?? toDept?.name ?? forward?.externalName ?? '';

  /// A pending forward to [userId] that still has actions to answer.
  bool awaits(int? userId) => pending && forward?.kind == 'user' && toUser != null && toUser!.id == userId && forward!.openActions.isNotEmpty;
  String get sourceName => fromUser?.name ?? fromDept?.name ?? '';

  factory WorkRoute.fromJson(Map<String, dynamic> j) {
    final from = asMap(j['from']), to = asMap(j['to']);
    return WorkRoute(
      id: asInt(j['id']),
      parentRouteId: j['parent_route_id'] == null ? null : asInt(j['parent_route_id']),
      fromDept: GovDept.from(from['dept']),
      fromUser: GovUser.from(from['user']),
      toDept: GovDept.from(to['dept']),
      toUser: GovUser.from(to['user']),
      action: '${j['action'] ?? 'review'}',
      note: j['note'] as String?,
      dueAt: orgParseUtc(j['due_at']),
      status: '${j['status'] ?? 'pending'}',
      answer: j['answer'] as String?,
      answeredBy: GovUser.from(j['answered_by']),
      answeredAt: orgParseUtc(j['answered_at']),
      answerNote: j['answer_note'] as String?,
      sessionId: j['session_id'] == null ? null : asInt(j['session_id']),
      createdAt: orgParseUtc(j['created_at']),
      createdBy: GovUser.from(j['created_by']),
      forward: RouteForward.from(j['forward']),
    );
  }
}

class WorkEvent {
  const WorkEvent({required this.id, required this.kind, this.actor, this.body, this.internal = false, this.data = const {}, this.createdAt});
  final int id;
  final String kind;
  final GovUser? actor;
  final String? body;
  final bool internal;
  final Map<String, dynamic> data;
  final DateTime? createdAt;

  factory WorkEvent.fromJson(Map<String, dynamic> j) => WorkEvent(
        id: asInt(j['id']),
        kind: '${j['kind'] ?? ''}',
        actor: GovUser.from(j['actor']),
        body: j['body'] as String?,
        internal: asBool(j['internal']),
        data: asMap(j['data']),
        createdAt: orgParseUtc(j['created_at']),
      );
}

class AgendaRef {
  const AgendaRef({required this.sessionId, this.council, this.status = 'pending', this.approve = 0, this.reject = 0, this.abstain = 0, this.eligible = 0, this.approvePct, this.scheduledAt});
  final int sessionId;
  final GovDept? council;
  final String status;
  final int approve, reject, abstain, eligible;
  final double? approvePct;
  final DateTime? scheduledAt;

  factory AgendaRef.fromJson(Map<String, dynamic> j) => AgendaRef(
        sessionId: asInt(j['session_id']),
        council: GovDept.from(j['council']),
        status: '${j['status'] ?? 'pending'}',
        approve: asInt(j['approve_count']),
        reject: asInt(j['reject_count']),
        abstain: asInt(j['abstain_count']),
        eligible: asInt(j['eligible_count']),
        approvePct: j['approve_pct'] == null ? null : asDouble(j['approve_pct']),
        scheduledAt: orgParseUtc(j['scheduled_at']),
      );
}

class WorkItem {
  WorkItem({
    required this.id,
    required this.ref,
    required this.type,
    required this.title,
    this.body,
    this.status = 'open',
    this.priority = 'medium',
    this.category,
    this.sourceDept,
    this.sourceUser,
    this.anonymous = false,
    this.ownerDept,
    this.assignee,
    this.dueAt,
    this.decidedAt,
    this.decision,
    this.voteOutcome,
    this.attachments = const [],
    this.tags = const [],
    this.version = 0,
    this.createdAt,
    this.updatedAt,
    this.overdue = false,
    this.pendingRoute,
    this.can = const GovCan({}),
    this.payload = const {},
    this.routes = const [],
    this.events = const [],
    this.agenda = const [],
    this.complaintId,
    this.formResponseId,
    this.beneficiary,
    this.chain,
    this.chainStep,
    this.externalSource,
    this.raw = const {},
  });

  final int id;
  final String ref, type, title, status, priority;
  final String? body, voteOutcome;
  final Category? category;
  final GovDept? sourceDept, ownerDept;
  final GovUser? sourceUser, assignee;
  final bool anonymous, overdue;
  final DateTime? dueAt, decidedAt, createdAt, updatedAt;
  final Decision? decision;
  final List<GovAttachment> attachments;
  final List<String> tags;
  final int version;
  final WorkRoute? pendingRoute;
  final GovCan can;
  final Map<String, dynamic> payload;
  final List<WorkRoute> routes;
  final List<WorkEvent> events;
  final List<AgendaRef> agenda;
  final int? complaintId, formResponseId;

  /// Who the item is FOR when that is not the submitter (D-140); null = the submitter themselves.
  final Beneficiary? beneficiary;

  /// The approval chain with every step's who / when / why (detail only, D-141) and the list card's short form.
  final ItemChain? chain;
  final ChainStepBrief? chainStep;

  /// The outside party when the item is an external request (D-891).
  final ExternalSource? externalSource;
  final Map<String, dynamic> raw;

  bool get isOpen => openStatuses.contains(status);
  bool get isDecidable => decidableStatuses.contains(status);
  bool get isDecided => status == 'approved' || status == 'rejected';
  String get sourceName => anonymous ? t('مجهول', 'Anonymous') : (sourceUser?.name ?? sourceDept?.name ?? externalSource?.label ?? '');

  factory WorkItem.fromJson(Map<String, dynamic> j) {
    final src = asMap(j['source']);
    final legacy = asMap(j['legacy']);
    return WorkItem(
      id: asInt(j['id']),
      ref: '${j['ref'] ?? ''}',
      type: '${j['type'] ?? 'request'}',
      title: '${j['title'] ?? ''}',
      body: j['body'] as String?,
      status: '${j['status'] ?? 'open'}',
      priority: '${j['priority'] ?? 'medium'}',
      category: j['category'] is Map ? Category.fromJson(asMap(j['category'])) : null,
      sourceDept: GovDept.from(src['dept']),
      sourceUser: GovUser.from(src['user']),
      anonymous: asBool(src['anonymous']),
      ownerDept: GovDept.from(j['owner_dept']),
      assignee: GovUser.from(j['assignee']),
      dueAt: orgParseUtc(j['due_at']),
      decidedAt: orgParseUtc(j['decided_at']),
      decision: Decision.from(j['decision']),
      voteOutcome: j['vote_outcome'] as String?,
      attachments: [for (final a in asMapList(j['attachments'])) GovAttachment.fromJson(a)],
      tags: [for (final x in (j['tags'] as List? ?? const [])) '$x'],
      version: asInt(j['version']),
      createdAt: orgParseUtc(j['created_at']),
      updatedAt: orgParseUtc(j['updated_at']),
      overdue: asBool(j['overdue']),
      pendingRoute: j['pending_route'] is Map ? WorkRoute.fromJson(asMap(j['pending_route'])) : null,
      can: GovCan(asMap(j['can'])),
      payload: asMap(j['payload']),
      routes: [for (final r in asMapList(j['routes'])) WorkRoute.fromJson(r)],
      events: [for (final e in asMapList(j['events'])) WorkEvent.fromJson(e)],
      agenda: [for (final a in asMapList(j['agenda'])) AgendaRef.fromJson(a)],
      complaintId: legacy['complaint_id'] == null ? null : asInt(legacy['complaint_id']),
      formResponseId: legacy['form_response_id'] == null ? null : asInt(legacy['form_response_id']),
      beneficiary: Beneficiary.from(j['beneficiary']),
      chain: ItemChain.from(j['chain']),
      chainStep: ChainStepBrief.from(j['chain_step']),
      externalSource: ExternalSource.from(j['external_source']),
      raw: j,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  For whom (D-140) · approval chain (D-141)
// ═════════════════════════════════════════════════════════════════════════════

/// Who an item is FOR: another member ([user]) or a person outside the system. The contact / id fields come only
/// to the people who handle the item and to the submitter.
class Beneficiary {
  const Beneficiary({required this.kind, this.name = '', this.relation, this.user, this.phone, this.email, this.nationalId, this.studentNumber});
  final String kind; // member | external
  final String name;
  final String? relation, phone, email, nationalId, studentNumber;
  final GovUser? user;

  bool get isExternal => kind == 'external';
  bool get hasContact => [phone, email, nationalId, studentNumber].any((x) => (x ?? '').isNotEmpty);

  static Beneficiary? from(dynamic j) {
    if (j is! Map) return null;
    final m = asMap(j);
    String? s(String k) => (m[k] == null || '${m[k]}'.isEmpty) ? null : '${m[k]}';
    return Beneficiary(
      kind: '${m['kind'] ?? 'member'}',
      name: '${m['name'] ?? ''}',
      relation: s('relation'),
      user: GovUser.from(m['user']),
      phone: s('phone'),
      email: s('email'),
      nationalId: s('national_id'),
      studentNumber: s('student_number'),
    );
  }
}

/// A member returned by `GET …/{org_id}/people` (the "for a member" picker; names only).
class GovPerson {
  const GovPerson({required this.id, required this.name, this.username, this.role});
  final int id;
  final String name;
  final String? username, role;

  factory GovPerson.fromJson(Map<String, dynamic> j) =>
      GovPerson(id: asInt(j['id']), name: '${j['name'] ?? ''}', username: j['username'] as String?, role: j['role'] as String?);
}

/// What the submit form builds for `beneficiary` and validates the way the server does (beneficiary.py), so the
/// person sees the problem next to the field before sending. [kind]: self · member · external.
class BeneficiaryDraft {
  BeneficiaryDraft({this.kind = 'self', this.member, this.name = '', this.phone = '', this.email = '', this.nationalId = '', this.studentNumber = '', this.relation = ''});
  String kind;
  GovPerson? member;
  String name, phone, email, nationalId, studentNumber, relation;

  static final _arabicDigits = RegExp('[٠-٩۰-۹]');
  static String _latinDigits(String s) => s.replaceAllMapped(_arabicDigits, (m) {
        final u = m[0]!.codeUnitAt(0);
        return String.fromCharCode(48 + (u >= 0x06F0 ? u - 0x06F0 : u - 0x0660));
      });
  static String _squash(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// field → message; empty = valid. Mirrors the server: the name is required (2+ characters, a letter), every
  /// optional field is checked only when filled.
  Map<String, String> validate() {
    final out = <String, String>{};
    if (kind == 'member' && member == null) out['user_id'] = t('اختر العضو', 'Pick the member');
    if (kind == 'external') {
      final n = _squash(name);
      if (n.length < 2 || !RegExp(r'\p{L}', unicode: true).hasMatch(n) || RegExp(r'[<>{}\[\]\\/@#$%^*=+|~`]').hasMatch(n)) {
        out['name'] = t('اكتب الاسم (حرفان على الأقل)', 'Enter the name (at least 2 letters)');
      }
      final p = _latinDigits(phone.trim());
      final digits = p.replaceAll(RegExp(r'\D'), '');
      if (p.isNotEmpty && (!RegExp(r'^\+?[0-9][0-9 ()\-]{5,22}$').hasMatch(p) || digits.length < 6 || digits.length > 15)) {
        out['phone'] = t('رقم الهاتف غير صحيح', 'Invalid phone number');
      }
      final e = email.trim();
      if (e.isNotEmpty && !RegExp(r'^[^@\s]{1,64}@[^@\s]+\.[^@\s]{2,}$').hasMatch(e)) out['email'] = t('البريد غير صحيح', 'Invalid e-mail');
      final nid = _latinDigits(nationalId.replaceAll(' ', ''));
      if (nid.isNotEmpty && !RegExp(r'^[A-Za-z0-9\-]{5,20}$').hasMatch(nid)) out['national_id'] = t('رقم الهوية غير صحيح', 'Invalid national id');
      final sn = _latinDigits(studentNumber.replaceAll(' ', ''));
      if (sn.isNotEmpty && !RegExp(r'^[A-Za-z0-9/\-_.]{2,40}$').hasMatch(sn)) out['student_number'] = t('الرقم الجامعي غير صحيح', 'Invalid student number');
    }
    final r = _squash(relation);
    if (kind != 'self' && r.isNotEmpty && (r.length < 2 || r.length > 60 || RegExp(r'[<>{}\[\]\\@#$%^*=+|~`]').hasMatch(r))) {
      out['relation'] = t('الصلة غير صحيحة', 'Invalid relation');
    }
    return out;
  }

  /// The request body's `beneficiary` (null = self).
  Map<String, dynamic>? toJson() {
    if (kind == 'member' && member != null) {
      return {'kind': 'member', 'user_id': member!.id, if (_squash(relation).isNotEmpty) 'relation': _squash(relation)};
    }
    if (kind != 'external') return null;
    String? v(String s) => s.trim().isEmpty ? null : s.trim();
    return {
      'kind': 'external',
      'name': _squash(name),
      'phone': ?v(phone),
      'email': ?v(email),
      'national_id': ?v(nationalId),
      'student_number': ?v(studentNumber),
      'relation': ?v(_squash(relation)),
    };
  }
}

const chainStepKinds = ['manager', 'entity', 'council', 'faculty_council', 'student_department_council'];

String chainKindLabel(String k) => switch (k) {
      'manager' => t('مدير الجهة', 'Manager'),
      'entity' => t('جهة أخرى', 'Another entity'),
      'council' => t('مجلس القسم', 'Department council'),
      'faculty_council' => t('مجلس الكلية', 'Faculty council'),
      // D-289: the council of the beneficiary's (else the submitter's) department, resolved when the item is sent
      'student_department_council' => t('مجلس قسم صاحب الطلب', "The requester's department council"),
      _ => k,
    };

/// One step of an approval chain: the settings form (kind + dept) or an item's step with its record.
class ChainStep {
  const ChainStep({required this.kind, this.deptId, this.dept, this.labelAr = '', this.labelEn = '', this.status = 'waiting', this.by, this.at, this.note, this.via});
  final String kind;
  final int? deptId;
  final GovDept? dept;
  final String labelAr, labelEn;

  /// waiting · current · approved · rejected · skipped
  final String status;
  final GovUser? by;
  final DateTime? at;
  final String? note, via;

  String get label {
    final ar = labelAr.isNotEmpty ? labelAr : chainKindLabel(kind), en = labelEn.isNotEmpty ? labelEn : chainKindLabel(kind);
    return t(ar, en);
  }

  bool get isDone => status == 'approved' || status == 'rejected' || status == 'skipped';

  factory ChainStep.fromJson(Map<String, dynamic> j) => ChainStep(
        kind: '${j['kind'] ?? 'manager'}',
        deptId: j['dept_id'] == null ? null : asInt(j['dept_id']),
        dept: GovDept.from(j['dept']),
        labelAr: '${j['label_ar'] ?? ''}',
        labelEn: '${j['label_en'] ?? ''}',
        status: '${j['status'] ?? 'waiting'}',
        by: GovUser.from(j['by']),
        at: orgParseUtc(j['at']),
        note: (j['note'] == null || '${j['note']}'.isEmpty) ? null : '${j['note']}',
        via: j['via'] as String?,
      );

  Map<String, dynamic> toSettingsJson() => {'kind': kind, 'dept_id': ?deptId};
}

/// An item's chain: the current round's steps, the index of the current one, earlier rounds (resubmits).
class ItemChain {
  const ItemChain({this.round = 1, this.current, this.steps = const [], this.rounds = const []});
  final int round;
  final int? current;
  final List<ChainStep> steps;
  final List<(int, List<ChainStep>)> rounds;

  ChainStep? get currentStep => current != null && current! >= 0 && current! < steps.length ? steps[current!] : null;

  static ItemChain? from(dynamic j) {
    if (j is! Map) return null;
    final m = asMap(j);
    return ItemChain(
      round: asInt(m['round'], 1),
      current: m['current'] == null ? null : asInt(m['current']),
      steps: [for (final s in asMapList(m['steps'])) ChainStep.fromJson(s)],
      rounds: [
        for (final r in asMapList(m['rounds'])) (asInt(r['round'], 1), [for (final s in asMapList(r['steps'])) ChainStep.fromJson(s)]),
      ],
    );
  }
}

/// The list card's "step 2 of 3 · council".
class ChainStepBrief {
  const ChainStepBrief({required this.index, required this.count, this.kind, this.round = 1});
  final int index, count, round;
  final String? kind;

  static ChainStepBrief? from(dynamic j) {
    if (j is! Map) return null;
    final m = asMap(j);
    return ChainStepBrief(index: asInt(m['index']), count: asInt(m['count']), kind: m['kind'] as String?, round: asInt(m['round'], 1));
  }

  String get label => '${t('الخطوة', 'Step')} ${index + 1}/$count${kind == null ? '' : ' · ${chainKindLabel(kind!)}'}';
}

/// A paged list reply: `{items, total, page, size, pages, facets}`.
class GovPage<T> {
  const GovPage({required this.items, this.total = 0, this.page = 1, this.pages = 1, this.facets = const {}});
  final List<T> items;
  final int total, page, pages;
  final Map<String, dynamic> facets;

  static GovPage<T> from<T>(dynamic j, T Function(Map<String, dynamic>) parse) {
    final m = asMap(j);
    return GovPage(
        items: [for (final x in asMapList(m['items'])) parse(x)],
        total: asInt(m['total']),
        page: asInt(m['page'], 1),
        pages: asInt(m['pages'], 1),
        facets: asMap(m['facets']));
  }

  /// `facets.status.open` → 3.
  int facet(String group, String key) => asInt(asMap(facets[group])[key]);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Delegation
// ═════════════════════════════════════════════════════════════════════════════

class DelegationScope {
  const DelegationScope({this.types = const [], this.categoryIds = const [], this.formIds = const [], this.council = false});
  final List<String> types;
  final List<int> categoryIds, formIds;
  final bool council;

  bool get isEmpty => types.isEmpty && categoryIds.isEmpty && formIds.isEmpty && !council;

  factory DelegationScope.fromJson(dynamic j) {
    final m = asMap(j);
    return DelegationScope(
      types: [for (final x in (m['types'] as List? ?? const [])) '$x'],
      categoryIds: [for (final x in (m['category_ids'] as List? ?? const [])) asInt(x)],
      formIds: [for (final x in (m['form_ids'] as List? ?? const [])) asInt(x)],
      council: asBool(m['council']),
    );
  }

  Map<String, dynamic> toJson() => {'types': types, 'category_ids': categoryIds, 'form_ids': formIds, 'council': council};
}

class Delegation {
  const Delegation({
    required this.id,
    required this.deptId,
    this.from,
    required this.to,
    this.mode = 'scoped',
    this.scope = const DelegationScope(),
    this.startsAt,
    this.endsAt,
    this.revokedAt,
    this.active = true,
    this.note,
    this.createdAt,
    this.dept,
  });
  final int id, deptId;
  final GovUser? from;
  final GovUser to;
  final String mode;
  final DelegationScope scope;
  final DateTime? startsAt, endsAt, revokedAt, createdAt;
  final bool active;
  final String? note;
  final GovDept? dept;

  bool get isGlobal => mode == 'global';

  factory Delegation.fromJson(Map<String, dynamic> j) => Delegation(
        id: asInt(j['id']),
        deptId: asInt(j['dept_id']),
        from: GovUser.from(j['from']),
        to: GovUser.from(j['to']) ?? const GovUser(id: 0, name: ''),
        mode: '${j['mode'] ?? 'scoped'}',
        scope: DelegationScope.fromJson(j['scope']),
        startsAt: orgParseUtc(j['starts_at']),
        endsAt: orgParseUtc(j['ends_at']),
        revokedAt: orgParseUtc(j['revoked_at']),
        active: asBool(j['active'], true),
        note: j['note'] as String?,
        createdAt: orgParseUtc(j['created_at']),
        dept: GovDept.from(j['dept']),
      );

  /// Mirrors the server rule (`access.delegation_covers`): global covers everything; scoped covers an item when every
  /// NON-EMPTY axis matches.
  bool covers(WorkItem item) {
    if (isGlobal) return true;
    if (scope.types.isNotEmpty && !scope.types.contains(item.type)) return false;
    if (scope.categoryIds.isNotEmpty && !scope.categoryIds.contains(item.category?.id ?? 0)) return false;
    if (scope.formIds.isNotEmpty) {
      final fid = item.payload['form_id'];
      if (fid == null || !scope.formIds.contains(asInt(fid))) return false;
    }
    return true;
  }

  /// Active at [now] (`revoked_at` null, inside the dates).
  bool activeAt(DateTime now) =>
      revokedAt == null && (startsAt == null || !startsAt!.isAfter(now)) && (endsAt == null || endsAt!.isAfter(now));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Councils · sessions · agenda · votes
// ═════════════════════════════════════════════════════════════════════════════

class CouncilSettings {
  CouncilSettings({
    this.chairUserId,
    this.sessionDay,
    this.sessionTime = '10:00',
    this.cutoffDays = 2,
    this.votingDeadlineHours = 72,
    this.quorumPct = 50,
    this.majorityPct,
    this.tieRule = 'reject',
    this.abstainCounts = false,
    this.noVoteRule = 'ignore',
    this.holidays = const [],
    this.holidayRule = 'next_day',
    this.autoAgenda = true,
    this.autoAgendaTypes = const [],
    this.autoAgendaCategoryIds = const [],
    this.timezone,
    this.meetingMode,
    this.meetingLocation,
    this.meetingLink,
  });

  int? chairUserId, sessionDay;

  /// D-966: online | in_person | null (not set), with a place or an https link.
  String? meetingMode, meetingLocation, meetingLink;
  String sessionTime, tieRule, noVoteRule, holidayRule;
  int cutoffDays, votingDeadlineHours, quorumPct;

  /// D-893: null = simple majority (approve > reject); a number = approve > reject AND approve share ≥ it.
  int? majorityPct;
  bool abstainCounts, autoAgenda;
  List<String> holidays, autoAgendaTypes;
  List<int> autoAgendaCategoryIds;
  String? timezone;

  factory CouncilSettings.fromJson(Map<String, dynamic> j) {
    final rules = asMap(j['auto_agenda_rules']);
    return CouncilSettings(
      chairUserId: j['chair_user_id'] == null ? null : asInt(j['chair_user_id']),
      sessionDay: j['session_day'] == null ? null : asInt(j['session_day']),
      sessionTime: '${j['session_time'] ?? '10:00'}',
      cutoffDays: asInt(j['cutoff_days'], 2),
      votingDeadlineHours: asInt(j['voting_deadline_hours'], 72),
      quorumPct: asInt(j['quorum_pct'], 50),
      majorityPct: j['majority_pct'] == null ? null : asInt(j['majority_pct']),
      tieRule: tieRules.contains(j['tie_rule']) ? '${j['tie_rule']}' : 'reject',
      abstainCounts: asBool(j['abstain_counts']),
      noVoteRule: noVoteRules.contains(j['no_vote_rule']) ? '${j['no_vote_rule']}' : 'ignore',
      holidays: [for (final h in (j['holidays'] as List? ?? const [])) '$h'],
      holidayRule: holidayRules.contains(j['holiday_rule']) ? '${j['holiday_rule']}' : 'next_day',
      autoAgenda: asBool(j['auto_agenda'], true),
      autoAgendaTypes: [for (final x in (rules['types'] as List? ?? const [])) '$x'],
      autoAgendaCategoryIds: [for (final x in (rules['category_ids'] as List? ?? const [])) asInt(x)],
      timezone: j['timezone'] as String?,
      meetingMode: meetingModes.contains(j['meeting_mode']) ? '${j['meeting_mode']}' : null,
      meetingLocation: j['meeting_location'] as String?,
      meetingLink: j['meeting_link'] as String?,
    );
  }

  /// The whole object: the server PUT replaces every field.
  Map<String, dynamic> toJson() => {
        'chair_user_id': chairUserId,
        'session_day': sessionDay,
        'session_time': sessionTime,
        'cutoff_days': cutoffDays,
        'voting_deadline_hours': votingDeadlineHours,
        'quorum_pct': quorumPct,
        'majority_pct': majorityPct,
        'tie_rule': tieRule,
        'abstain_counts': abstainCounts,
        'no_vote_rule': noVoteRule,
        'holidays': holidays,
        'holiday_rule': holidayRule,
        'auto_agenda': autoAgenda,
        'auto_agenda_rules': {'types': autoAgendaTypes, 'category_ids': autoAgendaCategoryIds},
        'timezone': timezone,
        'meeting_mode': meetingMode,
        'meeting_location': meetingLocation,
        'meeting_link': meetingLink,
      };

  CouncilSettings copy() => CouncilSettings.fromJson(toJson());
}

class SessionBrief {
  const SessionBrief({required this.id, this.scheduledAt, this.status = 'draft', this.kind = 'regular'});
  final int id;
  final DateTime? scheduledAt;
  final String status, kind;
  static SessionBrief? from(dynamic j) {
    if (j is! Map || j['id'] == null) return null;
    return SessionBrief(id: asInt(j['id']), scheduledAt: orgParseUtc(j['scheduled_at']), status: '${j['status'] ?? 'draft'}', kind: '${j['kind'] ?? 'regular'}');
  }
}

class Council {
  const Council({required this.id, required this.dept, this.level = 'department', this.chair, this.members = 0, this.settings, this.nextSession, this.can = const GovCan({}), this.parentDept, this.raw = const {}, this.secretary, this.totalWeight});
  final int id;
  final GovDept dept;
  final String level;
  final GovUser? chair;
  final int members;
  final CouncilSettings? settings;
  final SessionBrief? nextSession;
  final GovCan can;
  final GovDept? parentDept;
  final Map<String, dynamic> raw;

  /// D-965: the council secretary (the chair's powers on this council: `can.manage`), and the sum of the weights.
  final GovUser? secretary;
  final int? totalWeight;

  String get name => dept.name;
  int? get sessionDay => settings?.sessionDay;

  factory Council.fromJson(Map<String, dynamic> j) => Council(
        id: asInt(j['id']),
        dept: GovDept.from(j['dept']) ?? GovDept(id: asInt(j['dept_id']), kind: 'council'),
        level: '${j['level'] ?? 'department'}',
        chair: GovUser.from(j['chair']),
        members: asInt(j['members']),
        settings: j['settings'] is Map ? CouncilSettings.fromJson(asMap(j['settings'])) : null,
        nextSession: SessionBrief.from(j['next_session']),
        can: GovCan(asMap(j['can'])),
        parentDept: GovDept.from(j['parent_dept']),
        raw: j,
        secretary: GovUser.from(j['secretary']),
        totalWeight: j['total_weight'] == null ? null : asInt(j['total_weight']),
      );
}

class CouncilVote {
  const CouncilVote({required this.user, required this.vote, this.note, this.at});
  final GovUser user;
  final String vote;
  final String? note;
  final DateTime? at;
  factory CouncilVote.fromJson(Map<String, dynamic> j) =>
      CouncilVote(user: GovUser.from(j['user']) ?? const GovUser(id: 0, name: ''), vote: '${j['vote'] ?? ''}', note: j['note'] as String?, at: orgParseUtc(j['at']));
}

class AgendaItem {
  const AgendaItem({
    required this.id,
    required this.order,
    required this.item,
    this.status = 'pending',
    this.approve = 0,
    this.reject = 0,
    this.abstain = 0,
    this.eligible = 0,
    this.approvePct,
    this.decidedAt,
    this.note,
    this.myVote,
    this.votes = const [],
    this.escalatedItemId,
    this.excluded = false,
    this.excludedUsers = const [],
    this.result,
    this.decisionNo,
    this.templateKey,
    this.coiCount = 0,
    this.myCoi = false,
    this.councilWritten = false,
    this.voters,
    this.nonResponders,
    this.weights,
  });
  final int id, order;
  final WorkItem item;
  final String status;
  final int approve, reject, abstain, eligible;
  final double? approvePct;
  final DateTime? decidedAt;
  final String? note, myVote;
  final List<CouncilVote> votes;
  final int? escalatedItemId;

  /// I brought this item, so I do not vote on it (the server refuses with `own_item` and leaves me out of
  /// `eligible`); [excludedUsers] names such people to managers and, after the close, to everyone.
  final bool excluded;
  final List<GovUser> excludedUsers;

  /// D-969: approved_full | approved_partial | rejected | no_quorum | pending (null = an older server).
  final String? result;

  /// D-970: "session no./item no./year", set at the close on an approved or rejected row.
  final String? decisionNo, templateKey;

  /// D-969: how many members declared a conflict of interest; [myCoi] = I did (I am excused from this row).
  final int coiCount;
  final bool myCoi;

  /// D-967: written on the agenda by the chair / secretary rather than forwarded from a request.
  final bool councilWritten;

  /// The named results (managers live, everyone after the close; null = not visible to me).
  final List<AgendaVoter>? voters, nonResponders;
  final AgendaWeights? weights;

  /// The chip of the row: postponed / withdrawn keep their own label, everything else is the D-969 result.
  String get chip => const ['postponed', 'withdrawn'].contains(status) ? status : (result ?? agendaResultOf(status, reject: reject, abstain: abstain));

  /// The names are visible to me (managers live, everyone after the close).
  bool get resultsVisible => voters != null;

  bool get decided => const ['approved', 'rejected', 'tied', 'no_quorum', 'postponed'].contains(status);
  int get voted => approve + reject + abstain;

  factory AgendaItem.fromJson(Map<String, dynamic> j) => AgendaItem(
        id: asInt(j['id']),
        order: asInt(j['order']),
        item: WorkItem.fromJson(asMap(j['item'])),
        status: '${j['status'] ?? 'pending'}',
        approve: asInt(j['approve_count']),
        reject: asInt(j['reject_count']),
        abstain: asInt(j['abstain_count']),
        eligible: asInt(j['eligible_count']),
        approvePct: j['approve_pct'] == null ? null : asDouble(j['approve_pct']),
        decidedAt: orgParseUtc(j['decided_at']),
        note: j['note'] as String?,
        myVote: j['my_vote'] as String?,
        votes: [for (final v in asMapList(j['votes'])) CouncilVote.fromJson(v)],
        escalatedItemId: j['escalated_item_id'] == null ? null : asInt(j['escalated_item_id']),
        excluded: asBool(j['excluded']),
        excludedUsers: [for (final u in asMapList(j['excluded_users'])) GovUser.from(u)!],
        result: agendaResults.contains(j['result']) ? '${j['result']}' : null,
        decisionNo: '${j['decision_no'] ?? ''}'.trim().isEmpty ? null : '${j['decision_no']}'.trim(),
        templateKey: j['template_key'] as String?,
        coiCount: asInt(j['coi_count']),
        myCoi: asBool(j['my_coi']),
        councilWritten: asBool(j['council_written']),
        voters: j['voters'] is List ? [for (final v in asMapList(j['voters'])) AgendaVoter.fromJson(v)] : null,
        nonResponders: j['non_responders'] is List ? [for (final v in asMapList(j['non_responders'])) AgendaVoter.fromJson(v)] : null,
        weights: j['weights'] is Map ? AgendaWeights.fromJson(asMap(j['weights'])) : null,
      );
}

class CouncilSession {
  const CouncilSession({
    required this.id,
    this.council,
    this.kind = 'regular',
    this.title,
    this.scheduledAt,
    this.status = 'draft',
    this.publishedAt,
    this.votingOpensAt,
    this.votingClosesAt,
    this.closedAt,
    this.eligibleCount,
    this.version = 0,
    this.agenda = const [],
    this.myVotes = const {},
    this.resultsVisible = false,
    this.minutes,
    this.notes,
    this.can = const GovCan({}),
    this.raw = const {},
    this.reviewDeadline,
    this.manualRemindedAt,
    this.meeting,
  });
  final int id;
  final Council? council;
  final String kind, status;

  /// D-966: the review deadline (it becomes `voting_closes_at` at the opening while still ahead) · D-968: the last
  /// manual "remind non-voters" · the meeting (mode, place or link, the calendar meeting).
  final DateTime? reviewDeadline, manualRemindedAt;
  final SessionMeeting? meeting;
  final String? title, notes;
  final DateTime? scheduledAt, publishedAt, votingOpensAt, votingClosesAt, closedAt;
  final int? eligibleCount;
  final int version;
  final List<AgendaItem> agenda;
  final Map<int, String> myVotes;
  final bool resultsVisible;
  final Map<String, dynamic>? minutes;
  final GovCan can;
  final Map<String, dynamic> raw;

  bool get isVoting => status == 'voting';
  bool get isClosed => status == 'closed';
  int get pendingMyVotes => isVoting ? agenda.where((a) => a.status == 'voting' && a.myVote == null && !a.excluded).length : 0;

  factory CouncilSession.fromJson(Map<String, dynamic> j) => CouncilSession(
        id: asInt(j['id']),
        council: j['council'] is Map ? Council.fromJson(asMap(j['council'])) : null,
        kind: '${j['kind'] ?? 'regular'}',
        title: j['title'] as String?,
        scheduledAt: orgParseUtc(j['scheduled_at']),
        status: '${j['status'] ?? 'draft'}',
        publishedAt: orgParseUtc(j['published_at']),
        votingOpensAt: orgParseUtc(j['voting_opens_at']),
        votingClosesAt: orgParseUtc(j['voting_closes_at']),
        closedAt: orgParseUtc(j['closed_at']),
        eligibleCount: j['eligible_count'] == null ? null : asInt(j['eligible_count']),
        version: asInt(j['version']),
        agenda: [for (final a in asMapList(j['agenda'])) AgendaItem.fromJson(a)],
        myVotes: {for (final e in asMap(j['my_votes']).entries) asInt(e.key): '${e.value}'},
        resultsVisible: asBool(j['results_visible']),
        minutes: j['minutes'] is Map ? asMap(j['minutes']) : null,
        notes: j['notes'] as String?,
        can: GovCan(asMap(j['can'])),
        raw: j,
        reviewDeadline: orgParseUtc(j['review_deadline']),
        manualRemindedAt: orgParseUtc(j['manual_reminded_at']),
        meeting: j['meeting'] is Map ? SessionMeeting.fromJson(asMap(j['meeting'])) : null,
      );
}

/// The tally rules, mirrored from `councils.tally` so previews and tests agree with the server.
class VoteTally {
  const VoteTally({required this.approve, required this.reject, required this.abstain, required this.eligible, required this.outcome, required this.approvePct, required this.quorumMet, required this.needed});
  final int approve, reject, abstain, eligible, needed;
  final String outcome; // approved | rejected | tied | no_quorum
  final double approvePct;
  final bool quorumMet;

  /// [chairVote] is the chair's own vote (approve | reject | null) for `tie_rule: chair`.
  static VoteTally compute({
    required int approve,
    required int reject,
    required int abstain,
    required int eligible,
    required CouncilSettings s,
    String? chairVote,
  }) {
    final voted = approve + reject + abstain;
    // at least one vote, ever: nobody voting is no quorum, never a decision by default (D-892)
    final needed = math.max(1, (eligible * s.quorumPct / 100).ceil());
    final quorum = eligible == 0 ? false : voted >= needed;
    var denominator = approve + reject;
    if (s.abstainCounts) denominator += abstain;
    if (s.noVoteRule == 'abstain') denominator += math.max(0, eligible - voted);
    final pct = denominator == 0 ? 0.0 : approve / denominator * 100;
    String outcome;
    if (!quorum) {
      outcome = 'no_quorum';
    } else if (approve > reject) {
      outcome = s.majorityPct == null || pct >= s.majorityPct! ? 'approved' : 'rejected';
    } else if (reject > approve) {
      outcome = 'rejected';
    } else {
      outcome = switch (s.tieRule) {
        'chair' => chairVote == 'approve' ? 'approved' : 'rejected',
        'postpone' => 'postponed',
        _ => 'rejected',
      };
    }
    return VoteTally(approve: approve, reject: reject, abstain: abstain, eligible: eligible, outcome: outcome, approvePct: pct, quorumMet: quorum, needed: needed);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Institutions S2 (D-965 – D-970): roster · weights · meeting · named results · reminders
// ═════════════════════════════════════════════════════════════════════════════

const meetingModes = ['online', 'in_person'];
const agendaResults = ['approved_full', 'approved_partial', 'rejected', 'no_quorum', 'pending'];

/// The status chip of one agenda row (D-969).
String agendaResultLabel(String v) =>
    {
      'approved_full': t('موافقة بالإجماع', 'Approved unanimously'),
      'approved_partial': t('موافقة بالأغلبية', 'Approved by majority'),
      'rejected': t('رفض', 'Rejected'),
      'no_quorum': t('لم يكتمل النصاب', 'No quorum'),
      'pending': t('قيد التصويت', 'Voting pending'),
    }[v] ??
    agendaStatusLabel(v);

/// The D-969 result of a row from an older server that sends no `result` (the server's `result_status`).
String agendaResultOf(String status, {int reject = 0, int abstain = 0}) => switch (status) {
      'approved' => reject == 0 && abstain == 0 ? 'approved_full' : 'approved_partial',
      'rejected' || 'no_quorum' => status,
      _ => 'pending',
    };

String meetingModeLabel(String? v) => switch (v) {
      'online' => t('عن بُعد (اجتماع إلكتروني)', 'Online'),
      'in_person' => t('حضورياً', 'In person'),
      _ => t('غير محدد', 'Not set'),
    };

/// One name of the results: a voter (with [vote]) or a member who did not respond ([vote] null).
class AgendaVoter {
  const AgendaVoter({required this.userId, required this.name, this.user, this.vote, this.weight = 1, this.note, this.at});
  final int userId;
  final String name;
  final GovUser? user;
  final String? vote, note;
  final int weight;
  final DateTime? at;

  factory AgendaVoter.fromJson(Map<String, dynamic> j) {
    final user = GovUser.from(j['user']);
    final name = '${j['name'] ?? ''}'.trim();
    return AgendaVoter(
      userId: asInt(j['user_id'] ?? user?.id),
      name: name.isNotEmpty ? name : (user?.name ?? ''),
      user: user,
      vote: j['vote'] as String?,
      weight: math.max(1, asInt(j['weight'], 1)),
      note: '${j['note'] ?? ''}'.trim().isEmpty ? null : '${j['note']}'.trim(),
      at: orgParseUtc(j['at']),
    );
  }
}

/// The weighted sums of a row (D-969). [neededW] is null while the vote is live.
class AgendaWeights {
  const AgendaWeights({this.approveW = 0, this.rejectW = 0, this.abstainW = 0, this.eligibleW = 0, this.votedW = 0, this.neededW});
  final int approveW, rejectW, abstainW, eligibleW, votedW;
  final int? neededW;

  factory AgendaWeights.fromJson(Map<String, dynamic> j) => AgendaWeights(
        approveW: asInt(j['approve_w']),
        rejectW: asInt(j['reject_w']),
        abstainW: asInt(j['abstain_w']),
        eligibleW: asInt(j['eligible_w']),
        votedW: asInt(j['voted_w']),
        neededW: j['needed_w'] == null ? null : asInt(j['needed_w']),
      );
}

/// The three groups of the results sheet (+ abstentions when any).
class AgendaResultGroups {
  const AgendaResultGroups({this.approved = const [], this.rejected = const [], this.abstained = const [], this.notResponded = const []});
  final List<AgendaVoter> approved, rejected, abstained, notResponded;

  factory AgendaResultGroups.of(AgendaItem a) {
    final v = a.voters ?? const <AgendaVoter>[];
    return AgendaResultGroups(
      approved: [for (final x in v) if (x.vote == 'approve') x],
      rejected: [for (final x in v) if (x.vote == 'reject') x],
      abstained: [for (final x in v) if (x.vote == 'abstain') x],
      notResponded: a.nonResponders ?? const [],
    );
  }

  bool get isEmpty => approved.isEmpty && rejected.isEmpty && abstained.isEmpty && notResponded.isEmpty;
}

/// The meeting of a session (D-966): the council's setup plus the calendar meeting it created.
class SessionMeeting {
  const SessionMeeting({this.mode, this.location, this.link, this.calMeetingId, this.room = false});
  final String? mode, location, link;
  final int? calMeetingId;

  /// The platform's meeting room (online without a link of its own).
  final bool room;

  factory SessionMeeting.fromJson(Map<String, dynamic> j) => SessionMeeting(
        mode: meetingModes.contains(j['mode']) ? '${j['mode']}' : null,
        location: '${j['location'] ?? ''}'.trim().isEmpty ? null : '${j['location']}'.trim(),
        link: '${j['link'] ?? ''}'.trim().isEmpty ? null : '${j['link']}'.trim(),
        calMeetingId: j['cal_meeting_id'] == null ? null : asInt(j['cal_meeting_id']),
        room: asBool(j['room']),
      );

  /// "In person · Hall 3" · "Online · https://…" · "Online · the platform's meeting room".
  String get text {
    if (mode == null) return '';
    final where = mode == 'in_person'
        ? (location ?? '')
        : (link ?? (room ? t('غرفة اجتماعات المنصة (في التقويم)', "The platform's meeting room (in the calendar)") : ''));
    return [meetingModeLabel(mode), if (where.isNotEmpty) where].join(' · ');
  }
}

/// One member of the council roster (`GET …/councils/{cid}/members`).
class RosterMember {
  const RosterMember({required this.userId, required this.name, this.user, this.weight = 1, this.isHead = false, this.isChair = false, this.isSecretary = false, this.title});
  final int userId;
  final String name;
  final GovUser? user;
  final int weight;
  final bool isHead, isChair, isSecretary;
  final String? title;

  factory RosterMember.fromJson(Map<String, dynamic> j) {
    final user = GovUser.from(j['user']);
    return RosterMember(
      userId: asInt(j['user_id'] ?? user?.id),
      name: user?.name ?? '',
      user: user,
      weight: asInt(j['weight'], 1).clamp(1, 3),
      isHead: asBool(j['is_head']),
      isChair: asBool(j['is_chair']),
      isSecretary: asBool(j['is_secretary']),
      title: '${j['title'] ?? ''}'.trim().isEmpty ? null : '${j['title']}'.trim(),
    );
  }
}

class CouncilRoster {
  const CouncilRoster({required this.councilId, this.members = const [], this.totalWeight = 0, this.capPct = 40, this.secretaryUserId, this.chairUserId, this.canEdit = false, this.secretaryActing = false});
  final int councilId;
  final List<RosterMember> members;
  final int totalWeight, capPct;
  final int? secretaryUserId, chairUserId;

  /// Institutions v2 (D-982): no secretary is set, so the chair acts as secretary (`secretary_acting`).
  final bool secretaryActing;

  /// `can.roster`: the org admin (faculty council) or the department's head; never the secretary.
  final bool canEdit;

  factory CouncilRoster.fromJson(Map<String, dynamic> j) => CouncilRoster(
        councilId: asInt(j['council_id']),
        members: [for (final m in asMapList(j['items'])) RosterMember.fromJson(m)],
        totalWeight: asInt(j['total_weight']),
        capPct: asInt(j['cap_pct'], 40),
        secretaryUserId: j['secretary_user_id'] == null ? null : asInt(j['secretary_user_id']),
        chairUserId: j['chair_user_id'] == null ? null : asInt(j['chair_user_id']),
        canEdit: asBool(asMap(j['can'])['roster']),
        secretaryActing: asBool(j['secretary_acting']),
      );
}

/// The member whose weight breaks the cap (the server's `check_weights`): once any weight is not 1, nobody may hold
/// more than [capPct] % of the total. Equal weights are never capped. null = the weights are fine.
int? weightCapUser(Map<int, int> weights, {int capPct = 40}) {
  if (weights.isEmpty) return null;
  final total = weights.values.fold<int>(0, (a, b) => a + b);
  if (total == 0 || weights.values.every((w) => w == 1)) return null;
  final top = weights.entries.reduce((a, b) => b.value > a.value ? b : a);
  return top.value * 100 > capPct * total ? top.key : null;
}

/// The PUT body of the roster (D-965): [weights] only when they changed (the list replaces the team), the secretary
/// always (null clears it).
Map<String, dynamic> rosterBody({Map<int, int>? weights, required int? secretaryUserId}) => {
      if (weights != null) 'members': [for (final e in weights.entries) {'user_id': e.key, 'weight': e.value}],
      'secretary_user_id': secretaryUserId,
    };

/// The body of the one-tap fix of 422 `secretary_not_member` (fix_action `add_member`, UX v3): every member at
/// their weight ([weights] = the edited ones, else the roster's) plus [userId] at weight 1, the secretary as picked.
Map<String, dynamic> rosterAddMemberBody(CouncilRoster r, {Map<int, int>? weights, required int userId, required int? secretaryUserId}) {
  final w = {...(weights ?? {for (final m in r.members) m.userId: m.weight})};
  w.putIfAbsent(userId, () => 1);
  return rosterBody(weights: w, secretaryUserId: secretaryUserId);
}

/// The user the `add_member` fix adds: the server's `user_id`, else the secretary that was sent.
int? rosterFixUserId(Map<String, dynamic> detail, int? sentSecretary) {
  final v = int.tryParse('${detail['user_id'] ?? ''}');
  return v ?? sentSecretary;
}

/// The server offers (or, an older server, implies) the "add as member" fix.
bool rosterCanAddMemberFix(String? code, String? fixAction) => fixAction == 'add_member' || code == 'secretary_not_member';

/// How long until the manual reminder may be sent again (once an hour, D-968); null = now.
Duration? remindWait(DateTime? lastAt, {DateTime? now}) {
  if (lastAt == null) return null;
  final left = lastAt.add(const Duration(hours: 1)).difference(now ?? DateTime.now());
  return left.isNegative || left == Duration.zero ? null : left;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Saved filters · form assignments · export templates
// ═════════════════════════════════════════════════════════════════════════════

class SavedFilter {
  const SavedFilter({required this.id, required this.name, required this.scope, required this.query});
  final int id;
  final String name, scope;
  final Map<String, dynamic> query;
  factory SavedFilter.fromJson(Map<String, dynamic> j) => SavedFilter(id: asInt(j['id']), name: '${j['name'] ?? ''}', scope: '${j['scope'] ?? 'items'}', query: asMap(j['query']));
}

class FormAssignment {
  const FormAssignment({required this.user, this.status = 'pending', this.dueAt, this.responseId, this.remindedAt, this.remindCount = 0, this.formId, this.formTitle, this.orgId, this.id});
  final GovUser user;
  final String status;
  final DateTime? dueAt, remindedAt;
  final int? responseId, formId, orgId;

  /// The assignment row (a `org_form_assignment` link names it, UX v3 phase 2).
  final int? id;
  final int remindCount;
  final String? formTitle;
  bool get overdue => status == 'pending' && dueAt != null && dueAt!.isBefore(DateTime.now());
  factory FormAssignment.fromJson(Map<String, dynamic> j) => FormAssignment(
        user: GovUser.from(j['user']) ?? const GovUser(id: 0, name: ''),
        status: '${j['status'] ?? 'pending'}',
        dueAt: orgParseUtc(j['due_at']),
        responseId: j['response_id'] == null ? null : asInt(j['response_id']),
        remindedAt: orgParseUtc(j['reminded_at']),
        remindCount: asInt(j['remind_count']),
        formId: j['form_id'] == null ? null : asInt(j['form_id']),
        formTitle: j['form_title'] as String?,
        orgId: j['org_id'] == null ? null : asInt(j['org_id']),
        id: j['id'] == null ? null : asInt(j['id']),
      );
}

class ExportTemplate {
  const ExportTemplate({required this.id, this.deptId, required this.module, required this.lang, required this.name, required this.design, this.isDefault = false, this.shared = false, this.createdBy, this.updatedAt});
  final int id;
  final int? deptId;
  final String module, lang, name;
  final Map<String, dynamic> design;
  final bool isDefault, shared;
  final GovUser? createdBy;
  final DateTime? updatedAt;
  factory ExportTemplate.fromJson(Map<String, dynamic> j) => ExportTemplate(
        id: asInt(j['id']),
        deptId: j['dept_id'] == null ? null : asInt(j['dept_id']),
        module: '${j['module'] ?? 'items'}',
        lang: '${j['lang'] ?? 'ar'}',
        name: '${j['name'] ?? ''}',
        design: asMap(j['design']),
        isDefault: asBool(j['is_default']),
        shared: asBool(j['shared']),
        createdBy: GovUser.from(j['created_by']),
        updatedAt: orgParseUtc(j['updated_at']),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Helpers
// ═════════════════════════════════════════════════════════════════════════════

/// Default SLA hours per priority (mirrors `SLA_HOURS`).
const slaHours = {'urgent': 24, 'high': 48, 'medium': 72, 'low': 120};

/// Body of `POST …/items/{id}/route`.
/// The body of `POST …/items/{id}/forward` (D-890).
Map<String, dynamic> forwardBody({required String to, int? councilDeptId, int? userId, Map<String, String>? external, List<String> actions = const [], String? note, DateTime? dueAt}) => {
      'to': to,
      if (to == 'council' && councilDeptId != null) 'council_dept_id': councilDeptId,
      if (to == 'user') 'user_id': userId,
      if (to == 'external') 'external': {for (final e in (external ?? const <String, String>{}).entries) if (e.value.trim().isNotEmpty) e.key: e.value.trim()},
      if (to == 'user') 'actions': actions,
      if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      if (to == 'user' && dueAt != null) 'due_at': orgUtc(dueAt),
    };

/// The checks the forward sheet runs before sending (the server runs the same, D-890). Null = fine.
String? forwardProblem({required String to, int? userId, String externalName = '', List<String> actions = const []}) {
  if (to == 'user') {
    if (userId == null) return t('اختر الشخص', 'Pick the person');
    if (actions.isEmpty) return govCodeTexts()['forward_actions_invalid'];
    if (actions.contains('info') && actions.length > 1) return govCodeTexts()['forward_actions_invalid'];
  }
  if (to == 'external' && externalName.trim().length < 2) return govCodeTexts()['external_name_required'];
  return null;
}

Map<String, dynamic> routeBody({int? toDeptId, int? toUserId, required String action, String? note, DateTime? dueAt}) => {
      'to_dept_id': ?toDeptId,
      'to_user_id': ?toUserId,
      'action': action,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (dueAt != null) 'due_at': orgUtc(dueAt),
    };

/// Body of `POST …/entities/{dept}/delegations`.
Map<String, dynamic> delegationBody({required int toUserId, required String mode, DelegationScope? scope, DateTime? startsAt, DateTime? endsAt, String? note}) => {
      'to_user_id': toUserId,
      'mode': mode,
      if (mode == 'scoped') 'scope': (scope ?? const DelegationScope()).toJson(),
      'starts_at': orgUtc(startsAt),
      'ends_at': orgUtc(endsAt),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };
