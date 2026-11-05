// lib/features/org/advising/adv_models.dart — pure models of the Academic Advising module (Phase 2, foundation).
// No Flutter widgets: unit-tested in test/org/adv_models_test.dart. Contract: docs/advising/PHASE2.md (routes
// `GET …/orgs/{id}/advising/status`, `POST …/enable` · `…/disable`, member `GET …/public/{id}/advising/status`);
// backend ../back/routers/organization/org_advising_router.py.
//
// Every parser is tolerant of missing keys (an older server leaves a block out): a missing flag is false, a missing
// count block is null, a missing list is empty. Labels are bilingual through `t(ar, en)` like every org screen.
library;

import '../../admin/admin_common.dart' show asBool, asInt, asMap, asMapList, asStr, t;

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
  const AdvPerson({required this.userId, required this.name, this.type});

  final int userId;
  final String name;

  /// The assignment type of an advisor (`primary` · `co` · `support`); null for a director.
  final String? type;

  factory AdvPerson.fromJson(Map<String, dynamic> j) {
    final type = asStr(j['type']);
    return AdvPerson(userId: asInt(j['user_id'] ?? j['id']), name: asStr(j['name']).trim(), type: type.isEmpty ? null : type);
  }

  String get typeLabel => advAdvisorTypeLabel(type ?? '');
}

/// What I am in the advising of this organization (`me`).
class AdvMe {
  const AdvMe({this.admin = false, this.director = false, this.advisor = false, this.advisees = 0});

  final bool admin, director, advisor;

  /// How many students I advise (active assignments).
  final int advisees;

  factory AdvMe.fromJson(Map<String, dynamic> j) => AdvMe(
        admin: asBool(j['admin']),
        director: asBool(j['director']),
        advisor: asBool(j['advisor']),
        advisees: asInt(j['advisees']),
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
  const AdvCounts({this.students = 0, this.assigned = 0, this.unassigned = 0, this.advisors = 0});

  final int students, assigned, unassigned, advisors;

  factory AdvCounts.fromJson(Map<String, dynamic> j) => AdvCounts(
        students: asInt(j['students']),
        assigned: asInt(j['assigned']),
        unassigned: asInt(j['unassigned']),
        advisors: asInt(j['advisors']),
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
