// lib/features/org/org_dashboard_model.dart
//
// The org-admin home and the department dashboard, each from ONE payload — pure models, no widgets
// (test/org/org_dashboard_model_test.dart):
//   OrgHomeData.fromJson(GET /org/orgs/{id}/dashboard)    kpis · members · pending_total · attention · series →
//                                                          trends (7-day sum, delta vs the week before, 30-point
//                                                          spark) · departments · programs · recent_activity
//   OrgUnitData.fromJson(GET …/units/{t}/{id}/dashboard)   unit · manager · can · stats (null = may not see it) ·
//                                                          waiting · the preview lists · trends when a server adds
//                                                          `series`
//   orgAttentionText(item)                                  attention key → icon, title, subtitle, action label
// An older server without `members` / `series` → `members == null` and `trends` empty: the tiles simply hide.
// D-103 adds access · member_role · layout · can_insights · tasks (+ tasks_total) · departments[].tabs; without them
// `tasks == null` (Home draws the attention cards) and `layout` is empty (orgHomeOrder decides from the role).
// D-1081 adds `home_stats` (OrgHomeStats: the soft-wash home's four counts and their 8-week bars); null on an older
// server → the home keeps its earlier figures.
library;

import 'package:flutter_education_app/core/plural.dart' show countText;
import 'package:flutter/material.dart' show IconData, Icons;

import '../admin/admin_common.dart' show t;
import 'home/org_home_logic.dart' show OrgTask;
import 'org_schedule_autopilot.dart' show TermNeed;

int _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0);
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : const {};
/// The server's naive-UTC ISO time (no zone suffix) → a UTC instant; DateTime.tryParse alone reads it as local.
DateTime? _utc(dynamic v) {
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty) return null;
  final zoned = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(zoned ? s : '${s}Z')?.toUtc();
}

List<Map<String, dynamic>> _list(dynamic v) => v is List ? [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : const [];

// ─────────────────────────────────────────────────────────────────────────────
//  Trends
// ─────────────────────────────────────────────────────────────────────────────

/// One number and its trend: the sum of the last [window] days, the change against the [window] days before
/// (null when there is no previous window or it was empty — a rise from nothing has no percentage) and the
/// daily values for a sparkline.
class OrgTrend {
  const OrgTrend({required this.key, required this.value, required this.delta, required this.spark});

  final String key;
  final int value;
  final double? delta;
  final List<double> spark;

  static OrgTrend of(String key, List<int> daily, {int window = 7}) {
    final n = daily.length;
    final cur = daily.sublist(n - (n < window ? n : window)).fold<int>(0, (a, b) => a + b);
    double? delta;
    if (n >= window * 2) {
      final prev = daily.sublist(n - window * 2, n - window).fold<int>(0, (a, b) => a + b);
      if (prev > 0) delta = (cur - prev) * 100 / prev;
    }
    return OrgTrend(key: key, value: cur, delta: delta, spark: [for (final v in daily) v.toDouble()]);
  }
}

/// One day of the organization's `series` (oldest first, `YYYY-MM-DD`).
class OrgSeriesRow {
  const OrgSeriesRow(this.date, this.values);
  final String date;

  /// Every numeric column except `date` (joins · attendance · complaints · work_items on the org; whatever a
  /// unit's server sends).
  final Map<String, int> values;

  static OrgSeriesRow? fromJson(dynamic v) {
    if (v is! Map) return null;
    final vals = <String, int>{};
    for (final e in v.entries) {
      if ('${e.key}' == 'date') continue;
      if (e.value is num || int.tryParse('${e.value}') != null) vals['${e.key}'] = _int(e.value);
    }
    return OrgSeriesRow('${v['date'] ?? ''}', vals);
  }

  static List<OrgSeriesRow>? listFrom(dynamic v) {
    if (v is! List) return null;
    return [for (final x in v) ?OrgSeriesRow.fromJson(x)];
  }
}

List<OrgTrend> _trendsOf(List<OrgSeriesRow>? series, List<String> keys) {
  if (series == null || series.length < 2) return const [];
  return [
    for (final k in keys)
      if (series.any((r) => r.values.containsKey(k))) OrgTrend.of(k, [for (final r in series) r.values[k] ?? 0]),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
//  Organization home
// ─────────────────────────────────────────────────────────────────────────────

class OrgMembers {
  const OrgMembers({required this.students, required this.teachers, required this.staff, required this.pendingJoin});
  final int students, teachers, staff, pendingJoin;

  static OrgMembers? fromJson(dynamic v) => v is Map
      ? OrgMembers(
          students: _int(v['students']),
          teachers: _int(v['teachers']),
          staff: _int(v['staff']),
          pendingJoin: _int(v['pending_join']))
      : null;
}

/// One `attention[]` item; [raw] keeps the extras (overdue, schedules, terms, items, days …).
class OrgAttentionItem {
  OrgAttentionItem(this.raw)
      : key = '${raw['key'] ?? ''}',
        count = _int(raw['count']),
        severity = '${raw['severity'] ?? 'info'}';

  final Map<String, dynamic> raw;
  final String key, severity;
  final int count;

  int get overdue => _int(raw['overdue']);
  int get days => _int(raw['days']);
  List<Map<String, dynamic>> get items => _list(raw['items']);
  List<Map<String, dynamic>> get schedules => _list(raw['schedules']);
  List<TermNeed> get terms => _list(raw['terms']).map(TermNeed.of).toList();
}

/// The soft-wash home's four counts (D-1081, `home_stats`): votes waiting, open requests (overdue), the members of the
/// departments I see, my next council session; each count with its last 8 weeks, oldest first.
class OrgHomeStats {
  const OrgHomeStats({
    required this.votesWaiting,
    required this.requestsOpen,
    required this.requestsOverdue,
    required this.members,
    required this.votesWeeks,
    required this.requestsWeeks,
    required this.membersWeeks,
    this.nextSessionId,
    this.nextSessionTitle,
    this.nextSessionAt,
    this.nextSessionCouncilAr,
    this.nextSessionCouncilEn,
  });

  final int votesWaiting, requestsOpen, requestsOverdue, members;
  final List<int> votesWeeks, requestsWeeks, membersWeeks;
  final int? nextSessionId;
  final String? nextSessionTitle, nextSessionCouncilAr, nextSessionCouncilEn;
  final DateTime? nextSessionAt;

  static List<int> _weeks(dynamic v) => v is List ? [for (final x in v) _int(x)] : const [];

  static OrgHomeStats? fromJson(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final n = _map(m['next_session']);
    String? text(dynamic x) => x == null || '$x'.trim().isEmpty ? null : '$x';
    return OrgHomeStats(
      votesWaiting: _int(m['votes_waiting']),
      requestsOpen: _int(m['requests_open']),
      requestsOverdue: _int(m['requests_overdue']),
      members: _int(m['members']),
      votesWeeks: _weeks(m['votes_weeks']),
      requestsWeeks: _weeks(m['requests_weeks']),
      membersWeeks: _weeks(m['members_weeks']),
      nextSessionId: n.isEmpty ? null : _int(n['id']),
      nextSessionTitle: text(n['title']),
      nextSessionAt: _utc(n['at']),
      nextSessionCouncilAr: text(n['council_ar']),
      nextSessionCouncilEn: text(n['council_en']),
    );
  }

  /// The council's name in the reader's language (the other one when it is missing).
  String? get nextSessionCouncil {
    final ar = nextSessionCouncilAr ?? nextSessionCouncilEn, en = nextSessionCouncilEn ?? nextSessionCouncilAr;
    return ar == null || en == null ? null : t(ar, en);
  }
}

/// The org-admin home: everything `GET …/dashboard` answers, typed once.
class OrgHomeData {
  const OrgHomeData({
    required this.raw,
    required this.organization,
    required this.myRole,
    required this.kpis,
    required this.members,
    required this.pendingTotal,
    required this.attention,
    required this.series,
    required this.departments,
    required this.programs,
    required this.recentActivity,
    required this.generatedAt,
    this.access = '',
    this.memberRole,
    this.layout = '',
    this.canInsights = false,
    this.canFacultyOverview = false,
    this.tasks,
    this.tasksTotal = 0,
    this.homeStats,
  });

  /// D-1081: the soft-wash home's counts; null on an older server.
  final OrgHomeStats? homeStats;

  static const trendKeys = ['joins', 'attendance', 'complaints'];

  /// D-103 (an older server: empty / null / false): admin · staff · member.
  final String access;
  final String? memberRole;

  /// insights_first · actions_first (empty = the app decides from the role, orgHomeOrder).
  final String layout;
  final bool canInsights;

  /// D-979: the home's Faculty overview card (the dean, vice deans and org admin of an institution; absent = false).
  final bool canFacultyOverview;

  /// "Needs your attention" (the first 8, urgency first); null on an older server → the attention cards.
  final List<OrgTask>? tasks;
  final int tasksTotal;

  /// An organization admin (the server's `access`, else `my_role`).
  bool get isAdmin => access.isNotEmpty ? access == 'admin' : const ['org_admin', 'platform_admin'].contains(myRole);

  final Map<String, dynamic> raw;
  final Map<String, dynamic> organization;
  final String myRole;
  final Map<String, int> kpis;

  /// null on an older server: the hero shows the kpis' figures instead.
  final OrgMembers? members;

  /// `pending_total` (an older server: `attention_total`, else the sum of the items).
  final int pendingTotal;
  final List<OrgAttentionItem> attention;

  /// null on an older server: no trend tiles.
  final List<OrgSeriesRow>? series;
  final List<Map<String, dynamic>> departments, programs, recentActivity;
  final DateTime? generatedAt;

  static OrgHomeData? fromJson(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final attention = [for (final a in _list(m['attention'])) OrgAttentionItem(a)];
    final sum = attention.fold<int>(0, (n, a) => n + a.count);
    return OrgHomeData(
      raw: m,
      organization: _map(m['organization']),
      myRole: '${m['my_role'] ?? ''}',
      kpis: {for (final e in _map(m['kpis']).entries) e.key: _int(e.value)},
      members: OrgMembers.fromJson(m['members']),
      pendingTotal: m['pending_total'] != null ? _int(m['pending_total']) : (m['attention_total'] != null ? _int(m['attention_total']) : sum),
      attention: attention,
      series: OrgSeriesRow.listFrom(m['series']),
      departments: _list(m['departments']),
      programs: _list(m['programs']),
      recentActivity: _list(m['recent_activity']),
      generatedAt: _utc(m['generated_at']),
      access: '${m['access'] ?? ''}',
      memberRole: m['member_role'] == null ? null : '${m['member_role']}',
      layout: '${m['layout'] ?? ''}',
      canInsights: m['can_insights'] == true,
      canFacultyOverview: m['can_faculty_overview'] == true,
      tasks: OrgTask.listFrom(m['tasks']),
      tasksTotal: m['tasks_total'] != null ? _int(m['tasks_total']) : (m['tasks'] is List ? (m['tasks'] as List).length : 0),
      homeStats: OrgHomeStats.fromJson(m['home_stats']),
    );
  }

  static final empty = OrgHomeData.fromJson(const <String, dynamic>{})!;

  int kpi(String key) => kpis[key] ?? 0;

  OrgAttentionItem? attentionOf(String key) {
    for (final a in attention) {
      if (a.key == key) return a;
    }
    return null;
  }

  int count(String key) => attentionOf(key)?.count ?? 0;

  /// The attention cards Home still draws: all of them on an older server; beside `tasks`, only the
  /// organization-wide alerts the tasks do not carry (a term without a timetable, memberships ending …).
  List<OrgAttentionItem> get alerts =>
      tasks == null ? attention : [for (final a in attention) if (!orgAttentionCoveredByTasks.contains(a.key)) a];

  bool get hasTrends => series != null && series!.length >= 2;

  /// joins · attendance · complaints (empty without `series`).
  List<OrgTrend> get trends => _trendsOf(series, trendKeys);

  OrgTrend? trend(String key) {
    for (final x in trends) {
      if (x.key == key) return x;
    }
    return null;
  }

  /// My departments (service) then academic departments — what the units strip shows.
  List<Map<String, dynamic>> get units => [...departments, ...programs];

  /// The hero's four figures: members when the server sends them, else the kpis (older server).
  (int students, int teachers, int staff, int? pendingJoin) get figures => members != null
      ? (members!.students, members!.teachers, members!.staff, members!.pendingJoin)
      : (kpi('students'), kpi('teachers'), kpi('staff'), null);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Attention texts
// ─────────────────────────────────────────────────────────────────────────────

/// Attention keys whose items arrive one by one as `tasks` on a D-103 server (drawn there, never twice).
const orgAttentionCoveredByTasks = {'org_join_requests', 'unit_join_requests', 'program_choices', 'pending_forms', 'open_complaints'};

class OrgAttentionText {
  const OrgAttentionText(this.icon, this.title, this.subtitle, this.action);
  final IconData icon;
  final String title, subtitle, action;
}

/// What an attention item says and which verb its button carries. Null for a key this app version does not know
/// (the card is skipped; the count still lives in `pending_total`).
OrgAttentionText? orgAttentionText(OrgAttentionItem a) {
  final n = a.count;
  return switch (a.key) {
    'org_join_requests' => OrgAttentionText(Icons.person_add_alt_1_rounded, countText(n, ar1: 'شخص واحد يطلب الانضمام للمؤسسة', ar2: 'شخصان يطلبان الانضمام للمؤسسة', arFew: '{n} أشخاص يطلبون الانضمام للمؤسسة', arMany: '{n} شخصًا يطلبون الانضمام للمؤسسة', en1: '1 person asked to join', en: '{n} people asked to join'),
        t('راجعهم واقبل من يخصّك', 'Review and let the right people in'), t('مراجعة', 'Review')),
    'unit_join_requests' => OrgAttentionText(Icons.how_to_reg_rounded, t('$n طلب انضمام لأقسامك', '$n department join requests'),
        t('قرارك ينتظره الطلاب', 'Students are waiting for your decision'), t('مراجعة', 'Review')),
    'program_choices' => OrgAttentionText(Icons.how_to_vote_rounded, t('$n طالب اختار قسمه العلمي', '$n students chose their department'),
        t('وافق أو اعتذر من الهيكل الأكاديمي', 'Approve or decline in Academic structure'), t('فتح', 'Open')),
    'pending_forms' => OrgAttentionText(Icons.assignment_late_rounded, t('$n طلب ينتظر المراجعة', '$n requests to review'),
        t('نماذج أرسلها الطلاب والموظفون', 'Forms sent by students and staff'), t('مراجعة', 'Review')),
    'open_complaints' => OrgAttentionText(
        Icons.support_agent_rounded,
        t('$n شكوى مفتوحة', '$n open complaints'),
        a.overdue > 0
            ? t('${a.overdue} تجاوزت مهلة الرد — ابدأ بها', '${a.overdue} are past their reply time — start there')
            : t('كلها ضمن مهلة الرد', 'All within their reply time'),
        t('الرد', 'Reply')),
    'schedule_unplaced' => OrgAttentionText(Icons.event_busy_rounded, t('$n حصة بلا موعد في الجداول', '$n sessions still without a slot'),
        a.schedules.map((x) => '${x['name']}').take(2).join(' · '), t('فتح الجدول', 'Open timetable')),
    'schedule_suggestions' => OrgAttentionText(Icons.auto_fix_high_rounded, t('$n اقتراح لتحسين الجداول', '$n timetable suggestions'),
        t('مقترحات جاهزة للتطبيق بضغطة', 'Ready to apply in one tap'), t('عرض', 'View')),
    'term_without_timetable' => OrgAttentionText(
        Icons.auto_awesome_rounded,
        n == 1 ? t('فصل دراسي بلا جدول', 'A term has no timetable yet') : t('$n فصول دراسية بلا جدول', '$n terms have no timetable yet'),
        a.terms.map((x) => x.ready ? x.label : '${x.label} (${x.blockedTexts.join('، ')})').join(' · '),
        t('ولّد الآن', 'Generate now')),
    'expiring_memberships' => OrgAttentionText(Icons.hourglass_bottom_rounded,
        t('$n عضوية تنتهي خلال ${a.days} يوماً', '$n memberships end within ${a.days} days'),
        t('مدّدها قبل أن يفقد أصحابها الوصول', 'Extend them before people lose access'), t('تمديد', 'Extend')),
    'pending_sub_orgs' => OrgAttentionText(Icons.account_tree_rounded, t('$n مؤسسة فرعية قيد المراجعة', '$n sub-organizations in review'),
        t('بانتظار اعتماد إدارة المنصة', 'Waiting for the platform team'), t('عرض', 'View')),
    _ => null,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
//  Department dashboard
// ─────────────────────────────────────────────────────────────────────────────

/// One department (service `dept` or academic `program`): `GET …/units/{type}/{id}/dashboard`, typed once.
class OrgUnitData {
  const OrgUnitData({
    required this.raw,
    required this.unit,
    required this.manager,
    required this.can,
    required this.stats,
    required this.features,
    required this.joinPolicy,
    required this.requests,
    required this.forms,
    required this.programChoices,
    required this.users,
    required this.team,
    required this.subUnits,
    required this.series,
  });

  final Map<String, dynamic> raw;
  final Map<String, dynamic> unit, manager, joinPolicy;
  final Map<String, bool> can;

  /// A stat the caller may not see is null (its preview list is empty).
  final Map<String, int?> stats;
  final List<String> features;
  final List<Map<String, dynamic>> requests, forms, programChoices, users, team, subUnits;

  /// Absent today; the hero adds trend tiles the day a server sends it.
  final List<OrgSeriesRow>? series;

  static OrgUnitData? fromJson(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final st = _map(m['stats']);
    return OrgUnitData(
      raw: m,
      unit: _map(m['unit']),
      manager: _map(m['manager']),
      can: {for (final e in _map(m['can']).entries) e.key: e.value == true},
      stats: {for (final e in st.entries) e.key: e.value == null ? null : _int(e.value)},
      features: m['features'] is List ? [for (final f in m['features'] as List) '$f'] : const [],
      joinPolicy: _map(m['join_policy']),
      requests: _list(m['requests']),
      forms: _list(m['forms']),
      programChoices: _list(m['program_choices']),
      users: _list(m['users']),
      team: _list(m['team']),
      subUnits: _list(m['sub_units']),
      series: OrgSeriesRow.listFrom(m['series']),
    );
  }

  bool get isDept => unit['unit_type'] == 'dept';
  bool cap(String key) => can[key] == true;

  /// 0 when hidden (null) — the hero never shows "null".
  int stat(String key) => stats[key] ?? 0;
  bool hidden(String key) => stats.containsKey(key) && stats[key] == null;

  int get waiting => stat('pending_join_requests') + stat('pending_forms') + stat('pending_program_choices');

  /// Every numeric column of `series`, in the server's order.
  List<OrgTrend> get trends {
    final s = series;
    if (s == null || s.length < 2) return const [];
    final keys = <String>[];
    for (final r in s) {
      for (final k in r.values.keys) {
        if (!keys.contains(k)) keys.add(k);
      }
    }
    return _trendsOf(s, keys);
  }
}
