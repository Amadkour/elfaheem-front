// lib/features/courses/course_scope.dart
//
// Which side of a person's life a course list shows (server: ../back/services/course_scope.py):
//
//   personal  courses outside any organization — the personal account (Individual mode)
//   org       one organization's courses, its sub-organizations included — Organization mode
//   all       everything — a student's "All" chip, and what an older server always answers
//
// GET /my-courses (teacher) and GET /my-enrolled-courses (student) take `scope` (+ `org_id`), echo `scope`, and on
// the first page send `scopes` = the unfiltered list counted per side. Every course payload carries `org` (null =
// personal), parsed here as [CourseOrg].
//
// The teacher's list follows the mode strictly (`CourseScope.forMode`); the student picks a side on a chip bar
// whose chips and default are chosen here (`courseScopeChips`, `smartStudentScope`). Pure: unit-tested in
// test/org/course_scope_test.dart.
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';

enum CourseScopeKind { all, personal, org }

class CourseScope {
  const CourseScope._(this.kind, this.orgId);

  const CourseScope.org(int id) : this._(CourseScopeKind.org, id);

  static const all = CourseScope._(CourseScopeKind.all, null);
  static const personal = CourseScope._(CourseScopeKind.personal, null);

  /// The mode's side: Organization mode → that organization, else the personal account.
  static CourseScope forMode({required bool isOrg, int? orgId}) =>
      isOrg && orgId != null ? CourseScope.org(orgId) : personal;

  final CourseScopeKind kind;
  final int? orgId;

  bool get isAll => kind == CourseScopeKind.all;
  bool get isPersonal => kind == CourseScopeKind.personal;
  bool get isOrg => kind == CourseScopeKind.org;

  /// Query parameters for the list routes. "all" is sent too: the server's default side is the personal account
  /// (an older server ignores the parameter and lists everything anyway).
  Map<String, dynamic> get query => switch (kind) {
        CourseScopeKind.all => const {'scope': 'all'},
        CourseScopeKind.personal => const {'scope': 'personal'},
        CourseScopeKind.org => {'scope': 'org', 'org_id': orgId},
      };

  /// Does a course owned by [org] (null = personal) belong to this side?
  bool matches(CourseOrg? org) => switch (kind) {
        CourseScopeKind.all => true,
        CourseScopeKind.personal => org == null,
        CourseScopeKind.org => org != null && org.within(orgId!),
      };

  @override
  bool operator ==(Object other) => other is CourseScope && other.kind == kind && other.orgId == orgId;

  @override
  int get hashCode => Object.hash(kind, orgId);

  @override
  String toString() => isOrg ? 'org:$orgId' : kind.name;
}

/// The `scope` / `org_id` of the app mode's side (Individual mode → personal, Organization mode → that organization) for
/// a course request that is not a scoped list of its own (analytics, the course form's pickers, favourites, the
/// student home, categories). The server's default without `scope` is the personal account, so Organization mode must
/// say so.
Map<String, dynamic> modeCourseScopeQuery([AppModeController? mode]) {
  final m = mode ?? AppModeController.instance;
  return CourseScope.forMode(isOrg: m.isOrg, orgId: m.currentOrgId).query;
}

/// The server's `has_more` when it sends one (null on an older server: the caller falls back to `total`).
bool? serverHasMore(dynamic body) => body is Map && body['has_more'] is bool ? body['has_more'] as bool : null;

/// The organization a course belongs to.
class CourseOrg {
  const CourseOrg({required this.id, this.nameAr, this.nameEn, this.logoUrl, this.color, this.path});

  final int id;
  final String? nameAr, nameEn, logoUrl, color, path;

  static CourseOrg? fromJson(dynamic j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! num) return null;
    String? s(String k) => j[k] is String && (j[k] as String).trim().isNotEmpty ? j[k] as String : null;
    return CourseOrg(
      id: id.toInt(),
      nameAr: s('name_ar'),
      nameEn: s('name_en'),
      logoUrl: s('logo_url'),
      color: s('color'),
      path: s('path'),
    );
  }

  String get name => (AppConfig.lang == 'ar' ? (nameAr ?? nameEn) : (nameEn ?? nameAr)) ?? '#$id';

  /// The organization itself or one of its sub-organizations ("/1/4/9/" is within 1, 4 and 9).
  bool within(int orgId) => id == orgId || (path ?? '').contains('/$orgId/');

  /// The brand colour as ARGB, or null ("#RRGGBB" / "#AARRGGBB").
  int? get argb {
    final hex = (color ?? '').replaceFirst('#', '');
    final v = int.tryParse(hex, radix: 16);
    if (v == null) return null;
    if (hex.length == 6) return 0xFF000000 | v;
    if (hex.length == 8) return v;
    return null;
  }
}

/// One row of `scopes`: how many courses live on one side.
class CourseScopeCount {
  const CourseScopeCount({required this.scope, required this.count, this.org});

  final CourseScope scope;
  final int count;
  final CourseOrg? org;
}

/// `scopes` of a first page; empty for an older server (or an unreadable value).
List<CourseScopeCount> parseCourseScopes(dynamic body) {
  final raw = body is Map ? body['scopes'] : null;
  if (raw is! List) return const [];
  final out = <CourseScopeCount>[];
  for (final r in raw) {
    if (r is! Map) continue;
    final count = r['count'] is num ? (r['count'] as num).toInt() : 0;
    if (r['kind'] == 'personal') {
      out.add(CourseScopeCount(scope: CourseScope.personal, count: count));
    } else if (r['kind'] == 'org') {
      final org = CourseOrg.fromJson(r['org']);
      if (org != null) out.add(CourseScopeCount(scope: CourseScope.org(org.id), count: count, org: org));
    }
  }
  return out;
}

/// Did the server apply the scope? An older server ignores the query and echoes nothing: its list is everything.
bool serverScoped(dynamic body) => body is Map && body['scope'] is String;

/// How many courses [scope] holds according to [counts] (an organization adds its sub-organizations' rows).
int countFor(List<CourseScopeCount> counts, CourseScope scope) => switch (scope.kind) {
      CourseScopeKind.all => counts.fold(0, (s, c) => s + c.count),
      CourseScopeKind.personal => counts.where((c) => c.scope.isPersonal).fold(0, (s, c) => s + c.count),
      CourseScopeKind.org =>
        counts.where((c) => c.org != null && c.org!.within(scope.orgId!)).fold(0, (s, c) => s + c.count),
    };

/// The organizations that hold courses of [counts] (count > 0), the largest first — where "+N in your
/// organizations" leads from the personal list.
List<CourseScopeCount> orgsHoldingCourses(List<CourseScopeCount> counts) =>
    [for (final c in counts) if (c.scope.isOrg && c.org != null && c.count > 0) c]..sort((a, b) => b.count.compareTo(a.count));

/// The organization [orgId] as best known: from `scopes`, else from the mode's membership entry
/// (`{organization: {...}}` of GET /org/public/me/overview), else a bare id.
CourseOrg courseOrgFor(int orgId, List<CourseScopeCount> counts, [Map? modeEntry]) {
  for (final c in counts) {
    if (c.org?.id == orgId) return c.org!;
  }
  final o = CourseOrg.fromJson(modeEntry?['organization']);
  return o != null && o.id == orgId ? o : CourseOrg(id: orgId);
}

/// One chip of the student's switcher.
class CourseScopeChip {
  const CourseScopeChip({required this.scope, required this.count, this.org});

  final CourseScope scope;
  final int count;
  final CourseOrg? org; // null for "All" and "Personal"
}

/// The chips a student sees, in order: All (only when courses live on more than one side) · Personal ·
/// each organization by size. A side with no course is left out — except the selected one and the mode's
/// organization ([modeOrg]: the person is in Organization mode there, so its chip is shown even at 0, and an
/// organization whose courses all sit in sub-organizations gets one chip that counts them).
List<CourseScopeChip> courseScopeChips(
  List<CourseScopeCount> counts, {
  CourseScope? selected,
  CourseOrg? modeOrg,
}) {
  final personal = countFor(counts, CourseScope.personal);
  final orgRows = counts.where((c) => c.scope.isOrg && c.count > 0).toList()
    ..sort((a, b) => b.count.compareTo(a.count));
  final sides = (personal > 0 ? 1 : 0) + orgRows.length;
  final chips = <CourseScopeChip>[
    if (sides > 1 || (selected?.isAll ?? false)) CourseScopeChip(scope: CourseScope.all, count: countFor(counts, CourseScope.all)),
    if (personal > 0 || (selected?.isPersonal ?? false)) CourseScopeChip(scope: CourseScope.personal, count: personal),
  ];
  if (modeOrg != null) {
    // the mode's organization stands for its whole subtree: its sub-organizations' rows fold into it
    chips.add(CourseScopeChip(scope: CourseScope.org(modeOrg.id), count: countFor(counts, CourseScope.org(modeOrg.id)), org: modeOrg));
  }
  for (final r in orgRows) {
    if (modeOrg != null && r.org!.within(modeOrg.id)) continue;
    chips.add(CourseScopeChip(scope: r.scope, count: r.count, org: r.org));
  }
  if (selected != null && selected.isOrg && !chips.any((c) => c.scope == selected)) {
    chips.add(CourseScopeChip(scope: selected, count: countFor(counts, selected)));
  }
  return chips;
}

/// The side a student's list opens on: the mode's side ([modeScope]) unless the person picked one. In the personal
/// account with no personal course while organizations hold some, "All" — an empty page would hide courses the
/// person has. Organization mode stays on its organization even when empty (that page is about it).
CourseScope smartStudentScope(CourseScope modeScope, List<CourseScopeCount> counts, {CourseScope? picked}) {
  if (picked != null) return picked;
  if (modeScope.isPersonal && counts.isNotEmpty &&
      countFor(counts, CourseScope.personal) == 0 && countFor(counts, CourseScope.all) > 0) {
    return CourseScope.all;
  }
  return modeScope;
}
