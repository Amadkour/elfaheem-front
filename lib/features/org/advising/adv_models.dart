// lib/features/org/advising/adv_models.dart — pure models of the Academic Advising module. No Flutter widgets:
// unit-tested in test/org/adv_models_test.dart (Phase 2), test/org/adv_assign_models_test.dart (Phase 3) and
// test/org/adv_case_models_test.dart (Phase 4: workspace, 360, categories, flags, notes, timeline).
// Contracts: docs/advising/PHASE2.md (status, enable / disable, member status) and docs/advising/PHASE3.md (settings,
// advisors and their profiles, conflicts, students and manual assignment, distribution, handovers); backend
// ../back/routers/organization/org_advising_router.py.
//
// Every parser is tolerant of missing keys (an older server leaves a block out): a missing flag is false, a missing
// count block is null, a missing list is empty. Labels are bilingual through `t(ar, en)` like every org screen.
library;

import 'dart:convert' show jsonEncode;

import 'package:flutter_education_app/core/plural.dart';

import '../../admin/admin_common.dart' show asBool, asInt, asMap, asMapList, asStr, t;
import '../org_registrar.dart' show termTitle;
import '../org_v3.dart' show orgDay, orgParseUtc, orgUtc;
import 'adv_appt_models.dart' show AdvCommCounts, AdvMeetings, AdvThreadCounts, advCommTimelineText;

/// Organization types that may switch advising on; a sub-organization of one of them is eligible too
/// (the server's `ADVISING_ORG_TYPES`).
const advOrgTypes = {'university', 'faculty'};

/// The department preset that marks the Academic Advising department (its head is the Advising Director).
const advDeptPreset = 'academic_advising';

/// Assignment types, in the order a student's advisors are listed.
const advAdvisorTypes = ['primary', 'co', 'support'];

String advAdvisorTypeLabel(String type) => switch (type) {
      'primary' => t('المرشد الأكاديمي', 'Academic advisor'),
      'co' => t('مرشد مشارك', 'Co-advisor'),
      'support' => t('مرشد داعم', 'Support advisor'),
      _ => t('مرشد', 'Advisor'),
    };

/// Why an organization is not eligible (`reason` of the status), in the user's language.
String advReasonText(String? reason) => switch (reason) {
      'org_type' => t('الإرشاد الأكاديمي متاح للجامعات والكليات والأقسام التابعة لها فقط.',
          'Academic advising is available to universities, faculties and the units under them only.'),
      _ => t('الإرشاد الأكاديمي غير متاح لهذه المؤسسة.', 'Academic advising is not available for this organization.'),
    };

/// A person the status names (a director, an advisor).
class AdvPerson {
  const AdvPerson({required this.userId, required this.name, this.type, this.officeLocation, this.contactNote});

  final int userId;
  final String name;

  /// The assignment type of an advisor (`primary` · `co` · `support`); null for a director.
  final String? type;

  /// What the advisor wrote on their profile (member status, Phase 3); null when empty.
  final String? officeLocation, contactNote;

  factory AdvPerson.fromJson(Map<String, dynamic> j) {
    final type = asStr(j['type']);
    return AdvPerson(
      userId: asInt(j['user_id'] ?? j['id']),
      name: asStr(j['name']).trim(),
      type: type.isEmpty ? null : type,
      officeLocation: _text(j['office_location']),
      contactNote: _text(j['contact_note']),
    );
  }

  String get typeLabel => advAdvisorTypeLabel(type ?? '');
}

/// What I am in the advising of this organization (`me`).
class AdvMe {
  const AdvMe({
    this.admin = false,
    this.director = false,
    this.advisor = false,
    this.advisees = 0,
    this.handoversPending = 0,
    this.flagsUrgent = 0,
    this.flagsOverdue = 0,
    this.comm = const AdvCommCounts(),
  });

  final bool admin, director, advisor;

  /// How many students I advise (active assignments).
  final int advisees;

  /// Handovers to me that I have not acknowledged yet (Phase 3; 0 from an older server).
  final int handoversPending;

  /// Phase 4: urgent open flags of my students · flags past their review date (0 from an older server).
  final int flagsUrgent, flagsOverdue;

  /// Phase 5: unread messages · today's appointments (zeros from an older server).
  final AdvCommCounts comm;

  factory AdvMe.fromJson(Map<String, dynamic> j) => AdvMe(
        admin: asBool(j['admin']),
        director: asBool(j['director']),
        advisor: asBool(j['advisor']),
        advisees: asInt(j['advisees']),
        handoversPending: asInt(j['handovers_pending']),
        flagsUrgent: asInt(j['flags_urgent']),
        flagsOverdue: asInt(j['flags_overdue']),
        comm: AdvCommCounts.fromJson(j),
      );

  /// The highest of my roles: `admin` · `director` · `advisor` · `none`.
  String get role => admin
      ? 'admin'
      : director
          ? 'director'
          : advisor
              ? 'advisor'
              : 'none';

  /// Sees the whole organization's advising (counts, every student).
  bool get leads => admin || director;

  String get roleLabel => switch (role) {
        'admin' => t('مدير المؤسسة', 'Organization admin'),
        'director' => t('مدير الإرشاد الأكاديمي', 'Advising director'),
        'advisor' => t('مرشد أكاديمي', 'Academic advisor'),
        _ => t('عضو', 'Member'),
      };
}

/// The organization-wide numbers (`counts`, admins and directors only).
class AdvCounts {
  const AdvCounts({this.students = 0, this.assigned = 0, this.unassigned = 0, this.advisors = 0, this.away = 0, this.over = 0});

  final int students, assigned, unassigned, advisors;

  /// Phase 3: students whose primary advisor is away · advisors over their maximum (0 from an older server).
  final int away, over;

  factory AdvCounts.fromJson(Map<String, dynamic> j) => AdvCounts(
        students: asInt(j['students']),
        assigned: asInt(j['assigned']),
        unassigned: asInt(j['unassigned']),
        advisors: asInt(j['advisors']),
        away: asInt(j['away']),
        over: asInt(j['over']),
      );

  /// Share of students with an advisor, 0 – 100 (0 with no students).
  double get coveragePct => students <= 0 ? 0 : (assigned.clamp(0, students) * 100 / students);

  /// Students per advisor, rounded (0 with no advisor).
  int get perAdvisor => advisors <= 0 ? 0 : (assigned / advisors).round();
}

/// `GET …/orgs/{id}/advising/status` (staff) — also the answer of enable / disable.
class AdvStatus {
  const AdvStatus({
    this.eligible = false,
    this.reason,
    this.enabled = false,
    this.deptId,
    this.directors = const [],
    this.me = const AdvMe(),
    this.counts,
  });

  final bool eligible;

  /// Why not eligible: `org_type` (null when eligible).
  final String? reason;
  final bool enabled;

  /// The Academic Advising department that leads it (null until enabled).
  final int? deptId;
  final List<AdvPerson> directors;
  final AdvMe me;

  /// null for an advisor / a plain staff member (the server sends counts to admins and directors only).
  final AdvCounts? counts;

  factory AdvStatus.fromJson(Map<String, dynamic> j) {
    final enabled = asBool(j['enabled']);
    final reason = asStr(j['reason']);
    final dept = j['dept_id'];
    final counts = j['counts'];
    return AdvStatus(
      // an enabled organization is eligible by definition, whatever an older answer says
      eligible: enabled || asBool(j['eligible']),
      reason: reason.isEmpty ? null : reason,
      enabled: enabled,
      deptId: dept == null ? null : asInt(dept),
      directors: [for (final d in asMapList(j['directors'])) AdvPerson.fromJson(d)],
      me: AdvMe.fromJson(asMap(j['me'])),
      counts: counts is Map ? AdvCounts.fromJson(asMap(counts)) : null,
    );
  }

  bool get canManage => me.admin;

  String get reasonText => advReasonText(reason);
}

/// `GET …/public/{id}/advising/status` (member side).
class AdvMemberStatus {
  const AdvMemberStatus({this.enabled = false, this.role = 'none', this.advisors = const []});

  final bool enabled;

  /// `student` · `advisor` · `none` (an unknown value is `none`).
  final String role;

  /// My own active advisors (only when I study there), primary first.
  final List<AdvPerson> advisors;

  factory AdvMemberStatus.fromJson(Map<String, dynamic> j) {
    final role = asStr(j['role']);
    final advisors = [for (final a in asMapList(j['advisors'])) AdvPerson.fromJson(a)]..sort((a, b) => _typeRank(a.type) - _typeRank(b.type));
    return AdvMemberStatus(
      enabled: asBool(j['enabled']),
      role: const ['student', 'advisor'].contains(role) ? role : 'none',
      advisors: advisors,
    );
  }

  bool get isStudent => role == 'student';
  bool get isAdvisor => role == 'advisor';

  /// My primary advisor, null when I have none (or I do not study there).
  AdvPerson? get primaryAdvisor => advisors.where((a) => a.type == 'primary').firstOrNull;
}

int _typeRank(String? type) {
  final i = advAdvisorTypes.indexOf(type ?? '');
  return i < 0 ? advAdvisorTypes.length : i;
}

/// A department the Academic Advising may be given to (from `GET …/departments`).
class AdvDeptOption {
  const AdvDeptOption({required this.id, required this.nameAr, required this.nameEn, this.preset, this.kind = 'service'});

  final int id;
  final String nameAr, nameEn;
  final String? preset;
  final String kind;

  factory AdvDeptOption.fromJson(Map<String, dynamic> j) {
    final preset = asStr(j['preset']);
    return AdvDeptOption(
      id: asInt(j['id']),
      nameAr: asStr(j['name_ar']).trim(),
      nameEn: asStr(j['name_en']).trim(),
      preset: preset.isEmpty ? null : preset,
      kind: asStr(j['kind'], 'service'),
    );
  }

  bool get isAdvising => preset == advDeptPreset;

  String get name {
    final ar = nameAr.isNotEmpty ? nameAr : nameEn, en = nameEn.isNotEmpty ? nameEn : nameAr;
    return t(ar, en);
  }
}

/// The departments offered when switching advising on: active service departments, the Academic Advising one(s)
/// first, then by name. Scientific departments, councils and offices never lead advising.
List<AdvDeptOption> advDeptChoices(List<Map<String, dynamic>> departments) {
  final out = [
    for (final d in departments)
      if (d['is_active'] != false && asStr(d['kind'], 'service') == 'service') AdvDeptOption.fromJson(d),
  ];
  out.sort((a, b) {
    if (a.isAdvising != b.isAdvising) return a.isAdvising ? -1 : 1;
    return a.name.compareTo(b.name);
  });
  return out;
}

/// The department picked by default: the existing Academic Advising department, else null (= create one).
int? advDefaultDept(List<AdvDeptOption> choices) => choices.where((d) => d.isAdvising).firstOrNull?.id;

/// May the selected organization offer advising at all? Walks the organization and its ancestors through the
/// switcher's flat list (`/org/mine` items: `id`, `parent_id`, `type`). false only when the whole chain up to the
/// root is known and none of it is a university or a faculty; an unknown link (an ancestor I do not manage) keeps
/// the entry, and the server answers with `eligible` anyway.
bool advMaybeEligible(List<Map<String, dynamic>> items, int? orgId) {
  if (orgId == null) return false;
  final byId = {for (final o in items) asInt(o['id']): o};
  int? id = orgId;
  final seen = <int>{};
  while (id != null && seen.add(id)) {
    final o = byId[id];
    if (o == null) return true;
    if (advOrgTypes.contains(asStr(o['type']))) return true;
    final p = o['parent_id'];
    id = p == null ? null : asInt(p);
  }
  return id != null; // a loop in the data: unknown, keep the entry
}

// ═════════════════════════════════════════════════════════════════════════════
//  Phase 3 — settings and assignment (docs/advising/PHASE3.md)
// ═════════════════════════════════════════════════════════════════════════════

String? _text(dynamic v) {
  final s = asStr(v).trim();
  return s.isEmpty || s == 'null' ? null : s;
}

List<String> _strList(dynamic v) => v is List ? [for (final x in v) if (x != null && '$x'.isNotEmpty) '$x'] : const [];

Map<String, int> _intMap(dynamic v) => {for (final e in asMap(v).entries) e.key: asInt(e.value)};

/// A list answer of the advising routes: `{"items","total","page","size","pages","facets"}`.
class AdvPage<T> {
  const AdvPage({this.items = const [], this.total = 0, this.page = 1, this.size = 25, this.pages = 1, this.facets = const {}, this.restricted = 0});

  final List<T> items;
  final int total, page, size, pages;

  /// Counts per filter value (`available` · `away` · `warn` · `over`, or `unassigned` · `away` · `locked`).
  final Map<String, int> facets;

  /// Phase 4 (flags, notes): rows the caller may not read (sensitive or private), only counted.
  final int restricted;

  factory AdvPage.fromJson(Map<String, dynamic> j, T Function(Map<String, dynamic>) item) {
    final items = [for (final m in asMapList(j['items'])) item(m)];
    final size = asInt(j['size'], 25);
    final total = j.containsKey('total') ? asInt(j['total']) : items.length;
    final pages = j.containsKey('pages') ? asInt(j['pages'], 1) : (size <= 0 ? 1 : ((total + size - 1) ~/ size));
    return AdvPage(
      items: items,
      total: total,
      page: asInt(j['page'], 1),
      size: size,
      pages: pages < 1 ? 1 : pages,
      facets: _intMap(j['facets']),
      restricted: asInt(j['restricted']),
    );
  }

  int facet(String key) => facets[key] ?? 0;
}

/// A person a Phase 3 answer names: `{"user_id","name"}`.
class AdvRef {
  const AdvRef({required this.userId, required this.name});
  final int userId;
  final String name;

  static AdvRef? maybe(dynamic v) {
    if (v is! Map) return null;
    final m = asMap(v);
    final id = asInt(m['user_id'] ?? m['id']);
    return id == 0 ? null : AdvRef(userId: id, name: asStr(m['name']).trim());
  }

  String get shown => name.isEmpty ? '#$userId' : name;
}

// ── Labels ─────────────────────────────────────────────────────────────────

String advRoleLabel(String key) => switch (key) {
      'teacher' => t('عضو هيئة التدريس', 'Faculty member'),
      'teacher_assistant' => t('الهيئة المعاونة', 'Teaching assistant'),
      _ => key,
    };

String advRankLabel(String key) => switch (key) {
      'professor' => t('أستاذ', 'Professor'),
      'associate_professor' => t('أستاذ مشارك', 'Associate professor'),
      'assistant_professor' => t('أستاذ مساعد', 'Assistant professor'),
      'lecturer' => t('مدرس', 'Lecturer'),
      'assistant_lecturer' => t('مدرس مساعد', 'Assistant lecturer'),
      'demonstrator' => t('معيد', 'Demonstrator'),
      _ => key,
    };

String advStrategyLabel(String key) => switch (key) {
      'balanced' => t('توزيع متوازن', 'Balanced'),
      'round_robin' => t('بالتناوب', 'In turn'),
      'department' => t('القسم أولاً', 'Same department first'),
      'continuity' => t('المرشد السابق أولاً', 'Previous advisor first'),
      _ => key,
    };

String advStrategyHint(String key) => switch (key) {
      'balanced' => t('الطالب للمرشد الأقل حملاً نسبةً إلى سعته', 'Each student goes to the advisor with the lowest share of their capacity'),
      'round_robin' => t('على المرشدين بالدور، ويُتخطّى من امتلأ', 'Advisors take turns; a full advisor is skipped'),
      'department' => t('مرشدو قسم الطالب أو برنامجه أولاً، ثم التوازن', 'Advisors of the student\'s department or program first, then balanced'),
      'continuity' => t('مرشد سابق للطالب له سعة أولاً، ثم التوازن', 'A previous advisor of the student with room first, then balanced'),
      _ => '',
    };

const advStrategies = ['balanced', 'round_robin', 'department', 'continuity'];
const advRoles = ['teacher', 'teacher_assistant'];
const advRanks = ['professor', 'associate_professor', 'assistant_professor', 'lecturer', 'assistant_lecturer', 'demonstrator'];

/// Availability of an advisor; `leave` · `sabbatical` · `left` are "away" inside their dates.
const advStatuses = ['available', 'leave', 'sabbatical', 'left'];

String advStatusLabel(String key) => switch (key) {
      'available' => t('متاح', 'Available'),
      'leave' => t('في إجازة', 'On leave'),
      'sabbatical' => t('إجازة تفرغ علمي', 'Sabbatical'),
      'left' => t('غادر المؤسسة', 'Left'),
      _ => key,
    };

const advConflictReasons = ['relative', 'disciplinary', 'other'];

String advConflictReasonLabel(String key) => switch (key) {
      'relative' => t('صلة قرابة', 'Relative'),
      'disciplinary' => t('قضية تأديبية', 'Disciplinary case'),
      _ => t('سبب آخر', 'Other reason'),
    };

String advSourceLabel(String key) => switch (key) {
      'auto' => t('توزيع تلقائي', 'Automatic'),
      'manual' => t('تعيين يدوي', 'Set by hand'),
      'legacy' => t('من التسجيل', 'From the registrar'),
      'handover' => t('تسليم', 'Handover'),
      _ => key,
    };

/// Why a history row ended (`adv_assignments.end_reason`, services/organization/advising/assignments.py).
String advEndReasonLabel(String key) => switch (key) {
      'replaced' => t('استُبدل', 'Replaced'),
      'cleared' => t('أُلغي الإسناد', 'Unassigned'),
      'promoted' => t('أصبح أساسياً', 'Became primary'),
      'legacy_sync' => t('تحديث من التسجيل', 'Registrar update'),
      'rebalanced' => t('موازنة الأحمال', 'Rebalanced'),
      'reassigned' => t('نقل الطلاب', 'Reassigned'),
      'removed' => t('أُزيل', 'Removed'),
      'changed' => t('تغيّر نوعه', 'Type changed'),
      _ => t('انتهى', 'Ended'),
    };

/// Why a student was handed over (`handovers.REASONS` in services/organization/advising/handovers.py).
String advHandoverReasonLabel(String key) => switch (key) {
      'reassign' => t('نقل طلاب مرشد', 'Students moved from an advisor'),
      'rebalance' => t('موازنة الأحمال', 'Load rebalancing'),
      'manual' => t('تغيير المرشد يدوياً', 'Advisor changed by hand'),
      _ => t('تغيير المرشد', 'Advisor changed'),
    };

const advModes = ['distribute', 'rebalance', 'reassign'];

String advModeLabel(String key) => switch (key) {
      'distribute' => t('توزيع الجدد', 'Distribute'),
      'rebalance' => t('موازنة الأحمال', 'Rebalance'),
      'reassign' => t('نقل طلاب مرشد', 'Reassign'),
      _ => key,
    };

String advModeHint(String key) => switch (key) {
      'distribute' => t('يحصل كل طالب بلا مرشد على مرشد. لا يُمسّ من له مرشد.',
          'Every student without an advisor gets one. Students who have an advisor keep them.'),
      'rebalance' => t('يُنقل بعض طلاب المرشدين فوق الحد إلى مرشدين لديهم سعة. المقفل واليدوي لا يتحرك.',
          'Some students of advisors over their maximum move to advisors with room. Locked and hand-set students stay.'),
      'reassign' => t('يُنقل طلاب مرشد واحد إلى مرشد تختاره أو حسب الطريقة، مع ملف تسليم لكل طالب. المقفل واليدوي لا يتحرك إلا إذا كان المرشد غائباً.',
          'One advisor\'s students move to an advisor you choose, or by the strategy, with a handover for each student. Locked and hand-set students move only when the advisor is away.'),
      _ => '',
    };

String advRunStatusLabel(String key) => switch (key) {
      'planned' => t('معاينة', 'Previewed'),
      'applied' => t('مُطبّق', 'Applied'),
      'stale' => t('قديمة', 'Out of date'),
      _ => key,
    };

/// A distribution warning `{code, count}` in words (the server's `text.WARNINGS` codes).
String advWarningText(String code, int n) {
  String count(String ar1, String ar2, String arFew, String arMany, String en1, String en) =>
      countText(n, ar1: ar1, ar2: ar2, arFew: arFew, arMany: arMany, en1: en1, en: en);

  return switch (code) {
    'no_eligible_advisor' => count(
        'طالب واحد لا يوجد له مرشد مؤهل متاح في نطاقه', 'طالبان لا يوجد لهما مرشد مؤهل متاح في نطاقهما',
        '$n طلاب لا يوجد لهم مرشد مؤهل متاح في نطاقهم', '$n طالباً لا يوجد لهم مرشد مؤهل متاح في نطاقهم',
        '1 student has no eligible advisor available in their scope', '$n students have no eligible advisor available in their scope'),
    'capacity_full' => count(
        'طالب واحد لم يُوزّع لأن المرشدين المتاحين بلغوا الحد الأقصى', 'طالبان لم يُوزّعا لأن المرشدين المتاحين بلغوا الحد الأقصى',
        '$n طلاب لم يُوزّعوا لأن المرشدين المتاحين بلغوا الحد الأقصى', '$n طالباً لم يُوزّعوا لأن المرشدين المتاحين بلغوا الحد الأقصى',
        '1 student is left out: the available advisors are full', '$n students are left out: the available advisors are full'),
    'conflict_skipped' => count(
        'طالب واحد تُرك بسبب تعارض مصالح', 'طالبان تُركا بسبب تعارض مصالح', '$n طلاب تُركوا بسبب تعارض مصالح', '$n طالباً تُركوا بسبب تعارض مصالح',
        '1 student is left out because of a conflict of interest', '$n students are left out because of a conflict of interest'),
    'forced_over_capacity' => count(
        'تعيين واحد فوق الحد الأقصى', 'تعيينان فوق الحد الأقصى', '$n تعيينات فوق الحد الأقصى', '$n تعييناً فوق الحد الأقصى',
        '1 assignment goes above the maximum', '$n assignments go above the maximum'),
    'primary_away' => count(
        'طالب واحد مرشده الحالي غائب أو غادر — انقله من «المرشدون»', 'طالبان مرشدهما الحالي غائب أو غادر — انقلهما من «المرشدون»',
        '$n طلاب مرشدوهم غائبون أو غادروا — انقلهم من «المرشدون»', '$n طالباً مرشدوهم غائبون أو غادروا — انقلهم من «المرشدون»',
        '1 student\'s advisor is away or has left — reassign them from Advisors', '$n students\' advisors are away or have left — reassign them from Advisors'),
    'advisors_warn' => count(
        'مرشد واحد سيقترب من حده الأقصى', 'مرشدان سيقتربان من حدهما الأقصى', '$n مرشدين سيقتربون من حدهم الأقصى', '$n مرشداً سيقتربون من حدهم الأقصى',
        '1 advisor will be close to their maximum', '$n advisors will be close to their maximum'),
    'advisors_over' => count(
        'مرشد واحد فوق حده الأقصى', 'مرشدان فوق حدهما الأقصى', '$n مرشدين فوق حدهم الأقصى', '$n مرشداً فوق حدهم الأقصى',
        '1 advisor is above their maximum', '$n advisors are above their maximum'),
    _ => count('ملاحظة واحدة من الخادم', 'ملاحظتان من الخادم', '$n ملاحظات من الخادم', '$n ملاحظة من الخادم', '1 note from the server', '$n notes from the server'),
  };
}

/// One choice the server offers (`{"key","label_ar","label_en"}`), with the app's own label as a fallback.
class AdvOption {
  const AdvOption({required this.key, this.labelAr = '', this.labelEn = ''});
  final String key;
  final String labelAr, labelEn;

  factory AdvOption.fromJson(Map<String, dynamic> j) =>
      AdvOption(key: asStr(j['key']), labelAr: asStr(j['label_ar']).trim(), labelEn: asStr(j['label_en']).trim());

  String label(String Function(String) fallback) {
    final s = t(labelAr, labelEn);
    if (s.isNotEmpty) return s;
    final other = labelAr.isNotEmpty ? labelAr : labelEn;
    return other.isNotEmpty ? other : fallback(key);
  }
}

/// `{"id","name"}` of a department or a program.
class AdvNamed {
  const AdvNamed({required this.id, required this.nameAr, this.nameEn = ''});
  final int id;

  /// `name` (the organization's language, usually Arabic) · `name_en` (optional).
  final String nameAr, nameEn;

  factory AdvNamed.fromJson(Map<String, dynamic> j) => AdvNamed(id: asInt(j['id']), nameAr: asStr(j['name']).trim(), nameEn: asStr(j['name_en']).trim());

  String get name => nameEn.isEmpty ? nameAr : t(nameAr.isEmpty ? nameEn : nameAr, nameEn);
}

// ── Settings ───────────────────────────────────────────────────────────────

/// The settings fields this app edits (Phase 3). Every other stored key is kept as it is on save.
const advPolicyFields = ['eligible_roles', 'eligible_ranks', 'mode', 'max_load', 'warn_pct', 'strategy', 'auto_assign'];

/// The full effective settings (`policy.AdvisingPolicy`).
class AdvPolicy {
  const AdvPolicy({
    this.eligibleRoles = const ['teacher'],
    this.eligibleRanks = const [],
    this.mode = 'single',
    this.maxLoad = 40,
    this.warnPct = 80,
    this.strategy = 'balanced',
    this.autoAssign = true,
    this.raw = const {},
  });

  final List<String> eligibleRoles;

  /// Empty = any rank.
  final List<String> eligibleRanks;

  /// `single` (one primary advisor) · `multi` (plus co / support advisors).
  final String mode;
  final int maxLoad, warnPct;
  final String strategy;
  final bool autoAssign;

  /// The whole answer (later phases' fields: digest, SLA hours, …).
  final Map<String, dynamic> raw;

  factory AdvPolicy.fromJson(Map<String, dynamic> j) {
    const d = AdvPolicy();
    final roles = _strList(j['eligible_roles']);
    final mode = asStr(j['mode']);
    final strategy = asStr(j['strategy']);
    return AdvPolicy(
      eligibleRoles: j.containsKey('eligible_roles') && roles.isNotEmpty ? roles : d.eligibleRoles,
      eligibleRanks: _strList(j['eligible_ranks']),
      mode: mode == 'multi' ? 'multi' : 'single',
      maxLoad: j.containsKey('max_load') ? asInt(j['max_load'], d.maxLoad) : d.maxLoad,
      warnPct: j.containsKey('warn_pct') ? asInt(j['warn_pct'], d.warnPct) : d.warnPct,
      strategy: strategy.isEmpty ? d.strategy : strategy,
      autoAssign: j.containsKey('auto_assign') ? asBool(j['auto_assign'], true) : d.autoAssign,
      raw: j,
    );
  }

  bool get multi => mode == 'multi';

  /// The value of one of [advPolicyFields], as it is sent.
  dynamic value(String field) => switch (field) {
        'eligible_roles' => eligibleRoles,
        'eligible_ranks' => eligibleRanks,
        'mode' => mode,
        'max_load' => maxLoad,
        'warn_pct' => warnPct,
        'strategy' => strategy,
        'auto_assign' => autoAssign,
        _ => raw[field],
      };

  /// [settings] (a partial scope row) over these values.
  AdvPolicy overlay(Map<String, dynamic> settings) => AdvPolicy.fromJson({...raw, for (final f in advPolicyFields) f: value(f), ...settings});
}

/// One scope row (`dept` · `program` · `level` · `cohort`) of the settings.
class AdvPolicyScope {
  const AdvPolicyScope(
      {required this.id, required this.scopeType, required this.scopeRef, this.labelAr = '', this.labelEn = '', this.settings = const {}, this.updatedAt});

  final int id;
  final String scopeType, scopeRef;

  /// `label` · `label_en` (optional).
  final String labelAr, labelEn;
  final Map<String, dynamic> settings;
  final DateTime? updatedAt;

  factory AdvPolicyScope.fromJson(Map<String, dynamic> j) => AdvPolicyScope(
        id: asInt(j['id']),
        scopeType: asStr(j['scope_type']),
        scopeRef: asStr(j['scope_ref']),
        labelAr: asStr(j['label']).trim(),
        labelEn: asStr(j['label_en']).trim(),
        settings: asMap(j['settings']),
        updatedAt: orgParseUtc(j['updated_at']),
      );

  String get label => labelEn.isEmpty ? labelAr : t(labelAr.isEmpty ? labelEn : labelAr, labelEn);

  /// How many of the app's fields this scope sets itself.
  int get overrides => advPolicyFields.where(settings.containsKey).length;
}

String advScopeTypeLabel(String type) => switch (type) {
      'org' => t('المؤسسة', 'Organization'),
      'dept' => t('قسم', 'Department'),
      'program' => t('برنامج', 'Program'),
      'level' => t('مستوى', 'Level'),
      'cohort' => t('دفعة', 'Cohort'),
      _ => type,
    };

const advScopeTypes = ['dept', 'program', 'level', 'cohort'];

/// The choices of the settings page (`options`).
class AdvPolicyOptions {
  const AdvPolicyOptions({
    this.roles = const [],
    this.ranks = const [],
    this.strategies = const [],
    this.depts = const [],
    this.programs = const [],
    this.levels = const [],
    this.cohorts = const [],
  });

  final List<AdvOption> roles, ranks, strategies;
  final List<AdvNamed> depts, programs;
  final List<String> levels, cohorts;

  factory AdvPolicyOptions.fromJson(Map<String, dynamic> j) {
    List<AdvOption> opts(String k, List<String> fallback) {
      final l = [for (final m in asMapList(j[k])) AdvOption.fromJson(m)].where((o) => o.key.isNotEmpty).toList();
      return l.isNotEmpty ? l : [for (final f in fallback) AdvOption(key: f)];
    }

    return AdvPolicyOptions(
      roles: opts('roles', advRoles),
      ranks: opts('ranks', advRanks),
      strategies: opts('strategies', advStrategies),
      depts: [for (final m in asMapList(j['depts'])) AdvNamed.fromJson(m)],
      programs: [for (final m in asMapList(j['programs'])) AdvNamed.fromJson(m)],
      levels: _strList(j['levels']),
      cohorts: _strList(j['cohorts']),
    );
  }

  /// The values a scope of [type] may take: (scope_ref, label).
  List<(String, String)> refs(String type) => switch (type) {
        'dept' => [for (final d in depts) ('${d.id}', d.name)],
        'program' => [for (final p in programs) ('${p.id}', p.name)],
        'level' => [for (final l in levels) (l, l)],
        'cohort' => [for (final c in cohorts) (c, c)],
        _ => const [],
      };
}

/// `GET …/advising/policy` (also the answer of PUT / DELETE).
class AdvPolicyBundle {
  const AdvPolicyBundle({
    this.effective = const AdvPolicy(),
    this.defaults = const AdvPolicy(),
    this.orgId,
    this.orgSettings = const {},
    this.orgUpdatedAt,
    this.scopes = const [],
    this.options = const AdvPolicyOptions(),
  });

  /// The organization's effective settings (its own row over its ancestors over the defaults).
  final AdvPolicy effective;
  final AdvPolicy defaults;

  /// The organization's own row (null id = never saved).
  final int? orgId;
  final Map<String, dynamic> orgSettings;
  final DateTime? orgUpdatedAt;
  final List<AdvPolicyScope> scopes;
  final AdvPolicyOptions options;

  factory AdvPolicyBundle.fromJson(Map<String, dynamic> j) {
    final org = asMap(j['org']);
    final defaults = AdvPolicy.fromJson(asMap(j['defaults']));
    final eff = asMap(j['effective']);
    return AdvPolicyBundle(
      effective: eff.isEmpty ? defaults : AdvPolicy.fromJson(eff),
      defaults: defaults,
      orgId: org['id'] == null ? null : asInt(org['id']),
      orgSettings: asMap(org['settings']),
      orgUpdatedAt: orgParseUtc(org['updated_at']),
      scopes: [for (final m in asMapList(j['scopes'])) AdvPolicyScope.fromJson(m)],
      options: AdvPolicyOptions.fromJson(asMap(j['options'])),
    );
  }

  AdvPolicyScope? scope(String type, String ref) => scopes.where((s) => s.scopeType == type && s.scopeRef == ref).firstOrNull;

  /// The stored settings of a scope (`org` → the organization's own row).
  Map<String, dynamic> settingsOf(String type, String? ref) => type == 'org' ? orgSettings : (scope(type, ref ?? '')?.settings ?? const {});

  /// What a scope inherits for its unset fields: the organization's effective settings for a dept / program / level /
  /// cohort scope; for the organization itself the effective value of a field it does not set (its parent's or the
  /// default), else the default.
  AdvPolicy inheritedFor(String type) {
    if (type != 'org') return effective;
    return AdvPolicy.fromJson({
      ...defaults.raw,
      for (final f in advPolicyFields) f: orgSettings.containsKey(f) ? defaults.value(f) : effective.value(f),
    });
  }

  /// Where an unset field of the organization comes from: `parent` (an ancestor sets it) or `default`.
  String orgInheritSource(String field) => _same(effective.value(field), defaults.value(field)) ? 'default' : 'parent';

  /// The label of a scope row: the server's, else the option's name, else the raw reference.
  String scopeLabel(String type, String ref) {
    final s = scope(type, ref);
    if (s != null && s.label.isNotEmpty) return s.label;
    for (final (r, l) in options.refs(type)) {
      if (r == ref) return l;
    }
    return ref;
  }
}

bool _same(dynamic a, dynamic b) => jsonEncode(a) == jsonEncode(b);

/// The editable settings of ONE scope. The PUT replaces that scope row's settings, so the draft starts from what is
/// stored (later phases' keys included) and only the fields the person touches change.
class AdvSettingsDraft {
  const AdvSettingsDraft({required this.scopeType, this.scopeRef, this.original = const {}, this.settings = const {}, this.fresh = false});

  factory AdvSettingsDraft.of(AdvPolicyBundle b, String type, String? ref) {
    final s = Map<String, dynamic>.from(b.settingsOf(type, ref));
    return AdvSettingsDraft(scopeType: type, scopeRef: type == 'org' ? null : ref, original: s, settings: s);
  }

  final String scopeType;
  final String? scopeRef;
  final Map<String, dynamic> original, settings;

  /// A scope row that does not exist yet (saved by the first PUT, even with nothing set).
  final bool fresh;

  bool isSet(String field) => settings.containsKey(field);

  AdvSettingsDraft set(String field, dynamic value) =>
      AdvSettingsDraft(scopeType: scopeType, scopeRef: scopeRef, original: original, settings: {...settings, field: value}, fresh: fresh);

  /// Back to inheriting [field].
  AdvSettingsDraft reset(String field) => AdvSettingsDraft(
      scopeType: scopeType, scopeRef: scopeRef, original: original, settings: {...settings}..remove(field), fresh: fresh);

  bool get dirty => fresh || !_same(_sorted(original), _sorted(settings));

  /// The values shown: the scope's own over what it inherits.
  AdvPolicy shown(AdvPolicy inherited) => inherited.overlay(settings);

  /// The PUT body (the whole scope row).
  Map<String, dynamic> toBody() => {'scope_type': scopeType, 'scope_ref': scopeRef, 'settings': settings};

  /// Why it cannot be saved (bilingual), null when it can.
  String? get error {
    final roles = settings['eligible_roles'];
    if (roles is List && roles.isEmpty) return t('اختر فئة واحدة على الأقل من أعضاء هيئة التدريس', 'Choose at least one staff group');
    final max = settings['max_load'];
    if (max != null && (asInt(max) < 1 || asInt(max) > 1000)) return t('الحد الأقصى بين 1 و1000 طالب', 'The maximum is between 1 and 1000 students');
    final warn = settings['warn_pct'];
    if (warn != null && (asInt(warn) < 1 || asInt(warn) > 100)) return t('نسبة التنبيه بين 1 و100', 'The warning share is between 1 and 100');
    return null;
  }
}

Map<String, dynamic> _sorted(Map<String, dynamic> m) => {for (final k in (m.keys.toList()..sort())) k: m[k]};

// ── Advisors ───────────────────────────────────────────────────────────────

/// One advisor of `GET …/advisors` (also `…/advisors/me` and the PUT answer).
class AdvAdvisor {
  const AdvAdvisor({
    required this.userId,
    this.name = '',
    this.rank,
    this.role = '',
    this.dept,
    this.status = 'available',
    this.statusFrom,
    this.statusUntil,
    this.away = false,
    this.eligible = true,
    this.maxLoad = 40,
    this.maxLoadOverride,
    this.load = 0,
    this.coLoad = 0,
    this.loadPct = 0,
    this.warn = false,
    this.over = false,
    this.officeLocation,
    this.contactNote,
    this.bio,
  });

  final int userId;
  final String name;
  final String? rank;
  final String role;
  final String? dept;

  /// `available` · `leave` · `sabbatical` · `left`.
  final String status;

  /// Dates of the status (date only; null = open).
  final DateTime? statusFrom, statusUntil;

  /// Away now (status inside its dates, or no live staff membership): never gets new students.
  final bool away;
  final bool eligible;
  final int maxLoad;
  final int? maxLoadOverride;

  /// Active primary assignments · co / support assignments.
  final int load, coLoad, loadPct;
  final bool warn, over;
  final String? officeLocation, contactNote, bio;

  factory AdvAdvisor.fromJson(Map<String, dynamic> j) {
    final status = asStr(j['status']);
    final max = asInt(j['max_load'], 40);
    final load = asInt(j['load']);
    final ov = j['max_load_override'];
    return AdvAdvisor(
      userId: asInt(j['user_id']),
      name: asStr(j['name']).trim(),
      rank: _text(j['rank']),
      role: asStr(j['role']),
      dept: _text(j['dept']),
      status: advStatuses.contains(status) ? status : 'available',
      statusFrom: orgParseUtc(j['status_from']),
      statusUntil: orgParseUtc(j['status_until']),
      away: asBool(j['away']),
      eligible: asBool(j['eligible'], true),
      maxLoad: max,
      maxLoadOverride: ov == null ? null : asInt(ov),
      load: load,
      coLoad: asInt(j['co_load']),
      loadPct: j.containsKey('load_pct') ? asInt(j['load_pct']) : (max <= 0 ? 0 : (load * 100 / max).round()),
      warn: asBool(j['warn']),
      over: asBool(j['over']),
      officeLocation: _text(j['office_location']),
      contactNote: _text(j['contact_note']),
      bio: _text(j['bio']),
    );
  }

  String get shown => name.isEmpty ? '#$userId' : name;

  /// "Associate professor · Computer Science" (what is known).
  String get subtitle => [if (rank != null) advRankLabel(rank!), ?dept].join(' · ');

  /// The status in words, with its end date when one is set ("On leave until 12 Jan 2027").
  String get statusText {
    final label = advStatusLabel(status);
    final until = statusUntil;
    if (status == 'available' || until == null) return label;
    return t('$label حتى ${orgDay(until)}', '$label until ${orgDay(until)}');
  }
}

/// The profile PUT (`PUT …/advisors/{user_id}`, the whole object). An advisor editing their own profile may change
/// only office, contact note and bio; the rest is sent back as it was.
class AdvProfileDraft {
  const AdvProfileDraft({
    this.status = 'available',
    this.statusFrom,
    this.statusUntil,
    this.maxLoadOverride,
    this.officeLocation = '',
    this.contactNote = '',
    this.bio = '',
  });

  factory AdvProfileDraft.of(AdvAdvisor a) => AdvProfileDraft(
        status: a.status,
        statusFrom: a.statusFrom,
        statusUntil: a.statusUntil,
        maxLoadOverride: a.maxLoadOverride,
        officeLocation: a.officeLocation ?? '',
        contactNote: a.contactNote ?? '',
        bio: a.bio ?? '',
      );

  final String status;
  final DateTime? statusFrom, statusUntil;
  final int? maxLoadOverride;
  final String officeLocation, contactNote, bio;

  AdvProfileDraft copyWith({
    String? status,
    DateTime? Function()? statusFrom,
    DateTime? Function()? statusUntil,
    int? Function()? maxLoadOverride,
    String? officeLocation,
    String? contactNote,
    String? bio,
  }) =>
      AdvProfileDraft(
        status: status ?? this.status,
        statusFrom: statusFrom == null ? this.statusFrom : statusFrom(),
        statusUntil: statusUntil == null ? this.statusUntil : statusUntil(),
        maxLoadOverride: maxLoadOverride == null ? this.maxLoadOverride : maxLoadOverride(),
        officeLocation: officeLocation ?? this.officeLocation,
        contactNote: contactNote ?? this.contactNote,
        bio: bio ?? this.bio,
      );

  /// Away statuses carry dates; `available` sends none.
  bool get dated => status != 'available';

  String? get error {
    final f = statusFrom, u = statusUntil;
    if (dated && f != null && u != null && u.isBefore(f)) return t('تاريخ النهاية قبل البداية', 'The end date is before the start date');
    final m = maxLoadOverride;
    if (m != null && (m < 1 || m > 1000)) return t('الحد الأقصى بين 1 و1000 طالب', 'The maximum is between 1 and 1000 students');
    return null;
  }

  String? _clean(String s) => s.trim().isEmpty ? null : s.trim();

  Map<String, dynamic> toJson() => {
        'status': status,
        'status_from': dated ? (statusFrom == null ? null : orgDay(statusFrom)) : null,
        'status_until': dated ? (statusUntil == null ? null : orgDay(statusUntil)) : null,
        'max_load_override': maxLoadOverride,
        'office_location': _clean(officeLocation),
        'contact_note': _clean(contactNote),
        'bio': _clean(bio),
      };
}

// ── Conflicts of interest ──────────────────────────────────────────────────

class AdvConflict {
  const AdvConflict({
    required this.id,
    required this.advisor,
    required this.memberId,
    this.studentUserId = 0,
    this.studentName = '',
    this.reason = 'other',
    this.note,
    this.createdAt,
    this.assignedNow = false,
  });

  final int id;
  final AdvRef advisor;
  final int memberId, studentUserId;
  final String studentName;

  /// `relative` · `disciplinary` · `other`.
  final String reason;
  final String? note;
  final DateTime? createdAt;

  /// That advisor advises the student right now (the app then offers to reassign).
  final bool assignedNow;

  factory AdvConflict.fromJson(Map<String, dynamic> j) {
    final st = asMap(j['student']);
    final reason = asStr(j['reason']);
    return AdvConflict(
      id: asInt(j['id']),
      advisor: AdvRef.maybe(j['advisor']) ?? const AdvRef(userId: 0, name: ''),
      memberId: asInt(st['member_id'] ?? j['member_id']),
      studentUserId: asInt(st['user_id']),
      studentName: asStr(st['name']).trim(),
      reason: advConflictReasons.contains(reason) ? reason : 'other',
      note: _text(j['note']),
      createdAt: orgParseUtc(j['created_at']),
      assignedNow: asBool(j['assigned_now']),
    );
  }
}

// ── Students and manual assignment ─────────────────────────────────────────

/// A student's primary advisor.
class AdvPrimary {
  const AdvPrimary({required this.userId, this.name = '', this.away = false, this.locked = false, this.source = '', this.since});

  final int userId;
  final String name;
  final bool away, locked;

  /// `auto` · `manual` · `legacy` · `handover`.
  final String source;
  final DateTime? since;

  factory AdvPrimary.fromJson(Map<String, dynamic> j) => AdvPrimary(
        userId: asInt(j['user_id']),
        name: asStr(j['name']).trim(),
        away: asBool(j['away']),
        locked: asBool(j['locked']),
        source: asStr(j['source']),
        since: orgParseUtc(j['since']),
      );

  String get shown => name.isEmpty ? '#$userId' : name;
}

/// A co / support advisor of a student.
class AdvOther {
  const AdvOther({required this.userId, this.name = '', this.type = 'co'});
  final int userId;
  final String name;

  /// `co` · `support`.
  final String type;

  factory AdvOther.fromJson(Map<String, dynamic> j) {
    final type = asStr(j['type']);
    return AdvOther(userId: asInt(j['user_id']), name: asStr(j['name']).trim(), type: type == 'support' ? 'support' : 'co');
  }

  Map<String, dynamic> toJson() => {'user_id': userId, 'type': type};

  String get shown => name.isEmpty ? '#$userId' : name;
}

class AdvStudent {
  const AdvStudent({
    required this.memberId,
    this.userId = 0,
    this.name = '',
    this.code,
    this.program,
    this.level,
    this.cohort,
    this.primary,
    this.others = const [],
  });

  final int memberId, userId;
  final String name;
  final String? code, program, level, cohort;
  final AdvPrimary? primary;
  final List<AdvOther> others;

  factory AdvStudent.fromJson(Map<String, dynamic> j) {
    final p = j['primary'];
    return AdvStudent(
      memberId: asInt(j['member_id']),
      userId: asInt(j['user_id']),
      name: asStr(j['name']).trim(),
      code: _text(j['code']),
      program: _text(j['program']),
      level: _text(j['level']),
      cohort: _text(j['cohort']),
      primary: p is Map && asInt(asMap(p)['user_id']) != 0 ? AdvPrimary.fromJson(asMap(p)) : null,
      others: [for (final m in asMapList(j['others'])) AdvOther.fromJson(m)],
    );
  }

  String get shown => name.isEmpty ? '#$memberId' : name;

  /// "2023001 · Computer Science · Level 2" (what is known).
  String get subtitle => [?code, ?program, ?level].join(' · ');
}

/// The manual assignment PUT (`PUT …/students/{member_id}/advisors`, the whole object).
class AdvAdvisorsDraft {
  const AdvAdvisorsDraft({this.primary, this.locked = false, this.others = const [], this.reason = '', this.force = false});

  factory AdvAdvisorsDraft.of(AdvStudent s) => AdvAdvisorsDraft(
        primary: s.primary == null ? null : AdvRef(userId: s.primary!.userId, name: s.primary!.name),
        locked: s.primary?.locked ?? false,
        others: s.others,
      );

  final AdvRef? primary;
  final bool locked;
  final List<AdvOther> others;
  final String reason;

  /// Assign above the advisor's maximum (manage only; needs a reason).
  final bool force;

  AdvAdvisorsDraft copyWith({AdvRef? Function()? primary, bool? locked, List<AdvOther>? others, String? reason, bool? force}) => AdvAdvisorsDraft(
        primary: primary == null ? this.primary : primary(),
        locked: locked ?? this.locked,
        others: others ?? this.others,
        reason: reason ?? this.reason,
        force: force ?? this.force,
      );

  /// Adds [person] as a co / support advisor (never the primary, never twice).
  AdvAdvisorsDraft addOther(AdvRef person, String type) {
    if (person.userId == primary?.userId || others.any((o) => o.userId == person.userId)) return this;
    return copyWith(others: [...others, AdvOther(userId: person.userId, name: person.name, type: type)]);
  }

  AdvAdvisorsDraft removeOther(int userId) => copyWith(others: [for (final o in others) if (o.userId != userId) o]);

  /// What changed against [s].
  bool changedFrom(AdvStudent s) =>
      primary?.userId != s.primary?.userId ||
      locked != (s.primary?.locked ?? false) ||
      !_same([for (final o in others) o.toJson()], [for (final o in s.others) o.toJson()]);

  /// Why it cannot be saved (bilingual), null when it can. [multi] = the settings allow co / support advisors (in
  /// single mode the others are dropped from the body, see [toJson]).
  String? error({required bool multi}) {
    if (force && reason.trim().isEmpty) return t('اكتب سبب تجاوز الحد الأقصى', 'Write why the maximum is exceeded');
    if (primary == null && others.isNotEmpty) return t('اختر المرشد الأساسي أولاً', 'Choose the primary advisor first');
    return null;
  }

  Map<String, dynamic> toJson({required bool multi}) => {
        'primary': primary?.userId,
        'locked': primary == null ? false : locked,
        'others': multi ? [for (final o in others) o.toJson()] : const [],
        'reason': reason.trim().isEmpty ? null : reason.trim(),
        'force_over_capacity': force,
      };
}

/// One row of `GET …/students/{member_id}/history` (newest first).
class AdvHistoryEntry {
  const AdvHistoryEntry({
    required this.userId,
    this.name = '',
    this.type = 'primary',
    this.status = 'active',
    this.source = '',
    this.locked = false,
    this.startedAt,
    this.endedAt,
    this.endReason,
    this.actor,
  });

  final int userId;
  final String name, type, status, source;
  final bool locked;
  final DateTime? startedAt, endedAt;
  final String? endReason, actor;

  factory AdvHistoryEntry.fromJson(Map<String, dynamic> j) => AdvHistoryEntry(
        userId: asInt(j['user_id']),
        name: asStr(j['name']).trim(),
        type: asStr(j['type'], 'primary'),
        status: asStr(j['status'], 'active'),
        source: asStr(j['source']),
        locked: asBool(j['locked']),
        startedAt: orgParseUtc(j['started_at']),
        endedAt: orgParseUtc(j['ended_at']),
        endReason: _text(j['end_reason']),
        actor: _text(j['actor']),
      );

  bool get active => status == 'active' && endedAt == null;
}

// ── Distribution ───────────────────────────────────────────────────────────

/// The preview body (`POST …/assign/preview`).
class AdvPlanRequest {
  const AdvPlanRequest({
    this.mode = 'distribute',
    this.strategy,
    this.deptId,
    this.programId,
    this.level,
    this.cohort,
    this.from,
    this.to,
    this.memberIds,
  });

  final String mode;

  /// null = the effective settings' strategy.
  final String? strategy;
  final int? deptId, programId;
  final String? level, cohort;

  /// Reassign: whose students move · to whom (null = by the strategy).
  final AdvRef? from, to;
  final List<int>? memberIds;

  AdvPlanRequest copyWith({
    String? mode,
    String? Function()? strategy,
    int? Function()? deptId,
    int? Function()? programId,
    String? Function()? level,
    String? Function()? cohort,
    AdvRef? Function()? from,
    AdvRef? Function()? to,
    List<int>? Function()? memberIds,
  }) =>
      AdvPlanRequest(
        mode: mode ?? this.mode,
        strategy: strategy == null ? this.strategy : strategy(),
        deptId: deptId == null ? this.deptId : deptId(),
        programId: programId == null ? this.programId : programId(),
        level: level == null ? this.level : level(),
        cohort: cohort == null ? this.cohort : cohort(),
        from: from == null ? this.from : from(),
        to: to == null ? this.to : to(),
        memberIds: memberIds == null ? this.memberIds : memberIds(),
      );

  bool get hasScope => deptId != null || programId != null || level != null || cohort != null;

  /// Reassign needs the advisor whose students move (and never the same one as the target).
  bool get ready => mode != 'reassign' || (from != null && from!.userId != to?.userId);

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'strategy': strategy,
        'scope': hasScope ? {'dept_id': deptId, 'program_id': programId, 'level': level, 'cohort': cohort} : null,
        'from_advisor_user_id': mode == 'reassign' ? from?.userId : null,
        'to_advisor_user_id': mode == 'reassign' ? to?.userId : null,
        'member_ids': mode == 'reassign' ? memberIds : null,
      };
}

class AdvPlanCounts {
  const AdvPlanCounts({
    this.students = 0,
    this.assign = 0,
    this.move = 0,
    this.unchanged = 0,
    this.lockedKept = 0,
    this.skippedConflict = 0,
    this.skippedCapacity = 0,
  });

  final int students, assign, move, unchanged, lockedKept, skippedConflict, skippedCapacity;

  factory AdvPlanCounts.fromJson(Map<String, dynamic> j) => AdvPlanCounts(
        students: asInt(j['students']),
        assign: asInt(j['assign']),
        move: asInt(j['move']),
        unchanged: asInt(j['unchanged']),
        lockedKept: asInt(j['locked_kept']),
        skippedConflict: asInt(j['skipped_conflict']),
        skippedCapacity: asInt(j['skipped_capacity']),
      );

  int get changes => assign + move;
  int get skipped => skippedConflict + skippedCapacity;
}

/// One advisor's load before → after the plan.
class AdvPlanAdvisor {
  const AdvPlanAdvisor({required this.userId, this.name = '', this.before = 0, this.after = 0, this.max = 0, this.warn = false, this.over = false});

  final int userId;
  final String name;
  final int before, after, max;
  final bool warn, over;

  factory AdvPlanAdvisor.fromJson(Map<String, dynamic> j) => AdvPlanAdvisor(
        userId: asInt(j['user_id']),
        name: asStr(j['name']).trim(),
        before: asInt(j['before']),
        after: asInt(j['after']),
        max: asInt(j['max']),
        warn: asBool(j['warn']),
        over: asBool(j['over']),
      );

  int get delta => after - before;
  String get shown => name.isEmpty ? '#$userId' : name;
}

class AdvMove {
  const AdvMove({required this.memberId, this.name = '', this.from, required this.to});
  final int memberId;
  final String name;
  final AdvRef? from;
  final AdvRef to;

  factory AdvMove.fromJson(Map<String, dynamic> j) => AdvMove(
        memberId: asInt(j['member_id']),
        name: asStr(j['name']).trim(),
        from: AdvRef.maybe(j['from']),
        to: AdvRef.maybe(j['to']) ?? const AdvRef(userId: 0, name: ''),
      );

  String get shown => name.isEmpty ? '#$memberId' : name;
}

/// The preview answer. Apply sends back [planHash]; a different plan on the server → 409 `plan_stale`.
class AdvPlan {
  const AdvPlan({
    required this.planHash,
    this.mode = 'distribute',
    this.strategy = 'balanced',
    this.counts = const AdvPlanCounts(),
    this.advisors = const [],
    this.moves = const [],
    this.movesTotal = 0,
    this.warnings = const [],
  });

  final String planHash, mode, strategy;
  final AdvPlanCounts counts;

  /// Advisors whose load changes first (largest change), then by name.
  final List<AdvPlanAdvisor> advisors;

  /// The first 200 moves; [movesTotal] counts them all.
  final List<AdvMove> moves;
  final int movesTotal;
  final List<(String, int)> warnings;

  factory AdvPlan.fromJson(Map<String, dynamic> j) {
    final advisors = [for (final m in asMapList(j['advisors'])) AdvPlanAdvisor.fromJson(m)]
      ..sort((a, b) {
        final d = b.delta.abs().compareTo(a.delta.abs());
        return d != 0 ? d : a.shown.compareTo(b.shown);
      });
    final moves = [for (final m in asMapList(j['moves'])) AdvMove.fromJson(m)];
    return AdvPlan(
      planHash: asStr(j['plan_hash']),
      mode: asStr(j['mode'], 'distribute'),
      strategy: asStr(j['strategy'], 'balanced'),
      counts: AdvPlanCounts.fromJson(asMap(j['counts'])),
      advisors: advisors,
      moves: moves,
      movesTotal: j.containsKey('moves_total') ? asInt(j['moves_total']) : moves.length,
      warnings: [
        for (final w in asMapList(j['warnings']))
          if (asStr(w['code']).isNotEmpty) (asStr(w['code']), asInt(w['count'])),
      ],
    );
  }

  /// Nothing would change: Apply is pointless.
  bool get empty => counts.changes == 0;

  /// The largest load before or after (the scale of the before → after bars, never 0).
  int get scale {
    var m = 1;
    for (final a in advisors) {
      for (final v in [a.before, a.after, a.max]) {
        if (v > m) m = v;
      }
    }
    return m;
  }
}

/// `POST …/assign/apply`.
class AdvApplyResult {
  const AdvApplyResult({this.runId = 0, this.assigned = 0, this.moved = 0, this.handovers = 0, this.notifiedStudents = 0, this.notifiedAdvisors = 0});

  final int runId, assigned, moved, handovers, notifiedStudents, notifiedAdvisors;

  factory AdvApplyResult.fromJson(Map<String, dynamic> j) => AdvApplyResult(
        runId: asInt(j['run_id']),
        assigned: asInt(j['assigned']),
        moved: asInt(j['moved']),
        handovers: asInt(j['handovers']),
        notifiedStudents: asInt(j['notified_students']),
        notifiedAdvisors: asInt(j['notified_advisors']),
      );

  /// "Done: 38 assigned, 4 moved." in the user's language.
  String get summary {
    final parts = <String>[
      if (assigned > 0) t('$assigned تعيين', '$assigned assigned'),
      if (moved > 0) t('$moved نقل', '$moved moved'),
      if (handovers > 0) t('$handovers تسليم', '$handovers handovers'),
    ];
    return parts.isEmpty ? t('طُبّق التوزيع', 'Distribution applied') : t('طُبّق: ${parts.join('، ')}', 'Applied: ${parts.join(', ')}');
  }
}

/// One row of `GET …/assign/runs`.
class AdvRun {
  const AdvRun({required this.id, this.mode = 'distribute', this.strategy = '', this.status = 'planned', this.counts = const AdvPlanCounts(), this.actor, this.createdAt, this.appliedAt});

  final int id;
  final String mode, strategy, status;
  final AdvPlanCounts counts;
  final String? actor;
  final DateTime? createdAt, appliedAt;

  factory AdvRun.fromJson(Map<String, dynamic> j) {
    final actor = j['actor'];
    return AdvRun(
      id: asInt(j['id']),
      mode: asStr(j['mode'], 'distribute'),
      strategy: asStr(j['strategy']),
      status: asStr(j['status'], 'planned'),
      counts: AdvPlanCounts.fromJson(asMap(j['counts'])),
      actor: actor is Map ? _text(asMap(actor)['name']) : _text(actor),
      createdAt: orgParseUtc(j['created_at']),
      appliedAt: orgParseUtc(j['applied_at']),
    );
  }

  bool get applied => status == 'applied';
}

// ── Handovers ──────────────────────────────────────────────────────────────

class AdvHandoverSummary {
  const AdvHandoverSummary({this.flagsOpen = 0, this.plansActive = 0, this.requestsOpen = 0, this.notes = 0, this.lastMeetings = const []});

  final int flagsOpen, plansActive, requestsOpen, notes;

  /// (when, mode) of the latest meetings.
  final List<(DateTime?, String)> lastMeetings;

  factory AdvHandoverSummary.fromJson(Map<String, dynamic> j) => AdvHandoverSummary(
        flagsOpen: asInt(j['flags_open']),
        plansActive: asInt(j['plans_active']),
        requestsOpen: asInt(j['requests_open']),
        notes: asInt(j['notes']),
        lastMeetings: [for (final m in asMapList(j['last_meetings'])) (orgParseUtc(m['at']), asStr(m['mode']))],
      );

  bool get empty => flagsOpen == 0 && plansActive == 0 && requestsOpen == 0 && notes == 0 && lastMeetings.isEmpty;
}

class AdvHandover {
  const AdvHandover({
    required this.id,
    this.memberId = 0,
    this.student = '',
    this.from,
    required this.to,
    this.reason,
    this.note,
    this.summary = const AdvHandoverSummary(),
    this.createdAt,
    this.acknowledgedAt,
  });

  final int id, memberId;
  final String student;
  final AdvRef? from;
  final AdvRef to;

  /// Why it moved · what the previous advisor or the director wrote for the new advisor (optional).
  final String? reason, note;
  final AdvHandoverSummary summary;
  final DateTime? createdAt, acknowledgedAt;

  factory AdvHandover.fromJson(Map<String, dynamic> j) {
    final st = j['student'];
    return AdvHandover(
      id: asInt(j['id']),
      memberId: asInt(j['member_id']),
      student: (st is Map ? asStr(asMap(st)['name']) : asStr(st)).trim(),
      from: AdvRef.maybe(j['from']),
      to: AdvRef.maybe(j['to']) ?? const AdvRef(userId: 0, name: ''),
      reason: _text(j['reason']),
      note: _text(j['note']),
      summary: AdvHandoverSummary.fromJson(asMap(j['summary'])),
      createdAt: orgParseUtc(j['created_at']),
      acknowledgedAt: orgParseUtc(j['acknowledged_at']),
    );
  }

  bool get pending => acknowledgedAt == null;
  String get studentShown => student.isEmpty ? '#$memberId' : student;
}

String advMeetingModeLabel(String mode) => switch (mode) {
      'in_person' => t('حضوري', 'In person'),
      'video' => t('مرئي', 'Video'),
      'phone' => t('هاتف', 'Phone'),
      'chat' => t('محادثة', 'Chat'),
      'email' => t('بريد إلكتروني', 'E-mail'),
      _ => mode,
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Phase 4 — the advisor's workspace (docs/advising/PHASE4.md): my students by risk, the student 360, categories,
//  flags and their lifecycle, notes, the timeline, the advising key of `/org/mine`
// ═════════════════════════════════════════════════════════════════════════════

double? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

/// "1.62" (two decimals) · "" for null.
String advGpa(double? v) => v == null ? '' : v.toStringAsFixed(2);

/// "27%" (whole percent, one decimal under 10) · "" for null.
String advPct(double? v) {
  if (v == null) return '';
  final r = v < 10 && v != v.roundToDouble() ? v.toStringAsFixed(1) : v.round().toString();
  return '$r%';
}

// ── Priority, flag status, visibility, contact ───────────────────────────────

/// One scale for flags (PLAN §2 #6), lowest first.
const advPriorities = ['low', 'normal', 'high', 'urgent'];

/// 0 (low) – 3 (urgent); an unknown value counts as normal.
int advPriorityRank(String? p) {
  final i = advPriorities.indexOf(p ?? '');
  return i < 0 ? 1 : i;
}

String advPriorityLabel(String? p) => switch (p) {
      'low' => t('منخفضة', 'Low'),
      'high' => t('عالية', 'High'),
      'urgent' => t('عاجلة', 'Urgent'),
      _ => t('عادية', 'Normal'),
    };

/// The flag lifecycle (`flags_flow.py`), in order.
const advFlagStatuses = ['open', 'acknowledged', 'contacted', 'resolved', 'dismissed'];

String advFlagStatusLabel(String? s) => switch (s) {
      'open' => t('مفتوح', 'Open'),
      'acknowledged' => t('تم الاطلاع', 'Acknowledged'),
      'contacted' => t('تم التواصل', 'Contacted'),
      'resolved' => t('تمت المعالجة', 'Resolved'),
      'dismissed' => t('مستبعد', 'Dismissed'),
      _ => s ?? '',
    };

/// What moving a flag to [s] means, under its label in the status sheet.
String advFlagStatusHint(String s) => switch (s) {
      'open' => t('إعادة فتح التنبيه لمتابعته من جديد', 'Open the flag again to follow it up'),
      'acknowledged' => t('اطلعت عليه وستتابعه', 'You have seen it and will follow it up'),
      'contacted' => t('تواصلت مع الطالب (يُسجّل كآخر تواصل)', 'You reached the student (recorded as the last contact)'),
      'resolved' => t('عولج الأمر — اكتب النتيجة', 'The matter is dealt with — write the outcome'),
      'dismissed' => t('لا يحتاج متابعة', 'It needs no follow-up'),
      _ => '',
    };

bool advFlagClosed(String? s) => s == 'resolved' || s == 'dismissed';

/// The states a flag may move to from [status] (the server's `flags_flow.py`); a closed flag reopens only for its
/// owner or a director ([canReopen]).
List<String> advFlagNext(String? status, {bool canReopen = true}) => switch (status) {
      'open' => const ['acknowledged', 'contacted', 'resolved', 'dismissed'],
      'acknowledged' => const ['contacted', 'resolved', 'dismissed'],
      'contacted' => const ['resolved', 'dismissed'],
      'resolved' || 'dismissed' => canReopen ? const ['open'] : const [],
      _ => const [],
    };

/// Who may read a note: the author only · the student's advisors and the directors · also the student.
const advNoteVisibilities = ['private', 'team', 'student'];

String advVisibilityLabel(String? v) => switch (v) {
      'private' => t('خاصة', 'Private'),
      'student' => t('يراها الطالب', 'Shared with the student'),
      _ => t('فريق الإرشاد', 'Advising team'),
    };

String advVisibilityHint(String v) => switch (v) {
      'private' => t('أنت فقط', 'Only you'),
      'student' => t('مرشدو الطالب والمديرون والطالب نفسه', 'The student\'s advisors, the directors and the student'),
      _ => t('مرشدو الطالب ومديرو الإرشاد', 'The student\'s advisors and the advising directors'),
    };

/// How a logged contact happened.
const advContactModes = ['in_person', 'phone', 'video', 'chat', 'email'];

// ── Categories ───────────────────────────────────────────────────────────────

/// The built-in categories' names, for a category whose names came empty.
String advCategoryKeyLabel(String key) => switch (key) {
      'academic' => t('أكاديمي', 'Academic'),
      'financial' => t('مالي', 'Financial'),
      'career' => t('مهني', 'Career'),
      'health' => t('صحي', 'Health'),
      'psychological' => t('نفسي واجتماعي', 'Psychological and social'),
      'disciplinary' => t('انضباطي', 'Disciplinary'),
      'accessibility' => t('احتياجات خاصة وإتاحة', 'Accessibility'),
      'other' => t('أخرى', 'Other'),
      _ => key,
    };

/// A recommended accommodation of a category (e.g. extra exam time for `accessibility`).
class AdvAccommodation {
  const AdvAccommodation({this.key = '', this.labelAr = '', this.labelEn = ''});
  final String key, labelAr, labelEn;

  factory AdvAccommodation.fromJson(Map<String, dynamic> j) =>
      AdvAccommodation(key: asStr(j['key']), labelAr: asStr(j['label_ar']).trim(), labelEn: asStr(j['label_en']).trim());

  String get label {
    final s = t(labelAr, labelEn);
    if (s.isNotEmpty) return s;
    final other = labelAr.isNotEmpty ? labelAr : labelEn;
    return other.isNotEmpty ? other : key;
  }

  /// A new row has no key yet: the server makes one from the label.
  Map<String, dynamic> toJson() => {'key': key.isEmpty ? null : key, 'label_ar': labelAr.trim(), 'label_en': labelEn.trim()};

  AdvAccommodation copyWith({String? labelAr, String? labelEn}) =>
      AdvAccommodation(key: key, labelAr: labelAr ?? this.labelAr, labelEn: labelEn ?? this.labelEn);
}

/// A flag / note category (`GET …/categories`; also the `category` block of a flag or a note).
class AdvCategory {
  const AdvCategory({
    required this.id,
    this.key = '',
    this.nameAr = '',
    this.nameEn = '',
    this.sensitive = false,
    this.system = false,
    this.active = true,
    this.accommodations = const [],
  });

  final int id;
  final String key, nameAr, nameEn;

  /// Its flags and notes are read only by their author, the primary advisor and the directors.
  final bool sensitive;

  /// Seeded by the platform: renamable, never deletable.
  final bool system;
  final bool active;
  final List<AdvAccommodation> accommodations;

  factory AdvCategory.fromJson(Map<String, dynamic> j) => AdvCategory(
        id: asInt(j['id']),
        key: asStr(j['key']),
        nameAr: asStr(j['name_ar']).trim(),
        nameEn: asStr(j['name_en']).trim(),
        sensitive: asBool(j['sensitive']),
        system: asBool(j['system']),
        active: asBool(j['active'], true),
        accommodations: [for (final m in asMapList(j['accommodations'])) AdvAccommodation.fromJson(m)],
      );

  static AdvCategory? maybe(dynamic v) {
    if (v is! Map) return null;
    final c = AdvCategory.fromJson(asMap(v));
    return c.id == 0 && c.key.isEmpty ? null : c;
  }

  String get name {
    final s = t(nameAr, nameEn);
    if (s.isNotEmpty) return s;
    final other = nameAr.isNotEmpty ? nameAr : nameEn;
    return other.isNotEmpty ? other : advCategoryKeyLabel(key);
  }

  /// The label of one of its accommodation keys (the key itself when the category no longer lists it).
  String accommodationLabel(String k) => accommodations.where((a) => a.key == k).firstOrNull?.label ?? k;
}

/// The category editor's body: POST (new) and the whole-object PUT.
class AdvCategoryDraft {
  const AdvCategoryDraft({this.nameAr = '', this.nameEn = '', this.sensitive = false, this.active = true, this.accommodations = const []});

  factory AdvCategoryDraft.of(AdvCategory c) =>
      AdvCategoryDraft(nameAr: c.nameAr, nameEn: c.nameEn, sensitive: c.sensitive, active: c.active, accommodations: c.accommodations);

  final String nameAr, nameEn;
  final bool sensitive, active;
  final List<AdvAccommodation> accommodations;

  AdvCategoryDraft copyWith({String? nameAr, String? nameEn, bool? sensitive, bool? active, List<AdvAccommodation>? accommodations}) =>
      AdvCategoryDraft(
        nameAr: nameAr ?? this.nameAr,
        nameEn: nameEn ?? this.nameEn,
        sensitive: sensitive ?? this.sensitive,
        active: active ?? this.active,
        accommodations: accommodations ?? this.accommodations,
      );

  /// Why it cannot be saved, null when it can.
  String? error() {
    if (nameAr.trim().isEmpty && nameEn.trim().isEmpty) return t('اكتب اسم التصنيف', 'Give the category a name');
    if (accommodations.any((a) => a.labelAr.trim().isEmpty && a.labelEn.trim().isEmpty)) {
      return t('اكتب اسم كل تسهيل أو احذفه', 'Name every accommodation or remove it');
    }
    return null;
  }

  bool changedFrom(AdvCategory c) => !_same(toJson(), AdvCategoryDraft.of(c).toJson());

  /// [create]: the POST body (no `active`: a new category is active).
  Map<String, dynamic> toJson({bool create = false}) => {
        'name_ar': nameAr.trim(),
        'name_en': nameEn.trim(),
        'sensitive': sensitive,
        if (!create) 'active': active,
        'accommodations': [for (final a in accommodations) a.toJson()],
      };
}

// ── Risk ─────────────────────────────────────────────────────────────────────

/// A non-zero part of the risk score (`score.py`): `cgpa_low` · `gpa_drop` · `absence_high` · `failed_courses` ·
/// `open_flags` · `no_contact`, with its value.
class AdvRiskReason {
  const AdvRiskReason(this.code, [this.value, this.points = 0]);
  final String code;
  final double? value;

  /// What this part adds to the score (the server lists the parts largest first).
  final int points;

  factory AdvRiskReason.fromJson(Map<String, dynamic> j) => AdvRiskReason(asStr(j['code']), _num(j['value']), asInt(j['points']));
}

/// The sentence of a risk reason. [flags] (the student's open flags) words `open_flags`.
String advRiskReasonText(AdvRiskReason r, {AdvFlagCounts? flags}) {
  final v = r.value;
  final n = v?.round() ?? 0;
  switch (r.code) {
    case 'cgpa_low':
      return v == null ? t('المعدل التراكمي منخفض', 'Low CGPA') : t('المعدل التراكمي ${advGpa(v)} دون 2.00', 'CGPA ${advGpa(v)}, under 2.00');
    case 'gpa_drop':
      return v == null
          ? t('تراجع معدل الفصل الأخير', 'Last term GPA dropped')
          : t('معدل الفصل الأخير أقل من التراكمي بـ ${advGpa(v)}', 'Last term GPA ${advGpa(v)} under the CGPA');
    case 'absence_high':
      return v == null ? t('غياب مرتفع', 'High absence') : t('غياب ${advPct(v)} في أحد المقررات', '${advPct(v)} absence in a course');
    case 'failed_courses':
      return v == null
          ? t('رسوب في مقررات', 'Failed courses')
          : countText(n, ar1: 'رسوب في مقرر واحد', ar2: 'رسوب في مقررين', arFew: 'رسوب في $n مقررات', arMany: 'رسوب في $n مقرراً', en1: '1 failed course', en: '$n failed courses');
    case 'open_flags':
      final f = flags;
      if (f == null || f.total == 0) return t('تنبيهات مفتوحة', 'Open flags');
      final top = advPriorityLabel(f.highest);
      return countText(f.total,
          ar1: 'تنبيه مفتوح ($top)', ar2: 'تنبيهان مفتوحان، أعلاها $top', arFew: '${f.total} تنبيهات مفتوحة، أعلاها $top', arMany: '${f.total} تنبيهاً مفتوحاً، أعلاها $top',
          en1: '1 open flag ($top)', en: '${f.total} open flags, highest $top');
    case 'no_contact':
      return v == null
          ? t('لا تواصل مسجّل بعد', 'No contact recorded yet')
          : countText(n, ar1: 'لا تواصل منذ يوم', ar2: 'لا تواصل منذ يومين', arFew: 'لا تواصل منذ $n أيام', arMany: 'لا تواصل منذ $n يوماً', en1: 'No contact for 1 day', en: 'No contact for $n days');
    default:
      return r.code;
  }
}

/// How worrying a 0 – 100 risk score is: `low` (under 30) · `watch` (30 – 59) · `high` (60 and above).
String advRiskBand(int score) => score >= 60 ? 'high' : (score >= 30 ? 'watch' : 'low');

String advRiskBandLabel(String band) => switch (band) {
      'high' => t('خطر مرتفع', 'High risk'),
      'watch' => t('يحتاج متابعة', 'Needs watching'),
      _ => t('مستقر', 'Steady'),
    };

/// Open flags by priority (`open_flags`).
class AdvFlagCounts {
  const AdvFlagCounts({this.low = 0, this.normal = 0, this.high = 0, this.urgent = 0});
  final int low, normal, high, urgent;

  factory AdvFlagCounts.fromJson(dynamic v) {
    if (v is! Map) return AdvFlagCounts(normal: asInt(v));
    final j = asMap(v);
    return AdvFlagCounts(low: asInt(j['low']), normal: asInt(j['normal']), high: asInt(j['high']), urgent: asInt(j['urgent']));
  }

  int get total => low + normal + high + urgent;

  /// The highest priority with an open flag (null: none open).
  String? get highest => urgent > 0
      ? 'urgent'
      : high > 0
          ? 'high'
          : normal > 0
              ? 'normal'
              : low > 0
                  ? 'low'
                  : null;

  int of(String priority) => switch (priority) {
        'low' => low,
        'high' => high,
        'urgent' => urgent,
        _ => normal,
      };
}

/// Whole days since [at] (null: never), counted from [now] (default: the clock).
int? advDaysSince(DateTime? at, {DateTime? now}) {
  if (at == null) return null;
  final d = (now ?? DateTime.now()).toUtc().difference(at.toUtc()).inDays;
  return d < 0 ? 0 : d;
}

/// "Last contact 12 days ago" · "Contacted today" · "Never contacted".
String advLastContactText(DateTime? at, {DateTime? now}) {
  final d = advDaysSince(at, now: now);
  if (d == null) return t('لم يُتواصل معه بعد', 'Never contacted');
  if (d == 0) return t('تُوصّل معه اليوم', 'Contacted today');
  return countText(d,
      ar1: 'آخر تواصل منذ يوم', ar2: 'آخر تواصل منذ يومين', arFew: 'آخر تواصل منذ $d أيام', arMany: 'آخر تواصل منذ $d يوماً',
      en1: 'Last contact 1 day ago', en: 'Last contact $d days ago');
}

// ── Workspace ────────────────────────────────────────────────────────────────

/// One student of `GET …/workspace` (and the numbers of the 360's `stats`).
class AdvCaseItem {
  const AdvCaseItem({
    required this.memberId,
    this.userId = 0,
    this.name = '',
    this.code,
    this.program,
    this.level,
    this.cohort,
    this.standing,
    this.cgpa,
    this.lastTermGpa,
    this.absenceMax,
    this.failedCount = 0,
    this.openFlags = const AdvFlagCounts(),
    this.categories = const [],
    this.riskScore = 0,
    this.riskReasons = const [],
    this.lastContactAt,
    this.primary,
  });

  final int memberId, userId;
  final String name;
  final String? code, program, level, cohort, standing;
  final double? cgpa, lastTermGpa, absenceMax;
  final int failedCount;
  final AdvFlagCounts openFlags;

  /// Keys of the categories of the open flags the caller may see.
  final List<String> categories;

  /// 0 – 100.
  final int riskScore;
  final List<AdvRiskReason> riskReasons;
  final DateTime? lastContactAt;
  final AdvRef? primary;

  factory AdvCaseItem.fromJson(Map<String, dynamic> j) => AdvCaseItem(
        memberId: asInt(j['member_id']),
        userId: asInt(j['user_id']),
        name: asStr(j['name']).trim(),
        code: _text(j['code']),
        program: _text(j['program']),
        level: _text(j['level']),
        cohort: _text(j['cohort']),
        standing: _text(j['standing']),
        cgpa: _num(j['cgpa']),
        lastTermGpa: _num(j['last_term_gpa']),
        absenceMax: _num(j['absence_max']),
        failedCount: asInt(j['failed_count']),
        openFlags: AdvFlagCounts.fromJson(j['open_flags']),
        categories: _strList(j['categories']),
        riskScore: asInt(j['risk_score']).clamp(0, 100),
        riskReasons: [for (final m in asMapList(j['risk_reasons'])) AdvRiskReason.fromJson(m)],
        lastContactAt: orgParseUtc(j['last_contact_at']),
        primary: AdvRef.maybe(j['primary']),
      );

  String get shown => name.isEmpty ? '#$memberId' : name;

  /// "2023001 · Computer Science · Level 2 · 2023" (what is known).
  String get subtitle => [?code, ?program, ?level, ?cohort].join(' · ');

  /// The first reason the server listed (the parts come largest first), null when the score is 0.
  AdvRiskReason? get topReason => riskReasons.firstOrNull;
}

/// The workspace's sort orders.
const advWorkspaceSorts = ['risk', 'name', 'cgpa', 'contact'];

String advWorkspaceSortLabel(String s) => switch (s) {
      'name' => t('الاسم', 'Name'),
      'cgpa' => t('المعدل التراكمي', 'CGPA'),
      'contact' => t('أقدم تواصل', 'Oldest contact'),
      _ => t('الأعلى خطراً', 'Highest risk'),
    };

/// The open-flags filter: '' (any) · `open` · `urgent` · `none`.
const advFlagFilters = ['', 'open', 'urgent', 'none'];

String advFlagFilterLabel(String f) => switch (f) {
      'open' => t('لهم تنبيهات مفتوحة', 'With open flags'),
      'urgent' => t('تنبيه عاجل', 'An urgent flag'),
      'none' => t('بلا تنبيهات', 'No open flags'),
      _ => t('الكل', 'Any'),
    };

/// The workspace's query: search, the filters of the one filter sheet, the sort and the page.
class AdvWorkspaceQuery {
  const AdvWorkspaceQuery({
    this.q = '',
    this.advisor,
    this.cohort,
    this.level,
    this.programId,
    this.standing,
    this.categoryId,
    this.priority,
    this.flag = '',
    this.sort = 'risk',
    this.page = 1,
    this.size = 25,
  });

  final String q;

  /// Manage only: one advisor's students.
  final AdvRef? advisor;
  final String? cohort, level, standing, priority;
  final int? programId, categoryId;

  /// '' · `open` · `urgent` · `none`.
  final String flag;

  /// `risk` · `name` · `cgpa` · `contact`.
  final String sort;
  final int page, size;

  AdvWorkspaceQuery copyWith({
    String? q,
    AdvRef? Function()? advisor,
    String? Function()? cohort,
    String? Function()? level,
    int? Function()? programId,
    String? Function()? standing,
    int? Function()? categoryId,
    String? Function()? priority,
    String? flag,
    String? sort,
    int? page,
  }) =>
      AdvWorkspaceQuery(
        q: q ?? this.q,
        advisor: advisor == null ? this.advisor : advisor(),
        cohort: cohort == null ? this.cohort : cohort(),
        level: level == null ? this.level : level(),
        programId: programId == null ? this.programId : programId(),
        standing: standing == null ? this.standing : standing(),
        categoryId: categoryId == null ? this.categoryId : categoryId(),
        priority: priority == null ? this.priority : priority(),
        flag: flag ?? this.flag,
        sort: sort ?? this.sort,
        page: page ?? this.page,
        size: size,
      );

  /// Every filter off; the search and the sort stay.
  AdvWorkspaceQuery cleared() => AdvWorkspaceQuery(q: q, sort: sort, size: size);

  /// How many filters are on (the search and the sort are not filters).
  int get activeFilters => [advisor, cohort, level, programId, standing, categoryId, priority].where((v) => v != null).length + (flag.isEmpty ? 0 : 1);

  /// The query string. [manage]: the advisor filter is sent (the server ignores it for an advisor anyway).
  Map<String, dynamic> toQuery({required bool manage}) => {
        if (q.trim().isNotEmpty) 'q': q.trim(),
        if (manage && advisor != null) 'advisor_user_id': advisor!.userId,
        'cohort': ?cohort,
        'level': ?level,
        'program_id': ?programId,
        'standing': ?standing,
        'category_id': ?categoryId,
        'priority': ?priority,
        if (flag.isNotEmpty) 'flag': flag,
        'sort': sort,
        'page': page,
        'size': size,
      };
}

/// The choices of the filter sheet: from the settings (directors), else from the students already listed.
class AdvWorkspaceChoices {
  const AdvWorkspaceChoices({this.cohorts = const [], this.levels = const [], this.programs = const [], this.standings = const [], this.categories = const []});

  final List<String> cohorts, levels, standings;
  final List<AdvNamed> programs;
  final List<AdvCategory> categories;

  /// [options] (`GET …/policy`, directors) give every level, cohort and program; [seen] adds what the listed students
  /// carry (an advisor has no settings access); standings come from the students and the registrar's three.
  factory AdvWorkspaceChoices.from({AdvPolicyOptions? options, Iterable<AdvCaseItem> seen = const [], List<AdvCategory> categories = const []}) {
    List<String> merge(List<String> a, Iterable<String?> b) {
      final out = <String>{...a, for (final x in b) ?x}.toList()..sort();
      return out;
    }

    return AdvWorkspaceChoices(
      cohorts: merge(options?.cohorts ?? const [], seen.map((s) => s.cohort)),
      levels: merge(options?.levels ?? const [], seen.map((s) => s.level)),
      programs: options?.programs ?? const [],
      standings: merge(const ['good', 'probation', 'honours'], seen.map((s) => s.standing)),
      categories: [for (final c in categories) if (c.active) c],
    );
  }
}

// ── Flags ────────────────────────────────────────────────────────────────────

class AdvFlag {
  const AdvFlag({
    required this.id,
    required this.category,
    this.priority = 'normal',
    this.status = 'open',
    this.source = 'manual',
    this.note,
    this.outcomeNote,
    this.reviewDueAt,
    this.owner,
    this.accommodations = const [],
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.resolvedAt,
    this.resolvedInHours,
    this.escalatedAt,
    this.overdue = false,
    this.allowedNext,
    this.reopenedAt,
  });

  final int id;
  final AdvCategory category;

  /// `low` · `normal` · `high` · `urgent`.
  final String priority;

  /// `open` · `acknowledged` · `contacted` · `resolved` · `dismissed`.
  final String status;

  /// `manual` · `rule` (the early-warning engine, Phase 6).
  final String source;
  final String? note, outcomeNote;
  final DateTime? reviewDueAt;
  final AdvRef? owner, createdBy;

  /// Keys of the category's accommodations.
  final List<String> accommodations;
  final DateTime? createdAt, updatedAt, resolvedAt, escalatedAt;

  /// When it was last reopened (reopening clears the outcome and the escalation).
  final DateTime? reopenedAt;
  final int? resolvedInHours;

  /// Its review date has passed.
  final bool overdue;

  /// The states this caller may move the flag to (the server's state machine); null from an older server, where
  /// [advFlagNext] stands in.
  final List<String>? allowedNext;

  factory AdvFlag.fromJson(Map<String, dynamic> j) {
    final p = asStr(j['priority'], 'normal');
    final hours = j['resolved_in_hours'];
    return AdvFlag(
      id: asInt(j['id']),
      category: AdvCategory.maybe(j['category']) ?? const AdvCategory(id: 0, key: 'other'),
      priority: advPriorities.contains(p) ? p : 'normal',
      status: asStr(j['status'], 'open'),
      source: asStr(j['source'], 'manual'),
      note: _text(j['note']),
      outcomeNote: _text(j['outcome_note']),
      reviewDueAt: orgParseUtc(j['review_due_at']),
      owner: AdvRef.maybe(j['owner']),
      accommodations: _strList(j['accommodations']),
      createdBy: AdvRef.maybe(j['created_by']),
      createdAt: orgParseUtc(j['created_at']),
      updatedAt: orgParseUtc(j['updated_at']),
      resolvedAt: orgParseUtc(j['resolved_at']),
      resolvedInHours: hours == null ? null : asInt(hours),
      escalatedAt: orgParseUtc(j['escalated_at']),
      overdue: asBool(j['overdue']),
      allowedNext: j['allowed_next'] is List ? [for (final s in _strList(j['allowed_next'])) if (advFlagStatuses.contains(s)) s] : null,
      reopenedAt: orgParseUtc(j['reopened_at']),
    );
  }

  bool get closed => advFlagClosed(status);

  /// Where this caller may move it: the server's `allowed_next`, else the lifecycle ([canReopen]: owner or director).
  List<String> nextStates({bool canReopen = true}) => allowedNext ?? advFlagNext(status, canReopen: canReopen);
}

/// The flag sheet's body: POST and the whole-object PUT.
class AdvFlagDraft {
  const AdvFlagDraft({this.categoryId, this.priority = 'normal', this.note = '', this.reviewDueAt, this.accommodations = const []});

  factory AdvFlagDraft.of(AdvFlag f) => AdvFlagDraft(
        categoryId: f.category.id == 0 ? null : f.category.id,
        priority: f.priority,
        note: f.note ?? '',
        reviewDueAt: f.reviewDueAt,
        accommodations: f.accommodations,
      );

  final int? categoryId;
  final String priority, note;
  final DateTime? reviewDueAt;
  final List<String> accommodations;

  AdvFlagDraft copyWith({int? Function()? categoryId, String? priority, String? note, DateTime? Function()? reviewDueAt, List<String>? accommodations}) =>
      AdvFlagDraft(
        categoryId: categoryId == null ? this.categoryId : categoryId(),
        priority: priority ?? this.priority,
        note: note ?? this.note,
        reviewDueAt: reviewDueAt == null ? this.reviewDueAt : reviewDueAt(),
        accommodations: accommodations ?? this.accommodations,
      );

  /// A new category keeps only the accommodations it lists.
  AdvFlagDraft withCategory(AdvCategory c) =>
      copyWith(categoryId: () => c.id, accommodations: [for (final a in accommodations) if (c.accommodations.any((x) => x.key == a)) a]);

  AdvFlagDraft toggleAccommodation(String key) =>
      copyWith(accommodations: accommodations.contains(key) ? [for (final a in accommodations) if (a != key) a] : [...accommodations, key]);

  /// Why it cannot be saved, null when it can. [category] = the chosen one (its accommodations).
  String? error({AdvCategory? category}) {
    if (categoryId == null) return t('اختر تصنيف التنبيه', 'Choose the flag\'s category');
    if (note.length > 10000) return t('الملاحظة أطول من 10000 حرف', 'The note is longer than 10,000 characters');
    if (category != null && accommodations.any((a) => !category.accommodations.any((x) => x.key == a))) {
      return t('التسهيلات لا تتبع هذا التصنيف', 'Those accommodations do not belong to this category');
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'category_id': categoryId,
        'priority': priority,
        'note': note.trim().isEmpty ? null : note.trim(),
        'review_due_at': orgUtc(reviewDueAt),
        'accommodations': accommodations,
      };
}

/// One row of `GET …/flags/{id}/history` (newest first).
class AdvFlagEvent {
  const AdvFlagEvent({this.at, this.actor, this.action = '', this.before = const {}, this.after = const {}});
  final DateTime? at;
  final String? actor;
  final String action;
  final Map<String, dynamic> before, after;

  factory AdvFlagEvent.fromJson(Map<String, dynamic> j) => AdvFlagEvent(
        at: orgParseUtc(j['at']),
        actor: _personName(j['actor']),
        action: asStr(j['action']),
        before: asMap(j['before']),
        after: asMap(j['after']),
      );

  /// "Status: Open → Contacted" · "Opened" · "Edited" · "Escalated to the directors".
  String get text {
    final a = action.toLowerCase();
    final s0 = asStr(before['status']), s1 = asStr(after['status']);
    if (s1.isNotEmpty && s0 != s1 && s0.isNotEmpty) {
      return t('الحالة: ${advFlagStatusLabel(s0)} ← ${advFlagStatusLabel(s1)}', 'Status: ${advFlagStatusLabel(s0)} → ${advFlagStatusLabel(s1)}');
    }
    if (a.contains('escalat')) return t('صُعّد إلى مديري الإرشاد', 'Escalated to the advising directors');
    if (a.contains('create') || a.contains('open') || before.isEmpty) return t('فُتح التنبيه', 'Flag opened');
    final p0 = asStr(before['priority']), p1 = asStr(after['priority']);
    if (p1.isNotEmpty && p0 != p1 && p0.isNotEmpty) {
      return t('الأولوية: ${advPriorityLabel(p0)} ← ${advPriorityLabel(p1)}', 'Priority: ${advPriorityLabel(p0)} → ${advPriorityLabel(p1)}');
    }
    return t('عُدّل التنبيه', 'Flag edited');
  }

  /// The outcome note written with this change, when there is one.
  String? get outcome => _text(after['outcome_note']);
}

// ── Notes ────────────────────────────────────────────────────────────────────

class AdvNote {
  const AdvNote({
    required this.id,
    required this.author,
    this.visibility = 'team',
    this.sensitive = false,
    this.category,
    this.body = '',
    this.contactMode,
    this.contactAt,
    this.createdAt,
    this.editedAt,
    this.mine = false,
    this.clientId,
  });

  final int id;
  final AdvRef author;

  /// `private` · `team` · `student`.
  final String visibility;
  final bool sensitive;
  final AdvCategory? category;

  /// Plain text, never rendered as markup.
  final String body;

  /// Set when the note logs a contact: `in_person` · `phone` · `video` · `chat` · `email`.
  final String? contactMode;
  final DateTime? contactAt, createdAt, editedAt;
  final bool mine;

  /// The offline draft id it was posted with (matches a queued note already on the server).
  final String? clientId;

  factory AdvNote.fromJson(Map<String, dynamic> j) {
    final v = asStr(j['visibility'], 'team');
    return AdvNote(
      id: asInt(j['id']),
      author: AdvRef.maybe(j['author']) ?? const AdvRef(userId: 0, name: ''),
      visibility: advNoteVisibilities.contains(v) ? v : 'team',
      sensitive: asBool(j['sensitive']),
      category: AdvCategory.maybe(j['category']),
      body: asStr(j['body']),
      contactMode: _text(j['contact_mode']),
      contactAt: orgParseUtc(j['contact_at']),
      createdAt: orgParseUtc(j['created_at']),
      editedAt: orgParseUtc(j['edited_at']),
      mine: asBool(j['mine']),
      clientId: _text(j['client_id']),
    );
  }
}

/// The longest note the server keeps.
const advNoteMaxLength = 10000;

/// A note being written: the composer, the offline draft and the queued note (POST), or an edit (the whole-object
/// PUT). [clientId] makes a POST idempotent: the same id twice answers the note already made.
class AdvNoteDraft {
  const AdvNoteDraft({
    this.body = '',
    this.visibility = 'team',
    this.sensitive = false,
    this.categoryId,
    this.contactMode,
    this.contactAt,
    this.clientId,
  });

  factory AdvNoteDraft.of(AdvNote n) => AdvNoteDraft(
        body: n.body,
        visibility: n.visibility,
        sensitive: n.sensitive,
        categoryId: n.category?.id,
        contactMode: n.contactMode,
        contactAt: n.contactAt,
      );

  final String body;
  final String visibility;
  final bool sensitive;
  final int? categoryId;

  /// null: not a logged contact.
  final String? contactMode;
  final DateTime? contactAt;
  final String? clientId;

  AdvNoteDraft copyWith({
    String? body,
    String? visibility,
    bool? sensitive,
    int? Function()? categoryId,
    String? Function()? contactMode,
    DateTime? Function()? contactAt,
    String? Function()? clientId,
  }) {
    final s = sensitive ?? this.sensitive;
    final v = visibility ?? this.visibility;
    return AdvNoteDraft(
      body: body ?? this.body,
      // a sensitive note is never shown to the student
      visibility: s && v == 'student' ? 'team' : v,
      sensitive: s,
      categoryId: categoryId == null ? this.categoryId : categoryId(),
      contactMode: contactMode == null ? this.contactMode : contactMode(),
      contactAt: contactAt == null ? this.contactAt : contactAt(),
      clientId: clientId == null ? this.clientId : clientId(),
    );
  }

  bool get isContact => contactMode != null;
  bool get isEmpty => body.trim().isEmpty;

  /// Why it cannot be sent, null when it can.
  String? error() {
    if (body.trim().isEmpty) return t('اكتب الملاحظة', 'Write the note');
    if (body.length > advNoteMaxLength) return t('الملاحظة أطول من 10000 حرف', 'The note is longer than 10,000 characters');
    if (sensitive && visibility == 'student') return t('الملاحظة الحساسة لا تُعرض على الطالب', 'A sensitive note is never shown to the student');
    return null;
  }

  /// The POST / PUT body. [create] adds the offline id.
  Map<String, dynamic> toJson({bool create = true}) => {
        'body': body.trim(),
        'visibility': visibility,
        'sensitive': sensitive,
        'category_id': categoryId,
        'contact_mode': contactMode,
        'contact_at': contactMode == null ? null : orgUtc(contactAt ?? DateTime.now()),
        if (create) 'client_id': clientId,
      };

  /// What the device keeps (the draft store): the body as typed, nothing trimmed.
  Map<String, dynamic> toStore() => {
        'body': body,
        'visibility': visibility,
        'sensitive': sensitive,
        'category_id': categoryId,
        'contact_mode': contactMode,
        'contact_at': contactAt?.toUtc().toIso8601String(),
        'client_id': clientId,
      };

  factory AdvNoteDraft.fromStore(Map<String, dynamic> j) {
    final v = asStr(j['visibility'], 'team');
    final cat = j['category_id'];
    return AdvNoteDraft(
      body: asStr(j['body']),
      visibility: advNoteVisibilities.contains(v) ? v : 'team',
      sensitive: asBool(j['sensitive']),
      categoryId: cat == null ? null : asInt(cat),
      contactMode: _text(j['contact_mode']),
      contactAt: orgParseUtc(j['contact_at']),
      clientId: _text(j['client_id']),
    );
  }

  /// Something worth keeping on the device.
  bool get worthKeeping => !isEmpty;
}

// ── Timeline ─────────────────────────────────────────────────────────────────

/// A person a payload names as `{"user_id","name"}` or as a plain name.
String? _personName(dynamic v) {
  if (v is Map) {
    final m = asMap(v);
    final n = asStr(m['name']).trim();
    if (n.isNotEmpty) return n;
    final id = asInt(m['user_id'] ?? m['id']);
    return id == 0 ? null : '#$id';
  }
  return _text(v);
}

/// A category a payload names as a block (`{"key","name_ar","name_en"}`) or as its key.
String? _categoryName(dynamic v) {
  if (v is Map) return AdvCategory.fromJson(asMap(v)).name;
  final k = _text(v);
  return k == null ? null : advCategoryKeyLabel(k);
}

/// The timeline's kinds.
const advTimelineKinds = ['assigned', 'unassigned', 'handover', 'flag_opened', 'flag_status', 'note', 'contact'];

class AdvTimelineEntry {
  const AdvTimelineEntry({this.at, this.kind = '', this.refId, this.actor, this.data = const {}});
  final DateTime? at;
  final String kind;
  final int? refId;
  final String? actor;
  final Map<String, dynamic> data;

  factory AdvTimelineEntry.fromJson(Map<String, dynamic> j) {
    final ref = j['ref_id'];
    return AdvTimelineEntry(
      at: orgParseUtc(j['at']),
      kind: asStr(j['kind']),
      refId: ref == null ? null : asInt(ref),
      actor: _personName(j['actor']),
      data: asMap(j['data']),
    );
  }

  /// The line the app writes from [kind] and [data].
  String get text {
    final d = data;
    final advisor = _personName(d['advisor'] ?? d['to'] ?? d['user']);
    final type = asStr(d['type']);
    switch (kind) {
      case 'assigned':
        if (advisor == null) return t('أُسند مرشد للطالب', 'An advisor was assigned');
        final en = switch (type) { 'co' => 'co-advisor', 'support' => 'support advisor', _ => 'academic advisor' };
        return t('أصبح $advisor ${advAdvisorTypeLabel(type.isEmpty ? 'primary' : type)}', '$advisor became the $en');
      case 'unassigned':
        final who = _personName(d['advisor'] ?? d['user']);
        final why = _text(d['reason'] ?? d['end_reason']);
        final base = who == null ? t('انتهى إسناد مرشد', 'An advisor stopped advising') : t('توقف $who عن الإرشاد', '$who stopped advising');
        return why == null ? base : '$base · ${advEndReasonLabel(why)}';
      case 'handover':
        final from = _personName(d['from']), to = _personName(d['to']);
        if (from != null && to != null) return t('تسليم من $from إلى $to', 'Handed over from $from to $to');
        return to == null ? t('سُلّم الملف لمرشد جديد', 'Handed over to a new advisor') : t('سُلّم الملف إلى $to', 'Handed over to $to');
      case 'flag_opened':
        final cat = _categoryName(d['category']);
        final p = _text(d['priority']);
        return [t('تنبيه جديد', 'Flag opened'), ?cat, if (p != null) advPriorityLabel(p)].join(' · ');
      case 'flag_status':
        final cat = _categoryName(d['category']);
        final from = _text(d['from'] ?? d['before']), to = _text(d['to'] ?? d['after'] ?? d['status']);
        final move = to == null
            ? t('تغيّرت حالة تنبيه', 'A flag changed status')
            : from == null
                ? t('تنبيه: ${advFlagStatusLabel(to)}', 'Flag: ${advFlagStatusLabel(to)}')
                : t('تنبيه: ${advFlagStatusLabel(from)} ← ${advFlagStatusLabel(to)}', 'Flag: ${advFlagStatusLabel(from)} → ${advFlagStatusLabel(to)}');
        return cat == null ? move : '$move · $cat';
      case 'note':
        final v = _text(d['visibility']);
        final sensitive = asBool(d['sensitive']);
        return [
          t('ملاحظة إرشادية', 'Advising note'),
          if (v != null) advVisibilityLabel(v),
          if (sensitive) t('حساسة', 'sensitive'),
        ].join(' · ');
      case 'contact':
        final m = _text(d['mode'] ?? d['contact_mode']);
        return m == null ? t('تواصل مع الطالب', 'Contact with the student') : t('تواصل: ${advMeetingModeLabel(m)}', 'Contact: ${advMeetingModeLabel(m)}');
      default:
        return advCommTimelineText(kind, d) ?? t('نشاط في الملف', 'Activity on the record');
    }
  }
}

class AdvTimelinePage {
  const AdvTimelinePage({this.items = const [], this.next});
  final List<AdvTimelineEntry> items;

  /// The cursor of the next (older) page; null at the end.
  final String? next;

  factory AdvTimelinePage.fromJson(Map<String, dynamic> j) =>
      AdvTimelinePage(items: [for (final m in asMapList(j['items'])) AdvTimelineEntry.fromJson(m)], next: _text(j['next']));
}

// ── Student 360 ──────────────────────────────────────────────────────────────

class AdvCaseAdvisor {
  const AdvCaseAdvisor({required this.userId, this.name = '', this.type = 'primary', this.since, this.locked = false});
  final int userId;
  final String name, type;
  final DateTime? since;
  final bool locked;

  factory AdvCaseAdvisor.fromJson(Map<String, dynamic> j) {
    final type = asStr(j['type'], 'primary');
    return AdvCaseAdvisor(
      userId: asInt(j['user_id']),
      name: asStr(j['name']).trim(),
      type: advAdvisorTypes.contains(type) ? type : 'co',
      since: orgParseUtc(j['since']),
      locked: asBool(j['locked']),
    );
  }

  String get shown => name.isEmpty ? '#$userId' : name;
}

/// One course row of a registrar term (`academic.terms[].courses`).
class AdvCourseRow {
  const AdvCourseRow({this.code, this.nameAr = '', this.nameEn = '', this.credits, this.status = '', this.letter, this.absencePct, this.denied = false, this.attempt = 1});
  final String? code, letter;
  final String nameAr, nameEn, status;
  final double? credits, absencePct;
  final bool denied;
  final int attempt;

  factory AdvCourseRow.fromJson(Map<String, dynamic> j) => AdvCourseRow(
        code: _text(j['code']),
        nameAr: asStr(j['name_ar']).trim(),
        nameEn: asStr(j['name_en']).trim(),
        credits: _num(j['credits']),
        status: asStr(j['status']),
        letter: _text(j['letter']),
        absencePct: _num(j['absence_pct']),
        denied: asBool(j['denied']),
        attempt: asInt(j['attempt'], 1),
      );

  String get name {
    final s = t(nameAr, nameEn);
    return s.isNotEmpty ? s : (nameAr.isNotEmpty ? nameAr : nameEn);
  }

  /// A final letter that fails the course.
  bool get failed => letter == 'F' || letter == 'FA' || denied;
}

class AdvAcademicTerm {
  const AdvAcademicTerm({this.id = 0, this.label = '', this.termGpa, this.courses = const []});
  final int id;
  final String label;
  final double? termGpa;
  final List<AdvCourseRow> courses;

  factory AdvAcademicTerm.fromJson(Map<String, dynamic> j) {
    final term = asMap(j['term']);
    return AdvAcademicTerm(
      id: asInt(term['id']),
      label: termTitle(term),
      termGpa: _num(j['term_gpa']),
      courses: [for (final m in asMapList(j['courses'])) AdvCourseRow.fromJson(m)],
    );
  }

  double get credits => courses.fold(0.0, (s, c) => s + (c.credits ?? 0));
}

/// The registrar's record of the student (`record()`), the parts the 360 shows.
class AdvAcademic {
  const AdvAcademic({this.cgpa, this.earned, this.attempted, this.standing, this.stage, this.programName, this.terms = const []});
  final double? cgpa, earned, attempted;
  final String? standing, stage, programName;

  /// Oldest first, as the registrar lists them.
  final List<AdvAcademicTerm> terms;

  factory AdvAcademic.fromJson(Map<String, dynamic> j) {
    final p = asMap(j['program']);
    final pAr = asStr(p['name_ar']).trim(), pEn = asStr(p['name_en']).trim();
    final pn = t(pAr.isNotEmpty ? pAr : pEn, pEn.isNotEmpty ? pEn : pAr);
    return AdvAcademic(
      cgpa: _num(j['cgpa']),
      earned: _num(j['earned']),
      attempted: _num(j['attempted']),
      standing: _text(j['standing']),
      stage: _text(j['stage']),
      programName: pn.isEmpty ? null : pn,
      terms: [for (final m in asMapList(j['terms'])) AdvAcademicTerm.fromJson(m)],
    );
  }
}

class AdvGpaPoint {
  const AdvGpaPoint({this.termId = 0, this.label = '', this.termGpa, this.cgpa});
  final int termId;
  final String label;
  final double? termGpa, cgpa;

  /// `label` is the term's year label and `kind` its term (term1 · term2 · summer): together "Fall 2025-2026".
  factory AdvGpaPoint.fromJson(Map<String, dynamic> j) {
    final label = asStr(j['label']).trim(), kind = _text(j['kind']);
    return AdvGpaPoint(
      termId: asInt(j['term_id']),
      label: kind == null ? label : termTitle({'kind': kind, 'year_label': label}),
      termGpa: _num(j['term_gpa']),
      cgpa: _num(j['cgpa']),
    );
  }
}

class AdvCaseCounts {
  const AdvCaseCounts({this.flagsOpen = 0, this.notes = 0, this.restricted = 0, this.handovers = 0});
  final int flagsOpen, notes, restricted, handovers;

  factory AdvCaseCounts.fromJson(Map<String, dynamic> j) => AdvCaseCounts(
        flagsOpen: asInt(j['flags_open']),
        notes: asInt(j['notes']),
        restricted: asInt(j['restricted']),
        handovers: asInt(j['handovers']),
      );
}

/// What the caller may do on this student.
class AdvCaseCan {
  const AdvCaseCan({this.flag = false, this.note = false, this.assign = false, this.sensitive = false});

  /// Open / change flags · write notes · change the advisors (directors) · read and write sensitive content.
  final bool flag, note, assign, sensitive;

  factory AdvCaseCan.fromJson(Map<String, dynamic> j) =>
      AdvCaseCan(flag: asBool(j['flag']), note: asBool(j['note']), assign: asBool(j['assign']), sensitive: asBool(j['sensitive']));
}

/// `GET …/students/{member_id}/profile`.
class AdvCaseProfile {
  const AdvCaseProfile({
    required this.memberId,
    this.userId = 0,
    this.name = '',
    this.code,
    this.program,
    this.level,
    this.cohort,
    this.standing,
    this.joinedAt,
    this.advisors = const [],
    this.stats = const AdvCaseItem(memberId: 0),
    this.meetingsTerm = 0,
    this.academic,
    this.gpaTrend = const [],
    this.counts = const AdvCaseCounts(),
    this.can = const AdvCaseCan(),
    this.meetings = const AdvMeetings(),
    this.threadCounts = const AdvThreadCounts(),
  });

  final int memberId, userId;
  final String name;
  final String? code, level, cohort, standing;
  final AdvNamed? program;
  final DateTime? joinedAt;

  /// Primary first.
  final List<AdvCaseAdvisor> advisors;

  /// The workspace numbers (cgpa, absence, flags, score, reasons, last contact).
  final AdvCaseItem stats;
  final int meetingsTerm;

  /// The registrar's record; null when the organization does not use the registrar.
  final AdvAcademic? academic;

  /// Oldest first.
  final List<AdvGpaPoint> gpaTrend;
  final AdvCaseCounts counts;
  final AdvCaseCan can;

  /// Phase 5: the student's appointments and conversations (empty from an older server).
  final AdvMeetings meetings;
  final AdvThreadCounts threadCounts;

  factory AdvCaseProfile.fromJson(Map<String, dynamic> j) {
    final s = asMap(j['student']);
    final p = s['program'];
    final st = asMap(j['stats']);
    final ac = j['academic'];
    final advisors = [for (final m in asMapList(j['advisors'])) AdvCaseAdvisor.fromJson(m)]..sort((a, b) => _typeRank(a.type) - _typeRank(b.type));
    final memberId = asInt(s['member_id']);
    return AdvCaseProfile(
      memberId: memberId,
      userId: asInt(s['user_id']),
      name: asStr(s['name']).trim(),
      code: _text(s['code']),
      program: p is Map ? AdvNamed.fromJson(asMap(p)) : null,
      level: _text(s['level']),
      cohort: _text(s['cohort']),
      standing: _text(s['standing']),
      joinedAt: orgParseUtc(s['joined_at']),
      advisors: advisors,
      stats: AdvCaseItem.fromJson({...st, 'member_id': memberId}),
      meetingsTerm: asInt(st['meetings_term']),
      academic: ac is Map ? AdvAcademic.fromJson(asMap(ac)) : null,
      gpaTrend: [for (final m in asMapList(j['gpa_trend'])) AdvGpaPoint.fromJson(m)],
      counts: AdvCaseCounts.fromJson(asMap(j['counts'])),
      can: AdvCaseCan.fromJson(asMap(j['can'])),
      meetings: AdvMeetings.fromJson(asMap(j['meetings'])),
      threadCounts: AdvThreadCounts.fromJson(asMap(j['threads'])),
    );
  }

  String get shown => name.isEmpty ? '#$memberId' : name;

  /// "2023001 · Computer Science · Level 2 · 2023".
  String get subtitle => [?code, ?program?.name, ?level, ?cohort].join(' · ');

  AdvCaseAdvisor? get primary => advisors.where((a) => a.type == 'primary').firstOrNull;

  /// The Phase 3 student sheet's row for "Change advisor".
  AdvStudent toStudent() {
    final p = primary;
    return AdvStudent(
      memberId: memberId,
      userId: userId,
      name: name,
      code: code,
      program: program?.name,
      level: level,
      cohort: cohort,
      primary: p == null ? null : AdvPrimary(userId: p.userId, name: p.name, locked: p.locked, since: p.since),
      others: [for (final a in advisors) if (a.type != 'primary') AdvOther(userId: a.userId, name: a.name, type: a.type)],
    );
  }
}

// ── `/org/mine` ──────────────────────────────────────────────────────────────

/// The `advising` key of a `/org/mine?members=1` item: present when advising is on there and I direct it or hold
/// active assignments.
class AdvMineInfo {
  const AdvMineInfo({required this.role, this.advisees = 0});

  /// `director` · `advisor`.
  final String role;
  final int advisees;

  static AdvMineInfo? of(Map<String, dynamic>? item) {
    final a = item?['advising'];
    if (a is! Map) return null;
    final m = asMap(a);
    final role = asStr(m['role']);
    if (role != 'director' && role != 'advisor') return null;
    return AdvMineInfo(role: role, advisees: asInt(m['advisees']));
  }

  bool get director => role == 'director';
}
